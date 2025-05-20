-- Persistent Box Excavator with Refined Digging, Resume & Auto-Refuel
----------------------------------------------------------------------------- 
-- CONFIG
local X, Y, Z             = 5, 3, 4                -- box dimensions
local STATE_FILE          = "resume_state.txt"
----------------------------------------------------------------------------- 
-- STATE
local state = { x=1, y=1, z=1, dir=0 }               -- 0=+X,1=+Z,2=–X,3=–Z
----------------------------------------------------------------------------- 
-- PERSISTENCE
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
  if ok and type(loaded)=="table" then state=loaded return true end
  return false
end

local function deleteState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end
----------------------------------------------------------------------------- 
-- AUTO-REFUEL (one–shot; if no fuel, movement will fail & script will exit)
local function tryRefuelOnce()
  local f = turtle.getFuelLevel()
  if f ~= "unlimited" and f <= 0 then
    for slot=1,16 do
      turtle.select(slot)
      if turtle.refuel(0) then turtle.refuel() return true end
    end
    return false
  end
  return true
end
----------------------------------------------------------------------------- 
-- MOVEMENT (updates state.x/y/z & applies tryRefuelOnce)

local function moveForward()
  if not tryRefuelOnce() then
    print("✘ No fuel to move forward!") return false
  end
  while turtle.detect() do turtle.dig() end       -- only dig front
  if not turtle.forward() then
    print("✘ Blocked at ("..state.x..","..state.y..","..state.z..")")
    return false
  end
  if     state.dir==0 then state.x=state.x+1
  elseif state.dir==1 then state.z=state.z+1
  elseif state.dir==2 then state.x=state.x-1
  else                       state.z=state.z-1
  end
  return true
end

local function moveUp()
  if not tryRefuelOnce() then
    print("✘ No fuel to move up!") return false
  end
  while turtle.detectUp() do turtle.digUp() end     -- only dig above
  if not turtle.up() then
    print("✘ Can't ascend at layer "..state.y) 
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
----------------------------------------------------------------------------- 
-- DIG + MOVE FORWARD (no more digUp/digDown here!)
local function digAndMoveForward()
  return moveForward()
end
----------------------------------------------------------------------------- 
-- RESUME PROMPT
if loadState() then
  print("A saved session was found. Resume? (y/n)")
  if read():lower() ~= "y" then
    deleteState()
    state = { x=1, y=1, z=1, dir=0 }
  else
    print("Resuming at X="..state.x.." Y="..state.y.." Z="..state.z)
  end
end
----------------------------------------------------------------------------- 
-- MAIN EXCAVATION
for y = state.y, Y do
  state.y = y
  -- if this isn’t the very first layer, move up into it:
  if y > 1 then
    if not moveUp() then return end
    -- flip 180° so our snake‐pattern continues correctly
    turnLeft(); turnLeft()
  end

  for z = state.z, Z do
    state.z = z

    -- decide X-traversal order
    local xStart, xEnd, xStep = 1, X, 1
    if z % 2 == 0 then
      xStart, xEnd, xStep = X, 1, -1
    end

    for x = state.x, xEnd, xStep do
      state.x = x
      saveState()

      -- clear the block we're moving into
      if x ~= xEnd or z~=Z or y~=Y then
        -- (if it’s the very last cell of the box we’ll exit after saving)
        if not digAndMoveForward() then
          print("Halting at X="..state.x.." Y="..state.y.." Z="..state.z)
          return
        end
      end
    end

    -- step into next Z-row (snake turn)
    if z < Z then
      if z % 2 == 1 then
        turnRight()
        if not digAndMoveForward() then return end
        turnRight()
      else
        turnLeft()
        if not digAndMoveForward() then return end
        turnLeft()
      end
      state.x = (z % 2 == 1) and X or 1
      saveState()
    end
  end

  -- reset state.x/z for next layer
  state.x, state.z = 1, 1
  saveState()
end

-- CLEANUP
deleteState()
print("✅ Box excavation complete!")
