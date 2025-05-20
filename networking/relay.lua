-- Detect modems
local sides = { "left", "right", "top", "bottom", "front", "back" }
local modems = {}

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

print("Relay active between sides '" .. modemA .. "' and '" .. modemB .. "'")

-- Relay logic
local function relay(fromSide, toSide)
    while true do
        local senderId, message, protocol = rednet.receive(nil, nil, fromSide)

        if type(message) == "table" then
            local isTagged = false

            -- Check if message already has "source:relay" tag
            for i = 2, #message do
                if message[i] == "source:relay" then
                    isTagged = true
                    break
                end
            end

            if not isTagged then
                local newMessage = { table.unpack(message) }
                table.insert(newMessage, "source:relay")

                rednet.send(senderId, newMessage, protocol, toSide)
                print("Forwarded from " .. fromSide .. " → " .. toSide .. " (protocol: " .. tostring(protocol) .. ")")
            else
                print("Rejected looped message from " .. fromSide)
            end
        else
            print("Ignored non-list message from " .. fromSide)
        end
    end
end

-- Run two threads for bidirectional communication
parallel.waitForAny(
    function() relay(modemA, modemB) end,
    function() relay(modemB, modemA) end
)
