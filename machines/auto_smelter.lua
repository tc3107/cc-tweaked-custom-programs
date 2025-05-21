-- Smart AutoSmelter for CC:Tweaked
-- Maintains networked furnaces, auto-refuels dynamically, distributes items safely, and displays progress

-- Configuration files
local FURNACES_FILE = "furnaces.txt"
local SMELTABLE_FILE = "smeltable.txt"
local COAL_ITEM = "minecraft:coal"
local FUEL_PER_COAL = 8 -- number of smelts per coal
local MAX_FUEL_THRESHOLD = 2 -- below this triggers refuel

-- Utility: trim whitespace
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Utility: split text into lines
local function readLines(path)
  if not fs.exists(path) then return {} end
  local file, err = fs.open(path, "r")
  if not file then
    print("Error reading file "..path..": "..tostring(err))
    return {}
  end
  local content = file.readAll()
  file.close()
  local lines = {}
  for line in content:gmatch("([^\n]+)") do
    line = trim(line)
    if #line > 0 then table.insert(lines, line) end
  end
  return lines
end

-- Utility: write lines to file
local function writeLines(path, lines)
  local file, err = fs.open(path, "w")
  if not file then
    print("Error writing file "..path..": "..tostring(err))
    return false
  end
  for _, line in ipairs(lines) do file.writeLine(line) end
  file.close()
  return true
end

-- Ensure file exists
local function ensureFile(path)
  if not fs.exists(path) then
    local ok, err = pcall(fs.open, path, "w")
    if not ok then print("Error creating file "..path..": "..tostring(err)) end
  end
end

-- Discover storage peripherals (non-furnace inventories)
local function getStoragePeripherals()
  local storage = {}
  for _, name in ipairs(peripheral.getNames()) do
    local ok, per = pcall(peripheral.wrap, name)
    if ok and type(per.list) == "function" then
      -- exclude furnace by ability to smelt
      if not (type(per.getInputDetail) == "function") then
        table.insert(storage, name)
      end
    end
  end
  return storage
end

-- Build inventory index: { [itemName] = { total=N, sources={ {chest,slot,count}, ... } } }
local function buildInventoryIndex(storages)
  local index = {}
  for _, chest in ipairs(storages) do
    local per = peripheral.wrap(chest)
    for slot, item in pairs(per.list()) do
      local name  = item.name
      local count = item.count
      if not index[name] then index[name] = { total = 0, sources = {} } end
      index[name].total = index[name].total + count
      table.insert(index[name].sources, { chest = chest, slot = slot, count = count })
    end
  end
  return index
end

-- Load furnaces list, prompt retry if empty
local function loadFurnaces()
  ensureFile(FURNACES_FILE)
  local names = readLines(FURNACES_FILE)
  local furnaces = {}
  for _, name in ipairs(names) do
    if peripheral.isPresent(name) then
      local ok, per = pcall(peripheral.wrap, name)
      if ok then table.insert(furnaces, { name = name, per = per }) end
    end
  end
  while #furnaces == 0 do
    print("No furnaces configured. Please add at least one to "..FURNACES_FILE)
    print("Press Enter when ready...")
    read()
    names = readLines(FURNACES_FILE)
    furnaces = {}
    for _, name in ipairs(names) do
      if peripheral.isPresent(name) then
        local ok, per = pcall(peripheral.wrap, name)
        if ok then table.insert(furnaces, { name = name, per = per }) end
      end
    end
  end
  return furnaces
end

-- Dynamic fuel monitoring
local function monitorFuel(furnaces, storages)
  local warned = false
  while true do
    -- index storage each loop
    local index = buildInventoryIndex(storages)
    for _, f in ipairs(furnaces) do
      local fuelDetail = f.per.getItemDetail(2)
      local fuelCount = fuelDetail and fuelDetail.count or 0
      if fuelCount < MAX_FUEL_THRESHOLD then
        -- dynamic amount: refill to cover current input
        local inputDetail = f.per.getItemDetail(1)
        local toSmelt = inputDetail and inputDetail.count or 0
        local neededCoal = math.ceil(toSmelt / FUEL_PER_COAL)
        local give = math.max(1, neededCoal - fuelCount)
        local data = index[COAL_ITEM]
        if data and data.total > 0 then
          local remaining = give
          for _, src in ipairs(data.sources) do
            if remaining <= 0 then break end
            local chestPer = peripheral.wrap(src.chest)
            local moved = chestPer.pushItems(f.name, src.slot, remaining, 2)
            if moved and moved > 0 then
              remaining = remaining - moved
            end
          end
          warned = false
        else
          if not warned then
            print("⚠️ Warning: "..COAL_ITEM.." not found in network.")
            warned = true
          end
        end
      end
    end
    sleep(1)
  end
