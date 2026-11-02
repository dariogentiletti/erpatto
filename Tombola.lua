-- Er Patto: la Tombola de la settimana and the Totopatto.
--
-- Tombola: every week the patto gets one 3x3 card of nine challenges, the same for everybody (it comes from the
-- patto code and the week number, so nothing has to be sent). Each challenge is checked against what the member did
-- that week (the shared weekly stats), so everyone sees everyone's card. Points:
--   1 for each square, +2 for each line of three ("terno"), +10 for the full card ("tombola").
--
-- Totopatto: in the first two days of the week everyone guesses who will level most, quest most and die most that
-- week. The guesses travel in the record (so everyone sees who bet on whom); when the week is over, each player
-- counts their own right guesses: 3 points each.
--
-- The season ranking is the sum of everyone's points; each player keeps the history of their own weeks and shares
-- the total.
local ADDON, ns = ...
local U, M, P, T, UI = ns.U, ns.M, ns.P, ns.T, ns.UI
local H = UI.H
local TB = {}
ns.Tombola = TB

local YD_KM = 0.0009144 -- yards to km

-- the squares; k is a weekly stat (or a list summed), n the target
TB.POOL = {
  { id = "q20", t = "Fai 20 quest", k = "q", n = 20 },
  { id = "q50", t = "Fai 50 quest", k = "q", n = 50 },
  { id = "dg1", t = "Fai 'n dungeon", k = "dg", n = 1 },
  { id = "dg3", t = "Fai 3 dungeon", k = "dg", n = 3 },
  { id = "ding2", t = "Sali 2 livelli", k = "ding", n = 2 },
  { id = "ding4", t = "Sali 4 livelli", k = "ding", n = 4 },
  { id = "dw1", t = "Vinci 'n duello", k = "dw", n = 1 },
  { id = "dl1", t = "Perdi 'n duello", k = "dl", n = 1 },
  { id = "rk1", t = "Ammazza 'n raro", k = "rk", n = 1 },
  { id = "nk2", t = "Ammazza 2 boss o famosi", k = "nk", n = 2 },
  { id = "fi10", t = "Pesca 10 pesci", k = "fi", n = 10 },
  { id = "ga20", t = "Raccoji 20 erbe, minerali o pelli", k = { "he", "mi", "sk" }, n = 20 },
  { id = "lb1", t = "Trova 'n blu", k = { "lb", "le" }, n = 1 },
  { id = "em1", t = "More da scemo", k = "em", n = 1 },
  { id = "pt10", t = "Gioca 10 ore", k = "pt", n = 36000 },
  { id = "g50", t = "Fai 50 monete d'oro", k = "g", n = 500000 },
  { id = "tr20", t = "Cammina 20 km", k = "tr", n = 21873 },
  { id = "fl3", t = "Prendi 3 voli", k = "fl", n = 3 },
  { id = "hs3", t = "Torna a casa co' la pietra 3 vorte", k = "hs", n = 3 },
  { id = "dt0", t = "Nun more mai (armeno 5 ore)", zero = "dt", min = { "pt", 18000 } },
}
local LINES = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 }, { 1, 5, 9 }, { 3, 5, 7 } }
TB.LINES = LINES

local function RealWeek()
  if not (ns.state and P.HasSettings(ns.state)) then return nil end
  return M.WeekIndex(ns.state.settings, U.Now())
end

-- test mode (capo only, before the start): the card and the guesses already work, on what you do now (the
-- pre-start week), with the test members; guesses stay on this computer and no points are written
function TB.Testing()
  local wk = RealWeek()
  return wk ~= nil and wk < 1 and ns.db and ns.db.opts.testMode and ns.IsCapo and ns.IsCapo() and true or false
end

local function Week()
  local wk = RealWeek()
  if wk and wk < 1 and TB.Testing() then return 1 end
  return wk
end
TB.Week = Week

local function Weekly(rec, wk)
  local w = rec and rec.stats and rec.stats.w and rec.stats.w[wk]
  if type(w) ~= "table" and TB.Testing() then
    local real = RealWeek()
    w = rec and rec.stats and rec.stats.w and rec.stats.w[real]
  end
  return type(w) == "table" and w or {}
end
TB.Weekly = Weekly

-- a small deterministic shuffle from a string seed
local function Seeded(seed)
  local h = 2166136261
  for i = 1, #seed do h = (h * 16777619 + seed:byte(i)) % 4294967296 end
  return function(n)
    h = (h * 1103515245 + 12345) % 2147483648
    return (h % n) + 1
  end
