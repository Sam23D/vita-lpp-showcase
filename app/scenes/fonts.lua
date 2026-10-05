-- 4. Fonts: TTF loading, sizing, measuring, and the built-in debug font.
local S = {
  title = "Fonts", modules = { "Font", "Graphics" },
  desc = "Font.load (TTF/OTF, or the console's PGF/PVF fonts), setPixelSizes, getTextWidth and "
      .. "getTextHeight for layout, Font.print, and Font.unload. Compares with Graphics.debugPrint, "
      .. "the always-available system font.",
  hints = { { "up", "" }, { "down", "Size" }, { "square", "Reload font" } },
}

-- vita2d keeps one glyph atlas per font handle and never evicts. Rendering one handle
-- at many pixel sizes fills that atlas (slow on hardware, crashes Vita3K), so this
-- scene uses one handle per size: the headline handle is reloaded when its size
-- changes, the ramp and the wave text each get a fixed-size handle.
local PATH = asset_path("fonts/LiberationSans-Bold.ttf")
local RAMP = { 12, 16, 20, 26, 34 }
local f, f_size, ramp, wave = nil, nil, {}, nil
local size, t = 32, 0

local function sized(px)
  local ok, h = pcall(Font.load, PATH)
  if not ok then return nil end
  Font.setPixelSizes(h, px)
  return h
end

local function free_all()
  Defer.free(Font.unload, f); f, f_size = nil, nil
  Defer.free(Font.unload, wave); wave = nil
  for _, h in pairs(ramp) do Defer.free(Font.unload, h) end
  ramp = {}
end

local function load()
  free_all()
  local ok, h = Try("Font.load(LiberationSans-Bold.ttf)", Font.load, PATH)
  f = ok and h or nil
  for _, s in ipairs(RAMP) do ramp[s] = sized(s) end
  wave = sized(28)
end

function S.enter() load() end
function S.leave() free_all() end

function S.update()
  t = t + 1
  if Input.rep("up") then size = math.min(96, size + 2) end
  if Input.rep("down") then size = math.max(8, size - 2) end
  if Input.pressed("square") then load() end
  -- new size -> fresh handle (its atlas only ever holds glyphs of one size)
  if f and f_size and f_size ~= size then
    Defer.free(Font.unload, f)
    f, f_size = sized(size), size
  end
end

function S.draw()
  if not f then return end
  if f_size ~= size then Font.setPixelSizes(f, size); f_size = size end
  local msg = "Hello, Vita!"
  local w, h = Font.getTextWidth(f, msg), Font.getTextHeight(f, msg)
  local x, y = 480 - w / 2, 150 - h / 2
  Graphics.fillEmptyRect(x, x + w, y, y + h, C.line)  -- measured box
  Font.print(f, x, y, msg, Color.new(255, 255, 255))
  UI.mono(30, 64, string.format("setPixelSizes(f, %d)   getTextWidth = %d   getTextHeight = %d", size, w, h), C.accent2, 15)

  -- a type ramp: one pre-sized handle per size
  local yy = 250
  for _, s in ipairs(RAMP) do
    if ramp[s] then Font.print(ramp[s], 30, yy, s .. "px  The quick brown fox", C.text) end
    yy = yy + s + 10
  end
  -- wave text, per-glyph positioning with getTextWidth
  if wave then
    local word, xx = "Lua Player Plus", 560
    for i = 1, #word do
      local ch = word:sub(i, i)
      local hue = (t * 3 + i * 25) % 360
      Font.print(wave, xx, 300 + 12 * math.sin(t / 10 + i / 2), ch,
        Color.new(math.floor(127 + 127 * math.cos(math.rad(hue))), 200, math.floor(127 + 127 * math.sin(math.rad(hue)))))
      xx = xx + Font.getTextWidth(wave, ch)
    end
  end

  Graphics.debugPrint(560, 380, "Graphics.debugPrint: system font", C.text)
  Graphics.debugPrint(560, 410, "scale 1.6", C.accent2, 1.6)
  Log.draw(30, 436, 900, 60)
end

return S
