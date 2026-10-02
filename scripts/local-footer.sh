#!/usr/bin/env bash
# Footer bar of a local tab (runs in a 1-row pane created by plugins/ssh_info.lua).
# Usage: local-footer.sh <state file>
# Shows host, user, CPU, RAM, disk and network usage of this machine.
# Exits (closing the pane) once the state file no longer says "local", i.e.
# the tab went over ssh: WezTerm then opens the ssh footer in its place.
state=$1
INTERVAL=2
DISK=/ # mount point whose usage is shown
export LC_NUMERIC=C # "20.4" parses and prints the same in any locale
exec 2>/dev/null

# Gruvbox Material (same palette as lua/core/colors.lua)
rgb() { printf '%d;%d;%d' "0x${1:1:2}" "0x${1:3:2}" "0x${1:5:2}"; }
BG_DIM=$(rgb '#1d2021') BG3=$(rgb '#45403d')
FG0=$(rgb '#d4be98') GRAY=$(rgb '#7c6f64')
GREEN=$(rgb '#a9b665') YELLOW=$(rgb '#d8a657') ORANGE=$(rgb '#e78a4e')
RED=$(rgb '#ea6962') AQUA=$(rgb '#89b482') BLUE=$(rgb '#7daea3')
ROOT_BG=$(rgb '#3c2423') # footer background while the user is root
bg() { printf '\e[48;2;%sm' "$1"; }
fg() { printf '\e[38;2;%sm' "$1"; }
B=$'\e[1m' N=$'\e[22m' R=$'\e[0m'

human() { # bytes -> 1.2M; from 1000 of a unit on, the next one (1000G -> 1.0T)
  # $2: units printed with one decimal, the others rounded (default: all but B)
  awk -v b="$1" -v d="${2-KMGT}" 'BEGIN { split("B K M G T", u); i = 1
    while (b >= 1000 && i < 5) { b /= 1024; i++ }
    printf (index(d, u[i]) ? "%.1f%s" : "%.0f%s"), b, u[i] }'
}

level() { # percentage -> color
  if (($1 >= 90)); then echo "$RED"
  elif (($1 >= 70)); then echo "$YELLOW"
  else echo "$GREEN"; fi
}

strip() { sed 's/\x1b\[[0-9;]*m//g' <<<"$1"; }

. "$(dirname "$0")/wezterm-usage.sh"

printf '\e[?25l' # hide cursor
stty -echo -icanon 2>/dev/null
trap 'printf "\e[?25h"' EXIT
trap 'draw' WINCH

HOST=$(uname -n)

