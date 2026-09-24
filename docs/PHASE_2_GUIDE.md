# Phase 2 — Climbing, Parkour and Rooftops

Phase 2 turns the street into a climbing playground. Everything works immediately with the
stand-in mannequin. When you add the climbing animations to `harry.glb` (Part 3), the real model
uses them automatically, together with **foot IK** (feet planted on stairs, kerbs and slopes) and
**hand IK** (hands pinned to ledges and pipes).

To get the new code, pull the branch in Git Bash, or use GitHub Desktop → **Fetch origin** →
**Pull**:
```bash
git pull
```
Then open the project in Godot and press **F5**.

---

## Part 1 — How to climb

Harry only does what a strong, fit 1.88 m man could do. No magic sticking to walls: every grab
needs a real ledge, pipe or edge.

| Move | How | Details |
|---|---|---|
| **Vault** | Run at a low obstacle (0.3–1.3 m) and press **Space** | Horse trough, railings, crates. Harry keeps his speed on the far side. |
| **Mantle** | **Space** at a low obstacle with a top you can stand on | Handcarts, crate stacks, walls up to about 1.9 m. |
| **Jump-grab** | **Space** facing a ledge up to **2.95 m** above your feet | Harry jumps and hangs from it. |
| **Wall-run grab** | **Sprint or run at a wall** and press **Space** within about 1.5 m | Two strides up the wall. Reaches ledges up to **3.6 m** (shop cornices, first-floor string courses). |
| **Hang** | Automatic when a ledge is within reach while jumping or falling | Hold **C** while falling to *not* grab. |
| **Shimmy** | While hanging: **A / D** (or left stick) | Follows sills, cornices and string courses, and stops at gaps and corners. |
| **Climb up** | While hanging: **Space**, or hold **W** towards the wall | Only if there's room to stand or crouch on top. |
| **Hop up** | While hanging below a higher ledge within about 1.3 m: **Space** | Ledge to ledge. |
| **Drop** | While hanging or on a pipe: **C** | Drops straight down. Big drops still hurt. |
| **Jump back** | While hanging or on a pipe: hold **S** (away from the wall) + **Space** | Pushes off the wall. |
| **Drop to hang** | Crouch (**C**) and walk off an edge | Harry turns and lowers himself onto the edge instead of falling. This is how you get down from roofs safely. |
| **Drainpipe** | Face a drainpipe and press **Space** (also grabbed automatically when jumping at one) | **W** climbs, **S** climbs down. At the top, keep holding **W** to climb onto the roof. |
| **Landing roll** | Land from 2.2–7.5 m **while moving** | The roll keeps your momentum and takes only 35% of the fall damage. Landing from standing still = hard landing. |

**Catching a ledge while falling fast hurts your arms.** A catch after more than about 2.5 m of
free fall costs a few health points. After about 4.5 m, Harry can't hold on at all.

### The rooftop route in the test street
1. Every building has a **drainpipe** at one end of its front. Climb one to reach the roof.
2. Roofs are real 32° slate slopes you can walk and run along.
3. Where two neighbouring roofs differ by a storey, a **pipe on the taller building's side wall**
   takes you up.
4. From the alley's 9 m platform, jump and climb onto the roof beside it.
5. The two roofs either side of the alley are 2.4 m apart. **Sprint and jump across.**
6. Crouch-walk off the front of a roof to hang from the cornice, then shimmy along it or drop to a
   lower ledge.

### Phase 2 test checklist
- [ ] Sprint at the horse trough in the road (west kerb, near the middle of the street) and vault it.
- [ ] Mantle onto a handcart and onto the stacked crates.
- [ ] Climb a drainpipe to a roof, walk the roofline, and cross a height change using a side pipe.
- [ ] From a roof, crouch-walk off the eave, hang from the cornice, shimmy, climb back up.
- [ ] From the street, run at a shopfront and wall-run grab its cornice.
- [ ] Jump the alley gap between the two roofs.
- [ ] Drop from a first-floor ledge while running and roll.
- [ ] Press **F3**: the overlay shows the state (`HANG`, `PIPE`, `CLIMB_UP`, `VAULT`, `ROLL` …)
      and the height of the ledge you're holding.

---

## Part 2 — Tuning (Inspector, no code)

Open `scenes/player/harry.tscn`. Harry now creates a child node called **Parkour** automatically
when the game runs. To tune it in the editor, add that node permanently:

1. Select **Harry** → **right-click → Add Child Node** → search **HarryParkour** → **Create**.
2. Rename it to exactly **Parkour** (double-click the name).
3. In the Inspector you'll now see:
   - **Reach:** `Standing Reach` (2.95 m), `Wall Run Reach` (3.6 m), `Wall Run Min Speed`,
     `Vault Max Height`
   - **Timing:** `Climb Up Time`, `Mantle Time`, `Grab Time`, `Hop Time`, `Vault Time`
   - **Speeds:** `Shimmy Speed Max`, `Pipe Up Speed`, `Pipe Down Speed`, `Max Grab Fall Speed`

