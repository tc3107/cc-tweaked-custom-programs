local peripherals = peripheral.getNames()

print("Attached peripherals:")
for i, name in ipairs(peripherals) do
    print(i .. ": " .. name)
end
