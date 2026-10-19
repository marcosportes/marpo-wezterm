#!/bin/sh
# Runs setup.sh (git pull + sync) and records the commit that was installed.
# Usage: apply-update.sh SOURCE_DIR FINISHED_FILE
source=$1
finished=$2
export GIT_TERMINAL_PROMPT=0
timeout 120 "$source/setup.sh"
commit=$(git -C "$source" rev-parse HEAD 2>/dev/null || echo failed)
tmp="$finished.tmp"
printf '%s\n' "$commit" > "$tmp"
mv "$tmp" "$finished"
