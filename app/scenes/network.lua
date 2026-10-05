-- 18. Network: Wi-Fi info, HTTP(S) via libcurl, async requests, FTP server.
local S = ActionScene({
  title = "Network & HTTP", modules = { "Network", "System", "Graphics" },
  desc = "Network.init, then Wi-Fi state, signal level, IP and MAC address. requestString and "
      .. "downloadFile with GET/POST/HEAD (HTTPS works; certificates are NOT verified), their async "
      .. "variants polled with getAsyncState/getAsyncResult, and the built-in FTP server (initFTP/termFTP) "
      .. "exposing app0:, ux0:, ur0:, music0: and photo0: to your PC. Needs Wi-Fi.",
  hints = { { "enter", "Run" } },
  rows = 10,
})

local UA = "lpp-vita-showcase/1.0"
local img = nil

local function need_net() return Net.ensure() end

local function show_json_field(body, field)
  local v = body and body:match('"' .. field .. '"%s*:%s*"([^"]*)"')
  if v then Log.info(string.format("  %s = %s", field, v)) end
end

S.actions = {
  { label = "Wi-Fi status", action = function()
      if not need_net() then return end
      Try("isWifiEnabled", Network.isWifiEnabled)
      Try("getWifiLevel (0-100)", Network.getWifiLevel)
      Try("getIPAddress", Network.getIPAddress)
      Try("getMacAddress", Network.getMacAddress)
    end },
  { label = "GET  httpbin.org/get", action = function()
      if not need_net() then return end
      local ok, body = Try("requestString", Network.requestString, "https://httpbin.org/get?from=vita", UA)
      if ok then Log.info("  " .. #body .. " bytes"); show_json_field(body, "origin"); show_json_field(body, "User-Agent") end
    end },
  { label = "POST JSON  httpbin.org/post", action = function()
      if not need_net() then return end
      -- lpp always sends "Content-Type: application/json" with its requests
      local ok, body = Try("requestString(POST)", Network.requestString, "https://httpbin.org/post", UA, POST_METHOD,
        '{"console":"PS Vita","api":"lpp"}')
      if ok then
        local echoed = body:match('"data"%s*:%s*"(.-)",')
        Log.info("  server saw: " .. tostring(echoed))
      end
    end },
  { label = "HEAD github.com", action = function()
      if not need_net() then return end
      local ok, body = Try("requestString(HEAD)", Network.requestString, "https://github.com", UA, HEAD_METHOD)
      if ok then Log.info("  body length " .. #body .. " (HEAD has no body)") end
    end },
  { label = "downloadFile banner.png + show", action = function()
      if not need_net() then return end
      local dst = data_path("banner.png")
      Try("downloadFile", Network.downloadFile, "https://raw.githubusercontent.com/Rinnegatamante/lpp-vita/master/banner.png", dst, UA)
      if System.doesFileExist(dst) and System.statFile(dst).size > 0 then
        Defer.free(Graphics.freeImage, img)
        local ok, h = Try("loadImage(banner.png)", Graphics.loadImage, dst)
        img = ok and h or nil
      end
    end },
  { label = "requestStringAsync (UTC time)", action = function()
      if not need_net() then return end
      Async.start("requestStringAsync", function()
        Network.requestStringAsync("https://worldtimeapi.org/api/timezone/Etc/UTC", UA)
      end, function(res)
        Log.info("  " .. #(res or "") .. " bytes")
        show_json_field(res, "datetime")
      end)
    end },
  { label = "downloadFileAsync (lpp README)", action = function()
      if not need_net() then return end
      local dst = data_path("README.md")
      Async.start("downloadFileAsync", function()
        Network.downloadFileAsync("https://raw.githubusercontent.com/Rinnegatamante/lpp-vita/master/README.md", dst, UA)
      end, function()
        local s = file_read(dst)
        Log.info("  saved " .. human_bytes(#s) .. ", first line: " .. (s:match("[^\n]+") or ""))
      end)
    end },
  { label = "Start / stop FTP server", action = function()
      if not need_net() then return end
      if Net.ftp then
        Try("termFTP", Network.termFTP)
        Net.ftp = nil
      else
        local ok, ip, port = Try("initFTP", Network.initFTP)
        if ok then
          Net.ftp = string.format("ftp://%s:%d", ip, port)
          Log.ok("  connect your PC to " .. Net.ftp)
        end
      end
    end },
  { label = "Error: second Network.init", action = function()
      need_net()
      Try("Network.init again", Network.init)
    end },
  { label = "Network.term", action = Net.shutdown },
}

function S.leave()
  Defer.free(Graphics.freeImage, img); img = nil
  -- keep FTP running across scenes if the user started it; it is stopped from here or on exit
end

function S.update() S.list:update() end

function S.draw()
  S.draw_actions("Log")
  -- free strip under the 10-row list: y 398..498
  if img then
    local s = math.min(1, 150 / Graphics.getImageWidth(img), 52 / Graphics.getImageHeight(img))
    Graphics.drawScaleImage(16, 400, img, s, s)
    UI.text(176, 404, "downloaded banner.png", C.dim, 13)
  end
  Async.draw_badge(176, 422)
  if Net.ftp then UI.text(16, 468, "FTP server: " .. Net.ftp, C.ok, 15) end
end

return S
