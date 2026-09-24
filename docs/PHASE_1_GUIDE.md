# Phase 1 — Project, Lighting, Harry, Camera and One London Street

This guide assumes no game-programming experience. Every step says exactly where to click.
Phase 1 is **complete and playable** as soon as you finish Part 3. Parts 5 and 6 then swap the
stand-in art for photo-scanned textures and the real Harry model, **without any code changes**.

---

## Part 1 — Install the tools (Windows 10/11, 64-bit)

### 1.1 Godot 4.7.2 (the engine)
1. Go to **https://godotengine.org/download/windows/**.
2. Click the standard **Godot Engine** download (version **4.7.2**), **not** the ".NET" one.
   We use GDScript, which only needs the standard build.
3. You get a zip file `Godot_v4.7.2-stable_win64.exe.zip`. Right-click it → **Extract All…** →
   extract to `C:\Godot\`.
4. Inside `C:\Godot\` you'll find `Godot_v4.7.2-stable_win64.exe`. Right-click it →
   **Send to → Desktop (create shortcut)**. Godot needs no installer.

> Use the same Godot version for the whole project. If a newer 4.7.x comes out, it's safe to
> update. Before moving to 4.8, make a Git commit first (see 1.2).

### 1.2 Git and Git LFS (version control)
1. Go to **https://git-scm.com/download/win** and run the 64-bit installer. Accept every default
   option. **Git LFS is included** in the Windows installer.
2. Open **Start → "Git Bash"** and run these two commands once:
   ```bash
   git lfs install
   git config --global core.autocrlf false
   ```
3. (Optional, easier) Install **GitHub Desktop** from https://desktop.github.com/ if you prefer
   clicking buttons to typing commands.

**Why LFS?** Textures, models and sounds are big binary files. The repository's
`.gitattributes` file already sends them to Git LFS automatically, so your repository stays
fast. The `.gitignore` already excludes Godot's `.godot/` cache folder and build outputs.

### 1.3 Blender (for preparing Harry's model — needed in Part 6)
1. Go to **https://www.blender.org/download/** and install the latest stable release.
2. Install the **MPFB** add-on (MakeHuman for Blender): in Blender open **Edit → Preferences →
   Get Extensions**, search **"MPFB"**, click **Install**.

---

## Part 2 — Get the project onto your PC

**Option A: Git Bash**
```bash
cd /c/
mkdir -p GameDev && cd GameDev
git clone https://github.com/jintha24/claude.git ThiefOfLondon
cd ThiefOfLondon
git checkout claude/thief-london-godot-game-b3xtz5
```

**Option B: GitHub Desktop.** Use **File → Clone repository → jintha24/claude**, choose
`C:\GameDev\ThiefOfLondon`, then pick the branch `claude/thief-london-godot-game-b3xtz5`
from the **Current branch** menu.

---

## Part 3 — Open and play

1. Start Godot. The **Project Manager** window opens.
2. Click **Import** (top left). Browse to `C:\GameDev\ThiefOfLondon\project.godot` and click
   **Open**, then **Import & Edit**.
3. The first import takes about a minute. Godot is building its `.godot` cache.
4. Press **F5** (or the ▶ **Run Project** button, top right).

The very first launch spends a few seconds generating the fallback textures (brick, cobbles,
slate…). They are cached in your user folder, so later launches start straight away.

### Controls

| Action | Keyboard / Mouse | Xbox / PlayStation |
|---|---|---|
| Move | W A S D | Left stick |
| Look | Mouse | Right stick |
| Walk (slow) | hold Ctrl | push stick gently |
| Sprint | hold Shift | click Left stick (L3) |
| Crouch-sneak (toggle) | C | B / Circle |
| Jump | Space | A / Cross |
| Swap camera shoulder | Q | click Right stick (R3) |
| Pause menu | Esc | Start / Options |
| Debug overlay (FPS, state, speed, fall height) | F3 | — |

Interact (E), horse (F / H), inventory (Tab) and map (M) are already in the Input Map. They start
working in later phases.

### Phase 1 test checklist

Try each of these. They are the acceptance tests for this phase:

- [ ] Harry accelerates and slows down smoothly. He never stops or turns instantly, and a
      sprint turn is wide.
- [ ] Walk ≈ 1.45 m/s, run ≈ 3.6 m/s, sprint ≈ 6.4 m/s (press **F3** to see speed).
- [ ] Harry steps straight up kerbs, the front stoops, and the alley staircase without jumping.
- [ ] Crouch (C): the camera drops lower and closer. Under a low obstacle he can't stand up.
- [ ] The camera never goes through walls. Walk into the narrow alley (east side, halfway down
      the street) and back against a wall.
- [ ] **Q** swaps the camera smoothly between the right and left shoulder.
- [ ] Sprinting pulls the camera back and slightly widens the view, with a very light head-bob.
- [ ] **Fall damage:** climb the alley stairs to the 9 m platform. Step off the open side of the
      upper staircase. Drops under 3.5 m are harmless, a 9 m drop takes about ⅔ of Harry's health,
      and 11 m or more is fatal. He respawns at the start.
- [ ] Walk into crates and barrels: they get shoved according to their mass.
- [ ] Gas lamps light the fog, and chimneys smoke.

---

## Part 4 — How the project is organised

```
ThiefOfLondon/
├─ project.godot            Engine settings: Forward+, Jolt Physics, TAA, input map
├─ icon.svg                 Window/taskbar icon (a proper .ico comes in Phase 11)
├─ .gitignore, .gitattributes   Git + Git LFS rules
├─ scenes/
│  ├─ main/main.tscn               ← the scene that runs when you press F5
│  ├─ main/london_environment.tres ← sky, fog, GI, SSAO, SSR, glow, tone mapping
│  ├─ main/camera_attributes.tres  ← auto-exposure and depth of field
│  ├─ player/harry.tscn            ← Harry: CharacterBody3D + capsule + Visual
│  └─ camera/third_person_camera.tscn
├─ scripts/
│  ├─ core/main.gd                 places Harry at the spawn point
│  ├─ player/harry.gd              movement, state machine, steps, falls, damage
│  ├─ player/harry_animator.gd     loads harry.glb, builds the AnimationTree
│  ├─ player/harry_mannequin.gd    stand-in body until harry.glb exists
│  ├─ camera/third_person_camera.gd over-the-shoulder spring-arm camera
│  ├─ world/london_street.gd       lays out the street, alley, lamps, props
│  ├─ world/building_facade.gd     ONE modular Victorian building (house or shop)
│  ├─ world/gas_lamp.gd            gas lamp with real light and shadows
│  ├─ world/chimney_smoke.gd       chimney smoke particles
│  ├─ world/street_props.gd        crates, barrels, handcart
│  ├─ world/material_library.gd    every material; auto-uses downloaded textures
│  ├─ world/procedural_textures.gd fallback brick/cobble/slate/wood textures
│  ├─ world/mesh_builder.gd        merges building pieces into one mesh (performance)
│  └─ ui/game_hud.gd               health, damage/death fades, F3 overlay, pause menu
├─ assets/
│  ├─ characters/harry/   ← put harry.glb here (Part 6)
│  ├─ textures/<name>/    ← unzip downloaded textures here (Part 5)
│  ├─ animations/, models/props/, audio/, fonts/, hdri/   (later phases)
└─ docs/
   ├─ PHASE_1_GUIDE.md    this file
   ├─ ASSETS.md           every asset: source, licence, folder
   └─ STORY.md            the Victorian Robin Hood story bible
