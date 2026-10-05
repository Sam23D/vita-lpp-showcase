-- 14. Timer: millisecond stopwatches.
local S = {
  title = "Timer", modules = { "Timer", "System" },
  desc = "Timer.new creates a running millisecond stopwatch. getTime, setTime, pause, resume, reset, "
      .. "isPlaying and destroy, shown as a stopwatch with laps and a countdown. System.wait (in "
      .. "microseconds) blocks the whole app; its cost is measured with a timer.",
  hints = { { "cross", "Start/Stop" }, { "square", "Lap" }, { "circle", "Reset" }, { "down", "Set 59 s" },
            { "l", "Countdown" }, { "r", "wait()" } },
}

local sw, cd, laps = nil, nil, {}
local COUNT = 10000

function S.enter()
  sw = Timer.new()      -- timers start running...
  Timer.pause(sw)       -- ...so pause + reset gives a stopped 00:00.000
  Timer.reset(sw)
  laps = {}
end

function S.leave()
  if sw then Timer.destroy(sw); sw = nil end
  if cd then Timer.destroy(cd); cd = nil end
end

local function fmt(ms)
  ms = math.max(0, ms)
  return string.format("%02d:%02d.%03d", math.floor(ms / 60000), math.floor(ms / 1000) % 60, ms % 1000)
end

function S.update()
  if Input.pressed("cross") then
    if Timer.isPlaying(sw) then Try("Timer.pause", Timer.pause, sw) else Try("Timer.resume", Timer.resume, sw) end
  end
  if Input.pressed("square") then
    table.insert(laps, 1, Timer.getTime(sw))
    if #laps > 8 then table.remove(laps) end
  end
  if Input.pressed("circle") then
    Try("Timer.reset", Timer.reset, sw) -- keeps the running/paused state
    laps = {}
  end
  if Input.pressed("down") then
    -- lpp quirk: setTime on a RUNNING timer stores now+value, so getTime() then reports -value.
    -- The reliable pattern is pause -> setTime -> resume.
    local was = Timer.isPlaying(sw)
    Timer.pause(sw)
    Try("Timer.setTime(sw, 59000)", Timer.setTime, sw, 59000)
    if was then Timer.resume(sw) end
  end
  if Input.pressed("l") then
    if cd then Timer.destroy(cd) end
    cd = Timer.new()
    Log.info("countdown: remaining = 10000 - Timer.getTime(cd)")
  end
  if Input.pressed("r") then
    local t = Timer.new()
    System.wait(250000) -- microseconds!
    Log.ok(string.format("System.wait(250000) blocked for %d ms", Timer.getTime(t)))
    Timer.destroy(t)
  end
end

function S.draw()
  local ms = Timer.getTime(sw)
  local running = Timer.isPlaying(sw)
  UI.panel(40, 70, 520, 230, "Stopwatch")
  UI.text(60, 124, fmt(ms), running and C.white or C.dim, 54, UI.font.mono)
  UI.text(70, 210, running and "running  (isPlaying = true)" or "paused  (isPlaying = false)",
    running and C.ok or C.warn, 17)
  -- analog dial: the hand does one turn per minute
  local cx, cy = 490, 190
  Graphics.fillCircle(cx, cy, 60, C.panel2)
  for i = 0, 11 do
    local a = i * math.pi / 6
    UI.line(cx + math.sin(a) * 50, cy - math.cos(a) * 50, cx + math.sin(a) * 58, cy - math.cos(a) * 58, C.dim)
  end
  local a = (ms % 60000) / 60000 * 2 * math.pi
  UI.line(cx, cy, cx + math.sin(a) * 52, cy - math.cos(a) * 52, C.err)
  Graphics.fillCircle(cx, cy, 4, C.white)

  UI.panel(580, 70, 340, 230, "Laps")
  for i, l in ipairs(laps) do UI.mono(600, 100 + (i - 1) * 24, string.format("#%d  %s", #laps - i + 1, fmt(l)), C.text, 16) end

  UI.panel(40, 316, 520, 170, "Countdown")
  if cd then
    local left = COUNT - Timer.getTime(cd)
    if left <= 0 then
      UI.bold(70, 360, "LIFTOFF!", C.ok, 40)
    else
      UI.text(70, 356, string.format("%.1f", left / 1000), C.accent2, 48, UI.font.mono)
      UI.bar(70, 430, 460, 14, left / COUNT, C.accent2)
    end
  else
    UI.text(70, 370, "press L", C.dim, 18)
  end
  Log.draw(580, 316, 340, 170)
end

return S
