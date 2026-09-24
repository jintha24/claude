# Phase 5 — Day and Night, and Everybody's Daily Routine

Time now passes. **One in-game day lasts 48 real minutes.** The story begins on
**Thursday 20 September 1866 at 4 pm**, and the whole town follows the clock.

---

## Part 1 — What happens over a day

| Time | The street and the market |
|---|---|
| **5–7 am** | Dawn. The lamps go out one by one. The day shift of constables walks out from the station at 6. A few early risers appear. |
| **6:30 am** | Traders come out of the surrounding doors and set up their stalls. |
| **8 am – noon** | People leave their houses for work. The market fills and is busiest from about 10 until mid-afternoon (30 shoppers). |
| **Afternoon** | Shopping, browsing and chatting. Shoppers sometimes stop to talk; they're easier to rob when they're deep in conversation. |
| **6 pm** | Change of shift: the day constables walk back to the station, and the **night watch arrives a few minutes later with bullseye lanterns**. That gap is your window. |
| **6:30 pm** | Traders pack up and go home. The market thins out. |
| **Dusk** | The **lamplighter's round**: the gas lamps light up one after another, and lamplight appears in the windows. |
| **7–11 pm** | People head for the pubs (the Crown & Anchor, the Ten Bells, the White Hart). The streets quieten. |
| **Midnight – 1:30 am** | Closing time: drunks weave home, singing "Champagne Charlie" (the music-hall hit of 1866). |
| **2–5 am** | Almost nobody about. Most windows are dark. Only the night watch walks its beats. |

Everyone comes out of, and goes back into, a real **door**: houses, shops and pubs. Nobody
pops into existence in front of you.

### The sky
- **The sun** follows its real path for London (51.5° N) on the current date. Near the September
  equinox it's about 39° high at noon, rises at about 6 am and sets at about 6 pm. In winter it
  barely clears the rooftops.
- Its light turns golden when low and deep red at sunset.
- **The moon** gives a faint cold blue light at night, with soft shadows, and there are stars in
  the sky.
- The haze warms at sunrise and sunset and turns blue-black at night.

### What it means for stealth
- The daylight level feeds straight into the stealth system. At night everything between the
  lamps is dark and guards see much less far.
- **Gas lamps** make pools of light. Stay out of them, or put them out with a blunt arrow. A
  broken lamp stays dark until it's mended the next day.
- **Bullseye lanterns** carried by the night watch are real beams. Stepping into one lights you
  up as brightly as standing under a lamp.
- Pickpocketing is easier at night.

### Performance
Only the **6 lamps nearest the camera cast shadows** (all of them give light). This keeps nights
fast even with 20 lamps lit.

---

## Part 2 — Controls and settings

- **Tab (hold):** shows the pocket-watch clock and date (top centre). The clock also appears for
  a few seconds on every hour.
- **F6 (debug builds only):** skip forward one hour, to test different times quickly. It's
  disabled in the exported game.
- **Change the pace:** in `scripts/core/game_clock.gd` set `real_minutes_per_game_day` (48 by
  default). The Settings menu gets a slider in Phase 9.
- **Change the start date/time:** `start_year`, `start_month`, `start_day` and `minutes`
  (minute of the day) at the top of the same file.
- **Crowd density:** select **Population** in `main.tscn` and set **Density** (1.0 = normal).
  The hourly crowd curves are at the top of `scripts/npc/population.gd`.
- **Shift times:** `SHIFT_START_DAY`, `SHIFT_START_NIGHT` and `RELIEF_DELAY_MINUTES` in
  `scripts/world/street_patrols.gd`.

---

## Part 3 — How it's built

| File | Role |
|---|---|
| `scripts/core/game_clock.gd` | The clock and calendar. Signals `hour_passed`, `day_passed`, and `time_jumped` (sleeping or loading makes everything catch up at once). |
| `scripts/world/day_night_cycle.gd` | Sun and moon positions, light colours, stars, fog tint, stealth darkness, lamps (with the lamplighter's delays and the shadow budget) and lit windows. |
| `scripts/npc/population.gd` | Spawns and sends home traders, shoppers, passers-by, pub-goers and drunks by the hour, always through doors. |
| `scripts/world/street_patrols.gd` | Day and night rosters, shift changes, and the relief gap. |
| `scripts/npc/civilian.gd` | New behaviours: travel to a place, go indoors, chat in pairs, and walk home drunk. |
| `scripts/world/building_facade.gd` | Every front door is a marker (`npc_doors` group) with a kind: house, shop or pub. Windows belong to three lamplight groups. |

---

## Part 4 — Tests

`tests/test_daynight.gd` adds 30 checks:
- **Clock:** the date and weekday are correct (20 September 1866 was a Thursday), the clock
  format, and the 48-minute day.
- **Sun:** the real solar maths (noon height, sunrise at about 6, due south at noon).
- **Light:** sun and moon behave by day and night, and the stealth darkness follows them.
- **Lamps and windows:** lamps are off at noon, all lit at 10 pm and lit one by one at dusk. The
  shadow budget holds, and windows light and go dark.
- **Crowds:** a busy market at noon, and empty streets at 3 am.
- **Routines:** traders pack up at 6:30 pm, the shift changes at 6 pm with the relief arriving,
  lanterns light Harry, the pubs fill in the evening, and drunks go home at closing time.

Earlier tests now run at a fixed noon with the clock stopped, so they're unaffected by the
hour. The stealth test uses a real 10 pm night for its lamplight checks.
