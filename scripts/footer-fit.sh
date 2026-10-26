# Sourced by local-footer.sh and ssh-footer.sh (after their palette).
# The footer is a list of segments that fit_draw shrinks to the pane width so
# that every item stays visible: first the secondary texts (totals, labels,
# hints) lose characters, then the main values ("marpo-lap…"), then the
# separators get tight, until only the icons are left.
# Widths count characters: the Nerd Font Mono icons take one cell each.
#
#   seg <kind> <style> <text> [compact]
#     i  icon/fixed text, never shrinks
#     p  primary text (names, values)
#     s  secondary text, shrinks first
#     g  gap/separator, replaced by <compact> when space is very tight
#   seg_right   segments added after it go to the far right of the footer

# ${#var} must count characters, not bytes
case ${LC_ALL:-${LC_CTYPE:-$LANG}} in
  *[Uu][Tt][Ff]-8* | *[Uu][Tt][Ff]8*) ;;
  *) export LC_CTYPE=C.UTF-8 ;;
esac

ELLIPSIS='…'

# style: background, foreground and optional bold (any 3rd argument)
sty() { printf '\e[0;48;2;%s;38;2;%s%sm' "$1" "$2" "${3:+;1}"; }

seg_reset() { SK=() SS=() ST=() SA=() SEG_RIGHT=-1; }
seg() { SK+=("$1") SS+=("$2") ST+=("$3") SA+=("${4-}"); }
seg_right() { SEG_RIGHT=${#SK[@]}; }
seg_reset

# Width of segments [from, to) with the given caps; sets SEG_W.
# $1 primary cap, $2 secondary cap, $3 compact gaps (0/1), $4 from, $5 to
seg_width() {
  local i n
  SEG_W=0
  for ((i = $4; i < $5; i++)); do
    n=${#ST[i]}
    case ${SK[i]} in
      p) ((n > $1)) && n=$1 ;;
      s) ((n > $2)) && n=$2 ;;
      g) (($3)) && n=${#SA[i]} ;;
    esac
    ((SEG_W += n))
  done
}

# Largest cap in 0..$max for which everything fits in $avail; sets FIT_CAP
# (-1 if not even 0 fits). $1: which cap varies (p|s), $2 the other cap,
# $3 compact. Width only grows with the cap, so a binary search does.
fit_cap() {
  local lo=0 hi=$max mid
  FIT_CAP=-1
  while ((lo <= hi)); do
    mid=$(((lo + hi) / 2))
    if [ "$1" = p ]; then seg_width "$mid" "$2" "$3" 0 ${#SK[@]}
    else seg_width "$2" "$mid" "$3" 0 ${#SK[@]}; fi
    if ((SEG_W <= avail)); then FIT_CAP=$mid lo=$((mid + 1)); else hi=$((mid - 1)); fi
  done
}

# Text of segment $1 after the caps; sets PIECE
seg_piece() {
  local cap
  PIECE=${ST[$1]}
  case ${SK[$1]} in
    p) cap=$cp ;;
    s) cap=$cs ;;
    g) ((compact)) && PIECE=${SA[$1]}; return ;;
    *) return ;;
  esac
  if ((${#PIECE} > cap)); then
    if ((cap >= 2)); then PIECE=${PIECE:0:cap-1}$ELLIPSIS
    else PIECE=${PIECE:0:cap}; fi
  fi
}

# Renders segments [from, to) into OUT, clipped at $1 cells; sets OUT_W
seg_render() {
  local i room=$1
  OUT='' OUT_W=0
  for ((i = $2; i < $3 && room > 0; i++)); do
    seg_piece "$i"
    PIECE=${PIECE:0:room}
    OUT+=${SS[i]}$PIECE
    ((OUT_W += ${#PIECE}, room -= ${#PIECE}))
  done
}

# $1 pane width, $2 footer background (r;g;b)
fit_draw() {
  local cols=$1 base=$2 max=0 t avail cp cs compact=0 n right left_end
  n=${#SK[@]}
  left_end=$n
  ((SEG_RIGHT >= 0)) && left_end=$SEG_RIGHT
  for t in "${ST[@]}"; do ((${#t} > max)) && max=${#t}; done
  avail=$cols
  ((SEG_RIGHT >= 0)) && ((avail--)) # at least one cell between left and right
  cp=$max cs=$max

  seg_width "$cp" "$cs" 0 0 "$n"
  if ((SEG_W > avail)); then
    fit_cap s "$max" 0 # 1. secondary texts
    if ((FIT_CAP >= 0)); then
      cs=$FIT_CAP
    else
      cs=0
      fit_cap p 0 0 # 2. primary texts, while they still show a few letters
      if ((FIT_CAP >= 3)); then
        cp=$FIT_CAP
      else
        compact=1 # 3. tight separators
        fit_cap p 0 1
        cp=$((FIT_CAP < 0 ? 0 : FIT_CAP)) # 4. icons only (clipped if still too wide)
      fi
    fi
  fi

  local line left_w
  seg_render "$cols" 0 "$left_end"
  line=$OUT left_w=$OUT_W
  right=''
  if ((left_end < n)); then
    seg_render "$cols" "$left_end" "$n"
    ((left_w + OUT_W < cols)) && right="\e[$((cols - OUT_W + 1))G$OUT"
  fi
  # The pane's default background (OSC 11) paints the strip WezTerm leaves
  # between the divider and the row. plugins/ssh_info.lua writes the terminal
  # background there, brightened so it matches once the footer is dimmed.
  # $(<file), not the read builtin: draw also runs from the WINCH trap, and a
  # read there leaves the main loop's `read -t` waiting with no timeout
  local pane_bg
  pane_bg=$(<"${state%/*}/bg")
  if [ -n "$pane_bg" ] && [ "$pane_bg" != "$FIT_BG" ]; then
    FIT_BG=$pane_bg
    printf '\e]11;%s\e\\' "$pane_bg"
  fi
  printf '\e[H%s\e[0;48;2;%sm\e[K%b\e[0m' "$line" "$base" "$right"
}
