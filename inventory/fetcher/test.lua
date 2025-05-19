local side = "bottom"
local attachedPeripheral = peripheral.wrap(side)
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.wrap(name) == attachedPeripheral then
    print("Network name:", name)
    break
  end
end
