# The Thief of London

A realistic, open-world, third-person stealth game for Windows. You play **Harry Crane,
"The Hill Fox"**, a Victorian Robin Hood in **London, 1866**. Built with **Godot 4.7** (Forward+,
Jolt Physics) and GDScript.

> *"Take from those who won't miss it. Give to those who can't live without it."*

## Status: all 11 phases complete: Act One is playable from start to finish, ready to ship

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

**Greater London:** the city is now 3.4 km × 3.4 km (11.6 km²) round the old streets. It has about 1,240 blocks of terraces, shops, pubs and warehouses, the Thames with four bridges, St Paul's and Westminster, squares, churches and parks. Passers-by, street sellers and constables fill the streets, and all of it streams in around the player. The hills are now 4.1 km × 4.1 km (16.8 km²), with four villages, their people, farms, hedgerows and livestock, and travellers on the roads and hands in the fields. Harry's clearing is a camp: Aldous lives there on a daily routine (fire, wood, woods, whittling, supper, sleep) with his dog, and the Lantern Men come up of an evening to sit round the fire. Round the doors, people go about their day: sweeping steps, gossiping, keeping shop, drinking outside the pub, loading carts, children playing tag, each keeping their own hours and going home at night. The streets are thronged: thousands of walkers on every pavement round the player, drawn and walked on the GPU (`scripts/world/throng.gd`), thinning at night and in the rain. Chance encounters happen round Harry in both: a purse snatched in the street, a brawl, a street preacher, a beggar child, a highwayman on the London road, a carter with his wheel stuck in a rut. See [docs/GREATER_LONDON.md](docs/GREATER_LONDON.md).

