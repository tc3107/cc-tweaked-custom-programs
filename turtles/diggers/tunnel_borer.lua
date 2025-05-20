-- Configuration
local TUNNEL_LENGTH = 100
local TORCH_INTERVAL = 0  -- Set to nil to disable torch placement
local FUEL_THRESHOLD = 10

-- Utility: Auto-refuel if fuel is low
local function autoRefuel()
    if turtle.getFuelLevel() > FUEL_THRESHOLD then return end

    print("Fuel low! Refueling...")
    for slot = 1, 16 do
        turtle.select(slot)
        if turtle.refuel(0) then
            turtle.refuel()
            print("Refueled from slot " .. slot)
            return
        end
    end
    print("No fuel found!")
end

-- Utility: Place a torch behind the turtle (optional)
local function placeTorch()
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        if item and item.name:lower():find("torch") then
            turtle.select(slot)
            turtle.turnLeft()
            turtle.turnLeft()
            turtle.place()
            turtle.turnRight()
            turtle.turnRight()
            return
        end
    end
end

-- Main tunneling logic
for i = 1, TUNNEL_LENGTH do
    autoRefuel()

    -- Clear block in front
    while turtle.detect() do
        turtle.dig()
        sleep(0.4)  -- Give time for falling blocks like gravel
    end

    -- Move forward
    if not turtle.forward() then
        print("Movement blocked at position " .. i)
        break
    end

    -- Dig ceiling and floor (optional, creates a 2x1 tunnel)
    turtle.digUp()
    turtle.digDown()

    -- Place torch every TORCH_INTERVAL blocks (optional)
    if TORCH_INTERVAL and i % TORCH_INTERVAL == 0 then
        placeTorch()
    end
end

print("Tunnel complete!")
