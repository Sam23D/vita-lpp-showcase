-- Drawing helpers on top of Graphics / Font / Color.
-- NOTE lpp-vita argument order quirk: Graphics.drawLine(x1, x2, y1, y2, c) and
-- Graphics.fillRect(x1, x2, y1, y2, c) take both X values first. UI.line/UI.rect
-- hide that so scenes can think in (x, y, w, h).

UI = { W = 960, H = 544, HEADER = 44, FOOTER = 40 }

C = {
  bg      = Color.new(16, 20, 32),
  panel   = Color.new(28, 34, 52),
  panel2  = Color.new(38, 46, 70),
  line    = Color.new(64, 76, 110),
  text    = Color.new(230, 234, 245),
  dim     = Color.new(140, 150, 175),
  accent  = Color.new(95, 139, 255),
  accent2 = Color.new(249, 199, 79),
  ok      = Color.new(82, 214, 140),
  warn    = Color.new(255, 179, 71),
  err     = Color.new(255, 95, 109),
  white   = Color.new(255, 255, 255),
  black   = Color.new(0, 0, 0),
  shade   = Color.new(0, 0, 0, 150),
  cross   = Color.new(124, 156, 255),
  circle  = Color.new(255, 102, 102),
  square  = Color.new(255, 128, 214),
  triangle= Color.new(64, 220, 170),
}

-- UI.font.reg/bold/mono are font *families* (file paths). vita2d keeps one glyph atlas
-- per Font handle and never evicts, so rendering one handle at many pixel sizes fills
-- it up (slow on hardware, crashes Vita3K). We keep one handle per (family, size),
-- loaded on first use and sized once.
function UI.init()
  UI.font = {
    reg  = APP.root .. "assets/fonts/LiberationSans-Regular.ttf",
    bold = APP.root .. "assets/fonts/LiberationSans-Bold.ttf",
    mono = APP.root .. "assets/fonts/LiberationMono-Regular.ttf",
  }
  UI.handles = {}
end

local function use(family, size)
  local key = family .. "@" .. size
  local h = UI.handles[key]
  if not h then
    h = Font.load(family)
    Font.setPixelSizes(h, size)
    UI.handles[key] = h
  end
  return h
end

-- text(x, y, string, color, size, font) ; y is the top of the line
function UI.text(x, y, s, color, size, font)
  Font.print(use(font or UI.font.reg, size or 18), x, y, tostring(s), color or C.text)
end

function UI.bold(x, y, s, color, size) UI.text(x, y, s, color, size or 20, UI.font.bold) end
function UI.mono(x, y, s, color, size) UI.text(x, y, s, color, size or 16, UI.font.mono) end

function UI.tw(s, size, font)
  return Font.getTextWidth(use(font or UI.font.reg, size or 18), tostring(s))
end

function UI.th(s, size, font)
  return Font.getTextHeight(use(font or UI.font.reg, size or 18), tostring(s))
end

function UI.center(cx, y, s, color, size, font)
  UI.text(cx - UI.tw(s, size, font) / 2, y, s, color, size, font)
end

function UI.rect(x, y, w, h, c) Graphics.fillRect(x, x + w, y, y + h, c) end
function UI.frame(x, y, w, h, c) Graphics.fillEmptyRect(x, x + w, y, y + h, c) end
function UI.line(x1, y1, x2, y2, c) Graphics.drawLine(x1, x2, y1, y2, c) end

function UI.panel(x, y, w, h, title)
  UI.rect(x, y, w, h, C.panel)
  UI.frame(x, y, w, h, C.line)
  if title then
    UI.rect(x, y, w, 26, C.panel2)
    UI.text(x + 10, y + 4, title, C.accent2, 16, UI.font.bold)
  end
end

function UI.bar(x, y, w, h, frac, color)
  frac = math.max(0, math.min(1, frac or 0))
  UI.rect(x, y, w, h, C.panel2)
  if frac > 0 then UI.rect(x, y, w * frac, h, color or C.accent) end
  UI.frame(x, y, w, h, C.line)
end

