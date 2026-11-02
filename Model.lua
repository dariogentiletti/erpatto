-- Er Patto: the cap model.
-- Each level needs the same XP as Classic. Time per level = XP needed / XP per hour, where XP per hour grows like a
-- same-level mob's XP (45 + 5 x level) raised to a power solved so the curve hits "hours to 20" and "hours to 60".
-- Settings only use "from week N" rows, so changing them never rewrites weeks that already started.
local ADDON, ns = ...
local U = ns.U
local M = {}
ns.M = M

M.XP = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400, 12900, 14400, 16000, 17700,
  19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800,
  67100, 71600, 76100, 80800, 85700, 90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200,
  147500, 153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }
M.CX = { 0 } -- CX[L] = total XP to reach level L
for i = 1, #M.XP do M.CX[i + 1] = M.CX[i] + M.XP[i] end
M.MAXXP = M.CX[60]
M.WEEK = 7 * 24 * 3600
M.MAXLEVEL = 60

local function Weights(p)
  local w = {}
  for i = 1, 59 do w[i] = M.XP[i] / ((45 + 5 * i) ^ p) end
  return w
end

local function EarlyShare(w)
  local a, t = 0, 0
  for i = 1, 59 do
    t = t + w[i]
    if i <= 19 then a = a + w[i] end
  end
  return a / t
end

local cache = {}
-- cum[L] = played hours to reach level L (cum[1] = 0, cum[60] = h60)
function M.Curve(h20, h60)
  local key = h20 .. "/" .. h60
  if cache[key] then return cache[key] end
  local target, lo, hi = h20 / h60, 0, 4
  for _ = 1, 50 do
    local mid = (lo + hi) / 2
    if EarlyShare(Weights(mid)) < target then lo = mid else hi = mid end
  end
  local w = Weights((lo + hi) / 2)
  local total = 0
  for i = 1, 59 do total = total + w[i] end
  local cum = { 0 }
  for i = 1, 59 do cum[i + 1] = cum[i] + w[i] / total * h60 end
  cache[key] = cum
  return cum
end

function M.LevelAtHours(cum, h)
  local L = 1
  for i = 1, 60 do if cum[i] <= h + 1e-9 then L = i end end
  return L
end

function M.LevelFromXp(xp)
  local L = 1
  for i = 1, 60 do if M.CX[i] <= xp + 1e-6 then L = i end end
  return L
end

function M.XpToHours(cum, xp)
  if xp >= M.MAXXP then return cum[60] end
  local L = M.LevelFromXp(xp)
  return cum[L] + (xp - M.CX[L]) / M.XP[L] * (cum[L + 1] - cum[L])
end

function M.HoursToXp(cum, h)
  if h >= cum[60] then return M.MAXXP end
  local L = M.LevelAtHours(cum, h)
  return M.CX[L] + (h - cum[L]) / (cum[L + 1] - cum[L]) * M.XP[L]
end

-- latest row with row.from <= week (rows need not be sorted)
local function Active(rows, week, field)
  local best
  for _, r in ipairs(rows or {}) do
    if type(r.from) == "number" and r.from <= week and (field == nil or (type(r[field]) == "number" and r[field] > 0))
      and (not best or r.from >= best.from) then
      best = r
    end
  end
  return best
end
M.Active = Active

local function Reset(rows, week)
  for _, r in ipairs(rows or {}) do
    if r.from == week and type(r.level) == "number" and r.level >= 1 and r.level <= 60 then return r.level end
  end
  return nil
end

local DEFAULT_CALIB = { from = 1, h20 = 25, h60 = 190 }

function M.CalibFor(settings, week)
  return Active(settings.calib, week, "h60") or DEFAULT_CALIB
end

