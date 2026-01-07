#!/bin/bash
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')
dir_name=$(basename "$cwd")

osascript <<EOF
display notification "$dir_name" with title "Claude - ${session_id:0:8}" subtitle "Waiting at:" sound name "default"
tell application "iTerm" to activate
EOF
