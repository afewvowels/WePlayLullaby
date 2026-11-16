# WePlay: Lullaby — Crowd Control Equipment (`WePlayLullaby`)

![WePlay: Lullaby](thumbnail.png)

A gramophone backpack that sings nearby enemies to sleep. Biters and spitters close by fall asleep, spitters further out are lured in, and worms are hushed. Sleepers wake in fits and starts and creep closer, so you get total freedom to stand around... for a few seconds.

- **Factorio:** 2.1
- **Dependencies:** base ≥ 2.1.0 (Space Age not required)
- **Current version:** 0.5.5

## In game

Lullaby wakes up as soon as any biter or spitter is within 20 tiles, so it's already singing when charging biters arrive, and they're stopped right at the edge of the sleep radius. It pulses once a second and winds down about half a second after the last one is out of range. Worms alone don't wake it up, but they're hushed while it plays.

| Layer | Radius | Who | What happens |
|---|---|---|---|
| Sleep | 9 tiles | Biters and spitters | Held in place, twitching. Each pulse they may scuttle 2 tiles closer; the chance builds every pulse they stay put (faster for bigger enemies). |
| Siren song | 20 tiles | Spitters | Entranced too, and drawn in toward you until they're in the sleep layer. They can't fire while entranced. |
| Worm hush | 50 tiles | Worms | Stop firing while you're in range and the song lasts. |

A biter that falls asleep 9 tiles out takes about 12–22 seconds to reach you; behemoths about 9–14. Spitters creep all the way in too, to point blank (2 tiles, 3 in a vehicle). Entranced enemies won't glide through walls, buildings, trees, rocks or water.

**Full wake:** an enemy wakes fully when it creeps to point blank, when its trance wears off (30 s by default, however far it got), when you move away and leave it behind, or when the song stops. It then ignores Lullaby for the immunity time (30 s by default).

**Missed pulse:** each pulse costs power (15 kJ plus 4 kJ for every enemy held, lured or hushed). If the module doesn't have enough for a pulse, the record scratches and everyone wakes at once.

**One per grid:** a second Lullaby placed in the same grid is handed back. If you're in a vehicle with one and wear one too, only one plays: the higher quality one, or the vehicle's if they match.

### Look and sound

- A gold twisted sunburst of rays, streaky like brushed light near you and solid toward their ends, turns slowly around you like projected light, drawn over ore, rocks and trees and warped as if cast over bumpy ground, with ragged edges and drifting, smoky patches of light. It falls off like real light (inverse square), brightest near you and fading out at the sleep radius, and the half behind you (toward the top of the screen) fades and goes soft, for a sense of depth. Its twist swings one way, then back, and each pulse sends a jagged wave from the centre to the edge, with a soft swell of light and a gold glow. The rays glow onto what's underneath them: a soft bloom by day, and at night they actually light up the ground, buildings and biters beneath them.
- Entranced enemies get a light blue swirl over their heads that spins faster as they get ready to scuttle.
- A brass pad played like an old record: swells in, a sub-bass thrum on each pulse, runs down like a turntable losing power, and scratches on a missed pulse.

## Player settings

Each player sets these for themselves.

| Setting | Default | What it does |
|---|---|---|
| Lullaby sounds | On | Hear the music, pulses and record scratch. |
| Lullaby visual effects | On | See the rays, glow and night light. The effect still works with this off, and the swirls over entranced enemies always show. |

## Map settings

| Setting | Default | Range | What it does |
|---|---|---|---|
| Longest trance (seconds) | 30 | 5 – 300 | An entranced biter or spitter wakes fully after this long, so backing away can't keep a crowd under forever. Scuttles don't reset it. |
| Immunity after waking (seconds) | 30 | 0 – 60 | How long a fully woken enemy ignores the lullaby. 0 turns it off. |
| Worms can be re-entranced | Off | On / Off | Off: each worm is hushed once. On: worms can be hushed again after their immunity. |
| Pulse brightening (%) | 50 | 0 – 100 | How much the rays and glow brighten on each pulse (a soft swell once a second). 0 turns it off for a steady glow. |

| Disable effect cooldown (testing) | Off | On / Off | No immunity, and worms can be hushed again. Turning it on clears all current immunities. |

**Light sensitivity:** while Lullaby is playing, its light brightens softly once a second. If you're sensitive to pulsing light, set Pulse brightening to 0 for a steady glow, or turn off Lullaby visual effects in your player settings.

## Getting it

Research **Lullaby** after Modular armor, Circuit network, Advanced circuit and Military 2 (200 × automation, logistic and military science, 30 s each).

| Recipe | |
|---|---|
| Ingredients | 1 × Programmable speaker, 10 × Advanced circuit, 5 × Steel plate |
| Crafting time | 10 s |
| Equipment size | 2 × 2 |
| Power | 1 MJ buffer, charges at up to 400 kW |

