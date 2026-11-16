data:extend({
  {
    type = "int-setting",
    name = "wp-lullaby-immunity-seconds",
    setting_type = "runtime-global",
    default_value = 30,
    minimum_value = 0,
    maximum_value = 60,
    order = "a",
  },
  {
    type = "bool-setting",
    name = "wp-lullaby-worm-reentrance",
    setting_type = "runtime-global",
    default_value = false,
    order = "b",
  },
  {
    type = "int-setting",
    name = "wp-lullaby-pulse-flash",
    setting_type = "runtime-global",
    default_value = 50,
    minimum_value = 0,
    maximum_value = 100,
    order = "c",
  },
})
