# Phase 6 — Dynamic Weather

London's weather now changes by itself: **clear, overcast, rain, thunderstorms, thick London
fog, and snow in winter.** Every change blends in over about 12 in-game minutes, so nothing ever
switches abruptly. The weather shows under the clock (hold **Tab**).

---

## Part 1 — What you'll see

| | |
|---|---|
| **Rain** | Streaks that slant with the wind, stop on roofs and awnings (not through them) and splash where they land. The streets darken and turn glossy within about 10 minutes, so SSR reflects every gas lamp in the wet cobbles. **Puddles** fill the dips, and dry out long after the sheen has gone. |
| **Thunderstorms** | Heavy rain, a dark sky, lightning flashes and thunder (*"Thunder rolls over the rooftops"*). |
| **London fog** | The "pea-souper": thick, yellow-grey coal-smoke fog. Beyond 15–20 m the street disappears. |
| **Snow** (December to February only) | Slow drifting flakes. The cobbles, pavements and slate roofs gradually whiten. |
| **Overcast** | A drifting cloud layer, dimmer sun and duller light. |
| **Wind** | Chimney smoke leans with it, and the washing lines across the yard flap harder in a gale. Trees and grass in Phase 8 use the same wind. |

---

## Part 2 — What it does to the game

| Effect | Details |
|---|---|
| **Rain masks your footsteps** | Guards hear you from up to 55% less far in a downpour. A thunderclap drowns out everything for a few seconds. |
| **Rain and fog cut sight** | Rain shortens sight lines by up to 30%. Thick fog cuts them by 70%: a constable 14 m away can't see you at all. |
| **Wet roofs are slippery** | On a wet slope Harry loses grip and slides slowly downhill; stand still on soaking slates and you'll creep towards the edge. Slate and metal are the worst, then timber, then stone. **Sprinting across wet slates can end in a stumble and a slide.** Lying snow is just as treacherous. |
| **Fewer people out** | Crowds drop to a quarter in a storm and thin out in fog or snow. Fewer pickpocket marks, but fewer witnesses too. |
| **Umbrellas and shelter** | Ladies and gentlemen put up black umbrellas. Working people hurry under shop awnings and market-stall canvas, or go indoors, and come out again when the rain eases. Traders stay under their stall awnings. |
| **Darker days** | Heavy cloud dims both the sunlight and the general light level, so there's more shadow to hide in. |

---

## Part 3 — Controlling the weather

- **Automatic:** the weather moves on every 1–4 in-game hours along believable successions: fog
  tends to come on still mornings, and storms clear through rain.
- **From code or missions (Phase 10):**
  ```gdscript
  Weather.automatic = false                     # hold the weather
  Weather.set_weather(Weather.Kind.FOG)         # blend to fog
  Weather.set_weather(Weather.Kind.STORM, true) # instantly (e.g. when loading a save)
  ```
  Mission 15 (*The City Hides Its Fox*) uses a fog lockdown. Mission 20 (*The Winter Ball*) uses a
  snowstorm.
- **Tuning** (top of `scripts/core/weather.gd`):
  - `PROFILES`: cloud, rain, fog, snow and wind values for each kind.
  - `NEXT`: what tends to follow what.
  - `transition_minutes`: how long a change takes to blend in.
- **Effect strengths:**
  - Hearing and sight: bottom of `Weather._process`.
  - Crowd sizes: `population_factor()`.
  - Roof slipperiness: `Harry._wet_slip()`.
  - Wet-surface gloss per material: `WET_RESPONSE` in `material_library.gd`.

---

## Part 4 — How it's built

| File | Role |
|---|---|
| `scripts/core/weather.gd` | The weather state, smooth blending, wetness, puddles, lying snow, lightning, and effects on the senses. |
| `scripts/world/weather_effects.gd` | Rain (height-field collision and splashes), snow, the cloud layer, puddle decals, wet materials, wind, and lightning flashes. |
| `scripts/world/day_night_cycle.gd` | The sun and sky dimmed by cloud, and fog density and colour. |
| `scripts/npc/civilian.gd`, `npc_body.gd` | Umbrellas, and sheltering under awnings. |
| `scripts/player/harry.gd` | Slipping on wet slopes. |
| `project.godot` → Shader Globals | `wind_strength` and `wind_direction`, readable by any shader (washing lines now, trees and grass in Phase 8). |

**Renderer note:** rain stopping at roofs uses GPU particle collision, and puddles are Decals.
Both need the Forward+ renderer (the project default).

---

## Part 5 — Tests

`tests/test_weather.gd` adds 21 checks:
- Blending: gradual, never abrupt; the storm arrives in full.
- Senses: rain masks hearing and shortens sight.
- Surfaces: the streets soak, cobbles turn glossy, puddles form and then dry more slowly than
  the sheen.
- Rain particles fall, and the sun dims under storm clouds.
- Wind: chimney smoke follows it, and the washing lines are strung.
- Storms: lightning flashes.
- People: far fewer shoppers in a storm, and people shelter or use umbrellas.
- Roofs: Harry slides on a wet slate roof but stays put on a dry one.
- Fog blinds a constable at 14 m.
- Snow only in winter, and the weather changes by itself over the hours.

This phase also made the constables' eyesight more realistic: daylight shade no longer shortens
their sight range, and only real darkness does. The suite now has **150 checks**, all passing.
