#!/usr/bin/env bash

if ! response="$(timeout 2s herdr agent list 2>/dev/null)"; then
  jq -cn '{
    online: false,
    total: 0,
    working: 0,
    blocked: 0,
    done: 0,
    idle: 0,
    unknown: 0,
    agents: []
  }'
  exit
fi

jq -c '
  (.result.agents // []) as $agents
  | {
      online: true,
      total: ($agents | length),
      working: ($agents | map(select(.agent_status == "working")) | length),
      blocked: ($agents | map(select(.agent_status == "blocked")) | length),
      done: ($agents | map(select(.agent_status == "done")) | length),
      idle: ($agents | map(select(.agent_status == "idle")) | length),
      unknown: ($agents | map(select(.agent_status == "unknown")) | length),
      agents: (
        $agents
        | sort_by(
            if .agent_status == "blocked" then 0
            elif .agent_status == "working" then 1
            elif .agent_status == "done" then 2
            elif .agent_status == "idle" then 3
            else 4
            end,
            .cwd
          )
        | map({
            name: (.name // ((.cwd // "") | rtrimstr("/") | split("/") | last) // .pane_id // "Agent"),
            status: (.agent_status // "unknown"),
            paneId: (.pane_id // ""),
            cwd: (.cwd // "")
          })
      )
    }
' <<< "$response"
