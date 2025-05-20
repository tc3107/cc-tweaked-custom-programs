local sides = { "left", "right", "top", "bottom", "front", "back" }
local modems = {}

-- Detect modems
for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        rednet.open(side)
        table.insert(modems, side)
    end
end

if #modems ~= 2 then
    print("Error: Exactly two modems required (one wired, one wireless). Found: " .. #modems)
    return
end

local modemA = modems[1]
local modemB = modems[2]
local relayId = os.getComputerID()

print("Relay ID " .. relayId .. " bridging '" .. modemA .. "' and '" .. modemB .. "'")

-- Helper to determine if message is from another relay
local function isFromRelay(message)
    return type(message) == "table" and message.fromRelay == true
end

-- Relay function: one direction
local function relay(fromSide, toSide)
    while true do
        local senderId, message, protocol = rednet.receive()

        -- Ignore messages from other relays
        if isFromRelay(message) then
            -- Optionally: print("Ignored relay message from ID " .. senderId)
        else
            -- Wrap message and tag it as from a relay
            local wrapped = {
                fromRelay = true,
                originalSender = senderId,
                data = message,
                protocol = protocol
            }

            rednet.broadcast(wrapped, protocol)
            print("Forwarded message from ID " .. senderId .. " on protocol '" .. protocol .. "'")
        end
    end
end

-- Start bidirectional safe relay
parallel.waitForAny(
    function() relay(modemA, modemB) end,
    function() relay(modemB, modemA) end
)
