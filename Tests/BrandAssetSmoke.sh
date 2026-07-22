#!/bin/zsh

set -euo pipefail

icon_dir="SwingArc/Assets.xcassets/AppIcon.appiconset"

for name in AppIcon-1024.png AppIcon-1024-dark.png AppIcon-1024-tinted.png; do
  test -f "$icon_dir/$name"
  test "$(sips -g pixelWidth "$icon_dir/$name" | awk '/pixelWidth/ {print $2}')" = "1024"
  test "$(sips -g pixelHeight "$icon_dir/$name" | awk '/pixelHeight/ {print $2}')" = "1024"
done

corner_hex="$(magick "$icon_dir/AppIcon-1024.png" -format '%[hex:p{0,0}]' info:)"
test "${corner_hex:u}" = "090D0C"

if grep -RqiE 'gradient|filter|#[0-9a-f]{8}' BrandAssets/SwingArcMark*.svg; then
  print -u2 "Brand SVGs must use flat six-digit fills without filters or alpha colors."
  exit 1
fi

print "Brand asset smoke passed"
