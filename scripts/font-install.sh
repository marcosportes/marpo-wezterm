#!/usr/bin/env bash
# Downloads a Nerd Font from the official release and keeps only its "Mono"
# files (icons one cell wide). Run by plugins/font.lua when a font that is not
# there yet is picked.
# Usage: font-install.sh <release asset, e.g. Meslo> <fonts dir> [file prefix, e.g. MesloLGS]
# The prefix keeps one family of an asset that ships several (MesloLGS of
# Meslo). Exits 0 once <fonts dir>/<asset> holds the fonts.
set -eu
asset=$1 dest=$2/$1 prefix=${3:-*}
URL=https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$asset.tar.xz

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 2 -o "$tmp/font.tar.xz" "$URL"
mkdir -p "$tmp/out"
# only the styles core/fonts.lua asks for (some families ship dozens of
# weights and widths: Iosevka would take 380 MB)
patterns=()
for style in Regular Italic SemiBold SemiBoldItalic Bold BoldItalic; do
  patterns+=("${prefix}NerdFontMono-$style.ttf" "${prefix}NerdFontMono-$style.otf")
done
tar -xJf "$tmp/font.tar.xz" -C "$tmp/out" --wildcards --no-anchored "${patterns[@]}" 2>/dev/null || true
find "$tmp/out" -type f \( -name '*.ttf' -o -name '*.otf' \) | grep -q . || exit 1

# replace atomically: a half-written dir is never picked up by WezTerm
rm -rf "$dest.new"
mkdir -p "$dest.new"
find "$tmp/out" -type f \( -name '*.ttf' -o -name '*.otf' \) -exec mv -t "$dest.new" {} +
rm -rf "$dest"
mv "$dest.new" "$dest"
