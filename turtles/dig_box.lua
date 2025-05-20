-- Persistent Box Excavator with Correct Layer Flips, Resume & Auto-Refuel
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
  if f~="unlimited" and f<=0 then
    for s=1,16 do
      turtle.select(s)
      if turtle.refuel(0) then turtle.refuel(); return true end
    end
    return false
  end
  return true
end

-- MOVEMENT & DIGGING
local function turnLeft()  turtle.turnLeft();  state.dir=(state.dir+3)%4  end
local function turnRight() turtle.turnRight(); state.dir=(state.dir+1)%4  end

local function moveForward()
  if not tryRefuelOnce() then print("✘ No fuel!") return false end
  while turtle.detect() do turtle.dig() end                -- only dig front
  if not turtle.forward() then return false end
  if     state.dir==0 then state.x+=1
  elseif state.dir==1 then state.z+=1
  elseif state.dir==2 then state.x-=1
  else                      state.z-=1
  end
  return true
end

local function moveUp()
  if not tryRefuelOnce() then print("✘ No fuel!") return false end
  while turtle.detectUp() do turtle.digUp() end            -- only dig above
  if not turtle.up() then return false end
  state.y+=1
  return true
end

local function digAndMoveForward()
  return moveForward()
end

-- STARTUP: RESUME?
local loaded = loadState()
local origY = state.y
if loaded then
  print("Resume previous session? (y/n)")
  if read():lower()~="y" then
    deleteState()
    state = { x=1, y=1, z=1, dir=0 }
    origY = 1
  end
end

-- MAIN EXCAVATION
for y = state.y, Y do
  state.y = y

  -- ascend into new layer if needed
  if y > origY then
    if not moveUp() then return end
    -- after rising, orient to +X
    while state.dir~=0 do turnRight() end
  end

  local startZ = (y==origY) and state.z or 1

  for z = startZ, Z do
    state.z = z

    -- choose X-loop direction
    local xStart, xEnd, xStep
    if z%2==1 then xStart,xEnd,xStep = 1, X, 1
    else           xStart,xEnd,xStep = X, 1, -1
    end

    -- resume X on first row if needed
    local firstX = (y==origY and z==startZ) and state.x or xStart

    for x = firstX, xEnd, xStep do
      state.x = x
      saveState()
      -- skip final cell of box (no forward move after last block)
      if not (x==xEnd and z==Z and y==Y) then
        if not digAndMoveForward() then
          print("Halting at X="..state.x.." Y="..state.y.." Z="..state.z)
          return
        end
      end
    end

    -- move into next Z row if any
    if z < Z then
      -- turn toward +Z
      if     state.dir==0 then turnRight()
      elseif state.dir==2 then turnLeft()
      end
      if not digAndMoveForward() then return end
      -- turn back to X-axis for the new row
      if z%2==1 then turnRight() else turnLeft() end
      state.x = xEnd
      saveState()
    end
  end

  -- reset for next layer
  state.x, state.z = 1, 1
  saveState()
end

-- DONE
deleteState()
print("✅ Box excavation complete!")
