-- 12. Gui: the Dear ImGui binding, with touch and button navigation.
local S = {
  title = "Gui (ImGui)", modules = { "Gui" },
  desc = "lpp-vita embeds Dear ImGui: windows, a menu bar with menus and items, text (plain, coloured, "
      .. "disabled, wrapped), buttons, checkboxes, radios, 1-4 component float and int sliders, a combo "
      .. "box, list box, colour picker, progress bar, tooltips, images, manual layout, themes and the "
      .. "input modes (front touch, rear pad, buttons). Gui.init is required once per session.",
  hints = { { "touch", "Use" }, { "dpad", "Navigate" } },
  back_button = "select",
}

local inited = false
local st = {
  theme = DARK_THEME, check = true, radio = 1, f1 = 0.5, f2 = { 0.2, 0.8 }, f3 = { 1, 2, 3 }, f4 = { 0.1, 0.2, 0.3, 0.4 },
  i1 = 42, i2 = { 3, 7 }, i3 = { 1, 2, 3 }, i4 = { 10, 20, 30, 40 },
  combo = 1, listbox = 2, color = Color.new(95, 139, 255), clicks = 0,
  touch = true, rear = false, buttons = true, indirect = true, show_about = false,
}
local FRUITS = { "Apple", "Banana", "Cherry", "Dragonfruit", "Elderberry" }
local CONSOLES = { "PS Vita 1000", "PS Vita 2000", "PS TV", "Devkit", "Testkit", "PSP" }
local logo

function S.enter()
  if not inited then
    inited = Try("Gui.init", Gui.init)
  end
  Gui.setTheme(st.theme)
  Gui.setInputMode(st.touch, st.rear, st.buttons, st.indirect)
  logo = Graphics.loadImage(asset_path("img/hello.png"))
  local w, h = Gui.getTextSize("Hello ImGui")
  Log.info(string.format("Gui.getTextSize('Hello ImGui') = %.0f x %.0f", w, h))
end

function S.leave()
  Defer.free(Graphics.freeImage, logo); logo = nil
end

local function menubar()
  if Gui.initMainMenubar() then
    if Gui.initMenu("App") then
      if Gui.drawMenuItem("About", st.show_about) then st.show_about = not st.show_about end
      if Gui.drawMenuItem("Back to showcase  (SELECT)") then S.want_back = true end
      Gui.termMenu()
    end
    if Gui.initMenu("Theme") then
      for _, t in ipairs({ { "Dark", DARK_THEME }, { "Light", LIGHT_THEME }, { "Classic", CLASSIC_THEME } }) do
        if Gui.drawMenuItem(t[1], st.theme == t[2]) then st.theme = t[2]; Gui.setTheme(t[2]) end
      end
      Gui.termMenu()
    end
    if Gui.initMenu("Input") then
      local changed = false
      if Gui.drawMenuItem("Front touch", st.touch) then st.touch = not st.touch; changed = true end
      if Gui.drawMenuItem("Rear touchpad", st.rear) then st.rear = not st.rear; changed = true end
      if Gui.drawMenuItem("Buttons", st.buttons, st.touch or st.rear) then st.buttons = not st.buttons; changed = true end
      if Gui.drawMenuItem("Indirect front touch", st.indirect) then st.indirect = not st.indirect; changed = true end
      if changed then Gui.setInputMode(st.touch, st.rear, st.buttons, st.indirect) end
      Gui.termMenu()
    end
    if Gui.initMenu("Disabled menu", false) then Gui.termMenu() end
    Gui.termMainMenubar()
  end
end

