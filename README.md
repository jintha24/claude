# The Thief of London

A realistic, open-world, third-person stealth game for Windows. You play **Harry Crane,
"The Hill Fox"**, a Victorian Robin Hood in **London, 1866**. Built with **Godot 4.7** (Forward+,
Jolt Physics) and GDScript.

> *"Take from those who won't miss it. Give to those who can't live without it."*

## Status: Phases 1–8 of 11 complete and playable

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

**Phase 5 — day and night:** a 48-minute day on a real calendar (from Thursday 20 September
1866). The sun follows its true path for London, and nights have moonlight and stars. The
lamplighter's round lights the gas lamps at dusk, and lamplight fills the windows. Everyone
follows the clock: traders open and close, crowds rise and fall by the hour, people go to the
pub and drunks stagger home at closing time. Constables change shift at 6 am and 6 pm, and the
night watch carries bullseye lanterns.

**Phase 6 — weather:** clear, overcast, rain, thunderstorms, pea-souper fog and winter snow,
changing on their own and always blending smoothly. Rain stops at roofs and splashes. Streets turn
wet and glossy and puddles form, then dry out slowly. Wind moves smoke and washing lines. Rain
masks footsteps, fog blinds the constables, and wet slate roofs are slippery. Fewer people are out
in bad weather, and they shelter or carry umbrellas.

**Phase 7 — Ashcombe House:** Lord Ashcombe's walled mansion east of the market, the first great
break-in. There are seven ways in:
- the gates
- the tradesmen's door
- the servants' entrance
- a drainpipe to the wing roof
- the garden wall
- sash windows
- an old sewer

Inside are two floors of furnished rooms with hinged doors that guards open as they pass. You pick
locks in a lever-lock minigame, and the study safe has a Chubb detector lock that jams for good if
you slip. There are paintings to cut from their frames and silver to steal. Watch for creaky
floorboards, dim rooms and gaslight, and for servants who notice an open door or an empty frame.
Two mastiffs are let loose at night: they track you by scent according to the wind, outrun you,
and bite.

**Phase 8 — the hills:** 2 km × 2 km of downs and woods north of London:
- **Streaming:** the land streams in 64 m chunks on background threads, with levels of detail.
- **Harry's cave:** loaded on a background thread when he nears it. It has a fire, a bed (sleep), a loot chest and a fletching bench.
- **Wildlife:** red deer and rabbits with sight, hearing and wind-borne scent. Hunt them with broadhead arrows (never at a man: the Outlaw's Code).
- **Cinder:** his horse walks, trots, canters and gallops, and has stamina. He jumps logs, fences and walls, refuses what's too high, and comes when whistled.
- **Travel:** finger-posts link London and the hills, and Harry's belongings come with him.

**Visual pass (Syndicate-style mood):**
- blue skies with cumulus, blue-grey aerial haze
- a distant skyline with St Paul's, Westminster's Clock Tower, spires and smoking factory chimneys
- ornate lamps with hanging flower baskets, plane trees and bollards
- a columned bank front and a classically dressed Ashcombe House
- Harry in a flared leather greatcoat and top hat

Realistic faces and clothing need real 3D models. See [docs/REALISTIC_LOOK.md](docs/REALISTIC_LOOK.md).

## Getting started

Read **[docs/PHASE_1_GUIDE.md](docs/PHASE_1_GUIDE.md)**, then **[docs/PHASE_2_GUIDE.md](docs/PHASE_2_GUIDE.md)** **[docs/PHASE_3_GUIDE.md](docs/PHASE_3_GUIDE.md)** **[docs/PHASE_4_GUIDE.md](docs/PHASE_4_GUIDE.md)** **[docs/PHASE_5_GUIDE.md](docs/PHASE_5_GUIDE.md)** **[docs/PHASE_6_GUIDE.md](docs/PHASE_6_GUIDE.md)** **[docs/PHASE_7_GUIDE.md](docs/PHASE_7_GUIDE.md)** and **[docs/PHASE_8_GUIDE.md](docs/PHASE_8_GUIDE.md)**. It covers installing Godot, Git and
Blender, opening the project, controls, tuning, downloading textures, building Harry's model, and
the recommended PC specs.

## Documents
- [docs/PHASE_1_GUIDE.md](docs/PHASE_1_GUIDE.md) — step-by-step setup and Phase 1 walkthrough
- [docs/PHASE_2_GUIDE.md](docs/PHASE_2_GUIDE.md) — climbing controls, tuning, climbing animations and IK
- [docs/PHASE_3_GUIDE.md](docs/PHASE_3_GUIDE.md) — stealth rules, guards, takedowns, the longbow, building stealth spaces
- [docs/PHASE_4_GUIDE.md](docs/PHASE_4_GUIDE.md) — the market, crowds and pickpocketing
- [docs/PHASE_5_GUIDE.md](docs/PHASE_5_GUIDE.md) — day and night, routines, police shifts
- [docs/PHASE_6_GUIDE.md](docs/PHASE_6_GUIDE.md) — dynamic weather and its effects
- [docs/PHASE_7_GUIDE.md](docs/PHASE_7_GUIDE.md) — Ashcombe House: routes in, lockpicking, the safe, dogs
- [docs/PHASE_8_GUIDE.md](docs/PHASE_8_GUIDE.md) — the hills: streaming world, cave, hunting, Cinder, travel
- [docs/REALISTIC_LOOK.md](docs/REALISTIC_LOOK.md) — getting the *Assassin's Creed Syndicate* look: what the code does, and how to add real textures, skies and character models
- [docs/STORY.md](docs/STORY.md) — story bible (the Victorian Robin Hood) and which phase builds each story system
- [docs/ASSETS.md](docs/ASSETS.md) — asset sources and licences

## Roadmap
1. ✅ Project, lighting, Harry, camera, one street
2. ✅ Climbing, parkour, rooftops (plus foot/hand IK)
3. ✅ Stealth: guards, vision, hearing, light, noise, search; non-lethal takedowns; longbow
4. ✅ Market crowds and pickpocketing
5. ✅ NPC daily schedules and the day/night cycle
6. ✅ Dynamic weather and its gameplay effects
7. ✅ First palace infiltration (Ashcombe House)
8. ✅ World streaming, wilderness, cave camp, animals, Cinder the horse
9. Fishing, economy (Steal and Give), Legend and notoriety, menus, settings, saving
10. Story missions (Act 1 first), full districts, sound, performance
11. Windows export and installer
