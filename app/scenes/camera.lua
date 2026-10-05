-- 10. Camera: live preview from either camera + every image-processing setting.
local S = {
  title = "Camera", modules = { "Camera", "Graphics", "System", "Sound" },
  desc = "Camera.init(INNER_CAM|OUTER_CAM, resolution, fps) and getOutput, which returns an image you "
      .. "draw like any other. Every setter and getter: brightness, saturation, sharpness, contrast, "
      .. "reverse, effect, exposure, zoom, anti-flicker, ISO, gain, white balance, backlight and night "
      .. "mode. SQUARE saves a photo (saveImage + the shutter sound). Not available on PS TV.",
  hints = { { "up", "" }, { "down", "Setting" }, { "left", "" }, { "right", "Change" }, { "cross", "Swap cam" }, { "square", "Photo" } },
}

local cam, on = OUTER_CAM, false
local sel = 1

-- each setting: name, setter, getter, current value, step/choices, min, max
local function choices(list) return { list = list } end
local SETTINGS = {
  { "Brightness", "setBrightness", "getBrightness", 128, 8, 0, 255 },
  { "Saturation", "setSaturation", "getSaturation", 1.0, 0.25, 0, 4 },
  { "Sharpness", "setSharpness", "getSharpness", 100, 100, 100, 400 },
  { "Contrast", "setContrast", "getContrast", 128, 8, 0, 255 },
  { "Exposure (EV)", "setExposure", "getExposure", 0, 0.5, -2, 2 },
  { "Zoom", "setZoom", "getZoom", 10, 2, 10, 40 },
  { "Gain", "setGain", "getGain", 0, 1, 0, 16 },
  { "Reverse", "setReverse", "getReverse", 1, choices({ { "off", REVERSE_OFF }, { "mirror", REVERSE_MIRROR }, { "flip", REVERSE_FLIP }, { "both", REVERSE_BOTH } }) },
  { "Effect", "setEffect", "getEffect", 1, choices({ { "none", EFFECT_NONE }, { "negative", EFFECT_NEGATIVE }, { "b&w", EFFECT_BLACKWHITE }, { "sepia", EFFECT_SEPIA }, { "blue", EFFECT_BLUE }, { "red", EFFECT_RED }, { "green", EFFECT_GREEN } }) },
  { "Anti-flicker", "setAntiFlicker", "getAntiFlicker", 1, choices({ { "auto", ANTIFLICKER_AUTO }, { "50 Hz", ANTIFLICKER_50HZ }, { "60 Hz", ANTIFLICKER_60HZ } }) },
  { "ISO", "setISO", "getISO", 1, choices({ { "auto", ISO_AUTO }, { "100", ISO_100 }, { "200", ISO_200 }, { "400", ISO_400 } }) },
  { "White balance", "setWhiteBalance", "getWhiteBalance", 1, choices({ { "auto", WB_AUTO }, { "daylight", WB_DAYLIGHT }, { "fluorescent", WB_CWF }, { "lamp", WB_SLSA } }) },
  { "Backlight", "setBacklight", "getBacklight", 1, choices({ { "off", BACKLIGHT_OFF }, { "on", BACKLIGHT_ON } }) },
  { "Night mode", "setNightmode", "getNightmode", 1, choices({ { "off", NIGHTMODE_OFF }, { "low", NIGHTMODE_LOW }, { "medium", NIGHTMODE_MED }, { "high", NIGHTMODE_HIGH } }) },
}

local function value_of(s)
  if type(s[5]) == "table" then return s[5].list[s[4]][2] end
  return s[4]
end

local function apply(s) TryQ("Camera." .. s[2], Camera[s[2]], value_of(s)) end

local function start()
  if on then Camera.term(); on = false end
  on = Try(cam == OUTER_CAM and "Camera.init(OUTER_CAM, VGA_RES, 30)" or "Camera.init(INNER_CAM, VGA_RES, 30)",
    Camera.init, cam, VGA_RES, 30)
  if on then for _, s in ipairs(SETTINGS) do apply(s) end end
end

function S.enter() Audio.ensure(); start() end
function S.leave() if on then Try("Camera.term", Camera.term); on = false end end

function S.update()
  if Input.rep("down") then sel = sel % #SETTINGS + 1 end
  if Input.rep("up") then sel = (sel - 2) % #SETTINGS + 1 end
  local d = (Input.rep("right") and 1 or 0) - (Input.rep("left") and 1 or 0)
  if d ~= 0 and on then
    local s = SETTINGS[sel]
    if type(s[5]) == "table" then
      s[4] = (s[4] - 1 + d) % #s[5].list + 1
    else
      s[4] = math.max(s[6], math.min(s[7], s[4] + d * s[5]))
    end
    apply(s)
  end
  if Input.pressed("cross") then cam = (cam == OUTER_CAM) and INNER_CAM or OUTER_CAM; start() end
  if Input.pressed("square") and on then
    local img = Camera.getOutput()
    local name = string.format("photo_%d.png", os.time and os.time() or APP.frame)
    if Try("saveImage(camera) -> " .. name, Graphics.saveImage, img, data_path(name), FORMAT_PNG) then
      Sound.playShutter(IMAGE_CAPTURE)
    end
  end
end

function S.draw()
  if on then
    local img = Camera.getOutput()
    Graphics.drawScaleImage(16, 56, img, 0.9, 0.9) -- 640x480 -> 576x432
  else
    UI.panel(16, 56, 576, 432)
    UI.center(304, 250, "camera unavailable", C.err, 20)
  end
  UI.panel(608, 56, 336, 360, (cam == OUTER_CAM and "Rear" or "Front") .. " camera  set / get")
  for i, s in ipairs(SETTINGS) do
    local y = 86 + (i - 1) * 23
    if i == sel then UI.rect(612, y - 2, 328, 22, C.accent) end
    UI.text(620, y, s[1], C.text, 15)
    local shown = type(s[5]) == "table" and s[5].list[s[4]][1] or tostring(s[4])
    UI.text(770, y, shown, C.accent2, 15)
    if on then
      local ok, got = pcall(Camera[s[3]])
      UI.text(870, y, ok and tostring(got) or "err", C.dim, 14)
    end
  end
  Log.draw(608, 424, 336, 72)
end

return S
