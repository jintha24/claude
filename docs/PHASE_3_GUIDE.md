# Phase 3 — Stealth, Guards, Takedowns and the Longbow

The street now has three Metropolitan Police constables on duty:
- **Constable Bates** walks the beat along both pavements.
- **Constable Wren** stands guard outside the London & County Bank.
- **Constable Pike** walks the carriageway and looks into the private yard (the alley).

Harry can now sneak, hide, douse lamps, distract, knock men out and run. He never kills anyone
(the Outlaw's Code).

Pull the branch (`git pull`), open the project and press **F5**.

---

## Part 1 — How the constables think (realistic rules)

**Being seen isn't a crime.** In 1866 a man walking down a public street in daylight is just a
man. The constables only grow suspicious when what Harry is doing looks wrong:

| What Harry is doing | How suspicious (0–1) |
|---|---|
| Walking or running normally in a public street | 0 (ignored) |
| Sprinting | 0.3 |
| Crouch-sneaking | 0.5 |
| On rooftops, drainpipes, hanging from ledges | 0.9 |
| In a private yard or grounds (a **restricted zone**) | 1.0 ("Trespassing" shows by the light gem) |
| Aiming a bow, doing a takedown | 1.0 |
| Seen committing a crime (takedown, etc.) | instant chase |

**Eyes.** Each guard has a 120° field of view that is sharpest in the central 50°. He needs a
clear line of sight to Harry's head, chest or hips. What he sees depends on:
- **Light:** Harry's light level from the sun and sky, plus every gas lamp, with real shadow
  checks. At night, under a lamp is bright and between lamps is dark.
- **Posture:** crouched is smaller, and standing still is harder to spot.
- **Distance:** his vision range shrinks in the dark.
- **Looking up:** men on the street rarely look up at the rooftops.
- **Up close:** within about 2 m he'll see you in any light.
- **Weather:** fog and rain come in Phase 6.

**Ears.** Guards hear:
- Footsteps. How loud depends on gait and surface: cobbles are quiet, timber louder, and slate
  roofs clatter. Crouching is nearly silent.
- Heavy landings.
- Crates knocked over, arrows, breaking lamp glass, scuffles.

Walls muffle sound. Ordinary footsteps in a public street don't bother them. Suspicious sounds, or
footsteps somewhere nobody should be (on a roof, in the yard), do.

**What a guard does:**
1. **Suspicious:** stops, stares at the spot and says "Hullo? Who's there?". If nothing more
   happens, he shrugs it off.
2. **Investigating:** walks to the last place he saw or heard something.
3. **Searching:** looks around, checks nearby spots, and **pokes hiding places**. If you're in
   one, he finds you. After about 25 s he gives up ("Must've been a cat.") and returns to his beat,
   staying on edge for a couple of minutes.
4. **Chase:** swings his **police rattle** (whistles weren't used until 1884). Every constable
   within about 45 m comes running. He runs at 5.2 m/s, slower than Harry's sprint, so you can
   outrun him, break line of sight, climb, or hide.
5. **Arrest:** if he catches you on the ground, you're arrested. The screen fades, Harry starts
   again at the spawn, and every guard returns to his beat. (Fines and notoriety come in Phase 9.)
6. If you're up on the roofs he can't follow. He stands below shouting "Come down from there!"
   until he loses sight of you.

---

## Part 2 — Controls

| Action | Keyboard / Mouse | Controller |
|---|---|---|
| **Takedown** (from behind or the side, guard not chasing) | **E** | X / Square |
| **Aim longbow** | hold **Right mouse** | hold **LT / L2** |
| **Draw and loose** | hold, then release **Left mouse** (full draw ~0.9 s) | **RT / R2** |
| **Switch arrow** (blunt / whistle) | **R** | D-pad right |
| **Pick up an arrow** | **E** next to it | X / Square |
| **Hide** | crouch (**C**) inside a hay heap | B / Circle |

**Takedown:** creep up behind an unaware or suspicious guard and press **E**. Harry locks a
chokehold, and after 1.6 s the man is unconscious for 4 minutes. If another constable sees the
body, he sounds the rattle and searches the area. Anyone who sees the takedown itself chases at
once.

**Longbow:** a 1.8 m yew longbow, about 55 m/s at full draw. Arrows really drop, but the aim
allows for it, so the crosshair is where the arrow lands, as an experienced archer would judge
it. A short draw is slower and falls short.
- **Blunt arrows (12):** a head shot knocks out a guard who isn't chasing you. A body shot only
  staggers him and tells him roughly where it came from. Hitting a gas lamp's glass puts the
  flame out, and the street goes dark around it.
- **Whistle arrows (5):** shriek in flight and make a loud noise where they land. Guards go to
  look, which is your chance to slip past.
- Arrows lie where they fall. Walk over and press **E** to recover them.

---

## Part 3 — The HUD

- **Detection chevrons** around the centre of the screen point at every guard who is noticing you.
  They fill white, then amber, then red, with **?** when he's searching and **!** when he's
  chasing.
- **Light gem** (bottom left, appears when sneaking or suspicious): its brightness is how visible
  you are. It shows **Hidden** in a hiding place and **Trespassing** in a restricted zone.
- **Crosshair** while aiming, with the arrow type, the count and the draw strength.
- **Subtitles** for what nearby constables say.
- **F3** now also lists every guard's state and awareness, and your light, visibility,
  suspicion and the surface you're standing on.

---

## Part 4 — Building your own stealth spaces (in the editor)

- **Guards:** add a **Node3D**, attach `scripts/npc/guard.gd`, and set **Display Name** and
  **Patrol Route Path** in the Inspector. Everything else (vision range, FOV, detection rate,
  search time, speeds) is tunable in the Inspector groups **Eyes**, **Detection**, **Searching**
  and **Movement**. No route means he stands guard where you place him, facing the way he faces.
- **Patrol routes:** add a **Node3D** with `scripts/npc/patrol_route.gd`, then add **Marker3D**
  children in walking order. Each marker's **Y rotation** is the way he looks while waiting there.
  Its metadata `wait_time` (Inspector → **Add Metadata**, type float) is how long he waits.
  **Loop** off makes him walk back and forth.
- **Restricted zones:** an **Area3D** with `scripts/world/restricted_zone.gd` and a
  CollisionShape3D covering the private area.
- **Hiding spots:** an **Area3D** with `scripts/world/hiding_spot.gd` plus a CollisionShape3D.
  Place it inside something you can crouch into (hay, sacks, under a tarpaulin), with no solid
  collision.
- **Lights that matter for stealth:** add any OmniLight3D to the group `stealth_lights`.
- **Walk surfaces:** give a CollisionShape3D (or its body) the metadata `surface` =
  `stone` / `wood` / `slate` / `metal` / `grass` / `mud`.
- **Navigation:** the **Navigation** node in `main.tscn` bakes the walkable area for the guards
  from every collision shape under nodes in the `navigation_source` group each time the game
  starts. (Phase 8 moves this to per-chunk baking.)

---

## Part 5 — Constable model and animations (optional)

The constables use the same stand-in approach as Harry: a period-dressed mannequin with dark blue
tunic, custodian helmet, belt and truncheon. To use a real model:
1. Make a constable in MPFB/MakeHuman (about 1.78 m), rig and animate it on Mixamo. Use
   "Breathing Idle", "Walking", "Running", "Looking Around", "Angry" (alert), "Hit Reaction"
   (stunned) and "Dying" (unconscious). Combine them in Blender as in the Phase 1 guide, naming
   the actions `idle`, `walk`, `run`, `look_around`, `alert`, `stunned` and `unconscious`.
2. Save it as `assets/characters/constable/constable.glb`.
3. Set **Body Model Path** on each guard (Inspector) to that file.

For Harry's new moves the animator also looks for `aim` ("Standing Draw Arrow" or "Standing Aim
Idle"), `takedown` and `arrested` ("Kneeling"). Missing clips fall back to idle.

---

## Part 6 — Tests

`tests/test_stealth.gd` adds 31 automated checks:
- Innocent walkers are ignored; sneaking is noticed.
- Walls and the vision cone block sight; trespassers are chased and arrested; guards reset after
  a respawn.
- Hearing a landing leads to investigate, search, give up and return; crouch-walking is silent.
- The rattle brings help.
- Takedowns work from behind but not the front, and a found colleague raises the alarm.
- Hiding in hay works.
- Lamplight versus darkness is measured correctly.
- Arrows douse lamps, knock guards out with head shots, stun with body shots, and lure with
  whistles.
- Real-control shooting and pickups work, and the ballistic aim lands within 25 cm at 35 m.

Run everything with `tests\run_tests.bat` (see the Phase 2 guide). The suite now has 74 checks.
