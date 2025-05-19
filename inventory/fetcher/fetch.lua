-- fetch.lua: Retrieve specified items from networked storage
-- Configuration: set your desired output chest (network peripheral name)
local outputChest = "chest_output"  -- change to your output chest peripheral name
local listLineDelay = 0.5

-- Utility: trim whitespace
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Discover all storage peripherals on network or attached
local function getStoragePeripherals()
  local names = peripheral.getNames()
  local storage = {}
  for _, name in ipairs(names) do
    if peripheral.isPresent(name) then
      local ok, per = pcall(peripheral.wrap, name)
      if ok and type(per.list) == "function" then
        table.insert(storage, name)
      end
    end
  end
  return storage
end

-- Find first attached inventory peripheral (adjacent sides)
local function getAttachedStorage()
  local sides = {"left","right","top","bottom","front","back"}
  for _, side in ipairs(sides) do
    if peripheral.isPresent(side) then
      local ok, per = pcall(peripheral.wrap, side)
      if ok and type(per.list) == "function" then
        return side
      end
    end
  end
  return nil
end

-- Build inventory index: { [itemName] = { total=N, sources={ {chest,slot,count}, ... } } }
local function buildInventoryIndex(storagePeripherals)
  local index = {}
  local prefixSet = {}
  for _, chest in ipairs(storagePeripherals) do
    local per = peripheral.wrap(chest)
    for slot, item in pairs(per.list()) do
      local name  = item.name
      local count = item.count
      -- initialize
      if not index[name] then
        index[name] = { total = 0, sources = {} }
      end
      index[name].total = index[name].total + count
      table.insert(index[name].sources, { chest = chest, slot = slot, count = count })
      -- collect prefix
      local prefix = name:match("^(.-):")
      if prefix and not prefixSet[prefix] then
        prefixSet[prefix] = true
      end
    end
  end
  -- gather prefixes into list
  local prefixes = {}
  for p in pairs(prefixSet) do table.insert(prefixes, p) end
  return index, prefixes
end

-- Prompt user and read line
local function prompt(msg)
  write(msg .. " ")
  return read()
end

-- Main fetch logic
local function main()
  -- 1. Discover storage
  local storage = getStoragePeripherals()
  if #storage == 0 then
    print("Error: No storage peripherals found on network.")
    return
  end
  -- 2. Determine output chest
  local out = getAttachedStorage() or (peripheral.isPresent(outputChest) and outputChest)
  if not out then
    print("Error: No attached storage and outputChest '"..outputChest.."' not found.")
    return
  end
  -- 3. Index items
  print("Indexing items...")
  local index, prefixes = buildInventoryIndex(storage)
  -- 4. Prompt for action
  local choice = trim(string.lower(prompt("Enter item name or 'list':")))
  if choice == "list" then
    -- build list and sort by total desc
    local items = {}
    for name, data in pairs(index) do
      table.insert(items, { name = name, total = data.total })
    end
    table.sort(items, function(a,b) return a.total > b.total end)
    -- print with delay
    for _, v in ipairs(items) do
      print(v.name .. " - " .. v.total)
      sleep(listLineDelay)
    end
    return
  end
  -- 5. Normalize input and find match
  local normalized = choice:gsub("%s+", "_")
  local itemName = nil
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
  local qtyStr = prompt("How many would you like to fetch? ")
  local want = tonumber(qtyStr)
  if not want or want < 1 or want > available then
    print("Invalid quantity.")
    return
  end
  -- 7. Transfer
  local toFetch = want
  local moved = 0
  for _, src in ipairs(index[itemName].sources) do
    if toFetch <= 0 then break end
    local take = math.min(src.count, toFetch)
    local per = peripheral.wrap(src.chest)
    local ok = per.pushItems(out, src.slot, take)
    if ok > 0 then
      moved = moved + ok
      toFetch = toFetch - ok
    end
  end
  -- 8. Report
  if moved < want then
    print("Warning: Only fetched "..moved.." of "..want.." requested.")
  else
    print("Successfully fetched "..moved.." items to "..out)
  end
end

-- Run program
main()

