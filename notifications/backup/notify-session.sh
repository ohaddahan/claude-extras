#!/bin/bash
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')
dir_name=$(basename "$cwd")
hook_event=$(echo "$input" | jq -r '.hook_event_name // "notification"')

terminal-notifier \
  -title "Claude - ${session_id:0:8}" \
  -subtitle "$hook_event" \
  -message "$dir_name" \
  -group "$session_id" \
  -sound default