end

-- Display progress bar with proper cursor control
local function displayProgress(furnaces)
  local capacity = #furnaces * 64
  local _, startY = term.getCursorPos()
  while true do
    local totalItems = 0
    for _, f in ipairs(furnaces) do
      for slot=1,3 do
        local d = f.per.getItemDetail(slot)
        if d then totalItems = totalItems + d.count end
      end
    end
    if totalItems == 0 then break end
    local pct = math.floor((totalItems / capacity) * 100)
    local blocks = math.floor(pct / 10)
    local bar = string.rep("█", blocks) .. string.rep("░", 10 - blocks)
    term.setCursorPos(1, startY)
    term.clearLine()
    write(string.format("Progress: %s %3d%% (%d/%d)\n", bar, pct, totalItems, capacity))
    sleep(1)
  end
  print("✅ All furnaces are empty. Smelting complete.")
end

-- Smelting main logic with safety checks and suggestions
local function smeltMain(furnaces, storages)
  ensureFile(SMELTABLE_FILE)
  local smeltableList = readLines(SMELTABLE_FILE)
  local smeltable = {}
  for _, item in ipairs(smeltableList) do smeltable[item] = true end

  while true do
    write("Enter item to smelt (or 'skip'): ")
    local choice = trim(read() or "")
    if choice:lower() == "skip" then break end

    -- normalize and find matches
    local norm = choice:lower():gsub("%s+","_")
    local fullName = nil
    local suggestions = {}
    for item in pairs(smeltable) do
      if item:find(norm,1,true) then fullName = item end
      if #suggestions < 5 and item:find(norm) then table.insert(suggestions, item) end
    end
    if not fullName then
      print("Error: '"..choice.."' not smeltable.")
      if #suggestions>0 then
        print("Did you mean?")
        for _, s in ipairs(suggestions) do print(" - "..s) end
      end
    else
      local index = buildInventoryIndex(storages)
      local available = index[fullName] and index[fullName].total or 0
      local maxCap = #furnaces * 64
      print(string.format("Available: %d (Max furnace capacity: %d)", available, maxCap))
      write("Quantity to smelt: ")
      local qty = tonumber(trim(read() or ""))
      if not qty or qty < 1 or qty > available or qty > maxCap then
        print("Invalid quantity. Must be <= available and <= total furnace capacity.")
      else
        -- distribute items safely
        local perF = math.floor(qty / #furnaces)
        local rem = qty % #furnaces
        for i,f in ipairs(furnaces) do
          local target = perF + (i<=rem and 1 or 0)
          local movedTotal = 0
          if target>0 then
            -- check free input space
            local inDetail = f.per.getItemDetail(1)
            local used = inDetail and inDetail.count or 0
            local free = 64 - used
            local toSend = math.min(target, free)
            local remaining = toSend
            for _,src in ipairs(index[fullName].sources) do
              if remaining<=0 then break end
              local chestPer = peripheral.wrap(src.chest)
              local moved = chestPer.pushItems(f.name, src.slot, remaining, 1)
              if moved and moved>0 then
                remaining = remaining - moved
                movedTotal = movedTotal + moved
              end
            end
          end
          if movedTotal < target then
            print(string.format("⚠️ Furnace %d: Moved %d of %d requested", i, movedTotal, target))
          else
            print(string.format("Furnace %d: Received %d %s", i, movedTotal, fullName))
          end
        end
        break
      end
    end
  end
  displayProgress(furnaces)
end

-- Entry point
local function main()
  -- ensure config files
  ensureFile(FURNACES_FILE)
  ensureFile(SMELTABLE_FILE)

  -- load peripherals
  local furnaces = loadFurnaces()
  local storages = getStoragePeripherals()
  if #storages==0 then print("Warning: No storage peripherals found.") end

  -- run monitor and smelt logic in parallel
  parallel.waitForAll(
    function() monitorFuel(furnaces, storages) end,
    function() smeltMain(furnaces, storages) end
  )
end

-- Execute
main()
