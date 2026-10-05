-- 6. Controls: buttons, sticks, both touch panels, motion sensors, lightbar/rumble, home lock.
local S = {
  title = "Controls", modules = { "Controls" },
  desc = "Everything the input hardware reports: Controls.read and check for every button, both "
      .. "analog sticks, the front touchscreen (up to 6 fingers) and the rear touchpad (up to 4), "
      .. "gyroscope and accelerometer, getEnterButton, getDeviceInfo for the 5 controller ports, "
      .. "PS TV rumble and lightbar (DualShock 3/4), lockHomeButton and headsetStatus (unsafe only).",
  hints = { { "start", "Lock PS btn" }, { "select", "Rumble+light" } },
  back_button = "triangle",
}

local sensors, locked, t = false, false, 0
local trail_f, trail_r = {}, {}
local gyro = { 0, 0, 0 }
local accel = { 0, 0, 0 }
local devinfo, headset = {}, nil
local DEV = { [0] = "unpaired", [1] = "Vita", [2] = "virtual", [4] = "DS3", [8] = "DS4" }

function S.enter()
  sensors = Try("enableGyro", Controls.enableGyro) and Try("enableAccel", Controls.enableAccel)
  local ok, info = Try("getDeviceInfo", Controls.getDeviceInfo)
  devinfo = ok and info or {}
  local hok, h = Try("headsetStatus", Controls.headsetStatus)
  headset = hok and h or nil
  Log.info("getEnterButton = " .. (Input.ENTER == SCE_CTRL_CIRCLE and "CIRCLE (JP layout)" or "CROSS"))
end

function S.leave()
  if sensors then Controls.disableGyro(); Controls.disableAccel() end
  if locked then Controls.unlockHomeButton(); locked = false end
end