local function widgets()
  Gui.setWindowPos(10, 30, SET_ONCE)
  Gui.setWindowSize(470, 500, SET_ONCE)
  Gui.initWindow("Widgets", FLAG_NO_COLLAPSE)
  Gui.drawText("Hello ImGui, from Lua!")
  Gui.drawText("Coloured text via Gui.drawText(label, color)", st.color)
  Gui.drawDisabledText("drawDisabledText: greyed out")
  Gui.drawWrappedText("drawWrappedText wraps long strings to the window width, which is handy for help text inside panels.")
  Gui.drawSeparator()
  if Gui.drawButton("Click me") then st.clicks = st.clicks + 1 end
  Gui.drawTooltip("drawTooltip: shown while hovering the previous widget")
  Gui.resetLine()
  if Gui.drawSmallButton("small") then st.clicks = st.clicks + 1 end
  Gui.resetLine()
  Gui.drawText("clicks: " .. st.clicks)
  if Gui.drawButton("Wide button", 300, 34) then st.clicks = st.clicks + 10 end
  st.check = Gui.drawCheckbox("Checkbox", st.check)
  for i = 1, 3 do
    if Gui.drawRadioButton("Radio " .. i, st.radio == i) then st.radio = i end
    if i < 3 then Gui.resetLine() end
  end
  Gui.drawSeparator()
  st.f1 = Gui.drawSlider("float", 0, 1, st.f1)
  st.f2[1], st.f2[2] = Gui.drawSlider("float2", 0, 1, st.f2[1], st.f2[2])
  st.f3[1], st.f3[2], st.f3[3] = Gui.drawSlider("float3", 0, 5, st.f3[1], st.f3[2], st.f3[3])
  st.f4[1], st.f4[2], st.f4[3], st.f4[4] = Gui.drawSlider("float4", 0, 1, st.f4[1], st.f4[2], st.f4[3], st.f4[4])
  st.i1 = Gui.drawIntSlider("int", 0, 100, st.i1)
  st.i2[1], st.i2[2] = Gui.drawIntSlider("int2", 0, 10, st.i2[1], st.i2[2])
  st.i3[1], st.i3[2], st.i3[3] = Gui.drawIntSlider("int3", 0, 10, st.i3[1], st.i3[2], st.i3[3])
  st.i4[1], st.i4[2], st.i4[3], st.i4[4] = Gui.drawIntSlider("int4", 0, 50, st.i4[1], st.i4[2], st.i4[3], st.i4[4])
  Gui.drawProgressbar(st.f1)
  Gui.drawProgressbar(st.i1 / 100, 200, 14)
  Gui.termWindow()
end

local function pickers()
  Gui.setWindowPos(490, 30, SET_ONCE)
  Gui.setWindowSize(460, 500, SET_ONCE)
  Gui.initWindow("Pickers & images", FLAG_NO_COLLAPSE)
  Gui.setWidgetWidth(220)
  st.combo = Gui.drawComboBox("Combo box", st.combo, FRUITS)      -- 1-based index
  st.listbox = Gui.drawListBox("List box", st.listbox, CONSOLES)
  Gui.resetWidgetWidth()
  Gui.drawText("picked: " .. FRUITS[st.combo] .. " / " .. CONSOLES[st.listbox])
  Gui.setWidgetWidth(200)
  -- lpp bug: without the alpha flag the returned alpha byte is uninitialised, so re-pack it opaque
  local c = Gui.drawColorPicker("Colour", st.color)
  st.color = Color.new(Color.getR(c), Color.getG(c), Color.getB(c), 255)
  Gui.resetWidgetWidth()
  Gui.drawImage(logo)                                              -- natural size
  Gui.drawImage(logo, 128, 48)                                     -- scaled
  Gui.drawImage(logo, 96, 96, 80, 0, 96, 96)                       -- sub-rectangle
  Gui.drawImage(logo, 96, 96, 80, 0, 96, 96, Color.new(255, 160, 160)) -- tinted
  Gui.setWidgetPos(330, 470)
  Gui.drawSmallButton("setWidgetPos")
  Gui.termWindow()
end

local function about()
  if not st.show_about then return end
  Gui.setWindowPos(300, 180, SET_ALWAYS)
  Gui.setWindowSize(360, 140, SET_ALWAYS)
  Gui.initWindow("About", FLAG_NO_MOVE + FLAG_NO_RESIZE + FLAG_NO_SCROLLBAR)
  Gui.drawWrappedText("lpp-vita showcase. Dear ImGui driven from Lua via Gui.*")
  if Gui.drawButton("Close") then st.show_about = false end
  Gui.termWindow()
end

function S.update()
  if S.want_back then S.want_back = false; APP.pop() end
end

function S.frame()
  Graphics.initBlend()
  Screen.clear(C.bg)
  Gui.initBlend()
  menubar()
  widgets()
  pickers()
  about()
  Gui.termBlend()
  Graphics.termBlend()
end

return S
