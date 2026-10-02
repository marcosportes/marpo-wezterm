#!/usr/bin/env bash
# Runs ssh and, if the connection drops, offers to reconnect (Tabby style).
# Usage: ssh-reconnect.sh [--lazy] [ssh] <ssh arguments...>
#   --lazy: wait for Enter before connecting (session restore sends it when
#           the tab is selected, so background tabs don't ask for passphrases)
if [ "$1" = "--lazy" ]; then
  shift
  [ "$1" = "ssh" ] && shift
  printf '\e]2;%s\a' "ssh $*"
  printf '\e[2m● Connects when this tab is selected (or press Enter)\e[0m\n'
  read -rs _
  exec "$0" "$@"
fi
[ "$1" = "ssh" ] && shift

while true; do
  printf '\e]2;%s\a' "ssh $*"
  ssh "$@"
  code=$?
  # Alt+R (plugins/ssh.lua) kills ssh with SIGUSR1 (128+10): reconnect right away
  if [ "$code" -eq 138 ]; then
    stty sane 2>/dev/null # ssh died without restoring the terminal
    printf '\n\e[1;33m● Reconnecting...\e[0m\n'
    continue
  fi
  # Normal exit (exit/logout/Ctrl+D): close the tab
  [ "$code" -eq 0 ] && exit 0

  echo
  printf '\e[1;31m● Connection closed (exit code %s)\e[0m\n' "$code"
  printf '  \e[1m[Enter]\e[0m reconnect   \e[1m[s]\e[0m local shell   \e[1m[q]\e[0m close tab\n'
  read -rsn1 key
  case "$key" in
    q|Q) exit "$code" ;;
    s|S) exec "${SHELL:-/bin/zsh}" -l ;;
  esac
  echo "Reconnecting..."
done
