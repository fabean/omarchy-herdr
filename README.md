# Herdr for Omarchy

An Omarchy bar widget for monitoring [Herdr](https://herdr.dev) agents. It shows active or blocked agent counts in the bar and opens a detailed, keyboard-accessible panel with the status of every agent.

![Herdr agent activity panel in the Omarchy bar](preview.png)

## Requirements

- Omarchy with the Quattro shell plugin system
- [Herdr](https://herdr.dev)'s `herdr-core` (or `hc`) available on `PATH`, with its server running; the legacy `herdr` CLI is also supported
- `herdr-app` (previously `herdr-gui`) for focusing core agents in the desktop GUI
- `jq`
- GNU coreutils (`timeout`)
- OpenSSH when remote hosts are configured
- An Omarchy-compatible Nerd Font for the status icons

The plugin polls `herdr-core ls --json` every three seconds, including agents on machines registered with core. Terminals without an agent status (such as ordinary shells) and finished terminals are excluded. Blocked agents and errors receive the urgent indicator.

If core is unavailable, the plugin falls back to `herdr agent list` and the SSH targets listed in `remote-hosts`. SSH polling uses batch mode and short timeouts, so an offline host or one that needs a password cannot stall the bar. A successful core response, including an empty agent list, takes precedence over the legacy server. Polling does not start a stopped core server.

## Install

Review the source before installing. Omarchy plugins run as unsandboxed code inside the long-running shell process.

```bash
omarchy plugin add https://github.com/fabean/omarchy-herdr.git --enable
```

The widget is placed in the right bar section by default. If it was installed without `--enable`, enable it later:

```bash
omarchy plugin enable io.github.fabean.herdr --section right
```

## Use

- Left-click the widget to open or close the agent panel.
- Click an agent to show it in Herdr, including remote agents and sub-agents. The plugin raises the desktop GUI and opens it when needed. Legacy agents still focus or open the terminal-based Herdr client.
- Right-click the widget to refresh immediately.
- In the panel, press `R` or `Enter` to refresh and `Escape` to close.
- When Herdr is unavailable, the widget displays an offline indicator.

## Remote hosts

With herdr-core, use `hc machine add <target>` to register remote machines. The widget discovers these automatically and focuses their agents in the local GUI. No `remote-hosts` file is needed for core; that file is used only by the legacy fallback.

For the legacy Herdr server, add one SSH target per line to `remote-hosts` in the installed plugin directory. Targets may be hostnames, `user@host` values, or aliases from `~/.ssh/config`.

```text
# ~/.config/omarchy/plugins/io.github.fabean.herdr/remote-hosts
Hitmonlee
user@192.0.2.10
```

Set up key-based SSH authentication first. The widget never opens an SSH password prompt.

When at least one core machine or legacy remote host is configured, agent names are prefixed with their source, such as `local: api` or `Hitmonlee: worker`. Without remote hosts, local agent names are shown without a prefix.

## Update

```bash
omarchy plugin update io.github.fabean.herdr
```

## Remove

```bash
omarchy plugin remove io.github.fabean.herdr
```

Removal deletes only the plugin checkout and removes the widget from the Omarchy bar configuration. It does not remove Herdr or its data.

## Develop

Run the compatibility tests (Python 3, Bash, and `jq`):

```bash
python -m unittest discover -s tests -v
```

Validate the plugin against the installed Omarchy manifest schema:

```bash
omarchy plugin validate .
```

For local testing, install from a local Git remote or copy the repository into `~/.config/omarchy/plugins/io.github.fabean.herdr` and rescan plugins.

## License

[MIT](LICENSE)
