-- Persistent Box Excavator with Return-to-Start, Resume & Auto-Refuel
-------------------------------------------------------------------------------
-- CONFIG
local X, Y, Z      = 5, 3, 4                   -- box dimensions
local STATE_FILE   = "resume_state.txt"

-- STATE
local state = { x=1, y=1, z=1, dir=0 }          -- dir: 0=+X,1=+Z,2=-X,3=-Z

-- PERSISTENCE
local function saveState()
  local f = fs.open(STATE_FILE, "w")
  f.write(textutils.serialize(state))
  f.close()
end

local function loadState()
  if not fs.exists(STATE_FILE) then return false end
  local f = fs.open(STATE_FILE, "r")
  local ok, tbl = pcall(textutils.unserialize, f.readAll())
  f.close()
  if ok and type(tbl)=="table" then state=tbl; return true end
  return false
end

local function deleteState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

-- AUTO-REFUEL (one-shot)
local function tryRefuelOnce()
  local f = turtle.getFuelLevel()
  if f ~= "unlimited" and f <= 0 then
    for s=1,16 do
      turtle.select(s)
      if turtle.refuel(0) then
        turtle.refuel()
        return true
      end
    end
    return false
  end
  return true
end

-- TURN/ORIENT
local function turnLeft()
  turtle.turnLeft()
  state.dir = (state.dir + 3) % 4
end

local function turnRight()
  turtle.turnRight()
  state.dir = (state.dir + 1) % 4
end

local function faceDir(target)
  -- rotate right until we hit target
  while state.dir ~= target do
    turnRight()
  end
end

-- MOVEMENT
local function moveForward()
  if not tryRefuelOnce() then
    print("✘ No fuel to move forward!") return false
  end
  while turtle.detect() do turtle.dig() end      -- only clear front
  if not turtle.forward() then
    print("✘ Blocked at ("..state.x..","..state.y..","..state.z..")")
    return false
  end
  if     state.dir==0 then state.x = state.x + 1
  elseif state.dir==1 then state.z = state.z + 1
  elseif state.dir==2 then state.x = state.x - 1
  else                       state.z = state.z - 1
  end
  return true
end

local function moveUp()
  if not tryRefuelOnce() then
    print("✘ No fuel to move up!") return false
  end
  while turtle.detectUp() do turtle.digUp() end  -- only clear above
  if not turtle.up() then
    print("✘ Can't ascend at layer "..state.y) return false
  end
  state.y = state.y + 1
  return true
end

-- DIG & MOVE
local function digAndMoveForward()
  return moveForward()
end

-- RETURN TO START OF CURRENT LAYER (1,1) AND FACE +X
local function returnToLayerStart()
  -- X axis
  local dx = 1 - state.x
  if dx ~= 0 then
    local dirX = (dx > 0) and 0 or 2
    faceDir(dirX)
    for i=1, math.abs(dx) do
      if not moveForward() then
        print("✘ Couldn't return on X axis") return false
      end
    end
  end
  -- Z axis
  local dz = 1 - state.z
  if dz ~= 0 then
    local dirZ = (dz > 0) and 1 or 3
    faceDir(dirZ)
    for i=1, math.abs(dz) do
      if not moveForward() then
        print("✘ Couldn't return on Z axis") return false
      end
    end
  end
  state.x, state.z = 1, 1
  saveState()
  faceDir(0)  -- face +X
  return true
end

-- STARTUP: RESUME PROMPT
local resumed = loadState()
local origY   = state.y
if resumed then
  print("Resume previous session? (y/n)")
  if read():lower() ~= "y" then
    deleteState()
    state = { x=1, y=1, z=1, dir=0 }
    origY = 1
  else
    print("Resuming at X="..state.x.." Y="..state.y.." Z="..state.z)
  end
end

-- MAIN EXCAVATION
for y = state.y, Y do
  state.y = y

  -- if starting a new layer (beyond original), return to (1,1) then ascend
  if y > origY then
    if not returnToLayerStart() then return end
    if not moveUp()               then return end
    -- after ascending, ensure facing +X
    faceDir(0)
  end

  -- determine starting Z for resumed layer
  local startZ = (y==origY) and state.z or 1

  for z = startZ, Z do
    state.z = z

    -- determine X traversal direction for snake pattern
    local xStart, xEnd, xStep
    if z % 2 == 1 then
      xStart, xEnd, xStep = 1, X, 1
    else
      xStart, xEnd, xStep = X, 1, -1
    end

    -- resume X only on first row of resumed layer
    local firstX = (y==origY and z==startZ) and state.x or xStart

    for x = firstX, xEnd, xStep do
      state.x = x
      saveState()
      -- if not the very last cell, dig & move
      if not (x==xEnd and z==Z and y==Y) then
        if not digAndMoveForward() then
          print("Halting at X="..state.x.." Y="..state.y.." Z="..state.z)
          return
        end
      end
    end

    -- move into next Z-row if any
    if z < Z then
      -- turn toward +Z
      if     state.dir==0 then turnRight()
      elseif state.dir==2 then turnLeft() end

      if not digAndMoveForward() then return end

      -- turn back toward +X or -X
      if z % 2 == 1 then turnRight() else turnLeft() end

      state.x = xEnd
      saveState()
    end
  end

  -- reset for next layer (will be handled by returnToLayerStart)
  origY = origY  -- no-op
end

-- CLEANUP
deleteState()
print("✅ Box excavation complete!")