## How it works

- **Equipment:** a `battery-equipment` that only charges (`output_flow_limit = 0W`). The script spends its energy on each pulse.
- **Wearers:** each connected player's armor grid and current vehicle grid are checked; the best Lullaby is used and centred on the vehicle if driving, otherwise the character. Idle wearers are scanned every 10 ticks for any enemy unit within the lure radius. While active, the sleep layer's edge is checked every 3 ticks (catching biters up to a tile outside it) and the whole lure layer every 15.
- **Holding:** entranced units are kept as real units, disabled with `disabled_by_script` (falls back to `active`). They keep their health, resistances, unit number and corpse, and turrets can still shoot them. Twitches are small scripted teleports. Scuttles and spitters being drawn in are real walks so the walk animation plays: the unit is re-enabled with a `go_to_location` (distraction off), watched every tick, and frozen again as soon as it has gone far enough, reaches point blank, or runs out of time. A walk that makes no progress for 8 ticks finishes as a scripted glide, and gliding skips any step into something solid (water tile, or anything on the `player` collision layer that isn't a unit or vehicle). Set `WALK = false` in `balance.lua` to glide everything.
- **Spitters:** units with a stream attack or range over 4 are entranced anywhere in the lure layer and glide in at 0.05 tiles per tick until they're in the sleep layer.
- **Worms:** enemy `turret` entities in range are disabled by script while hushed.
- **Bookkeeping:** `storage.claimed` stops two wearers grabbing the same enemy; `storage.immune` holds immunity end ticks; `storage.worms_done` remembers hushed worms when re-entrancing is off (cleared when a worm is destroyed).
- **Visuals:** `rendering.draw_animation` for the rays (40 frames, one loop per 2 pulses, offset so frame 0 lands on a beat; rotation and the bumpy warp are baked in; additive blend; first render layer that works from `higher-object-under`, `object`, `decals`) and swirls (16 frames), `rendering.draw_light` for the glow. A blurred, half-resolution copy of the rays (`wp-lullaby-rays-bloom`, same 40 frames and timing, additive) gives the daylight bloom; a 20-frame ray-shaped light (`wp-lullaby-ray-light-0..19`, swapped by script every 6 ticks) lights up what's under the rays at night.
- **Sound:** pulse chunks are 70 ticks (60 + 5-tick fades) and start 5 ticks before each beat, so they crossfade. The start sound is 35 ticks and hands over to the first pulse; the stop sound takes the next pulse's slot.

Balance and tuning numbers live in `balance.lua`.

### Not in this first pass

- Bubble Gun-style sprite swap and struggle animation (sleepers twitch in place instead).
- Spidertrons driven by remote, and grids filled by robots (only player-placed duplicates are handed back).
- Research or quality bonuses.
- Pentapods and demolishers aren't affected.

## Tools (not in the zip)

Need Python with numpy, pillow and scipy (`pip install numpy pillow scipy`), plus ffmpeg on your PATH for the sounds. Run from anywhere; outputs go next to the scripts' parent folder.

- `python tools/lullaby_rays.py`: builds the ray, bloom and light sheets into `graphics/entity` (or `... sheet|bloom|light [out.png]` for one). Then run `python tools/lullaby_styles.py streaks` to give the rays their streaky look (the shipped style).
- `python tools/lullaby_styles.py halftone|streaks`: replaces the rays with the halftone dots or the fine-line streaks (run `lullaby_rays.py sheet` to go back to solid).
- `python tools/lullaby_swirl.py`: builds the swirl into `graphics/entity` (`--variants` adds the double and tight versions).
- `python tools/lullaby_sounds.py path/to/Brass_Swell_5.wav`: builds the sounds into `sounds`.

## Made with AI

AI was used heavily in the production of this mod. The code, documentation and portal description were written with Claude (Anthropic's AI assistant). The equipment icon, technology icon and thumbnail were generated with Grok. The rays, glow and swirls are made by Python scripts rather than drawn, and the sounds were cut and processed from a licensed stock clip by another script; those scripts were also written with AI. The design is directed, and every version played, tested and tuned in game, by the author.

## Credits

- The equipment icon, technology icon and thumbnail were made with AI image generation (Grok).
- The ground rays and swirls were drawn procedurally for this mod.
- Sounds were built from an Envato Elements asset ("Brass Swell 5"), reworked into a swell-in, crossfading pulse loops with a sub-bass thrum, a turntable run-down and a record scratch. The sound files are used under the Envato Elements licence and are not covered by the Unlicense.

## Licence

Code released under the Unlicense (the sound files stay under their Envato Elements licence).
