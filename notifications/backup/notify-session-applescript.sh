#!/bin/bash
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')
dir_name=$(basename "$cwd")
hook_event=$(echo "$input" | jq -r '.hook_event_name // "notification"')

osascript <<EOF
display notification "$dir_name" with title "Claude - ${session_id:0:8}" subtitle "$hook_event" sound name "default"
tell application "iTerm" to activate
EOF
