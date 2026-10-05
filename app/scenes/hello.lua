-- 1. Hello World — the smallest lpp-vita program, plus Color and Screen.
local S = {
  title = "Hello World", modules = { "Screen", "Color", "Graphics" },
  desc = "The classic: Screen.clear, Graphics.debugPrint (the console's built-in PGF font, with a scale "
      .. "argument) and Screen.flip. Also decomposes colours with Color.getR/G/B/A, reads the last "
      .. "displayed frame back with Screen.getPixel and toggles Screen.waitVblankStart.",
  hints = { { "square", "Toggle vblank wait" } },
}

local t, vsync = 0, true

function S.update()
  t = t + 1
  if Input.pressed("square") then
    vsync = not vsync
    Log.info("waitVblankStart " .. (vsync and "on" or "off"))
  end
  if vsync then Screen.waitVblankStart() end
end

function S.draw()
  local white = Color.new(255, 255, 255)
  -- the whole "hello world" of lpp-vita is these three calls:
  Graphics.debugPrint(40, 64, "Hello World!", white, 3.0)
  Graphics.debugPrint(44, 140, "Graphics.debugPrint(x, y, text, color, scale)", C.dim)

  local code = {
    "while true do",
    "  Graphics.initBlend()",
    "  Screen.clear()",
    '  Graphics.debugPrint(5, 5, "Hello World!", Color.new(255,255,255))',
    "  Graphics.termBlend()",
    "  Screen.flip()",
    "end",
  }
  UI.panel(40, 180, 520, 200, "index.lua")
  for i, l in ipairs(code) do UI.mono(56, 210 + (i - 1) * 22, l, C.accent2, 16) end

  -- Color: animated RGBA, packed as r | g<<8 | b<<16 | a<<24
  local r = math.floor(127 + 127 * math.sin(t / 40))
  local g = math.floor(127 + 127 * math.sin(t / 53 + 2))
  local b = math.floor(127 + 127 * math.sin(t / 67 + 4))
  local a = math.floor(160 + 95 * math.sin(t / 90))
  local c = Color.new(r, g, b, a)
  UI.panel(600, 64, 330, 316, "Color")
  UI.rect(620, 104, 120, 120, C.white)
  UI.rect(620, 104, 60, 60, C.black)
  UI.rect(680, 164, 60, 60, C.black)
  UI.rect(620, 104, 120, 120, c)
  UI.kv(760, 104, {
    { "getR", Color.getR(c) }, { "getG", Color.getG(c) },
    { "getB", Color.getB(c) }, { "getA", Color.getA(c) },
  }, 60, 17, 26)
  UI.mono(620, 240, "packed " .. UI.hex(c), C.text, 15)

  -- Screen.getPixel reads the *front* buffer, i.e. what was displayed last frame
  local px = Screen.getPixel(690, 150)
  UI.text(620, 272, "Screen.getPixel(690,150) last frame:", C.dim, 14)
  UI.mono(620, 294, UI.hex(px), C.text, 15)
  UI.rect(800, 290, 24, 24, px)
  UI.frame(800, 290, 24, 24, C.line)
  UI.text(620, 330, "vblank wait: " .. (vsync and "ON" or "OFF") .. "   fps: " .. APP.fps,
    vsync and C.ok or C.warn, 16)

  Log.draw(40, 396, 890, 92, "Log")
end

return S
