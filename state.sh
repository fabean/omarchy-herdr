#!/usr/bin/env bash

set -u

plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
hosts_file="$plugin_dir/remote-hosts"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

collect() {
  local host="$1" output_file="$2" response
  if [[ -z $host ]]; then
    response="$(timeout 2s herdr agent list 2>/dev/null)" || return
  else
    response="$(timeout 3s ssh -o BatchMode=yes -o ConnectTimeout=2 -o ConnectionAttempts=1 -- "$host" herdr agent list 2>/dev/null)" || return
  fi
  jq -ce --arg host "$host" '(.result.agents // []) | map({
    name: (.name // ((.cwd // "") | rtrimstr("/") | split("/") | last) // .pane_id // "Agent"),
    status: (.agent_status // "unknown"), paneId: (.pane_id // ""),
    cwd: (.cwd // ""), host: $host, session: "default"
  })' <<< "$response" > "$output_file" 2>/dev/null || return
  touch "$output_file.online"
}

collect "" "$work_dir/local.json" &
local_pid=$!
remote_pids=()
host_index=0
remote_enabled=false
if [[ -r $hosts_file ]]; then
  while IFS= read -r host || [[ -n $host ]]; do
    host="${host%%#*}"
    host="${host//[[:space:]]/}"
    [[ -n $host ]] || continue
    remote_enabled=true
    collect "$host" "$work_dir/remote-$host_index.json" &
    remote_pids+=("$!")
    host_index=$((host_index + 1))
  done < "$hosts_file"
fi
wait "$local_pid" 2>/dev/null || true
for pid in "${remote_pids[@]}"; do wait "$pid" 2>/dev/null || true; done

any_online=false
compgen -G "$work_dir/*.online" >/dev/null && any_online=true
mapfile -t result_files < <(find "$work_dir" -maxdepth 1 -type f -name '*.json' -print)
if (( ${#result_files[@]} == 0 )); then agents='[]'; else agents="$(jq -cs 'add // []' "${result_files[@]}")"; fi

jq -cn --argjson online "$any_online" --argjson remoteEnabled "$remote_enabled" --argjson agents "$agents" '
  def rank: if .status == "blocked" then 0 elif .status == "working" then 1 elif .status == "done" then 2 elif .status == "idle" then 3 else 4 end;
  {online: ($online or ($agents | length > 0)), remoteEnabled: $remoteEnabled,
   total: ($agents | length),
   working: ($agents | map(select(.status == "working")) | length),
   blocked: ($agents | map(select(.status == "blocked")) | length),
   done: ($agents | map(select(.status == "done")) | length),
   idle: ($agents | map(select(.status == "idle")) | length),
   unknown: ($agents | map(select(.status == "unknown")) | length),
   agents: ($agents | sort_by(rank, .host, .cwd))}'
