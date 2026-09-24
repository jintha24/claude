# Phase 9 — Steal and Give: Economy, Legend, Fishing, Menus and Saving

This phase turns the sandbox into a game you can play for hours and pick up again. You steal
from the rich, sell the goods, give to the poor and buy better kit. You fish and improve your
camp. Your deeds build **the Legend**, and Captain Crowe hunts you harder as your
**notoriety** rises. There is a title screen, a pause menu, full settings with key rebinding,
and save slots.

---

## Part 1 — Starting the game

The project now starts at the **title screen** (`scenes/ui/main_menu.tscn` is the main
scene). Press **F5** in Godot, or run the exported game.

| Button | What it does |
|---|---|
| **Continue** | Loads the most recent save (autosave or manual). Greyed out if there are none. |
| **New Game** | Starts fresh in London on Thursday 20 September 1866, at 4 in the afternoon. |
| **Load Game** | Choose any of the 6 slots. |
| **Settings** | See Part 7. |
| **Quit** | Back to Windows. |

Opening a scene directly (**F6** on `main.tscn` or `hills.tscn`) still works for testing, and
skips the menu.

## Part 2 — Steal and Give: the money loop

Money is kept in real **pounds, shillings and pence**: £1 = 20s = 240d.

1. **Steal.** Pickpocket, loot houses, crack safes.
2. **Sell** loot to **Mags Doyle, the fence**, at her stall on the east side of the market
   square. Press **E** to see what she'll pay for each piece, then *Sell it all*.
3. **Give** money at **Father Bernard's poor box**, at the north end of the street, where it meets the market.
4. **Spend** money at **T. Wren, Ironmonger**, the shop counter in the street, or at the camp.

**What the fence pays:**

