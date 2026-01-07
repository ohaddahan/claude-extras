#!/bin/bash
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')
dir_name=$(basename "$cwd")

terminal-notifier \
  -title "Claude - ${session_id:0:8}" \
  -subtitle "Waiting at:" \
  -message "$dir_name" \
  -group "$session_id" \
  -sound default
