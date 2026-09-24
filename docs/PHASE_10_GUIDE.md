# Phase 10 — The Story Begins: Act One, St Giles, Sound and Performance

This phase adds four things:
- **The story:** the mission system, and all six missions of **Act One: "The Outlaw of the Hills"**.
- **A new district:** the **St Giles rookery**, with the Fleet ditch and Father Bernard's church.
- **Sound:** every sound in the game, built in code, plus ambience and music.
- **Performance:** occlusion culling, draw distances and an F3 performance overlay.

---

## Part 1 — Playing the story

**New Game** starts where the story does: Harry's cave in the hills. Old **Aldous** is
waiting in the clearing with a gold ◆ over his head.

| On screen | Meaning |
|---|---|
| **◆ + a mission name** over someone | They have the next mission. Walk up and press **E**. Some missions start on their own when you arrive somewhere. |
| **Top left** | The mission's name and your current objective |
| **Gold ◆ with a distance** | Where the objective is. Off-screen, it sits on the edge pointing the way. |
| **Letterbox bars** | A cutscene. **E** or a click moves the dialogue on; **Space** skips the rest. |
| **Dialogue box** | Moves on by itself, or press **E** / click to hurry it along. |

- **Checkpoints:** a checkpoint is taken at the start of every mission step. If Harry is
  arrested, badly hurt, or fails the step (the boy gets away, the rent reaches Ashcombe
  House...), choose **Retry from the last checkpoint** or **Abandon the mission**. An
  abandoned mission can be started again from its giver.
- **Saving:** you can't save during a mission, and you can't travel between London and the
  hills in the middle of one. Missions are short, so finish it first. The autosave happens
  at the camp bed, the crypt cot, and on travel.
- **Choices:** some moments ask you to decide (the widow's rent). Choices are remembered
  and shape the ending (see `Story.ending()`).

## Part 2 — Act One, mission by mission

| # | Mission | Where / how it starts | What you do |
|---|---|---|---|
| 1 | **Cold Hearth** | The hills: talk to **Aldous** in the clearing | He gives you broadhead arrows (**R** switches arrows). Bring down a deer and butcher it (hold **E**), catch a fish from the jetty, and bring supper back to him. |
| 2 | **Crowded Pockets** | London: walk into the **market** by day (7 am – 7 pm) | A boy steals your purse. **Chase him** through the market, down the street and into St Giles (sprint!), and catch him within reach. Then prove you're the Hill Fox: pick a **gentleman's or lady's** pocket. **Pip joins the Lantern Men.** |
| 3 | **The Collector** | The street: **Mrs Hale** on the west pavement, by day | Pick **Mr Sloane's** pocket (top hat, walking to Ashcombe House) before he gets there, then give the rent back: **all of it**, or keep five shillings. The Legend begins. |
| 4 | **The Bridge** | St Giles: walk up to the **footbridge** over the Fleet ditch | **Big Tom** wants a shilling toll. Fight him on the planks (Part 3). The loser goes in the ditch. **Tom joins.** |
| 5 | **Father Bernard's Kitchen** | St Giles: **Father Bernard** at the soup kitchen, by day | Put at least **£1** in the poor box at the church door (sell loot to Mags Doyle if you're short), then follow him into the church. The **crypt becomes your safehouse**. |
| 6 | **Wanted: The Hill Fox** | The market's south entrance: buy a paper from the **newsboy** | The *Illustrated Police News* names you and Crowe offers £20. **Captain Crowe** and three constables give chase. **Escape:** break their line of sight and stay hidden for a few seconds, or reach the church. **End of Act One.** |

**What you get along the way:**
- **Pip's lookouts:** from Mission 2, every constable within 40 m has a small mark over his head.
  - Blue: calm. Amber: suspicious. Red: chasing.
- **The safehouse:** the crypt of St Giles has a cot (sleep and autosave) and a strongbox. The strongbox shares its contents with the camp chest in the hills.
- **Sanctuary:** once Father Bernard has taken you in, constables won't follow you into St Giles's church. Get inside and the chase is over.
- **The people you've met** stay in the world afterwards. Talk to them (**E**):
  - Aldous at the clearing
  - Pip in the market by day
  - Mrs Hale on her doorstep
  - Big Tom and Father Bernard at the soup kitchen (Bernard is in the church at night)

