-- Er Patto: the logic of Er Botteghino (the betting shop of the patto). The money is the piotta: play money of the
-- patto, never the game's gold (its own icon, a red sack).
--
-- La Tombola: every week one 3x3 card of nine challenges, the same for everybody. Nobody picks it: it comes out of
-- the "sacchetto", a draw seeded with the patto code and the week number, so every computer gets the same card
-- without sending anything. Never two squares on the same thing. Each square is checked against what the member did
-- that week (the shared weekly stats).
--   1 piotta a square, +2 a full line ("terno"), +10 the whole card ("tombola").
--
-- La Schedina: three questions each week, new every week (drawn like the card, from TB.QPOOL: who levels most,
-- who fishes most, who dies most...). Until the week closes you
-- pick a member and stake as many piotte as you like, at the odds ("quota") shown at that moment, which stay yours:
-- if your pick wins you get stake x quota. The odds come from how the patto is betting (the more piotte on someone,
-- the less they pay) mixed with the form (what each did this week so far and last week), with a small house edge.
-- Ties all win. If nobody did anything (all zero), stakes go back.
-- The closed week is shown in its own window (Botteghino.lua), not in the chat.
--
-- Everybody starts with 20 piotte, and gets one more for every hour played in a group with someone of the patto.
-- Piotte buy "sfottò" (a banner on a friend's screen) and make the ranking of
-- the richest. Each player keeps their own book (per week: tombola, winnings, stakes) and shares the balance.
-- The bets travel in the record: this week's (vt) and last week's (vp), so the pots can be counted by everyone.
local ADDON, ns = ...
local U, M, P, T, UI = ns.U, ns.M, ns.P, ns.T, ns.UI
local H = UI.H
local TB = {}
ns.Tombola = TB

TB.START = 20          -- piotte everyone starts with
TB.SFOTTO = 3          -- the price of a sfottò
TB.ICON = "Interface\\Icons\\INV_Misc_Bag_10_Red"
TB.HEX = "|cffffffff"   -- piotte are white, as the vanilla counters; the red sack tells them from gold

-- "1 piotta", "20 piotte"; Money adds the colour, Coin the little icon in front
function TB.Piotte(n) n = n or 0 return (n == 1 or n == -1) and (n .. " piotta") or (n .. " piotte") end
function TB.Coin(size) return "|T" .. TB.ICON .. ":" .. (size or 0) .. "|t" end
function TB.Money(n, noIcon) return (noIcon and "" or (TB.Coin() .. " ")) .. TB.HEX .. TB.Piotte(n) .. "|r" end
local YD_KM = 0.0009144 -- yards to km

-- the squares; k is a weekly stat (or a list summed), n the target. Meant to take a real week of play; wk: not
-- before that week (gold, bosses, flights need some levels first). The capo can swap a square of this week
-- (TB.Swap): the swaps travel in the settings, so every card stays the same for everybody.
TB.POOL = {
  { id = "q40", t = "Fai 40 quest", k = "q", n = 40 },
  { id = "q80", t = "Fai 80 quest", k = "q", n = 80, wk = 2 },
  { id = "dg3", t = "Fai 3 dungeon", k = "dg", n = 3 },
  { id = "dg6", t = "Fai 6 dungeon", k = "dg", n = 6, wk = 2 },
  { id = "ding5", t = "Sali 5 livelli", k = "ding", n = 5 },
  { id = "dw5", t = "Vinci 5 duelli", k = "dw", n = 5 },
  { id = "rk2", t = "Ammazza 2 rari", k = "rk", n = 2 },
  { id = "nk8", t = "Ammazza 8 boss", k = "nk", n = 8, wk = 2 },
  { id = "fi50", t = "Pesca 50 pesci", k = "fi", n = 50 },
  { id = "ga80", t = "Raccoji 80 erbe, minerali o pelli", k = { "he", "mi", "sk" }, n = 80 },
  { id = "lb3", t = "Trova 3 blu o viola", k = { "lb", "le" }, n = 3, wk = 2 },
  { id = "pt12", t = "Gioca 12 ore", k = "pt", n = 43200 },
  { id = "pt20", t = "Gioca 20 ore", k = "pt", n = 72000 },
  { id = "g25", t = "Fai 25 monete d'oro", k = "g", n = 250000, wk = 4 },
  { id = "g5", t = "Fai 5 monete d'oro", k = "g", n = 50000 },
  { id = "tr50", t = "Cammina 50 km", k = "tr", n = 54681 },
  { id = "tr100", t = "Cammina 100 km", k = "tr", n = 109362, wk = 2 },
  { id = "fl10", t = "Prendi 10 voli", k = "fl", n = 10, wk = 2 },
  { id = "em2", t = "More 2 vorte da scemo", k = "em", n = 2 },
  { id = "dt0", t = "Nun more mai (armeno 10 ore)", zero = "dt", min = { "pt", 36000 } },
}
-- what a square is about: a card never has two squares on the same thing
local function Group(sq)
  if sq.zero then return "0" .. sq.zero end
  return type(sq.k) == "table" and table.concat(sq.k, "+") or sq.k
end
local LINES = { { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 1, 4, 7 }, { 2, 5, 8 }, { 3, 6, 9 }, { 1, 5, 9 }, { 3, 5, 7 } }
TB.LINES = LINES

-- the three slots of the schedina; what each one asks changes every week (TB.Questions)
TB.QUESTIONS = { { key = "a" }, { key = "b" }, { key = "c" } }
-- the questions, drawn three a week; rare: often nobody does it, at most one of those a week
TB.QPOOL = {
  { id = "ding", stat = "ding", text = "Chi sale più livelli?" },
  { id = "q", stat = "q", text = "Chi fa più quest?" },
  { id = "dt", stat = "dt", text = "Chi more de più?" },
  { id = "dg", stat = "dg", text = "Chi fa più dungeon?" },
  { id = "fi", stat = "fi", text = "Chi pesca de più?" },
  { id = "g", stat = "g", text = "Chi fa più sordi?" },
  { id = "tr", stat = "tr", text = "Chi cammina de più?" },
  { id = "pt", stat = "pt", text = "Chi gioca de più?" },
  { id = "ga", stat = { "he", "mi", "sk" }, text = "Chi raccoje de più?" },
  { id = "nk", stat = "nk", text = "Chi ammazza più boss?", wk = 2 },
  { id = "lb", stat = { "lb", "le" }, text = "Chi trova più blu o viola?", wk = 2 },
  { id = "dw", stat = "dw", text = "Chi vince più duelli?", rare = true },
  { id = "em", stat = "em", text = "Chi more più da scemo?", rare = true },
  { id = "rk", stat = "rk", text = "Chi ammazza più rari?", rare = true },
  { id = "fl", stat = "fl", text = "Chi prende più voli?", rare = true, wk = 2 },
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

-- the week the Botteghino plays on: before the start it's already week 1 (the card to look at, the bets to place)
local function Week()
  local wk = RealWeek()
  if wk and wk < 1 then return 1 end
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

local function PoolById(id) for _, sq in ipairs(TB.POOL) do if sq.id == id then return sq end end end

-- the capo's swaps of a week, in order: { { i = square 1..9, id = new square } }
local function Swaps(wk)
  local out = {}
  local list = ns.state and ns.state.settings and ns.state.settings.tc
  for _, x in ipairs(type(list) == "table" and list or {}) do
    if x.wk == wk then out[#out + 1] = x end
  end
  return out
end
TB.Swaps = Swaps

local cards = {}
-- the card as drawn from the sacchetto, before any swap
local function Drawn(wk)
  local key = ns.state.code .. ":" .. wk
  local rnd = Seeded(key)
  local pool = {}
  for _, c in ipairs(TB.POOL) do if (c.wk or 1) <= wk then pool[#pool + 1] = c end end
  local card, used = {}, {}
  while #card < 9 and #pool > 0 do
    local sq = table.remove(pool, rnd(#pool))
    if not used[Group(sq)] then
      used[Group(sq)] = true
      card[#card + 1] = sq
    end
  end
  return card
end
function TB.Card(wk)
  wk = wk or Week()
  if not wk or wk < 1 or not ns.state then return nil end
  local swaps = Swaps(wk)
  local sig = ""
  for _, x in ipairs(swaps) do sig = sig .. x.i .. x.id .. ";" end
  local key = ns.state.code .. ":" .. wk .. ":" .. sig
  if cards[key] then return cards[key] end
  local card = Drawn(wk)
  -- a swap counts only if its square exists and doesn't repeat what another square is about
  for _, x in ipairs(swaps) do
    local sq = PoolById(x.id)
    if sq and card[x.i] then
      local clash = false
      for j, other in ipairs(card) do if j ~= x.i and Group(other) == Group(sq) then clash = true end end
      if not clash then card[x.i] = sq end
    end
  end
  cards[key] = card
  return card
end

-- the capo swaps square i of this week for another one (not about what the other eight are about)
TB.MAX_SWAPS = 3
function TB.CanSwap()
  if not (ns.state and P.HasSettings(ns.state) and ns.CanAdmin and ns.CanAdmin()) or ns.alt then return false end
  local wk = math.max(1, RealWeek() or 1)
  return #Swaps(wk) < TB.MAX_SWAPS, wk
end
function TB.Swap(i)
  local ok, wk = TB.CanSwap()
  if not wk then return false, "Solo er capo pò cambià le caselle." end
  if not ok then return false, "'Sta settimana hai già cambiato " .. TB.MAX_SWAPS .. " caselle." end
  local card = TB.Card(wk)
  local cur = card and card[i]
  if not cur then return false end
  local choices = {}
  for _, sq in ipairs(TB.POOL) do
    if sq.id ~= cur.id and (sq.wk or 1) <= wk then
      local clash = false
      for j, other in ipairs(card) do if j ~= i and Group(other) == Group(sq) then clash = true end end
      if not clash then choices[#choices + 1] = sq end
    end
  end
  if #choices == 0 then return false, "Nun c'è 'n'antra casella da mette." end
  local new = choices[math.random(#choices)]
  local ok2, e = P.EditSettings(ns.state, ns.recordGuid, function(st)
    local kept = {}
    for _, x in ipairs(type(st.tc) == "table" and st.tc or {}) do
      if x.wk >= wk - 1 and not (x.wk == wk and x.i == i) then kept[#kept + 1] = x end
    end
    kept[#kept + 1] = { wk = wk, i = i, id = new.id }
    st.tc = kept
  end)
  if not ok2 then return false, e end
  return true, cur, new
end

local function Value(w, k)
  if type(k) == "table" then
    local s = 0
    for _, x in ipairs(k) do s = s + (w[x] or 0) end
    return s
  end
  return w[k] or 0
end
TB.Value = Value

-- the three questions of a week: { { key = "a", stat, text }, ... }, the same on every computer
local questions = {}
function TB.Questions(wk)
  wk = math.max(1, wk or Week() or 1)
  local key = (ns.state and ns.state.code or "") .. ":q:" .. wk
  if questions[key] then return questions[key] end
  local rnd = Seeded(key)
  local pool = {}
  for _, q in ipairs(TB.QPOOL) do if (q.wk or 1) <= wk then pool[#pool + 1] = q end end
  local out, rare = {}, false
  while #out < #TB.QUESTIONS and #pool > 0 do
    local q = table.remove(pool, rnd(#pool))
    if not (q.rare and rare) then
      rare = rare or q.rare
      out[#out + 1] = { key = TB.QUESTIONS[#out + 1].key, id = q.id, stat = q.stat, text = q.text }
    end
  end
  questions[key] = out
  return out
end
local function QuestionOf(wk, qkey)
  for _, q in ipairs(TB.Questions(wk)) do if q.key == qkey then return q end end
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
-- the book: my piotte
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

-- a piotta for every hour played in a group with someone of the patto
TB.GROUP_HOUR = 3600
function TB.GroupPiotte(rec)
  local gp = rec and rec.stats and rec.stats.t and rec.stats.t.gp or 0
  return math.floor(gp / TB.GROUP_HOUR)
end

-- my balance: start + an hour in a group, a piotta + every week's tombola and winnings - every stake - what I spent
function TB.Balance()
  local b = Book()
  local rec = ns.MyRecord and ns.MyRecord()
  if not (b and rec) then return TB.START end
  local wk = Week() or 0
  local total = TB.START - b.spent + TB.GroupPiotte(rec)
  for w, e in pairs(b.weeks) do if w < wk then total = total + (e.t or 0) + (e.w or 0) end end
  local now = TB.Score(rec, wk)
  total = total + (now and now.points or 0)
  -- stakes are paid when placed (this week's and the open ones)
  for w, s in pairs(b.stakes or {}) do total = total - s end
  -- le sfide and le taje (Sfide.lua)
  if ns.Sfide then total = total + ns.Sfide.Delta() end
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
-- the schedina is open the whole week (and before the start, for week 1); the later you play, the more the odds
-- already know who's ahead
function TB.CanVote()
  local wk = Week()
  if TB.Testing() then return true, wk end
  if not wk or ns.alt then return false end
  return U.Now() < TB.Closes(wk), wk
end

function TB.Closes(wk) return TB.WeekStart(wk) + M.WEEK end

-- pick (guid) and/or stake (any whole number of piotte) for a question; the stake is paid now, a change refunds the old one
function TB.Bet(qkey, guid, stake)
  local ok, wk = TB.CanVote()
  if not ok then return false, "Le giocate so' chiuse." end
  local rec = ns.MyRecord()
  if not rec then return false end
  local cur = TB.VotesOf(rec, wk) or { wk = wk }
  local new = { wk = wk }
  for _, q in ipairs(TB.QUESTIONS) do new[q.key], new["s" .. q.key], new["q" .. q.key] = cur[q.key], cur["s" .. q.key], cur["q" .. q.key] end
  if guid then new[qkey] = guid end
  if not new[qkey] then return false, "Prima scegli su chi giocà." end
  local old = new["s" .. qkey] or 0
  if stake ~= nil then
    stake = tonumber(stake)
    if not stake or stake < 1 then return false, "Scrivi quante piotte ce metti (armeno 1)." end
    stake = math.floor(stake)
  end
  stake = stake or (old > 0 and old or math.min(5, TB.Balance() + old))
  local available = TB.Balance() + old
  if stake < 1 then return false, "Nun c'hai manco 'na piotta." end
  if stake > available then return false, "Nun c'hai abbastanza piotte (" .. available .. ")." end
  new["s" .. qkey] = stake
  -- the odds of this moment are yours (counted without your own old bet)
  local odds = TB.Odds(wk, UI.Members(), qkey, ns.recordGuid)
  new["q" .. qkey] = odds[new[qkey]] and odds[new[qkey]].q or 10
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
  for _, q in ipairs(TB.Questions(wk)) do
    local best = 0
    for _, m in ipairs(list) do best = math.max(best, Value(Weekly(m, wk), q.stat)) end
    out[q.key] = {}
    if best > 0 then
      for _, m in ipairs(list) do if Value(Weekly(m, wk), q.stat) == best then out[q.key][m.guid] = true end end
    end
  end
  return out
end

-- the odds of a question: for every member, what a piotta on them pays (x10, an integer), with the piotte already
-- on them and how many played them. The patto's bets weigh as much as the form once there are HOUSE piotte down.
local HOUSE, EDGE, MINQ, MAXQ = 30, 0.85, 11, 150
function TB.Odds(wk, list, qkey, without)
  local q = QuestionOf(wk, qkey)
  local form, sumForm, staked, count, total = {}, 0, {}, {}, 0
  for _, m in ipairs(list) do
    local f = 1 + Value(Weekly(m, wk), q.stat) + (wk and wk > 1 and Value(Weekly(m, wk - 1), q.stat) or 0)
    form[m.guid] = f
    sumForm = sumForm + f
    local v = m.guid ~= without and TB.VotesOf(m, wk)
    local g = v and v[qkey]
    if g then
      local st = StakeOf(v, qkey)
      staked[g] = (staked[g] or 0) + st
      count[g] = (count[g] or 0) + 1
      total = total + st
    end
  end
  local out = {}
  for _, m in ipairs(list) do
    local p = ((staked[m.guid] or 0) + HOUSE * form[m.guid] / sumForm) / (total + HOUSE)
    local x10 = math.floor(10 * EDGE / p + 0.5)
    out[m.guid] = { q = math.max(MINQ, math.min(MAXQ, x10)), staked = staked[m.guid] or 0, n = count[m.guid] or 0 }
  end
  return out, total
end

-- "2,5"
function TB.Quota(x10) return (string.format("%.1f", (x10 or 10) / 10):gsub("%.", ",")) end

-- what a week paid me: per question the payout at my odds (stakes back when nobody did anything)
function TB.Payout(wk, list, myVotes)
  local win = TB.Winners(wk, list)
  local total, right, lines = 0, 0, {}
  myVotes = myVotes or {}
  for _, q in ipairs(TB.Questions(wk)) do
    local mine = StakeOf(myVotes, q.key)
    local pick = myVotes[q.key]
    local nobody = next(win[q.key]) == nil
    local x10 = myVotes["q" .. q.key]
    if pick and not x10 then local o = TB.Odds(wk, list, q.key) x10 = o[pick] and o[pick].q or 10 end
    local got = 0
    if mine > 0 then
      if nobody then got = mine
      elseif win[q.key][pick] then
        got = math.floor(mine * x10 / 10)
        right = right + 1
      end
    end
    total = total + got
    lines[#lines + 1] = { q = q, got = got, mine = mine, nobody = nobody, winners = win[q.key], quota = x10 }
  end
  return total, right, lines
end

----------------------------------------------------------------------
-- closing the weeks
----------------------------------------------------------------------
-- everything the closing window shows for one week
local function Result(wk, rec, list, mine, sc, test)
  local byGuid = {}
  for _, m in ipairs(list) do byGuid[m.guid] = m end
  local function Name(g) return byGuid[g] and (tostring(byGuid[g].name):match("^(%S+)")) or "?" end
  local won, right, details = TB.Payout(wk, list, mine or {})
  local bets = {}
  for _, d in ipairs(details) do
    local names = {}
    for g in pairs(d.winners) do names[#names + 1] = Name(g) end
    table.sort(names)
    local pick = mine and mine[d.q.key]
    bets[#bets + 1] = { text = d.q.text, winners = names, pick = pick and Name(pick) or nil, stake = d.mine, got = d.got,
      nobody = d.nobody, quota = d.quota, right = pick ~= nil and d.winners[pick] or false }
  end
  sc = sc or { points = 0, cells = 0, lines = 0 }
  return { wk = wk, test = test, tomb = sc, bets = bets, won = won, right = right, total = sc.points + won, played = mine ~= nil }
end
TB.Result = Result

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
  local closed = {}
  for prev = b.closed + 1, wk - 1 do
    if not b.weeks[prev] then
      local sc = TB.Score(rec, prev)
      local mine = TB.VotesOf(rec, prev)
      local res = Result(prev, rec, list, mine, sc, false)
      local won, right = mine and res.won or 0, mine and res.right or 0
      b.weeks[prev] = { t = sc and sc.points or 0, w = won }
      if b.stakes and b.stakes[prev] then b.weeks[prev].s = b.stakes[prev] b.spent = b.spent + b.stakes[prev] b.stakes[prev] = nil end
      b.right = b.right + right
      if res.total > 0 or mine then closed[#closed + 1] = res end
    end
  end
  b.closed = math.max(b.closed, wk - 1)
  local bal = TB.Balance()
  local now = TB.Score(rec, wk)
  local cur = rec.pts or {}
  if cur.t ~= bal or cur.wk ~= wk or cur.w ~= (now and now.points or 0) then
    P.UpdateSelf(ns.state, ns.recordGuid, { pts = { t = bal, w = now and now.points or 0, wk = wk } }, "pts")
  end
  for _, res in ipairs(closed) do
    res.balance = bal
    if ns.News then
      ns.News.Add("Settimana " .. res.wk .. " chiusa: |cffffffff+" .. TB.Piotte(res.total) .. "|r (tombola " .. res.tomb.points ..
        ", Schedina " .. res.won .. ")")
    end
    ns.Fire("WeekClosed", res)
  end
end

-- test mode: close this week now and see what it gives (nothing is kept)
function TB.SimulateClose()
  local wk = Week()
  local rec = ns.MyRecord()
  if not (wk and rec) then return nil end
  local sc = TB.Score(rec, wk) or { points = 0, cells = 0, lines = 0 }
  local list = UI.Members()
  local mine = TB.VotesOf(rec, wk)
  local res = Result(wk, rec, list, mine, sc, true)
  -- the tombola is already in the balance, the stakes already out of it: what changes is the winnings
  res.balance = TB.Balance() + res.won
  local out = {}
  for _, d in ipairs(res.bets) do
    out[#out + 1] = d.text .. " " .. (#d.winners > 0 and table.concat(d.winners, ", ") or "nessuno") ..
      (d.stake > 0 and (d.got > 0 and (" +" .. d.got) or " perso") or "")
  end
  return res.total, sc, res.right, out, res.won, res
end

----------------------------------------------------------------------
-- sfottò: for 3 piotte a line on a friend's screen, written big. The lines come from his own numbers (his
-- deaths, his last words, his level against yours, his quests, his piotte...), so they hit where it hurts; a few
-- plain ones fill in when there's nothing to say. Chosen in a window from the right click menu (Sfide.lua).
----------------------------------------------------------------------
TB.SFOTTI = {
  "Ao, svejate: er cap nun aspetta.",
  "Pure 'n murloc c'ha più grinta de te.",
  "Stai fermo così tanto che te scambiano pe' 'n NPC.",
  "Gioca de più, che er patto te sta a aspettà.",
  "Er cap te guarda e ride.",
  "Te stai a fa' superà da tutti, pure da chi gioca cor gatto in braccio.",
}
local function ShortName(m) return m and (tostring(m.name):match("^(%S+)")) or "?" end
-- three lines for guid, the ones about him first
function TB.SfottiFor(guid)
  local list = UI.Members()
  local m, me
  for _, x in ipairs(list) do if x.guid == guid then m = x end if x.guid == ns.recordGuid then me = x end end
  if not m then return {} end
  me = me or ns.MyRecord()
  local wk = Week()
  local w, mw = TB.Weekly(m, wk), TB.Weekly(me, wk)
  local out = {}
  local function add(t) if #out < 6 then out[#out + 1] = t end end
  local g = m.rip and m.rip[1]
  if g and g.k == "cascato" then add("Cascato da 'n dirupo. La gravità 1, " .. ShortName(m) .. " 0.")
  elseif g and g.k == "affogato" then add("Affogato. Lo sai che se pò pure risalì a respirà?")
  elseif g and g.by then add("T'ha ammazzato " .. g.by .. ". Ma te pare?") end
  if g and g.w then add("Urtime parole: \"" .. g.w:sub(1, 50) .. "\". Ce credo che sei morto.") end
  if (w.dt or 0) >= 2 then add((w.dt or 0) .. " morti 'sta settimana. Ar cimitero t'hanno riservato er posto.") end
  if (w.em or 0) >= 1 then add((w.em or 0) .. " morti da scemo 'sta settimana. Sei 'n artista.") end
  if me and (me.lv or 0) > (m.lv or 0) then add("Livello " .. (m.lv or 1) .. "? Io sto ar " .. me.lv .. ". Te aspetto, eh.") end
  if (mw.q or 0) > (w.q or 0) + 5 then add((mw.q or 0) .. " quest io, " .. (w.q or 0) .. " tu. Ma che fai tutto er giorno?") end
  local h = me and me.h2h and me.h2h[m.name]
  if h and (h.w or 0) > (h.l or 0) then add("A duello te ho battuto " .. h.w .. " vorte. Nun te stanchi?") end
  if ns.Sfide and ns.Sfide.AtGogna(guid) then add("Ancora a la gogna? Te sta proprio bene.") end
  if TB.TotalOf(m) < 10 then add("C'hai " .. TB.Piotte(TB.TotalOf(m)) .. ". Manco pe' 'n supplì.") end
  -- mix the ones about him, keep three, fill with the plain ones
  for i = #out, 2, -1 do local j = math.random(i) out[i], out[j] = out[j], out[i] end
  while #out > 3 do table.remove(out) end
  local pool = {}
  for _, t in ipairs(TB.SFOTTI) do pool[#pool + 1] = t end
  while #out < 3 and #pool > 0 do out[#out + 1] = table.remove(pool, math.random(#pool)) end
  return out
end

local lastSfotto = 0
function TB.Sfotti(guid, text)
  if not (ns.state and guid) or ns.alt then return false end
  if guid == ns.recordGuid then return false, "Nun te poi sfotte da solo." end
  if type(text) == "number" then text = TB.SFOTTI[text] end
  text = type(text) == "string" and text:gsub("|", ""):gsub("[%c]", ""):sub(1, 140) or nil
  if not text or text == "" then return false, "Scegli che je dici." end
  local now = GetTime and GetTime() or 0
  if now - lastSfotto < 30 then return false, "Aspetta 'n attimo prima de sfotte de novo." end
  if TB.Balance() < TB.SFOTTO then return false, "Te servono " .. TB.Piotte(TB.SFOTTO) .. "." end
  lastSfotto = now
  if not TB.Testing() then
    local b = Book()
    b.spent = b.spent + TB.SFOTTO
    ns.C.Send("F", { t = guid, x = text })
    TB.Update()
  end
  return true, text
end

ns.On("Sfotto", function(from, data)
  if type(data) ~= "table" or data.t ~= ns.recordGuid then return end
  local text = type(data.x) == "string" and data.x:gsub("|", ""):gsub("[%c]", ""):sub(1, 140) or nil
  if not text then local p = tonumber(data.p) text = p and TB.SFOTTI[p] end
  if not text or text == "" then return end
  local who = ns.state and ns.state.members[from]
  local name = who and (tostring(who.name):match("^(%S+)")) or "Quarcuno"
  if ns.News then
    ns.News.Banner(name .. " te sfotte:", text, { 1, 0.5, 0.2 }, "evento")
    ns.News.Add("|cffffd100" .. name .. "|r t'ha sfottuto: " .. text)
  end
end)

-- a square swapped by the capo: everybody is told once
local function SwapsSeen(state)
  if state ~= ns.state or not (ns.db and P.HasSettings(state)) then return end
  local wk = math.max(1, RealWeek() or 1)
  ns.db.tcSeen = type(ns.db.tcSeen) == "table" and ns.db.tcSeen or {}
  local seen = ns.db.tcSeen[state.code] or {}
  ns.db.tcSeen[state.code] = seen
  for _, x in ipairs(Swaps(wk)) do
    local key = x.wk .. ":" .. x.i .. ":" .. x.id
    if not seen[key] then
      seen[key] = true
      local sq = PoolById(x.id)
      if sq and ns.News then ns.News.Add("Er capo ha cambiato 'na casella de la tombola: mo' c'è \"" .. sq.t .. "\".") end
    end
  end
end
ns.On("SettingsChanged", function(state) SwapsSeen(state) if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end end)
ns.On("StateChanged", function(state, kind) if kind ~= "M" then SwapsSeen(state) end end)

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
