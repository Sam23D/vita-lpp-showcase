-- 16. Archives & package files: ZIP, PBP, SFO.
local S = ActionScene({
  title = "ZIP / PBP / SFO", modules = { "System" },
  desc = "Built-in archive support: compressZip and addToZip (with compression level 0-9), extractZip, "
      .. "extractFromZip, and their async versions extractZipAsync and extractFromZipAsync polled with "
      .. "getAsyncState. Also extractPbp to unpack a PSP EBOOT.PBP and extractSfo to read PARAM.SFO "
      .. "metadata from a Vita app or from inside a PBP.",
  hints = { { "enter", "Run" } },
})

local OUT = APP.data .. "zip/"
local function ensure() if not System.doesDirExist(OUT) then System.createDirectory(OUT) end end
local function show_sfo(t)
  if not t then return end
  for _, k in ipairs({ "title", "short_title", "titleid", "version", "category" }) do
    if t[k] then Log.info(string.format("  %-11s %s", k, t[k])) end
  end
end
local function ls(dir, indent)
  indent = indent or "  "
  for _, e in ipairs(System.listDirectory(dir) or {}) do
    Log.info(indent .. e.name .. (e.directory and "/" or "  " .. human_bytes(e.size)))
    if e.directory then ls(dir .. e.name .. "/", indent .. "  ") end
  end
end

S.actions = {
  { label = "extractSfo(app0:/sce_sys/param.sfo)", action = function()
      local ok, t = Try("extractSfo", System.extractSfo, "app0:/sce_sys/param.sfo")
      if ok then show_sfo(t) end
    end },
  { label = "extractZip bundle.zip", action = function()
      ensure()
      Try("extractZip", System.extractZip, asset_path("sample/bundle.zip"), OUT .. "bundle")
      ls(OUT .. "bundle/")
    end },
  { label = "extractFromZip readme.txt", action = function()
      ensure()
      local dst = OUT .. "readme_only.txt"
      Try("extractFromZip", System.extractFromZip, asset_path("sample/bundle.zip"), "readme.txt", dst)
      if System.doesFileExist(dst) then Log.add("  | " .. file_read(dst):match("[^\n]+"), C.accent2) end
    end },
  { label = "extractZipAsync bundle.zip", action = function()
      ensure()
      Async.start("extractZipAsync", function()
        System.extractZipAsync(asset_path("sample/bundle.zip"), OUT .. "async")
      end, function() ls(OUT .. "async/") end)
    end },
  { label = "extractFromZipAsync numbers.csv", action = function()
      ensure()
      local dst = OUT .. "numbers.csv"
      Async.start("extractFromZipAsync", function()
        System.extractFromZipAsync(asset_path("sample/bundle.zip"), "data/numbers.csv", dst)
      end, function()
        local s = file_read(dst)
        local sum = 0
        for n, sq in s:gmatch("(%d+),(%d+)") do sum = sum + tonumber(sq) end
        Log.ok("sum of squares in numbers.csv = " .. sum)
      end)
    end },
  { label = "compressZip(app0:/sce_sys, level 9)", action = function()
      ensure()
      local z = OUT .. "sce_sys.zip"
      if System.doesFileExist(z) then System.deleteFile(z) end
      Try("compressZip", System.compressZip, "app0:/sce_sys", z, 9)
      Log.info("  size " .. human_bytes(System.statFile(z).size))
    end },
  { label = "addToZip hello.png into images/", action = function()
      local z = OUT .. "sce_sys.zip"
      if not System.doesFileExist(z) then Log.err("run compressZip first"); return end
      Try("addToZip", System.addToZip, asset_path("img/hello.png"), z, "images", 0)
      Log.info("  size " .. human_bytes(System.statFile(z).size))
      Try("extractZip (verify)", System.extractZip, z, OUT .. "roundtrip")
      ls(OUT .. "roundtrip/")
    end },
  { label = "extractSfo(legacy.pbp)", action = function()
      local ok, t = Try("extractSfo(PBP)", System.extractSfo, asset_path("sample/legacy.pbp"))
      if ok then show_sfo(t) end
    end },
  { label = "extractPbp legacy.pbp", action = function()
      ensure()
      Try("extractPbp", System.extractPbp, asset_path("sample/legacy.pbp"), OUT .. "pbp")
      ls(OUT .. "pbp/")
    end },
  { label = "Error: extractSfo on a PNG", action = function() Try("extractSfo(hello.png)", System.extractSfo, asset_path("img/hello.png")) end },
  { label = "Clean up zip/", action = function()
      local function rm(dir)
        for _, e in ipairs(System.listDirectory(dir) or {}) do
          if e.directory then rm(dir .. e.name .. "/") else System.deleteFile(dir .. e.name) end
        end
        System.deleteDirectory(dir)
      end
      rm(OUT)
      Log.ok("removed " .. OUT)
    end },
}

function S.update() S.list:update() end
function S.draw()
  S.draw_actions("Log")
  Async.draw_badge(16, 466)
end

return S
