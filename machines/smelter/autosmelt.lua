-- Smart AutoSmelter for CC:Tweaked (Reworked Architecture)

-- Configuration files
local FURNACES_FILE       = "furnaces.txt"
local SMELTABLE_FILE      = "smeltable.txt"
local FUELS_FILE          = "fuels.txt"
local OUTPUT_CHEST        = "minecraft:chest_43"
local MAX_FUEL_THRESHOLD  = 4
local PROGRESS_BAR_WIDTH  = 20
local CHECK_INTERVAL      = 0.5
local TEXT_SCALE = 1.5

-- State variables
local furnaces = {}
local storage  = {}
local fuels    = {}
local itemCounts = {}
local progressCapacity = 0
local done = false

-- Utility functions ------------------------------------------------------
local function trim(s) return (s or ""):match("^%s*(.-)%s*$") end

local function readLines(path)
  if not fs.exists(path) then return {} end
  local f = fs.open(path, "r")
  if not f then return {} end
  local content = f.readAll()
  f.close()
  local lines = {}
  for line in content:gmatch("([^\n]+)") do
    line = trim(line)
    if #line > 0 then table.insert(lines, line) end
  end
  return lines
end

local function ensureFile(path)
  if not fs.exists(path) then
    local ok, f = pcall(fs.open, path, "w")
    if ok and f then f.close() end
  end
end

-- Load peripherals -------------------------------------------------------
local function loadFurnaces()
  ensureFile(FURNACES_FILE)
  while #furnaces == 0 do
    local names = readLines(FURNACES_FILE)
    for _, name in ipairs(names) do
      if peripheral.isPresent(name) then
        local ok, p = pcall(peripheral.wrap, name)
        if ok and p then table.insert(furnaces, { name = name, per = p }) end
      end
    end
    if #furnaces == 0 then sleep(CHECK_INTERVAL) end
  end
end

local function loadFuels()
  ensureFile(FUELS_FILE)
  fuels = readLines(FUELS_FILE)
end

local function getStorage()
  local set = {}
  for _, f in ipairs(furnaces) do set[f.name] = true end
  for _, name in ipairs(peripheral.getNames()) do
    if not set[name] then
      local ok, p = pcall(peripheral.wrap, name)
      if ok and p and type(p.list) == "function" then
        table.insert(storage, name)
      end
    end
  end
end

-- Build item index from storage ------------------------------------------
local function buildIndex()
  local idx = {}
  for _, chest in ipairs(storage) do
    local p = peripheral.wrap(chest)
    if p then
      local ok, items = pcall(p.list)
      if ok and type(items) == "table" then
        for slot, item in pairs(items) do
          if item and item.name then
            idx[item.name] = idx[item.name] or {}
            table.insert(idx[item.name], { chest = chest, slot = slot })
          end
        end
      end
    end
  end
  return idx
end

-- Scanner thread ---------------------------------------------------------
local function scannerThread()
  print("[INFO] Scanning fuel levels...")
  local idx
  while not done do
    idx = buildIndex()
    local allInputEmpty = true
    local allOutputEmpty = true

    for _, f in ipairs(furnaces) do
      local ok, inD = pcall(f.per.getItemDetail, 1)
      local cnt = (ok and inD and inD.count) or 0
      itemCounts[f.name] = cnt
      if cnt > 0 then allInputEmpty = false end

      local ok2, outD = pcall(f.per.getItemDetail, 3)
      if ok2 and outD and outD.count > 0 then
        f.per.pushItems(OUTPUT_CHEST, 3, outD.count)
        allOutputEmpty = false
      end

      local ok3, fuelD = pcall(f.per.getItemDetail, 2)
      local fc = (ok3 and fuelD and fuelD.count) or 0
      if fc < MAX_FUEL_THRESHOLD then
        for _, name in ipairs(fuels) do
          local slots = idx[name]
          if slots then
            local need = MAX_FUEL_THRESHOLD - fc
            for _, s in ipairs(slots) do
              if need <= 0 then break end
              local cp = peripheral.wrap(s.chest)
              local moved = cp.pushItems(f.name, s.slot, need, 2)
              need = need - (moved or 0)
            end
            break
          end
        end
      end
    end

    local idxFuel = buildIndex()
    local anyFuel = false
    for _, name in ipairs(fuels) do
      if idxFuel[name] and #idxFuel[name] > 0 then anyFuel = true end
    end

    if ((allInputEmpty and allOutputEmpty) or not anyFuel) then
      done = true
    end
  end
