-- Er Patto: the logic of Er Botteghino (the betting shop of the patto). The money is the sesterzio.
--
-- La Tombola: every week one 3x3 card of nine challenges, the same for everybody. Nobody picks it: it comes out of
-- the "sacchetto", a draw seeded with the patto code and the week number, so every computer gets the same card
-- without sending anything. Each square is checked against what the member did that week (the shared weekly stats).
--   1 sesterzio a square, +2 a full line ("terno"), +10 the whole card ("tombola").
--
-- La Schedina: three questions each week (who levels most, who quests most, who dies most). In the first two days you
-- pick a member and stake sesterzi. At the end of the week the stakes of each question make the pot, shared among
-- those who guessed right, in proportion to what they staked. If nobody guessed right, everyone gets the stake back.
--
-- Everybody starts with 20 sesterzi. Sesterzi buy "sfottò" (a banner on a friend's screen) and make the ranking of
-- the richest. Each player keeps their own book (per week: tombola, winnings, stakes) and shares the balance.
-- The bets travel in the record: this week's (vt) and last week's (vp), so the pots can be counted by everyone.
local ADDON, ns = ...
local U, M, P, T, UI = ns.U, ns.M, ns.P, ns.T, ns.UI
local H = UI.H
local TB = {}
ns.Tombola = TB

TB.START = 20          -- sesterzi everyone starts with
TB.STAKES = { 1, 5, 10 }
TB.SFOTTO = 3          -- the price of a sfottò
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

TB.QUESTIONS = {
  { key = "a", stat = "ding", text = "Chi sale più livelli?" },
  { key = "b", stat = "q", text = "Chi fa più quest?" },
  { key = "c", stat = "dt", text = "Chi more de più?" },
}
TB.VOTE_WINDOW = 2 * 86400

----------------------------------------------------------------------
-- weeks, and the test mode
----------------------------------------------------------------------
local function RealWeek()
  if not (ns.state and P.HasSettings(ns.state)) then return nil end
  return M.WeekIndex(ns.state.settings, U.Now())
end
TB.RealWeek = RealWeek

-- test mode (/patto prova, capo only): the card works on what you do now, the schedina is always open, bets stay
-- on this computer and nothing is written in the real book
function TB.Testing()
  return ns.state ~= nil and ns.db and ns.db.opts.testMode and ns.IsCapo and ns.IsCapo() and P.HasSettings(ns.state) and true or false
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

function TB.WeekStart(wk)
  return ns.state.settings.start + (wk - 1) * M.WEEK
end

----------------------------------------------------------------------
-- the card
----------------------------------------------------------------------
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
-- the book: my sesterzi
----------------------------------------------------------------------
local function Book()
  if not (ns.db and ns.state) then return nil end
  ns.db.points = type(ns.db.points) == "table" and ns.db.points or {}
  local b = ns.db.points[ns.state.code]
  if type(b) ~= "table" then b = {} ns.db.points[ns.state.code] = b end
  b.weeks = type(b.weeks) == "table" and b.weeks or {}
  b.spent = b.spent or 0
  b.right = b.right or 0
  -- older books kept a number per week
  for wk, v in pairs(b.weeks) do if type(v) == "number" then b.weeks[wk] = { t = v, w = 0 } end end
  return b
end
TB.Book = Book

-- bets of a member for a week: their record (this week or last), or what we saw before; in test mode, mine are local
function TB.VotesOf(m, wk)
  wk = wk or Week()
  if not m then return nil end
  if m.guid == ns.recordGuid and TB.Testing() then
    local t = ns.db.testVotes
    return (t and t.wk == wk) and t or nil
  end
  if m.vt and m.vt.wk == wk then return m.vt end
  if m.vp and m.vp.wk == wk then return m.vp end
  local seen = ns.db and ns.db.betsSeen and ns.state and ns.db.betsSeen[ns.state.code]
  local w = seen and seen[wk]
  return w and w[m.guid] or nil
end

-- remember the bets we see, so a week can be counted even after people bet again
local function Remember(m)
  if not (ns.db and ns.state and m and m.guid) then return end
  ns.db.betsSeen = type(ns.db.betsSeen) == "table" and ns.db.betsSeen or {}
  local all = ns.db.betsSeen[ns.state.code] or {}
  ns.db.betsSeen[ns.state.code] = all
  for _, v in ipairs({ m.vt, m.vp }) do
    if type(v) == "table" and v.wk then
      all[v.wk] = all[v.wk] or {}
      all[v.wk][m.guid] = v
    end
  end
  for wk in pairs(all) do if (Week() or 0) - wk > 3 then all[wk] = nil end end
end

local function StakeOf(v, key) return v and v[key] and (v["s" .. key] or 0) or 0 end

-- my balance: start + every week's tombola and winnings - every stake - what I spent
function TB.Balance()
  local b = Book()
  local rec = ns.MyRecord and ns.MyRecord()
  if not (b and rec) then return TB.START end
  local wk = Week() or 0
  local total = TB.START - b.spent
  for w, e in pairs(b.weeks) do if w < wk then total = total + (e.t or 0) + (e.w or 0) end end
  local now = TB.Score(rec, wk)
  total = total + (now and now.points or 0)
  -- stakes are paid when placed (this week's and the open ones)
  for w, s in pairs(b.stakes or {}) do total = total - s end
  if TB.Testing() then
    local t = ns.db.testVotes
    if t and t.wk == wk then for _, q in ipairs(TB.QUESTIONS) do total = total - StakeOf(t, q.key) end end
  end
  return math.max(0, total)
end

-- anybody's balance: theirs as shared, mine live
function TB.TotalOf(m)
  if m.guid == ns.recordGuid then return TB.Balance() end
  return m.pts and m.pts.t or TB.START
end

----------------------------------------------------------------------
-- La Schedina
----------------------------------------------------------------------
function TB.CanVote()
  local wk = Week()
  if TB.Testing() then return true, wk end
  if not wk or wk < 1 or ns.alt then return false end
  return U.Now() - TB.WeekStart(wk) < TB.VOTE_WINDOW, wk
end

function TB.Closes(wk) return TB.WeekStart(wk) + TB.VOTE_WINDOW end

-- pick (guid) and/or stake for a question; the stake is paid now, a change refunds the old one
function TB.Bet(qkey, guid, stake)
  local ok, wk = TB.CanVote()
  if not ok then return false, "Le giocate so' chiuse." end
  local rec = ns.MyRecord()
  if not rec then return false end
  local cur = TB.VotesOf(rec, wk) or { wk = wk }
  local new = { wk = wk }
  for _, q in ipairs(TB.QUESTIONS) do new[q.key], new["s" .. q.key] = cur[q.key], cur["s" .. q.key] end
  if guid then new[qkey] = guid end
  if not new[qkey] then return false, "Prima scegli su chi giocà." end
  local old = new["s" .. qkey] or 0
  stake = stake or (old > 0 and old or 5)
  local available = TB.Balance() + old
  if stake > available then return false, "Nun c'hai abbastanza sesterzi (" .. available .. ")." end
  new["s" .. qkey] = stake
  if TB.Testing() then
    ns.db.testVotes = new
    ns.Fire("Refresh")
    return true
  end
  local b = Book()
  b.stakes = b.stakes or {}
  local sum = 0
  for _, q in ipairs(TB.QUESTIONS) do sum = sum + StakeOf(new, q.key) end
  b.stakes[wk] = sum
  local fields = { vt = new }
  if rec.vt and rec.vt.wk and rec.vt.wk < wk then fields.vp = rec.vt end
  P.UpdateSelf(ns.state, ns.recordGuid, fields, "vote")
  TB.Update()
  return true
end
TB.Vote = function(qkey, guid) return TB.Bet(qkey, guid) end

-- who won each question in a week (ties all win; nobody if the best is zero)
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

-- a question's market: pot, stakes per pick, the top picks with their payout
function TB.Market(wk, list, qkey)
  local pot, per, count = 0, {}, {}
  for _, m in ipairs(list) do
    local v = TB.VotesOf(m, wk)
    local g = v and v[qkey]
    if g then
      local s = StakeOf(v, qkey)
      pot = pot + s
      per[g] = (per[g] or 0) + s
      count[g] = (count[g] or 0) + 1
    end
  end
  local top = {}
  for g, n in pairs(count) do top[#top + 1] = { guid = g, n = n, stake = per[g], pays = per[g] > 0 and pot / per[g] or 0 } end
  table.sort(top, function(a, b) return a.n > b.n or (a.n == b.n and a.stake > b.stake) end)
  return pot, top
end

-- what a week paid me: winnings (and refunds when nobody guessed), right answers, lines to tell
function TB.Payout(wk, list, myVotes)
  local win = TB.Winners(wk, list)
  local total, right, lines = 0, 0, {}
  for _, q in ipairs(TB.QUESTIONS) do
    local pot, good = 0, 0
    for _, m in ipairs(list) do
      local v = TB.VotesOf(m, wk)
      if m.guid == ns.recordGuid then v = myVotes end
      local s = StakeOf(v, q.key)
      pot = pot + s
      if v and v[q.key] and win[q.key][v[q.key]] then good = good + s end
    end
    local mine = StakeOf(myVotes, q.key)
    local got = 0
    if mine > 0 then
      if good == 0 then got = mine -- nobody guessed: stakes back
      elseif win[q.key][myVotes[q.key]] then
        got = math.floor(pot * mine / good)
        right = right + 1
      end
    end
    total = total + got
    lines[#lines + 1] = { q = q, got = got, mine = mine, pot = pot, nobody = good == 0, winners = win[q.key] }
  end
  return total, right, lines
end

----------------------------------------------------------------------
-- closing the weeks
----------------------------------------------------------------------
function TB.Update()
  if not ns.state or ns.alt or not P.HasSettings(ns.state) then return end
  for _, m in pairs(ns.state.members) do Remember(m) end
  if TB.Testing() then return end
  local rec = ns.MyRecord()
  local wk = RealWeek()
  if not (rec and wk and wk >= 1) then return end
  local b = Book()
  local list = UI.Members()
  if b.closed == nil then b.closed = math.max(0, wk - 2) end
  for prev = b.closed + 1, wk - 1 do
    if not b.weeks[prev] then
      local sc = TB.Score(rec, prev)
      local mine = TB.VotesOf(rec, prev)
      local won, right = 0, 0
      if mine then won, right = TB.Payout(prev, list, mine) end
      b.weeks[prev] = { t = sc and sc.points or 0, w = won }
      if b.stakes and b.stakes[prev] then b.weeks[prev].s = b.stakes[prev] b.spent = b.spent + b.stakes[prev] b.stakes[prev] = nil end
      b.right = b.right + right
      if mine then
        U.Say("La Schedina de la settimana " .. prev .. ": " .. right .. "/3 indovinate, " .. won .. " sesterzi.")
      end
    end
  end
  b.closed = math.max(b.closed, wk - 1)
  local bal = TB.Balance()
  local now = TB.Score(rec, wk)
  local cur = rec.pts or {}
  if cur.t ~= bal or cur.wk ~= wk or cur.w ~= (now and now.points or 0) then
    P.UpdateSelf(ns.state, ns.recordGuid, { pts = { t = bal, w = now and now.points or 0, wk = wk } }, "pts")
  end
end

-- test mode: close this week now and see what it gives (nothing is kept)
function TB.SimulateClose()
  local wk = Week()
  local rec = ns.MyRecord()
  if not (wk and rec) then return nil end
  local sc = TB.Score(rec, wk) or { points = 0, cells = 0, lines = 0 }
  local list = UI.Members()
  local mine = TB.VotesOf(rec, wk) or {}
  local won, right, details = TB.Payout(wk, list, mine)
  local byGuid = {}
  for _, m in ipairs(list) do byGuid[m.guid] = m end
  local out = {}
  for _, d in ipairs(details) do
    local names = {}
    for g in pairs(d.winners) do names[#names + 1] = byGuid[g] and (tostring(byGuid[g].name):match("^(%S+)")) or "?" end
    table.sort(names)
    out[#out + 1] = d.q.text .. " " .. (#names > 0 and table.concat(names, ", ") or "nessuno") ..
      (d.mine > 0 and (d.got > 0 and (" |cff20ff20+" .. d.got .. "|r") or " |cffff4040perso|r") or "")
  end
  return sc.points + won, sc, right, out, won
end

----------------------------------------------------------------------
-- sfottò: a banner on a friend's screen, for 3 sesterzi
----------------------------------------------------------------------
TB.SFOTTI = {
  "Sei proprio 'n pischello!",
  "Ao, svejate!",
  "Ma che stai a fa'?",
  "Te stai a fa' superà da tutti.",
  "Va' a pescà, che è mejo.",
  "Er cap te guarda e ride.",
  "Pure Hogger te batte.",
  "Daje che manca poco... a diventà bravo.",
  "Stai a fa' la muffa?",
  "Me fai ride, guarda.",
}
local lastSfotto = 0
function TB.Sfotti(guid, idx)
  if not (ns.state and guid) or ns.alt then return false end
  if guid == ns.recordGuid then return false, "Nun te poi sfotte da solo." end
  local now = GetTime and GetTime() or 0
  if now - lastSfotto < 30 then return false, "Aspetta 'n attimo prima de sfotte de novo." end
  if TB.Balance() < TB.SFOTTO then return false, "Te servono " .. TB.SFOTTO .. " sesterzi." end
  idx = idx or math.random(#TB.SFOTTI)
  lastSfotto = now
  if not TB.Testing() then
    local b = Book()
    b.spent = b.spent + TB.SFOTTO
    ns.C.Send("F", { t = guid, p = idx })
    TB.Update()
  end
  return true, TB.SFOTTI[idx]
end

ns.On("Sfotto", function(from, data)
  if type(data) ~= "table" or data.t ~= ns.recordGuid then return end
  local p = tonumber(data.p)
  local text = p and TB.SFOTTI[p]
  if not text then return end
  local who = ns.state and ns.state.members[from]
  local name = who and (tostring(who.name):match("^(%S+)")) or "Quarcuno"
  if ns.News then
    ns.News.Banner(name .. " te sfotte:", text, { 1, 0.5, 0.2 }, "evento")
    ns.News.Add("|cffffd100" .. name .. "|r t'ha sfottuto: " .. text)
  end
end)

ns.On("MemberUpdated", function(rec) Remember(rec) end)
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
