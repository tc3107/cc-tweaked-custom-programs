-- Persistent Box Excavator with Resume & Auto-Refuel
-- Config -----------------------------------------------------------------
local X = 5                     -- width  (blocks to the right)
local Y = 3                     -- height (blocks up)
local Z = 4                     -- depth  (blocks forward)
local STATE_FILE = "resume_state.txt"

-- State ------------------------------------------------------------------
local state = {
  x   = 1,  -- current X (1..X)
  y   = 1,  -- current Y (1..Y)
  z   = 1,  -- current Z (1..Z)
  dir = 0,  -- 0=+X, 1=+Z, 2=-X, 3=-Z
}

-- Persistence -------------------------------------------------------------
local function saveState()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize(state))
  f.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return false end
  local f = fs.open(STATE_FILE, "r")
  local ok, loaded = pcall(textutils.unserialize, f.readAll())
  f.close()
  if ok and type(loaded)=="table" then state = loaded; return true end
  return false
end

local function deleteState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

-- Movement & Refuel ------------------------------------------------------
local function tryRefuelOnce()
  local fuel = turtle.getFuelLevel()
  if fuel ~= "unlimited" and fuel <= 0 then
    for slot = 1,16 do
      turtle.select(slot)
      if turtle.refuel(0) then
        turtle.refuel()
        return true
      end
    end
    return false
  end
  return true
end

local function moveForward()
  if not tryRefuelOnce() then
    print("✘ No fuel to move forward!") return false
  end
  if not turtle.forward() then
    print("✘ Blocked at ("..state.x..","..state.y..","..state.z..")") 
    return false
  end
  if     state.dir == 0 then state.x = state.x + 1
  elseif state.dir == 1 then state.z = state.z + 1
  elseif state.dir == 2 then state.x = state.x - 1
  elseif state.dir == 3 then state.z = state.z - 1
  end
  return true
end

local function moveUp()
  if not tryRefuelOnce() then
    print("✘ No fuel to move up!") return false
  end
  if not turtle.up() then
    print("✘ Can't move up at layer "..state.y) 
    return false
  end
  state.y = state.y + 1
  return true
end

local function turnLeft()
  turtle.turnLeft()
  state.dir = (state.dir + 3) % 4
end

local function turnRight()
  turtle.turnRight()
  state.dir = (state.dir + 1) % 4
end

-- Digging ---------------------------------------------------------------
local function digAndMoveForward()
  turtle.dig()       -- clear front
  if not moveForward() then return false end
  turtle.digUp()     -- clear ceiling
  turtle.digDown()   -- clear floor
  return true
end

-- Startup Resume Prompt --------------------------------------------------
if loadState() then
  print("A previous session was found. Resume? (y/n)")
  local ans = read()
  if ans:lower() ~= "y" then
    deleteState()
    state = { x=1, y=1, z=1, dir=0 }
  else
    print("Resuming from X="..state.x.." Y="..state.y.." Z="..state.z)
  end
end

-- Main Excavation Logic --------------------------------------------------
for y = state.y, Y do
  state.y = y
  for z = state.z, Z do
    state.z = z

    -- determine X traversal direction
    local xStart, xEnd, step = 1, X, 1
    if z % 2 == 0 then xStart, xEnd, step = X, 1, -1 end

    for x = state.x, xEnd, step do
      state.x = x
      saveState()

      if not digAndMoveForward() then
        print("Halting at X="..state.x.." Y="..state.y.." Z="..state.z)
        return
      end
    end

    -- move to next Z row, if any
    if z < Z then
      if z % 2 == 1 then
        turnRight(); 
        if not digAndMoveForward() then return end
        turnRight()
      else
        turnLeft();  
        if not digAndMoveForward() then return end
        turnLeft()
      end
      state.x = (z % 2 == 1) and X or 1
      saveState()
    end
  end

  -- ascend one layer
  if y < Y then
    -- clear any block above
    turtle.digUp()
    if not moveUp() then return end
    -- flip direction for snake pattern on new layer
    turnLeft(); turnLeft()
    state.z = 1
    saveState()
  end
end

-- Cleanup ----------------------------------------------------------------
deleteState()
print("✅ Box excavation complete!") 
