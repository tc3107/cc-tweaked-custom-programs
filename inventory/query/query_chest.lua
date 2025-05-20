-- Open rednet on all sides with modems
local sides = {"left", "right", "top", "bottom", "front", "back"}
for _, side in ipairs(sides) do
  if peripheral.getType(side) == "modem" then
    rednet.open(side)
  end
end

-- List of chest server hostnames
local chestReaders = {
  "chest_reader_1",
  "chest_reader_2",
  -- Add more hostnames as needed
}

local protocol = "items"
local timeout = 5  -- seconds to wait for responses
local combinedInventory = {}

-- Add items to the combined tally
local function addItems(source)
  for item, count in pairs(source) do
    combinedInventory[item] = (combinedInventory[item] or 0) + count
  end
end

-- Send query to each chest reader
local activeReaders = {}
for _, name in ipairs(chestReaders) do
  local id = rednet.lookup(protocol, name)
  if id then
    rednet.send(id, {"get_inventory"}, protocol)
    activeReaders[id] = true
  else
    print("Could not resolve hostname:", name)
  end
end

-- Receive responses
local responsesExpected = 0
for _ in pairs(activeReaders) do
  responsesExpected = responsesExpected + 1
end

local responsesReceived = 0
local startTime = os.clock()

while responsesReceived < responsesExpected and (os.clock() - startTime) < timeout do
  local senderId, data, proto = rednet.receive(protocol, 1)
  local response = data[1]
  if senderId and activeReaders[senderId] and type(response) == "table" then
    addItems(response)
    responsesReceived = responsesReceived + 1
  end
end

-- Sort the final combined inventory by count
local sorted = {}
for item, count in pairs(combinedInventory) do
  table.insert(sorted, {name = item, count = count})
end
table.sort(sorted, function(a, b) return a.count > b.count end)

-- Print the result
print("=== Combined Chest Inventory ===")
if #sorted == 0 then
  print("No data received.")
else
  for _, entry in ipairs(sorted) do
    print(("%-40s x %d"):format(entry.name, entry.count))
  end
end
