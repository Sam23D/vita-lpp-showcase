--[[
  lpp-vita showcase — "Hello, Vita!" for every API Lua Player Plus Vita exposes.

  lpp-vita runs app0:/index.lua with luaL_dostring, so this file is only a
  bootstrap: it loads the shared libraries and every scene with dofile.
  Paths: app0:/ is this VPK (read-only), ux0:/data/lpp-showcase/ is our
  writable scratch space (allowed even with the "safe" eboot).
]]

-- LuaJIT's JIT compiler needs sceKernel*VMDomain (executable memory), which the
-- Vita3K emulator does not implement: the first hot loop crashes it (PC = 0x0).
-- The interpreter is plenty for this app, so the JIT is off unless you create
-- ux0:/data/lpp-showcase/jit_on (real hardware only).
if jit then
  jit.off()
  if System.doesFileExist("ux0:/data/lpp-showcase/jit_on") then jit.on() end
end

APP = {
  root = "app0:/",
  data = "ux0:/data/lpp-showcase/",
  title_id = "LPPS00001",
  version = "1.0",
}

function include(path)
  return dofile(APP.root .. path)
end

include("lib/coverage.lua")  -- must be first: wraps every module function
include("lib/ui.lua")
include("lib/input.lua")
include("lib/widgets.lua")
include("lib/services.lua")
include("lib/app.lua")
include("lib/autotest.lua")

APP.scene_files = {
  "hello", "primitives", "images", "fonts", "rescaler",
  "controls", "sound", "mic", "video", "camera", "render3d", "gui",
  "dialogs", "timer", "files", "archives", "database",
  "network", "sockets", "system", "registry", "danger", "coverage",
}

APP.main()
