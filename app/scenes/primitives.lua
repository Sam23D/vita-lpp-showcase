-- 2. 2D primitives.
local S = {
  title = "2D Primitives", modules = { "Graphics" },
  desc = "GPU-drawn primitives: drawPixel, drawLine, fillRect, fillEmptyRect and fillCircle. "
      .. "Watch out for the argument order: drawLine/fillRect/fillEmptyRect take "
      .. "(x1, x2, y1, y2, color) - both X first - not (x1, y1, x2, y2).",
  hints = { { "cross", "Burst" }, { "lstick", "Move" } },
}

local stars, sparks, t = {}, {}, 0
local cx, cy = 480, 300

function S.enter()
  stars = {}
  for i = 1, 220 do
    stars[i] = { x = math.random(0, 959), y = math.random(50, 500), s = math.random(1, 3) }
  end
  sparks = {}
end

function S.update()
  t = t + 1
  cx = math.max(40, math.min(920, cx + Input.axis(Input.lx) * 6))
  cy = math.max(80, math.min(470, cy + Input.axis(Input.ly) * 6))
  for _, s in ipairs(stars) do
    s.x = s.x - s.s
    if s.x < 0 then s.x, s.y = 959, math.random(50, 500) end
  end
  if Input.pressed("cross") or Input.tap then
    local ox, oy = cx, cy
    if Input.tap then ox, oy = Input.tap.x, Input.tap.y end
    for i = 1, 40 do
      local a, v = math.random() * math.pi * 2, 2 + math.random() * 5
      sparks[#sparks + 1] = { x = ox, y = oy, vx = math.cos(a) * v, vy = math.sin(a) * v, life = 60 }
    end
  end
  for i = #sparks, 1, -1 do
    local p = sparks[i]
    p.x, p.y, p.vy, p.life = p.x + p.vx, p.y + p.vy, p.vy + 0.12, p.life - 1
    if p.life <= 0 then table.remove(sparks, i) end
  end
end

function S.draw()
  -- drawPixel: starfield
  for _, s in ipairs(stars) do
    local v = 80 + s.s * 55
    Graphics.drawPixel(s.x, s.y, Color.new(v, v, v))
  end
  -- drawLine: rotating spirograph  (x1, x2, y1, y2 !)
  for i = 0, 35 do
    local a = t / 60 + i * math.pi / 18
    local x1, y1 = 200 + math.cos(a) * 110, 290 + math.sin(a) * 110
    local x2, y2 = 200 + math.cos(a * 2.5) * 50, 290 + math.sin(a * 2.5) * 50
    Graphics.drawLine(x1, x2, y1, y2, Color.new(95 + i * 4, 139, 255 - i * 3))
  end
  -- fillRect: equaliser bars
  for i = 0, 11 do
    local h = 30 + 90 * math.abs(math.sin(t / 25 + i * 0.6))
    Graphics.fillRect(380 + i * 20, 396 + i * 20, 400 - h, 400, Color.new(249, 199 - i * 8, 79 + i * 12))
  end
  -- fillEmptyRect: nested frames
  for i = 0, 6 do
    local k = (t + i * 10) % 70
    Graphics.fillEmptyRect(660 + k, 900 - k, 110 + k, 330 - k, Color.new(82, 214, 140, 255 - k * 3))
  end
  -- fillCircle: cursor + sparks
  Graphics.fillCircle(cx, cy, 18 + 4 * math.sin(t / 8), C.accent)
  Graphics.fillCircle(cx, cy, 8, C.white)
  for _, p in ipairs(sparks) do
    Graphics.fillCircle(p.x, p.y, 1 + p.life / 20, Color.new(255, 140 + p.life, 80, p.life * 4))
  end

  UI.mono(80, 420, "Graphics.drawLine(x1, x2, y1, y2, color)", C.accent2, 15)
  UI.mono(80, 442, "Graphics.fillRect(x1, x2, y1, y2, color)", C.accent2, 15)
  UI.mono(80, 464, "Graphics.fillCircle(x, y, radius, color)", C.accent2, 15)
  UI.mono(560, 420, "Graphics.drawPixel(x, y, color)", C.accent2, 15)
  UI.mono(560, 442, "Graphics.fillEmptyRect(x1, x2, y1, y2, c)", C.accent2, 15)
  UI.text(560, 466, #sparks .. " particles, " .. APP.fps .. " fps", C.dim, 15)
end

return S
