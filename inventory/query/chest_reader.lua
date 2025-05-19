local hostname = "chest_reader_1"  -- Make this unique

-- Open all modem sides for rednet
local sides = {"left", "right", "top", "bottom", "front", "back"}
for _, side in ipairs(sides) do
  if peripheral.getType(side) == "modem" then
    rednet.open(side)
  end
end

-- Automatically find the first chest peripheral
local chest = peripheral.find("inventory")  -- Compatible with most chests
if not chest then
  print("No chest found. Make sure it's connected or try restarting.")
  return
end

-- Host the rednet server
rednet.host("items", hostname)
print("Server '" .. hostname .. "' is online, protocol 'items'")

-- Function to get item counts
local function getInventory()
  local items = chest.list()
  local result = {}

  for _, item in pairs(items) do
    if result[item.name] then
      result[item.name] = result[item.name] + item.count
    else
      result[item.name] = item.count
    end
  end

  return result
end

-- Main server loop
while true do
  local senderId, message, protocol = rednet.receive("items")
  print("Received:", message, "from", senderId)

  if message == "get_inventory" then
    local inventory = getInventory()
    rednet.send(senderId, inventory, "items")
    print("Inventory sent to", senderId)
  else
    print("Unknown request:", message)
  end
end
