-- fetch.lua
-- Fetcher Client: requests a global index from the Central Server, then proceeds with fetching items.

-- CONFIGURATION: set this to the Computer ID of your Central Server
local CENTRAL_ID = 5  
local NETWORK_PROTOCOL = "inventoryNet"

-- Utility: trim whitespace
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Find and open a modem for rednet
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

-- Main fetch logic (after index is loaded)
local function doFetch(index)
  -- 1. let user list or choose an item
  local choice = trim(prompt("Enter item name (or 'list'):"):lower())
  if choice == "list" then
    local items = {}
    for name, data in pairs(index) do
      table.insert(items, { name = name, total = data.total })
    end
    table.sort(items, function(a,b) return a.total > b.total end)
    for _, v in ipairs(items) do
      local raw = v.name:match(":(.+)") or v.name
      print(("- %s : %d"):format(raw, v.total))
    end
    return
  end

  -- Normalize and find exact key in the index table
  local normalized = choice:gsub("%s+", "_")
  local itemKey
  for full, data in pairs(index) do
    if full:match(":"..normalized.."$") then
      itemKey = full
      break
    end
  end
  if not itemKey then
    print("Item not found:", choice)
    return
  end

  local available = index[itemKey].total
  print("Available:", available)
  local qty = tonumber(prompt("How many to fetch?"))
  if not qty or qty < 1 or qty > available then
    print("Invalid quantity.")
    return
  end

  -- Transfer: iterate all sources and push items
  local moved = 0
  local toFetch = qty
  local outChest = peripheral.getNames() -- assume first chest is output; adapt as needed
  outChest = outChest[1]
  for _, src in ipairs(index[itemKey].sources) do
    if toFetch <= 0 then break end
    local per = peripheral.wrap(src.chest)
    local take = math.min(src.count, toFetch)
    local ok, pushed = pcall(function()
      return per.pushItems(outChest, src.slot, take)
    end)
    if ok and pushed > 0 then
      moved = moved + pushed
      toFetch = toFetch - pushed
    end
  end

  print(("Fetched %d of %d"):format(moved, qty))
end

-- Bootstrap
if not initRednet() then
  print("Error: no modem found.")
  return
end

-- 1. Request index from Central
rednet.send(CENTRAL_ID, {{ action="index_request" }}, NETWORK_PROTOCOL)
print("Requested global index from Central Server...")

-- 2. Wait for response
local id, msg = rednet.receive(NETWORK_PROTOCOL, 30)
if not id or not msg or not msg[1] or msg[1].action ~= "index_response" then
  print("Did not receive index in time.")
  return
end

local payload = msg[1]
print("Index received. Total item types:", table.getn(vim.tbl_keys(payload.data)))
-- 3. Run fetch loop
while true do
  doFetch(payload.data)
end

