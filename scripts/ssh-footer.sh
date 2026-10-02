#!/usr/bin/env bash
# Footer bar of an SSH tab (runs in a 1-row pane created by plugins/ssh_info.lua).
# Usage: ssh-footer.sh <state file>
# The state file holds one tab-separated line written by WezTerm:
#   <pid> <alias> <user> <ip> <port>
# <pid> is ssh itself or the ssh-reconnect.sh wrapper that runs it.
# Exits (closing the pane) once that process is gone.
state=$1
INTERVAL=2
export LC_NUMERIC=C # "20.4" parses and prints the same in any locale
exec 2>/dev/null # ps warns about the 1-row terminal ("screen size is bogus")

# Gruvbox Material (same palette as lua/core/colors.lua)
rgb() { printf '%d;%d;%d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
BG_DIM=$(rgb '#1d2021') BG1=$(rgb '#32302f') BG3=$(rgb '#45403d')
FG0=$(rgb '#d4be98') FG_DIM=$(rgb '#a89984') GRAY=$(rgb '#7c6f64')
GREEN=$(rgb '#a9b665') YELLOW=$(rgb '#d8a657') ORANGE=$(rgb '#e78a4e')
RED=$(rgb '#ea6962') AQUA=$(rgb '#89b482') BLUE=$(rgb '#7daea3') PURPLE=$(rgb '#d3869b')
ROOT_BG=$(rgb '#3c2423') # footer background while the user is root
BASE=$BG_DIM # footer background: $ROOT_BG while root
bg() { printf '\e[48;2;%sm' "$1"; }
fg() { printf '\e[38;2;%sm' "$1"; }
B=$'\e[1m' N=$'\e[22m' R=$'\e[0m'

human() { # bytes -> 1.2M; from 1000 of a unit on, the next one (1000G -> 1.0T)
  # $2: units printed with one decimal, the others rounded (default: all but B)
  awk -v b="$1" -v d="${2-KMGT}" 'BEGIN { split("B K M G T", u); i = 1
    while (b >= 1000 && i < 5) { b /= 1024; i++ }
    printf (index(d, u[i]) ? "%.1f%s" : "%.0f%s"), b, u[i] }'
}

duration() { # seconds -> 2h03m
  local s=$1
  if ((s >= 86400)); then printf '%dd%02dh' $((s / 86400)) $((s % 86400 / 3600))
  elif ((s >= 3600)); then printf '%dh%02dm' $((s / 3600)) $((s % 3600 / 60))
  else printf '%dm%02ds' $((s / 60)) $((s % 60)); fi
}

strip() { sed 's/\x1b\[[0-9;]*m//g' <<<"$1"; }

. "$(dirname "$0")/wezterm-usage.sh"

printf '\e[?25l' # hide cursor
stty -echo -icanon 2>/dev/null
trap 'printf "\e[?25h"' EXIT
trap 'draw' WINCH

prev_sent='' prev_recv='' prev_time='' up_rate='' down_rate='' line=''
auth_sp='' auth_time='' pending_since='' prev_retrans=0

