-- 📡 Open rednet on all modem sides
local sides = {"left", "right", "top", "bottom", "front", "back"}
for _, side in ipairs(sides) do
  if peripheral.getType(side) == "modem" then
    rednet.open(side)
  end
end

-- 🧰 List of chest reader hostnames to query
local chestReaders = {
  "chest_reader_1",
  "chest_reader_2",
  -- Add more if needed
}

local protocol = "items"
local timeout = 3  -- seconds
local combinedInventory = {}

-- 🛒 Function to merge inventories
local function addItems(source)
  for item, count in pairs(source) do
    combinedInventory[item] = (combinedInventory[item] or 0) + count
  end
end

-- 🔁 Query each chest reader
for _, reader in ipairs(chestReaders) do
  rednet.send(reader, "get_inventory", protocol)
end

-- ⏳ Collect responses
local responsesExpected = #chestReaders
local responsesReceived = 0
local startTime = os.clock()

while responsesReceived < responsesExpected and (os.clock() - startTime) < timeout do
  local id, response, proto = rednet.receive(protocol, 1)
  if response and type(response) == "table" then
    addItems(response)
    responsesReceived = responsesReceived + 1
  end
end

-- 📊 Sort inventory from highest to lowest count
local sorted = {}
for item, count in pairs(combinedInventory) do
  table.insert(sorted, {name = item, count = count})
end
table.sort(sorted, function(a, b) return a.count > b.count end)

-- 🖨️ Print results
print("=== Combined Chest Inventory ===")
for _, entry in ipairs(sorted) do
  print(("%-40s x %d"):format(entry.name, entry.count))
end
