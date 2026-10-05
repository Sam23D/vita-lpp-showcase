--[[
  run.lua — drive the showcase headlessly against the lpp-vita mock.

    luajit tools/mock/run.lua [--unsafe] [--shots DIR] [--quiet]

  Opens every scene from the home menu with simulated button presses, runs every
  action, answers system dialogs, injects touches/sensor/socket traffic, saves a
  screenshot per scene, then prints API coverage and every red log line. Exit code
  is non-zero if a scene crashed, an unexpected error was logged, or coverage < 100%.
]]

MOCK_DIR = "tools/mock/"
local args = { unsafe = false, shots = "build/shots", quiet = false }
do
  local i = 1
  while arg[i] do
    if arg[i] == "--unsafe" then args.unsafe = true
    elseif arg[i] == "--shots" then i = i + 1; args.shots = arg[i]
    elseif arg[i] == "--quiet" then args.quiet = true
    elseif arg[i] == "--autotest" then args.autotest = true end
    i = i + 1
  end
end
local MODE = args.unsafe and "unsafe" or "safe"
local SHOTS = args.shots .. "/" .. MODE .. "/"

local M = dofile(MOCK_DIR .. "lpp_mock.lua")
M.cfg.safe = not args.unsafe
M.cfg.app_dir = "build/stage_" .. MODE .. "/"   -- the packaged layout (tools/build.py --stage-only)
M.cfg.sandbox = "build/sandbox_" .. MODE .. "/"
os.execute("rm -rf " .. M.cfg.sandbox .. " && mkdir -p " .. M.cfg.sandbox .. "ux0/data " .. M.cfg.sandbox .. "ur0/shell/db")
os.execute("mkdir -p " .. SHOTS)
os.execute("mkdir -p " .. M.cfg.sandbox .. "vs0/vsh/etc && echo '[layout]' > " .. M.cfg.sandbox .. "vs0/vsh/etc/index_layout.ini")
M.install()

local B = {
  cross = SCE_CTRL_CROSS, circle = SCE_CTRL_CIRCLE, square = SCE_CTRL_SQUARE, triangle = SCE_CTRL_TRIANGLE,
  up = SCE_CTRL_UP, down = SCE_CTRL_DOWN, left = SCE_CTRL_LEFT, right = SCE_CTRL_RIGHT,
  l = SCE_CTRL_LTRIGGER, r = SCE_CTRL_RTRIGGER, start = SCE_CTRL_START, select = SCE_CTRL_SELECT,
}

local report = { scenes = {}, crashes = {}, errors = {}, shots = 0, dialogs = 0 }
local current_scene = "boot"

---------------------------------------------------------------- driver primitives
local function frame(n) for _ = 1, n or 1 do coroutine.yield() end end
local function press(b, hold)
  M.input.buttons = b
  frame(hold or 1)
  M.input.buttons = 0
  frame(1)
end
local function shot(name)
  frame(1) -- make sure the frame we want is on the "front" buffer
  M.save_png(SHOTS .. name .. ".png")
  report.shots = report.shots + 1
end

