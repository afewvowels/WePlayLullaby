local B = require("balance")
local MOD = "__WePlayLullaby__"
local NAME = "wp-lullaby-equipment"

-- Only list prerequisites that exist, so overhaul mods that rename techs don't break loading.
local function existing(techs)
  local out = {}
  for _, t in pairs(techs) do
    if data.raw.technology[t] then out[#out + 1] = t end
  end
  return out
end

data:extend({
  -- Item
  {
    type = "item",
    name = NAME,
    icon = MOD .. "/graphics/icons/lullaby-equipment.png",
    icon_size = 64,
    place_as_equipment_result = NAME,
    subgroup = "military-equipment",
    order = "b[active-defense]-z[wp-lullaby]",
    stack_size = 20,
  },

  -- Equipment: a battery that only charges. The script spends its energy on each pulse.
  {
    type = "battery-equipment",
    name = NAME,
    sprite = {
      filename = MOD .. "/graphics/equipment/lullaby-equipment.png",
      width = 128,
      height = 128,
      priority = "medium",
      scale = 0.5,
    },
    shape = {width = 2, height = 2, type = "full"},
    energy_source = {
      type = "electric",
      buffer_capacity = B.BUFFER,
      input_flow_limit = B.INPUT_FLOW,
      output_flow_limit = "0W",
      usage_priority = "tertiary",
    },
    categories = {"armor"},
  },

  -- Recipe
  {
    type = "recipe",
    name = NAME,
    enabled = false,
    energy_required = 10,
    ingredients = {
      {type = "item", name = "programmable-speaker", amount = 1},
      {type = "item", name = "advanced-circuit", amount = 10},
      {type = "item", name = "steel-plate", amount = 5},
    },
    results = {{type = "item", name = NAME, amount = 1}},
  },

  -- Technology
  {
    type = "technology",
    name = NAME,
    icon = MOD .. "/graphics/technology/lullaby-equipment.png",
    icon_size = 256,
    effects = {{type = "unlock-recipe", recipe = NAME}},
    prerequisites = existing({"modular-armor", "circuit-network", "advanced-circuit", "military-2"}),
    unit = {
      count = 200,
      ingredients = {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1},
        {"military-science-pack", 1},
      },
      time = 30,
    },
    order = "g-h-z",
  },

  -- Ground rays: 40 frames, one loop = 2 pulses = 120 ticks (built by tools/lullaby_rays.py).
  -- Rotation and the bumpy-ground warp are baked in. Additive, so it reads as projected light.
  {
    type = "animation",
    name = "wp-lullaby-rays",
    filename = MOD .. "/graphics/entity/lullaby-rays.png",
    width = 384,
    height = 384,
    frame_count = 40,
    line_length = 8,
    priority = "medium",
    blend_mode = "additive",
    flags = {"no-crop"},
  },

  -- Bloom: a blurred copy of the rays (same 40 frames and timing, half resolution), additive,
  -- so the rays glow softly onto whatever's underneath them in daylight.
  {
    type = "animation",
    name = "wp-lullaby-rays-bloom",
    filename = MOD .. "/graphics/entity/lullaby-rays-bloom.png",
    width = 192,
    height = 192,
    frame_count = 40,
    line_length = 8,
    priority = "medium",
    blend_mode = "additive",
    flags = {"no-crop"},
  },

  -- Second colour: the bands between the rays (same timing), and its bloom.
  {
    type = "animation",
    name = "wp-lullaby-rays-b",
    filename = MOD .. "/graphics/entity/lullaby-rays-b.png",
    width = 384,
    height = 384,
    frame_count = 40,
    line_length = 8,
    priority = "medium",
    blend_mode = "additive",
    flags = {"no-crop"},
  },
  {
    type = "animation",
    name = "wp-lullaby-rays-b-bloom",
    filename = MOD .. "/graphics/entity/lullaby-rays-b-bloom.png",
    width = 192,
    height = 192,
    frame_count = 40,
    line_length = 8,
    priority = "medium",
    blend_mode = "additive",
    flags = {"no-crop"},
  },

  -- Overhead swirl: 16 frames, loops as it spins (built by tools/lullaby_swirl.py).
  {
    type = "animation",
    name = "wp-lullaby-swirl",
    filename = MOD .. "/graphics/entity/lullaby-swirl.png",
    width = 128,
    height = 128,
    frame_count = 16,
    line_length = 8,
    priority = "medium",
    flags = {"no-crop"},
  },

  -- Sounds (built by tools/lullaby_sounds.py)
  {
    type = "sound",
    name = "wp-lullaby-start",
    filename = MOD .. "/sounds/start.ogg",
    volume = 0.6,
    audible_distance_modifier = 0.6,
  },
  {
    type = "sound",
    name = "wp-lullaby-pulse",
    variations = {
      {filename = MOD .. "/sounds/pulse-1.ogg", volume = 0.6},
      {filename = MOD .. "/sounds/pulse-2.ogg", volume = 0.6},
      {filename = MOD .. "/sounds/pulse-3.ogg", volume = 0.6},
    },
    audible_distance_modifier = 0.6,
  },
  {
    type = "sound",
    name = "wp-lullaby-stop",
    filename = MOD .. "/sounds/stop.ogg",
    volume = 0.6,
    audible_distance_modifier = 0.6,
  },
  {
    type = "sound",
    name = "wp-lullaby-scratch",
    filename = MOD .. "/sounds/scratch.ogg",
    volume = 0.8,
    audible_distance_modifier = 0.8,
  },
})

-- Ray-shaped light (20 frames, swapped by script every 6 ticks): at night the rays
-- light up the ground, buildings and biters underneath them.
local lights = {}
for i = 0, 19 do
  lights[#lights + 1] = {
    type = "sprite",
    name = "wp-lullaby-ray-light-" .. i,
    filename = MOD .. "/graphics/entity/lullaby-rays-light.png",
    x = (i % 5) * 192,
    y = math.floor(i / 5) * 192,
    width = 192,
    height = 192,
    priority = "medium",
    flags = {"light"},
  }
end
data:extend(lights)
