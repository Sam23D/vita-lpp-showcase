-- 20. System info: console, battery, clocks, power timers, screenshots, launching.
local S = {
  title = "System Info", modules = { "System" },
  desc = "Console and account info (username, language, model, PSID, title/ID, firmware), date and time, "
      .. "the full battery report, CPU/BUS/GPU/crossbar clock control, power-saving timers (disable "
      .. "auto-suspend and screen dimming while a video plays), takeScreenshot in BMP/PNG/JPG, and "
      .. "launching URIs (executeUri, launchApp). Clocks are restored when you leave.",
  hints = { { "up", "" }, { "down", "Clock preset" }, { "square", "Screenshot" }, { "cross", "No-sleep" }, { "circle", "Open browser" } },
}

local LANGS = { [0] = "Japanese", "English (US)", "French", "Spanish", "German", "Italian", "Dutch",
  "Portuguese (PT)", "Russian", "Korean", "Chinese (trad.)", "Chinese (simp.)", "Finnish", "Swedish",
  "Danish", "Norwegian", "Polish", "Portuguese (BR)", "English (UK)", "Turkish" }
local DAYS = { [0] = "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local PRESETS = {
  { "Power save", 111, 111, 111, 111 },
  { "Default", 333, 111, 111, 111 },
  { "Balanced", 444, 166, 166, 111 },
  { "Max", 444, 222, 222, 166 },
}
local preset, info, saved, nosleep = 2, {}, nil, false
local shot_fmt = 1
local FORMATS = { { "BMP", FORMAT_BMP, "bmp" }, { "PNG", FORMAT_PNG, "png" }, { "JPG", FORMAT_JPG, "jpg" } }

local function safe(f, ...) local ok, v = pcall(f, ...) if ok then return v end return "(" .. tostring(v):gsub("^.-: ", "") .. ")" end

function S.enter()
  saved = { System.getCpuSpeed(), System.getBusSpeed(), System.getGpuSpeed(), System.getGpuXbarSpeed() }
  info.user = System.getUsername()
  info.lang = System.getLanguage()
  info.model = System.getModel()
  info.psid = System.getPsId()
  info.title = System.getTitle()
  info.tid = System.getTitleID()
  info.fw_spoof = System.getSpoofedFirmware()
  info.fw = safe(System.getFirmware)          -- unsafe only
  info.fw_factory = safe(System.getFactoryFirmware) -- unsafe only
  info.boot = safe(System.getBootParams)      -- unsafe only
  info.safe = System.isSafeMode()
end

function S.leave()
  if saved then
    System.setCpuSpeed(saved[1]); System.setBusSpeed(saved[2]); System.setGpuSpeed(saved[3]); System.setGpuXbarSpeed(saved[4])
  end
  if nosleep then
    System.enableTimer(AUTO_SUSPEND_TIMER); System.enableTimer(SCREEN_OFF_TIMER); System.enableTimer(SCREEN_DIMMING_TIMER)
    nosleep = false
  end
end

local function apply_preset()
  local p = PRESETS[preset]
  Try("setCpuSpeed(" .. p[2] .. ")", System.setCpuSpeed, p[2])
  Try("setBusSpeed(" .. p[3] .. ")", System.setBusSpeed, p[3])
  Try("setGpuSpeed(" .. p[4] .. ")", System.setGpuSpeed, p[4])
  Try("setGpuXbarSpeed(" .. p[5] .. ")", System.setGpuXbarSpeed, p[5])
end

