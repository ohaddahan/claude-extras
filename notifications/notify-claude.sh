#!/bin/bash
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
cwd=$(echo "$input" | jq -r '.cwd // "."')
hook_event=$(echo "$input" | jq -r '.hook_event_name // "notification"')
dir_name=$(basename "$cwd")

case "$hook_event" in
  "permission_prompt")
    title="Claude needs permission"
    subtitle="${session_id:0:8}"
    ;;
  "idle_prompt")
    title="Claude is waiting"
    subtitle="${session_id:0:8}"
    ;;
  "Stop")
    title="Claude finished"
    subtitle="${session_id:0:8}"
    ;;
  *)
    title="Claude - ${session_id:0:8}"
    subtitle="$hook_event"
    ;;
esac

terminal-notifier \
  -title "$title" \
  -subtitle "$subtitle" \
  -message "$dir_name" \
  -group "claude-$session_id" \
  -sound default \
  -activate com.googlecode.iterm2