```

### Tuning things without code
Almost every number is an **exported variable**, so you can change it in the **Inspector**:

- **Harry's speeds, acceleration, jump, fall-damage heights, step height:** open
  `scenes/player/harry.tscn` (double-click it in the **FileSystem** dock, bottom left). Click the
  **Harry** node. The **Inspector** (right side) shows groups such as **Speeds (m/s)**,
  **Momentum**, **Jumping and falling**…
- **Camera distance, shoulder offset, FOV, sensitivity, invert Y, head-bob:** open
  `scenes/main/main.tscn` and click **ThirdPersonCamera**.
- **Sky, fog, GI, reflections:** double-click `scenes/main/london_environment.tres`. Each
  section (Sky, Ambient Light, SSR, SSAO, SSIL, SDFGI, Glow, Fog, Volumetric Fog, Adjustments)
  can be expanded and edited. Changes show live in the 3D viewport.
- **Time of day (for now):** in `main.tscn` click **Sun** and change **Rotation X**
  (−16 = low golden sun, −50 = midday). Phase 5 replaces this with the day/night cycle.
- **The street:** in `main.tscn` click **LondonStreet** and change **Layout Seed** to reshuffle
  building widths, heights, brick types and shops.

### Seeing the street in the editor
The street is generated by code (a `@tool` script), so it appears in the 3D viewport when
`main.tscn` is open. If it ever doesn't show, click **Scene → Reload Saved Scene**.

### Why these technical choices (short version)
- **Forward+ renderer:** the only Godot renderer with SDFGI, volumetric fog, SSR and SSIL.
- **Jolt Physics** (Project Settings → Physics → 3D → Physics Engine): more stable stacking,
  used for crates now and carriages later.
- **Physics interpolation** is on, so movement is smooth at 120/144 Hz, not just 60 Hz.
- **TAA** anti-aliasing plus 16× anisotropic filtering keeps cobbles crisp at grazing angles.
  FSR 2 upscaling becomes a Settings-menu option in Phase 9.
- **World-space triplanar mapping** on buildings keeps bricks at their real size on walls of
  any size, with no stretching.
- **Merged building meshes:** each building is about 5 draw calls instead of about 300.

---

## Part 5 — Photo-scanned textures (optional; the game looks better)

Everything already has realistic procedural textures. To upgrade to real photo-scanned
textures:

1. Pick a texture from **https://polyhaven.com/textures** or **https://ambientcg.com** (both
   **CC0**: free for commercial use, no credit required).
2. Download the **2K** version. On Poly Haven choose **JPG**, and on ambientCG choose
   **2K-JPG**.
3. **Unzip the files straight into the matching folder** below. No renaming is needed: the game
   recognises both sites' file names (`_diff`, `_nor_gl`, `_rough`, `_ao`, `_disp` /
   `_Color`, `_NormalGL`, `_Roughness`, `_AmbientOcclusion`, `_Displacement`).

| Folder in `assets/textures/` | What to search for | Used on |
|---|---|---|
| `cobblestone/` | Poly Haven "cobblestone" / ambientCG "PavingStones" (square granite setts) | the road |
| `pavement/` | "paving", "flagstone" / ambientCG "PavingStones" (large slabs) | pavements |
| `curb_granite/` | "granite" / ambientCG "Rock" (grey speckled) | kerbs, steps |
| `brick_yellow/` | "brick" — a yellow/buff London stock brick | most houses |
| `brick_red/` | "red brick" / ambientCG "Bricks" | red houses, chimneys |
| `stucco/` | "plaster" / ambientCG "Plaster" (cream, smooth) | painted stucco fronts |
| `stone_trim/` | "concrete smooth", "limestone" / ambientCG "Concrete" (pale) | sills, cornices |
| `slate_roof/` | "roof slates", "slate" / ambientCG "RoofingTiles" (slate) | roofs |
| `wood_planks/` | "wood planks" / ambientCG "Planks" (weathered) | stairs, crates |
| `wood_painted/` | "painted wood" / ambientCG "PaintedWood" (white/light) | doors, shopfronts (tinted) |

4. Switch back to Godot. It imports the files automatically (you'll see a progress bar).
5. Press **F5**. The new textures are used immediately.
6. **Normal maps:** if the textures look "inside-out" (lit from below), you downloaded a DirectX
   normal map. Delete the `_nor_dx` / `_NormalDX` file and keep the `_nor_gl` / `_NormalGL`
   one.
7. **Scale:** if bricks look too big or too small, open `scripts/world/material_library.gd` and
   change `tile_real` for that material. This is the number of metres one texture repeat
   covers. A real brick course is 75 mm.
8. Record every asset you use in `docs/ASSETS.md` (a template row is there).

---

## Part 6 — Harry's real model and animations

Until this is done Harry is a dark, coated mannequin with the right proportions. The code
picks up the real model automatically from **`assets/characters/harry/harry.glb`**.

### 6.1 Build the body in Blender with MPFB (MakeHuman)
1. Open Blender → **File → New → General**. Delete the default cube (select it, press **X**).
2. Press **N** in the 3D viewport → **MPFB** tab → **New human → From scratch** → **Create human**.
3. In **Model**, set **Gender** fully male, **Age** ≈ 26 years, **Muscle** slightly above average,
   **Weight** average/lean, **Height** until the info panel shows **188 cm**.
4. **Apply assets → Library**: add **eyes**, **eyebrows**, **eyelashes**, **teeth**, a short
   **hair** style, and **skin** (MPFB's skin library includes realistic skin materials).
   Also add clothes that suit a Victorian worker: trousers, a long coat, boots, and a cap.
   MakeHuman's *community asset packs* (install from **MPFB → Apply assets → Load pack**,
   downloaded from **http://www.makehumancommunity.org/content/user_contributed_assets.html**)
   include coats, waistcoats, flat caps and boots. **Check each asset's licence** (most are CC0 or
   CC-BY) and record it in `docs/ASSETS.md`.
5. **Do not add a rig in MPFB.** Mixamo will rig it in the next step.
6. Select the body **and** all clothing (click the body, **Shift**-click each piece).
   Choose **File → Export → FBX**. In the export panel set **Limit to: Selected Objects**
   and **Path Mode: Copy**, and click the little **Embed Textures** icon next to it.
   Save as `harry_unrigged.fbx`.

*(Alternative: a realistic CC-BY character from **https://sketchfab.com** — filter
**Downloadable** and a Creative Commons licence, search "victorian man". Download as FBX or glTF,
then continue from 6.2.)*

### 6.2 Auto-rig and download animations from Mixamo (free Adobe account)
1. Go to **https://www.mixamo.com** → **Upload Character** → select `harry_unrigged.fbx`.
2. Place the markers (chin, wrists, elbows, knees, groin), choose **Skeleton LOD: Standard**,
   click **Next** until it is rigged.
3. **Download** the rigged character: **Format FBX Binary, Skin: With Skin**, and name it
   `harry_character.fbx`.
4. Now download each animation below. Search its name, click it, and **tick "In Place"** where
   that box exists. This is essential: Harry's code moves the body, the animation only moves
   the limbs. Then click **Download** with **Format FBX Binary, Skin: Without Skin,
   Frames per Second 30**.

| Save the file as | Search Mixamo for | In Place |
|---|---|---|
| `idle.fbx` | "Breathing Idle" | — |
| `walk.fbx` | "Walking" | ✔ |
| `run.fbx` | "Running" (or "Jog Forward") | ✔ |
| `sprint.fbx` | "Fast Run" or "Sprint" | ✔ |
| `crouch_idle.fbx` | "Crouching Idle" | — |
| `crouch_walk.fbx` | "Crouched Walking" | ✔ |
| `jump.fbx` | "Jump" (standing jump up) | ✔ |
| `fall.fbx` | "Falling Idle" | — |
| `land.fbx` | "Falling To Landing" | ✔ |
| `death.fbx` | "Dying" | — |

Mixamo animations are free to use in commercial games, royalty-free (Adobe's Mixamo FAQ).
Put all the FBX files in `C:\GameDev\HarrySource\`, **outside** the Godot project, because they
are source files.

### 6.3 Combine them into one harry.glb in Blender
1. New Blender file. Delete the cube. **File → Import → FBX** → `harry_character.fbx`.
2. For each animation file: **File → Import → FBX** → e.g. `walk.fbx`. It imports a second
   armature. Open the **Dope Sheet** (bottom editor) → switch its mode to **Action Editor**.
   Rename the new action (the name field at the top) to exactly **`walk`**. Click the **shield**
   icon (Fake User) so it is kept. Then delete the imported extra armature (select it in the
   Outliner, press **X**).
3. Repeat for every animation. Use the names in the first column without `.fbx`: `idle`,
   `walk`, `run`, `sprint`, `crouch_idle`, `crouch_walk`, `jump`, `fall`, `land`, `death`.
4. Select Harry's armature. In the **Action Editor**, pick each action in turn and click
   **Push Down** so all actions end up as NLA strips.
5. **File → Export → glTF 2.0 (.glb/.gltf)**:
   - Format: **glTF Binary (.glb)**
   - Include: **Selected Objects** off, **Custom Properties** off
   - Mesh: **Apply Modifiers** on
   - Animation: **Animation** on, **Mode: NLA Tracks** (or **Actions**), **Always Sample
     Animations** on
   - Save as **`C:\GameDev\ThiefOfLondon\assets\characters\harry\harry.glb`**
6. Save the Blender file as `C:\GameDev\HarrySource\harry.blend` (keep it for later changes).

### 6.4 Import settings in Godot
1. Switch to Godot. It imports `harry.glb` automatically.
2. In the **FileSystem** dock, **double-click `harry.glb`**. The **Advanced Import Settings**
   window opens.
3. In the scene tree on the left, click **Skeleton3D**. On the right, under **Retarget → Bone Map**,
   click **[empty] → New BoneMap**. Click the new BoneMap and set **Profile → New
   SkeletonProfileHumanoid**. Godot auto-maps Mixamo bone names, and every circle should turn
   green. This makes Harry's animations reusable on NPCs later.
4. Still under Retarget: **Remove Tracks → Unmapped Bones** on, **Rest Fixer → Overwrite Axis** on.
5. Click **Reimport** (bottom right).
6. Press **F5**. Harry now uses the real model. The code scales it to exactly **1.88 m**, turns it
   to face forward, and builds the AnimationTree: locomotion and crouch blend spaces, jump, fall,
   land and death states, with cross-fades.

### 6.5 Stop foot sliding
Open `scenes/player/harry.tscn`, click **Visual**, and look at **Animation reference speeds**.
Watch Harry's feet while walking, running and sprinting (use **F3** to see his speed):
- feet slide **forward** relative to the ground → **lower** that clip's speed value;
- feet slide **backward** → **raise** it.

A value is correct when the planted foot stays still on the cobbles.

If the model faces backwards, set **Model Yaw Offset Degrees** on **Visual** to `0`.

---

## Part 7 — Commit your work

```bash
git add -A
git commit -m "Add Harry model and textures"
git push
```

LFS stores the textures and `.glb` automatically. `git lfs ls-files` lists them.

---

## Recommended PC specs

| | Developing (editor + Blender) | Playing at High, 1080p, 60 FPS | Minimum (Low, 30 FPS) |
|---|---|---|---|
| CPU | 8-core, e.g. Ryzen 7 5700X / Core i7-12700 | 6-core, Ryzen 5 5600 / Core i5-12400 | 4-core, Core i5-8400 |
| RAM | 32 GB | 16 GB | 8 GB |
| GPU | RTX 3070 / RX 6800 (8+ GB VRAM) | RTX 3060 / RX 6700 XT (8 GB) | GTX 1660 / RX 5600 XT (Vulkan 1.2) |
| Storage | NVMe SSD, 100 GB free (assets + Blender files) | SSD, ~20 GB (final game) | SSD recommended |
| OS | Windows 10/11 64-bit | Windows 10/11 64-bit | Windows 10 64-bit |

SDFGI and volumetric fog are the heaviest effects. On weaker GPUs, lower the SDFGI cascades and
turn off SSIL. Phase 9's graphics presets automate this.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Your video card driver does not support Vulkan" | Update your GPU driver. Forward+ needs Vulkan (or Direct3D 12). |
| Mouse is free / camera doesn't turn | Click inside the game window (Alt+Tab releases the mouse). |
| Street missing in the editor viewport | **Scene → Reload Saved Scene**. |
| Textures still procedural after downloading | Check that the files are directly inside e.g. `assets/textures/cobblestone/` (not in a sub-folder) and that one filename contains `diff`/`Color`. |
| Harry is still the mannequin | Check the path is exactly `assets/characters/harry/harry.glb`. Look in **Output** (bottom panel) for a `HarryAnimator` warning listing the animation names found. |
| Harry runs away from his collision capsule | An animation was downloaded without **In Place**. Re-download it with In Place ticked. |
| Low FPS | In `london_environment.tres` untick **SSIL** first, then reduce **SDFGI → Cascades** to 3, then **Volumetric Fog → Length** to 60. |

---

## What's next — Phase 2 preview
Climbing and parkour: ledge detection with shape casts on sills, cornices and string courses;
drainpipe climbing (the pipes are already tagged `climbable_pipe` on physics layer 5); shimmying;
vaulting crates and carts; rooftop-to-rooftop jumps; landing rolls. Foot IK on stairs and hand IK
on ledges use Godot 4.7's built-in `TwoBoneIK3D` modifiers. Rope arrows from the story's longbow
also plug into this climbing system.
