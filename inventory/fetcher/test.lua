local attached = peripheral.wrap("bottom")
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.wrap(name) == attached then
    print("Network name:", name)
    break
  end
end
