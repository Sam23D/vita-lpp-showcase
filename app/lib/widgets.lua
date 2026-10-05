-- Reusable widgets: a scrolling list, an on-screen log, and Try() which turns
-- lpp-vita errors (luaL_error) into log lines instead of killing the app.

Log = { lines = {}, max = 200 }

function Log.add(s, color)
  local lines = Log.lines
  lines[#lines + 1] = { s = tostring(s), c = color or C.text, t = APP.frame }
  if #lines > Log.max then table.remove(lines, 1) end
  if System.consolePrint then System.consolePrint("[lpp-showcase] " .. tostring(s)) end
end
function Log.ok(s) Log.add(s, C.ok) end
function Log.err(s) Log.add(s, C.err) end
function Log.info(s) Log.add(s, C.dim) end
function Log.clear() Log.lines = {} end

function Log.draw(x, y, w, h, title)
  UI.panel(x, y, w, h, title or "Log")
  local gap = 19
  local rows = math.floor((h - 34) / gap)
  local first = math.max(1, #Log.lines - rows + 1)
  for i = first, #Log.lines do
    local l = Log.lines[i]
    local s = l.s
    while #s > 1 and UI.tw(s, 14, UI.font.mono) > w - 16 do s = s:sub(1, -2) end
    UI.mono(x + 8, y + 32 + (i - first) * gap, s, l.c, 14)
  end
end

-- printable form of any value returned by a binding (handles become hex,
-- binary strings - e.g. Registry TYPE_BINARY - become a short hex dump)
function show_value(v)
  if type(v) == "number" and v > 0xFFFF then return UI.hex(v) end
  if type(v) == "string" and v:find("[%z\1-\8\14-\31\127-\255]") then
    local hex = {}
    for i = 1, math.min(8, #v) do hex[#hex + 1] = string.format("%02X", v:byte(i)) end
    return "<" .. #v .. " bytes: " .. table.concat(hex, " ") .. (#v > 8 and " ..." or "") .. ">"
  end
  if type(v) == "table" then return "table(" .. #v .. ")" end
  return tostring(v)
end

-- Try("Sound.open", function() return Sound.open(p) end) -> ok, result...
-- Errors raised by the native bindings come back as Lua errors and are logged.
function Try(label, fn, ...)
  local res = { pcall(fn, ...) }
  if res[1] then
    if res[2] == nil then Log.ok(label .. "  ok") else Log.ok(label .. "  -> " .. show_value(res[2])) end
  else
    local msg = tostring(res[2]):gsub("^.-:%d+: ", "")
    Log.err(label .. "  ! " .. msg)
  end
  return unpack(res)
end

-- Quiet variant: no log on success.
function TryQ(label, fn, ...)
  local res = { pcall(fn, ...) }
  if not res[1] then Log.err(label .. "  ! " .. tostring(res[2]):gsub("^.-:%d+: ", "")) end
  return unpack(res)
end

---------------------------------------------------------------- List widget
-- items: { {label=, sub=, color=, action=function(item) end}, ... }
List = {}
List.__index = List

function List.new(items, opts)
  opts = opts or {}
  return setmetatable({
    items = items, sel = 1, top = 1,
    x = opts.x or 16, y = opts.y or (UI.HEADER + 12),
    w = opts.w or 420, row = opts.row or 34,
    rows = opts.rows or 13, size = opts.size or 18,
  }, List)
end

function List:current() return self.items[self.sel] end

function List:update()
  local n = #self.items
  if n == 0 then return end
  if Input.rep("down") then self.sel = self.sel % n + 1 end
  if Input.rep("up") then self.sel = (self.sel - 2) % n + 1 end
  if Input.rep("right") then self.sel = math.min(n, self.sel + self.rows) end
  if Input.rep("left") then self.sel = math.max(1, self.sel - self.rows) end
  local ay = Input.axis(Input.ly)
  if ay ~= 0 and APP.frame % math.max(2, math.floor(10 - 8 * math.abs(ay))) == 0 then
    self.sel = math.max(1, math.min(n, self.sel + (ay > 0 and 1 or -1)))
  end
  if self.sel < self.top then self.top = self.sel end
  if self.sel >= self.top + self.rows then self.top = self.sel - self.rows + 1 end
  -- touch: tap a row to select, tap the selected row again to activate
  local p = Input.tap
  if p and Input.in_rect(p, self.x, self.y, self.w, self.rows * self.row) then
    local idx = self.top + math.floor((p.y - self.y) / self.row)
    if idx <= n then
      if idx == self.sel then return self:activate() end
      self.sel = idx
    end
  end
  if Input.enter() then return self:activate() end
end

function List:activate()
  local it = self.items[self.sel]
  if it and it.action then return it.action(it) end
end

function List:draw()
  local n = #self.items
  for i = self.top, math.min(n, self.top + self.rows - 1) do
    local it = self.items[i]
    local y = self.y + (i - self.top) * self.row
    if i == self.sel then
      UI.rect(self.x, y, self.w, self.row - 2, C.accent)
    elseif i % 2 == 0 then
      UI.rect(self.x, y, self.w, self.row - 2, C.panel)
    end
    UI.text(self.x + 10, y + (self.row - self.size) / 2 - 2, it.label, it.color or C.text, self.size)
    if it.sub then
      local s = tostring(it.sub)
      UI.text(self.x + self.w - 10 - UI.tw(s, 14), y + (self.row - 14) / 2 - 1, s,
        i == self.sel and C.white or C.dim, 14)
    end
  end
  if n > self.rows then -- scrollbar
    local h = self.rows * self.row
    UI.rect(self.x + self.w + 4, self.y, 4, h, C.panel)
    UI.rect(self.x + self.w + 4, self.y + h * (self.top - 1) / n, 4, h * self.rows / n, C.dim)
  end
end

---------------------------------------------------------------- System dialogs
-- Both the message dialog and the IME keyboard are drawn by the OS on top of
-- our frame (lpp-vita pumps them inside Graphics.termBlend), so the app keeps
-- rendering normally while they are open and just polls their state.
Dialog = { msg = nil, kb = nil }

function Dialog.busy() return Dialog.msg ~= nil or Dialog.kb ~= nil end

-- buttons: BUTTON_OK | BUTTON_YES_NO | BUTTON_OK_CANCEL | BUTTON_CANCEL | BUTTON_NONE
function Dialog.message(text, buttons, on_done)
  if Dialog.busy() then return false end
  local ok = Try("System.setMessage", System.setMessage, text, false, buttons or BUTTON_OK)
  if ok then Dialog.msg = { done = on_done } end
  return ok
end

function Dialog.confirm(text, on_yes, on_no)
  return Dialog.message(text, BUTTON_YES_NO, function(state)
    if state == CANCELED then
      Log.info("answered: No")
      if on_no then on_no() end
    else
      Log.info("answered: Yes")
      if on_yes then on_yes() end
    end
  end)
end

-- Progress-bar message; returns a handle with :set(pct, label) and :close()
function Dialog.progress(text)
  if Dialog.busy() then return nil end
  local ok = Try("System.setMessage(progress)", System.setMessage, text, true)
  if not ok then return nil end
  local h = {}
  Dialog.msg = { done = function() end, progress = h }
  function h.set(_, pct, label)
    System.setMessageProgress(math.max(0, math.min(100, math.floor(pct))))
    if label then System.setMessageProgMsg(label) end
  end
  function h.close() System.closeMessage() end
  return h
end

function Dialog.keyboard(title, text, on_done, opts)
  if Dialog.busy() then return false end
  opts = opts or {}
  local ok = Try("Keyboard.start", Keyboard.start, title, text or "", opts.length or 128,
    opts.type or TYPE_DEFAULT, opts.mode or MODE_TEXT, opts.option or 0)
  if ok then Dialog.kb = { done = on_done } end
  return ok
end

function Dialog.update()
  if Dialog.msg then
    local st = System.getMessageState()
    if st ~= RUNNING then
      local d = Dialog.msg
      Dialog.msg = nil
      if d.done then d.done(st) end
    end
  end
  if Dialog.kb then
    local st = Keyboard.getState()
    if st ~= RUNNING then
      local d = Dialog.kb
      Dialog.kb = nil
      local text = nil
      if st ~= CANCELED then text = Keyboard.getInput() end
      Keyboard.clear()
      if d.done then d.done(text) end
    end
  end
end

---------------------------------------------------------------- Actions panel
-- A list of named actions + the log next to it: the layout most scenes use.
function ActionScene(def)
  local s = def
  function s.enter_actions()
    s.list = List.new(s.actions, { w = def.list_w or 400, rows = def.rows or 13, row = def.row or 34 })
  end
  function s.draw_actions(log_title)
    s.list:draw()
    local lx = s.list.x + s.list.w + 20
    Log.draw(lx, UI.HEADER + 12, UI.W - lx - 12, def.log_h or (UI.H - UI.HEADER - UI.FOOTER - 24), log_title)
  end
  return s
end
