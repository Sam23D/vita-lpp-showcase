-- 8. Microphone: record to WAV, pause/resume, play it back.
local S = {
  title = "Microphone", modules = { "Mic", "Sound" },
  desc = "Mic.start(seconds, samplerate) records in the background (the samplerate must be a multiple "
      .. "of 16000 and at most 48000). Mic.isRecording, Mic.pause and Mic.resume control it, and "
      .. "Mic.stop(path) writes a mono 16-bit WAV, which we then play with the Sound module.",
  hints = { { "cross", "Record 5 s" }, { "square", "Pause/Resume" }, { "circle", "Stop & play" } },
}

local RATES = { 16000, 32000, 48000 }
local rate_i, rec, paused, timer, snd = 1, false, false, nil, nil
local OUT = "mic.wav"

local function stop_and_play()
  if not rec then return end
  rec, paused = false, false
  local path = data_path(OUT)
  Try("Mic.stop(" .. path .. ")", Mic.stop, path)
  if snd then Sound.close(snd); snd = nil end
  local ok, h = Try("Sound.open(mic.wav)", Sound.open, path)
  if ok then snd = h; Sound.play(snd, false) end
end

function S.enter() Audio.ensure() end
function S.leave()
  if rec then Mic.stop(data_path("discard.wav")); System.deleteFile(data_path("discard.wav")); rec = false end
  if snd then Sound.close(snd); snd = nil end
  if timer then Timer.destroy(timer); timer = nil end
end

function S.update()
  if Input.pressed("up") then rate_i = rate_i % #RATES + 1 end
  if Input.pressed("cross") and not rec then
    if snd then Sound.close(snd); snd = nil end
    rec = Try(string.format("Mic.start(5, %d)", RATES[rate_i]), Mic.start, 5, RATES[rate_i])
    if timer then Timer.destroy(timer) end
    timer = Timer.new()
  elseif Input.pressed("square") and rec then
    if paused then Try("Mic.resume", Mic.resume); Timer.resume(timer)
    else Try("Mic.pause", Mic.pause); Timer.pause(timer) end
    paused = not paused
  elseif Input.pressed("circle") then
    stop_and_play()
  end
  -- isRecording turns false when the requested duration is filled (or while paused)
  if rec and not paused and not Mic.isRecording() then
    Log.info("buffer full")
    stop_and_play()
  end
  if Input.pressed("down") then Try("Mic.start(1, 22050) - invalid rate", Mic.start, 1, 22050) end
end

function S.draw()
  UI.panel(40, 64, 420, 250, "Recorder")
  UI.text(60, 100, "sample rate (UP to change):", C.dim, 15)
  UI.bold(300, 98, RATES[rate_i] .. " Hz", C.accent2, 18)
  local state = rec and (paused and "PAUSED" or "RECORDING") or (snd and (Sound.isPlaying(snd) and "PLAYING BACK" or "done") or "idle")
  local col = rec and (paused and C.warn or C.err) or C.text
  if rec and not paused and math.floor(APP.frame / 20) % 2 == 0 then Graphics.fillCircle(72, 160, 10, C.err) end
  UI.bold(92, 148, state, col, 24)
  local ms = timer and Timer.getTime(timer) or 0
  UI.bar(60, 200, 380, 18, rec and (ms / 5000) or 0, C.err)
  UI.text(60, 226, string.format("%.1f / 5.0 s   Mic.isRecording() = %s", ms / 1000, tostring(Mic.isRecording())), C.text, 15)
  UI.text(60, 260, "DOWN: try an invalid rate (22050)", C.dim, 14)
  UI.text(60, 282, "output: " .. data_path(OUT), C.dim, 14)
  -- fake VU meter while recording, so there is something to look at
  for i = 0, 15 do
    local h = (rec and not paused) and (10 + 60 * math.abs(math.sin(APP.frame / 7 + i))) or 4
    UI.rect(500 + i * 26, 300 - h, 20, h, i > 12 and C.err or (i > 9 and C.warn or C.ok))
  end
  UI.text(500, 310, "(animation only - lpp exposes no live mic level)", C.dim, 13)
  Log.draw(40, 330, 880, 160)
end

return S
