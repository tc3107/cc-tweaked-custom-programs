-- Persistent Box Excavator with Return-to-Start, Resume & Auto-Refuel
-------------------------------------------------------------------------------

-- Forward, Up, Right
local X, Y, Z      = 5, 3, 4
local STATE_FILE   = "resume_state.txt"

-- STATE (x, y, z, dir, stage)
-- dir: 0=+X, 1=+Z, 2=-X, 3=-Z
-- stage: "dig", "return", "ascend"
local state = { x=1, y=1, z=1, dir=0, stage="dig" }

-- PERSISTENCE --------------------------------------------------------------
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
  if ok and type(tbl)=="table" then state = tbl return true end
  return false
end

local function deleteState()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
end

-- AUTO-REFUEL (one-shot) --------------------------------------------------
local function tryRefuelOnce()
  local f = turtle.getFuelLevel()
  if f ~= "unlimited" and f <= 0 then
    for s=1,16 do
      turtle.select(s)
      if turtle.refuel(0) then turtle.refuel() return true end
    end
    return false
  end
  return true
end

-- TURN AND FACING ---------------------------------------------------------
local function turnLeft()
  turtle.turnLeft()
  state.dir = (state.dir + 3) % 4
end

local function turnRight()
  turtle.turnRight()
  state.dir = (state.dir + 1) % 4
end

local function faceDir(target)
  while state.dir ~= target do turnRight() end
end

-- MOVEMENT ----------------------------------------------------------------
local function moveForward()
  if not tryRefuelOnce() then print("✘ No fuel to move forward!") return false end
  while turtle.detect() do turtle.dig() end
  if not turtle.forward() then return false end
  if     state.dir == 0 then state.x = state.x + 1
  elseif state.dir == 1 then state.z = state.z + 1
  elseif state.dir == 2 then state.x = state.x - 1
  else                       state.z = state.z - 1 end
  return true
end

local function moveUp()
  if not tryRefuelOnce() then print("✘ No fuel to move up!") return false end
  while turtle.detectUp() do turtle.digUp() end
  if not turtle.up() then return false end
  state.y = state.y + 1
  return true
end

local function digAndMoveForward()
  return moveForward()
end

-- RETURN TO LAYER START --------------------------------------------------
local function returnToLayerStart()
  -- return along X to 1
  local dx = 1 - state.x
  if dx ~= 0 then
    local dirX = dx > 0 and 0 or 2
    faceDir(dirX)
    for i=1,math.abs(dx) do if not moveForward() then return false end end
  end
  -- return along Z to 1
  local dz = 1 - state.z
  if dz ~= 0 then
    local dirZ = dz > 0 and 1 or 3
    faceDir(dirZ)
    for i=1,math.abs(dz) do if not moveForward() then return false end end
  end
  state.x, state.z = 1, 1
  saveState()
  faceDir(0)
  return true
end

-- STARTUP: LOAD & PROMPT RESUME -------------------------------------------
if loadState() then
  print("Resume previous session? (y/n)")
  if read():lower() ~= "y" then
    deleteState()
    state = { x=1, y=1, z=1, dir=0, stage="dig" }
  end
else
  saveState()
end

-- MAIN LOOP ---------------------------------------------------------------
while true do
  -- if beyond last layer, finish
  if state.y > Y then
    deleteState()
    print("✅ Box excavation complete!")
    return
  end

  if state.stage == "return" then
    if not returnToLayerStart() then error("Failed to return to layer start.") end
    state.stage = "ascend"
    saveState()
  end

  if state.stage == "ascend" then
    if not moveUp() then error("Failed to ascend from layer "..state.y) end
    state.stage = "dig"
    state.x, state.z = 1, 1
    saveState()
  end

  if state.stage == "dig" then
    for z = state.z, Z do
      state.z = z
      saveState()

      -- determine snake pattern on X
      local xStart, xEnd, xStep = 1, X, 1
      if z % 2 == 0 then xStart, xEnd, xStep = X, 1, -1 end
      local startX = (z == state.z) and state.x or xStart

      for x = startX, xEnd, xStep do
        state.x = x
        saveState()
        if x ~= xEnd then
          if not digAndMoveForward() then
            print(string.format("Halting at X=%d Y=%d Z=%d", state.x, state.y, state.z))
            return
          end
        end
      end

      -- move to next row if needed
      if z < Z then
        faceDir(1)
        if not digAndMoveForward() then error("Failed stepping to next row.") end
        if z % 2 == 1 then faceDir(2) else faceDir(0) end
        state.x = xEnd
        state.z = z + 1
        saveState()
      end
    end

    -- if last layer, finish; else return to start
    if state.y == Y then
      deleteState()
      print("✅ Box excavation complete!")
      return
    else
      state.stage = "return"
      saveState()
    end
  end
end
