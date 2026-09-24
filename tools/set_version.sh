#!/usr/bin/env bash
# Sets the game's version everywhere it's written down: project.godot (shown on the title
# screen), the Windows export preset (the .exe's file properties) and the installer.
# Usage: tools/set_version.sh 0.12.0
set -euo pipefail
V="${1:?usage: tools/set_version.sh X.Y.Z}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3"; exit 1; }
cd "$(dirname "$0")/.."
sed -i.bak -E "s/^config\/version=\".*\"/config\/version=\"$V\"/" project.godot
sed -i.bak -E "s/^application\/(file|product)_version=\".*\"/application\/\1_version=\"$V.0\"/" export_presets.cfg
sed -i.bak -E "s/^  #define AppVersion \".*\"/  #define AppVersion \"$V\"/" installer/thief_of_london.iss
rm -f project.godot.bak export_presets.cfg.bak installer/thief_of_london.iss.bak
grep -E '^config/version' project.godot
grep -E '_version=' export_presets.cfg
grep -E '#define AppVersion' installer/thief_of_london.iss
