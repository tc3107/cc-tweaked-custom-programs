-- fetch.lua
-- Networked Fetcher Client: requests a global index from the coordinator,
-- then allows the user to retrieve items from networked storage.

local CENTRAL_ID       = 19
local OUTPUT_CHEST     = "minecraft:chest_X"
local NETWORK_PROTOCOL = "inventoryNet"
local LIST_DELAY       = 0.75
local INDEX_TIMEOUT    = 65 -- seconds to wait for index response

-- Trim whitespace
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

-- Count the number of keys in a table
local function countKeys(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Find and open any attached modem
local function initRednet()
  for _, side in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(side)
    if t == "modem" or t == "wireless_modem" then
      rednet.open(side)
      print("[DEBUG] rednet opened on", side)
      return true
    end
  end
  return false
end

-- Prompt helper
local function prompt(msg)
  write(msg .. " ")
  return read()
end

-- Compute list of item prefixes for fuzzy lookup
local function computePrefixes(index)
  local set = {}
  for name in pairs(index) do
    local p = name:match("^(.-):")
    if p then set[p] = true end
  end
  local list = {}
  for p in pairs(set) do table.insert(list, p) end
  return list
end

-- Get free slot count in a chest
local function getFreeSpace(name)
  local per = peripheral.wrap(name)
  local total = per.size()
  local used = 0
  for _, item in pairs(per.list()) do
    if item then used = used + 1 end
  end
  return total - used
end

-- Transfer items from sources to output chest
local function fetchItems(itemSources, qty, outName)
  local remaining = qty
  local moved = 0
  for _, src in ipairs(itemSources) do
    if remaining <= 0 then break end
    if getFreeSpace(outName) <= 0 then
      print("[WARN] Output chest full, stopping early")
      break
    end
    local take = math.min(src.count, remaining)
    local per = peripheral.wrap(src.chest)
    print(string.format("[DEBUG] Moving %d from %s slot %d", take, src.chest, src.slot))
    local ok = per.pushItems(outName, src.slot, take)
    if ok and ok > 0 then
      remaining = remaining - ok
      moved = moved + ok
    else
      print(string.format("[ERROR] Failed to move from %s slot %d", src.chest, src.slot))
    end
  end
  return moved
end

-- Interactive fetch using provided index
local function runPrompt(index)
  local prefixes = computePrefixes(index)
  while true do
    local choice = trim(string.lower(prompt("Enter item name or 'list':")))
    if choice == "" then return end
    if choice == "list" then
      local items = {}
      for n, d in pairs(index) do table.insert(items, {name=n,total=d.total}) end
      table.sort(items, function(a,b) return a.total > b.total end)
      for _, v in ipairs(items) do
        local raw = v.name:match(":(.+)") or v.name
        print("* " .. raw:gsub("_"," ") .. " - " .. v.total)
        sleep(LIST_DELAY)
      end
    else
      local normalized = choice:gsub("%s+","_")
      local itemName
      for _, p in ipairs(prefixes) do
        local cand = p .. ":" .. normalized
        if index[cand] then itemName = cand break end
      end
      if not itemName then
        print("Item not found: " .. choice)
      else
        local available = index[itemName].total
        print("Available: " .. available)
        local qty = tonumber(prompt("How many to fetch?"))
        if not qty or qty < 1 or qty > available then
          print("Invalid quantity.")
        else
          local moved = fetchItems(index[itemName].sources, qty, OUTPUT_CHEST)
          print("Fetched " .. moved .. " of " .. qty)
        end
      end
    end
  end
end

-- MAIN
if not initRednet() then
  error("No modem found for rednet")
end

rednet.send(CENTRAL_ID, {{ action = "index_request" }}, NETWORK_PROTOCOL)
print("[INFO] Requested global index from server, waiting up to " .. INDEX_TIMEOUT .. "s...")
local sender, msg = rednet.receive(NETWORK_PROTOCOL, INDEX_TIMEOUT)
if sender ~= CENTRAL_ID then
  print("[ERROR] Unexpected sender or timeout")
  return
end
local payload = type(msg)=="table" and msg[1]
if not payload or payload.action ~= "index_response" then
  print("[ERROR] Invalid response")
  return
end

print("[DEBUG] Index payload received from server")

print("[INFO] Index received with " .. tostring(countKeys(payload.data)) .. " item types")
runPrompt(payload.data)

