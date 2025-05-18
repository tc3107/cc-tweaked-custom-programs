local hostname = "chest_reader_1"  -- Make this unique
local inputSide = "left"           -- Set this to the modem side connected to the chest network

-- Open all modem sides for rednet
local sides = {"left", "right", "top", "bottom", "front", "back"}
for _, side in ipairs(sides) do
  if peripheral.getType(side) == "modem" then
    rednet.open(side)
  end
end

-- Wrap the modem on the input side (used to scan chests)
local modem = peripheral.wrap(inputSide)
if not modem or peripheral.getType(inputSide) ~= "modem" then
  print("No modem found on inputSide:", inputSide)
  return
end

-- Find all inventory peripherals connected through the modem
local chestNames = modem.getNamesRemote()
local chests = {}

for _, name in ipairs(chestNames) do
  if peripheral.getType(name) == "inventory" then
    table.insert(chests, peripheral.wrap(name))
    print("Found chest:", name)
  end
end

if #chests == 0 then
  print("No chests found on the network via", inputSide)
  return
end

-- Host the rednet server
rednet.host("items", hostname)
print("Server '" .. hostname .. "' is online using protocol 'items'")

-- Function to get combined inventory from all chests
local function getInventory()
  local result = {}

  for _, chest in ipairs(chests) do
    for _, item in pairs(chest.list()) do
      if result[item.name] then
        result[item.name] = result[item.name] + item.count
      else
        result[item.name] = item.count
      end
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
