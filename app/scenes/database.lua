-- 17. Database: embedded SQLite.
local S = ActionScene({
  title = "SQLite", modules = { "Database" },
  desc = "lpp-vita bundles SQLite. Database.open creates or opens a .db file, execQuery runs any SQL "
      .. "and returns the result rows as a Lua array of {column = value} tables (values are strings "
      .. "or nil), and Database.close releases it. The demo keeps a high-score table on ux0:, and "
      .. "with the unsafe eboot it can query the system's own app.db (read-only).",
  hints = { { "enter", "Run" } },
})

local DB = APP.data .. "scores.db"
local db, rows = nil, {}
local NAMES = { "KRATOS", "SACKBOY", "NATHAN", "KAT", "SLY", "RATCHET", "JAK", "ICO" }

local function q(sql)
  local ok, res = Try("execQuery: " .. sql:sub(1, 46), Database.execQuery, db, sql)
  return ok and res or nil
end

local function refresh()
  rows = q("SELECT id, name, score, strftime('%H:%M:%S', at, 'unixepoch') AS t FROM scores ORDER BY score DESC LIMIT 10") or {}
end

S.actions = {
  { label = "Insert a random score", action = function()
      q(string.format("INSERT INTO scores(name, score, at) VALUES('%s', %d, strftime('%%s','now'))",
        NAMES[math.random(#NAMES)], math.random(100, 99999)))
      refresh()
    end },
  { label = "Aggregate: COUNT / AVG / MAX", action = function()
      local r = q("SELECT COUNT(*) AS n, CAST(AVG(score) AS INT) AS avg, MAX(score) AS best FROM scores")
      if r and r[1] then Log.info(string.format("  n=%s avg=%s best=%s", r[1].n, tostring(r[1].avg), tostring(r[1].best))) end
    end },
  { label = "GROUP BY name", action = function()
      for _, r in ipairs(q("SELECT name, COUNT(*) AS c FROM scores GROUP BY name ORDER BY c DESC") or {}) do
        Log.info(string.format("  %-8s x%s", r.name, r.c))
      end
    end },
  { label = "Transaction: insert 100 rows", action = function()
      local t = Timer.new()
      local parts = { "BEGIN;" }
      for i = 1, 100 do parts[#parts + 1] = string.format("INSERT INTO scores(name, score, at) VALUES('BOT%d', %d, 0);", i, i * 7) end
      parts[#parts + 1] = "COMMIT;"
      q(table.concat(parts, " "))
      Log.ok("100 inserts in " .. Timer.getTime(t) .. " ms")
      Timer.destroy(t)
      refresh()
    end },
  { label = "DELETE bots", action = function() q("DELETE FROM scores WHERE name LIKE 'BOT%'"); refresh() end },
  { label = "NULL handling", action = function()
      local r = q("SELECT NULL AS empty, 'x' AS something")
      if r then Log.info("  empty=" .. tostring(r[1].empty) .. "  something=" .. tostring(r[1].something)) end
    end },
  { label = "sqlite_version()", action = function()
      local r = q("SELECT sqlite_version() AS v")
      if r then Log.info("  SQLite " .. r[1].v) end
    end },
  { label = "Error: bad SQL", action = function() q("SELEKT * FROM nowhere") end },
  { label = "System app.db (unsafe): count apps", action = function()
      local ok, sys = Try("Database.open(ur0:shell/db/app.db)", Database.open, "ur0:shell/db/app.db")
      if not ok then return end
      local r = select(2, Try("execQuery", Database.execQuery, sys,
        "SELECT COUNT(DISTINCT titleId) AS n FROM tbl_appinfo_icon"))
      if r and r[1] then Log.ok("  installed bubbles: " .. r[1].n) end
      Database.close(sys)
    end },
  { label = "DROP + recreate table", action = function()
      q("DROP TABLE IF EXISTS scores")
      q("CREATE TABLE scores(id INTEGER PRIMARY KEY, name TEXT NOT NULL, score INTEGER, at INTEGER)")
      refresh()
    end },
}

function S.enter()
  local ok, h = Try("Database.open(scores.db)", Database.open, DB)
  if not ok then return end
  db = h
  q("CREATE TABLE IF NOT EXISTS scores(id INTEGER PRIMARY KEY, name TEXT NOT NULL, score INTEGER, at INTEGER)")
  refresh()
end

function S.leave()
  if db then Try("Database.close", Database.close, db); db = nil end
end

function S.update() if db then S.list:update() end end

function S.draw()
  S.list:draw()
  local x, w = 436, UI.W - 436 - 12
  UI.panel(x, 56, w, 250, "SELECT ... ORDER BY score DESC LIMIT 10")
  for i, r in ipairs(rows) do
    local y = 86 + (i - 1) * 21
    UI.mono(x + 12, y, string.format("%2d. %-8s %6s  %s", i, r.name, r.score, r.t or ""), i == 1 and C.accent2 or C.text, 15)
  end
  if #rows == 0 then UI.text(x + 12, 90, "(empty table)", C.dim, 15) end
  Log.draw(x, 316, w, 176)
end

return S
