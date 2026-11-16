-- Fit vehicle grids from overhaul mods, like WePlay: Cartographer Equipment.
local eq = data.raw["battery-equipment"]["wp-lullaby-equipment"]
for _, cat in pairs({"vehicle-equipment", "universal-equipment"}) do
  if data.raw["equipment-category"] and data.raw["equipment-category"][cat] then
    table.insert(eq.categories, cat)
  end
end