**Phase 8 — the hills:** downs and woods north of London (first 2 km × 2 km, since grown to 4 km × 4 km):
- **Streaming:** the land streams in 64 m chunks on background threads, with levels of detail.
- **Harry's cave:** loaded on a background thread when he nears it. It has a fire, a bed (sleep), a loot chest and a fletching bench.
- **Wildlife:** red deer, rabbits and red foxes with sight, hearing and wind-borne scent. Hunt them with broadhead arrows (never at a man: the Outlaw's Code).
- **Cinder:** his horse walks, trots, canters and gallops, and has stamina. He jumps logs, fences and walls, refuses what's too high, and comes when whistled.
- **Travel:** finger-posts link London and the hills, and Harry's belongings come with him.

**Phase 9 — Steal and Give:**
- **Economy:** real £sd money. Sell loot to Mags Doyle the fence, give at the poor box, and buy picks, arrows and better kit at T. Wren, Ironmonger.
- **The Legend and notoriety:** giving raises the Legend (from *Nobody* to *The Legend of London*) and makes witnesses keep quiet. Crowe's notoriety brings wanted posters, a reward and extra constables, and fades while you lie low.
- **Upgrades and camp:** soft boots, a dark greatcoat, kid gloves, a yew war-bow, and a paddock, smokehouse and bunks for the cave.
- **Fishing:** cast, wait for the bite, strike, and play roach, perch, tench and pike on the tension line.
- **Menus and saving:** title screen, pause menu, the Ledger (Tab), save slots with autosave, and full settings with Low–Ultra presets, audio buses and key/pad rebinding.

**Phase 10 — the story begins:**
- **Act One, "The Outlaw of the Hills":** six missions, from Aldous's first lesson in the hills to Captain Crowe's manhunt through the market. They are:
  - hunting and fishing
  - chasing Pip through the crowds
  - lifting a widow's rent back from Ashcombe's collector
  - a fist fight with Big Tom on the Fleet footbridge
  - Father Bernard's soup kitchen and crypt safehouse
  - the Police News naming the Hill Fox
- **The mission system:**
  - objectives and markers, checkpoints with retry
  - in-engine cutscenes, dialogue and choices
  - the Lantern Men band (Pip marks the constables)
  - the Legend, and ending logic for the Acts to come
- **St Giles:** a new district behind the street.
  - The rookery's courts, and the Fleet ditch (wade it, climb out by ladders or steps).
  - Tom's footbridge, and St Giles-in-the-Fields with its tower, crypt safehouse and sanctuary.
  - It visibly improves as Harry gives to the poor.
- **Sound:**
  - every sound built in code (footsteps on 8 surfaces, doors, locks, bow, rattle, dogs, hooves, bells, thunder)
  - ambience that follows weather, time and place, and chase and tension music
  - drop-in replacements for real recordings
- **Performance:** occlusion culling, draw distances, NPC level of detail, one-piece far bodies for distant people, merged building shadows, dynamic resolution, graphics presets picked for your PC on first run, and an F3 performance overlay.

**Phase 11 — shipping:**
- **Export presets:** Windows 64-bit (icon, version and company details in the .exe, and a console launcher for troubleshooting) and Linux.
- **The Windows installer:** an Inno Setup script. It offers a desktop shortcut and a Direct3D 12 "safe mode" shortcut, keeps your saves on uninstall unless you ask, and ships the Read Me, the licence and Godot's third-party notices.
- **One-command builds:**
  - `tools\build_windows.bat` builds the game and installer on Windows.
  - `tools/build_release.sh` builds Windows and Linux, runs the exported game's self-test (`--smoke-test`) and zips both for itch.io.
- **Soak test:** `godot --headless --path . --script res://tools/soak_test.gd` plays the whole game unattended (the hills by day and night, riding, hunting, the road to London, every district in every weather, street incidents, save and load, and back). It reports any fall out of the world, leaked nodes, memory creep or long stalls, and the log shows any engine error.
- **Release helpers:** version bumping (`tools/set_version.sh`), Steam upload scripts (SteamPipe) and itch.io publishing (butler).
- **In-game extras:** the title screen shows the version, and **F12** saves a screenshot without the HUD.

**Visual pass (Syndicate-style mood):**
- blue skies with cumulus, blue-grey aerial haze
- a distant skyline with St Paul's, Westminster's Clock Tower, spires and smoking factory chimneys
- ornate lamps with hanging flower baskets, plane trees and bollards
- a columned bank front and a classically dressed Ashcombe House
- Harry in a flared leather greatcoat and top hat

**Real people:** most Londoners, and Harry himself, are professionally modelled people with photographed faces and skin: 27 [Microsoft Rocketbox](https://github.com/microsoft/Microsoft-Rocketbox) avatars (MIT licence). Gentlemen in dark suits, working men, constables, ladies and children, dressed for 1866 with top hats, bowlers, caps, the custodian helmet, ladies' hats and long, full skirts. They stand about, walk, run, sprint, talk, sit and wave by Rocketbox motion capture from real actors, with feet planted and no sliding. The procedural rig blends over the capture for fighting, climbing, falling and parkour. See [docs/REAL_PEOPLE.md](docs/REAL_PEOPLE.md).

**Generated people:** the other looks (priests, house guards, the background crowd) are built from the MakeHuman data: everyone in the game used to be a real human body (from the CC0 MakeHuman
data) in period clothes: gentlemen in frock coats and top hats, ladies in crinolines and
bonnets, costermongers, constables, rookery folk and Harry himself, each one different
in build, face, skin, hair, beard and colours. Hair and beards are layered shells with a soft, strandy edge; contact shadows are baked into every character (under collars and brims, in the folds where garments meet); and nobody stands dead still: they breathe, shift their weight and glance about. See [docs/REALISTIC_LOOK.md](docs/REALISTIC_LOOK.md).

**Daily routines:** the town is a roster of about 130 residents, each with a home, a trade
and a day. Costermongers keep their stalls from half past six to half past six; clerks
walk to work and come out to the market in their dinner hour; housewives shop at a
different hour each day; labourers leave for the docks before six; gentlemen browse and
retire to the club; pensioners take their morning turn; on Sunday morning the
churchgoers walk to St Giles; in the evening the drinkers go to the pub and are turned
out after midnight to stagger home. The rookery folk work in their yards and queue at
the soup kitchen at midday; beggars sit out by day; constables and Ashcombe's men keep
their shifts. Everyone comes out of their own front door and goes in through a real one.

## Getting started

Read **[docs/PHASE_1_GUIDE.md](docs/PHASE_1_GUIDE.md)**, then **[docs/PHASE_2_GUIDE.md](docs/PHASE_2_GUIDE.md)** **[docs/PHASE_3_GUIDE.md](docs/PHASE_3_GUIDE.md)** **[docs/PHASE_4_GUIDE.md](docs/PHASE_4_GUIDE.md)** **[docs/PHASE_5_GUIDE.md](docs/PHASE_5_GUIDE.md)** **[docs/PHASE_6_GUIDE.md](docs/PHASE_6_GUIDE.md)** **[docs/PHASE_7_GUIDE.md](docs/PHASE_7_GUIDE.md)** **[docs/PHASE_8_GUIDE.md](docs/PHASE_8_GUIDE.md)** **[docs/PHASE_9_GUIDE.md](docs/PHASE_9_GUIDE.md)** **[docs/PHASE_10_GUIDE.md](docs/PHASE_10_GUIDE.md)** and **[docs/PHASE_11_GUIDE.md](docs/PHASE_11_GUIDE.md)**. It covers installing Godot, Git and
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
- [docs/PHASE_9_GUIDE.md](docs/PHASE_9_GUIDE.md) — Steal and Give: fence, poor box, upgrades, Legend, notoriety, fishing, menus, settings, saving
- [docs/PHASE_10_GUIDE.md](docs/PHASE_10_GUIDE.md) — Act One walkthrough, the mission system, the fist fight, St Giles, sound (and adding real recordings), performance, writing missions
- [docs/PHASE_11_GUIDE.md](docs/PHASE_11_GUIDE.md) — building the Windows game and installer, testing a build, releasing on Steam and itch.io, code signing, release checklist
- [docs/GREATER_LONDON.md](docs/GREATER_LONDON.md) — the 11.6 km² city and the 16.8 km² hills: layout, streaming, people, villages and farms
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
9. ✅ Fishing, economy (Steal and Give), Legend and notoriety, menus, settings, saving
10. ✅ Story missions (Act 1), the St Giles district, sound, performance
11. ✅ Windows export, installer, Steam and itch.io release pipeline

### What's next: the rest of the story
The systems for the whole story are in place (missions, cutscenes, choices, the band, the
Legend, the ending logic), so the remaining work is mostly content:

- **Act Two, "Steal from the Rich" (missions 7–13):**
  - the rent-coach ambush on horseback
  - Lady Evelyn
  - the archery meeting in disguise
  - the workhouse rescue
  - the Bank of Ashcombe
  - Nate revealed
  - the rookery fire
- **Act Three (missions 14–18):**
  - the camp raid
  - the fog lockdown
  - the Newgate gallows rescue
  - Graves's deal: the Ledger choice
  - the band reunited
- **Act Four (missions 19–22):**
  - casing Ashcombe Palace
  - the Winter Ball heist
  - Nate on the rooftops
  - the race to Westminster, and the three endings
- **Smaller additions:** rope arrows, Old Jonah's river routes, Tobias's letters (collectibles), more districts (the docks, Westminster).
- **Look and sound:** real character models and recorded sound (see [docs/REALISTIC_LOOK.md](docs/REALISTIC_LOOK.md) and Part 5 of the Phase 10 guide).

Each mission is a short script (see "Writing a mission" in [docs/PHASE_10_GUIDE.md](docs/PHASE_10_GUIDE.md)).
