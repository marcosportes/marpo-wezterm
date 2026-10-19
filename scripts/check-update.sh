#!/bin/sh
# Compares origin with the commit last installed by setup.sh.
# Writes one line to DEST: a commit sha (origin is ahead), "same", or "fail".
# Usage: check-update.sh SOURCE_DIR INSTALLED_COMMIT DEST
source=$1
installed=$2
dest=$3
tmp="$dest.tmp"

finish() {
  printf '%s\n' "$1" > "$tmp"
  mv "$tmp" "$dest"
}

export GIT_TERMINAL_PROMPT=0
if [ ! -d "$source/.git" ]; then
  finish fail
  exit 0
fi

# Public GitHub remotes are fetched over HTTPS so the check works when the
# desktop session has no SSH key loaded. Anything else uses origin as-is.
url=$(git -C "$source" remote get-url origin 2>/dev/null || true)
https=$(printf '%s' "$url" | sed -e 's#^git@github.com:#https://github.com/#' -e 's#^ssh://git@github.com/#https://github.com/#')
fetched=0
case "$https" in
  https://github.com/*)
    if timeout 15 git -C "$source" fetch --quiet "$https" HEAD; then
      fetched=1
    fi
    ;;
esac
if [ "$fetched" -eq 0 ] && ! timeout 15 git -C "$source" fetch --quiet origin; then
  finish fail
  exit 0
fi
remote=$(git -C "$source" rev-parse FETCH_HEAD 2>/dev/null) || remote=
if [ -z "$remote" ]; then
  finish fail
  exit 0
fi
if ! git -C "$source" cat-file -e "$installed^{commit}" 2>/dev/null; then
  finish fail
  exit 0
fi
if [ "$remote" = "$installed" ]; then
  finish same
elif git -C "$source" merge-base --is-ancestor "$installed" "$remote"; then
  finish "$remote"
else
  # Local history is not behind origin (ahead, or diverged). Nothing to fast-forward.
  finish same
fi