Landing-roll settings are on the **Harry** node under **Jumping and falling**: `Roll Min Speed`,
`Roll Max Height`, `Roll Damage Factor`, `Roll Duration`. Climbing camera distance is on
**ThirdPersonCamera** (`main.tscn`) → **Climb Distance**.

### What counts as a ledge
The code looks at real collision geometry, so you never have to mark ledges by hand. A ledge is
any surface that has:
- a flat-enough top (steeper than about 40° doesn't count),
- a vertical face below it that Harry can hang against,
- at least 45 cm of free space above the lip for his hands.

On the buildings that means window sills, lintels, string courses, door hoods, shop cornices,
roof cornices and wall tops. Drainpipes are separate: they sit on physics layer 5 ("climbable")
in the group `climbable_pipe`. To make any new pipe, ladder rail or post climbable, give it a
`StaticBody3D` with a `CylinderShape3D` on layer 5 and add it to that group
(**Node dock → Groups → climbable_pipe → Add**).

---

## Part 3 — Climbing animations for the real Harry (Mixamo)

Download these exactly as in Phase 1 Part 6.2: **FBX Binary, Without Skin, 30 fps**. Then add them
to `harry.blend` as actions with the names in the first column, as in Part 6.3. Re-export
`harry.glb` and Godot re-imports it by itself.

| Action name in Blender | Search Mixamo for | In Place |
|---|---|---|
| `hang_idle` | "Hanging Idle" | — |
| `shimmy_left` | "Left Shimmy" (or "Braced Hang Shimmy" mirrored) | — |
| `shimmy_right` | "Right Shimmy" | — |
| `climb_up` | "Braced Hang To Crouch" (or "Climbing To Top") | — |
| `hop_up` | "Braced Hang Hop Up" | — |
| `pipe_climb` | "Climbing Ladder" | — |
| `vault` | "Jump Over" | — |
| `roll` | "Falling To Roll" | — |

These clips can't be "In Place" on Mixamo, and that's fine. While Harry climbs, the code cancels
the clip's own hip movement (root motion) and moves him along a collision-checked path instead. It
also time-stretches each clip to match the action's duration exactly.

**Foot and hand IK switch on automatically** if the skeleton was retargeted to Godot's humanoid
profile (Phase 1 guide, 6.4 step 3), or keeps its raw Mixamo bone names. Two extra nodes appear
under the Skeleton3D when the game runs: **LegIK** and **ArmIK**. These are Godot 4.7's built-in
`TwoBoneIK3D`.
- Feet: each foot is raycast onto the ground below it, and the pelvis lowers for the lower foot
  (stairs, kerbs, roof slopes). Full strength when standing or walking, partial when running,
  and off when sprinting or in the air.
- Hands: pinned to the ledge lip (0.24 m either side of centre) while hanging or climbing, or to
  the pipe while on a drainpipe.
- To switch IK off (e.g. to compare), select **Visual** in `harry.tscn` and untick **Enable IK**.
- If the knees bend the wrong way, your skeleton's forward axis is unusual. Tell me the bone names
  from the **Output** panel and I'll adjust the pole directions.

---

## Part 4 — What changed in the code

| File | What |
|---|---|
| `scripts/player/parkour_sensor.gd` | **New.** Raycasts and shape checks that find walls, ledges, obstacles, pipes and free space. |
| `scripts/player/harry_parkour.gd` | **New.** The climbing moves: grab, hang, shimmy, climb up, hop, pipe, vault, drop to hang. |
| `scripts/player/harry_ik.gd` | **New.** Foot planting and hand pinning for the real model, using TwoBoneIK3D. |
| `scripts/player/harry.gd` | New states (ROLL, GRAB, HANG, CLIMB_UP, PIPE, VAULT), landing rolls, and hand-off to parkour. |
| `scripts/player/harry_animator.gd` | Climbing clips, hang blend space, one-shot timing, root-motion cancelling, hands aligned to the ledge, IK setup. |
| `scripts/player/harry_mannequin.gd` | Procedural poses for every new state. |
| `scripts/world/building_facade.gd` | Sills, lintels, string courses, cornices, door hoods and shop cornices now have collision. |
| `scripts/world/london_street.gd` | Side pipes wherever neighbouring roofs differ in height, roof access from the alley, a horse trough. |
| `scripts/camera/third_person_camera.gd` | Pulls back while climbing. |

Wet rooftops becoming slippery arrives with the weather system in Phase 6. Rope arrows (story:
the longbow) will plug into this same climbing system as extra "pipes".

---

## Part 5 — Automated tests (run them after any change)

The `tests/` folder contains automated gameplay tests. They start the real game without a
window, press keys like a player would, and check the results. Examples: "sprint speed is 6.4 m/s",
"Harry climbs the drainpipe onto the roof", "a 13 m fall is fatal and he respawns", "the Mixamo
clips map to the right states and IK switches on".

**Windows:** open **Command Prompt** in the project folder and run the *console* build of Godot
(it ships in the same zip, named `…_win64_console.exe`):
```bat
tests\run_tests.bat "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
```
Each check prints `PASS` or `FAIL`, and every file ends with a `RESULT` line. Phase 2 has 43 checks,
all passing. Each new phase adds its own test file, and every phase is only delivered with the
whole suite passing.
