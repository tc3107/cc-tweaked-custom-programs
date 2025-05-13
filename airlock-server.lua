print("Starting program...")

local relay = peripheral.wrap('redstone_relay_2')
rednet.open('left')
rednet.host('auth', 'airlock_control')

local function get_state()
    if not fs.exists("airlock_state.txt") then
        print("State file inexistent.")
        return false
    end
    local file = fs.open("airlock_state.txt", "r")
    local content = file.readAll()
    file.close()
    local state = (content == "true")
    return state
end

while true do
    local id, msg, proto = rednet.receive()
    if proto == 'auth' then
        print("Request received from", id, "for:", msg)

        if get_state() then
            rednet.send(id, true, 'auth')
            print("Access approved.")
        else
            rednet.send(id, false, 'auth')
            print("Access denied.")
        end
    end
    print()
end
