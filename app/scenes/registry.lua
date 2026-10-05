-- 21. Registry (unsafe eboot only).
local S = ActionScene({
  title = "Registry", modules = { "Registry" },
  desc = "Read and write the system registry, where the OS keeps its settings. getKey/setKey take a "
      .. "category path, a key name and a type (TYPE_STRING, TYPE_NUMBER, TYPE_BINARY); getSysKey "
      .. "reads system parameters by numeric id. All three need the UNSAFE eboot. The only write here "
      .. "is a reversible round-trip of the current value.",
  hints = { { "enter", "Run" } },
})

-- NOTE: Keyboard also registers TYPE_NUMBER (IME number pad). Both happen to equal 2,
-- so the shared global works for either module.

local KEYS = {
  { "/CONFIG/SYSTEM/", "username", TYPE_STRING },
  { "/CONFIG/SYSTEM/", "language", TYPE_NUMBER },
  { "/CONFIG/SYSTEM/", "button_assign", TYPE_NUMBER },
  { "/CONFIG/SYSTEM/", "flight_mode", TYPE_NUMBER },
  { "/CONFIG/DISPLAY/", "brightness", TYPE_NUMBER },
  { "/CONFIG/SOUND/", "main_volume", TYPE_NUMBER },
  { "/CONFIG/DATE/", "time_format", TYPE_NUMBER },
  { "/CONFIG/NP/", "account_id", TYPE_BINARY },
}

local function show(v) return show_value(v) end

S.actions = {}
for _, k in ipairs(KEYS) do
  S.actions[#S.actions + 1] = { label = "getKey " .. k[1] .. k[2], action = function()
    local ok, v = Try("getKey(" .. k[2] .. ")", Registry.getKey, k[1], k[2], k[3])
    if ok then Log.info("  = " .. show(v, k[3])) end
  end }
end
S.actions[#S.actions + 1] = { label = "getSysKey ids 1..8 (number)", action = function()
  for id = 1, 8 do
    local ok, v = TryQ("getSysKey", Registry.getSysKey, id, TYPE_NUMBER)
    if ok then Log.info(string.format("  sysparam %d = %s", id, tostring(v))) else break end
  end
end }
S.actions[#S.actions + 1] = { label = "setKey round-trip: brightness", action = function()
  local ok, v = Try("getKey brightness", Registry.getKey, "/CONFIG/DISPLAY/", "brightness", TYPE_NUMBER)
  if not ok then return end
  -- write the same value back: proves setKey works without changing anything
  Try("setKey brightness = " .. v, Registry.setKey, "/CONFIG/DISPLAY/", "brightness", TYPE_NUMBER, v)
  local _, v2 = Try("getKey brightness", Registry.getKey, "/CONFIG/DISPLAY/", "brightness", TYPE_NUMBER)
  Log.ok("  unchanged: " .. tostring(v == v2))
end }

function S.enter()
  if System.isSafeMode() then
    Log.err("Running the SAFE eboot: every Registry call raises")
    Log.err("'this function requires unsafe mode'. Rebuild with --unsafe.")
  end
end

function S.update() S.list:update() end
function S.draw() S.draw_actions("Log") end

return S
