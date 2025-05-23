-- fetch.lua
-- Fetcher Client: requests a global index from the Central Server, then proceeds with fetching items.

-- CONFIGURATION
local CENTRAL_ID       = 19                      -- Computer ID of your Central Server
local OUTPUT_CHEST     = "minecraft:chest_X"   -- Name of the chest to receive fetched items
local NETWORK_PROTOCOL = "inventoryNet"         -- Rednet protocol for messaging

-- Utility: trim whitespace
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Initialize rednet by opening an attached modem
local function initRednet()
  for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if t == "modem" or t == "wireless_modem" then
      rednet.open(name)
      return true
    end
  end
  return false
end

-- Prompt user for input
local function prompt(msg)
  write(msg .. " ")
  return read()
end

-- Perform fetching using the provided index
local function doFetch(index)
  -- Ask for item or list
  local choice = trim(prompt("Enter item name (or 'list'):"):lower())
  if choice == "list" then
    local items = {}
    for name, data in pairs(index) do
      table.insert(items, { name = name, total = data.total })
    end
    table.sort(items, function(a,b) return a.total > b.total end)
    for _, v in ipairs(items) do
      local raw = v.name:match(":(.+)") or v.name
      print(('- %s : %d'):format(raw, v.total))
    end
    return
  end

  -- Normalize choice and find matching key
  local normalized = choice:gsub("%s+", "_")
  local itemKey
  for fullName, data in pairs(index) do
    if fullName:match(":"..normalized.."$") then
      itemKey = fullName
      break
    end
  end
  if not itemKey then
    print("Item not found: " .. choice)
    return
  end

  -- Ask for quantity
  local available = index[itemKey].total
  print("Available: " .. available)
  local qty = tonumber(prompt("How many to fetch?"))
  if not qty or qty < 1 or qty > available then
    print("Invalid quantity.")
    return
  end

  -- Transfer items from sources to output chest
  local moved, toFetch = 0, qty
  for _, src in ipairs(index[itemKey].sources) do
    if toFetch <= 0 then break end
    local per = peripheral.wrap(src.chest)
    local take = math.min(src.count, toFetch)
    local ok, pushed = pcall(function()
      return per.pushItems(OUTPUT_CHEST, src.slot, take)
    end)
    if ok and pushed > 0 then
      moved = moved + pushed
      toFetch = toFetch - pushed
    end
  end
  print(('Fetched %d of %d'):format(moved, qty))
end

-- Bootstrap
if not initRednet() then
  print("Error: no modem found.")
  return
end

-- Request global index from Central Server
rednet.send(CENTRAL_ID, {{ action = "index_request" }}, NETWORK_PROTOCOL)
print("Requested global index from Central Server...")

-- Wait for response
local sender, msg = rednet.receive(NETWORK_PROTOCOL, 30)
if not sender or not msg or not msg[1] or msg[1].action ~= "index_response" then
  print("Error: did not receive index in time.")
  return
end

local payload = msg[1]
print("Index received. Item types: " .. #payload.data)

-- Fetch loop
while true do
  doFetch(payload.data)
end
