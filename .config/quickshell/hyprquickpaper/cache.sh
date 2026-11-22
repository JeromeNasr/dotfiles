#!/usr/bin/env bash
# Build/refresh JPEG thumbnails for the wallpaper picker (only missing/outdated ones),
# and drop thumbnails whose wallpaper was deleted. Thumb name: "<original file name>.jpg".
CONFIG="$1/config.json"
expand_home() { case "$1" in '$HOME') echo "$HOME";; '$HOME/'*) echo "$HOME/${1#'$HOME/'}";; *) echo "$1";; esac; }
wallpaper_path=$(expand_home "$(jq -r '.wallpaper_path' "$CONFIG")")
cache_path=$(expand_home "$(jq -r '.cache_path' "$CONFIG")")
jobs_max=$(( $(nproc) > 4 ? 4 : $(nproc) ))      # keep the machine responsive
mkdir -p "$cache_path"

shopt -s nullglob nocaseglob
for img in "$wallpaper_path"/*.{jpg,jpeg,png,webp}; do
    out="$cache_path/$(basename "$img").jpg"
    [[ -f "$out" && "$out" -nt "$img" ]] && continue
    # jpeg:size lets the decoder downscale while reading -> several times faster on big JPEGs.
    # Write to a temp file and rename, so the picker never reads a half-written thumbnail.
    ( nice -n 10 magick -define jpeg:size=1600x900 "$img[0]" -auto-orient -thumbnail 800x450^ \
          -gravity center -extent 800x450 -strip -quality 86 "jpg:$out.part" \
      && mv -f "$out.part" "$out" ) &
    while (( $(jobs -rp | wc -l) >= jobs_max )); do wait -n; done
done
wait

# prune thumbnails of wallpapers that no longer exist
for t in "$cache_path"/*.jpg; do
    [[ -f "$wallpaper_path/$(basename "$t" .jpg)" ]] || rm -f "$t"
done