| Goods | Price |
|---|---|
| Valuables (watches, rings, silver) | 35% of their worth |
| Goods from a **famous** burglary (an aristocrat's) | 25%: everyone knows where they came from |
| Game hides and pelts | 70% |
| Provisions (venison, rabbits, fish) | 80%, or 160% once you've built the **smokehouse** |

Keys, papers and letters are no use to her.

**If you're arrested:**
- The constables fine you **a quarter of your purse**.
- They take the valuables and provisions you're carrying.
- Anything stashed in the **camp chest** is safe.

## Part 3 — The Legend and notoriety

Two numbers follow Harry through the whole game. Hold **Tab** to see both in the **Ledger**,
Harry's pocket-book. It also shows your purse, picks, arrows, loot and upgrades.

**The Legend** (0–100) is what the people think of the Hill Fox:

| Legend | Rank |
|---|---|
| 0–19 | Nobody |
| 20–39 | A Rumour |
| 40–59 | The Hill Fox |
| 60–79 | A Folk Hero |
| 80–100 | The Legend of London |

- **Up:** giving to the poor raises it: 2 Legend per £1, from ½ up to 12 per gift.
- **Down:** robbing working people lowers it by 2.5 a time. Robbing traders costs a little.
- **Silent witnesses:** above 30 Legend, some witnesses *don't* raise the alarm when you rob
  the rich, up to a 60% chance at the top.

**Notoriety** (0–100) is how badly Crowe wants you:

| Rises by | Amount |
|---|---|
| Stealing from the rich | Scales with the value, up to 6 per theft |
| Robbing a constable | 1 |
| Every alarm raised | 2 |

It **falls by 8 every day** while the hue and cry dies down. Lie low in the hills and it fades.

| Notoriety | What happens |
|---|---|
| 25+ | **Wanted posters** go up with Crowe's reward (up to £50) |
| 50+ | **Extra constables** walk the street and market |
| 75+ | A hunted man: guards are sharper and slower to calm down |

## Part 4 — Upgrades

**T. Wren, Ironmonger (gear):**

| Item | Price | Effect |
|---|---|---|
| Set of Chubb-pattern picks | £1 10s | Lockpick sweet spot 30% wider |
| Soft-soled boots | £2 | Footsteps 25% quieter |
| Dark worsted greatcoat | £2 10s | 15% harder to see in shadow |
| Pickpocket's kid gloves | £1 5s | Pickpocket sweet spot 25% wider |
| Yew war-bow | £4 | Draws in 0.7 s instead of 0.9 s, and shoots farther |
| Large quiver | £1 | Carry 30 of each arrow instead of 20 |

Wren also sells **lockpicks** at 6d each and arrows by the piece: **blunt** 2d, **whistle** 3d,
**broadhead** 4d.

**The camp:** use the **plans by the fire** in the cave.

| Improvement | Price | Effect |
|---|---|---|
| A paddock for Cinder | £2 10s | He gets his wind back twice as fast |
| A smokehouse | £3 | Venison and fish fetch twice as much |
| Bunks and a stove | £5 | Room for the Lantern Men. Sleeping restores your lockpicks. |

Each improvement appears in the cave when you buy it. Upgrades are saved and re-applied on loading.

## Part 5 — Fishing

**Where:**
- the **anglers' jetty** on the north shore of the lake in the hills
- two quiet spots on the bank

Stand at one and the prompt reads *Fish from the jetty* (or *the bank*).

| Step | What to do |
|---|---|
| **Cast** | Hold **E**. The rod bends back and a power bar rises and falls. Let go at the top: a long cast reaches deeper water and bigger fish (pike). |
| **Wait** | Watch the float. Bites come sooner at **dawn and dusk** and in dull weather, and slower at noon and at night. Press **E** to reel in early. |
| **Strike** | When the float dips, press **E** within a second, or the fish takes the bait and goes. |
| **Play the fish** | Hold **E** to reel in (tension rises), let go to give line (tension falls). Keep the needle in the **middle band** while reeling and the fish tires. |

**Losing the fish:**
- Reel without stopping and the line **snaps**.
- Leave it slack too long and the fish **throws the hook**.

Walking away puts the rod down.

| Fish | Weight | Notes |
|---|---|---|
| Roach | up to ¾ lb | common |
| Perch | up to 1¾ lb | |
| Tench | up to 3½ lb | fights hard |
| Pike | 2–14 lb | deep water only; very strong |

Fish go in your bag as provisions. Sell them to Mags, or keep them.

## Part 6 — Saving

- **Autosaves (slot 0):** when you **travel** between London and the hills, and whenever you
  **sleep at the camp**.
- **Manual saves (slots 1–5):** press **Esc**, then **Save Game**. Each slot shows when it was
  saved, the place, your purse and your play time. Old saves can be deleted.
- **Loading:** from the pause menu or the title screen.

**What's saved:**
- where Harry is
- his purse, loot, picks, arrows and health
- the time, date and weather
- the Legend, notoriety and given total
- upgrades and camp improvements
- what's been looted (emptied safes and taken loot stay empty)

Saves are plain JSON in `%APPDATA%\Godot\app_userdata\The Thief of London\saves\`. You can
back them up or delete them there.

## Part 7 — Pause menu and settings

**Esc** pauses: *Resume, Save Game, Load Game, Settings, Quit to Title, Quit to Desktop*.

**Settings** has five tabs. Everything is saved to `settings.cfg` next to the saves.

| Tab | Options |
|---|---|
| **Graphics** | Preset (**Low / Medium / High / Ultra**), or each option: global illumination (SDFGI), reflections (SSR), ambient occlusion, indirect light (SSIL), volumetric fog, shadow resolution, render scale and view distance. Changing one option sets the preset to *Custom*. |
| **Display** | Fullscreen, V-Sync, field of view |
| **Audio** | Master, Music, Sound effects, Ambience, Voice (these are real audio buses) |
| **Gameplay** | Mouse sensitivity, invert Y, subtitles, length of a day (24–120 real minutes) |
| **Controls** | Every action, with keyboard/mouse and controller columns |

To rebind a control, click its button and press the new key, mouse button or pad button.
**Esc** cancels. *Reset all controls to default* restores them all.

On a slow PC start with **Low**. Its render scale of 0.67 with TAA still looks sharp.

## Part 8 — How it's built

| File | What it does |
|---|---|
| `scripts/core/progress.gd` | The Legend, notoriety, bounty, escalation, upgrades and wellbeing. The rules in Part 3 are here. |
| `scripts/economy/upgrades.gd` | The price list (`CATALOG`, `SUPPLIES`), buying, the fence's prices, and applying effects to Harry and Cinder |
| `scripts/economy/fence.gd`, `alms_box.gd`, `shop_counter.gd`, `london_trade.gd` | Mags, the poor box and Wren's counter, and where they stand in London |
| `scripts/world/wanted_posters.gd`, `street_patrols.gd` | Posters and extra constables as notoriety rises |
| `scripts/fishing/fishing_session.gd`, `fishing_spot.gd` | The fishing rules and the float |
| `scripts/core/save_game.gd`, `scripts/core/game_state.gd` | Save slots, autosave, loading |
| `scripts/core/game_settings.gd` | Settings, presets, key rebinding, `settings.cfg` |
| `scripts/ui/main_menu.gd`, `pause_menu.gd`, `save_load_menu.gd`, `settings_menu.gd`, `ledger_panel.gd`, `choice_menu.gd`, `ui_kit.gd` | All menus, built in code in one Victorian style |

**Handy tweaks:**
- **Prices:** edit `CATALOG` in `upgrades.gd` (in pence: 240 = £1).
- **How fast notoriety fades:** `NOTORIETY_DECAY_PER_DAY` in `progress.gd`.
- **Fish:** the `SPECIES` table in `fishing_session.gd` (name, weights, strength, price per lb).
  The tension band is `TENSION_LOW` / `TENSION_HIGH`.

## Part 9 — Tests

- `tests/test_progression.gd` (54 checks) covers:
  - the Legend and ranks, notoriety, bounty, escalation, posters and patrols
  - the fence, the poor box and the shop
  - every upgrade's effect
  - arrest fines
  - settings, presets and rebinding
  - saving, loading and the autosave on travel
  - the menus
- `tests/test_fishing.gd` (22 checks) covers:
  - fishing from the jetty: cast, bite, strike, landing, snapping, slack line, missing the strike, walking away, pike on long casts
  - the camp improvements, and sleeping with the bunks built

Run everything with `tests/run_tests.sh <path to godot>`.
