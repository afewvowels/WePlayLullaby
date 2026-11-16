-- WePlay: Lullaby — Crowd Control Equipment
--
-- One Lullaby per wearer sings in pulses (once a second) while enemies are near:
--   sleep layer  (B.SLEEP_RADIUS): biters and spitters are frozen in place, twitching.
--                Each pulse they may scuttle a little closer; the chance builds every
--                pulse they stay put. Within B.WAKE_DISTANCE = full wake.
--   lure layer   (B.LURE_RADIUS):  spitters are entranced too and drawn in, gliding
--                toward the wearer until they're in the sleep layer.
--   worm hush    (B.WORM_RADIUS):  worms stop firing while the song lasts.
-- All movement while entranced is scripted (the unit stays disabled), so nothing
-- can attack or overshoot. A full wake (reached the wearer, left behind, or the
-- field dropped) makes an enemy immune for the immunity setting. A missed pulse
-- (not enough energy) wakes everyone.

local B = require("balance")

local EQUIPMENT = "wp-lullaby-equipment"
local RAYS = "wp-lullaby-rays"
local BLOOM = "wp-lullaby-rays-bloom"
local RAYS_B = "wp-lullaby-rays-b"
local BLOOM_B = "wp-lullaby-rays-b-bloom"
local LIGHT_PREFIX = "wp-lullaby-ray-light-"
local LIGHT_FRAMES = 20
local SWIRL = "wp-lullaby-swirl"
local RAY_FRAMES = 40
local RAY_LOOP = 2 * B.PULSE_TICKS
local SWIRL_FRAMES = 16

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------

local function init_storage()
  storage.wearers = storage.wearers or {}       -- player index -> wearer state
  storage.claimed = storage.claimed or {}       -- unit number -> player index holding it
  storage.immune = storage.immune or {}         -- unit number -> tick the immunity ends
  storage.worms_done = storage.worms_done or {} -- unit number -> true (re-entrancing off)
  storage.proto = storage.proto or {}           -- prototype name -> {ranged, growth}
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Testing: no immunity at all, and worms can be hushed again right away.
local function cooldown_disabled()
  return settings.global["wp-lullaby-disable-cooldown"].value
end

local function immunity_ticks()
  if cooldown_disabled() then return 0 end
  return settings.global["wp-lullaby-immunity-seconds"].value * 60
end

local function flash_strength()
  return settings.global["wp-lullaby-pulse-flash"].value / 100
end

local function worm_reentrance()
  return cooldown_disabled() or settings.global["wp-lullaby-worm-reentrance"].value
end

local function dist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function set_disabled(e, value)
  if not (e and e.valid) then return end
  if not pcall(function() e.disabled_by_script = value end) then
    pcall(function() e.active = not value end)
  end
end

local function command(e, cmd)
  if not (e and e.valid) then return end
  local c = e.commandable
  if c and c.valid then pcall(c.set_command, cmd) end
end

local function destroy(obj)
  if obj and obj.valid then obj.destroy() end
end

local function proto_info(e)
  local name = e.name
  local info = storage.proto[name]
  if info then return info end
  local p = e.prototype
  local ap = p.attack_parameters
  local range = (ap and ap.range) or 1
  local ranged = ap ~= nil and (ap.type == "stream" or range > 4)
  local ok, health = pcall(function() return p.get_max_health() end)
  if not ok or not health then
    ok, health = pcall(function() return p.max_health end)
    if not ok or not health then health = 100 end
  end
  local tier = math.min(B.TIER_MAX, health / B.TIER_HEALTH)
  info = {ranged = ranged, growth = B.SCUTTLE_GROWTH * (1 + tier)}
  storage.proto[name] = info
  return info
end

local function is_immune(un, tick)
  local t = storage.immune[un]
  if t and t > tick then return true end
  if t then storage.immune[un] = nil end
  return false
end

