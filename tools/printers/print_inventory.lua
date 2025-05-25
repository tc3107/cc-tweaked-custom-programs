local peripherals = peripheral.getNames()

for _, name in ipairs(peripherals) do
    local t = peripheral.getType(name)
    if t == "inventory" then
        print("Inventory found: " .. name)
    end
end
