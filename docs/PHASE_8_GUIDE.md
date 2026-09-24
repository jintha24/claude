# Phase 8 — The Hills: Streaming World, Cave, Wildlife and Cinder

Harry's home ground: 2 km × 2 km of rolling downland and woods north of London, with his
cave, a lake, deer and rabbits, the old London road, and his horse, Cinder.

---

## Part 1 — Getting there and back

- **From London:** walk (or ride) to the **finger-post in the north-west corner of the
  market square** and press **E**: *"Set off for the hills"*. You arrive where the London
  road enters the hills, at the east edge.
- **From the hills:** follow the road east to the **London finger-post**: *"Set off for London"*.
  You arrive on the north road into the market.
- **Loading:** a title card with a progress bar shows while the next place loads on a
  background thread.
- **What comes with you:** your purse, loot, keys, lockpicks, arrows and health. If you set
  off on horseback, Cinder comes too.

The game can also be started straight in the hills: open `scenes/wilderness/hills.tscn`
and press **F6** (Run Current Scene). Harry wakes in the clearing in front of his cave.

## Part 2 — The land

| Place | Where | Notes |
|---|---|---|
| **The cave** | Against the escarpment, north of the clearing | Harry's home (Part 3) |
| **The clearing** | In front of the cave | Aldous's old jump course: a log, a rail fence, a dry-stone wall, and the high sheepfold wall |
| **The lake** | South-east of the cave | About 1.5 m deep; you **wade**, slowly and noisily |
| **The London road** | From the clearing, winding east | Graded gently along the valleys; the finger-post is at the east edge |
| **Woods** | Everywhere between | Oaks and beeches low down, Scots pines higher up; boulders on the steep slopes |

The world is a **streamed** open world:
- **Chunks:** the land is cut into 64 m chunks. Those near Harry have full detail, collision,
  trees with solid trunks, boulders and wind-blown grass.
- **Far chunks:** up to about 450 m away they're drawn simply.
- **Background threads:** everything is built on background threads as you move, so there are no loading pauses.
- **Unloading:** chunks far behind you are unloaded.

## Part 3 — The cave hideout

The cave is loaded on a background thread (`ResourceLoader.load_threaded_request`) when
you come within about 220 m, and unloaded beyond 320 m.

| Feature | What E does |
|---|---|
| **Fire** | Lights you up. The back of the cave is dark by day. |
| **Bedroll** | **Sleep until dusk** (by day) or **until dawn** (at night). You wake fully healed. |
| **Camp chest** | **Stash your loot** (everything except keys), or **take it back**. It's safe here until it's fenced or given away (Phase 9). |
| **Fletching bench** | **Make arrows** (hold): tops up to 12 blunt, 6 whistle and 8 broadhead. |

## Part 4 — Wildlife and hunting

**Red deer** (herds of 3–6, sometimes with a stag) and **rabbits** live in the hills.

- **Sight:** they see movement and a man in the open. Crouch, keep still and stay in shadow.
- **Hearing:** they hear **every** sound, not just suspicious ones.
- **Scent:** deer smell you up to about 60 m **downwind**. Approach with the wind in your face
  (watch smoke and grass).
- **Alarm:** a herd **bolts together**. Deer run at up to 11 m/s; rabbits zig-zag.

**Hunting.** Press **R** to cycle to **broadhead** arrows (the new steel hunting heads).
- A broadhead **brings a deer down** after a short dying run.
- **Blunts** kill rabbits (blunts were the small-game arrow of the day), but only frighten a deer.
- Press **E** on the carcass: *Butcher the deer* (hold) gives **venison** and a **hide**; a rabbit gives the rabbit and its pelt.

**The Outlaw's Code:** Harry will not loose a broadhead at a person. If a man is under the
crosshair he lowers the bow: *"The Hill Fox doesn't kill."*

## Part 5 — Cinder

