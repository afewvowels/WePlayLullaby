-- WePlay: Lullaby -- Crowd Control Equipment
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

local function immunity_ticks()
  return settings.global["wp-lullaby-immunity-seconds"].value * 60
end

local function flash_strength()
  return settings.global["wp-lullaby-pulse-flash"].value / 100
end

local function worm_reentrance()
  return settings.global["wp-lullaby-worm-reentrance"].value
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
-- Swirl over entranced enemies
---------------------------------------------------------------------------

local function draw_swirl(e)
  local box = e.prototype.selection_box
  local top = box and box.left_top and box.left_top.y or -0.8
  local size = box and (box.right_bottom.x - box.left_top.x) or 1
  local scale = B.SWIRL_SCALE * math.max(0.8, math.min(1.6, size))
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

local function set_swirl_speed(rec)
  local s = rec.swirl
  if s and s.valid then
    local struggle = math.min(1, (rec.chance or 0) / 0.6)
    s.animation_speed = B.SWIRL_SPEED + B.SWIRL_SPEED_STRUGGLE * struggle
  end
end

---------------------------------------------------------------------------
-- Ground effect and glow
---------------------------------------------------------------------------

local function ray_tint(level)
  -- The ray animation uses additive blending, so the tint is just brightness.
  local c = B.RAY_COLOR
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
    if ok and obj then return obj end
  end
end

local function draw_glow(w)
  return rendering.draw_light({
    sprite = "utility/light_medium",
    target = w.center,
    surface = w.center.surface,
    scale = B.GLOW_SCALE,
    intensity = 0,
    minimum_darkness = 0,
    color = B.GLOW_COLOR,
  })
end

local function light_frame(w, tick)
  local t = (tick - w.first_beat) % RAY_LOOP
  return math.floor(t * LIGHT_FRAMES / RAY_LOOP) % LIGHT_FRAMES
end

local function draw_ray_light(w)
  w.light_frame = light_frame(w, game.tick)
  return rendering.draw_light({
    sprite = LIGHT_PREFIX .. w.light_frame,
    target = w.center,
    surface = w.center.surface,
    -- the 192 px light covers 6 tiles at scale 1; match the 384 px rays
    scale = ray_scale() * 2,
    intensity = 0,
    minimum_darkness = 0.3,
    color = B.RAY_COLOR,
  })
end

local function draw_all(w)
  w.rays = draw_rays(w, RAYS, ray_scale())
  w.bloom = draw_rays(w, BLOOM, ray_scale() * 2)
  w.ray_light = draw_ray_light(w)
  w.glow = draw_glow(w)
end

local function destroy_all(w)
  destroy(w.rays); destroy(w.bloom); destroy(w.ray_light); destroy(w.glow)
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

local function play(w, path)
  if w.center and w.center.valid then
    w.center.surface.play_sound({path = path, position = w.center.position})
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
  }
  draw_all(w)
  storage.wearers[player.index] = w
  play(w, "wp-lullaby-start")
end

-- Is this unit one the song should take? Biters in the sleep layer, spitters in the lure layer.
local function wants(e, d)
  if d <= B.SLEEP_RADIUS then return true end
  return d <= B.LURE_RADIUS and proto_info(e).ranged
end

-- Proximity: Lullaby plays while biters are in the sleep layer or spitters in the
-- lure layer, entranced or not. Worms alone don't wake it or keep it going.
local function anything_in_range(center, forces)
  local surface, pos = center.surface, center.position
  for _, e in pairs(surface.find_entities_filtered({position = pos, radius = B.LURE_RADIUS, type = "unit", force = forces})) do
    if wants(e, dist(e.position, pos)) then return true end
  end
  return false
end

local function scan_idle()
  for _, player in pairs(game.connected_players) do
    if not storage.wearers[player.index] then
      local eq, center = find_source(player)
      if eq and eq.energy >= B.ACTIVATE_MIN then
        local forces = enemy_forces(center.force)
        if #forces > 0 and anything_in_range(center, forces) then
          activate(player, center)
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
      local d = dist(rec.home, pos)
      local ranged = proto_info(e).ranged
      if d > (ranged and B.LURE_RADIUS or B.SLEEP_RADIUS) + 2 then
        full_wake_unit(w, un, rec, false); w.held[un] = nil
      elseif d <= wake then
        full_wake_unit(w, un, rec, true); w.held[un] = nil
      else
        rec.drawing = d > B.SLEEP_RADIUS
        if not rec.drawing and rec.scuttle_left <= 0 then
          if math.random() < rec.chance then
            rec.scuttle_left = B.SCUTTLE_DISTANCE
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
  local near = false
  if #forces > 0 then
    for _, e in pairs(surface.find_entities_filtered({position = pos, radius = B.LURE_RADIUS, type = "unit", force = forces})) do
      local d = dist(e.position, pos)
      if wants(e, d) then
        near = true
        local un = e.unit_number
        if un and not storage.claimed[un] and not is_immune(un, tick) and d > wake then
          local rec = entrance(w, e)
          rec.drawing = d > B.SLEEP_RADIUS
        end
      end
    end
  end

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
  end
  if w.idle_pulses >= B.IDLE_PULSES then
    w.winding = true
  end
  w.next_beat = tick + B.PULSE_TICKS
end

-- Between pulses: spitters drawn in, scuttles, twitching.
local function between_pulses(w, tick)
  if tick % B.MOVE_TICKS ~= 0 then return end
  local pos = w.center.position
  local wake = wake_distance(w)
  local twitch = tick % B.JITTER_TICKS == 0
  for un, rec in pairs(w.held) do
    local e = rec.entity
    if e and e.valid then
      if rec.drawing then
        glide(w, rec, B.DRAW_SPEED * B.MOVE_TICKS)
        if dist(rec.home, pos) <= B.SLEEP_RADIUS then rec.drawing = false end
      elseif rec.scuttle_left > 0 then
        local moved = glide(w, rec, math.min(rec.scuttle_left, B.SCUTTLE_SPEED * B.MOVE_TICKS))
        rec.scuttle_left = moved > 0 and (rec.scuttle_left - moved) or 0
      elseif twitch then
        local struggle = math.min(1, rec.chance / 0.6)
        local amp = B.JITTER + B.JITTER_STRUGGLE * struggle
        e.teleport({x = rec.home.x + (math.random() * 2 - 1) * amp,
                    y = rec.home.y + (math.random() * 2 - 1) * amp})
      end
      if dist(rec.home, pos) <= wake then
        full_wake_unit(w, un, rec, true); w.held[un] = nil
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
  between_pulses(w, tick)
  if tick % 2 == 0 then update_visuals(w, tick) end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

script.on_init(init_storage)
script.on_configuration_changed(function()
  init_storage()
  storage.proto = {}
  -- Redraw rays (layer or blend may have changed) and move any 0.1 lured spitters in.
  for _, w in pairs(storage.wearers) do
    if w.lured then
      for un, rec in pairs(w.lured) do full_wake_unit(w, un, rec, false) end
      w.lured = nil
    end
    for _, rec in pairs(w.held) do
      rec.scuttle_left = rec.scuttle_left or 0
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

script.on_event(defines.events.on_player_left_game, function(event)
  local w = storage.wearers[event.player_index]
  if w then shut_down(w) end
end)
