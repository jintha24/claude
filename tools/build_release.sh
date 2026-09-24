#!/usr/bin/env bash
# Builds release versions of The Thief of London from Linux or macOS (or a CI machine):
# the Windows game (builds/windows), a Linux build (builds/linux, handy for Steam Deck
# testing), and zips of both for itch.io. Then checks the exported game actually starts.
#
# Usage: tools/build_release.sh /path/to/godot
# Needs the Godot export templates for your Godot version installed.
set -euo pipefail
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
VERSION=$(grep -E '^config/version=' project.godot | cut -d'"' -f2)
echo "=== The Thief of London $VERSION"

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

mkdir -p builds/windows builds/linux
echo "=== Windows..."
"$GODOT" --headless --path . --export-release "Windows Desktop" builds/windows/TheThiefOfLondon.exe
test -s builds/windows/TheThiefOfLondon.exe && test -s builds/windows/TheThiefOfLondon.pck
echo "=== Linux..."
"$GODOT" --headless --path . --export-release "Linux" builds/linux/TheThiefOfLondon.x86_64
test -s builds/linux/TheThiefOfLondon.x86_64 && test -s builds/linux/TheThiefOfLondon.pck

# Smoke test: the exported game boots to the title screen, loads London and the hills,
# runs them for a few seconds and quits (scripts/core/smoke_test.gd).
echo "=== Smoke-testing the exported build..."
if timeout 300 ./builds/linux/TheThiefOfLondon.x86_64 --headless -- --smoke-test > builds/smoke.log 2>&1 && grep -q "SMOKE OK" builds/smoke.log; then
	echo "Exported game runs."
else
	echo "The exported game failed its smoke test: see builds/smoke.log"
	exit 1
fi

echo "=== Adding the Read Me, licence and third-party notices..."
for d in builds/windows builds/linux; do
	cp installer/README.txt "$d/Read Me.txt"
	cp installer/LICENSE.txt "$d/Licence.txt"
	cp installer/THIRD_PARTY_NOTICES.txt "$d/Third-party notices.txt"
done

echo "=== Zipping for itch.io..."
(cd builds/windows && rm -f ../TheThiefOfLondon-$VERSION-windows.zip && zip -q -r ../TheThiefOfLondon-$VERSION-windows.zip .)
(cd builds/linux && rm -f ../TheThiefOfLondon-$VERSION-linux.zip && zip -q -r ../TheThiefOfLondon-$VERSION-linux.zip .)
ls -la builds/*.zip
echo "=== Done. Make the Windows installer with Inno Setup on Windows (installer/thief_of_london.iss)."