function S.update()
  t = t + 1
  if sensors then
    gyro = { Controls.readGyro() }
    accel = { Controls.readAccel() }
  end
  for _, p in ipairs(Input.touch) do trail_f[#trail_f + 1] = { p.x, p.y, t } end
  for _, p in ipairs(Input.rear) do trail_r[#trail_r + 1] = { p.x, p.y, t } end
  while trail_f[1] and t - trail_f[1][3] > 40 do table.remove(trail_f, 1) end
  while trail_r[1] and t - trail_r[1][3] > 40 do table.remove(trail_r, 1) end

  if Input.pressed("start") then
    if locked then Try("unlockHomeButton", Controls.unlockHomeButton) else Try("lockHomeButton", Controls.lockHomeButton) end
    locked = not locked
  end
  if Input.pressed("select") then
    -- port 0 means "the first DualShock" (lpp maps it to port 1); harmless on a handheld Vita
    Try("rumble(0, 200, 200)", Controls.rumble, 0, 200, 200)
    Try("setLightbar(0, accent)", Controls.setLightbar, 0, Color.new(math.random(255), math.random(255), math.random(255)))
  end
  if Input.held_frames.select == 30 then Controls.rumble(0, 0, 0) end
end

local BUTTONS = {
  { "up", SCE_CTRL_UP }, { "down", SCE_CTRL_DOWN }, { "left", SCE_CTRL_LEFT }, { "right", SCE_CTRL_RIGHT },
  { "cross", SCE_CTRL_CROSS }, { "circle", SCE_CTRL_CIRCLE }, { "square", SCE_CTRL_SQUARE }, { "triangle", SCE_CTRL_TRIANGLE },
  { "l", SCE_CTRL_LTRIGGER }, { "r", SCE_CTRL_RTRIGGER }, { "start", SCE_CTRL_START }, { "select", SCE_CTRL_SELECT },
  { "ps", SCE_CTRL_PSBUTTON }, { "vol+", SCE_CTRL_VOLUP }, { "vol-", SCE_CTRL_VOLDOWN }, { "power", SCE_CTRL_POWER },
}

local function stick(cx, cy, x, y, label)
  Graphics.fillCircle(cx, cy, 44, C.panel2)
  Graphics.fillEmptyRect(cx - 44, cx + 44, cy - 44, cy + 44, C.line)
  local dx, dy = (x - 128) / 128 * 40, (y - 128) / 128 * 40
  UI.line(cx, cy, cx + dx, cy + dy, C.dim)
  Graphics.fillCircle(cx + dx, cy + dy, 12, C.accent)
  UI.center(cx, cy + 50, string.format("%s %3d,%3d", label, x, y), C.text, 14)
end

local function touch_view(x, y, w, h, pts, trail, color, label, sw, sh)
  UI.panel(x, y, w, h, label)
  local sx, sy = w / sw, (h - 26) / sh
  for _, p in ipairs(trail) do Graphics.fillCircle(x + p[1] * sx, y + 26 + p[2] * sy, 2, color) end
  for i, p in ipairs(pts) do
    Graphics.fillCircle(x + p.x * sx, y + 26 + p.y * sy, 9, color)
    UI.text(x + p.x * sx + 10, y + 18 + p.y * sy, tostring(i), C.white, 13)
  end
  UI.text(x + 8, y + h - 20, #pts .. " finger(s)", C.dim, 13)
end

function S.draw()
  local pad = Input.pad
  -- buttons grid via Controls.check
  UI.panel(16, 56, 300, 196, "Controls.read() = " .. UI.hex(pad))
  for i, b in ipairs(BUTTONS) do
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    local x, y = 26 + col * 72, 90 + row * 40
    local on = Controls.check(pad, b[2])
    UI.rect(x, y, 64, 30, on and C.accent or C.panel2)
    UI.center(x + 32, y + 6, b[1], on and C.white or C.dim, 15)
  end
  stick(380, 140, Input.lx, Input.ly, "L")
  stick(500, 140, Input.rx, Input.ry, "R")

  -- motion
  UI.panel(580, 56, 364, 196, "Motion sensors")
  if sensors then
    UI.kv(592, 90, {
      { "gyro  x/y/z", string.format("%+.2f %+.2f %+.2f", gyro[1] or 0, gyro[2] or 0, gyro[3] or 0) },
      { "accel x/y/z", string.format("%+.2f %+.2f %+.2f", accel[1] or 0, accel[2] or 0, accel[3] or 0) },
    }, 110, 15, 22)
    -- bubble level from the accelerometer
    local bx, by = 870, 180
    Graphics.fillCircle(bx, by, 50, C.panel2)
    Graphics.fillEmptyRect(bx - 50, bx + 50, by, by, C.line)
    Graphics.fillCircle(bx - (accel[1] or 0) * 45, by + (accel[2] or 0) * 45, 9, C.ok)
    UI.text(592, 150, "tilt the console:", C.dim, 14)
  else
    UI.text(592, 92, "sensors unavailable", C.err, 15)
  end

  touch_view(16, 262, 450, 230, Input.touch, trail_f, C.accent2, "Front touch (readTouch)", 960, 544)
  touch_view(482, 262, 300, 230, Input.rear, trail_r, C.ok, "Rear pad (readRetroTouch)", 960, 544)

  UI.panel(796, 262, 148, 230, "Ports")
  for i = 1, 5 do
    local ty = devinfo[i] and devinfo[i].type
    UI.text(806, 290 + (i - 1) * 22, i - 1 .. ": " .. (DEV[ty] or tostring(ty)), C.text, 14)
  end
  UI.text(806, 404, "headset:", C.dim, 14)
  UI.text(806, 422, headset == nil and "unsafe only" or (headset and "plugged" or "no"), headset == nil and C.warn or C.text, 14)
  UI.text(806, 446, "PS button:", C.dim, 14)
  UI.text(806, 464, locked and "LOCKED" or "normal", locked and C.warn or C.text, 14)
end

return S
