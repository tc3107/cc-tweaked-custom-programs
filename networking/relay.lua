local protocol = "sort"
local sides = { "left", "right", "top", "bottom", "front", "back" }
local modems = {}

-- Identify exactly two modem sides
for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        rednet.open(side)
        table.insert(modems, side)
    end
end

if #modems ~= 2 then
    print("Error: This relay requires exactly two modems.")
    print("Found " .. #modems .. ". Please attach one wired and one wireless modem.")
    return
end

local modemA = modems[1]
local modemB = modems[2]

print("Relay running between '" .. modemA .. "' and '" .. modemB .. "' on protocol '" .. protocol .. "'.")

-- Function to forward messages from one modem to the other
local function relay(fromSide, toSide)
    while true do
        local senderId, message, proto = rednet.receive(protocol)
        -- Forward only if the message was received on the expected modem
        if rednet.isOpen(fromSide) then
            rednet.broadcast(message, proto)
        end
    end
end

-- Run two threads: A → B and B → A
parallel.waitForAny(
    function() relay(modemA, modemB) end,
    function() relay(modemB, modemA) end
)