end

local cards = {}
function TB.Card(wk)
  wk = wk or Week()
  if not wk or wk < 1 or not ns.state then return nil end
  local key = ns.state.code .. ":" .. wk
  if cards[key] then return cards[key] end
  local rnd = Seeded(key)
  local pool = {}
  for i, c in ipairs(TB.POOL) do pool[i] = c end
  local card = {}
  for i = 1, 9 do card[i] = table.remove(pool, rnd(#pool)) end
  cards[key] = card
  return card
end

local function Value(w, k)
  if type(k) == "table" then
    local s = 0
    for _, x in ipairs(k) do s = s + (w[x] or 0) end
    return s
  end
  return w[k] or 0
end

-- how far a member is on one square: done, current, target
function TB.Progress(sq, w)
  if sq.zero then
    local ok = (w[sq.zero] or 0) == 0 and (w[sq.min[1]] or 0) >= sq.min[2]
    return ok, ok and 1 or 0, 1
  end
  local v = Value(w, sq.k)
  return v >= sq.n, math.min(v, sq.n), sq.n
end

function TB.ProgressText(sq, cur, target)
  if sq.k == "pt" then return string.format("%d/%d ore", math.floor(cur / 3600), target / 3600) end
  if sq.k == "g" then return string.format("%d/%d oro", math.floor(cur / 10000), target / 10000) end
  if sq.k == "tr" then return string.format("%.1f/%d km", cur * YD_KM, math.floor(target * YD_KM + 0.5)) end
  if sq.zero then return cur >= 1 and "fatto" or "ancora no" end
  return cur .. "/" .. target
end

-- the score of a member for a week (default: this week)
function TB.Score(rec, wk)
  wk = wk or Week()
  local card = wk and TB.Card(wk)
  if not (card and rec) then return nil end
  local w = Weekly(rec, wk)
  local done, cells = {}, 0
  for i, sq in ipairs(card) do
    done[i] = TB.Progress(sq, w)
    if done[i] then cells = cells + 1 end
  end
  local lines = 0
  for _, l in ipairs(LINES) do if done[l[1]] and done[l[2]] and done[l[3]] then lines = lines + 1 end end
  local full = cells == 9
  return { wk = wk, done = done, cells = cells, lines = lines, full = full, points = cells + 2 * lines + (full and 10 or 0) }
end

----------------------------------------------------------------------
-- Totopatto
----------------------------------------------------------------------
TB.QUESTIONS = {
  { key = "a", stat = "ding", text = "Chi sale più livelli?" },
  { key = "b", stat = "q", text = "Chi fa più quest?" },
  { key = "c", stat = "dt", text = "Chi more de più?" },
}
TB.VOTE_WINDOW = 2 * 86400

function TB.WeekStart(wk)
  local s = ns.state.settings
  return s.start + (wk - 1) * M.WEEK
end

function TB.CanVote()
  local wk = Week()
  if TB.Testing() then return true, wk end
  if not wk or wk < 1 or ns.alt then return false end
  return U.Now() - TB.WeekStart(wk) < TB.VOTE_WINDOW, wk
end

-- my guesses of a member's record (or, in test mode, the ones kept on this computer)
function TB.VotesOf(m, wk)
  wk = wk or Week()
  local vt = m and m.vt
  if m and m.guid == ns.recordGuid and TB.Testing() then vt = ns.db.testVotes end
  if vt and vt.wk == wk then return vt end
  return nil
end

function TB.Vote(qkey, guid)
  local ok, wk = TB.CanVote()
  if not ok then return false end
  local rec = ns.MyRecord()
  if not rec then return false end
  if TB.Testing() then
    local t = (ns.db.testVotes and ns.db.testVotes.wk == wk) and ns.db.testVotes or { wk = wk }
    t[qkey] = guid
    ns.db.testVotes = t
    ns.Fire("Refresh")
    return true
  end
  local vt = (rec.vt and rec.vt.wk == wk) and { wk = wk, a = rec.vt.a, b = rec.vt.b, c = rec.vt.c } or { wk = wk }
  vt[qkey] = guid
  P.UpdateSelf(ns.state, ns.recordGuid, { vt = vt }, "vote")
  return true
end

-- who won each question in a week: { a = { [guid] = true }, ... } (ties all win; nobody if the best is zero)
function TB.Winners(wk, list)
  local out = {}
  for _, q in ipairs(TB.QUESTIONS) do
    local best = 0
    for _, m in ipairs(list) do best = math.max(best, Weekly(m, wk)[q.stat] or 0) end
    out[q.key] = {}
    if best > 0 then
      for _, m in ipairs(list) do if (Weekly(m, wk)[q.stat] or 0) == best then out[q.key][m.guid] = true end end
    end
  end
  return out
end

----------------------------------------------------------------------
-- my points: one entry per week, frozen when the week is over
----------------------------------------------------------------------
local function Book()
  if not (ns.db and ns.state) then return nil end
  ns.db.points = type(ns.db.points) == "table" and ns.db.points or {}
  local b = ns.db.points[ns.state.code]
  if type(b) ~= "table" then b = { weeks = {}, right = 0 } ns.db.points[ns.state.code] = b end
  b.weeks = b.weeks or {}
  return b
end

-- called often: closes the weeks that ended (tombola + guesses) and shares the total
function TB.Update()
  if not ns.state or ns.alt or not P.HasSettings(ns.state) or TB.Testing() then return end
  local rec = ns.MyRecord()
  local wk = Week()
  if not (rec and wk and wk >= 1) then return end
  local b = Book()
  local list = UI.Members()
  -- the weeks that ended since last time, while their stats are still in the records
  if b.closed == nil then b.closed = math.max(0, wk - 2) end
  for prev = b.closed + 1, wk - 1 do
    if not b.weeks[prev] then
      local sc = TB.Score(rec, prev)
      local pts = sc and sc.points or 0
      local right = 0
      if rec.vt and rec.vt.wk == prev then
        local win = TB.Winners(prev, list)
        for _, q in ipairs(TB.QUESTIONS) do
          local g = rec.vt[q.key]
          if g and win[q.key][g] then right = right + 1 end
        end
      end
      b.weeks[prev] = pts + 3 * right
      b.right = (b.right or 0) + right
      if right > 0 then U.Say("Totopatto: hai indovinato " .. right .. (right == 1 and " risposta" or " risposte") .. ", +" .. 3 * right .. " punti.") end
    end
  end
  b.closed = math.max(b.closed, wk - 1)
  local now = TB.Score(rec, wk)
  local total = now and now.points or 0
  for w, n in pairs(b.weeks) do if w < wk then total = total + n end end
  local cur = rec.pts or {}
  if cur.t ~= total or cur.wk ~= wk or cur.w ~= (now and now.points or 0) then
    P.UpdateSelf(ns.state, ns.recordGuid, { pts = { t = total, w = now and now.points or 0, wk = wk } }, "pts")
  end
end

-- test mode: close this week now, to see what it would give (nothing is kept)
function TB.SimulateClose()
  local wk = Week()
  local rec = ns.MyRecord()
  if not (wk and rec) then return nil end
  local sc = TB.Score(rec, wk) or { points = 0, cells = 0, lines = 0 }
  local list = UI.Members()
  local win = TB.Winners(wk, list)
  local mine = TB.VotesOf(rec, wk) or {}
  local right, lines = 0, {}
  local byGuid = {}
  for _, m in ipairs(list) do byGuid[m.guid] = m end
  for _, q in ipairs(TB.QUESTIONS) do
    local names = {}
    for g in pairs(win[q.key]) do names[#names + 1] = byGuid[g] and (tostring(byGuid[g].name):match("^(%S+)")) or "?" end
    table.sort(names)
    local ok = mine[q.key] and win[q.key][mine[q.key]] and true or false
    if ok then right = right + 1 end
    lines[#lines + 1] = q.text .. " " .. (#names > 0 and table.concat(names, ", ") or "nessuno") .. (ok and " |cff20ff20(indovinato)|r" or "")
  end
  return sc.points + 3 * right, sc, right, lines
end

-- points of anybody: their shared total, mine computed live
function TB.TotalOf(m)
  if m.guid == ns.recordGuid then
    local rec = ns.MyRecord()
    return rec and rec.pts and rec.pts.t or 0
  end
  return m.pts and m.pts.t or 0
end

ns.On("SelfChanged", function(state, reason)
  if state ~= ns.state or reason == "pts" or reason == "vote" then return end
  TB.Update()
end)
ns.On("Login", function()
  if C_Timer then
    C_Timer.After(15, TB.Update)
    C_Timer.NewTicker(120, TB.Update)
  end
end)
