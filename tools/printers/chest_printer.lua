-- Automatically find the first chest peripheral
local chest = peripheral.find("inventory")  -- Compatible with most chests
if not chest then
  print("No chest found. Make sure it's connected or try restarting.")
  return
end

-- Function to get and print item counts
local function printInventory()
  local items = chest.list()
  local result = {}

  for _, item in pairs(items) do
    if result[item.name] then
      result[item.name] = result[item.name] + item.count
    else
      result[item.name] = item.count
    end
  end

  print("Chest Inventory Contents:")
  for name, count in pairs(result) do
    print(name .. ": " .. count)
  end
end

-- Run once
printInventory()
