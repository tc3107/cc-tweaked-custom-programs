-- === Configuration ===
local modemSide = "left" -- Single modem connected to all chests
local inputChestName = "minecraft:chest_0" -- The dedicated input chest

-- Item routing map: item name → output chest peripheral name
local routes = {
  ["minecraft:cobblestone"] = "minecraft:chest_1",
  ["minecraft:dirt"] = "minecraft:chest_2"
  -- Add more as needed
}

-- === Wrap All Inventories ===

local function getChests()
  local modem = peripheral.wrap(modemSide)
  if not modem or peripheral.getType(modemSide) ~= "modem" then
    print("No modem found on side:", modemSide)
    return nil
  end

  local input = nil
  local outputs = {}

  for _, name in ipairs(modem.getNamesRemote()) do
    if peripheral.getType(name) == "inventory" then
      if name == inputChestName then
        input = { name = name, chest = peripheral.wrap(name) }
      else
        outputs[name] = peripheral.wrap(name)
      end
    end
  end

  if not input then
    print("Input chest not found:", inputChestName)
    return nil
  end

  return input, outputs
end

-- === Sorting Logic with Debug ===

local function sortItems(input, outputs, routes)
  local foundAnyItems = false
  local list = input.chest.list()

  print("Scanning input chest:", input.name)

  if next(list) == nil then
    print("  → Chest is empty.")
  else
    foundAnyItems = true
  end

  for slot, item in pairs(list) do
    print(("  Slot %d: %s x%d"):format(slot, item.name, item.count))

    local targetName = routes[item.name]
    if targetName then
      local dest = outputs[targetName]
      if dest then
        local moved = input.chest.pushItems(targetName, slot)
        print(("    → Moved %d to %s"):format(moved, targetName))
      else
        print(("    → Route exists but output chest '%s' not found"):format(targetName))
      end
    else
      print("    → No route for this item, skipping.")
    end
  end

  if not foundAnyItems then
    print("No items found to sort.")
  end
end

-- === Main Loop ===

local input, outputs = getChests()

if not input then
  print("Failed to start: Input chest not found.")
  return
end

print("Sorter running. Scanning every 5 seconds.")

while true do
  sortItems(input, outputs, routes)
  sleep(5)
end
