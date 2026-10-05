# Sourced by local-footer.sh and ssh-footer.sh (after their palette and
# footer-fit.sh). Shown at the far right of the footer, labeled "wezterm usage".
# CPU and RAM used by WezTerm itself: the wezterm-gui process that runs the
# footer (its parent), not the shells/programs inside the tabs. CPU is a share
# of the whole machine (all cores), like the local footer's CPU.
WEZ_PID=$PPID
WEZ_COLOR=$(rgb '#d3869b')
wez_prev_proc='' wez_prev_total='' wez_cpu='' wez_rss=''
WEZ_ICON=$'\uf489' # nf-oct-terminal
# Thresholds: CPU < 5% green, up to 10% yellow, above red;
# RAM < 500M green, up to 1G yellow, above red
WEZ_CPU_WARN=5 WEZ_CPU_CRIT=10
WEZ_RAM_WARN=$((500 * 1024 * 1024)) WEZ_RAM_CRIT=$((1024 * 1024 * 1024))

# Samples into globals (the previous sample must survive between calls, which
# a $(...) subshell would lose); wez_segs adds them to the footer
wezterm_usage() {
  wez_cpu='' wez_rss=''
  local stat total proc rss cpu='…' cpu_color=$FG0 ram_color
  stat=$(</proc/"$WEZ_PID"/stat) || return
  read -r _ u n s i w q sq st _ </proc/stat
  total=$((u + n + s + i + w + q + sq + st))
  # utime and stime (fields 14 and 15); cut after ")" since comm may hold spaces
  read -r -a f <<<"${stat##*) }"
  proc=$((f[11] + f[12]))
  if [ -n "$wez_prev_total" ] && ((total > wez_prev_total)); then
    cpu=$(awk -v p=$((proc - wez_prev_proc)) -v t=$((total - wez_prev_total)) \
      'BEGIN { printf "%.1f", 100 * p / t }')
    cpu_color=$(awk -v c="$cpu" -v w="$WEZ_CPU_WARN" -v k="$WEZ_CPU_CRIT" \
      'BEGIN { print (c < w ? "g" : c <= k ? "y" : "r") }')
    case $cpu_color in g) cpu_color=$GREEN ;; y) cpu_color=$YELLOW ;; *) cpu_color=$RED ;; esac
    cpu+='%'
  fi
  wez_prev_proc=$proc wez_prev_total=$total
  rss=$(awk '/^VmRSS:/ { print $2 * 1024 }' /proc/"$WEZ_PID"/status)
  if ((rss < WEZ_RAM_WARN)); then ram_color=$GREEN
  elif ((rss <= WEZ_RAM_CRIT)); then ram_color=$YELLOW
  else ram_color=$RED; fi
  wez_cpu=$cpu wez_cpu_color=$cpu_color wez_rss=$(human "$rss") wez_ram_color=$ram_color
}

# $1: footer background
wez_segs() {
  [ -n "$wez_rss" ] || return
  seg_right
  seg i "$(sty "$1" "$WEZ_COLOR")" "$WEZ_ICON"
  seg s "$(sty "$1" "$WEZ_COLOR")" " wezterm usage"
  seg g "$(sty "$1" "$GRAY")" " "
  seg p "$(sty "$1" "$wez_cpu_color")" "$wez_cpu"
  seg g "$(sty "$1" "$GRAY")" " · " " "
  seg p "$(sty "$1" "$wez_ram_color")" "$wez_rss"
}
