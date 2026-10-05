-- 23. Coverage: which of the API functions this session has actually called.
local S = {
  title = "API Coverage", modules = {},
  desc = "Every function of all 18 lpp-vita modules is wrapped at start-up and counted when called. "
      .. "This page lists them per module, green when used at least once this session, with call "
      .. "counts. Visit the other demos and come back to fill it in. SQUARE writes a report to "
      .. "ux0:/data/lpp-showcase/coverage.txt.",
  hints = { { "left", "" }, { "right", "Module" }, { "square", "Save report" } },
}

local mi = 1

function S.update()
  if Input.rep("right") then mi = mi % #Coverage.modules + 1 end
  if Input.rep("left") then mi = (mi - 2) % #Coverage.modules + 1 end
  if Input.pressed("square") then
    local out = {}
    local h, t = Coverage.summary()
    out[#out + 1] = string.format("lpp-vita showcase coverage: %d / %d functions called", h, t)
    for _, e in ipairs(Coverage.modules) do
      local mh, mt = Coverage.module_stats(e)
      out[#out + 1] = string.format("\n[%s] %d/%d", e.name, mh, mt)
      for _, fn in ipairs(e.fns) do
        out[#out + 1] = string.format("  %s %-22s %d", Coverage.calls[e.name .. "." .. fn] > 0 and "+" or "-", fn,
          Coverage.calls[e.name .. "." .. fn])
      end
    end
    local path = data_path("coverage.txt")
    if System.doesFileExist(path) then System.deleteFile(path) end
    file_write(path, table.concat(out, "\n") .. "\n")
    Log.ok("saved " .. path)
  end
end

function S.draw()
  -- module overview, left column
  for i, e in ipairs(Coverage.modules) do
    local h, t = Coverage.module_stats(e)
    local y = 56 + (i - 1) * 24
    if i == mi then UI.rect(12, y - 2, 296, 23, C.accent) end
    UI.text(20, y, e.name, C.text, 15)
    UI.bar(130, y + 4, 110, 12, t > 0 and h / t or 0, h == t and C.ok or C.accent2)
    UI.text(250, y, h .. "/" .. t, C.dim, 14)
  end
  -- function grid for the selected module
  local e = Coverage.modules[mi]
  local h, t = Coverage.module_stats(e)
  UI.panel(320, 56, 624, 436, e.name .. "   " .. h .. " / " .. t .. " called")
  local cols = #e.fns > 34 and 3 or 2
  local cw = 600 / cols
  local per = math.ceil(#e.fns / cols)
  for i, fn in ipairs(e.fns) do
    local c, r = math.floor((i - 1) / per), (i - 1) % per
    local n = Coverage.calls[e.name .. "." .. fn]
    local x, y = 332 + c * cw, 88 + r * (per > 20 and 17 or 20)
    UI.text(x, y, fn, n > 0 and C.ok or C.dim, per > 20 and 13 or 15)
    if n > 0 then UI.text(x + cw - 50, y, n > 9999 and "9999+" or tostring(n), C.dim, 12) end
  end
  local all_h, all_t = Coverage.summary()
  UI.bar(12, 500 - 6, 296, 10, all_h / all_t, C.ok)
  UI.text(12, 470, string.format("total %d / %d (%d%%)", all_h, all_t, math.floor(100 * all_h / all_t)), C.accent2, 15)
end

return S
