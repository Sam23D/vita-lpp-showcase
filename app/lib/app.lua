-- App shell: scene registry, main loop, crash-safe frame, home menu.

APP.frame = 0
APP.fps = 0
APP.scenes = {}
APP.by_id = {}

local function load_scenes()
  for _, id in ipairs(APP.scene_files) do
    local ok, scene = pcall(include, "scenes/" .. id .. ".lua")
    if not ok then
      scene = { title = id, desc = "Failed to load: " .. tostring(scene), modules = {}, broken = true }
    end
    scene.id = id
    APP.scenes[#APP.scenes + 1] = scene
    APP.by_id[id] = scene
  end
end

---------------------------------------------------------------- scene stack
local stack = {}

function APP.current() return stack[#stack] end

function APP.push(scene)
  stack[#stack + 1] = scene
  Log.clear()
  Log.info("> " .. (scene.title or scene.id))
  if scene.enter_actions then scene.enter_actions() end
  if scene.enter then
    local ok, err = pcall(scene.enter, scene)
    if not ok then Log.err("enter: " .. tostring(err)) end
  end
end

function APP.pop()
  local scene = table.remove(stack)
  if scene and scene.leave then
    local ok, err = pcall(scene.leave, scene)
    if not ok then Log.err("leave: " .. tostring(err)) end
  end
end

---------------------------------------------------------------- home menu
local Home = { id = "home", title = "Hello, Vita!", subtitle = "lpp-vita API showcase" }
APP.home = Home

function Home.enter()
  local items = {}
  for _, s in ipairs(APP.scenes) do
    items[#items + 1] = {
      label = s.title, sub = table.concat(s.modules or {}, " "),
      color = s.broken and C.err or nil,
      scene = s,
      action = function(it) if not it.scene.broken then APP.push(it.scene) end end,
    }
  end
  Home.list = Home.list or List.new(items, { w = 470, rows = 13, row = 34 })
  Home.list.items = items
end

function Home.update()
  Home.list:update()
  if Input.pressed("start") then System.exit() end
end

local function module_cov(mods)
  local hit, total = 0, 0
  for _, entry in ipairs(Coverage.modules) do
    for _, m in ipairs(mods or {}) do
      if entry.name == m then
        local h, t = Coverage.module_stats(entry)
        hit, total = hit + h, total + t
      end
    end
  end
  return hit, total
end

function Home.draw()
  Home.list:draw()
  local s = Home.list:current().scene
  local x, y, w = 512, UI.HEADER + 12, UI.W - 512 - 14
  UI.panel(x, y, w, 300, s.title)
  local used = UI.paragraph(x + 14, y + 38, s.desc or "", w - 28, C.text, 17, 23)
  local hit, total = module_cov(s.modules)
  if total > 0 then
    UI.text(x + 14, y + 300 - 60, "API calls made from these modules", C.dim, 14)
    UI.bar(x + 14, y + 300 - 38, w - 120, 16, hit / total, C.ok)
    UI.text(x + w - 96, y + 300 - 40, hit .. " / " .. total, C.text, 16)
  end
  -- banner
  local by = y + 314
  UI.panel(x, by, w, 140)
  if APP.logo then Graphics.drawImage(x + 14, by + 22, APP.logo) end
  local h, t = Coverage.summary()
  UI.text(x + 286, by + 20, "Interpreter", C.dim, 14)
  UI.text(x + 286, by + 38, System.isSafeMode() and "safe eboot" or "UNSAFE eboot", System.isSafeMode() and C.ok or C.warn, 17)
  UI.text(x + 286, by + 66, "Whole API exercised", C.dim, 14)
  UI.text(x + 286, by + 84, string.format("%d / %d  (%d%%)", h, t, math.floor(100 * h / t)), C.accent2, 17)
  UI.text(x + 14, by + 121, "v" .. APP.version .. "  |  " .. APP.fps .. " fps  |  " .. #APP.scenes .. " demos", C.dim, 14)
end

Home.hints = { { "enter", "Open" }, { "start", "Quit" } }

---------------------------------------------------------------- frame
local function draw_error_overlay(err)
  UI.rect(80, 160, 800, 200, C.panel)
  UI.frame(80, 160, 800, 200, C.err)
  UI.bold(100, 176, "Scene error", C.err, 22)
  UI.paragraph(100, 214, err, 760, C.text, 16)
  UI.text(100, 330, "Press TRIANGLE to go back to the menu.", C.dim, 16)
end

function APP.main()
  if not System.doesDirExist("ux0:/data") then System.createDirectory("ux0:/data") end
  if not System.doesDirExist(APP.data) then System.createDirectory(APP.data) end
  UI.init()
  APP.logo = Graphics.loadImage(APP.root .. "assets/img/hello.png")
  load_scenes()
  APP.push(Home)
  if Autotest then Autotest.maybe_start() end

  local fps_timer, fps_frames = Timer.new(), 0
  APP.scene_error = nil

  while true do
    APP.frame = APP.frame + 1
    fps_frames = fps_frames + 1
    if Timer.getTime(fps_timer) >= 1000 then
      APP.fps = fps_frames
      fps_frames = 0
      Timer.reset(fps_timer)
    end

    Input.update()
    local scene = APP.current()
    Dialog.update()
    Async.update()

    if APP.scene_error then
      if Input.pressed("triangle") then
        APP.scene_error = nil
        APP.pop()
      end
    elseif Dialog.busy() then
      -- the OS dialog owns the input while it is open; scenes may still animate via tick()
      if scene.tick then pcall(scene.tick, scene) end
    else
      if scene.tick then pcall(scene.tick, scene) end
      local back = scene.back_button or "triangle"
      if scene ~= Home and Input.pressed(back) and not (scene.blocks_back and scene.blocks_back()) then
        APP.pop()
        scene = APP.current()
      elseif scene.update then
        local ok, err = pcall(scene.update, scene)
        if not ok then APP.scene_error = tostring(err) end
      end
    end

    if scene.frame and not APP.scene_error then
      -- scenes that need full control of the frame (rescaler, 3D, gui)
      local ok, err = pcall(scene.frame, scene)
      if not ok then
        APP.scene_error = tostring(err)
        pcall(Graphics.termBlend)
      end
    else
      Graphics.initBlend()
      Screen.clear(C.bg)
      if APP.scene_error then
        draw_error_overlay(APP.scene_error)
      else
        local ok, err = pcall(scene.draw, scene)
        if not ok then APP.scene_error = tostring(err) end
      end
      UI.header(scene.title, scene.subtitle or table.concat(scene.modules or {}, " / "))
      local hints = {}
      for _, h in ipairs(scene.hints or {}) do hints[#hints + 1] = h end
      if scene ~= Home then hints[#hints + 1] = { scene.back_button or "triangle", "Back" } end
      UI.footer(hints)
      Graphics.termBlend()
    end
    Screen.flip()
    Defer.update()
  end
end

-- convenience for scenes that implement frame(): standard chrome around custom drawing
function APP.chrome(scene)
  UI.header(scene.title, scene.subtitle or table.concat(scene.modules or {}, " / "))
  local hints = {}
  for _, h in ipairs(scene.hints or {}) do hints[#hints + 1] = h end
  hints[#hints + 1] = { scene.back_button or "triangle", "Back" }
  UI.footer(hints)
end
