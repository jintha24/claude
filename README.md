# The Thief of London

A realistic, open-world, third-person stealth game for Windows. You play **Harry Crane,
"The Hill Fox"**, a Victorian Robin Hood in **London, 1866**. Built with **Godot 4.7** (Forward+,
Jolt Physics) and GDScript.

> *"Take from those who won't miss it. Give to those who can't live without it."*

## Status: Phases 1–4 of 11 complete and playable

- Project set up with the Forward+ renderer, Jolt Physics, physics interpolation, TAA, 16× anisotropic filtering,
  the full keyboard/mouse and controller input map, and Git + Git LFS rules.
- Realistic lighting: physical sky, low golden sun with 4-split soft shadows, SDFGI, SSAO, SSIL,
  SSR, volumetric fog, glow, AgX tone mapping, auto-exposure, subtle far depth of field.
- **Harry** (1.88 m): realistic momentum (acceleration, deceleration, speed-limited turning),
  walk / run / sprint / crouch-sneak, jump with coyote time and input buffering, automatic
  step-up for kerbs, stoops and stairs, fall damage, health regeneration, death and respawn,
  pushes crates and barrels by mass. Loads a Mixamo/MPFB model automatically and builds its
  AnimationTree in code. A procedurally animated stand-in body is used until then.
- **Third-person camera:** over-the-shoulder spring-arm camera with wall collision (for both the
  shoulder offset and the distance), shoulder swap, crouch and sprint framing, and a subtle head-bob.
- **One Victorian street** at real scale: a cobbled carriageway, granite kerbs, York-stone pavements,
  generated terraced houses and shopfronts (sash windows, doorcases, stoops, railings, slate
  roofs, chimneys with smoke, drainpipes), 12 shadow-casting gas lamps, an alley with a timber
  stair to 4.5 m and 9 m, physics crates and barrels, handcarts, and a church spire in the haze.

**Phase 2 — climbing and parkour:** vault, mantle, jump-grab and wall-run grab, hang, shimmy,
climb up, hop up between ledges, drop-to-hang from edges, drainpipe climbing, jump off walls, and
landing rolls. The rooftops are connected by side pipes, an alley gap and roof access. Real building
ledges (sills, lintels, string courses, cornices) are grabbable. The real model gets foot IK on
uneven ground and hand IK on ledges (Godot 4.7 `TwoBoneIK3D`).

**Phase 3 — stealth:** Metropolitan Police constables with realistic sight (light, shadow,
posture, line of sight) and hearing (gait, surface, walls). Suspicion depends on behaviour, so
walking the street is fine but rooftops, sneaking and trespassing are not. Guards search, poke
hiding places, chase with the police rattle, arrest, give up and return to their beats.
Non-lethal chokehold takedowns, and a longbow with blunt arrows (knock-outs, dousing gas lamps)
and whistle arrows (distractions). Hiding spots, restricted zones, and a stealth HUD.

**Phase 4 — the market:** a Spitalfields-style market square with 16 stalls, shops and a pub,
about 30 wandering and browsing shoppers, and traders crying their wares. Pickpocketing is a
timing mini-game shaped by crowd density, the victim's movement, their suspicion and the time of
day. Loot matches each class of victim, in pounds, shillings and pence. Failures bring shouts of
"Stop, thief!", gawking crowds and constables. Crowd avoidance and NPC level of detail.

## Getting started

Read **[docs/PHASE_1_GUIDE.md](docs/PHASE_1_GUIDE.md)**, then **[docs/PHASE_2_GUIDE.md](docs/PHASE_2_GUIDE.md)** **[docs/PHASE_3_GUIDE.md](docs/PHASE_3_GUIDE.md)** and **[docs/PHASE_4_GUIDE.md](docs/PHASE_4_GUIDE.md)**. It covers installing Godot, Git and
Blender, opening the project, controls, tuning, downloading textures, building Harry's model, and
the recommended PC specs.

## Documents
- [docs/PHASE_1_GUIDE.md](docs/PHASE_1_GUIDE.md) — step-by-step setup and Phase 1 walkthrough
- [docs/PHASE_2_GUIDE.md](docs/PHASE_2_GUIDE.md) — climbing controls, tuning, climbing animations and IK
- [docs/PHASE_3_GUIDE.md](docs/PHASE_3_GUIDE.md) — stealth rules, guards, takedowns, the longbow, building stealth spaces
- [docs/PHASE_4_GUIDE.md](docs/PHASE_4_GUIDE.md) — the market, crowds and pickpocketing
- [docs/STORY.md](docs/STORY.md) — story bible (the Victorian Robin Hood) and which phase builds each story system
- [docs/ASSETS.md](docs/ASSETS.md) — asset sources and licences

## Roadmap
1. ✅ Project, lighting, Harry, camera, one street
2. ✅ Climbing, parkour, rooftops (plus foot/hand IK)
3. ✅ Stealth: guards, vision, hearing, light, noise, search; non-lethal takedowns; longbow
4. ✅ Market crowds and pickpocketing
5. NPC daily schedules and the day/night cycle
6. Dynamic weather and its gameplay effects
7. First palace infiltration
8. World streaming, wilderness, cave camp, animals, Cinder the horse
9. Fishing, economy (Steal and Give), Legend and notoriety, menus, settings, saving
10. Story missions (Act 1 first), full districts, sound, performance
11. Windows export and installer
