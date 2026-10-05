-- 9. Video: hardware MP4 playback via sceAvPlayer, subtitles, trick play.
local S = {
  title = "Video", modules = { "Video" },
  desc = "Video.init + Video.open plays H.264/AAC MP4 through the hardware decoder. getOutput returns "
      .. "the current frame as an image you can draw at any scale. Also covers openSubs/getSubs "
      .. "(.vtt and .srt), getTime, jumpToTime, setPlayMode (2x-32x fast-forward), "
      .. "pause/resume/isPlaying, setVolume/getVolume, closeSubs, close and term.",
  hints = { { "circle", "Pause" }, { "left", "" }, { "right", "-/+10s" }, { "l", "" }, { "r", "Speed" },
            { "square", "Subs" }, { "up", "" }, { "down", "Vol" } },
}

local MODES = { NORMAL_MODE, FAST_FORWARD_2X_MODE, FAST_FORWARD_4X_MODE, FAST_FORWARD_8X_MODE,
                FAST_FORWARD_16X_MODE, FAST_FORWARD_32X_MODE }
local mode_i, srt, open = 1, false, false

local function load_subs()
  Video.closeSubs()
  local f = srt and "video/clip.srt" or "video/clip.vtt"
  Try("Video.openSubs(" .. f .. ")", Video.openSubs, asset_path(f))
end

function S.enter()
  Try("Video.init", Video.init)
  open = Try("Video.open(clip.mp4, loop)", Video.open, asset_path("video/clip.mp4"), true)
  if open then load_subs() end
  Video.setVolume(24000)
end

function S.leave()
  if open then
    Video.closeSubs()
    Try("Video.close", Video.close)
    open = false
  end
  Try("Video.term", Video.term)
end

function S.update()
  if not open then return end
  if Input.pressed("circle") then
    if Video.isPlaying() then Try("Video.pause", Video.pause) else Try("Video.resume", Video.resume) end
  end
  if Input.pressed("r") then mode_i = math.min(#MODES, mode_i + 1); Try("setPlayMode x" .. MODES[mode_i] / 100, Video.setPlayMode, MODES[mode_i]) end
  if Input.pressed("l") then mode_i = math.max(1, mode_i - 1); Try("setPlayMode x" .. MODES[mode_i] / 100, Video.setPlayMode, MODES[mode_i]) end
  if Input.pressed("right") then Try("jumpToTime(+10s)", Video.jumpToTime, Video.getTime() + 10000) end
  if Input.pressed("left") then Try("jumpToTime(-10s)", Video.jumpToTime, math.max(0, Video.getTime() - 10000)) end
  if Input.pressed("square") then srt = not srt; load_subs() end
  if Input.held("up") then Video.setVolume(math.min(32767, Video.getVolume() + 300)) end
  if Input.held("down") then Video.setVolume(math.max(0, Video.getVolume() - 300)) end
end

function S.draw()
  if not open then Log.draw(40, 70, 880, 400); return end
  local frame = Video.getOutput()
  if frame ~= 0 then
    local w, h = Graphics.getImageWidth(frame), Graphics.getImageHeight(frame)
    Graphics.setImageFilters(frame, FILTER_LINEAR, FILTER_LINEAR)
    local s = math.min(640 / w, 362 / h)
    Graphics.drawScaleImage(16, 56, frame, s, s)
    local sub = Video.getSubs()
    if sub and sub ~= "" then
      local tw = UI.tw(sub, 20, UI.font.bold)
      UI.rect(16 + 320 - tw / 2 - 8, 380, tw + 16, 30, C.shade)
      UI.center(16 + 320, 384, sub, C.white, 20, UI.font.bold)
    end
  end
  local ms = Video.getTime()
  UI.bar(16, 426, 640, 10, (ms % 14000) / 14000, C.accent)
  UI.panel(672, 56, 272, 184, "Player")
  UI.kv(684, 88, {
    { "isPlaying", tostring(Video.isPlaying()), Video.isPlaying() and C.ok or C.warn },
    { "getTime", string.format("%.1f s", ms / 1000) },
    { "speed", "x" .. MODES[mode_i] / 100 },
    { "volume", math.floor(Video.getVolume() * 100 / 32767) .. " %" },
    { "subtitles", srt and ".srt" or ".vtt" },
    { "frame", frame ~= 0 and string.format("%dx%d", Graphics.getImageWidth(frame), Graphics.getImageHeight(frame)) or "-" },
  }, 100, 15, 24)
  Log.draw(672, 250, 272, 246)
end

return S
