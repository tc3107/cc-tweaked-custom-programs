-- === Configuration ===
local inputSide = "left"   -- Side where modem connects to input chests
local outputSide = "right" -- Side where modem connects to output chests

-- Item routing map: item name → output chest peripheral name
local routes = {
  ["minecraft:cobblestone"] = "minecraft:chest_0",
  ["minecraft:dirt"] = "minecraft:chest_1"
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

-- === Sorting Logic ===

local function sortItems(inputChests, routes)
  for _, input in ipairs(inputChests) do
    local list = input.chest.list()
    for slot, item in pairs(list) do
      local targetName = routes[item.name]
      if targetName then
        local moved = input.chest.pushItems(targetName, slot)
        print(("Moved %d of %s to %s"):format(moved, item.name, targetName))
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