local function check_crash()
  if APP.scene_error then
    report.crashes[#report.crashes + 1] = current_scene .. ": " .. APP.scene_error
    io.stderr:write("CRASH in " .. current_scene .. ": " .. APP.scene_error .. "\n")
    shot("CRASH_" .. current_scene)
    press(B.triangle)
  end
end

-- answer whatever system dialog is open; progress / no-button dialogs are closed by the app
local function settle_dialogs(max_frames, policy)
  for _ = 1, max_frames or 240 do
    local msg, kb = M.state.msg, M.state.kb
    if not msg and not kb and not Async.busy() then return end
    if kb and kb.state == 2 and M.frame - kb.opened > 3 then
      report.dialogs = report.dialogs + 1
      M.answer_keyboard("Hola Vita " .. M.frame)
    elseif msg and not msg.result and msg.progress == nil and msg.buttons ~= BUTTON_NONE and M.frame - msg.opened > 3 then
      report.dialogs = report.dialogs + 1
      local yes = true
      if policy then yes = policy(msg.text) end
      M.answer_message(yes and FINISHED or CANCELED)
    end
    frame(1)
  end
end

local function open(id)
  io.stderr:write(string.format("[frame %5d] open %s\n", M.frame, id))
  local list = APP.home.list
  local target
  for i, it in ipairs(list.items) do if it.scene.id == id then target = i end end
  assert(target, "no scene " .. id)
  while list.sel < target do press(B.down) end
  while list.sel > target do press(B.up) end
  press(B.cross)
  frame(2)
  current_scene = id
  assert(APP.current().id == id, "expected scene " .. id .. " got " .. tostring(APP.current().id))
  report.scenes[#report.scenes + 1] = id
end

local function back()
  local s = APP.current()
  press(B[s.back_button or "triangle"])
  frame(1)
  assert(APP.current() == APP.home, "back() did not return home from " .. tostring(s.id))
  current_scene = "home"
end

-- run every action of an ActionScene, in order, answering dialogs
local function run_actions(policy, between)
  local s = APP.current()
  for i = 1, #s.actions do
    while s.list.sel < i do press(B.down) end
    while s.list.sel > i do press(B.up) end
    press(B.cross)
    frame(2)
    settle_dialogs(300, policy)
    if between then between(i, s.actions[i]) end
    check_crash()
  end
end

-- collect the red lines the scene logged
local function harvest_log()
  for _, l in ipairs(Log.lines) do
    if l.c == C.err then report.errors[#report.errors + 1] = current_scene .. ": " .. l.s end
  end
end

---------------------------------------------------------------- the script
local function script()
  frame(5)
  shot("00_home")
  -- walk the home menu (also covers List navigation + the scene description panel)
  for _ = 1, 4 do press(B.down) end
  shot("00_home_selected")
  for _ = 1, 4 do press(B.up) end

  -- 1 hello
  open("hello"); frame(30); shot("01_hello"); press(B.square); frame(3); press(B.square); harvest_log(); back()

  -- 2 primitives: stick + touch burst
  open("primitives")
  M.input.lx = 220; frame(10); M.input.lx = 128
  press(B.cross)
  M.input.touch = { { x = 700, y = 200 } }; frame(1); M.input.touch = {}; frame(10)
  shot("02_primitives"); harvest_log(); back()

  -- 3 images: three pages, every page action, painting
  open("images")
  frame(20); shot("03_images_p1")
  press(B.square); frame(2)
  press(B.r); frame(2)
  for _ = 1, 6 do M.input.buttons = B.cross; frame(1); M.input.buttons = B.right; frame(1) end
  M.input.buttons = 0
  M.input.touch = { { x = 200, y = 250 } }; frame(3); M.input.touch = {}
  M.input.lx, M.input.ly = 200, 60; frame(5); M.input.lx, M.input.ly = 128, 128
  press(B.square); frame(3)
  shot("03_images_p2")
  press(B.r); frame(2)
  press(B.square); frame(30)
  shot("03_images_p3")
  press(B.l); press(B.l)
  harvest_log(); back()

  -- 4 fonts
  open("fonts"); press(B.up); press(B.up); press(B.down); press(B.square); frame(5); shot("04_fonts"); harvest_log(); back()

  -- 5 rescaler: cycle all modes
  open("rescaler"); frame(10); shot("05_rescaler_2x")
  press(B.square); frame(5); shot("05_rescaler_3ds")
  press(B.square); frame(5); press(B.square); frame(3)
  harvest_log(); back()

  -- 6 controls: buttons, sticks, touches, lock, rumble
  open("controls")
  M.input.buttons = B.cross + B.l + B.up
  M.input.lx, M.input.ly, M.input.rx, M.input.ry = 40, 200, 230, 30
  M.input.touch = { { x = 300, y = 200 }, { x = 600, y = 380 } }
  M.input.rear = { { x = 480, y = 272 } }
  frame(12)
  shot("06_controls")
  M.input.buttons, M.input.touch, M.input.rear = 0, {}, {}
  M.input.lx, M.input.ly, M.input.rx, M.input.ry = 128, 128, 128, 128
  press(B.start); press(B.select, 2); frame(30); press(B.start)
  harvest_log(); back()

  -- 7 sound
  open("sound")
  run_actions(nil, function(i, a)
    if a.file then
      -- adjust volume of the selected track with L/R, then pause/resume it
      M.input.buttons = B.l; frame(5); M.input.buttons = B.r; frame(2); M.input.buttons = 0; frame(1)
      press(B.cross); frame(1); press(B.cross)
    end
  end)
  -- play two tracks again so the screenshot shows open handles
  local s = APP.current()
  while s.list.sel > 1 do press(B.up) end
  press(B.cross); press(B.down); press(B.cross); frame(5)
  shot("07_sound"); harvest_log(); back()

  -- 8 mic: record, pause, resume, stop & play; then let one run to completion; invalid rate
  open("mic")
  press(B.up)
  press(B.cross); frame(30); press(B.square); frame(10); press(B.square); frame(10)
  shot("08_mic_recording")
  press(B.circle); frame(5)
  press(B.cross); frame(5 * 60 + 10)
  press(B.down); frame(3)
  shot("08_mic_done"); harvest_log(); back()

  -- 9 video
  open("video"); frame(70); shot("09_video")
  press(B.circle); frame(2); press(B.circle)
  press(B.r); press(B.r); frame(30); press(B.l); press(B.l)
  press(B.right); press(B.left)
  press(B.square); frame(40)
  M.input.buttons = B.down; frame(5); M.input.buttons = B.up; frame(3); M.input.buttons = 0
  shot("09_video_srt"); harvest_log(); back()

  -- 10 camera: walk every setting, change each, swap camera, take photos
  open("camera")
  for _ = 1, 14 do press(B.right); press(B.right); press(B.left); press(B.down) end
  press(B.cross); frame(3); press(B.square); frame(3); press(B.cross); frame(3); press(B.square)
  frame(5); shot("10_camera"); harvest_log(); back()

  -- 11 3D
  open("render3d")
  M.input.lx, M.input.ly, M.input.rx, M.input.ry = 170, 150, 140, 110
  frame(20); M.input.lx, M.input.ly, M.input.rx, M.input.ry = 128, 128, 128, 128
  press(B.square); frame(10); shot("11_render3d")
  press(B.cross); frame(2); press(B.cross)
  harvest_log(); back()

  -- 12 gui: open each menu for a frame so menu items get drawn, then the about box
  open("gui")
  for _, m in ipairs({ "App", "Theme", "Input" }) do M.gui_open = m; frame(2) end
  M.gui_open = nil
  frame(5); shot("12_gui"); harvest_log(); back()

  -- 13 dialogs: every message layout, progress, keyboards
  open("dialogs")
  run_actions(function(text) return not text:find("second", 1, true) end, function(i)
    if i == 2 then shot("13_dialog_overlay_done") end
  end)
  -- one screenshot with a dialog visibly open
  local s13 = APP.current()
  while s13.list.sel > 2 do press(B.up) end
  press(B.cross); frame(3); shot("13_dialogs_open"); settle_dialogs()
  frame(3); shot("13_dialogs"); harvest_log(); back()

  -- 14 timer
  open("timer")
  press(B.cross); frame(90); press(B.square); frame(40); press(B.square)
  press(B.down); frame(10)
  press(B.l); frame(60)
  press(B.r); frame(2)
  press(B.cross); frame(5)
  shot("14_timer")
  press(B.circle); frame(2)
  harvest_log(); back()

  -- 15 files: all actions, then the browser
  open("files")
  run_actions()
  press(B.square); frame(2); press(B.cross); frame(2); press(B.down); press(B.cross); frame(3)
  shot("15_files_browser")
  press(B.square); frame(2)
  shot("15_files"); harvest_log(); back()

  -- 16 archives
  open("archives"); run_actions(); frame(5); shot("16_archives"); harvest_log(); back()

  -- 17 database
  open("database"); run_actions()
  local s17 = APP.current()
  while s17.list.sel > 1 do press(B.up) end
  for _ = 1, 6 do press(B.cross) end -- a few rows for the screenshot
  frame(3); shot("17_database"); harvest_log(); back()

  -- 18 network
  open("network"); run_actions(); frame(5); shot("18_network")
  -- leave FTP running? run_actions toggled it once (on). Turn it off again by re-running that action.
  harvest_log(); back()

  -- 19 sockets: start server, connect a fake PC client, then the rest
  open("sockets")
  run_actions(nil, function(i)
    if i == 1 then
      local c = M.socket_client("hello vita\r\n")
      frame(3)
      assert(c.sent and c.sent:find("PS Vita says: hello vita", 1, true), "echo server did not answer: " .. tostring(c.sent))
    end
  end)
  frame(3); shot("19_sockets")
  local s19 = APP.current()
  while s19.list.sel > 1 do press(B.up) end
  press(B.cross) -- stop server
  harvest_log(); back()

  -- 20 system
  open("system")
  press(B.up); press(B.up); press(B.down); press(B.down)
  press(B.square); frame(2); press(B.square); frame(2); press(B.square); frame(2)
  press(B.cross); frame(2)
  press(B.circle); frame(2); settle_dialogs()
  frame(600) -- reaches the periodic resetTimer
  press(B.cross)
  shot("20_system"); harvest_log(); back()

  -- 21 registry
  open("registry"); run_actions(); shot("21_registry"); harvest_log(); back()

  -- 22 danger zone: say yes to everything except quitting the app
  -- prepare optional inputs so install/plugin branches run in the mock
  os.execute("mkdir -p " .. M.cfg.sandbox .. "ux0/data/lpp-showcase/install")
  for _, f in ipairs({ "plugin.suprx", "plugin.skprx" }) do
    local h = io.open(M.cfg.sandbox .. "ux0/data/lpp-showcase/" .. f, "w"); h:write("x"); h:close()
  end
  open("danger")
  run_actions(function(text) return not text:find("Quit", 1, true) end)
  shot("22_danger"); harvest_log(); back()

  -- 23 coverage: browse modules, save report
  open("coverage")
  for _ = 1, 5 do press(B.right) end
  press(B.square); frame(3)
  shot("23_coverage"); harvest_log(); back()

  -- quit from the home menu (System.exit)
  frame(3)
  shot("00_home_end")
  press(B.start)
end

---------------------------------------------------------------- run
if args.autotest then
  -- let the app's own in-app autotest (app/lib/autotest.lua) drive itself
  os.execute("mkdir -p " .. M.cfg.sandbox .. "ux0/data/lpp-showcase && touch " .. M.cfg.sandbox .. "ux0/data/lpp-showcase/autotest")
  script = function()
    while true do
      -- the in-app driver closes dialogs itself, except the mock never ends a message on its own
      frame(1)
    end
  end
  M.cfg.log_console = true
end
local co = coroutine.create(script)
M.on_flip = function()
  M.tick_async()
  M.tick_video()
  local ok, err = coroutine.resume(co)
  if not ok then
    io.stderr:write("DRIVER ERROR in " .. current_scene .. ": " .. tostring(err) .. "\n" .. debug.traceback(co) .. "\n")
    report.crashes[#report.crashes + 1] = "driver: " .. tostring(err)
    error({ mock_exit = true }, 0)
  end
  if coroutine.status(co) == "dead" then error({ mock_exit = true }, 0) end
  if M.frame > 20000 then error("runaway: too many frames", 0) end
end

-- the gui mock reads which menu is open from M.gui_open
local main = assert(loadfile(M.cfg.app_dir .. "index.lua"))
local t0 = os.clock()
local ok, err = pcall(main)
local exited = (not ok) and type(err) == "table" and err.mock_exit
if not ok and not exited then
  report.crashes[#report.crashes + 1] = "top-level: " .. tostring(err)
  io.stderr:write("TOP-LEVEL ERROR: " .. tostring(err) .. "\n")
end

---------------------------------------------------------------- report
local hit, total = Coverage.summary()
local missing = Coverage.missing()
print(string.format("== lpp-vita showcase / mock run (%s eboot) ==", MODE))
print(string.format("frames %d (%.1fs simulated), wall %.1fs, scenes %d, screenshots %d, dialogs answered %d",
  M.frame, M.frame / 60, os.clock() - t0, #report.scenes, report.shots, report.dialogs))
print(string.format("native calls checked: %d   argument errors raised by the C-derived checks: %d",
  M.stats.calls, M.stats.arg_errors))
print(string.format("API coverage: %d / %d functions", hit, total))
if #missing > 0 then print("  never called: " .. table.concat(missing, ", ")) end
print("side effects requested: " .. table.concat(M.events, " | "))
if not args.quiet then
  print("red log lines (" .. #report.errors .. "):")
  for _, e in ipairs(report.errors) do print("  " .. e) end
end
print("crashes: " .. #report.crashes)
for _, c in ipairs(report.crashes) do print("  " .. c) end
local fw = io.open(SHOTS .. "report.txt", "w")
fw:write(table.concat(report.errors, "\n"), "\n")
fw:close()

-- pass/fail: every red line must be one of the intentional error demos, no argument
-- errors, no crashes, and every function called (in safe mode: every function that
-- does not require the unsafe eboot).
local EXPECTED = {
  "bad argument #4 to 'loadImage'", "unknown audio file format", "multiple of 16000",
  "cannot start multiple message instances", "cannot open requested file", "SFO file is corrupted",
  "SELEKT", "Network is already inited", "not allowed for server sockets", "requires unsafe mode",
  "Running the SAFE eboot", "Rebuild with --unsafe",
}
local unexpected = {}
for _, e in ipairs(report.errors) do
  local ok = false
  for _, pat in ipairs(EXPECTED) do if e:find(pat, 1, true) then ok = true end end
  if not ok then unexpected[#unexpected + 1] = e end
end
local uncovered = {}
for _, name in ipairs(missing) do
  local mod, fn = name:match("^(%w+)%.(%w+)$")
  if not (M.cfg.safe and M.API.modules[mod][fn].unsafe) then uncovered[#uncovered + 1] = name end
end
print(string.format("unexpected red lines: %d   required functions never called: %d", #unexpected, #uncovered))
for _, e in ipairs(unexpected) do print("  UNEXPECTED " .. e) end
for _, e in ipairs(uncovered) do print("  UNCOVERED " .. e) end
local pass = #report.crashes == 0 and #unexpected == 0 and #uncovered == 0 and M.stats.arg_errors == 0
print(pass and "RESULT: PASS" or "RESULT: FAIL")
os.exit(pass and 0 or 1)
