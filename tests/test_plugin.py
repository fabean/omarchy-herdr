import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
import json, os, pathlib, sys
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
with open(os.environ["MOCK_CALLS"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
if name == "setsid":
    os.execvp(args[0], args)
config = json.loads(pathlib.Path(os.environ["MOCK_CONFIG"]).read_text())
reply = config.get(name + " " + (args[0] if args else ""), config.get(name, {"code": 1}))
marker = pathlib.Path(os.environ["MOCK_CONFIG"] + ".started")
if reply.get("start"):
    marker.touch()
if reply.get("needs_start") and not marker.exists():
    sys.exit(1)
sys.stdout.write(reply.get("stdout", ""))
sys.exit(reply.get("code", 0))
'''


class PluginTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        for name in ("state.sh", "focus-agent.sh"):
            shutil.copy2(ROOT / name, self.directory / name)
        for name in ("herdr-core", "hc", "herdr", "ssh", "herdr-app", "herdr-gui",
                     "hyprctl", "ps", "setsid", "foot", "xdg-terminal-exec"):
            executable = self.bin / name
            executable.write_text(f"#!{sys.executable}\n{MOCK}")
            executable.chmod(0o755)
        self.config = {}
        self.config_path = self.directory / "config.json"
        self.calls_path = self.directory / "calls.jsonl"
        self.env = {**os.environ, "PATH": f"{self.bin}:/usr/bin:/bin",
                    "MOCK_CONFIG": str(self.config_path), "MOCK_CALLS": str(self.calls_path)}

    def reply(self, command, value, **options):
        self.config[command] = {"stdout": json.dumps(value), **options}

    def run_script(self, name, *args):
        self.config_path.write_text(json.dumps(self.config))
        return subprocess.run([str(self.directory / name), *args], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def state(self):
        result = self.run_script("state.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def calls(self):
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()]

    def test_core_aggregates_remote_agents_and_skips_shells_and_finished_terminals(self):
        self.reply("herdr-core", {"terminals": [
            {"address": "t1", "status": "working", "cwd": "/work/api"},
            {"address": "vps/t2", "status": "blocked", "where": "Remote / Review"},
            {"address": "t3", "agent": "fish", "state": "live"},
            {"address": "t4", "status": "done", "state": "finished"},
        ], "machines": [{"name": "vps", "state": "connected"}]})
        (self.directory / "remote-hosts").write_text("vps\n")
        state = self.state()
        self.assertTrue(state["online"])
        self.assertTrue(state["remoteEnabled"])
        self.assertEqual((state["total"], state["working"], state["blocked"]), (2, 1, 1))
        self.assertEqual(state["agents"][0]["terminalId"], "vps/t2")
        self.assertEqual(state["agents"][0]["host"], "vps")
        self.assertEqual(state["agents"][0]["backend"], "core")
        self.assertFalse(any(call[0] in ("ssh", "herdr") for call in self.calls()))

    def test_core_accepts_full_status_records_and_counts_errors_and_unknown_states(self):
        self.reply("herdr-core", {"terminals": [
            {"address": "t1", "status": {"state": "error"}, "name": "<img src='x'>"},
            {"address": "t2", "status": {"state": "idle"}, "cwd": "/old",
             "foreground": {"cwd": "/work/current"}},
            {"address": "t3", "status": "new-status"},
        ]})
        state = self.state()
        self.assertEqual((state["errors"], state["idle"], state["unknown"]), (1, 1, 1))
        self.assertEqual(state["agents"][0]["name"], "<img src='x'>")
        self.assertEqual(state["agents"][1]["cwd"], "/work/current")

    def test_empty_core_is_online_and_does_not_fall_back_to_stale_legacy_server(self):
        self.reply("herdr-core", {"terminals": [], "machines": []})
        state = self.state()
        self.assertTrue(state["online"])
        self.assertEqual(state["total"], 0)
        self.assertEqual(self.calls(), [["herdr-core", "server", "status", "--json"],
                                       ["herdr-core", "ls", "--json"]])

    def test_polling_does_not_start_a_stopped_core(self):
        self.config["herdr-core server"] = {"code": 1}
        self.reply("herdr-core ls", {"terminals": []})
        self.reply("herdr", {"result": {"agents": []}})
        self.assertTrue(self.state()["online"])
        self.assertFalse(any(call[:2] == ["herdr-core", "ls"] for call in self.calls()))

    def test_hc_only_installation(self):
        (self.bin / "herdr-core").unlink()
        # Hide the real herdr-core binary on this development machine.
        self.env["PATH"] = str(self.bin)
        for name in ("bash", "dirname", "mktemp", "timeout", "jq", "touch", "find", "rm"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.reply("hc", {"terminals": [{"address": "t1", "status": "done"}]})
        self.assertEqual(self.state()["done"], 1)

    def test_malformed_core_response_falls_back_to_legacy(self):
        self.reply("herdr-core", {"error": "unavailable"})
        self.reply("herdr", {"result": {"agents": [
            {"pane_id": "tab1:pane2", "agent_status": "working", "cwd": "/work/api"}
        ]}})
        state = self.state()
        self.assertEqual(state["working"], 1)
        self.assertEqual(state["agents"][0]["paneId"], "tab1:pane2")
        self.assertEqual(state["agents"][0]["backend"], "herdr")

    def test_legacy_remote_hosts_and_offline_local(self):
        (self.directory / "remote-hosts").write_text("# comment\n vps # remote\n")
        self.reply("ssh", {"result": {"agents": [{"pane_id": "a:b", "agent_status": "idle"}]}})
        state = self.state()
        self.assertTrue(state["online"])
        self.assertTrue(state["remoteEnabled"])
        self.assertEqual(state["agents"][0]["host"], "vps")
        self.assertIn("BatchMode=yes", next(call for call in self.calls() if call[0] == "ssh"))

    def test_failed_or_invalid_backends_are_offline(self):
        self.config["herdr"] = {"stdout": "not json"}
        state = self.state()
        self.assertFalse(state["online"])
        self.assertEqual(state["agents"], [])

    def test_core_focus_uses_gui_and_raises_its_window(self):
        self.config["herdr-app do"] = {}
        self.reply("hyprctl clients", [
            {"class": "herdr-app", "address": "0x123", "workspace": {"name": "2"}}
        ])
        result = self.run_script("focus-agent.sh", "vps", "default", "vps/t1", "core")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["herdr-app", "do", "agent.focus", "--terminal", "vps/t1"], self.calls())
        self.assertIn(["hyprctl", "dispatch", "hl.dsp.focus({ window = 'address:0x123' })"], self.calls())
        self.assertFalse(any(call[0] in ("herdr", "ssh", "foot") for call in self.calls()))

    def test_core_focus_supports_previous_gui_binary_name(self):
        (self.bin / "herdr-app").unlink()
        self.env["PATH"] = str(self.bin)
        for name in ("bash", "timeout", "jq"):
            (self.bin / name).symlink_to(shutil.which(name))
        self.config["herdr-gui do"] = {}
        self.reply("hyprctl clients", [])
        result = self.run_script("focus-agent.sh", "", "default", "t1", "core")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["herdr-gui", "do", "agent.focus", "--terminal", "t1"], self.calls())

    def test_core_focus_starts_closed_gui_and_retries(self):
        self.config["herdr-app do"] = {"needs_start": True}
        self.config["herdr-app "] = {"start": True}
        self.reply("hyprctl clients", [])
        result = self.run_script("focus-agent.sh", "", "default", "t1", "core")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["setsid", "herdr-app"], self.calls())

    def test_core_focus_failure_does_not_launch_another_running_gui(self):
        self.config["herdr-app status"] = {}
        result = self.run_script("focus-agent.sh", "", "default", "t1", "core")
        self.assertEqual(result.returncode, 1)
        self.assertFalse(any(call[0] == "setsid" for call in self.calls()))

    def test_focus_rejects_invalid_identifiers(self):
        for address in ("--help", "t1;touch /tmp/bad", "../t1", "vps/../../t2"):
            with self.subTest(address=address):
                self.assertEqual(self.run_script("focus-agent.sh", "", "default", address, "core").returncode, 2)
        self.assertFalse(self.calls_path.exists())

    def test_legacy_focus_keeps_original_three_argument_interface(self):
        self.reply("hyprctl clients", [])
        self.config["ps"] = {}
        self.config["herdr"] = {}
        result = self.run_script("focus-agent.sh", "", "default", "tab1:pane2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(["herdr", "agent", "focus", "tab1:pane2"], self.calls())


if __name__ == "__main__":
    unittest.main()
