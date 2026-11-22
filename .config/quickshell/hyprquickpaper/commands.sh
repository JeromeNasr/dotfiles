#!/usr/bin/env bash
# Apply a wallpaper: animated transition, then re-theme from it.
# Transition types: fade, wipe, grow, outer, wave, center, any, random

img="$1"
[[ -f "$img" ]] || { echo "commands.sh: not a file: $img" >&2; exit 1; }

dur=1.0
awww img "$img" --transition-type grow --transition-pos 0.5,0.5 \
    --transition-duration "$dur" --transition-fps 60 --transition-bezier .25,1,.3,1

# Re-theme once the transition has mostly played, at low priority, so matugen and the
# app reloads don't steal frames from the animation.
mkdir -p "$HOME/.cache/43pr"
setsid -f bash -c 'sleep 0.8; exec nice -n 10 python3 "$HOME/.config/43pr/bin/theme.py" wallpaper "$1"' _ "$img" \
    >>"$HOME/.cache/43pr/theme.log" 2>&1