function S.update()
  if Input.pressed("up") then preset = math.min(#PRESETS, preset + 1); apply_preset() end
  if Input.pressed("down") then preset = math.max(1, preset - 1); apply_preset() end
  if Input.pressed("cross") then
    nosleep = not nosleep
    local f = nosleep and System.disableTimer or System.enableTimer
    local name = nosleep and "disableTimer" or "enableTimer"
    Try(name .. "(AUTO_SUSPEND_TIMER)", f, AUTO_SUSPEND_TIMER)
    Try(name .. "(SCREEN_OFF_TIMER)", f, SCREEN_OFF_TIMER)
    Try(name .. "(SCREEN_DIMMING_TIMER)", f, SCREEN_DIMMING_TIMER)
  end
  -- while "no-sleep" is on, also poke the idle timer the way video players do
  if nosleep and APP.frame % 600 == 0 then System.resetTimer(AUTO_SUSPEND_TIMER) end
  if Input.pressed("square") then
    local f = FORMATS[shot_fmt]
    local path = data_path("screenshot." .. f[3])
    if Try("takeScreenshot(" .. f[1] .. ")", System.takeScreenshot, path, f[2], 200) then
      Log.info("  " .. path .. "  " .. human_bytes(System.statFile(path).size))
    end
    shot_fmt = shot_fmt % #FORMATS + 1
  end
  if Input.pressed("circle") then
    Dialog.confirm("Open https://vitadb.rinnegatamante.it in the Vita web browser?\n(this app stays open in the background)", function()
      Try("executeUri(webbrowser:...)", System.executeUri, "webbrowser:https://vitadb.rinnegatamante.it")
    end)
  end
end

function S.draw()
  local h, m, s = System.getTime()
  local dow, d, mo, y = System.getDate()
  UI.panel(16, 56, 460, 250, "Console")
  UI.kv(28, 88, {
    { "User", info.user },
    { "Language", (LANGS[info.lang] or "?") .. " (" .. info.lang .. ")" },
    { "Model", info.model == 0x20000 and "PS TV" or (info.model == 0x10000 and "PS Vita" or UI.hex(info.model)) },
    { "PSID", info.psid:sub(1, 23) .. "..." },
    { "This app", info.title .. "  [" .. info.tid .. "]" },
    { "Firmware", info.fw_spoof .. "  real " .. tostring(info.fw) },
    { "Factory FW", tostring(info.fw_factory) },
    { "Interpreter", info.safe and "safe eboot" or "unsafe eboot", info.safe and C.ok or C.warn },
    { "Date / time", string.format("%s %04d-%02d-%02d %02d:%02d:%02d", DAYS[dow] or dow, y, mo, d, h, m, s) },
  }, 120, 15, 23)

  UI.panel(492, 56, 452, 250, "Battery")
  local pct = System.getBatteryPercentage()
  UI.bar(504, 90, 300, 26, pct / 100, pct < 20 and C.err or C.ok)
  UI.bold(816, 92, pct .. " %", C.white, 20)
  UI.kv(504, 128, {
    { "Charging", tostring(System.isBatteryCharging()) },
    { "Time left", System.getBatteryLife() .. " min" },
    { "Capacity", System.getBatteryCapacity() .. " / " .. System.getBatteryFullCapacity() .. " mAh" },
    { "Health (SOH)", System.getBatteryHealth() .. " %" },
    { "Cycles", System.getBatteryCycles() },
    { "Temperature", System.getBatteryTemp() .. " C" },
    { "Voltage", System.getBatteryVolt() .. " mV" },
  }, 130, 15, 23)

  UI.panel(16, 316, 460, 176, "Clocks (MHz)   UP/DOWN: " .. PRESETS[preset][1])
  local clocks = { { "CPU", System.getCpuSpeed(), 444 }, { "BUS", System.getBusSpeed(), 222 },
                   { "GPU", System.getGpuSpeed(), 222 }, { "GPU Xbar", System.getGpuXbarSpeed(), 166 } }
  for i, c in ipairs(clocks) do
    local yy = 348 + (i - 1) * 28
    UI.text(28, yy, c[1], C.dim, 15)
    UI.bar(110, yy + 2, 270, 16, c[2] / c[3], C.accent)
    UI.text(392, yy, tostring(c[2]), C.text, 15)
  end
  UI.text(28, 462, "power timers: " .. (nosleep and "DISABLED (no sleep)" or "normal"), nosleep and C.warn or C.dim, 14)
  Log.draw(492, 316, 452, 176)
end

return S