# Tux (nf-linux-tux) waddling back and forth in a 3-cell slot before the host
# name. anim() redraws only that slot, between the full redraws of draw().
TUX=$'\uf31a' ANIM_FPS=2 ANIM_TICK=0.5 # frames per second, seconds per frame
FRAMES=("$TUX  " " $TUX " "  $TUX" " $TUX ")
ANIM_SLOT="\e[1;2H$(bg "$GREEN")$(fg "$BG_DIM")$B" # slot starts after the leading space
frame=0
anim() {
  frame=$(((frame + 1) % ${#FRAMES[@]}))
  printf '%b%s%s' "$ANIM_SLOT" "${FRAMES[frame]}" "$R"
}
USER_NAME=${USER:-$(id -un)}
BASE=$BG_DIM # footer background: $ROOT_BG while root

# User of the program in the foreground of the tab's terminal: follows su,
# sudo -i, etc. From the foreground process group's leader, walks down to the
# innermost process, preferring children in the foreground of their own
# terminal ("+" in stat): sudo runs the command on a pty of its own.
fg_user() {
  local tty=${1#/dev/} pgid
  [ -n "$tty" ] || return
  pgid=$(ps -o tpgid= -t "$tty" | awk '$1 > 0 { print $1; exit }')
  [ -n "$pgid" ] || return
  ps -e -o pid=,ppid=,stat=,user:32= | awk -v start="$pgid" '
    { user[$1] = $4; kids[$2] = kids[$2] " " $1; if ($3 ~ /\+/) fgp[$1] = 1 }
    END {
      if (!(start in user)) exit
      p = start
      while (p in kids) {
        n = split(kids[p], k, " "); next_p = ""
        for (i = n; i >= 1; i--) if (k[i] in fgp) { next_p = k[i]; break }
        if (next_p == "") next_p = k[n]
        p = next_p
      }
      print user[p]
    }'
}
prev_total='' prev_idle='' prev_rx='' prev_tx='' prev_time='' line=''

collect() {
  [ -r "$state" ] || exit 0
  local mode tty u
  read -r mode tty _ <"$state"
  [ "$mode" = local ] || exit 0
  u=$(fg_user "$tty") && [ -n "$u" ] && USER_NAME=$u
  BASE=$BG_DIM user_color=$ORANGE
  [ "$USER_NAME" = root ] && BASE=$ROOT_BG user_color=$RED

  local now sep="$(fg "$BG3") │ "
  now=$(date +%s)

  # CPU: busy share of the time elapsed since the last sample (/proc/stat)
  local cpu='' total idle
  read -r _ u n s i w q sq st _ </proc/stat
  total=$((u + n + s + i + w + q + sq + st)) idle=$((i + w))
  if [ -n "$prev_total" ] && ((total > prev_total)); then
    cpu=$((100 * ((total - prev_total) - (idle - prev_idle)) / (total - prev_total)))
  fi
  prev_total=$total prev_idle=$idle

  # RAM: what is not available to new programs (cache counts as free)
  local mem_total mem_avail mem_used mem_pct
  mem_total=$(awk '/^MemTotal:/ { print $2 * 1024 }' /proc/meminfo)
  mem_avail=$(awk '/^MemAvailable:/ { print $2 * 1024 }' /proc/meminfo)
  mem_used=$((mem_total - mem_avail)) mem_pct=$((100 * mem_used / mem_total))

  # Disk
  local disk_used disk_size disk_pct
  read -r disk_used disk_size < <(df -B1 --output=used,size "$DISK" | tail -1)
  disk_pct=$((100 * disk_used / disk_size))

  # Network: physical interfaces only (bridges, docker, VPN would count twice)
  local rx tx up_rate='…' down_rate='…'
  read -r rx tx < <(awk 'NR > 2 {
      sub(/^ +/, ""); split($0, f, /[: ]+/)
      if (f[1] ~ /^(lo|br-|docker|veth|virbr|wg|tun|tap)/) next
      rx += f[2]; tx += f[10] } END { printf "%d %d", rx, tx }' /proc/net/dev)
  if [ -n "$prev_rx" ] && ((now > prev_time)); then
    up_rate=$(human $(((tx - prev_tx) / (now - prev_time))) GT)
    down_rate=$(human $(((rx - prev_rx) / (now - prev_time))) GT)
  fi
  prev_rx=$rx prev_tx=$tx prev_time=$now

  line="$(bg "$GREEN")$(fg "$BG_DIM")$B ${FRAMES[frame]} $HOST $N"
  line+="$(bg "$user_color")$(fg "$BG_DIM")$B  $USER_NAME $N$(bg "$BASE")  "
  if [ -n "$cpu" ]; then
    line+="$(fg "$(level "$cpu")")󰻠 $(fg "$FG0")${cpu}%"
  else
    line+="$(fg "$GREEN")󰻠 $(fg "$GRAY")…"
  fi
  line+="$sep$(fg "$(level "$mem_pct")")󰍛 $(fg "$FG0")$(human "$mem_used")$(fg "$GRAY") / $(human "$mem_total")"
  line+="$sep$(fg "$(level "$disk_pct")")󰋊 $(fg "$FG0")$(human "$disk_used" "")$(fg "$GRAY") / $(human "$disk_size" "")"
  line+="$sep$(fg "$AQUA")↑ $(fg "$FG0")$up_rate"
  line+="$sep$(fg "$BLUE")↓ $(fg "$FG0")$down_rate"
  wezterm_usage # drawn at the far right by draw()
}

draw() {
  local cols plain
  cols=$(stty size 2>/dev/null </dev/tty | cut -d' ' -f2)
  plain=$(strip "$line")
  cols=${cols:-80}
  # too narrow: keep only host and user
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
  # animates the penguin until the next sample, swallowing anything typed
  # into the footer
  for ((i = 0; i < INTERVAL * ANIM_FPS; i++)); do
    read -rs -t "$ANIM_TICK" -n 64 _ 2>/dev/null
    anim
  done
done
