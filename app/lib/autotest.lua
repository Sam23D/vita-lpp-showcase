-- Autotest: drives the whole app from inside the console/emulator.
-- Enabled when ux0:/data/lpp-showcase/autotest exists (tools/emu.sh --autotest creates it).
-- It replaces the button/touch sources, visits every scene, runs the safe actions,
-- prints "AUTOTEST ..." through System.consolePrint before every step (so a crash in
-- the emulator log points at the exact call), saves a screenshot per scene and exits.

Autotest = { pad = 0, touch = {}, rear = {}, active = false, step = "" }

-- actions that leave the app, touch the OS, or need a human (IME keyboard)
local SKIP = { "Keyboard:", "launchApp", "launchEboot", "Standby", "Reboot", "Shutdown", "Exit app",
  "Re-install", "uninstallApp", "Plugins:", "Remount", "unmountMountpoint" }
local SKIP_SCENES = { danger = true }

local function say(s)
  Autotest.step = s
  System.consolePrint("AUTOTEST " .. s)
end

local function frame(n) for _ = 1, n or 1 do coroutine.yield() end end
local function press(b, hold)
  Autotest.pad = b
  frame(hold or 1)
  Autotest.pad = 0
  frame(1)
end

local function shot(name)
  frame(2)
  local dir = APP.data .. "shots/"
  if not System.doesDirExist(dir) then System.createDirectory(dir) end
  pcall(System.takeScreenshot, dir .. name .. ".png", FORMAT_PNG)
end

-- wait for system dialogs / async jobs; message dialogs are closed after a moment
local function settle()
  for i = 1, 600 do
    if not Dialog.busy() and not Async.busy() then return end
    if Dialog.msg and i == 30 then
      say("  closing system message")
      pcall(System.closeMessage)
    end
    if Dialog.kb and i == 30 then
      say("  keyboard open - cannot answer it, clearing")
      pcall(Keyboard.clear)
      Dialog.kb = nil
    end
    frame(1)
  end
  say("  WARNING: dialog/async still busy after 10 s")
end

local function open(scene)
  say("open " .. scene.id)
  local list = APP.home.list
  for i, it in ipairs(list.items) do if it.scene == scene then list.sel = i end end
  press(Input.ENTER)
  frame(30)
end

local function back()
  local s = APP.current()
  if s == APP.home then return end
  say("back from " .. tostring(s.id))
  press(Input.B[s.back_button or "triangle"])
  frame(5)
  if APP.current() ~= APP.home then
    say("  still in " .. tostring(APP.current().id) .. ", popping")
    APP.pop()
  end
end

local function skipped(label)
  for _, k in ipairs(SKIP) do if label:find(k, 1, true) then return true end end
  return false
end

local function run_actions(s)
  for i, a in ipairs(s.actions) do
    if skipped(a.label) then
      say("  skip action: " .. a.label)
    else
      say("  action " .. i .. ": " .. a.label)
      s.list.sel = i
      press(Input.ENTER)
      frame(3)
      settle()
      if APP.scene_error then say("  SCENE ERROR: " .. APP.scene_error) end
    end
  end
end

