#!/usr/bin/env bash
# Fetches the CC0 MakeHuman data the character generator builds people from:
#   * the MakeHuman base mesh, shape targets and game-engine rig (from MPFB2)
#   * the high-poly eyes and their texture (from MakeHuman 1.x)
# Everything used is released as CC0 by the MakeHuman project (see data/LICENSE_*.md).
# Usage: tools/characters/fetch_data.sh
set -euo pipefail
cd "$(dirname "$0")"
D=data
C=cache
mkdir -p "$C" "$D/targets" "$D/rig" "$D/eyes"
# Keep Godot from importing the raw data (it lives inside the project folder).
touch "$C/.gdignore" "$D/.gdignore"
if [ ! -d "$C/mpfb2" ]; then
	git clone -q --depth 1 https://github.com/makehumancommunity/mpfb2 "$C/mpfb2"
fi
if [ ! -d "$C/makehuman" ]; then
	git clone -q --depth 1 --filter=blob:none --no-checkout https://github.com/makehumancommunity/makehuman "$C/makehuman"
	(cd "$C/makehuman" && git checkout HEAD -- makehuman/data/eyes)
fi
M="$C/mpfb2/src/mpfb/data"
cp "$M/3dobjs/base.obj" "$D/"
mkdir -p "$D/regions"
for r in lips_solid scalp_solid face_solid eyelids_solid neck_front_split neck_back_split; do
	cp "$M/uv_layers/$r.json.gz" "$D/regions/"
done
cp "$M/rigs/standard/rig.game_engine.json" "$M/rigs/standard/weights.game_engine.json" "$D/rig/"
rm -rf "$D/targets"/*
for t in macrodetails nose mouth chin cheek head eyes ears neck forehead eyebrows; do
	cp -r "$M/targets/$t" "$D/targets/"
done
# Clothes are fitted over a body without nipples (they'd print through the cloth).
mkdir -p "$D/targets/breast"
for t in nipple-point-decr nipple-size-decr breast-point-decr; do
	cp "$M/targets/breast/$t.target.gz" "$D/targets/breast/"
done
mkdir -p "$D/targets/torso"
cp "$M/targets/torso/torso-muscle-pectoral-decr.target.gz" "$D/targets/torso/"
E="$C/makehuman/makehuman/data/eyes"
cp "$E/high-poly/high-poly.mhclo" "$E/high-poly/high-poly.obj" "$E/materials/brown_eye.png" "$D/eyes/"
cp "$C/mpfb2/LICENSE.ASSETS.md" "$D/LICENSE_MakeHuman_assets_CC0.md"
echo "MakeHuman data ready in tools/characters/$D"
