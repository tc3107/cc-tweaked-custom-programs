-- Smart AutoSmelter for CC:Tweaked
-- Streamlined: no refuel/output prints, dynamic progress updates

-- Configuration files and settings
local FURNACES_FILE       = "furnaces.txt"
local SMELTABLE_FILE      = "smeltable.txt"
local FUELS_FILE          = "fuels.txt"   -- new fuels list file
local OUTPUT_CHEST        = "minecraft:chest_X"
local FUEL_PER_COAL       = 8            -- smelts per coal
local MAX_FUEL_THRESHOLD  = 2            -- refill threshold
local PROGRESS_BAR_WIDTH  = 20           -- characters in progress bar
local CHECK_INTERVAL      = 1            -- seconds for all loops

-- Utility: trim
local function trim(s)
  return (s or ""):match("^%s*(.-)%s*$")
end

-- Read lines
local function readLines(path)
  if not fs.exists(path) then return {} end
  local file = fs.open(path, "r") if not file then return {} end
  local content = file.readAll() file.close()
  local lines = {}
  for line in content:gmatch("([^\n]+)") do
    line = trim(line)
    if #line>0 then table.insert(lines,line) end
  end
  return lines
end

-- Ensure file
local function ensureFile(path)
  if not fs.exists(path) then local ok,f=pcall(fs.open,path,"w") if ok and f then f.close() end end
end

-- Load furnaces
local function loadFurnaces()
  ensureFile(FURNACES_FILE)
  while true do
    local names = readLines(FURNACES_FILE)
    local fsList = {}
    for _,n in ipairs(names) do
      if peripheral.isPresent(n) then
        local ok,per = pcall(peripheral.wrap,n)
        if ok and per then table.insert(fsList,{name=n,per=per}) end
      end
    end
    if #fsList>0 then return fsList end
    sleep(CHECK_INTERVAL)
  end
end

-- Load fuels in order
local function loadFuels()
  ensureFile(FUELS_FILE)
  local lines = readLines(FUELS_FILE)
  local fuels = {}
  for _, line in ipairs(lines) do table.insert(fuels, line) end
  return fuels
end

-- Discover storage (exclude furnaces)
local function getStorage(furnaces)
  local furnaceSet={}
  for _,f in ipairs(furnaces) do furnaceSet[f.name]=true end
  local list={}
  for _,n in ipairs(peripheral.getNames()) do
    if not furnaceSet[n] then
      local ok,per=pcall(peripheral.wrap,n)
      if ok and per and type(per.list)=="function" then table.insert(list,n) end
    end
  end
  return list
end

-- Build inventory index
local function buildIndex(storage)
  local idx={}
  for _,chest in ipairs(storage) do
    local per=peripheral.wrap(chest)
    if per then
      local ok,items = pcall(per.list)
      if ok and type(items)=="table" then
        for slot,item in pairs(items) do
          if item and item.name then
            local nm,count=item.name,item.count
            idx[nm]=idx[nm] or {total=0,sources={}}
            idx[nm].total=idx[nm].total+count
            table.insert(idx[nm].sources,{chest=chest,slot=slot,count=count})
          end
        end
      end
    end
  end
  return idx
end

-- Collect output (no prints)
local function collectOutput(furnaces)
  for _,f in ipairs(furnaces) do
    local out=f.per.getItemDetail(3)
    if out and out.count>0 then
      f.per.pushItems(OUTPUT_CHEST,3,out.count)
    end
  end
end

-- Monitor furnaces: fuel and output
local function monitorFurnaces(furnaces,storage)
  local warned=false
  while true do
    collectOutput(furnaces)
    local fuels = loadFuels()
    local idx=buildIndex(storage)
    for _,f in ipairs(furnaces) do
      local fuel=f.per.getItemDetail(2)
      local fc=(fuel and fuel.count) or 0
      if fc<MAX_FUEL_THRESHOLD then
        local inD=f.per.getItemDetail(1)
        local needed=math.max(1,math.ceil(((inD and inD.count)or 0)/FUEL_PER_COAL)-fc)
        local refueled=false
        for _,fuelName in ipairs(fuels) do
          local entry=idx[fuelName]
          if entry and entry.total>0 then
            local rem=needed
            for _,src in ipairs(entry.sources) do
              if rem<=0 then break end
              local cp=peripheral.wrap(src.chest)
              local mv=cp.pushItems(f.name,src.slot,rem,2)
              if mv and mv>0 then rem=rem-mv end
            end
            refueled=true
            break
          end
        end
        warned=not refueled
      end
    end
    sleep(CHECK_INTERVAL)
  end
end

-- Progress bar updates only on change
local function displayProgress(furnaces)
  local capacity=#furnaces*64
  local _,y=term.getCursorPos()
  local prev= -1
  while true do
    local total=0
    for _,f in ipairs(furnaces) do
      local inD=f.per.getItemDetail(1)
      if inD then total=total+inD.count end
    end
    if total==0 then break end
    if total~=prev then
      local pct=math.floor(total/capacity*100)
      local filled=math.floor(pct/100*PROGRESS_BAR_WIDTH)
      local bar=string.rep("#",filled)..string.rep("-",PROGRESS_BAR_WIDTH-filled)
      term.setCursorPos(1,y)
      term.clearLine()
      write(string.format("Progress:[%s]%d%% %d/%d",bar,pct,total,capacity))
      prev=total
    end
    sleep(CHECK_INTERVAL)
  end
  print("\n[SUCCESS] All input slots empty.")
end

-- Main smelting
local function smeltMain(furnaces,storage)
  ensureFile(SMELTABLE_FILE)
  local list=readLines(SMELTABLE_FILE)
  local smeltable={}
  for _,i in ipairs(list) do smeltable[i]=true end
  while true do
    io.write("Item to smelt (or 'skip'): ")
    local c=trim(read() or "") if c:lower()=="skip" then break end
    local norm=c:lower():gsub("%s+","_")
    local full=nil
    for item in pairs(smeltable) do if item:find(norm,1,true) then full=item end end
    if not full then goto cont end
    local idx=buildIndex(storage)
    local entry=idx[full] if not entry then return end
    local avail=entry.total
    local cap=#furnaces*64
    io.write(string.format("Found %d %s | Cap %d\n",avail,full,cap))
    io.write("Qty to smelt: ")
    local q=tonumber(trim(read() or ""))
    if not q or q<1 or q>avail or q>cap then goto cont end
    local perF=math.floor(q/#furnaces)
    local rem=q%#furnaces
    for i,f in ipairs(furnaces) do
      local tgt=perF+(i<=rem and 1 or 0)
      local mv=0
      if tgt>0 then
        local inD=f.per.getItemDetail(1)
        local free=64-((inD and inD.count)or 0)
        local send=math.min(tgt,free)
        for _,s in ipairs(entry.sources) do
          if send<=0 then break end
          local cp=peripheral.wrap(s.chest)
          local ok=cp.pushItems(f.name,s.slot,send,1)
          if ok and ok>0 then mv=mv+ok;send=send-ok end
        end
      end
      io.write(string.format("F%d:%d/%d ",i,mv,tgt))
    end
    io.write("\n")
    break
    ::cont::
  end
  displayProgress(furnaces)
end

-- Entry
local function main()
  ensureFile(FURNACES_FILE)
  ensureFile(SMELTABLE_FILE)
  ensureFile(FUELS_FILE)
  local furnaces=loadFurnaces()
  local storage=getStorage(furnaces)
  parallel.waitForAll(
    function() monitorFurnaces(furnaces,storage) end,
    function() smeltMain(furnaces,storage) end
  )
end

main()
