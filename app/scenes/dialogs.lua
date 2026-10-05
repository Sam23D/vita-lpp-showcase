-- 13. System dialogs: message boxes, progress dialog, on-screen keyboard.
local S = ActionScene({
  title = "Dialogs & Keyboard", modules = { "System", "Keyboard" },
  desc = "The OS common dialogs, drawn by the system over your frame. System.setMessage with every "
      .. "button layout, getMessageState (RUNNING/FINISHED/CANCELED), a progress-bar dialog driven by "
      .. "setMessageProgress and setMessageProgMsg and closed with closeMessage, and the IME keyboard: "
      .. "Keyboard.start in text, password, number and multiline modes, getState, getInput and clear.",
  hints = { { "enter", "Open" } },
  rows = 11,
})

S.last_text = "(nothing typed yet)"

local function kb(label, title, opts)
  return { label = label, action = function()
    Dialog.keyboard(title, opts.initial or "", function(text)
      if text then S.last_text = text; Log.ok("typed: " .. text) else Log.info("keyboard canceled") end
    end, opts)
  end }
end

local prog = nil
local function progress_demo()
  prog = Dialog.progress("Pretending to install 100 homebrews...")
  if prog then
    prog.pct, prog.t = 0, Timer.new()
    prog:set(0, "0 %")
  end
end

S.actions = {
  { label = "Message: OK", action = function() Dialog.message("Hello from System.setMessage!\nButtons: BUTTON_OK", BUTTON_OK, function(st) Log.info("state " .. st) end) end },
  { label = "Message: Yes / No", action = function() Dialog.confirm("Do you like the PS Vita?", function() Log.ok("Correct answer.") end) end },
  { label = "Message: OK / Cancel", action = function() Dialog.message("BUTTON_OK_CANCEL layout", BUTTON_OK_CANCEL, function(st) Log.info(st == CANCELED and "CANCELED" or "OK") end) end },
  { label = "Message: Cancel only", action = function() Dialog.message("BUTTON_CANCEL layout", BUTTON_CANCEL) end },
  { label = "Message: no buttons (auto-close 2 s)", action = function()
      if Dialog.message("BUTTON_NONE: closed from code with System.closeMessage()", BUTTON_NONE) then
        S.autoclose = Timer.new()
      end
    end },
  { label = "Progress-bar dialog", action = progress_demo },
  kb("Keyboard: text", "Type something", { initial = "Hello Vita" }),
  kb("Keyboard: password", "Secret", { mode = MODE_PASSWORD, length = 16 }),
  kb("Keyboard: number", "A number", { type = TYPE_NUMBER, length = 8 }),
  kb("Keyboard: extended number", "Decimal", { type = TYPE_EXT_NUMBER, length = 10 }),
  kb("Keyboard: Latin, multiline", "Notes", { type = TYPE_LATIN, option = OPT_MULTILINE, length = 256 }),
  kb("Keyboard: no autocap / assistance", "raw text", { option = OPT_NO_AUTOCAP + OPT_NO_ASSISTANCE }),
  { label = "Error: second message while open", action = function()
      Try("setMessage #1", System.setMessage, "first", false, BUTTON_OK)
      Try("setMessage #2", System.setMessage, "second", false, BUTTON_OK)
      Dialog.msg = { done = function() end }
    end },
}

function S.update() S.list:update() end

-- tick() runs every frame, even while a system dialog owns the input
function S.tick()
  if S.autoclose and Timer.getTime(S.autoclose) > 2000 then
    Timer.destroy(S.autoclose)
    S.autoclose = nil
    Try("System.closeMessage", System.closeMessage)
  end
  if prog and Dialog.msg then
    if Timer.getTime(prog.t) > 150 then
      prog.pct = prog.pct + 4
      Timer.reset(prog.t)
      if prog.pct > 100 then
        prog:close()
        Timer.destroy(prog.t)
        prog = nil
        Log.ok("progress finished, closeMessage()")
      else
        prog:set(prog.pct, prog.pct .. " %")
      end
    end
  elseif prog then
    Timer.destroy(prog.t)
    prog = nil
  end
end

function S.draw()
  S.draw_actions("Log")
  UI.panel(16, 440, 400, 52, "Last keyboard input")
  UI.text(28, 468, S.last_text:sub(1, 40), C.accent2, 16)
end

return S