end

-- Display thread ---------------------------------------------------------
local function displayThread()
  while progressCapacity == 0 and not done do sleep(0) end

  local mon
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then mon = peripheral.wrap(name); break end
  end
  if mon then
    mon.setTextScale(TEXT_SCALE)
    mon.clear()
  end

  local y = select(2, term.getCursorPos())
  while not done do
    local total = 0
    for _, f in ipairs(furnaces) do total = total + (itemCounts[f.name] or 0) end
    local doneCount = progressCapacity - total
    local pct = math.floor(doneCount / progressCapacity * 100)
    local filled = math.floor(pct / 100 * PROGRESS_BAR_WIDTH)
    local bar = string.rep("#", filled) .. string.rep("-", PROGRESS_BAR_WIDTH - filled)

    term.setCursorPos(1, y)
    term.clearLine()
    write(string.format("T-Progress:[%s] %d%% %d/%d", bar, pct, doneCount, progressCapacity))

    if mon then
      mon.clear()
      mon.setCursorPos(1, 1)
      mon.write(string.format("M-Progress:[%s] %d%%", bar, pct))
    end

    sleep(CHECK_INTERVAL)
  end
  print("\n[SUCCESS] All smelting complete or out of fuel.")
  if mon then mon.setCursorPos(1,2); mon.write("[SUCCESS]") end
end

-- Insertion thread --------------------------------------------------------
local function insertionThread()
  ensureFile(SMELTABLE_FILE)
  local list = readLines(SMELTABLE_FILE)
  local smeltable = {}
  for _, name in ipairs(list) do smeltable[name] = true end

  local totalInFurnaces = 0
  for _, f in ipairs(furnaces) do
    local ok, inD = pcall(f.per.getItemDetail, 1)
    totalInFurnaces = totalInFurnaces + ((ok and inD and inD.count) or 0)
  end

  io.write("Item to smelt (or 'skip'): ")
  local input = trim(read() or "")
  if input:lower() == 'skip' then
    progressCapacity = totalInFurnaces
    return
  end

  local norm = input:lower():gsub("%s+", "_")
  local target
  for name in pairs(smeltable) do
    if name:find(norm, 1, true) then target = name end
  end
  if not target then
    print("[ERROR] Unknown smeltable: " .. input)
    return
  end

  local idx = buildIndex()
  local entry = idx[target]
  if not entry or #entry == 0 then
    print("[ERROR] No items to smelt: " .. target)
    return
  end

  local totalAvail = 0
  for _, slot in ipairs(entry) do
    local p = peripheral.wrap(slot.chest)
    local info = p.getItemDetail(slot.slot)
    if info and info.count and info.count > 0 then
      totalAvail = totalAvail + info.count
    end
  end

  if totalAvail == 0 then
    print("[ERROR] No items to smelt: " .. target)
    return
  end

  io.write(string.format("Found %d %s\n", totalAvail, target))
  io.write("Qty to smelt: ")
  local q = tonumber(trim(read() or ""))
  if not q or q <= 0 or q > totalAvail then
    print("[ERROR] Invalid quantity")
    return
  end

  progressCapacity = q + totalInFurnaces

  local perF = math.floor(q / #furnaces)
  local rem = q % #furnaces
  local neededMap = {}
  for i, f in ipairs(furnaces) do neededMap[f.name] = perF + (i <= rem and 1 or 0) end
  for name, slots in pairs(idx) do
    if name == target then
      for _, slot in ipairs(slots) do
        for _, f in ipairs(furnaces) do
          local need = neededMap[f.name]
          if need > 0 then
            local cp = peripheral.wrap(slot.chest)
            local moved = cp.pushItems(f.name, slot.slot, need, 1)
            neededMap[f.name] = need - (moved or 0)
          end
        end
      end
      break
    end
  end
end

-- Main execution ----------------------------------------------------------
local function main()
  ensureFile(FURNACES_FILE)
  ensureFile(FUELS_FILE)
  loadFurnaces()
  getStorage()
  loadFuels()
  parallel.waitForAll(scannerThread, insertionThread, displayThread)
end

main()
