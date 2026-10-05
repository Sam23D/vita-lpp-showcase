-- 19. Sockets: a TCP echo server on the Vita, a raw HTTP client, UDP.
local S = ActionScene({
  title = "Sockets", modules = { "Socket", "Network" },
  desc = "Raw BSD sockets. createServerSocket + accept make the Vita a TCP echo server (from your PC: "
      .. "echo hello | nc -q1 <vita-ip> 5000). connect, send and receive speak plain HTTP to "
      .. "example.com, plus a UDP datagram and close. Sockets are non-blocking: receive returns \"\" "
      .. "when nothing is waiting and accept returns nil when nobody is connecting.",
  hints = { { "enter", "Run" } },
})

local PORT = 5000
local server, clients = nil, {}

-- lpp resolves host names with gethostbyname and does not check the result, so a failed
-- DNS lookup (Wi-Fi off, bad name) crashes the interpreter. Always check Wi-Fi first.
local function online()
  if not Net.ensure() then return false end
  if not Network.isWifiEnabled() then Log.err("Wi-Fi is off"); return false end
  return true
end

S.actions = {
  { label = "Start / stop TCP echo server :" .. PORT, action = function()
      if server then
        for _, c in ipairs(clients) do Socket.close(c.sock) end
        clients = {}
        Try("Socket.close(server)", Socket.close, server)
        server = nil
      elseif online() then
        local ok, s = Try("createServerSocket(" .. PORT .. ")", Socket.createServerSocket, PORT)
        if ok then
          server = s
          Log.ok("  from your PC:  echo hello | nc -q1 " .. Network.getIPAddress() .. " " .. PORT)
        end
      end
    end },
  { label = "HTTP over raw TCP (example.com)", action = function()
      if not online() then return end
      local ok, s = Try("Socket.connect(example.com, 80)", Socket.connect, "example.com", 80)
      if not ok then return end
      local req = "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"
      Try("Socket.send " .. #req .. " bytes", Socket.send, s, req)
      -- non-blocking: poll receive until the data stops coming, at most 3 s
      local data, t, quiet = "", Timer.new(), nil
      while Timer.getTime(t) < 3000 do
        local chunk = Socket.receive(s, 4096)
        if chunk ~= "" then
          data, quiet = data .. chunk, Timer.getTime(t)
        elseif quiet and Timer.getTime(t) - quiet > 400 then
          break
        end
      end
      Timer.destroy(t)
      Socket.close(s)
      Log.info("  received " .. #data .. " bytes")
      Log.info("  " .. (data:match("^[^\r\n]+") or "(nothing)"))
      Log.info("  <title>" .. (data:match("<title>(.-)</title>") or "?") .. "</title>")
    end },
  { label = "UDP: datagram to one.one.one.one:53", action = function()
      if not online() then return end
      local ok, s = Try("Socket.connect(UDP_SOCKET)", Socket.connect, "one.one.one.one", 53, UDP_SOCKET)
      if ok then
        -- lpp does not connect() UDP sockets, so send has no destination: expect a negative result
        Try("Socket.send(udp)", Socket.send, s, "hello")
        Try("Socket.close(udp)", Socket.close, s)
      end
    end },
  { label = "Error: receive on server socket", action = function()
      if not server then Log.err("start the server first"); return end
      Try("Socket.receive(server)", Socket.receive, server, 16)
    end },
  { label = "Error: send on server socket", action = function()
      if not server then Log.err("start the server first"); return end
      Try("Socket.send(server)", Socket.send, server, "x")
    end },
}

-- tick() runs every frame (even while dialogs are open) and serves the clients.
-- One request per connection: read what the client sent, echo it, close. lpp only puts the
-- LISTENING socket in non-blocking mode, so on some firmwares receive() on an accepted socket
-- blocks until data arrives; one-shot clients like `echo hi | nc` make that wait tiny.
function S.tick()
  if not server then return end
  local c = Socket.accept(server)
  if c then
    clients[#clients + 1] = { sock = c, age = 0 }
    Log.ok("client connected")
  end
  for i = #clients, 1, -1 do
    local cl = clients[i]
    cl.age = cl.age + 1
    local data = Socket.receive(cl.sock, 1024)
    if data ~= "" then
      Log.add("<< " .. data:gsub("[\r\n]+$", ""), C.accent2)
      Socket.send(cl.sock, "PS Vita says: " .. data)
    end
    if data ~= "" or cl.age > 300 then
      Socket.close(cl.sock)
      table.remove(clients, i)
    end
  end
end

function S.leave()
  for _, c in ipairs(clients) do Socket.close(c.sock) end
  clients = {}
  if server then Socket.close(server); server = nil end
end

function S.update() S.list:update() end

function S.draw()
  S.draw_actions("Log")
  UI.panel(16, 420, 400, 72, "Echo server")
  if server then
    UI.text(28, 448, "listening on " .. Network.getIPAddress() .. ":" .. PORT, C.ok, 16)
    UI.text(28, 468, #clients .. " client(s) connected", C.dim, 14)
  else
    UI.text(28, 450, "stopped", C.dim, 16)
  end
end

return S