-- PlayStation button glyphs drawn from primitives (fonts have no such glyphs)
function UI.glyph(kind, cx, cy, r)
  r = r or 11
  if kind == "cross" or kind == "circle" or kind == "square" or kind == "triangle" then
    Graphics.fillCircle(cx, cy, r, C.black)
    local k = r * 0.5
    if kind == "cross" then
      UI.line(cx - k, cy - k, cx + k, cy + k, C.cross)
      UI.line(cx - k, cy + k, cx + k, cy - k, C.cross)
      UI.line(cx - k + 1, cy - k, cx + k + 1, cy + k, C.cross)
      UI.line(cx - k + 1, cy + k, cx + k + 1, cy - k, C.cross)
    elseif kind == "circle" then
      Graphics.fillCircle(cx, cy, k + 2, C.circle)
      Graphics.fillCircle(cx, cy, k - 1, C.black)
    elseif kind == "square" then
      UI.frame(cx - k, cy - k, 2 * k, 2 * k, C.square)
      UI.frame(cx - k + 1, cy - k + 1, 2 * k - 2, 2 * k - 2, C.square)
    else
      local top, bl, br = cy - k - 1, cx - k - 1, cx + k + 1
      UI.line(cx, top, bl, cy + k, C.triangle)
      UI.line(cx, top, br, cy + k, C.triangle)
      UI.line(bl, cy + k, br, cy + k, C.triangle)
    end
  else
    local label = ({ l = "L", r = "R", start = "START", select = "SELECT", up = "UP",
      down = "DOWN", left = "LEFT", right = "RIGHT", dpad = "D-PAD", lstick = "L-STICK",
      rstick = "R-STICK", touch = "TOUCH", rear = "REAR" })[kind] or kind
    local w = UI.tw(label, 13, UI.font.bold) + 12
    UI.rect(cx - w / 2, cy - 10, w, 20, C.panel2)
    UI.frame(cx - w / 2, cy - 10, w, 20, C.dim)
    UI.text(cx - w / 2 + 6, cy - 8, label, C.text, 13, UI.font.bold)
    return w
  end
  return 2 * r
end

-- hints = { {"cross", "Select"}, {"triangle", "Back"} } (use "enter" for the system confirm button)
function UI.hints(hints, y)
  y = y or UI.H - UI.FOOTER / 2
  local x = 16
  for _, h in ipairs(hints) do
    local kind = h[1] == "enter" and Input.ENTER_GLYPH or h[1]
    local w
    if kind == "cross" or kind == "circle" or kind == "square" or kind == "triangle" then
      UI.glyph(kind, x + 11, y, 11)
      w = 22
    else
      w = UI.tw(({ l = "L", r = "R" })[kind] or kind:upper(), 13, UI.font.bold) + 12
      UI.glyph(kind, x + w / 2, y)
    end
    UI.text(x + w + 6, y - 9, h[2], C.text, 16)
    x = x + w + 18 + UI.tw(h[2], 16)
  end
end

function UI.header(title, subtitle)
  UI.rect(0, 0, UI.W, UI.HEADER, C.panel)
  UI.line(0, UI.HEADER, UI.W, UI.HEADER, C.line)
  UI.bold(16, 10, title, C.white, 22)
  if subtitle then UI.text(28 + UI.tw(title, 22, UI.font.bold), 14, subtitle, C.dim, 15) end
  -- status: clock + battery, refreshed twice per second (cheap, but no need per frame)
  local s = UI.status
  if not s or APP.frame - s.at > 30 then
    local h, m = System.getTime()
    s = { at = APP.frame, clock = string.format("%02d:%02d", h, m),
          bat = System.getBatteryPercentage(), chg = System.isBatteryCharging() }
    UI.status = s
  end
  local bx = UI.W - 70
  UI.frame(bx, 14, 40, 18, C.dim)
  UI.rect(bx + 40, 19, 3, 8, C.dim)
  UI.rect(bx + 2, 16, 36 * s.bat / 100, 14, s.chg and C.ok or (s.bat < 20 and C.err or C.text))
  UI.text(bx - 52, 13, s.clock, C.text, 17)
end

function UI.footer(hints)
  UI.rect(0, UI.H - UI.FOOTER, UI.W, UI.FOOTER, C.panel)
  UI.line(0, UI.H - UI.FOOTER, UI.W, UI.H - UI.FOOTER, C.line)
  UI.hints(hints)
end

-- key/value table; rows = { {"Battery", "87 %"}, ... }
function UI.kv(x, y, rows, kw, size, gap)
  size, gap = size or 16, gap or 22
  for i, r in ipairs(rows) do
    UI.text(x, y + (i - 1) * gap, r[1], C.dim, size)
    UI.text(x + (kw or 180), y + (i - 1) * gap, tostring(r[2]), r[3] or C.text, size)
  end
end

-- word-wrap by measured width
function UI.wrap(s, width, size, font)
  local lines, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    local try = line == "" and word or (line .. " " .. word)
    if UI.tw(try, size, font) > width and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = try
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end

function UI.paragraph(x, y, s, width, color, size, gap)
  size = size or 16
  local lines = UI.wrap(s, width, size)
  for i, l in ipairs(lines) do UI.text(x, y + (i - 1) * (gap or size + 5), l, color or C.dim, size) end
  return #lines * (gap or size + 5)
end

function UI.hex(n)
  if n == nil then return "nil" end
  if n < 0 then n = n + 4294967296 end
  return string.format("0x%08X", n)
end