| Control | Action |
|---|---|
| **F** near him | Mount / dismount (when he's slow). You get off on the left, or wherever there's room. |
| **H** (anywhere) | **Whistle**. He comes at a canter. If he's far off, or can't find a way, he turns up close by, out of view. |
| **Move** | Ride that way (camera-relative). A light touch walks, a firm one trots. |
| **Shift (tap)** | Spur him on: trot → canter → gallop. He holds the pace until you ease off. |
| **Ctrl** | Hold him to a walk. |
| **Pull back** | Slow down, stop, rein back. |
| **Space** | Ask for a jump. |

**Speeds** (real horse gaits):

| Gait | Speed |
|---|---|
| Walk | 1.7 m/s |
| Trot | 3.8 m/s |
| Canter | 7.2 m/s |
| Gallop | 13 m/s |

The gallop uses **stamina**. When he's spent he drops to a canter until he's got his wind back.

**Horse parkour:**
- At a canter or gallop he **jumps anything up to 1.35 m** by himself: logs, fences, walls. Try the jump course in the clearing.
- He **refuses** anything higher (the 2 m sheepfold wall), **drops of more than 2.6 m** and **slopes too steep to climb**. He shies and stops.

**Other details:**
- **Hoofbeats** carry: walking 6 m, trotting 10 m, cantering 16 m, galloping 26 m. Guards hear them.
- He **wades** slowly through water.
- He can't climb very steep ground, so pick your way round.
- The **camera** pulls back when you ride, and further still at the canter.

In London, Cinder waits in the **mews** behind Ashcombe House. Whistle and he comes.

## Part 6 — How it's built

| File | What it does |
|---|---|
| `scripts/wilderness/terrain_generator.gd` | The shape of the land: a pure function of (x, z), so any thread can build any chunk. Holds the clearing, cave cut, lake, road and map edges. |
| `scripts/wilderness/world_streamer.gd` | Chunk streaming on `WorkerThreadPool`: detail levels, collision (`HeightMapShape3D`), tree and grass scatter, the terrain shader. |
| `scripts/wilderness/tree_meshes.gd`, `scripts/world/foliage.gd` | Trees built from leaf cards, and grass. The leaf texture is painted in code; replace it with `assets/textures/foliage/leaves.png`. |
| `scripts/wilderness/streamed_scene.gd` | Threaded load and unload of a place (the cave). |
| `scripts/wilderness/cave_hideout.gd`, `camp_bed.gd`, `camp_chest.gd`, `arrow_bench.gd` | The cave and its features. |
| `scripts/wilderness/wild_animal.gd`, `animal_spawner.gd`, `carcass.gd` | Deer and rabbits. |
| `scripts/horse/horse.gd` | Cinder. Drop a rigged horse model at `assets/characters/cinder/cinder.glb` to replace the stand-in. |
| `scripts/core/game_state.gd`, `scripts/ui/loading_screen.gd`, `scripts/wilderness/travel_point.gd` | Travelling between places. |

**Handy tweaks:**
- **View distance:** on the **Streamer** node, set `far_radius` (chunks, default 7) and `near_radius`.
- **Animals:** on the **Animals** node, set `deer_herds` and `rabbits`.
- **Horse:** on **Cinder**, set `gallop_seconds` (stamina), `acceleration` and `braking`. Gait speeds are in `GAIT_SPEED`.

**About Terrain3D:** the brief suggested the Terrain3D plugin. This phase uses a built-in
streamed height-field instead: it needs no compiled plug-in, runs in the automated tests,
and builds the same land on every PC. Terrain3D can still be added later for hand-sculpted
areas.

## Part 7 — Tests

`tests/test_wilderness.gd` (52 checks) covers:
- **Streaming:**
  - chunks load around Harry at the right detail levels
  - far chunks free
  - the terrain is the same on any thread
  - the lake and the road grade
- **The cave:**
  - wading
  - the threaded load and unload
  - the dark cave and the firelight
  - sleep, the chest and the bench
- **Wildlife:**
  - grazing, bolting as a herd, scent with the wind
  - hunting and butchering, blunt against deer and rabbit
  - the Outlaw's Code
- **Cinder:**
  - mounting, gaits, the jump course, refusing the high wall
  - galloping, stamina, hoofbeats, dismounting, whistling from far away
- **Travel:** the round trip to London and back with everything kept.
