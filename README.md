# The Thief of London

A realistic, open-world, third-person stealth game for Windows. You play **Harry Crane,
"The Hill Fox"**, a Victorian Robin Hood in **London, 1866**. Built with **Godot 4.7** (Forward+,
Jolt Physics) and GDScript.

> *"Take from those who won't miss it. Give to those who can't live without it."*

## Status: Phase 1 of 11 — complete and playable

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

## Getting started

Read **[docs/PHASE_1_GUIDE.md](docs/PHASE_1_GUIDE.md)**. It covers installing Godot, Git and
Blender, opening the project, controls, tuning, downloading textures, building Harry's model, and
the recommended PC specs.

## Documents
- [docs/PHASE_1_GUIDE.md](docs/PHASE_1_GUIDE.md) — step-by-step setup and Phase 1 walkthrough
- [docs/STORY.md](docs/STORY.md) — story bible (the Victorian Robin Hood) and which phase builds each story system
- [docs/ASSETS.md](docs/ASSETS.md) — asset sources and licences

## Roadmap
1. ✅ Project, lighting, Harry, camera, one street
2. Climbing, parkour, rooftops (plus foot/hand IK)
3. Stealth: guards, vision, hearing, light, noise, search; non-lethal takedowns; longbow basics
4. Market crowds and pickpocketing
5. NPC daily schedules and the day/night cycle
6. Dynamic weather and its gameplay effects
7. First palace infiltration
8. World streaming, wilderness, cave camp, animals, Cinder the horse
9. Fishing, economy (Steal and Give), Legend and notoriety, menus, settings, saving
10. Story missions (Act 1 first), full districts, sound, performance
11. Windows export and installer
