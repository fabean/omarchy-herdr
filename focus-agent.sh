#!/usr/bin/env bash

set -u
host="${1-}"
session="${2-}"
pane="${3-}"
backend="${4-herdr}"

focus_window() {
  local address="$1" workspace="$2"
  [[ $workspace =~ ^(special:)?[A-Za-z0-9_-]{1,32}$ ]] && hyprctl dispatch "hl.dsp.focus({ workspace = '$workspace' })" >/dev/null 2>&1
  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] && hyprctl dispatch "hl.dsp.focus({ window = 'address:$address' })" >/dev/null 2>&1
}

if [[ $backend == core ]]; then
  [[ $pane =~ ^([A-Za-z0-9][A-Za-z0-9._-]{0,63}/)*t[0-9a-z]+$ ]] || exit 2
  gui=""
  for candidate in herdr-app herdr-gui; do
    if command -v "$candidate" >/dev/null 2>&1; then gui="$candidate"; break; fi
  done
  [[ -n $gui ]] || exit 1

  # agent.focus also reveals sub-agents that do not have their own pane.
  if ! timeout 2s "$gui" do agent.focus --terminal "$pane" >/dev/null 2>&1; then
    # A running GUI may reject a stale address; opening another window cannot fix it.
    timeout 1s "$gui" status >/dev/null 2>&1 && exit 1
    setsid "$gui" </dev/null >/dev/null 2>&1 &
    focused=false
    for (( attempt=0; attempt<20; attempt++ )); do
      if timeout 0.5s "$gui" do agent.focus --terminal "$pane" >/dev/null 2>&1; then
        focused=true
        break
      fi
      sleep 0.1
    done
    [[ $focused == true ]] || exit 1
  fi

  if command -v hyprctl >/dev/null 2>&1; then
    while IFS=$'\t' read -r address workspace; do
      focus_window "$address" "$workspace"
      break
    done < <(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "herdr-app" or .class == "herdr-gui") | [.address, .workspace.name] | @tsv')
  fi
  exit 0
fi

[[ $backend == herdr ]] || exit 2

[[ $host =~ ^[A-Za-z0-9_.@:-]*$ ]] || exit 2
[[ $session =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || exit 2
[[ $pane =~ ^[A-Za-z0-9_-]{1,32}:[A-Za-z0-9_-]{1,32}$ ]] || exit 2

remote_targets=()
if [[ -n $host ]]; then
  remote_targets+=("$host")
  resolved_host="$(ssh -G -- "$host" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')"
  [[ -n $resolved_host ]] && remote_targets+=("$resolved_host")
  if [[ -n $resolved_host ]]; then
    while IFS= read -r address; do
      [[ -n $address ]] && remote_targets+=("$address")
    done < <(getent ahosts "$resolved_host" 2>/dev/null | awk '{ print $1 }' | sort -u)
  fi
fi

if [[ -z $host ]]; then
  if [[ $session == default ]]; then
    herdr agent focus "$pane" >/dev/null 2>&1 || true
  else
    herdr --session "$session" agent focus "$pane" >/dev/null 2>&1 || true
  fi
else
  remote_command=(herdr)
  [[ $session == default ]] || remote_command+=(--session "$session")
  remote_command+=(agent focus "$pane")
  timeout 3s ssh -o BatchMode=yes -o ConnectTimeout=2 -o ConnectionAttempts=1 -- "$host" "${remote_command[@]}" >/dev/null 2>&1 || true
fi

if command -v hyprctl >/dev/null 2>&1; then
  declare -A address_of_pid=() workspace_of_pid=()
  while IFS=$'\t' read -r window_pid address workspace; do
    [[ $window_pid =~ ^[0-9]+$ ]] || continue
    address_of_pid[$window_pid]="$address"
    workspace_of_pid[$window_pid]="$workspace"
  done < <(hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.pid > 0) | [.pid, .address, .workspace.name] | @tsv')

  while read -r client_pid command_line; do
    [[ $client_pid =~ ^[0-9]+$ ]] || continue
    matches=false
    if [[ -z $host ]]; then
      [[ $command_line =~ (^|/)herdr[[:space:]]*$ ]] && matches=true
    else
      for target in "${remote_targets[@]}"; do
        if [[ $command_line == *"herdr --remote=$target"* || $command_line == *"herdr --remote $target"* ]]; then
          matches=true
          break
        fi
      done
    fi
    [[ $matches == true ]] || continue

    for (( depth=0; depth<32 && client_pid>1; depth++ )); do
      if [[ -n ${address_of_pid[$client_pid]-} ]]; then
        address="${address_of_pid[$client_pid]}"
        workspace="${workspace_of_pid[$client_pid]}"
        focus_window "$address" "$workspace"
        exit 0
      fi
      stat_line="$(<"/proc/$client_pid/stat")" || break
      stat_rest="${stat_line#*") "}"
      read -r _ client_pid _ <<< "$stat_rest"
    done
  done < <(ps -eo pid=,args= 2>/dev/null | grep -E 'her[d]r')
fi

herdr_command=(herdr)
[[ -n $host ]] && herdr_command+=(--remote "$host")
[[ $session == default ]] || herdr_command+=(--session "$session")
if command -v foot >/dev/null 2>&1; then
  setsid foot --app-id=herdr -e "${herdr_command[@]}" >/dev/null 2>&1 &
elif command -v xdg-terminal-exec >/dev/null 2>&1; then
  setsid xdg-terminal-exec -- "${herdr_command[@]}" >/dev/null 2>&1 &
fi
