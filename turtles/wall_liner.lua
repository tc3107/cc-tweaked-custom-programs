-- =========================
-- Wall Builder with Auto-Refuel
-- =========================

-- CONFIGURATION
local steps = 10               -- Number of blocks to move
local placementDirection = "down"  -- left, right, up, down
local FUEL_THRESHOLD = 10      -- Refuel if below this level

-- ========== UTILITY FUNCTIONS ==========

-- Check and refuel if fuel is low
local function autoRefuel()
    if turtle.getFuelLevel() == "unlimited" then return end
    if turtle.getFuelLevel() > FUEL_THRESHOLD then return end

    print("Fuel low (" .. turtle.getFuelLevel() .. ") — refueling...")

    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.refuel(0) then
            turtle.refuel()
            print("Refueled from slot " .. slot)
            return
        end
    end

    print("⚠️ WARNING: No valid fuel found!")
end

-- Select a block to place
local function selectBlock()
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.getItemCount(slot) > 0 and not turtle.refuel(0) then
            return true
        end
    end
    print("Out of blocks!")
    return false
end

-- Place a block relative to the turtle
local function placeRelative(dir)
    if not selectBlock() then return false end

    if dir == "left" then
        turtle.turnLeft()
        turtle.place()
        turtle.turnRight()
    elseif dir == "right" then
        turtle.turnRight()
        turtle.place()
        turtle.turnLeft()
    elseif dir == "up" then
        turtle.placeUp()
    elseif dir == "down" then
        turtle.placeDown()
    else
        print("Invalid direction: " .. tostring(dir))
        return false
    end

    return true
end

-- Step forward and dig if needed
local function stepForward()
    while not turtle.forward() do
        if turtle.detect() then
            turtle.dig()
        else
            sleep(0.5)
        end
    end
end

-- ========== MAIN LOOP ==========

for i = 1, steps do
    print("Step " .. i .. "/" .. steps)
    autoRefuel()

    if not placeRelative(placementDirection) then
        print("Failed to place at step " .. i)
        break
    end

    if i < steps then
        stepForward()
    end
end

print("✅ Wall building complete.")
