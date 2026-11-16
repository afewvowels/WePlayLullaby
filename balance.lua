-- Balance numbers and tuning, shared by data.lua and control.lua.
-- First-pass values: tune in game.

local B = {}

-- Equipment
B.BUFFER = "1MJ"              -- energy buffer
B.INPUT_FLOW = "400kW"        -- how fast it charges from the grid
B.ACTIVATE_MIN = 250000       -- J needed in the buffer before it will wake up

-- Layers (tiles)
B.SLEEP_RADIUS = 9            -- biters and spitters fall asleep inside this
B.LURE_RADIUS = 20            -- spitters are entranced and drawn in from this far
B.WORM_RADIUS = 50            -- worms are hushed out to this (vanilla behemoth worm: 48)
B.WAKE_DISTANCE = 2.0         -- point blank: anything entranced this close wakes and attacks (+1 in a vehicle)

-- Timing (ticks)
B.PULSE_TICKS = 60            -- one pulse per second; must match the sounds
B.START_TICKS = 30            -- wake-up swell before the first pulse; must match start.ogg
B.SOUND_LEAD = 5              -- pulse chunks start this many ticks before the beat
B.SCAN_TICKS = 30             -- how often idle wearers look for enemies
B.IDLE_PULSES = 2             -- pulses with no biters or spitters nearby before it winds down
B.WIND_DOWN_TICKS = 50        -- rays fade out over this
B.MOVE_TICKS = 2              -- how often entranced units are moved
B.JITTER_TICKS = 4            -- how often sleepers twitch

-- Power per pulse (J)
B.PULSE_BASE = 15000          -- 15 kJ per pulse just to run the song (15 kW)
B.PULSE_PER_TARGET = 4000     -- + 4 kJ per enemy entranced or hushed (4 kW each)

-- Fits and starts (all movement is scripted; entranced units never walk on their own)
B.SCUTTLE_CHANCE = 0.05       -- chance to scuttle on the first pulse asleep
B.SCUTTLE_GROWTH = 0.09       -- added each pulse it stays put (scaled up for bigger enemies)
B.SCUTTLE_DISTANCE = 2.0      -- tiles toward the wearer per scuttle
B.SCUTTLE_SPEED = 0.1         -- tiles per tick while scuttling (a 2-tile lurch takes 20 ticks)
B.DRAW_SPEED = 0.05           -- tiles per tick while a spitter is drawn in (20 -> 9 tiles in ~3.7 s)
B.BLOCK_RADIUS = 0.35         -- entranced units won't glide into walls, buildings, trees, rocks or water
B.TIER_HEALTH = 1500          -- max health at which growth is doubled (behemoth biter: 3000 = tripled, capped)
B.TIER_MAX = 2.0              -- cap on the extra growth multiplier
B.JITTER = 0.03               -- twitch distance when deep asleep (tiles)
B.JITTER_STRUGGLE = 0.12      -- extra twitch distance as the scuttle chance rises

-- Look
B.RAY_LAYERS = {"higher-object-under", "object", "decals"}  -- first that works; above ore, rocks and trees
B.RAY_TILES_PER_SCALE = 12    -- the 384 px ray frame covers 12 tiles at scale 1
B.RAY_COLOR = {r = 1.0, g = 0.80, b = 0.43}
B.RAY_BRIGHTNESS = 0.22       -- additive brightness
B.RAY_FLASH = 0.12            -- extra brightness on each pulse (at 100% pulse flash)
B.FLASH_TICKS = 40           -- each pulse's swell rises and falls over this (soft, once a second)
B.BLOOM_BRIGHTNESS = 0.16     -- additive soft glow around the rays (daylight)
B.BLOOM_FLASH = 0.10
B.LIGHT_INTENSITY = 0.55      -- ray-shaped light (night): lights up what's under the rays
B.LIGHT_FLASH = 0.2
B.GLOW_COLOR = {r = 1.0, g = 0.82, b = 0.5}
B.GLOW_SCALE = 4              -- soft round light on the wearer
B.GLOW_INTENSITY = 0.3
B.GLOW_FLASH = 0.12
B.SWIRL_COLOR = {r = 0.59, g = 0.84, b = 1.0}
B.SWIRL_SCALE = 0.42
B.SWIRL_SPEED = 0.25          -- frames per tick when deep asleep
B.SWIRL_SPEED_STRUGGLE = 0.75 -- extra speed as the scuttle chance rises

return B
