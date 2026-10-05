-- 7. Sound: every decoder lpp-vita ships, multiple channels, metadata, shutter sounds.
local S = ActionScene({
  title = "Sound", modules = { "Sound" },
  desc = "Sound.init starts 8 audio channels. Plays OGG Vorbis, MP3, WAV, AIFF and MIDI (FM synth), "
      .. "several at once, with per-track pause/resume/isPlaying, setVolume/getVolume (0-32767), "
      .. "getTitle/getAuthor from ID3, Vorbis comments and WAV LIST chunks, the system camera "
      .. "shutter sounds, and a clean Sound.term + re-init. FLAC is NOT supported by lpp-vita.",
  hints = { { "enter", "Run" }, { "l", "Vol-" }, { "r", "Vol+" } },
  list_w = 380, rows = 10,
})

local FILES = {
  { "melody.ogg", "OGG Vorbis" }, { "melody.mp3", "MP3 (ID3v2.3)" }, { "melody.wav", "WAV PCM16" },
  { "melody.aif", "AIFF" }, { "melody.mid", "MIDI (FM synth)" },
}
local tracks = {} -- filename -> handle

local function handle(f)
  if tracks[f] then return tracks[f] end
  local ok, h = Try("Sound.open(" .. f .. ")", Sound.open, asset_path("audio/" .. f))
  if not ok then return nil end
  tracks[f] = h
  Log.info(string.format("  title=%q  author=%q", Sound.getTitle(h), Sound.getAuthor(h)))
  return h
end

local function toggle(f)
  local h = handle(f)
  if not h then return end
  if S.started[f] then
    if Sound.isPlaying(h) then Try("Sound.pause", Sound.pause, h) else Try("Sound.resume", Sound.resume, h) end
  else
    Try("Sound.play(h, true)", Sound.play, h, true)  -- true = loop
    S.started[f] = true
  end
end

local function close_all()
  for f, h in pairs(tracks) do
    Try("Sound.close(" .. f .. ")", Sound.close, h)
  end
  tracks, S.started = {}, {}
end

S.started = {}
S.actions = {}
for _, f in ipairs(FILES) do
  S.actions[#S.actions + 1] = { label = "Play / pause " .. f[2], sub = f[1], file = f[1], action = function(it) toggle(it.file) end }
end
for _, a in ipairs({
  { "Shutter: image capture", function() Try("playShutter(IMAGE_CAPTURE)", Sound.playShutter, IMAGE_CAPTURE) end },
  { "Shutter: video start", function() Try("playShutter(VIDEO_CAPTURE_START)", Sound.playShutter, VIDEO_CAPTURE_START) end },
  { "Shutter: video end", function() Try("playShutter(VIDEO_CAPTURE_END)", Sound.playShutter, VIDEO_CAPTURE_END) end },
  { "Close all tracks", close_all },
  { "Sound.term + Sound.init", function()
      close_all()
      Try("Sound.term", Sound.term)
      Audio.ready = false
      Audio.ensure()
    end },
  { "Try FLAC (unsupported)", function()
      local p = data_path("fake.flac")
      file_write(p, "fLaC\0\0\0\34")
      Try("Sound.open(fake.flac)", Sound.open, p)
      System.deleteFile(p)
    end },
}) do
  S.actions[#S.actions + 1] = { label = a[1], action = a[2] }
end

function S.enter() Audio.ensure() end
function S.leave() close_all() end

function S.update()
  S.list:update()
  local it = S.list:current()
  local h = it.file and tracks[it.file]
  if h then
    local v = Sound.getVolume(h)
    if Input.held("l") then Sound.setVolume(h, math.max(0, v - 400)) end
    if Input.held("r") then Sound.setVolume(h, math.min(32767, v + 400)) end
  end
end

function S.draw()
  -- per-track status + volume bars
  for i, it in ipairs(S.actions) do
    if it.file then
      local h = tracks[it.file]
      it.sub = (not h) and it.file or ((Sound.isPlaying(h) and "> " or "|| ") ..
        math.floor(Sound.getVolume(h) * 100 / 32767) .. "%")
    end
  end
  S.draw_actions("Log")
  local x = S.list.x
  UI.panel(x, 400, S.list.w, 90, "Open handles")
  local n = 0
  for f, h in pairs(tracks) do
    UI.bar(x + 10 + n * 72, 440, 60, 10, Sound.getVolume(h) / 32767, Sound.isPlaying(h) and C.ok or C.dim)
    UI.text(x + 10 + n * 72, 456, f:match("%.(%w+)$"), C.dim, 13)
    n = n + 1
  end
  if n == 0 then UI.text(x + 10, 440, "none", C.dim, 14) end
end

return S
