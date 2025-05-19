-- fetch.lua: Retrieve specified items from networked storage
-- Configuration: set your desired output chest (network peripheral name)
local outputChest = "minecraft:chest_X"
local listLineDelay = 0.75

-- Utility: trim whitespace
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Discover all storage peripherals on network
local function getStoragePeripherals()
  local storage = {}
  for _, name in ipairs(peripheral.getNames()) do
    local ok, per = pcall(peripheral.wrap, name)
    if ok and type(per.list) == "function" then
      table.insert(storage, name)
    end
  end
  return storage
end

-- Build inventory index quickly using per.list()
-- { [itemName] = { total=N, sources={ {chest,slot,count}, ... } } }
local function buildInventoryIndex(storagePeripherals)
  local index = {}
  local prefixSet = {}
  for _, chest in ipairs(storagePeripherals) do
    local per = peripheral.wrap(chest)
    for slot, item in pairs(per.list()) do
      local name  = item.name
      local count = item.count
      -- initialize if needed
      if not index[name] then
        index[name] = { total = 0, sources = {} }
      end
      -- accumulate total and record source
      index[name].total = index[name].total + count
      table.insert(index[name].sources, { chest = chest, slot = slot, count = count })
      -- collect prefix for modded lookup
      local prefix = name:match("^(.-):")
      if prefix then prefixSet[prefix] = true end
    end
  end
  -- convert prefix set into list
  local prefixes = {}
  for p in pairs(prefixSet) do table.insert(prefixes, p) end
  return index, prefixes
end

-- Prompt user and read line
local function prompt(msg)
  write(msg .. " ")
  return read()
end

-- Get free slots in a chest peripheral
local function getFreeSpace(chestName)
  local per = peripheral.wrap(chestName)
  local total = per.size()
  local used = 0
  for _, item in pairs(per.list()) do
    if item then used = used + 1 end
  end
  return total - used
end

-- Main fetch logic
local function main()
  -- 1. Discover storage
  local storage = getStoragePeripherals()
  if #storage == 0 then
    print("Error: No storage peripherals found on network.")
    return
  end

  -- 2. Determine output chest (network only)
  if not peripheral.isPresent(outputChest) then
    print("Error: outputChest '" .. outputChest .. "' not found on network.")
    return
  end
  local outName = outputChest

  -- 3. Index items quickly
  print("Indexing items...")
  local index, prefixes = buildInventoryIndex(storage)

  -- 4. Prompt for action
  local choice = trim(string.lower(prompt("Enter item name or 'list':")))
  if choice == "list" then
    local items = {}
    for name, data in pairs(index) do
      table.insert(items, { name = name, total = data.total })
    end
    table.sort(items, function(a,b) return a.total > b.total end)
    for _, v in ipairs(items) do
      print(v.name .. " - " .. v.total)
      sleep(listLineDelay)
    end
    return
  end

  -- 5. Normalize input and find match
  local normalized = choice:gsub("%s+", "_")
  local itemName
  for _, prefix in ipairs(prefixes) do
    local candidate = prefix .. ":" .. normalized
    if index[candidate] then
      itemName = candidate
      break
    end
  end
  if not itemName then
    print("Item not found: " .. choice)
    return
  end

  local available = index[itemName].total
  print("Available: " .. available)

  -- 6. Quantity
  local qtyStr = prompt("How many would you like to fetch?")
  local want = tonumber(qtyStr)
  if not want or want < 1 or want > available then
    print("Invalid quantity.")
    return
  end

  -- 7. Transfer with chest-full check
  local toFetch = want
  local moved = 0
  for _, src in ipairs(index[itemName].sources) do
    if toFetch <= 0 then break end
    -- Check output chest space
    local free = getFreeSpace(outName)
    if free <= 0 then
      print("Output chest is full. Stopping transfer.")
      break
    end
    -- calculate take amount without exceeding needed count
    local take = math.min(src.count, toFetch)
    local per = peripheral.wrap(src.chest)
    local ok = per.pushItems(outName, src.slot, take)
    if ok and ok > 0 then
      moved = moved + ok
      toFetch = toFetch - ok
    end
  end

  -- 8. Report
  print("Fetched " .. moved .. " of " .. want .. " requested.")
end

-- Run program
main()