collect() {
  [ -r "$state" ] || exit 0
  IFS=$'\t' read -r pid alias user ip port <"$state"
  kill -0 "$pid" 2>/dev/null || exit 0
  wezterm_usage # drawn at the far right by draw()

  # the ssh process: the pid itself or its child (under ssh-reconnect.sh)
  if [ "$(ps -o comm= -p "$pid")" = ssh ]; then sp=$pid
  else sp=$(pgrep -P "$pid" -x ssh | head -1); fi

  local host=" 󰒋 $alias " user_color=$ORANGE
  BASE=$BG_DIM
  [ "$user" = root ] && BASE=$ROOT_BG user_color=$RED
  # user, IP and port each in their own block
  local addr=''
  [ -n "$user" ] && addr+="$(bg "$user_color")$(fg "$BG_DIM")$B  $user $N"
  addr+="$(bg "$YELLOW")$(fg "$BG_DIM")$B 󰩟 $ip $N"
  addr+="$(bg "$BLUE")$(fg "$BG_DIM")$B 󰒍 $port $N"
  if [ -z "$sp" ]; then
    line="$(bg "$RED")$(fg "$BG_DIM")$B$host$N$addr$(bg "$BASE")$(fg "$RED")  ● disconnected"
    prev_sent='' pending_since=''
    return
  fi

  local stats sent recv rtt rttvar lastsnd lastrcv retrans now
  now=$(date +%s)
  # TCP counters of the ssh socket: no extra traffic, no remote commands
  stats=$(ss -tinpH state established 2>/dev/null | awk -v p="pid=$sp," 'index($0, p) { getline; print; exit }')
  sent=$(grep -oP 'bytes_sent:\K\d+' <<<"$stats")
  recv=$(grep -oP 'bytes_received:\K\d+' <<<"$stats")
  rtt=$(grep -oP ' rtt:\K[\d.]+' <<<"$stats")
  rttvar=$(grep -oP ' rtt:[\d.]+/\K[\d.]+' <<<"$stats")
  lastsnd=$(grep -oP 'lastsnd:\K\d+' <<<"$stats")
  lastrcv=$(grep -oP 'lastrcv:\K\d+' <<<"$stats")
  retrans=$(grep -oP 'retrans:\d+/\K\d+' <<<"$stats")

  # Connected time counts from login, not from when ssh started: while it asks
  # for a password/passphrase the tty is in canonical mode; once the session
  # opens ssh switches it to raw mode (-icanon). Kept in a file so it survives
  # the footer being recreated.
  local first=0
  if [ "$auth_sp" != "$sp" ]; then
    auth_sp=$sp auth_time='' pending_since='' prev_retrans=0 first=1
    [ -r "$state.auth" ] && read -r a t <"$state.auth" && [ "$a" = "$sp" ] && auth_time=$t
  fi
  if [ -z "$auth_time" ]; then
    local tty
    tty=$(ps -o tty= -p "$sp" | tr -d ' ')
    if [ -n "$tty" ] && [ "$tty" != '?' ] && stty -F "/dev/$tty" -a | grep -q -- ' -icanon'; then
      auth_time=$now
      # already logged in the first time we look (footer recreated, config
      # reload): the login moment was missed, ssh's start is the best guess
      ((first)) && auth_time=$((now - $(ps -o etimes= -p "$sp")))
      echo "$sp $auth_time" >"$state.auth"
    fi
  fi

  # Stall: we sent data (a keystroke, a keepalive) after the server last spoke
  # and got nothing back. Sends right after a receive are ssh's own flow
  # control, not something waiting for an answer, hence the 300 ms margin.
  local stall=0
  if [ -n "$lastsnd" ] && [ -n "$lastrcv" ] && ((lastrcv - lastsnd > 300)); then
    [ -z "$pending_since" ] && pending_since=$((now - lastsnd / 1000))
    stall=$((now - pending_since))
  else
    pending_since=''
  fi

  if [ -n "$prev_sent" ] && [ -n "$sent" ] && ((now > prev_time)); then
    up_rate=$(human $(((sent - prev_sent) / (now - prev_time))) GT)
    down_rate=$(human $(((recv - prev_recv) / (now - prev_time))) GT)
  fi
  prev_sent=$sent prev_recv=$recv prev_time=$now

  local sep="$(fg "$BG3") │ " state_color=$GREEN
  ((stall >= 5)) && state_color=$YELLOW
  ((stall >= 15)) && state_color=$RED
  line="$(bg "$state_color")$(fg "$BG_DIM")$B$host$N$addr$(bg "$BASE")"
  if ((stall >= 5)); then
    line+="  $(fg "$state_color")$B⚠ no response for $(duration "$stall")$N $(fg "$GRAY")· Alt+R reconnects$sep"
  else
    line+='  '
  fi
  if [ -n "$auth_time" ]; then
    line+="$(fg "$YELLOW")󱑎 $(fg "$FG0")$(duration $((now - auth_time)))"
  else
    line+="$(fg "$YELLOW")󰌆 $(fg "$FG_DIM")authenticating..."
  fi
  if [ -n "$sent" ]; then
    line+="$sep$(fg "$AQUA")↑ $(fg "$FG0")$(human "$sent" GT)$(fg "$GRAY")${up_rate:+ $up_rate}"
    line+="$sep$(fg "$BLUE")↓ $(fg "$FG0")$(human "$recv" GT)$(fg "$GRAY")${down_rate:+ $down_rate}"
    local ms jit color=$GREEN
    ms=$(printf '%.0f' "${rtt:-0}") jit=$(printf '%.0f' "${rttvar:-0}")
    ((ms >= 80 || jit >= 50)) && color=$YELLOW
    ((ms >= 200 || jit >= 150)) && color=$RED
    line+="$sep$(fg "$color")󰓅 $(fg "$FG0")${ms} ms$(fg "$GRAY") ±${jit}"
    # retransmitted segments: packet loss on the way
    if ((${retrans:-0} > 0)); then
      local rcolor=$GRAY
      ((retrans > prev_retrans)) && rcolor=$ORANGE
      line+="$sep$(fg "$rcolor")󰑓 ${retrans} lost"
    fi
    prev_retrans=${retrans:-0}
  else
    # shared connection (ControlMaster): the socket belongs to the master
    line+="$sep$(fg "$PURPLE")󰌘 $(fg "$FG_DIM")shared connection"
  fi
}

draw() {
  local cols plain
  cols=$(stty size 2>/dev/null </dev/tty | cut -d' ' -f2)
  plain=$(strip "$line")
  cols=${cols:-80}
  # truncating an ANSI string safely is not worth it: drop the stats if too narrow
  if ((${#plain} >= cols)); then
    line=${line%%$'\e[48;2;'"$BASE"'m'*}$(bg "$BASE")
    plain=$(strip "$line")
  fi
  # WezTerm's own usage at the far right, when it fits
  local right='' rplain
  rplain=$(strip "$wez_segment")
  if [ -n "$wez_segment" ] && ((${#plain} + ${#rplain} + 2 < cols)); then
    right="\e[$((cols - ${#rplain} + 1))G$(bg "$BASE")$wez_segment"
  fi
  printf '\e[H%s%s\e[K%b%s' "$(bg "$BASE")" "$line" "$right" "$R"
}

while :; do
  collect
  draw
  # sleeps and swallows anything typed into the footer
  read -rs -t "$INTERVAL" -n 64 _ 2>/dev/null
done
