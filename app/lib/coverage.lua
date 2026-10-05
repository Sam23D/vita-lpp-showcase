-- Wraps every function of every lpp-vita module so the app can show, live,
-- which parts of the API you have exercised (see the "Coverage" scene).

Coverage = { calls = {}, modules = {}, total = 0 }

Coverage.MODULES = {
  "Camera", "Color", "Controls", "Database", "Font", "Graphics", "Gui",
  "Keyboard", "Mic", "Network", "Registry", "Render", "Screen", "Socket",
  "Sound", "System", "Timer", "Video",
}

for _, mod in ipairs(Coverage.MODULES) do
  local t = _G[mod]
  local entry = { name = mod, fns = {} }
  if type(t) == "table" then
    for name, fn in pairs(t) do
      if type(fn) == "function" then
        local key = mod .. "." .. name
        local calls = Coverage.calls
        calls[key] = 0
        entry.fns[#entry.fns + 1] = name
        t[name] = function(...)
          calls[key] = calls[key] + 1
          return fn(...)
        end
        Coverage.total = Coverage.total + 1
      end
    end
  end
  table.sort(entry.fns)
  Coverage.modules[#Coverage.modules + 1] = entry
end

function Coverage.module_stats(entry)
  local hit = 0
  for _, name in ipairs(entry.fns) do
    if Coverage.calls[entry.name .. "." .. name] > 0 then hit = hit + 1 end
  end
  return hit, #entry.fns
end

function Coverage.summary()
  local hit = 0
  for _, n in pairs(Coverage.calls) do
    if n > 0 then hit = hit + 1 end
  end
  return hit, Coverage.total
end

function Coverage.missing()
  local out = {}
  for _, entry in ipairs(Coverage.modules) do
    for _, name in ipairs(entry.fns) do
      if Coverage.calls[entry.name .. "." .. name] == 0 then
        out[#out + 1] = entry.name .. "." .. name
      end
    end
  end
  return out
end
