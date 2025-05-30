print("Starting program...")

local relay = peripheral.wrap('redstone_relay_1')
rednet.open('back')
rednet.host('auth', 'airlock_control')

local function get_state()
    if not fs.exists("airlock_state.txt") then
        print("State file inexistent.")
        return false
    end
    local file = fs.open("airlock_state.txt", "r")
    local content = file.readAll()
    file.close()
    if string.find(content, 'true') then
        return true
    else
        return false
    end
end

print("Airlock file state: ", get_state())

while true do
    local id, data, proto = rednet.receive()
    local msg = type(data) == 'table' and data[1]
    if proto == 'auth' and type(msg) == 'string' then
        print("Request received from", id, "for:", msg)

        if get_state() then
            rednet.send(id, {true}, 'auth')
            print("Access approved.")
        else
            rednet.send(id, {false}, 'auth')
            print("Access denied.")
        end
    else
        print("Malformed packet from", id)
    end
    print()
end
