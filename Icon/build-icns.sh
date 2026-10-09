#!/bin/zsh
# Renders every icon size and packs them into Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")"
SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  swift make-icon.swift "$SET/icon_${s}x${s}.png" $s
  swift make-icon.swift "$SET/icon_${s}x${s}@2x.png" $((s * 2))
done
iconutil -c icns "$SET" -o ../Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
