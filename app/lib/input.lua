-- Input state, sampled once per frame (Controls module).

Input = {
  pad = 0, old = 0,
  lx = 128, ly = 128, rx = 128, ry = 128,
  touch = {}, rear = {}, tap = nil, rear_tap = nil,
  held_frames = {},
}

Input.B = {
  cross = SCE_CTRL_CROSS, circle = SCE_CTRL_CIRCLE,
  square = SCE_CTRL_SQUARE, triangle = SCE_CTRL_TRIANGLE,
  up = SCE_CTRL_UP, down = SCE_CTRL_DOWN, left = SCE_CTRL_LEFT, right = SCE_CTRL_RIGHT,
  l = SCE_CTRL_LTRIGGER, r = SCE_CTRL_RTRIGGER,
  start = SCE_CTRL_START, select = SCE_CTRL_SELECT,
}

-- Japanese consoles swap confirm/cancel; respect the system setting.
Input.ENTER = Controls.getEnterButton()
Input.ENTER_GLYPH = (Input.ENTER == SCE_CTRL_CIRCLE) and "circle" or "cross"

local function pairs_to_points(...)
  local t, out = { ... }, {}
  for i = 1, #t - 1, 2 do out[#out + 1] = { x = t[i], y = t[i + 1] } end
  return out
end

function Input.update()
  Input.old = Input.pad
  Input.pad = Controls.read()
  Input.lx, Input.ly = Controls.readLeftAnalog()
  Input.rx, Input.ry = Controls.readRightAnalog()
  local was_front, was_rear = #Input.touch > 0, #Input.rear > 0
  Input.touch = pairs_to_points(Controls.readTouch())
  Input.rear = pairs_to_points(Controls.readRetroTouch())
  Input.tap = (not was_front and #Input.touch > 0) and Input.touch[1] or nil
  Input.rear_tap = (not was_rear and #Input.rear > 0) and Input.rear[1] or nil
  for name, b in pairs(Input.B) do
    if Controls.check(Input.pad, b) then
      Input.held_frames[name] = (Input.held_frames[name] or 0) + 1
    else
      Input.held_frames[name] = 0
    end
  end
end

function Input.held(name) return (Input.held_frames[name] or 0) > 0 end
function Input.pressed(name) return Input.held_frames[name] == 1 end
function Input.enter() return Controls.check(Input.pad, Input.ENTER) and not Controls.check(Input.old, Input.ENTER) end

-- pressed, then auto-repeat after 18 frames every 4 frames (for d-pad lists)
function Input.rep(name)
  local n = Input.held_frames[name] or 0
  return n == 1 or (n > 18 and n % 4 == 0)
end

-- analog value centred on 0, with a dead zone, in -1..1
function Input.axis(v)
  local a = (v - 128) / 127
  if math.abs(a) < 0.15 then return 0 end
  return math.max(-1, math.min(1, a))
end

function Input.in_rect(p, x, y, w, h)
  return p and p.x >= x and p.x < x + w and p.y >= y and p.y < y + h
end
