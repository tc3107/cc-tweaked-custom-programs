local peripherals = peripheral.getNames()

for _, name in ipairs(peripherals) do
    local types = peripheral.getType(name)
    -- Ensure types is a table in case of multiple types
    if type(types) == "string" then
        types = {types}
    end
    for _, t in ipairs(types) do
        if t == "inventory" then
            print("Inventory found: " .. name)
            break
        end
    end
end