local function enemy_forces(force)
  local out = {}
  for _, f in pairs(game.forces) do
    if force.is_enemy(f) then out[#out + 1] = f end
  end
  return out
end

-- The grid with the best Lullaby for this player: highest quality, vehicle wins ties.
local function find_source(player)
  local best, best_level, best_vehicle
  local function consider(grid, is_vehicle)
    if not (grid and grid.valid) then return end
    local eq = grid.find(EQUIPMENT)
    if not eq then return end
    local level = eq.quality and eq.quality.level or 0
    if not best or level > best_level or (level == best_level and is_vehicle and not best_vehicle) then
      best, best_level, best_vehicle = eq, level, is_vehicle
    end
  end
  local character = player.character
  if character and character.valid then consider(character.grid, false) end
  local vehicle = player.vehicle
  if vehicle and vehicle.valid then consider(vehicle.grid, true) end
  if not best then return nil end
  local center = (vehicle and vehicle.valid) and vehicle or character
  if not (center and center.valid) then return nil end
  return best, center
end

local function wake_distance(w)
  return B.WAKE_DISTANCE + (w.center.type == "character" and 0 or 1)
end

-- Would an entranced unit bump into something solid at p? (walls, buildings, trees,
-- rocks, cliffs, water). Other units don't block.
local function blocked(e, p)
  local surface = e.surface
  local tile = surface.get_tile(p.x, p.y)
  if tile and tile.valid then
    local ok, collides = pcall(tile.collides_with, "player")
    if ok and collides then return true end
  end
  for _, o in pairs(surface.find_entities_filtered({position = p, radius = B.BLOCK_RADIUS, collision_mask = "player"})) do
    if o ~= e and o.type ~= "unit" and o.type ~= "character" and o.type ~= "car" and o.type ~= "spider-vehicle" then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Per-player sound and graphics settings
---------------------------------------------------------------------------

local function player_wants(player, setting)
  local ok, value = pcall(function() return player.mod_settings[setting].value end)
  return not ok or value ~= false
end

-- Who sees the effects: {all = true}, {none = true}, or {list = {player indices}}.
-- Cached; rebuilt when a setting changes or a player joins or leaves.
local view_cache
local function viewers()
  if view_cache then return view_cache end
  local list, everyone = {}, true
  for _, player in pairs(game.connected_players) do
    if player_wants(player, "wp-lullaby-graphics") then
      list[#list + 1] = player.index
    else
      everyone = false
    end
  end
  if everyone then view_cache = {all = true, list = list}
  elseif #list == 0 then view_cache = {none = true}
  else view_cache = {list = list} end
  return view_cache
end

-- New objects are visible to everyone by default, so they only need changing when
-- someone has graphics off. Existing objects (refresh) always get an explicit list.
local function apply_view(obj, refresh)
  if not (obj and obj.valid) then return obj end
  local v = viewers()
  if v.none then
    obj.visible = false
  elseif v.all and not refresh then
    return obj
  else
    obj.visible = true
    obj.players = v.list
  end
  return obj
end

---------------------------------------------------------------------------
-- Swirl over entranced enemies
---------------------------------------------------------------------------

local function draw_swirl(e)
  local box = e.prototype.selection_box
  local top = box and box.left_top and box.left_top.y or -0.8
  local size = box and (box.right_bottom.x - box.left_top.x) or 1
  local scale = B.SWIRL_SCALE * math.max(0.8, math.min(1.6, size))
  -- Swirls are gameplay information (who's entranced), so everyone always sees them,
  -- whatever their visual effects setting.
  return rendering.draw_animation({
    animation = SWIRL,
    target = {entity = e, offset = {0, top - 0.55 * scale * 2}},
    surface = e.surface,
    x_scale = scale,
    y_scale = scale,
    tint = B.SWIRL_COLOR,
    render_layer = "air-object",
    animation_speed = B.SWIRL_SPEED,
    animation_offset = math.random(0, SWIRL_FRAMES - 1),
  })
end

local function trance_ticks()
  return settings.global["wp-lullaby-max-trance-seconds"].value * 60
end

-- How close an entranced enemy is to breaking free (0..1): whichever is further
-- along, its scuttle chance or its time in the trance.
local function struggle(rec)
  local by_chance = math.min(1, (rec.chance or 0) / 0.6)
  local by_time = rec.since and math.min(1, (game.tick - rec.since) / trance_ticks()) or 0
  return math.max(by_chance, by_time ^ 2)
end

local function set_swirl_speed(rec)
  local s = rec.swirl
  if s and s.valid then
    s.animation_speed = B.SWIRL_SPEED + B.SWIRL_SPEED_STRUGGLE * struggle(rec)
  end
end

---------------------------------------------------------------------------
-- Ground effect and glow
---------------------------------------------------------------------------

local function ray_tint(level, color)
  -- The ray animations use additive blending, so the tint is just brightness.
  local c = color or B.RAY_COLOR
  return {r = c.r * level, g = c.g * level, b = c.b * level, a = level}
end

local function ray_scale()
  return (2 * B.SLEEP_RADIUS + 2) / B.RAY_TILES_PER_SCALE
end

local function draw_rays(w, animation, scale)
  -- Frame 0 of the loop lands on the first beat.
  local offset = (-(w.first_beat % RAY_LOOP) * RAY_FRAMES / RAY_LOOP) % RAY_FRAMES
  local args = {
    animation = animation,
    target = w.center,
    surface = w.center.surface,
    x_scale = scale,
    y_scale = scale,
    tint = ray_tint(0),
    animation_speed = RAY_FRAMES / RAY_LOOP,
    animation_offset = offset,
  }
  for _, layer in pairs(B.RAY_LAYERS) do
    args.render_layer = layer
    local ok, obj = pcall(rendering.draw_animation, args)
    if ok and obj then return apply_view(obj) end
  end
end

local function draw_glow(w)
  return apply_view(rendering.draw_light({
    sprite = "utility/light_medium",
    target = w.center,
    surface = w.center.surface,
    scale = B.GLOW_SCALE,
    intensity = 0,
    minimum_darkness = 0,
    color = B.GLOW_COLOR,
  }))
end

local function light_frame(w, tick)
  local t = (tick - w.first_beat) % RAY_LOOP
  return math.floor(t * LIGHT_FRAMES / RAY_LOOP) % LIGHT_FRAMES
end

local function draw_ray_light(w)
  w.light_frame = light_frame(w, game.tick)
  return apply_view(rendering.draw_light({
    sprite = LIGHT_PREFIX .. w.light_frame,
    target = w.center,
    surface = w.center.surface,
    -- the 192 px light covers 6 tiles at scale 1; match the 384 px rays
    scale = ray_scale() * 2,
    intensity = 0,
    minimum_darkness = 0.3,
    color = B.RAY_COLOR,
  }))
end

local function draw_all(w)
  w.rays = draw_rays(w, RAYS, ray_scale())
  w.bloom = draw_rays(w, BLOOM, ray_scale() * 2)
  if B.TWO_COLOR then
    w.rays_b = draw_rays(w, RAYS_B, ray_scale())
    w.bloom_b = draw_rays(w, BLOOM_B, ray_scale() * 2)
  end
  w.ray_light = draw_ray_light(w)
  w.glow = draw_glow(w)
end

local function destroy_all(w)
  destroy(w.rays); destroy(w.bloom); destroy(w.ray_light); destroy(w.glow)
  destroy(w.rays_b); destroy(w.bloom_b)
end


local function update_visuals(w, tick)
  local level = 1
  if tick < w.first_beat then
    level = 1 - (w.first_beat - tick) / B.START_TICKS
  end
  if w.fade_from then
    level = math.max(0, 1 - (tick - w.fade_from) / B.WIND_DOWN_TICKS)
  end
  level = math.max(0, math.min(1, level))
  -- Pulse swell: a soft rise and fall (no sharp spike), scaled by the map setting.
  local since = tick - (w.last_beat or -1000)
  local flash = 0
  if since >= 0 and since < B.FLASH_TICKS then
    flash = math.sin(math.pi * since / B.FLASH_TICKS) ^ 2 * flash_strength()
  end
  if w.rays and w.rays.valid then
    w.rays.color = ray_tint(level * (B.RAY_BRIGHTNESS + B.RAY_FLASH * flash))
  end
  if w.bloom and w.bloom.valid then
    w.bloom.color = ray_tint(level * (B.BLOOM_BRIGHTNESS + B.BLOOM_FLASH * flash))
  end
  local kb = level * B.RAY_B_STRENGTH
  if w.rays_b and w.rays_b.valid then
    w.rays_b.color = ray_tint(kb * (B.RAY_BRIGHTNESS + B.RAY_FLASH * flash), B.RAY_COLOR_B)
  end
  if w.bloom_b and w.bloom_b.valid then
    w.bloom_b.color = ray_tint(kb * (B.BLOOM_BRIGHTNESS + B.BLOOM_FLASH * flash), B.RAY_COLOR_B)
  end
  if w.ray_light and w.ray_light.valid then
    local f = light_frame(w, tick)
    if f ~= w.light_frame then
      w.light_frame = f
      w.ray_light.sprite = LIGHT_PREFIX .. f
    end
    w.ray_light.intensity = level * (B.LIGHT_INTENSITY + B.LIGHT_FLASH * flash)
  end
  if w.glow and w.glow.valid then
    w.glow.intensity = level * (B.GLOW_INTENSITY + B.GLOW_FLASH * flash)
  end
end

---------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------

local function claim(un, w) storage.claimed[un] = w.player_index end
local function unclaim(un) storage.claimed[un] = nil end

-- Wake a unit fully: it shrugs off the song for the immunity time and comes for the wearer.
local function full_wake_unit(w, un, rec, attack)
  destroy(rec.swirl)
  local e = rec.entity
  if e and e.valid then
    set_disabled(e, false)
    local imm = immunity_ticks()
    if imm > 0 then storage.immune[e.unit_number] = game.tick + imm end
    if attack and w.center and w.center.valid then
      command(e, {type = defines.command.attack, target = w.center, distraction = defines.distraction.by_enemy})
    end
  end
  unclaim(un)
end

local function release_worm(w, un, rec)
  destroy(rec.swirl)
  local e = rec.entity
  if e and e.valid then
    set_disabled(e, false)
    if worm_reentrance() then
      local imm = immunity_ticks()
      if imm > 0 then storage.immune[un] = game.tick + imm end
    else
      storage.worms_done[un] = true
      script.register_on_object_destroyed(e)
    end
  end
  unclaim(un)
end

local function worm_eligible(un, tick)
  if storage.claimed[un] then return false end
  if worm_reentrance() then return not is_immune(un, tick) end
  return not storage.worms_done[un]
end

local function entrance(w, e)
  local rec = {
    entity = e,
    home = e.position,
    chance = B.SCUTTLE_CHANCE,
    since = game.tick,      -- when the trance started (scuttles don't reset it)
    scuttle_left = 0,
    drawing = false,
    swirl = draw_swirl(e),
  }
  command(e, {type = defines.command.stop, distraction = defines.distraction.none})
  set_disabled(e, true)
  set_swirl_speed(rec)
  w.held[e.unit_number] = rec
  claim(e.unit_number, w)
  return rec
end

-- Move an entranced unit up to `step` tiles toward the wearer. Returns the distance moved.
local function glide(w, rec, step)
  local e = rec.entity
  local c = w.center.position
  local p = rec.home
  local d = dist(p, c)
  local wake = wake_distance(w)
  if d <= wake then return 0 end
  step = math.min(step, d - wake + 0.05)
  local dest = {x = p.x + (c.x - p.x) / d * step, y = p.y + (c.y - p.y) / d * step}
  if blocked(e, dest) then return 0 end
  e.teleport(dest)
  rec.home = dest
  return step
end

-- Let an entranced unit walk (so its walk animation plays) up to `distance` tiles
-- toward the wearer, with distraction off. It's watched every tick and frozen again
-- the moment it has gone far enough, gets to point blank, stalls or runs out of time.
-- With B.WALK off, or if it stalls, it glides the rest of the way instead.
local function start_move(w, rec, distance)
  local e = rec.entity
  local p, c = e.position, w.center.position
  local d = dist(p, c)
  distance = math.min(distance, d - wake_distance(w) + 0.05)
  if distance < 0.05 then return end
  if not B.WALK then
    rec.scuttle_left = distance
    return
  end
  local dest = {x = p.x + (c.x - p.x) / d * distance, y = p.y + (c.y - p.y) / d * distance}
  set_disabled(e, false)
  command(e, {type = defines.command.go_to_location, destination = dest, radius = 0.25,
              distraction = defines.distraction.none})
  rec.walk = {start = p, left = distance, last_d = d, stall = 0,
              ends = game.tick + math.ceil(distance / B.WALK_MIN_SPEED) + 10}
end

local function stop_walk(rec, glide_rest)
  local e = rec.entity
  local walk = rec.walk
  rec.walk = nil
  command(e, {type = defines.command.stop, distraction = defines.distraction.none})
  set_disabled(e, true)
  rec.home = e.position
  if glide_rest then
    rec.scuttle_left = math.max(0, walk.left - dist(e.position, walk.start))
  end
end

local function update_walk(w, rec, tick)
  local e = rec.entity
  local walk = rec.walk
  local p = e.position
  local dc = dist(p, w.center.position)
  if dc < walk.last_d - 0.005 then walk.stall = 0 else walk.stall = walk.stall + 1 end
  walk.last_d = dc
  if dist(p, walk.start) >= walk.left - 0.05 or dc <= wake_distance(w) or tick >= walk.ends then
    stop_walk(rec, false)
  elseif walk.stall >= B.WALK_STALL_TICKS then
    stop_walk(rec, true)   -- blocked or wandering off: glide the rest
  end
end

---------------------------------------------------------------------------
-- Wearer lifecycle
---------------------------------------------------------------------------

local function count_targets(w)
  return table_size(w.held) + table_size(w.worms)
end

local function release_all(w, attack)
  for un, rec in pairs(w.held) do full_wake_unit(w, un, rec, attack) end
  for un, rec in pairs(w.worms) do release_worm(w, un, rec) end
  w.held, w.worms = {}, {}
end

local function shut_down(w)
  release_all(w, true)
  destroy_all(w)
  storage.wearers[w.player_index] = nil
end

-- Played only to players who have Lullaby's sound on.
local function play(w, path)
  if not (w.center and w.center.valid) then return end
  local surface, pos = w.center.surface, w.center.position
  local listeners, everyone = {}, true
  for _, player in pairs(game.connected_players) do
    if player_wants(player, "wp-lullaby-sound") then
      listeners[#listeners + 1] = player
    else
      everyone = false
    end
  end
  if everyone then
    surface.play_sound({path = path, position = pos})
  else
    for _, player in pairs(listeners) do
      if player.surface == surface then player.play_sound({path = path, position = pos}) end
    end
  end
end

local function activate(player, center)
  local tick = game.tick
  local w = {
    player_index = player.index,
    center = center,
    held = {}, worms = {},
    next_beat = tick + B.START_TICKS,
    first_beat = tick + B.START_TICKS,
    idle_pulses = 0,
    last_near = tick,
  }
  draw_all(w)
  storage.wearers[player.index] = w
  play(w, "wp-lullaby-start")
end

-- Is this unit one the song should take? Biters in the sleep layer, spitters in the lure layer.
local function wants(e, d)
  if d <= B.SLEEP_RADIUS + B.CATCH_MARGIN then return true end
  return d <= B.LURE_RADIUS and proto_info(e).ranged
end

-- Proximity: Lullaby plays while any biter or spitter is within the lure radius,
-- entranced or not, so it's already singing when charging biters reach the sleep
-- layer. Worms alone don't wake it or keep it going.
local function anything_in_range(center, forces)
  return #center.surface.find_entities_filtered({position = center.position, radius = B.LURE_RADIUS,
                                                 type = "unit", force = forces, limit = 1}) > 0
end

-- Entrance any new biters in the sleep layer and spitters in the lure layer. Runs
-- every few ticks while active (not just on pulses), because a charging biter covers
-- several tiles a second. Returns whether any enemy unit is within the lure radius.
local function catch_new(w, forces, radius)
  local tick = game.tick
  local center = w.center
  local pos = center.position
  local wake = wake_distance(w)
  local near = false
  if #forces == 0 then return false end
  for _, e in pairs(center.surface.find_entities_filtered({position = pos, radius = radius or B.LURE_RADIUS, type = "unit", force = forces})) do
    near = true
    local un = e.unit_number
    if un and not storage.claimed[un] and not is_immune(un, tick) then
      local d = dist(e.position, pos)
      if d > wake and wants(e, d) then
        local rec = entrance(w, e)
        rec.drawing = d > B.SLEEP_RADIUS and proto_info(e).ranged
        if rec.drawing then start_move(w, rec, d - (B.SLEEP_RADIUS - 0.5)) end
      end
    end
  end
  return near
end

local function scan_idle()
  for _, player in pairs(game.connected_players) do
    if not storage.wearers[player.index] then
      local eq, center = find_source(player)
      if eq and eq.energy >= B.ACTIVATE_MIN then
        local forces = enemy_forces(center.force)
        if #forces > 0 and anything_in_range(center, forces) then
          activate(player, center)
          catch_new(storage.wearers[player.index], forces)
        end
      end
    end
  end
end

-- One pulse: pay for it, then update every layer.
local function pulse(w, eq)
  local tick = game.tick
  local center = w.center
  local pos, surface = center.position, center.surface

  local cost = B.PULSE_BASE + B.PULSE_PER_TARGET * count_targets(w)
  if eq.energy < cost then
    -- Missed pulse: the field drops and everyone wakes fully.
    play(w, "wp-lullaby-scratch")
    shut_down(w)
    return
  end
  eq.energy = eq.energy - cost
  w.last_beat = tick

  local forces = enemy_forces(center.force)
  local wake = wake_distance(w)

  -- Entranced units: left behind, reached the wearer, drawn in, scuttle or stay put.
  for un, rec in pairs(w.held) do
    local e = rec.entity
    if not (e and e.valid) then
      destroy(rec.swirl); w.held[un] = nil; unclaim(un)
    else
      local d = dist(rec.walk and e.position or rec.home, pos)
      local ranged = proto_info(e).ranged
      if d > (ranged and B.LURE_RADIUS or B.SLEEP_RADIUS) + 2 then
        full_wake_unit(w, un, rec, false); w.held[un] = nil
      elseif tick - (rec.since or tick) >= trance_ticks() then
        -- The trance wears off: it can't be kept under forever by backing away.
        full_wake_unit(w, un, rec, true); w.held[un] = nil
      elseif d <= wake then
        full_wake_unit(w, un, rec, true); w.held[un] = nil
      else
        rec.drawing = d > B.SLEEP_RADIUS and ranged
        local moving = rec.walk or rec.scuttle_left > 0
        if rec.drawing and not moving then
          start_move(w, rec, d - (B.SLEEP_RADIUS - 0.5))
        elseif not rec.drawing and not moving then
          if math.random() < rec.chance then
            start_move(w, rec, B.SCUTTLE_DISTANCE)
            rec.chance = B.SCUTTLE_CHANCE
          else
            rec.chance = math.min(1, rec.chance + proto_info(e).growth)
          end
          set_swirl_speed(rec)
        end
      end
    end
  end

  -- New units, and whether anything is still close enough to keep singing.
  local near = catch_new(w, forces)

  -- Worms: hushed while the wearer stays in range and the song lasts.
  for un, rec in pairs(w.worms) do
    local e = rec.entity
    if not (e and e.valid) then
      destroy(rec.swirl); w.worms[un] = nil; unclaim(un)
    elseif dist(e.position, pos) > B.WORM_RADIUS + 2 then
      release_worm(w, un, rec); w.worms[un] = nil
    end
  end
  if #forces > 0 then
    for _, e in pairs(surface.find_entities_filtered({position = pos, radius = B.WORM_RADIUS, type = "turret", force = forces})) do
      local un = e.unit_number
      if un and worm_eligible(un, tick) then
        set_disabled(e, true)
        w.worms[un] = {entity = e, swirl = draw_swirl(e)}
        claim(un, w)
      end
    end
  end

  -- No biters or spitters nearby for a while: wind down (releasing any hushed worms).
  if not near then
    w.idle_pulses = w.idle_pulses + 1
  else
    w.idle_pulses = 0
    w.last_near = tick
  end
  if w.idle_pulses >= B.IDLE_PULSES then
    w.winding = true
  end
  w.next_beat = tick + B.PULSE_TICKS
end

-- Between pulses: walking (every tick), gliding and twitching.
local function between_pulses(w, tick)
  local pos = w.center.position
  local wake = wake_distance(w)
  local step_tick = tick % B.MOVE_TICKS == 0
  local twitch = tick % B.JITTER_TICKS == 0
  for un, rec in pairs(w.held) do
    local e = rec.entity
    if e and e.valid then
      if rec.walk then
        update_walk(w, rec, tick)
      elseif rec.scuttle_left > 0 then
        if step_tick then
          local speed = rec.drawing and B.DRAW_SPEED or B.SCUTTLE_SPEED
          local moved = glide(w, rec, math.min(rec.scuttle_left, speed * B.MOVE_TICKS))
          rec.scuttle_left = moved > 0 and (rec.scuttle_left - moved) or 0
        end
      elseif twitch then
        local amp = B.JITTER + B.JITTER_STRUGGLE * struggle(rec)
        e.teleport({x = rec.home.x + (math.random() * 2 - 1) * amp,
                    y = rec.home.y + (math.random() * 2 - 1) * amp})
      end
      if not rec.walk then
        local d = dist(rec.home, pos)
        if rec.drawing and d <= B.SLEEP_RADIUS then rec.drawing = false end
        if d <= wake then
          full_wake_unit(w, un, rec, true); w.held[un] = nil
        end
      end
    end
  end
end

local function tick_wearer(w, tick)
  local player = game.get_player(w.player_index)
  local eq, center = nil, nil
  if player and player.valid and player.connected then eq, center = find_source(player) end
  if not eq then
    if w.center and w.center.valid then play(w, "wp-lullaby-stop") end
    shut_down(w)
    return
  end
  if center ~= w.center then
    -- Got in or out of a vehicle: follow the new centre.
    w.center = center
    destroy_all(w)
    draw_all(w)
  end

  if w.fade_from then
    update_visuals(w, tick)
    if tick >= w.fade_from + B.WIND_DOWN_TICKS then shut_down(w) end
    return
  end

  if tick == w.next_beat - B.SOUND_LEAD then
    if w.winding then
      play(w, "wp-lullaby-stop")
    elseif eq.energy >= B.PULSE_BASE + B.PULSE_PER_TARGET * count_targets(w) then
      play(w, "wp-lullaby-pulse")
    end
    -- (not enough for the next pulse: no chunk; pulse() plays the scratch)
  end
  if tick >= w.next_beat then
    if w.winding then
      w.fade_from = tick - B.SOUND_LEAD
    else
      pulse(w, eq)
      if not storage.wearers[w.player_index] then return end
    end
  end
  -- Biters arriving at the sleep layer are caught right at its edge (checked every few
  -- ticks); the lure layer is swept less often, since spitters are drawn in anyway.
  if tick % B.LURE_SCAN_TICKS == 0 then
    if catch_new(w, enemy_forces(w.center.force)) then w.last_near = tick end
  elseif tick % B.CATCH_TICKS == 0 then
    if catch_new(w, enemy_forces(w.center.force), B.SLEEP_RADIUS + B.CATCH_MARGIN) then w.last_near = tick end
  end

  -- Nothing within the lure radius for a moment (say, you jetpacked away): wind down
  -- straight away rather than waiting for the next pulse. Anything left behind wakes.
  if tick - (w.last_near or tick) >= B.IDLE_TICKS then
    release_all(w, false)
    play(w, "wp-lullaby-stop")
    w.winding = true
    w.fade_from = tick
    update_visuals(w, tick)
    return
  end
  between_pulses(w, tick)
  if tick % 2 == 0 then update_visuals(w, tick) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

script.on_init(init_storage)
script.on_load(function() view_cache = nil end)
script.on_configuration_changed(function()
  view_cache = nil
  init_storage()
  storage.proto = {}
  -- Redraw rays (layer or blend may have changed) and move any 0.1 lured spitters in.
  for _, w in pairs(storage.wearers) do
    if w.lured then
      for un, rec in pairs(w.lured) do full_wake_unit(w, un, rec, false) end
      w.lured = nil
    end
    local everyone = {}
    for _, p in pairs(game.connected_players) do everyone[#everyone + 1] = p.index end
    for _, list in pairs({w.held, w.worms}) do
      for _, rec in pairs(list) do
        if rec.swirl and rec.swirl.valid then rec.swirl.visible = true; rec.swirl.players = everyone end
      end
    end
    for _, rec in pairs(w.held) do
      rec.scuttle_left = rec.scuttle_left or 0
      rec.since = rec.since or game.tick
      rec.home = rec.home or (rec.entity and rec.entity.valid and rec.entity.position)
    end
    if w.center and w.center.valid then
      destroy_all(w)
      draw_all(w)
    end
  end
end)

script.on_event(defines.events.on_tick, function(event)
  local tick = event.tick
  for _, w in pairs(storage.wearers) do
    tick_wearer(w, tick)
  end
  if tick % B.SCAN_TICKS == 0 then scan_idle() end
  if tick % 36000 == 0 then
    for un, t in pairs(storage.immune) do
      if t <= tick then storage.immune[un] = nil end
    end
  end
end)

-- One per grid: hand a second one straight back.
script.on_event(defines.events.on_player_placed_equipment, function(event)
  local eq, grid = event.equipment, event.grid
  if not (eq and eq.valid and eq.name == EQUIPMENT) then return end
  if grid.count(EQUIPMENT) <= 1 then return end
  local quality = eq.quality and eq.quality.name or "normal"
  grid.take({equipment = eq})
  local player = game.get_player(event.player_index)
  if player then
    local stack = {name = EQUIPMENT, count = 1, quality = quality}
    if player.insert(stack) == 0 and player.character then
      player.surface.spill_item_stack({position = player.position, stack = stack})
    end
    player.create_local_flying_text({text = {"wp-lullaby.one-per-grid"}, create_at_cursor = true})
  end
end)

script.on_event(defines.events.on_object_destroyed, function(event)
  if event.useful_id then
    storage.worms_done[event.useful_id] = nil
    storage.immune[event.useful_id] = nil
  end
end)

-- Turning the cooldown off forgets every current immunity and hushed worm straight away.
-- Re-apply who can see the effects to everything currently drawn.
local function refresh_view()
  view_cache = nil
  for _, w in pairs(storage.wearers) do
    apply_view(w.rays, true); apply_view(w.bloom, true); apply_view(w.ray_light, true); apply_view(w.glow, true)
    apply_view(w.rays_b, true); apply_view(w.bloom_b, true)
  end
end

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting == "wp-lullaby-disable-cooldown" and cooldown_disabled() then
    storage.immune = {}
    storage.worms_done = {}
  end
  if event.setting == "wp-lullaby-graphics" then refresh_view() end
end)

script.on_event(defines.events.on_player_joined_game, refresh_view)

script.on_event(defines.events.on_player_left_game, function(event)
  local w = storage.wearers[event.player_index]
  if w then shut_down(w) end
  refresh_view()
end)
