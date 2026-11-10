#!/usr/bin/env bash

set -u

plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
hosts_file="$plugin_dir/remote-hosts"
work_dir="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$work_dir"' EXIT

collect_legacy() {
  local host="$1" output_file="$2" response
  if [[ -z $host ]]; then
    response="$(timeout 2s herdr agent list 2>/dev/null)" || return
  else
    response="$(timeout 3s ssh -o BatchMode=yes -o ConnectTimeout=2 -o ConnectionAttempts=1 -- "$host" herdr agent list 2>/dev/null)" || return
  fi
  jq -ce --arg host "$host" '.result.agents | select(type == "array") | map({
    name: (.name // ((.cwd // "") | rtrimstr("/") | split("/") | last) // .pane_id // "Agent"),
    status: (.agent_status // "unknown"), paneId: (.pane_id // ""),
    cwd: (.cwd // ""), host: $host, session: "default", backend: "herdr"
  })' <<< "$response" > "$output_file" 2>/dev/null || { rm -f -- "$output_file"; return 1; }
  touch "$output_file.online"
}

collect_core() {
  local core response
  for core in herdr-core hc; do
    command -v "$core" >/dev/null 2>&1 || continue
    # ls starts a server on demand; polling must leave a stopped core stopped.
    timeout 1s "$core" server status --json >/dev/null 2>&1 || continue
    response="$(timeout 2s "$core" ls --json 2>/dev/null)" || continue
    jq -ce '
      .terminals | select(type == "array") | map(
        select((.state // "live") == "live") |
        (.status | if type == "object" then .state else . end) as $status |
        select(($status | type) == "string" and $status != "") |
        select((.address | type) == "string" and .address != "") |
        (.foreground.cwd // .cwd // "") as $cwd |
        {
          name: (.name // .where // (if $cwd != "" then ($cwd | rtrimstr("/") | split("/") | last) else .address end)),
          status: $status, terminalId: .address, paneId: "", cwd: $cwd,
          host: (.address | split("/") | .[0:-1] | join("/")),
          session: "default", backend: "core"
        }
      )' <<< "$response" > "$work_dir/core.json" 2>/dev/null || { rm -f -- "$work_dir/core.json"; continue; }
    remote_enabled="$(jq -r --slurpfile agents "$work_dir/core.json" '
      (if (.machines | type) == "array" then (.machines | length > 0) else false end)
      or any($agents[0][]; .host != "")' <<< "$response")"
    touch "$work_dir/core.json.online"
    return 0
  done
  return 1
}

remote_enabled=false
# Core already aggregates its registered machines. Do not mix in the old server's
# stale agents or poll those machines a second time through remote-hosts.
if ! collect_core; then
  collect_legacy "" "$work_dir/local.json" &
  local_pid=$!
  remote_pids=()
  host_index=0
  if [[ -r $hosts_file ]]; then
    while IFS= read -r host || [[ -n $host ]]; do
      host="${host%%#*}"
      host="${host//[[:space:]]/}"
      [[ -n $host ]] || continue
      remote_enabled=true
      collect_legacy "$host" "$work_dir/remote-$host_index.json" &
      remote_pids+=("$!")
      host_index=$((host_index + 1))
    done < "$hosts_file"
  fi
  wait "$local_pid" 2>/dev/null || true
  for pid in "${remote_pids[@]}"; do wait "$pid" 2>/dev/null || true; done
fi

any_online=false
compgen -G "$work_dir/*.online" >/dev/null && any_online=true
mapfile -t result_files < <(find "$work_dir" -maxdepth 1 -type f -name '*.json' -print)
if (( ${#result_files[@]} == 0 )); then agents='[]'; else agents="$(jq -cs 'add // []' "${result_files[@]}")"; fi

jq -cn --argjson online "$any_online" --argjson remoteEnabled "$remote_enabled" --argjson agents "$agents" '
  def rank: if .status == "blocked" or .status == "error" then 0 elif .status == "working" then 1 elif .status == "done" then 2 elif .status == "idle" then 3 else 4 end;
  {online: ($online or ($agents | length > 0)), remoteEnabled: $remoteEnabled,
   total: ($agents | length),
   working: ($agents | map(select(.status == "working")) | length),
   blocked: ($agents | map(select(.status == "blocked")) | length),
   errors: ($agents | map(select(.status == "error")) | length),
   done: ($agents | map(select(.status == "done")) | length),
   idle: ($agents | map(select(.status == "idle")) | length),
   unknown: ($agents | map(select(.status | IN("working", "blocked", "error", "done", "idle") | not)) | length),
   agents: ($agents | sort_by(rank, .host, .cwd))}'