-- Week-by-week caps for one team. Each row: week, cap, gain, done, dingXp, dingHours, xpStart, xpEnd, hours
function M.TeamRows(settings, team, minRows)
  local rows, xp, prevCap = {}, 0, 1
  for k = 1, 260 do
    local calib = M.CalibFor(settings, k)
    local cum = M.Curve(calib.h20, calib.h60)
    local reset = Reset(team.pace, k)
    if reset then xp = M.CX[reset] end
    local pace = Active(team.pace, k, "hours")
    local H = pace and pace.hours or 10
    local xpStart = xp
    local xpEnd = M.HoursToXp(cum, M.XpToHours(cum, xp) + H)
    local cap = M.LevelFromXp(xpEnd)
    rows[k] = {
      week = k, cap = cap, gain = cap - prevCap, done = prevCap >= 60 and not reset, hours = H,
      dingXp = math.max(0, M.CX[cap] - xpStart),
      dingHours = math.max(0, M.XpToHours(cum, M.CX[cap]) - M.XpToHours(cum, xpStart)),
      xpStart = xpStart, xpEnd = xpEnd,
    }
    xp, prevCap = xpEnd, cap
    if cap >= 60 and k >= (minRows or 0) then break end
  end
  return rows
end

-- All teams, padded to the same number of weeks.
function M.Schedule(settings)
  local out, n = { teams = {}, n = 0 }, 0
  for _, team in ipairs(settings.teams or {}) do
    local rows = M.TeamRows(settings, team)
    out.teams[team.id] = rows
    if #rows > n then n = #rows end
  end
  for _, team in ipairs(settings.teams or {}) do
    if #out.teams[team.id] < n then out.teams[team.id] = M.TeamRows(settings, team, n) end
  end
  out.n = n
  out.starts = {}
  for k = 1, n do out.starts[k] = (settings.start or 0) + (k - 1) * M.WEEK end
  return out
end

-- 0 before the start, otherwise the 1-based week number.
function M.WeekIndex(settings, now)
  if not settings.start or now < settings.start then return 0 end
  return math.floor((now - settings.start) / M.WEEK) + 1
end

function M.TeamById(settings, id)
  for _, t in ipairs(settings.teams or {}) do if t.id == id then return t end end
  return nil
end

-- Everything a screen needs about one team right now.
function M.Status(settings, teamId, now)
  local team = M.TeamById(settings, teamId)
  if not team or not settings.start then return nil end
  local rows = M.TeamRows(settings, team)
  local wk = M.WeekIndex(settings, now)
  local idx = math.max(1, wk)
  local lifted = wk > #rows
  local row = rows[math.min(idx, #rows)]
  local cap = lifted and 60 or row.cap
  local nextRow = rows[idx + 1]
  local finish
  for i, r in ipairs(rows) do if r.cap >= 60 then finish = i break end end
  local unlockAt = settings.start + (wk < 1 and 0 or wk) * M.WEEK
  return {
    team = team, rows = rows, week = wk, row = row, cap = cap, lifted = lifted, started = wk >= 1,
    nextCap = lifted and 60 or (nextRow and nextRow.cap or 60), finishWeek = finish,
    unlockAt = unlockAt, weekStart = settings.start + (idx - 1) * M.WEEK,
  }
end

-- Played hours a player still needs to reach the cap level, from the patto's average speed curve.
-- The XP bar is read as a fraction, so a client with a different XP table (retail tests) still gives sane numbers.
function M.HoursToCap(settings, week, lv, xp, xpm, cap)
  if not lv or lv >= 60 or lv >= cap then return 0 end
  local calib = M.CalibFor(settings, math.max(1, week))
  local cum = M.Curve(calib.h20, calib.h60)
  local frac = (xp and xpm and xpm > 0) and math.max(0, math.min(1, xp / xpm)) or 0
  local now = M.CX[lv] + frac * M.XP[lv]
  return math.max(0, M.XpToHours(cum, M.CX[math.min(60, cap)]) - M.XpToHours(cum, now))
end

-- How a player stands against a cap.
function M.PlayerState(level, cap)
  if not level or level < 1 then return "unknown", 0 end
  if level > cap then return "over", level - cap end
  if level == cap then return "at", 0 end
  return "behind", cap - level
end
