-- 5. Rescaler: write a game at a low resolution and let lpp-vita upscale it.
local S = {
  title = "Rescaler", modules = { "Graphics" },
  desc = "Graphics.initRescaler(x, y, xscale, yscale) redirects all drawing into an off-screen buffer "
      .. "that termBlend scales onto the screen; termRescaler turns it off. This is how lpp-3ds "
      .. "(400x240) or PSP-sized (480x272) games are ported. The demo draws a 480x272 game and "
      .. "toggles 1x, 2x and fit modes.",
  hints = { { "square", "Mode" } },
}

local modes = {
  { "off (native 960x544)" },
  { "2x  (480x272 -> 960x544)", 0, 0, 2, 2 },
  { "3DS 400x240 -> fit height", math.floor(480 - 400 * 544 / 240 / 2), 0, 544 / 240, 544 / 240 },
}
local mode, t, ball = 2, 0, { x = 100, y = 100, vx = 2.3, vy = 1.7 }

local function apply()
  if S.active then
    Try("termRescaler", Graphics.termRescaler)
    S.active = false
  end
  local m = modes[mode]
  if m[2] then
    S.active = Try("initRescaler" .. string.format("(%d, %d, %.2f, %.2f)", m[2], m[3], m[4], m[5]),
      Graphics.initRescaler, m[2], m[3], m[4], m[5])
  end
end

function S.enter() apply() end
function S.leave() if S.active then Graphics.termRescaler(); S.active = false end end

function S.update()
  t = t + 1
  if Input.pressed("square") then mode = mode % #modes + 1; apply() end
  local W, H = 480, 272
  if mode == 3 then W, H = 400, 240 end
  ball.x, ball.y = ball.x + ball.vx, ball.y + ball.vy
  if ball.x < 8 or ball.x > W - 8 then ball.vx = -ball.vx end
  if ball.y < 8 or ball.y > H - 8 then ball.vy = -ball.vy end
end

-- with the rescaler on, the whole frame (UI included) is drawn at low-res
function S.frame()
  Graphics.initBlend()
  Screen.clear(C.bg)
  local W, H = 480, 272
  if mode == 3 then W, H = 400, 240 end
  if mode == 1 then W, H = 960, 544 end
  Graphics.fillRect(0, W, 0, H, Color.new(30, 40, 70))
  for x = 0, W, 16 do Graphics.drawLine(x, x, 0, H, Color.new(45, 58, 95)) end
  for y = 0, H, 16 do Graphics.drawLine(0, W, y, y, Color.new(45, 58, 95)) end
  Graphics.fillEmptyRect(0, W - 1, 0, H - 1, C.accent2)
  Graphics.fillCircle(ball.x, ball.y, 8, C.err)
  Graphics.debugPrint(6, 4, string.format("logical %dx%d", W, H), C.white)
  Graphics.debugPrint(6, 24, modes[mode][1], C.accent2)
  Graphics.debugPrint(6, H - 26, "SQUARE: next mode   TRIANGLE: back", C.dim)
  Graphics.termBlend()
end

return S
