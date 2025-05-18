-- === Configuration ===
local inputSide = "left"   -- Side where modem connects to input chests
local outputSide = "right" -- Side where modem connects to output chests

-- Item routing map: item name to output chest peripheral name
local routes = {
  ["minecraft:cobblestone"] = "minecraft:chest_1",
  ["minecraft:dirt"] = "minecraft:chest_2"
  -- Add more as needed
}

-- === Wrap Inventories ===

local function wrapInventories(modemSide)
  local modem = peripheral.wrap(modemSide)
  if not modem or peripheral.getType(modemSide) ~= "modem" then
    error("No modem found on side: " .. modemSide)
  end

  local chests = {}
  for _, name in ipairs(modem.getNamesRemote()) do
    if peripheral.getType(name) == "inventory" then
      table.insert(chests, {
        name = name,
        chest = peripheral.wrap(name)
      })
    end
  end
  return chests
end

-- === Sorting Logic with Debug ===

local function sortItems(inputChests, routes)
  for _, input in ipairs(inputChests) do
    local chestName = input.name
    local list = input.chest.list()
    print("Scanning chest:", chestName)

    for slot, item in pairs(list) do
      print(("  Slot %d: %s x%d"):format(slot, item.name, item.count))

      local targetName = routes[item.name]
      if targetName then
        local moved = input.chest.pushItems(targetName, slot)
        print(("    → Moved %d to %s"):format(moved, targetName))
      else
        print("    → No route for this item, skipping.")
      end
    end
  end
end

-- === Main Loop ===

local inputChests = wrapInventories(inputSide)
print("Sorter running. Scanning every 5 seconds.")

while true do
  sortItems(inputChests, routes)
  sleep(5)
end