## Part 3 — The fist fight

A bare-knuckle fight on narrow footing: nobody is knocked out. Whoever loses his
**balance** goes over the side.

| Control | Action |
|---|---|
| **Left mouse (tap)** | Jab: quick and light. A clean jab interrupts his wind-up. |
| **Left mouse (hold ½ s, release)** | Haymaker: slow and heavy. It breaks his guard. |
| **Right mouse (hold)** | Guard. It blocks most of a jab or haymaker, but not a shove. |
| **A / D** | Sway aside and dodge anything. It costs a little footing. |
| **W / S** | Step in and out. |

**Reading him:** Tom telegraphs every blow.
- A short draw-back means a jab.
- A long one with a roar ("Hraagh!") and **!!** on screen means a haymaker.
- Squaring up with no wind-back means a shove (**!**, and a guard won't stop it).

**The winning rhythm:** sway just before a blow lands, then jab while he recovers.

**Balance** comes back when you're not being hit. Blows hurt a little, but never fatally.

## Part 4 — St Giles

St Giles is the rookery behind the west side of the street, where Harry grew up. Go in
through **Church Lane**, the gap in the west terrace about halfway along the street.

| Place | Notes |
|---|---|
| **Tenement courts** | Lodging-houses, yards with washing lines, a pump, privies and rubbish heaps to hide in. The two lane rows have entries through to the yards. |
| **The Fleet ditch** | The old river, now an open sewer 3 m down between stone walls. Fall in and you wade (slowly, noisily). Climb out by the **iron ladders**, or the **stone steps** at the south end, which come out on the east bank. |
| **The footbridge** | One narrow plank bridge with no rail: Tom's bridge. |
| **St Giles-in-the-Fields** | A church with a tower (a real clock), a spire and a churchyard. Inside are pews, candles and a stair down to the **crypt**. The bell tolls every hour, and it's heard all over London. |
| **The soup kitchen** | Tables, a cauldron over a brazier, and the queue. |

**The district improves as you give.** The poor boxes feed `Progress.wellbeing`, and the
rookery shows it:

| Wellbeing | What changes |
|---|---|
| 15+ | Window boxes of flowers appear |
| 45+ | Bunting goes up across Church Lane |
| Rising | Fewer beggars sit in the lane, and the soup queue grows (more people fed) |

## Part 5 — Sound

The game ships with **no recorded audio**: every sound is synthesised in code the first
time it's needed (`scripts/audio/sound_library.gd`).

| Sound | Details |
|---|---|
| **Footsteps** | Harry's, on stone, slate, wood, grass, gravel, dirt, carpet and water, with four variations each |
| **Loops (ambience)** | Rain, wind, crowd murmur, city hum, birdsong, crickets, lapping water, fire |
| **One-shots** | Every noise the game makes: doors, windows, locks and picks, the safe, arrows (twang, thud, whistle), breaking glass, the police rattle, dogs, hooves, the whistle for Cinder, splashes, punches, coins, thunder, the church bell |

**What you hear:**
- **Where:** everything is heard where it happens, in 3D.
- **Ambience mix:** it follows the weather, the hour and the place.
  - Rain and wind rise with the weather, and are muffled indoors.
  - London has the crowd (louder where people are) and the city.
  - The hills have birds by day, crickets on nights outside winter, and water near the lake.
- **Music:** the director adds music by mood.
  - A low, uneasy drone plays while constables are searching.
  - A drum pulse joins it in a chase, and a stinger sounds when you're first spotted.

**Volume** is set per bus (Master, Music, Sound effects, Ambience, Voice) in Settings → Audio.

**Replacing sounds with real recordings** (no code changes): put a file with the sound's
name in the right folder, as `.ogg`, `.wav` or `.mp3`.

| Folder | Examples |
|---|---|
| `assets/audio/sfx/` | `bell.ogg`, `rattle.ogg`, `door_creak.ogg`, `bow_release.ogg` (the full list is at the top of `sound_library.gd`) |
| `assets/audio/footsteps/` | `step_stone_1.ogg` … `step_stone_4.ogg`, `step_wood_1.ogg`, … |
| `assets/audio/ambience/` | `rain.ogg`, `crowd.ogg`, `birds.ogg`, … (made to loop automatically) |
| `assets/audio/music/` | `explore.ogg` (calm), `tension.ogg`, `chase.ogg` |

**Good free sources:**
- [freesound.org](https://freesound.org) (check each licence)
- [Sonniss GDC bundles](https://sonniss.com/gameaudiogdc) (royalty-free)
- [OpenGameArt](https://opengameart.org)

## Part 6 — Performance

| Feature | What it does |
|---|---|
| **Occlusion culling** | Every building is an occluder, so whatever is behind the terraces isn't drawn. It's switched on in the project settings. |
| **Draw distances** | Crates, barrels, bollards and hay stop being drawn beyond 70 m. Carts, stalls and troughs stop at 120 m. People stop at 150 m. They fade out rather than pop. |
| **NPC level of detail** | Townsfolk beyond 35 m animate at a third of the rate. Beyond 80 m they stop animating and think less often. |
| **Streaming** | The hills stream in chunks (Phase 8), and the cave loads on a background thread. |
| **Sounds** | Built on a worker thread while the place loads, so the first footstep never hitches. |
| **F3 overlay** | Shows frame time (and physics time), draw calls, objects and primitives drawn, node count, NPC count, and video and static memory. |

**On a slow PC:**
1. Settings → Graphics → **Low**, which uses render scale 0.67 with FSR2.
2. If that's still slow, turn off **Volumetric fog**.
3. Then lower **Shadow resolution**.

## Part 7 — How it's built

| File | What it does |
|---|---|
| `scripts/story/story.gd` | Story state: the mission list (`MISSIONS`), what's done, flags and choices, the band, `start` / `retry` / `abandon`, the ending |
| `scripts/story/mission.gd` | The base class every mission extends, with its scripting helpers |
| `scripts/story/act1/m1_…m6_*.gd` | The six missions |
| `scripts/story/mission_giver.gd`, `story_director.gd`, `story_talk.gd`, `story_npc.gd` | Who offers which mission and where; the characters afterwards; scripted characters |
| `scripts/story/brawl_fight.gd` | The fist fight |
| `scripts/ui/story_ui.gd`, `mission_hud.gd`, `dialogue_box.gd`, `cutscene_player.gd` | Mission HUD, dialogue, cutscenes, retry menu |
| `scripts/world/st_giles.gd`, `water_volume.gd` | The district, and wadeable water in built places |
| `scripts/audio/sound_library.gd`, `audio_director.gd` | Sound synthesis and file overrides; the mix |
| `scripts/core/perf_tuning.gd` | Draw distances, occluders, overlay numbers |

## Part 8 — Writing a mission

1. Make `scripts/story/act2/m7_the_rent_coach.gd`:

```gdscript
extends Mission

var coachman: StoryNPC

func step_count() -> int:
	return 2

func setup(_from_step: int) -> void:
	coachman = npc("Coachman", NPCBody.Outfit.WORKER, 1.78, Vector3(10, 0, 20), Vector3(0, 0, 20))

func run_step(i: int) -> void:
	match i:
		0:
			await say([["Coachman", "Stand aside, there!"]])
		1:
			set_objective("Get to the coach", coachman)
			await until(func() -> bool: return harry_near(coachman.global_position, 2.0))
```

2. Add it to `Story.MISSIONS`, with its number, act, title, place, script and blurb.
3. Add a giver to `StoryDirector.GIVERS`: where it's offered, by whom, and at what hours.

**Rules for mission code:**
- Only wait with `until` and `wait`. They stop cleanly if the mission fails.
- Put anything the mission creates through `npc()` or `spawn()`, so it's cleared away afterwards.
- Make `setup(from_step)` place things correctly for **any** step. That's what a retry from a checkpoint calls.

## Part 9 — Tests

| Test | Checks | What it covers |
|---|---|---|
| `tests/test_story.gd` | about 75 | The whole district (walking in, the bridge, wading, ladders, steps, the church and crypt, the charity visuals); the sound (all sounds built, footsteps, ambience, rain, the bell, the chase music); and Missions 2–6 played through, with a failure and retry in Missions 3 and 4 and a won fist fight |
| `tests/test_story_hills.gd` | 18 | Mission 1 and the sound of the hills |
| `tests/test_performance.gd` | — | Occluders, draw distances, NPC LOD, the F3 overlay and London's frame time |
