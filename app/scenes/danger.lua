-- 22. Danger zone: power, launching, app install, plugins, partitions (mostly unsafe).
-- Every action asks for confirmation through a system dialog first.
local S = ActionScene({
  title = "Danger Zone", modules = { "System" },
  desc = "Calls that leave the app or touch the OS: exit, reboot, shutdown, standby, launchApp, "
      .. "launchEboot, and with the unsafe eboot installApp, uninstallApp and doesAppExist, user and "
      .. "kernel plugins (taiHEN), unmountPartition, mountPartition and unmountMountpoint. Every "
      .. "action asks first. Nothing here is destructive unless you confirm it.",
  hints = { { "enter", "Run (asks first)" } },
  rows = 12,
})

local function confirm(text, fn) return function() Dialog.confirm(text, fn) end end

local SELF = APP.title_id
local SETTINGS_APP = "NPXS10015"

S.actions = {
  { label = "doesAppExist(" .. SELF .. ")", action = function()
      Try("doesAppExist(self)", System.doesAppExist, SELF)
      Try("doesAppExist(" .. SETTINGS_APP .. ")", System.doesAppExist, SETTINGS_APP)
      Try("doesAppExist(ABCD12345)", System.doesAppExist, "ABCD12345")
    end },
  { label = "launchApp: Settings", color = C.warn, action = confirm(
      "Open the system Settings app?\nThis showcase will close.", function()
        Try("launchApp(" .. SETTINGS_APP .. ")", System.launchApp, SETTINGS_APP)
      end) },
  { label = "launchEboot: restart this app", color = C.warn, action = confirm(
      "Restart the showcase with System.launchEboot('app0:/eboot.bin')?", function()
        Try("launchEboot", System.launchEboot, "app0:/eboot.bin")
      end) },
  { label = "Standby (sleep)", color = C.warn, action = confirm("Put the Vita to sleep?", function()
      Try("standby", System.standby)
    end) },
  { label = "Reboot", color = C.err, action = confirm("Reboot the console now?", function() Try("reboot", System.reboot) end) },
  { label = "Shutdown", color = C.err, action = confirm("Power off the console now?", function() Try("shutdown", System.shutdown) end) },
  { label = "Exit app (System.exit)", color = C.warn, action = confirm("Quit the showcase?", function() System.exit() end) },
  { label = "Re-install extracted app (unsafe)", color = C.err, action = function()
      local dir = "ux0:/data/lpp-showcase/install/"
      if not System.doesDirExist(dir) then
        Log.err("installApp(dir) promotes an EXTRACTED app folder (eboot.bin + sce_sys/).")
        Log.info("  extract a VPK to " .. dir .. " first, e.g. with")
        Log.info("  System.extractZip('ux0:/x.vpk', '" .. dir .. "')")
        return
      end
      Dialog.confirm("Install the app extracted in\n" .. dir .. " ?", function()
        Try("installApp", System.installApp, dir)
      end)
    end },
  { label = "uninstallApp(ABCD12345) - nonexistent", action = confirm(
      "Call System.uninstallApp('ABCD12345')?\n(no such app: shows the call, removes nothing)", function()
        Try("uninstallApp(ABCD12345)", System.uninstallApp, "ABCD12345")
      end) },
  { label = "Plugins: load/unload user plugin", action = function()
      local p = "ux0:/data/lpp-showcase/plugin.suprx"
      if not System.doesFileExist(p) then
        Log.info("put a user plugin at " .. p .. " to try loadUserPlugin/unloadUserPlugin")
        Try("loadUserPlugin(missing) ->", System.loadUserPlugin, p)
        return
      end
      Dialog.confirm("Load " .. p .. " into this process?", function()
        local ok, id = Try("loadUserPlugin", System.loadUserPlugin, p)
        if ok and id >= 0 then Try("unloadUserPlugin", System.unloadUserPlugin, id) end
      end)
    end },
  { label = "Plugins: load/unload kernel plugin", color = C.err, action = function()
      local p = "ux0:/data/lpp-showcase/plugin.skprx"
      if not System.doesFileExist(p) then
        Log.info("put a kernel plugin at " .. p .. " to try loadKernelPlugin/unloadKernelPlugin")
        Try("loadKernelPlugin(missing) ->", System.loadKernelPlugin, p)
        return
      end
      Dialog.confirm("Load a KERNEL plugin? A bad one can crash the console.", function()
        local ok, id = Try("loadKernelPlugin", System.loadKernelPlugin, p)
        if ok and id >= 0 then Try("unloadKernelPlugin", System.unloadKernelPlugin, id) end
      end)
    end },
  { label = "Remount vs0: read-write and back", color = C.err, action = confirm(
      "Unmount vs0: (0x300) and remount it READ_WRITE, then back to READ_ONLY?\nThis is how file managers unlock system partitions.",
      function()
        Try("unmountPartition(0x300)", System.unmountPartition, 0x300)
        Try("mountPartition(0x300, READ_WRITE)", System.mountPartition, 0x300, READ_WRITE)
        Try("unmountPartition(0x300)", System.unmountPartition, 0x300)
        Try("mountPartition(0x300, READ_ONLY)", System.mountPartition, 0x300, READ_ONLY)
      end) },
  { label = "unmountMountpoint(addcont0:)", action = confirm(
      "Unmount the virtual addcont0: mountpoint (DLC) for this app?", function()
        Try("unmountMountpoint(addcont0:)", System.unmountMountpoint, "addcont0:")
      end) },
}

function S.enter()
  Log.info(System.isSafeMode() and "SAFE eboot: unsafe-only calls will raise errors (shown in red)."
    or "UNSAFE eboot: everything here is live. Read the dialogs.")
end

function S.update() S.list:update() end
function S.draw() S.draw_actions("Log") end

return S
