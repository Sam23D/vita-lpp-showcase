-- Shared subsystems that several scenes use. lpp-vita keeps one global state per
-- subsystem, so init/term must be coordinated app-wide, not per scene.

---------------------------------------------------------------- Audio
-- Sound.init starts the 8 audio-channel threads AND the microphone thread, so
-- Mic needs it too. Calling it twice is harmless (guarded in C), but Sound.term
-- would kill every track, so the app inits once and never terms mid-session.
Audio = { ready = false }
function Audio.ensure()
  if not Audio.ready then
    Audio.ready = Try("Sound.init", Sound.init)
  end
  return Audio.ready
end

---------------------------------------------------------------- Network
-- Network.init raises "Network is already inited" on a second call, and HTTP,
-- FTP and sockets all share it.
Net = { up = false, ftp = nil }
function Net.ensure()
  if not Net.up then
    Net.up = Try("Network.init", Network.init)
  end
  return Net.up
end

function Net.shutdown()
  if Net.ftp then TryQ("Network.termFTP", Network.termFTP); Net.ftp = nil end
  if Net.up then Try("Network.term", Network.term); Net.up = false end
end

---------------------------------------------------------------- Async
-- lpp-vita runs at most ONE async task at a time (ASYNC_TASKS_MAX = 1), shared
-- by Graphics.loadImageAsync, Network.*Async and System.extract*Async.
-- System.getAsyncState(): 0 running, 1 finished, -1 failed to start.
-- System.getAsyncResult(): string for requestStringAsync / loadImageAsync.
Async = { job = nil }

function Async.busy() return Async.job ~= nil end

function Async.start(label, starter, on_done)
  if Async.job then
    Log.err(label .. "  ! another async task is running (" .. Async.job.label .. ")")
    return false
  end
  local ok = Try(label, starter)
  if not ok then return false end
  Async.job = { label = label, on_done = on_done, t = Timer.new() }
  return true
end

function Async.update()
  local job = Async.job
  if not job then return end
  local st = System.getAsyncState()
  if st ~= 0 then
    Async.job = nil
    local ms = Timer.getTime(job.t)
    Timer.destroy(job.t)
    if st == 1 then
      local res = System.getAsyncResult()
      Log.ok(string.format("%s finished in %d ms", job.label, ms))
      if job.on_done then job.on_done(res) end
    else
      Log.err(job.label .. " failed (state " .. tostring(st) .. ")")
    end
  end
end

function Async.draw_badge(x, y)
  if not Async.job then return end
  local t = Timer.getTime(Async.job.t)
  UI.rect(x, y, 260, 24, C.panel2)
  local dots = string.rep(".", math.floor(t / 300) % 4)
  UI.text(x + 8, y + 3, "async: " .. Async.job.label .. dots, C.accent2, 14)
end

---------------------------------------------------------------- Paths
function data_path(name) return APP.data .. name end
function asset_path(name) return APP.root .. "assets/" .. name end

function file_write(path, s)
  local h = System.openFile(path, FCREATE)
  System.writeFile(h, s, #s)
  System.closeFile(h)
end

function file_read(path)
  local h = System.openFile(path, FREAD)
  local s = System.readFile(h, System.sizeFile(h))
  System.closeFile(h)
  return s
end

function human_bytes(n)
  if not n then return "?" end
  local units, i = { "B", "KiB", "MiB", "GiB" }, 1
  while n >= 1024 and i < #units do n = n / 1024; i = i + 1 end
  return string.format(i == 1 and "%d %s" or "%.1f %s", n, units[i])
end


-- Deferred frees: vita2d frees textures immediately, but the GPU may still be
-- drawing the previous frame with them. Real hardware usually survives that;
-- Vita3K crashes. Queue the free and run it 3 frames later (after Screen.flip).
Defer = { q = {} }
function Defer.free(fn, handle)
  if handle then Defer.q[#Defer.q + 1] = { fn = fn, h = handle, n = 3 } end
end
function Defer.update()
  local keep = {}
  for _, e in ipairs(Defer.q) do
    e.n = e.n - 1
    if e.n <= 0 then pcall(e.fn, e.h) else keep[#keep + 1] = e end
  end
  Defer.q = keep
end
