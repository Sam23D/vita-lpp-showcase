-- 15. Files: the I/O API, plus a small file browser.
local S = ActionScene({
  title = "Files", modules = { "System" },
  desc = "File I/O on any mounted device: openFile with FREAD/FWRITE/FCREATE/FRDWR, readFile, writeFile, "
      .. "seekFile (SET/CUR/END), sizeFile, closeFile, statFile, statOpenedFile, doesFileExist, "
      .. "doesDirExist, rename, copyFile, deleteFile, createDirectory, listDirectory, deleteDirectory and "
      .. "free/total space. The safe eboot can only open files under ux0:/data and app0:/.",
  hints = { { "enter", "Run" }, { "square", "Browse" } },
  rows = 12,
})

local DIR = APP.data .. "files/"
local NOTE = DIR .. "note.txt"

local function stat_str(st)
  if not st then return "nil" end
  local m = st.mod_time
  return string.format("%s, %s, modified %04d-%02d-%02d %02d:%02d", human_bytes(st.size),
    st.directory and "dir" or "file", m.year, m.month, m.day, m.hour, m.minute)
end

S.actions = {
  { label = "createDirectory files/", action = function()
      Try("doesDirExist", System.doesDirExist, DIR)
      Try("createDirectory", System.createDirectory, DIR)
      Try("doesDirExist", System.doesDirExist, DIR)
    end },
  { label = "Write note.txt (FCREATE)", action = function()
      local text = "Hello from lpp-vita!\nWritten at frame " .. APP.frame .. "\n"
      -- FCREATE is O_CREAT|O_WRONLY with no O_TRUNC: delete first or old bytes remain at the end
      if System.doesFileExist(NOTE) then System.deleteFile(NOTE) end
      local ok, h = Try("openFile(FCREATE)", System.openFile, NOTE, FCREATE)
      if ok then
        Try("writeFile " .. #text .. " bytes", System.writeFile, h, text, #text)
        Try("closeFile", System.closeFile, h)
      end
    end },
  { label = "Append a line (FRDWR + seek END)", action = function()
      local ok, h = Try("openFile(FRDWR)", System.openFile, NOTE, FRDWR)
      if not ok then return end
      Try("seekFile(0, END)", System.seekFile, h, 0, END)
      local line = "appended at frame " .. APP.frame .. "\n"
      System.writeFile(h, line, #line)
      Log.info("statOpenedFile: " .. stat_str(System.statOpenedFile(h)))
      System.closeFile(h)
    end },
  { label = "Read note.txt (FREAD)", action = function()
      local ok, h = Try("openFile(FREAD)", System.openFile, NOTE, FREAD)
      if not ok then return end
      local n = System.sizeFile(h)
      Log.info("sizeFile = " .. n)
      local s = System.readFile(h, n)
      for line in s:gmatch("[^\n]+") do Log.add("  | " .. line, C.accent2) end
      System.seekFile(h, 6, SET)
      Log.info("seek(6, SET) + read 4: '" .. System.readFile(h, 4) .. "'")
      System.seekFile(h, 1, CUR)
      Log.info("seek(1, CUR) + read 4: '" .. System.readFile(h, 4) .. "'")
      System.closeFile(h)
    end },
  { label = "statFile note.txt", action = function()
      local ok, st = Try("statFile", System.statFile, NOTE)
      if ok then Log.info(stat_str(st)) end
    end },
  { label = "copyFile -> copy.txt", action = function() Try("copyFile", System.copyFile, NOTE, DIR .. "copy.txt") end },
  { label = "rename copy.txt -> renamed.txt", action = function() Try("rename", System.rename, DIR .. "copy.txt", DIR .. "renamed.txt") end },
  { label = "listDirectory files/", action = function()
      local ok, list = Try("listDirectory", System.listDirectory, DIR)
      if ok and list then
        for _, e in ipairs(list) do Log.info(string.format("  %s%s  %s", e.name, e.directory and "/" or "", human_bytes(e.size))) end
      end
    end },
  { label = "Delete files + deleteDirectory", action = function()
      local list = System.listDirectory(DIR) or {}
      for _, e in ipairs(list) do Try("deleteFile " .. e.name, System.deleteFile, DIR .. e.name) end
      Try("deleteDirectory (must be empty)", System.deleteDirectory, DIR)
      Log.info("doesDirExist -> " .. tostring(System.doesDirExist(DIR)))
    end },
  { label = "Free / total space", action = function()
      for _, dev in ipairs({ "ux0:", "ur0:", "uma0:", "imc0:" }) do
        local okf, free = TryQ("getFreeSpace", System.getFreeSpace, dev)
        local okt, total = TryQ("getTotalSpace", System.getTotalSpace, dev)
        if okf and okt and total and total > 0 then
          Log.info(string.format("%-5s %s free of %s", dev, human_bytes(free), human_bytes(total)))
        end
      end
    end },
  { label = "Error: open a missing file", action = function() Try("openFile(missing)", System.openFile, DIR .. "nope.bin", FREAD) end },
  { label = "Read outside ux0:/data (unsafe only)", action = function()
      Try("listDirectory ur0:/", System.listDirectory, "ur0:/")
      Try("openFile vs0:/vsh/etc/index_layout.ini", System.openFile, "vs0:/vsh/etc/index_layout.ini", FREAD)
    end },
}

---------------------------------------------------------------- browser
local browsing, path, entries, bsel = false, "ux0:/data/", {}, 1
local function refresh()
  entries = System.listDirectory(path) or {}
  table.sort(entries, function(a, b)
    if a.directory ~= b.directory then return a.directory end
    return a.name:lower() < b.name:lower()
  end)
  if path:match("^%w+:/.+/$") then table.insert(entries, 1, { name = "..", directory = true, size = 0 }) end
  bsel = 1
end

function S.update()
  if Input.pressed("square") then
    browsing = not browsing
    if browsing then refresh() end
  end
  if not browsing then return S.list:update() end
  local n = #entries
  if n > 0 then
    if Input.rep("down") then bsel = bsel % n + 1 end
    if Input.rep("up") then bsel = (bsel - 2) % n + 1 end
  end
  if Input.enter() and entries[bsel] then
    local e = entries[bsel]
    if e.name == ".." then path = path:gsub("[^/]+/$", "")
    elseif e.directory then path = path .. e.name .. "/"
    else Log.info(e.name .. ": " .. stat_str(System.statFile(path .. e.name))) end
    if e.directory then refresh() end
  end
end

function S.draw()
  if not browsing then return S.draw_actions("Log") end
  UI.panel(16, 56, 540, 436, path)
  local top = math.max(1, bsel - 8)
  for i = top, math.min(#entries, top + 16) do
    local e = entries[i]
    local y = 86 + (i - top) * 24
    if i == bsel then UI.rect(18, y - 2, 536, 22, C.accent) end
    UI.text(28, y, (e.directory and "[" .. e.name .. "]") or e.name, e.directory and C.accent2 or C.text, 15)
    if not e.directory then UI.text(460, y, human_bytes(e.size), C.dim, 14) end
  end
  if #entries == 0 then UI.text(28, 90, "(empty or not readable)", C.dim, 15) end
  Log.draw(572, 56, 372, 436)
end

return S
