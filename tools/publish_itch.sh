#!/usr/bin/env bash
# Uploads the builds to itch.io with butler (https://itch.io/docs/butler/).
# Usage: tools/publish_itch.sh yourname/the-thief-of-london
# Run tools/build_release.sh first. butler only uploads what changed, and players using
# the itch app get the update as a small patch.
set -euo pipefail
TARGET="${1:?usage: tools/publish_itch.sh <itch user>/<game page>}"
cd "$(dirname "$0")/.."
VERSION=$(grep -E '^config/version=' project.godot | cut -d'"' -f2)
butler push builds/windows "$TARGET:windows" --userversion "$VERSION"
butler push builds/linux "$TARGET:linux" --userversion "$VERSION"
butler status "$TARGET"