-- extra button presses per scene (mirrors tools/mock/run.lua)
local B = Input.B
local EXTRA = {
  hello = function() frame(60); press(B.square); frame(10); press(B.square) end,
  primitives = function() press(B.cross); Autotest.touch = { { x = 700, y = 200 } }; frame(2); Autotest.touch = {}; frame(30) end,
  images = function()
    frame(30); press(B.square); frame(5); shot("images_p1")
    press(B.r); for _ = 1, 10 do Autotest.pad = B.cross + B.right; frame(1) end; Autotest.pad = 0
    press(B.square); frame(10); shot("images_p2")
    press(B.r); press(B.square); frame(5); settle(); frame(20); shot("images_p3")
  end,
  fonts = function() press(B.up); press(B.up); press(B.square); frame(10) end,
  rescaler = function() frame(20); press(B.square); frame(20); press(B.square); frame(20); press(B.square); frame(10) end,
  controls = function()
    Autotest.touch = { { x = 300, y = 200 }, { x = 600, y = 380 } }; Autotest.rear = { { x = 480, y = 272 } }
    Autotest.pad = B.cross + B.l; frame(20); Autotest.pad = 0; Autotest.touch = {}; Autotest.rear = {}
    press(B.start); press(B.select); frame(30); press(B.start)
  end,
  mic = function() press(B.cross); frame(60); press(B.square); frame(20); press(B.square); frame(20); press(B.circle); frame(60); press(B.down); frame(5) end,
  video = function() frame(120); shot("video"); press(B.circle); frame(10); press(B.circle); press(B.r); frame(30); press(B.l); press(B.square); frame(60) end,
  camera = function()
    frame(30)
    for _ = 1, 14 do press(B.right); press(B.down) end
    press(B.square); frame(10); press(B.cross); frame(30)
  end,
  render3d = function() frame(60); press(B.square); frame(30) end,
  gui = function() frame(90) end,
  timer = function() press(B.cross); frame(90); press(B.square); press(B.down); press(B.l); frame(60); press(B.r); frame(5) end,
  files = function() press(B.square); frame(10); press(Input.ENTER); frame(10); shot("files_browser"); press(B.square) end,
  system = function()
    frame(30)
    press(B.up); press(B.down)
    press(B.square); frame(10); press(B.square); frame(10); press(B.square); frame(10)
    press(B.cross); frame(10); press(B.cross)
  end,
  coverage = function() for _ = 1, 6 do press(B.right) end; press(B.square); frame(10) end,
}

local function script()
  frame(30)
  say("start  safe=" .. tostring(System.isSafeMode()))
  shot("00_home")
  for _, scene in ipairs(APP.scenes) do
    if SKIP_SCENES[scene.id] or scene.broken then
      say("skip scene " .. scene.id .. (scene.broken and " (BROKEN: " .. tostring(scene.desc) .. ")" or ""))
    else
      open(scene)
      if APP.current() ~= scene then
        say("  FAILED to open " .. scene.id .. (APP.scene_error and (": " .. APP.scene_error) or ""))
      else
        if scene.actions then run_actions(scene) end
        if EXTRA[scene.id] then say("  extra input"); EXTRA[scene.id]() end
        settle()
        shot(scene.id)
        if APP.scene_error then say("  SCENE ERROR: " .. APP.scene_error) end
        for _, l in ipairs(Log.lines) do
          if l.c == C.err then say("  red: " .. l.s) end
        end
        back()
      end
    end
  end
  local h, t = Coverage.summary()
  say(string.format("DONE coverage %d/%d", h, t))
  local fh = System.openFile(APP.data .. "autotest_done", FCREATE)
  System.writeFile(fh, "ok", 2)
  System.closeFile(fh)
  frame(30)
  Autotest.finished = true
end

local co

function Autotest.start()
  Autotest.active = true
  co = coroutine.create(script)
  local real_read = Controls.read
  Controls.read = function()
    if coroutine.status(co) ~= "dead" then
      local ok, err = coroutine.resume(co)
      if not ok then say("DRIVER ERROR at '" .. Autotest.step .. "': " .. tostring(err)) end
    end
    if Autotest.finished then System.exit() end
    return Autotest.pad
  end
  Controls.readLeftAnalog = function() return 128, 128 end
  Controls.readRightAnalog = function() return 128, 128 end
  local function pts(list)
    local out = {}
    for _, p in ipairs(list) do out[#out + 1] = p.x; out[#out + 1] = p.y end
    return unpack(out)
  end
  Controls.readTouch = function() return pts(Autotest.touch) end
  Controls.readRetroTouch = function() return pts(Autotest.rear) end
  System.consolePrint("AUTOTEST enabled (" .. tostring(real_read ~= nil) .. ")")
end

function Autotest.maybe_start()
  if System.doesFileExist(APP.data .. "autotest") then Autotest.start() end
end
