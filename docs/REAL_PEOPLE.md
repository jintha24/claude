# Real people

Most people in the game, and Harry, are **Microsoft Rocketbox** avatars
(https://github.com/microsoft/Microsoft-Rocketbox, MIT licence, (c) 2020 Microsoft; the
licence ships in `assets/characters/rocketbox/LICENSE.md` and in the game's third-party
notices). They are professionally modelled and textured, with photographed faces and skin.

## Who is who (`scripts/npc/real_people.gd`)

| Look | Avatars | Dressed for 1866 with |
|---|---|---|
| gentleman | Business_Male_01-05, Male_Adult_03 | a top hat or a bowler |
| worker | Male_Adult_02, 05, 14, 20, Gardener_Male_01, Delivery_Male_01 | a flat cap |
| ragged | Male_Adult_07, 11, 20, Gardener_Male_01 (clothes darker and duller) | a flat cap |
| constable | Police_Male_03, Pilot_Male_01, 02 (tunics toned navy) | the custodian helmet |
| lady | Business_Female_02, 03, Female_Adult_02, 09, 11, 14 | a small straw or felt hat, and a long, full skirt |
| child | Male_Child_01, 02, Female_Child_01, 02 | sometimes a cap |
| harry | Male_Adult_07, browned to his greatcoat | his top hat |

Each look picks an avatar by the person's seed. The body texture is toned for the period
(`CLOTH_TINT`). Hats are fitted just above the eyebrows, oval to the head. Skirts hang
from the pelvis, gathered into folds, fuller behind, with a waistband. They swing:
`ClothSway` (`scripts/npc/cloth_sway.gd`) is a damped spring on how the waist moves. The
skirt trails as she walks, swings out on a turn and settles with a little bounce. It
is cheap enough for a whole street; there is no cloth simulation. The faces look along
-Z in the model, so cap peaks, helmet badges and the tilt of a lady's hat point that way. Looks with no
avatars (priest, house guard) stay the generated MakeHuman people (`CharacterLook`).

## Materials

- **Head:** the photographed colour, normal map, roughness from the specular map, and a little light through the skin.
- **Clothes and hands:** the same set, tinted.
- **Hair, lashes and brows:** an alpha-hashed sheet.

Each mesh draws out to 150 m. The engine's automatic LODs thin it with distance.

## Motion capture (`scripts/npc/mocap.gd`)

The real people and Harry move as the Rocketbox actors moved. These are Microsoft's
motion-capture clips, from the same repository under the same MIT licence. The clips:

- **Standing about:** four idles, one picked per person.
- **On the move:** walk, stroll, run and sprint.
- **Other acts:** looking round, talking and listening, sitting, waving, holding an umbrella, drunk (standing and walking), and crouching.

`tools/import_rocketbox_anims.gd` turns the FBX clips into two libraries,
`assets/characters/rocketbox/anims/male.res` and `female.res`:
- **Rotations:** every bone's rotation over time. A bone a clip leaves out holds the clip's own rest.
- **Hips:** the biped root's walk along is taken out. What is left goes onto the pelvis in the avatars' frame: the rise and fall, the sway, and sitting down.
- **Metadata:** each moving clip records how far one cycle carries the actor and when the left foot is forward.

Each person has their own AnimationTree, stepped by hand from `NPCBody.update_body` or
`HarryMannequin.update_pose`:
- **Speed:** idle → walk → run → sprint are blended by speed. The moving clips are kept in step and played just fast enough for the speed, so a planted foot stays put. A child's shorter stride is allowed for.
- **Acts:** the other acts cross-fade in over 0.45 s.

The procedural rig is blended over the clips for what was never recorded:
- **Whole body:** fists, staggers, knocked out, and all of Harry's parkour, jumps, rolls, riding and fights.
- **Arms only:** a truncheon, the police rattle, an umbrella, the bow, picking a pocket or a lock, browsing a stall.
- **Head:** turning to look at Harry.
- **Blend timing:** the rig blends in quickly and out a little slower. Blending out, it holds its last pose, so nothing pops.

`tests/test_mocap.gd` checks:
- every avatar stands upright under the clips (children too; their `Bip02` bones are renamed `Bip01` with their skin);
- a planted foot keeps pace with the ground walking and running;
- no pose change moves the head more than a few centimetres in a frame;
- the knocked-out fall takes over half a second;
- Harry hands over to the rig in the air and back on landing.

To add clips, copy the FBX files into `res://tmp_rb/`, import them, add them to `CLIPS` in the tool, and run it:
`godot --headless --path . --script res://tools/import_rocketbox_anims.gd`.

## The rig (`scripts/npc/character_rig.gd`)

The same mannequin drives every body. Its joints give the poses the clips don't have.
`update(weight, masks)` blends them over the clips, for the whole body or for named bone
groups. The rig handles any skeleton:
- **Bone names:** the biped names (`Bip01 L Thigh`...) map to the mannequin's (`BIPED`).
- **Pose:** each bone's pose is the joint rotation, then a limb correction from the model's rest arm or leg to straight down, then the bone's own rest orientation.
- **Frame:** the skeleton's own frame is allowed for. The avatars face +Z inside a rotated biped frame.
- **Hips:** with no root bone the pelvis follows the hips pivot in the world, so a knocked-out person lies on the ground.

## Adding more

```
# 1. fetch avatars (sparse), e.g. Male_Adult_08
git clone --filter=blob:none --no-checkout --depth 1 https://github.com/microsoft/Microsoft-Rocketbox rb
cd rb && git sparse-checkout set "Assets/Avatars/*/Male_Adult_08/Textures/*" "Assets/Avatars/*/Male_Adult_08/Export/Male_Adult_08.fbx" && git checkout
# 2. textures
python3 tools/rocketbox/textures.py rb Male_Adult_08
# 3. model: copy the .fbx into res://tmp_rb/, import, then
godot --headless --path . --script res://tools/import_rocketbox.gd -- Male_Adult_08
# 4. add the name to AVATARS in scripts/npc/real_people.gd; delete tmp_rb/
# 5. set the new textures' import to VRAM compressed with mipmaps (normal maps as normal maps);
#    tests/test_people.gd checks this
```

`tests/test_people.gd` checks every look: a real person, standing straight, arms by the
sides, a stride when walking, hat or skirt, and flat on the ground when knocked out.
