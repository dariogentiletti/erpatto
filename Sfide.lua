-- Er Patto: er duello a la gogna, le sfide, le taje, le gufate e le scommesse sui duelli.
--
-- Er duello a la gogna (right click on a member): no piotte, only honour. The first duel between the two after the
-- yes counts. The loser can ask for la rivincita within ten minutes; if the other one loses that, he can ask for la
-- bella; after la bella it's over. When it's over (nobody asks, someone says basta, a rivincita refused or not
-- fought, la bella played) the loser goes a la gogna: a day, or a week if he lost a rivincita (or a bella) he asked
-- for himself. The winner then chooses er pegno (a quarter of an hour; if he doesn't, the picture). Whoever is a la
-- gogna can't do duelli a la gogna, and everyone does at most one a day.
-- Er pegno (while a la gogna; the loser sees it as a debuff by the buffs, the patto next to the name and in chat):
--   Er santino      a picture on the loser's screen for the whole gogna (a face and a line the winner chose), the
--                   face's name ("A Pecora") in front of theirs in chat
--   Er burattino    the winner holds the strings: from the right click menu he makes the loser do an emote
--   Er teschio      in a group, out of dungeons, the loser wears the skull raid marker
--   Er verso        a word the winner chose at the end of everything they write in chat
--   La figuraccia   every time they come back to life, their character clucks (or the emote chosen) in front of all
--   Lo strillone    every time they die, the whole patto is told on screen
--   Er servo        "servo de Dario" in front of their name in chat, and they bow every time they target Dario
-- Er Campione: whoever wins a gogna against the champion (or the first one) holds the crown, a title.
--
-- Le sfide (Er Botteghino, piotte only): who does more of something (quest, sordi, pesci...) or reaches the next
-- tenth level first, until the end of the patto week; the winner takes both stakes.
-- La taja: piotte on someone's head; the first to beat them in a duel takes them. La gufata: piotte that someone
-- dies in the next five minutes; if they live they take them, if they die they pay half. Duelli in diretta: when
-- two of the patto start a duel, everyone in the same zone gets a small window to bet on one of the two.
--
-- Everything that lasts travels in the records (gd, gp, sf, sk, tg, gf, dd, rip: see Patto.CleanMember) and every
-- client works out the same results from them; what has to be seen at once also goes as a quick message (kind "X"),
-- kept until the record arrives. Each client keeps its own book of piotte.
local ADDON, ns = ...
local U, M, P, T, UI = ns.U, ns.M, ns.P, ns.T, ns.UI
local H = UI.H
local S = {}
ns.Sfide = S

local DAY = 86400
S.PENDING = DAY           -- a sfida waits a day for the answer
-- the yes is the game's own: the challenge sends the duel request, accepting it is accepting the gogna
S.DUEL_WINDOW = 600       -- the duel after the request counts if it ends within ten minutes
S.RV_ASK = 600            -- the loser has ten minutes to ask for la rivincita (or la bella)
S.RV_FIGHT = 600          -- and it's fought within ten minutes
S.PICK = 900              -- the winner has a quarter of an hour to choose er pegno
S.SHORT, S.LONG = 1, 7    -- days a la gogna
S.TAJA_WINDOW = 7 * DAY
S.GUFA = 300              -- five minutes
S.BET_WINDOW = 600        -- a bet on a duel waits ten minutes for the result
local SLACK = 60

-- the order is the number in the records: new ones go at the end
S.PENE = {
  { key = "img", name = "La pecora",
    tip = "Ogni tanto (in media 'na vorta ogni mezz'ora) pe' 'n minuto, in mezzo a lo schermo suo, 'na pecora co' scritto \"Ricordate che Dario te ha 'mpecorato\"." },
  { key = "pupo", name = "Er burattino", tip = "Tieni li fili: cor tasto destro su de lui, 'na vorta ogni 5 minuti, je fai fà 'n'emote (balla, la gallina, s'inginocchia...) e dì a tutti che se fa tirà li fili; lui sente pure la musica der burattino.",
    icon = "Interface\\Icons\\Spell_Shadow_Charm" },
  { key = "bee", name = "Er verso", ask = "Verso", tip = "'Sta parola a la fine de tutto quello che scrive in chat.",
    icon = "Interface\\Icons\\Ability_Druid_DemoralizingRoar" },
  { key = "cry", name = "Er piagnone", tip = "Ogni du' minuti er personaggio suo piagne davanti a tutti; e si je stai vicino, fa pure \"nguee nguee\".",
    icon = "Interface\\Icons\\Spell_Shadow_DeathScream" },
  { key = "crier", name = "Lo strillone", tip = "Ogni vorta che more, a tutto er patto je compare scritto grosso.",
    icon = "Interface\\Icons\\Ability_Warrior_BattleShout" },
  { key = "servo", name = "Er servo", tip = "In chat è \"servo de\" chi l'ha battuto; quanno je sta vicino je s'inchina, e 'na vorta ogni dieci minuti dice a tutti \"is the slave of\" er padrone.",
    icon = "Interface\\Icons\\Spell_Holy_SealOfSalvation" },
  { key = "kara", name = "Er karaoke", tip = "A ogni mostro che ammazza parte 'na canzoncina (a vorte lenta, a vorte veloce, mai due insieme): la sente solo lui.",
    icon = "Interface\\Icons\\INV_Misc_Drum_01" },
  { key = "giampy", name = "Er Giampaolato", tip = "Ogni vorta che zompa se sente \"ahia!\" (o \"basta!\"); e quanno ringrazia quarcuno (/thanks) parte er Cerbero, pe' lui e pe' chi ha ringraziato.",
    icon = "Interface\\Icons\\Spell_Holy_Silence" },
}
S.WAITING_ICON = "Interface\\Icons\\INV_Misc_QuestionMark" -- a la gogna, er pegno still to choose
-- the faces of er santino (and their name in chat)
S.FIGURE = {
  { name = "La pecora", icon = "Interface\\Icons\\Spell_Nature_Polymorph", say = "Ha perso e mo' fa bee.", verb = "'mpecorato" },
}
S.EMOTES = {
  { tok = "CHICKEN", name = "Fa la gallina" },
  { tok = "KNEEL", name = "S'inginocchia" },
  { tok = "CRY", name = "Piagne" },
  { tok = "SURRENDER", name = "Se arrende" },
  { tok = "FLEX", name = "Fa er bullo" },
  { tok = "SILLY", name = "Fa lo scemo" },
}
S.STATS = {
  { key = "q", name = "Quest" }, { key = "g", name = "Sordi" }, { key = "fi", name = "Pesci" },
  { key = "ga", name = "Raccolta" }, { key = "tr", name = "Strada" }, { key = "dg", name = "Dungeon" },
  { key = "rk", name = "Rari" }, { key = "nk", name = "Boss" }, { key = "dt", name = "Morti", low = true },
}

local GREY, GOLD = "|cff9d9d9d", "|cffffd100"
local function Now() return U.Now() end
local function Short(m) return (tostring(m and m.name or "?"):match("^(%S+)")) or "?" end
local function StatOf(key) for _, x in ipairs(S.STATS) do if x.key == key then return x end end end
local function Hash(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end return h end
local function Figure(id, e) return S.FIGURE[tonumber(e) or 0] or S.FIGURE[(Hash(tostring(id)) % #S.FIGURE) + 1] end
S.Figure = Figure
local function Members()
  local out = {}
  if not ns.state then return out end
  for guid, m in pairs(ns.state.members) do out[guid] = m end
  for _, m in ipairs(UI.Members()) do out[m.guid] = m end -- test members too
  return out
end
S.Members = Members
local function Piotte(n) return ns.Tombola and ns.Tombola.Piotte(n) or (n .. " piotte") end
local function Span(long) return long and "'na settimana" or "'n giorno" end
-- nothing goes to the chat: errors and confirmations are written in the window they come from
-- why nothing can be done here: with an alt, or before joining a patto
local function NoPlay()
  if ns.alt then return false, "Co' 'n alt nun se pò: usa er personaggio der patto." end
  return false, "Prima entra in un patto."
end
local function Report(d, ok, msg)
  if d and d.err then d.err:SetText(ok and "" or (msg or "Nun se pò.")) end
  return ok
end
-- the epic call: the battleground horn of the old game, when someone wants you at the gogna
local function Epic()
  if not PlaySound then return end
  pcall(PlaySound, (SOUNDKIT and SOUNDKIT.PVP_THROUGH_QUEUE) or 8459, "Master")
end
S.Epic = Epic

----------------------------------------------------------------------
-- my book: what I paid in and got back
----------------------------------------------------------------------
local function Store()
  if not (ns.db and ns.state) then return nil end
  ns.db.sfide = type(ns.db.sfide) == "table" and ns.db.sfide or {}
  -- in test mode a book of its own, as the tombola's (Tombola.BookKey)
  local key = ns.Tombola and ns.Tombola.BookKey and ns.Tombola.BookKey() or ns.state.code
  local s = ns.db.sfide[key]
  if type(s) ~= "table" then s = {} ns.db.sfide[key] = s end
  s.res = s.res or {}     -- id -> the result, once known
  s.book = s.book or {}   -- id -> { s = paid, got = back }
  s.told = s.told or {}   -- what we already announced
  s.asked = s.asked or {} -- sfide already shown in a dialog
  s.bets = s.bets or {}   -- my bets on duels
  return s
end
S.Store = Store

-- my book as lines: { at, k, o, s (paid), g (got back, nil while open) }
function S.Ledger()
  local st = Store()
  local out = {}
  if not st then return out end
  local known = {}
  for _, c in ipairs(S.All()) do known[c.id] = { k = "sf", o = (c.from == ns.recordGuid) and c.to or c.from, at = c.at } end
  for _, t in ipairs(S.Taje()) do known[t.id] = { k = "tj", o = t.on, at = t.at } end
  for _, g in ipairs(S.Gufate()) do known[g.id] = { k = "gu", o = g.on, at = g.at } end
  for id, b in pairs(st.bets) do known[id] = { k = "sb", o = b.pick, at = b.at } end
  for id, e in pairs(st.book) do
    local x = known[id] or {}
    out[#out + 1] = { at = e.gt or e.at or x.at or 0, k = e.k or x.k or "sf", o = e.o or x.o, s = e.s or 0, g = e.got }
  end
  return out
end

function S.Delta()
  local st = Store()
  if not st then return 0 end
  local d = 0
  for _, e in pairs(st.book) do d = d - (e.s or 0) + (e.got or 0) end
  return d
end
-- every line of the book keeps what it was (k), with whom (o) and when (at, and gt when it was paid back): the
-- Scontrini page lists them
local function Pay(id, s, k, o)
  local st = Store()
  local e = st.book[id] or { s = 0 }
  st.book[id] = e
  e.s, e.k, e.o, e.at = s, k or e.k, o or e.o, e.at or Now()
end
local function Got(id, n, k, o)
  local st = Store()
  local e = st.book[id] or { s = 0, k = k, o = o, at = Now() }
  st.book[id] = e
  if e.got == nil then e.got, e.gt = n, Now() end
end
local function Balance() return ns.Tombola and ns.Tombola.Balance() or 0 end

----------------------------------------------------------------------
-- reading the records (and the quick messages not yet in a record)
----------------------------------------------------------------------
local liveSf, liveGd, liveAns, livePick, liveGf = {}, {}, {}, {}, {}

-- the sfide a piotte
function S.All()
  local out, seen = {}, {}
  for guid, m in pairs(Members()) do
    for _, c in ipairs(m.sf or {}) do if c.id then seen[c.id] = true end end
    for _, c in ipairs(m.sf or {}) do
      local k, st = c.k, c.st
      if k == "q" then k, st = "s", "q" end -- the old quest sfida
      if k == "s" or k == "l" then
        out[#out + 1] = { id = c.id, from = guid, to = c.to, k = k, n = c.n, s = c.s or 0, st = st, at = c.at or 0 }
      end
    end
  end
  for id, c in pairs(liveSf) do if not seen[id] then out[#out + 1] = c end end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

-- the records keep only the last four of each; what we saw before is kept here (the last 40, two weeks), so the
-- list of taje and gufate shows them all
local function Lists(key, field)
  local out, seen = {}, {}
  local st = Store()
  local arch
  if st then
    st.arch = type(st.arch) == "table" and st.arch or {}
    st.arch[key] = type(st.arch[key]) == "table" and st.arch[key] or {}
    arch = st.arch[key]
  end
  for guid, m in pairs(Members()) do
    for _, x in ipairs(m[key] or {}) do
      local y = {}
      for k, v in pairs(x) do y[k] = v end
      y[field] = guid
      out[#out + 1] = y
      if y.id then seen[y.id] = true if arch then arch[y.id] = y end end
    end
  end
  if arch then
    local n, oldest = 0, nil
    for id, y in pairs(arch) do
      if Now() - (y.at or 0) > 14 * DAY then arch[id] = nil
      else
        n = n + 1
        if not seen[id] then out[#out + 1] = y end
      end
    end
    while n > 40 do
      oldest = nil
      for id, y in pairs(arch) do if not oldest or (y.at or 0) < (arch[oldest].at or 0) then oldest = id end end
      arch[oldest] = nil n = n - 1
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end
function S.Taje() return Lists("tg", "by") end
function S.Gufate()
  local out = Lists("gf", "by")
  local seen = {}
  for _, g in ipairs(out) do seen[g.id] = true end
  for id, g in pairs(liveGf) do if not seen[id] then out[#out + 1] = g end end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

-- the answer to a sfida or a duello a la gogna, from the one it was thrown at
local function Ans(c, all)
  local m = all[c.to]
  for _, a in ipairs(m and m.sk or {}) do if a.id == c.id then return a end end
  local l = liveAns[c.id]
  if l and l.by == c.to then return l end
  return nil
end

-- the first duel between a and b at or after t: winner, loser, when
local function FirstDuel(all, a, b, t)
  local best
  for _, pair in ipairs({ { a, b }, { b, a } }) do
    local m = all[pair[1]]
    for _, d in ipairs(m and m.dd or {}) do
      if d.o == pair[2] and (d.at or 0) >= t and (not best or d.at < best.at) then
        best = { at = d.at, w = d.w == 1 and pair[1] or pair[2], l = d.w == 1 and pair[2] or pair[1] }
      end
    end
  end
  return best
end
S.FirstDuel = FirstDuel

local function FirstBeat(all, x, t)
  local best
  for guid, m in pairs(all) do
    for _, d in ipairs(m.dd or {}) do
      if (d.at or 0) >= t then
        local w
        if guid ~= x and d.o == x and d.w == 1 then w = guid end
        if guid == x and d.w == 0 then w = d.o end
        if w and (not best or d.at < best.at) then best = { w = w, at = d.at } end
      end
    end
  end
  return best
end

-- a member's total of a counter (raccolta: herbs, ore and skins together)
function S.Total(m, key)
  local t = m and m.stats and m.stats.t or {}
  if key == "ga" then return (t.he or 0) + (t.mi or 0) + (t.sk or 0) end
  return t[key] or 0
end

function S.Fmt(key, n)
  if key == "g" then return ns.Money and ns.Money(n, true) or (math.floor(n / 10000) .. " oro") end
  if key == "tr" then return string.format("%.1f km", n * 0.0009144) end
  return tostring(n)
end

-- a sfida runs until the end of the patto week it was accepted in
function S.EndOf(t)
  if ns.state and P.HasSettings(ns.state) then
    local wk = M.WeekIndex(ns.state.settings, t)
    return ns.state.settings.start + wk * M.WEEK
  end
  return t + 7 * DAY
end

-- where a sfida stands: "aspetta", "rifiutata", "scaduta", "incorso", "finita" (+ the result, + the answer)
function S.State(c, all)
  all = all or Members()
  local st = Store()
  local res = st and st.res[c.id]
  local ans = Ans(c, all)
  if res then return "finita", res, ans end
  local now = Now()
  if not ans then return (now - c.at > S.PENDING) and "scaduta" or "aspetta", nil, nil end
  if ans.a ~= 1 then return "rifiutata", nil, ans end
  local t0 = ans.at or c.at
  local e = ans.e or S.EndOf(t0)
  local r
  if c.k == "l" then
    local a, b = all[c.from], all[c.to]
    local ta, tb = a and a.ms and a.ms[c.n], b and b.ms and b.ms[c.n]
    if ta and ta > e then ta = nil end
    if tb and tb > e then tb = nil end
    if ta and (not tb or ta < tb) then r = { w = c.from, l = c.to, at = ta }
    elseif tb and (not ta or tb < ta) then r = { w = c.to, l = c.from, at = tb }
    elseif ta and tb then r = { w = "", at = ta }
    elseif now > e + 1800 then r = { w = "", at = e } end
  else
    local a, b = all[c.from], all[c.to]
    local fresh = a and b and (a.up or 0) >= e and (b.up or 0) >= e
    if now > e and (fresh or now > e + 1800) then
      local da = S.Total(a, c.st) - (ans.sa or 0)
      local db = S.Total(b, c.st) - (ans.sb or 0)
      local low = StatOf(c.st) and StatOf(c.st).low
      if da == db then r = { w = "", at = e, da = da, db = db }
      elseif (da > db) ~= (low and true or false) then r = { w = c.from, l = c.to, at = e, da = da, db = db }
      else r = { w = c.to, l = c.from, at = e, da = da, db = db } end
    end
  end
  if r then
    if st then st.res[c.id] = r end
    return "finita", r, ans
  end
  return "incorso", nil, ans
end

function S.TajaState(t, all)
  all = all or Members()
  local st = Store()
  local res = st and st.res[t.id]
  if res then return "finita", res end
  local b = FirstBeat(all, t.on, t.at)
  local r
  if b then r = { w = b.w, l = t.on, at = b.at }
  elseif Now() - t.at > S.TAJA_WINDOW then r = { w = "", at = t.at + S.TAJA_WINDOW } end
  if r then
    if st then st.res[t.id] = r end
    return "finita", r
  end
  return "aperta"
end

-- a gufata: "morto" (died in the five minutes) or "campato"
function S.GufaState(g, all)
  all = all or Members()
  local st = Store()
  local res = st and st.res[g.id]
  if res then return res.w, res end
  local m = all[g.on]
  local died
  for _, r in ipairs(m and m.rip or {}) do if r.at >= g.at and r.at <= g.at + S.GUFA then died = r.at end end
  if not died and m and m.dat and m.dat >= g.at and m.dat <= g.at + S.GUFA then died = m.dat end
  local r
  if died then r = { w = "morto", at = died }
  elseif Now() > g.at + S.GUFA and m and (m.up or 0) >= g.at + S.GUFA + 30 then
    -- his record from after the five minutes is here, with no death in it: he lived
    r = { w = "campato", at = g.at + S.GUFA }
  elseif Now() > g.at + 3600 then
    r = { w = "nullo", at = g.at + 3600 } -- nothing heard from him in an hour: stakes back
  end
  if r then
    if st then st.res[g.id] = r end
    return r.w, r
  end
  return "aperta"
end

----------------------------------------------------------------------
-- er duello a la gogna: each one is a series (duel, rivincita, bella) followed from the records
----------------------------------------------------------------------
-- every challenge a la gogna: id -> { id, from, to, rv (the previous one), x (1: "basta"), at }
function S.GdAll()
  local out = {}
  for guid, m in pairs(Members()) do
    for _, x in ipairs(m.gd or {}) do
      if x.id then out[x.id] = { id = x.id, from = guid, to = x.to, rv = x.rv, x = x.x, at = x.at or 0 } end
    end
  end
  for id, x in pairs(liveGd) do if not out[id] then out[id] = x end end
  return out
end

local function PickOf(s, all)
  local m = all[s.w]
  local best
  for _, x in ipairs(m and m.gp or {}) do if x.id == s.id then best = x end end
  if not best then local l = livePick[s.id] if l and l.by == s.w then best = l end end
  if best and (best.at or 0) <= s.te + S.PICK + SLACK and S.PENE[best.p or 0] then return best end
  return nil
end

-- states: "incorso" (the duel request is out, the duel to be fought: s.cur), "rivincita" (the loser of
-- s.last may ask), "chiusa" (s.w, s.l, s.te: when it closed, s.til: end of the gogna, s.long, s.pena, s.pick),
-- "rifiutata", "scaduta", "nunfatto" (accepted, never fought). s.duels: the duels fought, s.ids: their challenges.
function S.Series(all)
  all = all or Members()
  local gd = S.GdAll()
  local nexts = {}
  for _, x in pairs(gd) do
    if x.rv then nexts[x.rv] = nexts[x.rv] or {} table.insert(nexts[x.rv], x) end
  end
  local now = Now()
  local out = {}
  for _, root in pairs(gd) do
    if not root.rv and not root.x then
      local s = { id = root.id, a = root.from, b = root.to, at = root.at, duels = {}, ids = {}, reqs = {} }
      local function Close(te, why)
        local d = s.duels[#s.duels]
        s.state, s.w, s.l, s.te, s.why = "chiusa", d.w, d.l, te, why
        s.long = #s.duels > 1 and d.asker == d.l
        s.til = te + (s.long and S.LONG or S.SHORT) * DAY
      end
      local cur, n = root, 1
      while cur do
        s.ids[n] = cur.id
        s.reqs[n] = { id = cur.id, from = cur.from, to = cur.to, at = cur.at }
        local fightWin = n == 1 and S.DUEL_WINDOW or S.RV_FIGHT
        local t0 = cur.at
        local prev = s.duels[n - 1]
        local d = FirstDuel(all, cur.from, cur.to, math.max(t0 - SLACK, prev and (prev.at + 1) or 0))
        if d and d.at > t0 + fightWin then d = nil end
        if not d then
          -- the duel request turned down (x = 2, written by either of the two), or never fought
          local off
          for _, x in ipairs(nexts[cur.id] or {}) do if x.x == 2 and x.at >= t0 - SLACK then off = x end end
          if off then s.refused = { n = n, id = cur.id, from = cur.from, to = cur.to, at = off.at } end
          if not off and now - t0 <= fightWin then s.state, s.cur, s.n = "incorso", cur, n
          elseif n == 1 then s.state = "nunfatto"
          else Close(off and off.at or (t0 + fightWin), "no") end
          break
        end
        s.duels[n] = { w = d.w, l = d.l, at = d.at, asker = cur.from }
        if n >= 3 then Close(d.at, "bella") break end
        local nx
        for _, x in ipairs(nexts[cur.id] or {}) do
          if x.from == d.l and x.x ~= 2 and x.at >= d.at - SLACK and x.at <= d.at + S.RV_ASK + SLACK and (not nx or x.at < nx.at) then nx = x end
        end
        if nx and nx.x then Close(nx.at, "basta") break end
        if nx then
          cur, n = nx, n + 1
        elseif now - d.at <= S.RV_ASK then
          s.state, s.n, s.last = "rivincita", n, d
          break
        else
          Close(d.at + S.RV_ASK, "tempo")
          break
        end
      end
      if s.state == "chiusa" then
        s.pick = PickOf(s, all)
        if s.pick then s.pena, s.t, s.e = s.pick.p, s.pick.t, s.pick.e
        elseif now > s.te + S.PICK then s.pena = 1 end -- he didn't choose: the picture
      end
      out[#out + 1] = s
    end
  end
  table.sort(out, function(x, y) return (x.at or 0) > (y.at or 0) end)
  return out
end

-- why guid can't do a duello a la gogna now: "aperto", "gogna" (+ until), or nil. Whoever wins can go on
-- winning: no daily limit
local function Block(guid, series, except)
  local now = Now()
  local why, til
  for _, s in ipairs(series) do
    if s.id ~= except and (s.a == guid or s.b == guid) then
      if s.state == "aspetta" or s.state == "incorso" or s.state == "rivincita" then return "aperto" end
      if s.state == "chiusa" and s.l == guid and now < s.til then return "gogna", s.til end
    end
  end
  return why, til
end
S.Block = Block

local function BlockText(guid, series, all, except)
  local why, til = Block(guid, series, except)
  if not why then return nil end
  if guid == ns.recordGuid then
    if why == "aperto" then return "C'hai già 'n duello a la gogna in ballo." end
    return "Stai a la gogna fino a " .. U.When(til) .. "."
  end
  local name = Short(all[guid])
  if why == "aperto" then return name .. " c'ha già 'n duello a la gogna in ballo." end
  return name .. " sta già a la gogna."
end
S.BlockText = BlockText

----------------------------------------------------------------------
-- who is a la gogna, with which pegno (and how many times each one went)
----------------------------------------------------------------------
local gogne, nicks, verses, shame, criers, servants, atGogna, goats = {}, {}, {}, {}, {}, {}, {}, {}
local series = {}
local champion
local test = {}
function S.Champion() return champion end
function S.GognaOf(rec) local g = rec and gogne[rec.guid] if g and Now() < g.til then return g end end
function S.NickOf(rec) local g = rec and nicks[rec.guid] if g and Now() < g.til then return g end end
function S.VerseOf(rec) local g = rec and verses[rec.guid] if g and Now() < g.til then return g end end
function S.CrierOf(rec) local g = rec and criers[rec.guid] if g and Now() < g.til then return g end end
function S.ServoOf(rec) local g = rec and servants[rec.guid] if g and Now() < g.til then return g end end
function S.ShameOf(guid) return shame[guid] or 0 end
-- a la gogna now: { til, by, long, s (the series) }
function S.AtGogna(guid) local g = guid and atGogna[guid] if g and Now() < g.til then return g end end
function S.Last() return series end

-- "Er soprannome "Pippa"", "La maschera: A Pecora", "Er servo de Dario"
function S.PegnoText(s, all)
  local pena = S.PENE[s.pena or 0]
  if not pena then return nil end
  if pena.key == "img" then return pena.name end
  if pena.key == "bee" then return pena.name .. " \"" .. tostring(s.t or "?") .. "\"" end
  if pena.key == "servo" then return pena.name .. " de " .. Short((all or Members())[s.w]) end
  return pena.name
end
-- er pegno told to whoever has it: what happens to them, in plain words
function S.PegnoYou(s, all)
  all = all or Members()
  local pena = S.PENE[s.pena or 0]
  if not pena then return nil end
  local by = Short(all[s.w])
  if pena.key == "img" then
    local f = Figure(s.id, s.e)
    return "Ogni tanto (in media 'na vorta ogni mezz'ora), pe' 'n minuto, te compare 'na pecora in mezzo a lo schermo, co' scritto \"Ricordate che " .. by .. " te ha 'mpecorato\". Nun la poi levà."
  elseif pena.key == "kara" then
    return "A ogni mostro che ammazzi parte 'na canzoncina (a vorte lenta, a vorte veloce, una pe' vorta). La senti solo te."
  elseif pena.key == "giampy" then
    return "Sei giampaolato: ogni vorta che zompi senti \"ahia!\" (o \"basta!\"); e quanno ringrazi quarcuno (/thanks) parte er Cerbero, pe' te e pe' chi hai ringraziato, si è der patto."
  elseif pena.key == "pupo" then
    return "Sei er burattino de " .. by .. ": 'na vorta ogni 5 minuti te tira li fili, e er personaggio tuo balla, fa la gallina, s'inginocchia... davanti a tutti, co' la musica der burattino."
  elseif pena.key == "bee" then
    return "A la fine de tutto quello che scrivi in chat, l'amichi der patto leggono \"" .. tostring(s.t) .. "\"."
  elseif pena.key == "cry" then
    return "Sei er piagnone: ogni du' minuti er personaggio tuo piagne davanti a tutti, e quanno stai vicino a " .. by .. " fa pure \"nguee nguee\"."
  elseif pena.key == "crier" then
    return "Ogni vorta che mori, a tutto er patto je compare scritto grosso sur su' schermo."
  elseif pena.key == "servo" then
    return "In chat, davanti ar nome tuo, l'amichi der patto leggono [servo de " .. by .. "]. Quanno je stai vicino je t'inchini, e 'na vorta ogni dieci minuti tutti leggono \"" .. ((ns.MyRecord and Short(ns.MyRecord())) or "") .. " is the slave of " .. by .. ".\""
  end
end

-- the face of a pegno: the animal of the mask, the icon of the others, a question mark while it's being chosen
function S.PegnoIcon(s)
  local pena = S.PENE[s.pena or 0]
  if not pena then return S.WAITING_ICON end
  if pena.key == "img" then return Figure(s.id, s.e).icon end
  return pena.icon
end

local function keep(map, guid, x)
  if Now() >= x.til then return end
  if not map[guid] or x.til > map[guid].til then map[guid] = x end
end
-- what a gogna does to its loser, while it lasts
local function Apply(s, all)
  keep(atGogna, s.l, { til = s.til, by = s.w, long = s.long, s = s })
  local why = "ha perso a la gogna co' " .. Short(all[s.w])
  local pena = S.PENE[s.pena or 0]
  if pena and pena.key == "bee" and s.t then
    keep(verses, s.l, { t = s.t, til = s.til, why = why, by = s.w })
  elseif pena and pena.key == "crier" then
    keep(criers, s.l, { from = s.te, til = s.til, by = s.w })
  elseif pena and pena.key == "servo" then
    keep(servants, s.l, { til = s.til, by = s.w, name = Short(all[s.w]) })
  end
end

local function Rebuild()
  gogne, nicks, verses, shame, criers, servants, atGogna, goats = {}, {}, {}, {}, {}, {}, {}, {}
  local all = Members()
  series = S.Series(all)
  local crowns = {}
  for _, s in ipairs(series) do
    if s.state == "chiusa" then
      shame[s.l] = (shame[s.l] or 0) + 1
      crowns[#crowns + 1] = { w = s.w, l = s.l, at = s.te }
      Apply(s, all)
    end
  end
  -- the crown: through the gogne in order, it goes to whoever beats the one holding it
  table.sort(crowns, function(a, b) return a.at < b.at end)
  champion = nil
  for _, d in ipairs(crowns) do
    if not champion or champion == d.l or champion == d.w then champion = d.w end
  end
  -- test mode: a gogna of two minutes on me
  if test.s and ns.recordGuid and Now() < test.s.til then
    test.s.l = ns.recordGuid
    for _, map in ipairs({ gogne, nicks, verses, criers, servants, atGogna, goats }) do map[ns.recordGuid] = nil end
    Apply(test.s, all)
  end
end
S.Rebuild = Rebuild

----------------------------------------------------------------------
-- doing things
----------------------------------------------------------------------
local function MyList(key)
  local rec = ns.MyRecord and ns.MyRecord()
  local out = {}
  for _, x in ipairs(rec and rec[key] or {}) do out[#out + 1] = x end
  return out, rec
end
local function NewId() return (tostring(ns.recordGuid):sub(-6)) .. ":" .. tostring(math.floor(Now())) .. ":" .. math.random(100, 999) end
local function Send(data) if ns.C and ns.C.Send then pcall(ns.C.Send, "X", data) end end
local function Clean(t)
  t = tostring(t or ""):gsub("|", ""):gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
  return t ~= "" and t:sub(1, 20) or nil
end
local function FindSeries(id)
  for _, s in ipairs(S.Series()) do if s.id == id then return s end end
end

-- find a unit token for a name nearby (to start the duel request)
local function UnitFor(name)
  if not (UnitName and name) then return nil end
  local short = tostring(name):match("^(%S+)")
  local tokens = { "target", "mouseover", "focus" }
  for i = 1, 4 do tokens[#tokens + 1] = "party" .. i end
  for i = 1, 40 do tokens[#tokens + 1] = "raid" .. i end
  for i = 1, 40 do tokens[#tokens + 1] = "nameplate" .. i end
  for _, u in ipairs(tokens) do
    local ok, n = pcall(UnitName, u)
    if ok and n and not U.IsSecret(n) and (n == name or n == short) then return u end
  end
end

-- send the game's duel request to a member (from a click: the game wants a hardware event); hint: a unit token
local function StartTheDuel(guid, hint)
  local m = Members()[guid]
  if not m then return false, "Nun è der patto." end
  if not StartDuel then return false, "Er duello nun pò partì." end
  local u
  if hint and UnitName then
    local ok, n = pcall(UnitName, hint)
    if ok and n and not U.IsSecret(n) and (n == m.name or n == Short(m)) then u = hint end
  end
  u = u or UnitFor(m.name)
  if not u then return false, Short(m) .. " nun è qui vicino: mettilo ner mirino e riprova." end
  if not pcall(StartDuel, u) then return false, "Er duello nun è partito: riprova." end
  return true
end

local function SaveAnswer(id, yes, extra)
  local a = { id = id, a = yes and 1 or 0, at = Now() }
  for k, v in pairs(extra or {}) do a[k] = v end
  local keep = { a }
  for _, x in ipairs(MyList("sk")) do if #keep < 10 and x.id ~= id then keep[#keep + 1] = x end end
  P.UpdateSelf(ns.state, ns.recordGuid, { sk = keep }, "sfide")
  Send({ t = "ans", id = id, a = yes and 1 or 0 })
end

local function SaveGd(c)
  local keep = { c }
  for _, x in ipairs(MyList("gd")) do if #keep < 6 then keep[#keep + 1] = x end end
  P.UpdateSelf(ns.state, ns.recordGuid, { gd = keep }, "sfide")
  Send({ t = "gd", c = c })
end

-- throw a duello a la gogna
function S.Gogna(to, unit)
  if not ns.state or ns.alt then return NoPlay() end
  local all = Members()
  if not all[to] or to == ns.recordGuid then return false, "Scegli chi sfidà." end
  local list = S.Series(all)
  local why = BlockText(ns.recordGuid, list, all) or BlockText(to, list, all)
  if why then return false, why end
  local ok, e = StartTheDuel(to, unit)
  if not ok then return false, e end
  local c = { id = NewId(), to = to, at = Now() }
  SaveGd(c)
  S.Live(ns.recordGuid, to, true)
  S.Update()
  return true, c
end

-- the loser asks for la rivincita (or la bella), or says basta
function S.Rematch(sid, basta)
  if not ns.state or ns.alt then return NoPlay() end
  local s = FindSeries(sid)
  if not (s and s.state == "rivincita" and s.last.l == ns.recordGuid) then return false, "Nun c'è più niente da chiede." end
  if not basta then
    local ok, e = StartTheDuel(s.last.w)
    if not ok then return false, e end
  end
  local c = { id = NewId(), to = s.last.w, rv = s.ids[s.n], x = basta and 1 or nil, at = Now() }
  SaveGd(c)
  if not basta then S.Live(ns.recordGuid, s.last.w, true) end
  S.Update()
  return true, c
end

-- the duel request was turned down (DUEL_FINISHED with no winner): the gogna isn't on
local function TurnedDown()
  local me = ns.recordGuid
  for _, x in ipairs(S.Series()) do
    if x.state == "incorso" and (x.cur.from == me or x.cur.to == me) and Now() - x.cur.at > 2 then
      SaveGd({ id = NewId(), to = x.cur.from == me and x.cur.to or x.cur.from, rv = x.cur.id, x = 2, at = Now() })
      S.Update()
    end
  end
end

-- the winner chooses er pegno
function S.Pick(sid, p, t, e)
  if not ns.state or ns.alt then return NoPlay() end
  local s = FindSeries(sid)
  if not (s and s.state == "chiusa" and s.w == ns.recordGuid) then return false, "Nun c'è pegno da sceje." end
  if s.pick then return false, "Er pegno l'hai già scelto." end
  if Now() > s.te + S.PICK then return false, "Troppo tardi: j'è toccato er santino." end
  local pena = S.PENE[tonumber(p) or 0]
  if not pena then return false, "Scegli er pegno." end
  local text = Clean(t)
  if pena.ask and not pena.opt and not text then return false, "Scrivi " .. pena.ask:lower() .. "." end
  local x = { id = sid, p = tonumber(p), t = pena.ask and text or nil, e = nil, at = Now() }
  local keep = { x }
  for _, y in ipairs(MyList("gp")) do if #keep < 4 and y.id ~= sid then keep[#keep + 1] = y end end
  P.UpdateSelf(ns.state, ns.recordGuid, { gp = keep }, "sfide")
  Send({ t = "gp", x = x })
  S.Update()
  return true
end

function S.RaceLevel(other)
  local me = ns.MyRecord()
  local top = math.max(me and me.lv or 1, other and other.lv or 1)
  local n = (math.floor(top / 10) + 1) * 10
  return n <= 60 and n or nil
end

local function Open(all, a, b)
  for _, c in ipairs(S.All()) do
    local st = S.State(c, all)
    if (st == "aspetta" or st == "incorso") and ((c.from == a and c.to == b) or (c.from == b and c.to == a)) then return c end
  end
end

-- a sfida a piotte. o: { to, k ("s": who does more, "l": the race to the level), st (the counter), s (stake) }
function S.Challenge(o)
  if not ns.state or ns.alt then return NoPlay() end
  local all = Members()
  local other = all[o.to]
  if not other or o.to == ns.recordGuid then return false, "Scegli chi sfidà." end
  if ns.Tombola and ns.Tombola.Mine(o.to) then return false, "Co' 'n alt tuo nun se fanno sfide." end
  if o.k ~= "l" and not (o.k == "s" and StatOf(o.st)) then return false, "Scegli su che." end
  local stake = math.floor(tonumber(o.s) or 0)
  if stake < 1 then return false, "Metti armeno 'na piotta." end
  if stake > Balance() then return false, "Nun c'hai abbastanza piotte." end
  local n
  if o.k == "l" then
    n = S.RaceLevel(other)
    if not n then return false, "Ar 60 nun se corre più." end
  end
  if Open(all, ns.recordGuid, o.to) then return false, "Co' " .. Short(other) .. " c'è già 'na sfida aperta." end
  local c = { id = NewId(), to = o.to, k = o.k, n = n, st = o.k == "s" and o.st or nil, s = stake, at = Now() }
  local keep = { c }
  for _, x in ipairs(MyList("sf")) do if #keep < 6 then keep[#keep + 1] = x end end
  Pay(c.id, stake, "sf", o.to)
  P.UpdateSelf(ns.state, ns.recordGuid, { sf = keep }, "sfide")
  Send({ t = "sf", c = c })
  S.Update()
  return true, c
end

function S.Answer(id, yes, c)
  if not ns.state or ns.alt then return NoPlay() end
  local all = Members()
  if not c then for _, x in ipairs(S.All()) do if x.id == id then c = x end end end
  if not c or c.to ~= ns.recordGuid then return false, "'Sta sfida nun è pe' te." end
  if Ans(c, all) then return false, "Hai già risposto." end
  if c.at and Now() - c.at > S.PENDING then return false, "'Sta sfida è scaduta." end
  if yes and c.s > Balance() then return false, "Nun c'hai abbastanza piotte pe' 'sta posta." end
  local extra
  if yes then
    local now = Now()
    extra = { e = S.EndOf(now) }
    if c.k == "s" then extra.sa, extra.sb = S.Total(all[c.from], c.st), S.Total(all[c.to], c.st) end
    Pay(id, c.s, "sf", c.from)
  end
  SaveAnswer(id, yes, extra)
  S.Update()
  return true
end

function S.Taja(on, stake)
  if not ns.state or ns.alt then return NoPlay() end
  local all = Members()
  if not all[on] then return false, "Scegli su chi." end
  if ns.Tombola and ns.Tombola.Mine(on) then return false, "La taja su te stesso (o su 'n alt tuo) nun se pò mette." end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 1 then return false, "La taja è armeno 'na piotta." end
  if stake > Balance() then return false, "Nun c'hai abbastanza piotte." end
  local t = { id = NewId(), on = on, s = stake, at = Now() }
  local keep = { t }
  for _, x in ipairs(MyList("tg")) do if #keep < 4 then keep[#keep + 1] = x end end
  Pay(t.id, stake, "tj", on)
  P.UpdateSelf(ns.state, ns.recordGuid, { tg = keep }, "sfide")
  S.Update()
  return true
end

function S.Gufa(on, stake)
  if not ns.state or ns.alt then return NoPlay() end
  local all = Members()
  local m = all[on]
  if not m or on == ns.recordGuid then return false, "Scegli a chi gufà." end
  if ns.Tombola and ns.Tombola.Mine(on) then return false, "Gufà 'n alt tuo? Nun se pò." end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 2 then return false, "La gufata è armeno du' piotte." end
  if stake > Balance() then return false, "Nun c'hai abbastanza piotte." end
  for _, g in ipairs(S.Gufate()) do
    if g.on == on and S.GufaState(g, all) == "aperta" then return false, "A " .. Short(m) .. " je sta già a gufà quarcuno." end
  end
  local g = { id = NewId(), on = on, s = stake, at = Now() }
  local keep = { g }
  for _, x in ipairs(MyList("gf")) do if #keep < 4 then keep[#keep + 1] = x end end
  Pay(g.id, stake, "gu", on)
  P.UpdateSelf(ns.state, ns.recordGuid, { gf = keep }, "sfide")
  Send({ t = "gf", on = on, s = stake, id = g.id, at = g.at })
  S.Update()
  return true
end

----------------------------------------------------------------------
-- duels live: everyone in the same zone can bet on one of the two
----------------------------------------------------------------------
local liveSeen = {}
-- tell the patto a duel between a and b is starting (gogna: it's a duello a la gogna)
function S.Live(a, b, gogna)
  local key = (a < b) and (a .. b) or (b .. a)
  local now = GetTime and GetTime() or 0
  if liveSeen[key] and now - liveSeen[key] < 90 then return end
  liveSeen[key] = now
  local z = GetRealZoneText and U.Plain(GetRealZoneText(), "string")
  Send({ t = "live", a = a, b = b, z = z, g = gogna and 1 or nil })
end

function S.Bet(a, b, pick, stake)
  local st = Store()
  if not st then return NoPlay() end
  if ns.Tombola and (ns.Tombola.Mine(a) or ns.Tombola.Mine(b)) then return false, "Sur duello tuo (o de 'n alt tuo) nun se punta." end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 1 then return false, "Punta armeno 'na piotta." end
  if stake > Balance() then return false, "Nun c'hai abbastanza piotte." end
  local id = "bet:" .. NewId()
  st.bets[id] = { a = a, b = b, pick = pick, s = stake, at = Now() }
  Pay(id, stake, "sb", pick)
  if ns.Tombola then ns.Tombola.Update() end
  return true
end

----------------------------------------------------------------------
-- keeping up: my book, the news, the dialogs, my own pegno
----------------------------------------------------------------------
local function Tell(st, key, fn)
  if st.told[key] then return end
  st.told[key] = true
  fn()
end
local function Name(all, guid) return Short(all[guid]) end

-- the herald of the gogna: one line in the chat for everyone online, with a sound (er "DI PIÙÙÙ" for a rivincita
-- or a bella asked)
S.CAGASOTTO = {
  "%s s'è cagato sotto: ha rifiutato er duello a la gogna co' %s. Coniglio!",
  "%s ha visto %s e s'è dato. Fuggi, fuggi.",
  "%s dice de no a %s. Mamma l'ha chiamato pe' cena, se capisce.",
  "%s nun ce sta: co' %s nun se mena. Che fifa.",
}
function S.Herald(what, n, r, all, past)
  if not ns.News then return end
  local a, b = Name(all, r.from), Name(all, r.to)
  local kind = n == 1 and "duello a la gogna" or (n == 2 and "rivincita" or "bella")
  if what == "ask" then
    if n == 1 then
      ns.News.Banner("Duello a la gogna!", a .. " ha sfidato " .. b .. " a duello a la gogna. " .. b .. " ce sta a pensà...", { 1, 0.5, 0.2 }, "big")
    else
      ns.News.Banner(n == 2 and "Rivincita!" or "La bella!", a .. " vole " .. (n == 2 and "la rivincita" or "la bella") .. " co' " .. b .. ": si la riperde, er pegno je dura 'na settimana intera! " .. b .. " ce sta a pensà...", { 1, 0.5, 0.2 },
        H.MEDIA .. "duello\\dipiu.ogg")
    end
  elseif what == "ok" then
    ns.News.Banner(b .. " ha accettato!", (past and "Er " .. kind .. " s'è fatto" or "Er " .. kind .. " è partito") .. ": " .. a .. " contro " .. b .. ".", { 1, 0.82, 0 }, "big")
  elseif what == "no" then
    local f = S.CAGASOTTO[(math.floor(r.at or 0) % #S.CAGASOTTO) + 1]
    ns.News.Banner(b .. " s'è cagato sotto!", f:format(b, a), { 1, 0.3, 0.3 }, "big")
  end
end

-- the duel request of a gogna was accepted (the countdown starts): the patto hears it at once
local function Accepted(id)
  local st = Store()
  if not st then return end
  local all = Members()
  for _, s in ipairs(S.Series(all)) do
    for n, r in ipairs(s.reqs or {}) do
      if r.id == id then Tell(st, id .. ":ok", function() S.Herald("ok", n, r, all) end) return end
    end
  end
end
S.Accepted = Accepted
function S.DuelStarts()
  local me = ns.recordGuid
  for _, s in ipairs(S.Series(Members())) do
    if s.state == "incorso" and s.cur and (s.cur.to == me or s.cur.from == me) then
      Send({ t = "gok", id = s.cur.id })
      Accepted(s.cur.id)
      return
    end
  end
end

-- "Chi fa più pesci, fino a dom 8 nov"
function S.What(c, all, ans)
  local w
  if c.k == "l" then w = "Chi arriva prima ar " .. tostring(c.n)
  else
    local x = StatOf(c.st)
    w = x and (x.low and "Chi more de meno" or ("Chi fa più " .. x.name:lower())) or "?"
  end
  local e = ans and ans.a == 1 and ans.e
  return w .. ", fino a " .. U.Day(e or S.EndOf(Now()))
end

-- what happened, in one line: "Pietro ha perso pure la rivincita co' Dario"
local function SeriesHead(s, all)
  local W, L = GOLD .. Name(all, s.w) .. "|r", GOLD .. Name(all, s.l) .. "|r"
  local n = #s.duels
  local which = n == 3 and "la bella" or "la rivincita"
  if n == 1 then return L .. " ha perso er duello a la gogna co' " .. W, Name(all, s.l) .. " ha perso!" end
  if s.long then return L .. " ha perso pure " .. which .. " co' " .. W, Name(all, s.l) .. " ha perso pure " .. which .. "!" end
  if n == 2 then return W .. " s'è vennicato: ha vinto la rivincita co' " .. L, Name(all, s.w) .. " s'è vennicato!" end
  return W .. " ha vinto la bella co' " .. L, Name(all, s.w) .. " ha vinto la bella!"
end

local shown = {} -- dialogs already opened in this session (a reload opens them again if still due)
function S.Forget() shown = {} end
local quiet = true -- the first pass after login only learns what is already there
function S.Update()
  local st = Store()
  if not st or not P.HasSettings(ns.state) then return end
  Rebuild()
  local all = Members()
  local News = ns.News
  local me = ns.recordGuid
  -- the sfide a piotte
  for _, c in ipairs(S.All()) do
    local state, r, ans = S.State(c, all)
    local mine = c.from == me or c.to == me
    if mine and not ns.alt then
      if state == "rifiutata" or state == "scaduta" then
        if c.from == me then Got(c.id, c.s) end
      elseif state == "finita" then
        if r.w == "" then Got(c.id, st.book[c.id] and st.book[c.id].s or 0)
        elseif r.w == me then Got(c.id, 2 * c.s)
        else Got(c.id, 0) end
      end
    end
    if ans and ans.a == 1 then
      Tell(st, c.id .. ":si", function()
        if not quiet and News then
          News.Add(GOLD .. Name(all, c.to) .. "|r ha accettato la sfida de " .. GOLD .. Name(all, c.from) .. "|r: " .. S.What(c, all, ans) .. ", " .. Piotte(c.s) .. ".")
        end
      end)
    end
    if state == "finita" then
      Tell(st, c.id .. ":fine", function()
        if quiet or not News then return end
        if r.w == "" then
          News.Add("La sfida tra " .. Name(all, c.from) .. " e " .. Name(all, c.to) .. " è finita pari: poste ridate.")
        else
          News.Add(GOLD .. Name(all, r.w) .. "|r ha vinto la sfida co' " .. GOLD .. Name(all, r.l) .. "|r (+" .. Piotte(2 * c.s) .. ").")
        end
      end)
    end
    if c.to == me and state == "aspetta" and not st.asked[c.id] and not ns.alt then
      st.asked[c.id] = true
      S.Ask(c, all)
    end
  end
  -- er duello a la gogna
  for _, s in ipairs(series) do
    if not ns.alt then
      -- one window at a time, under the game's duel request: what's at stake, what to do
      if s.state == "incorso" and s.cur.to == me and not shown["a:" .. s.cur.id] then
        shown["a:" .. s.cur.id] = true
        S.Called(s, all)
      elseif s.state == "rivincita" and s.last.l == me and not shown["r:" .. s.ids[s.n]] then
        shown["r:" .. s.ids[s.n]] = true
        S.OfferRematch(s, all)
      elseif s.state == "rivincita" and s.last.w == me and not shown["w:" .. s.ids[s.n]] then
        shown["w:" .. s.ids[s.n]] = true
        S.Notice("Hai vinto!", "Hai battuto " .. GOLD .. Name(all, s.last.l) .. "|r.\nSi vole " .. (s.n == 1 and "la rivincita" or "la bella") .. ", te arriva la richiesta de duello.", 15)
      elseif s.state == "chiusa" and s.w == me and not s.pick and Now() <= s.te + S.PICK and not shown["p:" .. s.id] then
        shown["p:" .. s.id] = true
        S.ShowPegno(s)
      elseif s.state == "chiusa" and s.l == me and not s.pena and not shown["l:" .. s.id] then
        shown["l:" .. s.id] = true
        S.Notice("A la gogna", "Hai perso co' " .. GOLD .. Name(all, s.w) .. "|r: stai a la gogna pe' " .. Span(s.long) .. ".\nEr pegno lo sta a sceje lui.", 20)
      elseif s.state == "chiusa" and s.l == me and s.pena and Now() < s.til and not st.told["y:" .. s.id] then
        st.told["y:" .. s.id] = true
        S.ShowPena(s, all)
      end
    end
    -- the whole patto hears it: who called whom, and whether he took it or ran away
    for n, r in ipairs(s.reqs or {}) do
      Tell(st, r.id .. ":ask", function()
        if quiet or Now() - (r.at or 0) > 900 then return end
        S.Herald("ask", n, r, all)
      end)
      if s.duels[n] then
        Tell(st, r.id .. ":ok", function()
          if quiet or Now() - (s.duels[n].at or 0) > 900 then return end
          S.Herald("ok", n, r, all, true)
        end)
      end
    end
    if s.refused then
      local r = s.refused
      Tell(st, r.id .. ":no", function()
        if quiet or Now() - (r.at or 0) > 900 then return end
        S.Herald("no", r.n, r, all)
      end)
    end
    if s.state == "chiusa" then
      Tell(st, s.id .. ":fine", function()
        if quiet or not News then return end
        local line, title = SeriesHead(s, all)
        local pre = ""
        if s.why == "no" then pre = GOLD .. Name(all, s.l) .. "|r nun ha dato " .. (#s.duels == 2 and "la bella" or "la rivincita") .. " a " .. GOLD .. Name(all, s.w) .. "|r. " end
        if s.why == "no" then line = pre .. line end
        News.Add(line .. ": a la gogna pe' " .. Span(s.long) .. ".")
        News.Banner(title, Name(all, s.l) .. " va a la gogna pe' " .. Span(s.long) .. ". Er pegno lo sceje " .. Name(all, s.w) .. ".", { 1, 0.5, 0.2 }, "evento", true)
      end)
      if s.pena then
        Tell(st, s.id .. ":pegno", function()
          local pena = S.PENE[s.pena]
          if quiet or not News then return end
          local what = S.PegnoText(s, all)
          News.Add("Er pegno de " .. GOLD .. Name(all, s.l) .. "|r: " .. what .. (s.pick and "" or " (" .. Name(all, s.w) .. " nun ha scelto)") .. ".")
          News.Banner("Er pegno de " .. Name(all, s.l), what .. ". L'ha scelto " .. Name(all, s.w) .. ".", { 1, 0.5, 0.2 }, "evento")
        end)
      end
    end
  end
  for _, t in ipairs(S.Taje()) do
    local state, r = S.TajaState(t, all)
    if state == "finita" and not ns.alt then
      if t.by == me then Got(t.id, (r.w == "" or r.w == me) and t.s or 0) end
      if r.w == me and t.by ~= me then st.book[t.id .. ":w"] = st.book[t.id .. ":w"] or { s = 0, got = t.s, k = "tjw", o = t.on, at = r.at, gt = r.at } end
    end
    Tell(st, t.id .. ":su", function()
      if quiet or not News then return end
      News.Add("Taja de " .. Piotte(t.s) .. " su " .. GOLD .. Name(all, t.on) .. "|r: chi lo batte a duello se le pija.")
      News.Banner("Taja su " .. Name(all, t.on), Piotte(t.s) .. " a chi lo batte a duello", { 1, 0.5, 0.2 }, "evento")
    end)
    if state == "finita" and r.w ~= "" then
      Tell(st, t.id .. ":presa", function()
        if quiet or not News then return end
        News.Add(GOLD .. Name(all, r.w) .. "|r s'è pijato la taja su " .. GOLD .. Name(all, t.on) .. "|r (" .. Piotte(t.s) .. ").")
      end)
    end
  end
  for _, g in ipairs(S.Gufate()) do
    local state = S.GufaState(g, all)
    if state ~= "aperta" and not ns.alt then
      local half = math.floor(g.s / 2)
      if g.by == me then Got(g.id, state == "morto" and (g.s + half) or (state == "nullo" and g.s or 0), "gu", g.on) end
      if g.on == me and state ~= "nullo" then
        -- he pays half, but never more than he has (the bank pays the rest of what the gufo wins)
        if state == "morto" then st.book[g.id .. ":t"] = st.book[g.id .. ":t"] or { s = math.min(half, math.max(0, Balance())), got = 0, k = "gut", o = g.by, at = g.at, gt = Now() }
        else st.book[g.id .. ":t"] = st.book[g.id .. ":t"] or { s = 0, got = g.s, k = "gut", o = g.by, at = g.at, gt = Now() } end
      end
    end
    if state ~= "aperta" then
      Tell(st, g.id .. ":fine", function()
        if quiet or not News then return end
        if state == "nullo" then
          News.Add("La gufata de " .. GOLD .. Name(all, g.by) .. "|r su " .. GOLD .. Name(all, g.on) .. "|r nun se sa com'è finita: posta ridata.")
        elseif state == "morto" then
          News.Add("La gufata de " .. GOLD .. Name(all, g.by) .. "|r ha funzionato: " .. GOLD .. Name(all, g.on) .. "|r è morto. Paga " .. Piotte(math.floor(g.s / 2)) .. ".")
          if g.on == me or g.by == me then News.Banner("La gufata ha funzionato!", Name(all, g.on) .. " è morto. Gufo: " .. Name(all, g.by), { 1, 0.5, 0.2 }, "evento") end
        else
          News.Add(GOLD .. Name(all, g.on) .. "|r è campato a la gufata de " .. GOLD .. Name(all, g.by) .. "|r: se pija " .. Piotte(g.s) .. ".")
          if g.on == me then News.Banner("Sei campato!", "La gufata de " .. Name(all, g.by) .. " nun ha funzionato: +" .. Piotte(g.s), nil, "evento") end
        end
      end)
    end
  end
  -- my bets on duels
  for id, b in pairs(st.bets) do
    if not st.book[id] or st.book[id].got == nil then
      local d = FirstDuel(all, b.a, b.b, b.at)
      if d and d.at <= b.at + S.BET_WINDOW then
        local won = d.w == b.pick
        Got(id, won and 2 * b.s or 0, "sb", b.pick)
        if News then News.Add(won and ("Hai vinto " .. Piotte(2 * b.s) .. " puntando su " .. GOLD .. Name(all, b.pick) .. "|r.")
          or ("Hai perso " .. Piotte(b.s) .. " puntando su " .. Name(all, b.pick) .. ".")) end
      elseif Now() > b.at + S.BET_WINDOW then
        Got(id, b.s, "sb", b.pick)
      end
    end
  end
  -- duels between patto members and the gravestones make the news
  for guid, m in pairs(all) do
    for _, d in ipairs(m.dd or {}) do
      if d.w == 1 then
        Tell(st, "duel:" .. guid .. ":" .. tostring(d.at), function()
          if not quiet and News then News.Add(GOLD .. Short(m) .. "|r ha battuto " .. GOLD .. Name(all, d.o) .. "|r a duello.") end
        end)
      end
    end
    for _, g in ipairs(m.rip or {}) do
      Tell(st, "rip:" .. guid .. ":" .. tostring(g.at), function()
        if quiet or not News then return end
        if g.w then News.Add("R.I.P. " .. GOLD .. Short(m) .. "|r" .. S.GraveText(g) .. ". Urtime parole: \"" .. g.w .. "\"") end
        -- lo strillone: everyone is told
        local cr = criers[guid]
        if cr and g.at >= cr.from and g.at < cr.til and Now() - g.at < 600 then
          News.Banner("Lo strillone: " .. Short(m) .. " è morto de novo!", S.CrierLine(Short(m), g), { 1, 0.5, 0.2 }, "evento", true)
        end
      end)
    end
  end
  -- er Campione: say it when the crown changes hands
  if champion and st.champ ~= champion then
    local was = st.champ
    st.champ = champion
    if not quiet and News then
      News.Add(GOLD .. Name(all, champion) .. "|r è er novo Campione de la gogna" .. (was and all[was] and (": ha battuto " .. Name(all, was)) or "") .. ".")
      News.Banner(Name(all, champion) .. " è er Campione!", "La corona è sua finché nun perde a la gogna.", nil, "evento", true)
    end
  end
  quiet = false
  S.ShowMyGogna()
  S.GufaWatch()
  if ns.Tombola then ns.Tombola.Update() end
end

-- lo strillone: how he died, told so the whole patto laughs (by the kind of death, the killer and the place)
S.CRIER = {
  cascato = { "%s è cascato a %s. Gravità 1, %s 0.", "%s ha provato a volà a %s. Nun era 'n uccello.", "A %s c'era 'n gradino. %s nun l'ha visto." },
  affogato = { "%s è affogato a %s. Pure li pesci ridono.", "%s s'è scordato de respirà a %s.", "A %s %s ha bevuto troppo. Acqua." },
  pischello = { "%s s'è fatto ammazzà da 'n %s a %s. 'N pischello!", "A %s 'n %s ha menato %s. Vergogna eterna." },
  pvp = { "%s s'è fatto fà fori da %s a %s. 'Na passeggiata.", "A %s %s ha incontrato %s. È finita male." },
  mostro = { "%s s'è fatto fà fori da 'n %s a %s.", "%s 1, %s 0. A %s.", "A %s 'n %s s'è magnato %s. Bon appetito." },
}
function S.CrierLine(name, g)
  local k = g.k
  if not S.CRIER[k] then k = "mostro" end
  local list = S.CRIER[k]
  local f = list[(math.floor(g.at or 0) % #list) + 1]
  local z, by = g.z or "chissà dove", g.by or "quarcosa"
  -- the order of the names in each line: name, place / name, killer, place, as the line wants them
  if k == "cascato" then
    if f:find("^A %%s") then return f:format(z, name) end
    return f:format(name, z, name)
  elseif k == "affogato" then
    if f:find("^A %%s") then return f:format(z, name) end
    return f:format(name, z)
  elseif k == "pischello" or k == "pvp" then
    if f:find("^A %%s") then return f:format(z, by, name) end
    return f:format(name, by, z)
  else
    if f:find("^A %%s") then return f:format(z, by, name) end
    if f:find("^%%s 1") then return f:format(by, name, z) end
    return f:format(name, by, z)
  end
end

-- ", livello 14, ammazzato da Kobold Vermin a Elwynn Forest"
function S.GraveText(g)
  local s = g.lv and (", livello " .. g.lv) or ""
  if g.k == "cascato" then s = s .. ", cascato"
  elseif g.k == "affogato" then s = s .. ", affogato"
  elseif g.by then s = s .. ", ammazzato da " .. g.by end
  if g.z then s = s .. " a " .. g.z end
  return s
end

-- every gravestone of the patto, newest first
function S.Graves()
  local out = {}
  for guid, m in pairs(Members()) do
    for _, g in ipairs(m.rip or {}) do out[#out + 1] = { guid = guid, m = m, g = g } end
  end
  table.sort(out, function(a, b) return a.g.at > b.g.at end)
  return out
end

----------------------------------------------------------------------
-- dialogs (the vanilla popup: dialog box, white text, red buttons)
----------------------------------------------------------------------
-- the gogna windows: one at a time, under the game's own popups (the duel request sits at the top)
local GOGNA = {}
local function Only(d) for _, x in ipairs(GOGNA) do if x ~= d and x:IsShown() then x:Hide() end end end
local function Dialog(name, w, h, title, gogna)
  local d = CreateFrame("Frame", name, UIParent)
  d:SetSize(w, h)
  if gogna then d:SetPoint("TOP", UIParent, "TOP", 0, -260) GOGNA[#GOGNA + 1] = d else d:SetPoint("CENTER", 0, 160) end
  d:SetFrameStrata("DIALOG")
  d:SetToplevel(true)
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  H.Chrome(d)
  d.title = H.DialogHeader(d, title, 160)
  d.err = H.Text(d, "GameFontRedSmall", "", w - 40, "CENTER")
  d.err:SetPoint("BOTTOM", 0, 44)
  d:HookScript("OnShow", function() d.err:SetText("") end)
  if UISpecialFrames then table.insert(UISpecialFrames, name) end
  d:Hide()
  return d
end

-- a dialog that has done its part: one line of what happened, the buttons go, it closes by itself
local function Done(d, text, secs, keep)
  for _, x in ipairs(d.controls or {}) do x:Hide() end
  if d.msg then d.msg:SetText(text) d.msg:Show() end
  d.err:SetText("")
  if not keep and C_Timer then
    local token = {}
    d.token = token
    C_Timer.After(secs or 4, function() if d.token == token then d:Hide() end end)
  end
end
local function Reset(d)
  d.token = nil
  for _, x in ipairs(d.controls or {}) do x:Show() end
  if d.msg then d.msg:Hide() end
end
local function TwoButtons(d, yes, no)
  d.yes:ClearAllPoints() d.yes:SetPoint("BOTTOMRIGHT", d, "BOTTOM", -6, 18)
  d.no:ClearAllPoints() d.no:SetPoint("BOTTOMLEFT", d, "BOTTOM", 6, 18)
  d.yes:SetText(yes) d.no:SetText(no)
end
local function OneButton(d, text)
  d.no:ClearAllPoints() d.no:SetPoint("BOTTOM", 0, 18)
  d.no:SetText(text)
end
local RULE = "Chi perde sta a la gogna 'n giorno, cor pegno che sceje chi vince."

-- a sfida a piotte for me
local ask
function S.Ask(c, all)
  all = all or Members()
  if not ask then
    ask = Dialog("ErPattoSfida", 400, 140, "Sfida!")
    ask.text = H.Text(ask, "GameFontHighlight", "", 360, "CENTER")
    ask.text:SetPoint("TOP", 0, -34)
    ask.yes = H.Btn(ask, "Ce sto", 120, function()
      if ask.c.id == "prova" then ask:Hide() return end
      if Report(ask, S.Answer(ask.c.id, true, ask.c)) then Done(ask, "Ce stai! In bocca ar lupo.") end
    end)
    ask.no = H.Btn(ask, "No", 120, function() if ask.c.id ~= "prova" then S.Answer(ask.c.id, false, ask.c) end ask:Hide() end)
    TwoButtons(ask, "Ce sto", "No")
    ask.msg = H.Text(ask, "GameFontNormal", "", 360, "CENTER")
    ask.msg:SetPoint("BOTTOM", 0, 24)
    ask.controls = { ask.yes, ask.no }
  end
  Reset(ask)
  ask.c = c
  ask.text:SetText(GOLD .. Name(all, c.from) .. "|r te sfida: " .. S.What(c, all):gsub("^C", "c") .. ".\nPosta " .. Piotte(c.s) .. ": chi vince se pija er doppio.")
  ask:Show()
  if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE) or 880) end
end

-- a window that only tells: a line or two, the X, it closes by itself
local notice
function S.Notice(title, body, secs, horn)
  if not notice then
    notice = Dialog("ErPattoAvviso", 420, 112, "", true)
    H.CloseX(notice)
    notice.text = H.Text(notice, "GameFontHighlight", "", 380, "CENTER")
    notice.text:SetPoint("TOP", 0, -34)
  end
  notice.title:SetText(title)
  notice.text:SetText(body)
  local th = notice.text.GetStringHeight and notice.text:GetStringHeight() or 0
  if type(th) ~= "number" or th <= 0 then th = 14 * (select(2, tostring(body):gsub("\n", "")) + 2) end
  notice:SetHeight(math.max(96, 34 + th + 28))
  Only(notice)
  notice:Show()
  if horn then Epic() end
  local token = {}
  notice.token = token
  if C_Timer then C_Timer.After(secs or 12, function() if notice.token == token then notice:Hide() end end) end
end

-- the duel request of a gogna for me: what's at stake (accepting is in the game's own popup)
function S.Called(s, all)
  all = all or Members()
  local who = GOLD .. Name(all, s.cur.from) .. "|r"
  if s.n == 1 then
    S.Notice("Duello a la gogna!", who .. " te sfida a duello a la gogna: accetta la richiesta de duello.\n" .. RULE, 60, true)
  else
    local which = s.n == 2 and "la rivincita" or "la bella"
    S.Notice(s.n == 2 and "Rivincita!" or "La bella!", who .. " vole " .. which .. ": accetta la richiesta de duello.\nSi la riperde, sta a la gogna 'na settimana. Si perdi tu, ce stai tu 'n giorno. Si nun accetti, ce va lui pe' 'n giorno.", 60, true)
  end
end

-- I lost: la rivincita (or la bella)?
local offer
function S.OfferRematch(s, all)
  all = all or Members()
  if not offer then
    offer = Dialog("ErPattoRivincita", 400, 150, "Hai perso!", true)
    offer.text = H.Text(offer, "GameFontHighlight", "", 360, "CENTER")
    offer.text:SetPoint("TOP", 0, -32)
    offer.yes = H.Btn(offer, "Rivincita!", 130, function()
      if offer.sid == "prova" then Done(offer, "Richiesta de duello mannata (prova).") return end
      local ok, c = S.Rematch(offer.sid)
      if Report(offer, ok, c) then
        offer.sent = c.id
        Done(offer, "Richiesta de duello mannata a " .. Name(Members(), offer.winner) .. ".\nSi accetta, è " .. (offer.n == 1 and "la rivincita" or "la bella") .. ".", 6)
      end
    end)
    offer.no = H.Btn(offer, "Basta così", 130, function()
      if not offer.sent and offer.sid ~= "prova" then S.Rematch(offer.sid, true) end
      offer:Hide()
    end)
    offer.msg = H.Text(offer, "GameFontNormal", "", 360, "CENTER")
    offer.msg:SetPoint("CENTER", 0, 8)
    offer.controls = { offer.yes, offer.no, offer.text }
  end
  Reset(offer)
  offer.sid, offer.n, offer.winner, offer.sent = s.id, s.n, s.last.w, nil
  local who = GOLD .. Name(all, s.last.w) .. "|r"
  if s.n == 1 then
    offer.text:SetText("Si lassi stà, vai a la gogna 'n giorno.\nRivincita co' " .. who .. "? Si la riperdi, ce stai 'na settimana.")
    TwoButtons(offer, "Rivincita!", "Basta così")
  else
    offer.text:SetText("Si lassi stà, vai a la gogna 'n giorno.\nLa bella co' " .. who .. "? Si la perdi, ce stai 'na settimana.")
    TwoButtons(offer, "La bella!", "Basta così")
  end
  Only(offer)
  offer:Show()
  local left = S.RV_ASK - (Now() - (s.last.at or Now()))
  if C_Timer then C_Timer.After(math.max(1, left), function() if offer.sid == s.id and not offer.sent then offer:Hide() end end) end
end

-- er pegno chooser: one red button per pegno (two columns); a click gives that pegno at once (the tooltip says what
-- it does). Er verso needs its word first: the click opens the box for it, Enter or "Daje" gives it.
local function PenaPicker(parent, x, y, form, onPick)
  local w = { radios = {} }
  local function go() if onPick then onPick() end end
  for i, p in ipairs(S.PENE) do
    local b = H.Btn(parent, p.name, 180, function()
      form.p = i
      if w.Refresh then w.Refresh() end
      if S.PENE[i].ask then w.text:SetFocus() else go() end
    end, 22)
    b:SetPoint("TOPLEFT", x + ((i - 1) % 2) * 190, y - math.floor((i - 1) / 2) * 26)
    b.v = i
    b:SetScript("OnEnter", function(self) H.Tip(self, { S.PENE[self.v].name, S.PENE[self.v].tip }) end)
    b:SetScript("OnLeave", H.HideTip)
    w.radios[i] = b
  end
  local rows = math.ceil(#S.PENE / 2)
  w.label = H.Text(parent, "GameFontNormalSmall", "Er verso", 60)
  w.label:SetPoint("TOPLEFT", x + 4, y - rows * 26 - 8)
  w.text = H.Input(parent, 150, 30)
  w.text:SetPoint("TOPLEFT", x + 70, y - rows * 26 - 4)
  w.text:SetScript("OnTextChanged", function(self) form.t = self:GetText() end)
  w.text:SetScript("OnEnterPressed", function(self) self:ClearFocus() go() end)
  w.go = H.Btn(parent, "Daje", 80, go, 22)
  w.go:SetPoint("LEFT", w.text, "RIGHT", 8, 0)
  w.emote = H.Btn(parent, "", 10, function() end, 18) w.emote:Hide() -- kept for the old callers
  w.face = parent:CreateTexture(nil, "ARTWORK") w.face:Hide()
  function w.Refresh()
    for _, b in ipairs(w.radios) do
      if (form.p or 0) == b.v and S.PENE[b.v].ask then b:LockHighlight() else b:UnlockHighlight() end
    end
    local pena = S.PENE[form.p or 0]
    local ask = pena and pena.ask
    w.label:SetShown(ask and true or false)
    w.text:SetShown(ask and true or false)
    w.go:SetShown(ask and true or false)
    if ask then
      w.label:SetText(pena.ask)
      if not w.text:HasFocus() then w.text:SetText(form.t or "") end
    end
  end
  return w
end
S.PenaPicker = PenaPicker

-- I won: wait for the rivincita, then choose er pegno
local pegno
function S.ShowPegno(s)
  local all = Members()
  if not pegno then
    pegno = Dialog("ErPattoPegno", 440, 236, "Hai vinto!", true)
    pegno.form = { p = 0, e = 1 }
    pegno.text = H.Text(pegno, "GameFontHighlight", "", 400, "CENTER")
    pegno.text:SetPoint("TOP", 0, -32)
    pegno.pena = PenaPicker(pegno, 36, -74, pegno.form, function()
      if pegno.sid == "prova" then Done(pegno, "Er pegno è fatto (prova).", 2.5) return end
      local f = pegno.form
      if Report(pegno, S.Pick(pegno.sid, f.p, f.t, f.e)) then Done(pegno, "Er pegno è fatto: " .. Name(Members(), pegno.l) .. " sta a la gogna.", 2.5) end
    end)
    pegno.msg = H.Text(pegno, "GameFontNormal", "", 340, "CENTER")
    pegno.msg:SetPoint("CENTER", 0, -10)
    pegno.controls = { pegno.text, pegno.pena.text, pegno.pena.label, pegno.pena.go }
    for _, r in ipairs(pegno.pena.radios) do pegno.controls[#pegno.controls + 1] = r end
  end
  Reset(pegno)
  pegno.sid = s.id
  pegno.l = s.l
  pegno.form.p, pegno.form.t, pegno.form.e = 0, nil, 1
  pegno.text:SetText(GOLD .. Name(all, s.l) .. "|r va a la gogna pe' " .. Span(s.long) .. ".\nChe pegno je dai?")
  pegno.pena.Refresh()
  Only(pegno)
  pegno:Show()
  if C_Timer then
    local left = S.PICK - (Now() - (s.te or Now()))
    C_Timer.After(math.max(1, left), function() if pegno.sid == s.id then pegno:Hide() end end)
  end
end

-- the bet on two of the patto fighting
local bet
function S.ShowBet(a, b, gogna)
  local all = Members()
  if not (all[a] and all[b]) then return end
  if not bet then
    bet = Dialog("ErPattoScommessa", 320, 150, "Ar Colosseo!")
    H.CloseX(bet)
    bet.text = H.Text(bet, "GameFontHighlight", "", 290, "CENTER")
    bet.text:SetPoint("TOP", 0, -32)
    bet.label = H.Text(bet, "GameFontNormalSmall", "Punti", 40)
    bet.label:SetPoint("TOPLEFT", 34, -78)
    bet.stake = H.Input(bet, 40, 4)
    if bet.stake.SetNumeric then bet.stake:SetNumeric(true) end
    bet.stake:SetPoint("TOPLEFT", 76, -74)
    bet.note = H.Text(bet, "GameFontHighlightSmall", "piotte, chi indovina raddoppia", 160)
    bet.note:SetPoint("TOPLEFT", 122, -78)
    local function pick(i)
      return function()
        local ok, msg = S.Bet(bet.a, bet.b, i == 1 and bet.a or bet.b, bet.stake:GetText())
        if Report(bet, ok, msg) then
          Done(bet, "Hai puntato " .. Piotte(tonumber(bet.stake:GetText()) or 0) .. " su " .. Name(Members(), i == 1 and bet.a or bet.b) .. ".", 3)
        end
      end
    end
    bet.pa = H.Btn(bet, "", 120, pick(1)) bet.pa:SetPoint("BOTTOMRIGHT", bet, "BOTTOM", -6, 18)
    bet.pb = H.Btn(bet, "", 120, pick(2)) bet.pb:SetPoint("BOTTOMLEFT", bet, "BOTTOM", 6, 18)
    bet.msg = H.Text(bet, "GameFontNormal", "", 270, "CENTER")
    bet.msg:SetPoint("BOTTOM", 0, 24)
    bet.controls = { bet.pa, bet.pb, bet.label, bet.stake, bet.note }
  end
  Reset(bet)
  bet.a, bet.b = a, b
  bet.text:SetText(H.Colored(all[a]) .. " contro " .. H.Colored(all[b]) .. (gogna and ", a la gogna" or "") .. ".\nSu chi punti?")
  bet.pa:SetText(Short(all[a]))
  bet.pb:SetText(Short(all[b]))
  bet.stake:SetText("5")
  bet.shownAt = GetTime and GetTime() or 0
  -- on top, centred: under the cap bar when the bar is up there (as the clip after a duel)
  bet:ClearAllPoints()
  if bet.SetUserPlaced then pcall(bet.SetUserPlaced, bet, false) end
  local hud = _G.ErPattoHUD
  local top = hud and hud.IsShown and hud:IsShown() and hud.GetTop and hud:GetTop()
  local hh = UIParent.GetHeight and UIParent:GetHeight() or 768
  if top and top > hh * 0.6 then bet:SetPoint("TOP", hud, "BOTTOM", 0, -56)
  else bet:SetPoint("TOP", UIParent, "TOP", 0, -90) end
  bet:Show()
  -- the call to the arena: the auction house bell (never a duel's sound, so nobody thinks he's been called)
  if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN) or 5274, "Master") end
  if C_Timer then C_Timer.After(60, function() if bet and bet.shownAt and (GetTime() - bet.shownAt) >= 59 then bet:Hide() end end) end
end

-- from the menu: throw a duello a la gogna
local duel
function S.OpenDuel(guid, unit)
  local all = Members()
  if not all[guid] or guid == ns.recordGuid then return end
  if not duel then
    duel = Dialog("ErPattoDuelloGogna", 400, 140, "Duello a la gogna", true)
    duel.text = H.Text(duel, "GameFontHighlight", "", 360, "CENTER")
    duel.text:SetPoint("TOP", 0, -34)
    duel.yes = H.Btn(duel, "Sfida!", 130, function()
      local ok, c = S.Gogna(duel.to, duel.unit)
      if Report(duel, ok, c) then
        duel.sent = c.id
        Done(duel, "Richiesta de duello mannata a " .. Name(Members(), duel.to) .. ".\nSi accetta, è a la gogna.", 6)
      end
    end)
    duel.no = H.Btn(duel, "Lassa stà", 130, function() duel:Hide() end)
    duel.msg = H.Text(duel, "GameFontNormal", "", 360, "CENTER")
    duel.msg:SetPoint("TOP", 0, -40)
    duel.controls = { duel.yes, duel.no, duel.text }
  end
  Reset(duel)
  TwoButtons(duel, "Sfida!", "Lassa stà")
  duel.sent = nil
  duel.to, duel.unit = guid, unit
  duel.text:SetText("Sfidi " .. H.Colored(all[guid]) .. " a duello a la gogna.\n" .. RULE)
  Only(duel)
  duel:Show()
  local list = S.Series(all)
  local why = BlockText(ns.recordGuid, list, all) or BlockText(guid, list, all)
  duel.err:SetText(why or "")
  duel.yes:SetEnabled(not why)
end

----------------------------------------------------------------------
-- after a duel with someone of the patto: the clip on its own (the winner's or the loser's, with its music) and
-- under it a small vanilla box with "Hai vinto!" in green or "Hai perso!" in red and the record between the two.
-- The clips are frame sheets in Media/duello (256x144 frames, 4 by 7 on a 1024x1024 sheet, 12 a second): while
-- it plays, one texture coordinate change per frame; nothing at all when it's closed.
----------------------------------------------------------------------
S.CLIPS = {
  vinto = { sheets = 3, frames = 77, sound = "vinto.ogg" },
  perso = { sheets = 1, frames = 24, sound = "perso.ogg" },
}
local clip
function S.DuelClip(won, otherName, w, l)
  local c = S.CLIPS[won and "vinto" or "perso"]
  if not c then return end
  if not clip then
    clip = CreateFrame("Frame", "ErPattoDuelloFinito", UIParent)
    clip:SetSize(320, 250)
    clip:SetPoint("CENTER", UIParent, "CENTER", -340, 60)
    clip:SetFrameStrata("DIALOG")
    clip:SetMovable(true)
    clip.screen = clip:CreateTexture(nil, "ARTWORK")
    clip.screen:SetSize(320, 180)
    clip.screen:SetPoint("TOP", 0, 0)
    clip.box = CreateFrame("Frame", nil, clip, "BackdropTemplate")
    clip.box:SetSize(220, 64)
    clip.box:SetPoint("TOP", clip.screen, "BOTTOM", 0, -4)
    clip.box:EnableMouse(true) clip.box:RegisterForDrag("LeftButton")
    clip.box:SetScript("OnDragStart", function() clip:StartMoving() end)
    clip.box:SetScript("OnDragStop", function() clip:StopMovingOrSizing() end)
    H.Chrome(clip.box)
    local x = H.CloseX(clip.box)
    if x and x.SetScript then x:SetScript("OnClick", function() clip:Hide() end) end
    clip.title = H.Text(clip.box, "GameFontNormal", "", 180, "CENTER")
    clip.title:SetPoint("TOP", 0, -16)
    clip.record = H.Text(clip.box, "GameFontHighlightSmall", "", 180, "CENTER")
    clip.record:SetPoint("TOP", clip.title, "BOTTOM", 0, -6)
    clip:SetScript("OnUpdate", function(self, el)
      if not self.c then return end
      self.t = self.t + (el or 0)
      local i = math.floor(self.t * 12)
      if i >= self.c.frames then
        i = self.c.frames - 1
        if self.t > self.c.frames / 12 + 0.5 then self:Hide() return end
      end
      if i == self.shown then return end
      self.shown = i
      local sheet, k = math.floor(i / 28) + 1, i % 28
      local col, row = k % 4, math.floor(k / 4)
      if sheet ~= self.sheet then
        self.sheet = sheet
        self.screen:SetTexture(H.MEDIA .. "duello\\" .. self.name .. sheet .. ".tga")
      end
      self.screen:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 144 / 1024, (row + 1) * 144 / 1024)
    end)
    clip:SetScript("OnHide", function(self) self.c = nil if self.handle and StopSound then pcall(StopSound, self.handle) end end)
  end
  clip.c, clip.name, clip.t, clip.shown, clip.sheet = c, won and "vinto" or "perso", 0, nil, nil
  clip.title:SetText(won and "Hai vinto!" or "Hai perso!")
  if won then clip.title:SetTextColor(0.1, 1, 0.1) else clip.title:SetTextColor(1, 0.1, 0.1) end
  clip.record:SetText("Tu " .. GOLD .. (w or 0) .. "|r - " .. GOLD .. (l or 0) .. "|r " .. tostring(otherName))
  -- on top, in the middle: under the cap bar when the bar is up there
  clip:ClearAllPoints()
  local hud = _G.ErPattoHUD
  local top = hud and hud.IsShown and hud:IsShown() and hud.GetTop and hud:GetTop()
  local h = UIParent.GetHeight and UIParent:GetHeight() or 768
  if top and top > h * 0.6 then clip:SetPoint("TOP", hud, "BOTTOM", 0, -56)
  else clip:SetPoint("TOP", UIParent, "TOP", 0, -80) end
  clip:Show()
  if PlaySoundFile then
    local ok, willPlay, handle = pcall(PlaySoundFile, H.MEDIA .. "duello\\" .. c.sound, "Master")
    clip.handle = ok and handle or nil
  end
end
ns.On("J_Duel", function(name, won)
  if not (ns.state and type(name) == "string") or ns.alt then return end
  local other
  for guid, m in pairs(ns.state.members) do
    if guid ~= ns.recordGuid and (m.name == name or Short(m) == name or Short(m) == name:match("^([^%-]+)")) then other = m end
  end
  if not other then return end
  local rec = ns.MyRecord and ns.MyRecord()
  local h = rec and rec.h2h and (rec.h2h[name] or rec.h2h[other.name]) or {}
  pcall(S.DuelClip, won, Short(other), h.w, h.l)
end)

-- my pegno, explained: what it does to me, until when, who sent me (once when it lands, and from the debuff)
local pena
function S.ShowPena(s, all)
  all = all or Members()
  if not pena then
    pena = Dialog("ErPattoPena", 420, 176, "A la gogna", true)
    pena.icon = pena:CreateTexture(nil, "ARTWORK")
    pena.icon:SetSize(36, 36)
    pena.icon:SetPoint("TOPLEFT", 26, -34)
    local border = pena:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Debuff-Border")
    border:SetSize(40, 39)
    border:SetPoint("CENTER", pena.icon)
    border:SetVertexColor(0.8, 0, 0)
    pena.name = H.Text(pena, "GameFontNormal", "", 310)
    pena.name:SetPoint("TOPLEFT", 74, -34)
    pena.text = H.Text(pena, "GameFontHighlight", "", 316)
    pena.text:SetPoint("TOPLEFT", 74, -52)
    pena.til = H.Text(pena, "GameFontHighlightSmall", "", 316)
    pena.yes = H.Btn(pena, "Ho capito", 120, function() pena:Hide() end)
    pena.yes:SetPoint("BOTTOM", 0, 18)
  end
  local p = S.PENE[s.pena or 0]
  pena.icon:SetTexture(S.PegnoIcon(s))
  pena.name:SetText(p and p.name or "Er pegno")
  pena.text:SetText(S.PegnoYou(s, all) or "")
  pena.til:ClearAllPoints()
  pena.til:SetPoint("TOPLEFT", pena.text, "BOTTOMLEFT", 0, -8)
  pena.til:SetText(GREY .. "Fino a " .. U.When(s.til) .. ". T'ha mannato " .. Name(all, s.w) .. ".|r")
  local th = (pena.text.GetStringHeight and pena.text:GetStringHeight()) or 42
  pena:SetHeight(math.max(150, 52 + th + 30 + 50))
  Only(pena)
  pena:Show()
end

-- the sfottò: three lines about him (Tombola.SfottiFor), pick one, 3 piotte, it lands big on his screen
local sfo
function S.OpenSfotti(guid)
  local all = Members()
  local TB = ns.Tombola
  if not (TB and all[guid]) or guid == ns.recordGuid then return end
  if not sfo then
    sfo = Dialog("ErPattoSfotti", 460, 190, "Sfotti")
    sfo.text = H.Text(sfo, "GameFontHighlight", "", 420, "CENTER")
    sfo.text:SetPoint("TOP", 0, -32)
    sfo.radios = {}
    for i = 1, 3 do
      local r = H.Radio(sfo, "", function() sfo.pick = i for k, x in ipairs(sfo.radios) do x:SetSelected(k == i) end end)
      r:SetPoint("TOPLEFT", 28, -58 - (i - 1) * 22)
      sfo.radios[i] = r
    end
    sfo.yes = H.Btn(sfo, "Sfotti!", 120, function()
      local ok, msg = TB.Sfotti(sfo.guid, sfo.lines[sfo.pick or 1])
      if Report(sfo, ok, msg) then
        if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND) or 120) end
        Done(sfo, "Sfottuto! A " .. Name(Members(), sfo.guid) .. " je compare: \"" .. msg .. "\"", 4)
      end
    end)
    sfo.no = H.Btn(sfo, "Lassa stà", 120, function() sfo:Hide() end)
    TwoButtons(sfo, "Sfotti!", "Lassa stà")
    sfo.msg = H.Text(sfo, "GameFontNormal", "", 420, "CENTER")
    sfo.msg:SetPoint("CENTER", 0, -4)
    sfo.controls = { sfo.yes, sfo.no, sfo.text, sfo.radios[1], sfo.radios[2], sfo.radios[3] }
  end
  Reset(sfo)
  sfo.guid, sfo.pick = guid, 1
  sfo.lines = TB.SfottiFor(guid)
  sfo.title:SetText("Sfotti " .. Short(all[guid]))
  sfo.text:SetText("Je compare scritto grosso sur su' schermo. Costa " .. Piotte(TB.SFOTTO) .. ".")
  for i, r in ipairs(sfo.radios) do
    r.text:SetText(sfo.lines[i] or "")
    r:SetSize(400, 16)
    r:SetSelected(i == 1)
    r:SetShown(sfo.lines[i] ~= nil)
  end
  sfo:Show()
end

-- er burattino: the master picks an emote, the loser's character does it (once every ten minutes)
S.PUPO_EVERY = 300 -- li fili, once every five minutes
S.PUPO = { { tok = "DANCE", name = "Balla" }, { tok = "CHICKEN", name = "Fa la gallina" }, { tok = "KNEEL", name = "S'inginocchia" },
  { tok = "CRY", name = "Piagne" }, { tok = "SILLY", name = "Fa lo scemo" }, { tok = "BOW", name = "S'inchina" },
  { tok = "FLEX", name = "Fa er bullo" }, { tok = "SURRENDER", name = "Se arrende" } }
local pulled = {} -- guid -> when I last pulled the strings
function S.PuppetOf(guid)
  local g = S.AtGogna(guid)
  local pena = g and S.PENE[g.s.pena or 0]
  return g and pena and pena.key == "pupo" and g.by == ns.recordGuid and g or nil
end
function S.Pull(guid, i)
  if not S.PuppetOf(guid) then return false, "Nun è er burattino tuo." end
  local e = S.PUPO[i]
  if not e then return false end
  local left = (pulled[guid] or 0) + S.PUPO_EVERY - Now()
  if left > 0 then return false, "Li fili se ponno tirà de novo tra " .. math.max(1, math.ceil(left / 60)) .. " minuti." end
  pulled[guid] = Now()
  Send({ t = "pp", on = guid, e = i })
  return true, e
end
local pupo
function S.OpenPuppet(guid)
  local all = Members()
  if not all[guid] then return end
  if not pupo then
    pupo = Dialog("ErPattoBurattino", 360, 186, "Er burattino")
    H.CloseX(pupo)
    pupo.text = H.Text(pupo, "GameFontHighlight", "", 320, "CENTER")
    pupo.text:SetPoint("TOP", 0, -32)
    pupo.btns = {}
    for i, e in ipairs(S.PUPO) do
      local b = H.Btn(pupo, e.name, 140, function()
        local ok, x = S.Pull(pupo.guid, i)
        if Report(pupo, ok, x) then Done(pupo, Name(Members(), pupo.guid) .. ": " .. x.name:lower() .. ".", 3) end
      end, 20)
      b:SetPoint("TOPLEFT", (i % 2 == 1) and 30 or 186, -56 - math.floor((i - 1) / 2) * 24)
      pupo.btns[i] = b
    end
    pupo.msg = H.Text(pupo, "GameFontNormal", "", 320, "CENTER")
    pupo.msg:SetPoint("CENTER", 0, -6)
    pupo.controls = { pupo.text }
    for _, b in ipairs(pupo.btns) do pupo.controls[#pupo.controls + 1] = b end
  end
  Reset(pupo)
  pupo.guid = guid
  pupo.text:SetText("Tiri li fili de " .. H.Colored(all[guid]) .. ": che je fai fà?")
  pupo:Show()
end

local gufa
function S.OpenGufa(guid)
  local all = Members()
  if not all[guid] or guid == ns.recordGuid then return end
  if not gufa then
    gufa = Dialog("ErPattoGufata", 340, 176, "Gufata")
    gufa.text = H.Text(gufa, "GameFontHighlight", "", 300, "CENTER")
    gufa.text:SetPoint("TOP", 0, -32)
    local l = H.Text(gufa, "GameFontNormalSmall", "Posta", 60) l:SetPoint("TOPLEFT", 90, -92)
    gufa.stake = H.Input(gufa, 40, 4)
    if gufa.stake.SetNumeric then gufa.stake:SetNumeric(true) end
    gufa.stake:SetPoint("TOPLEFT", 140, -88)
    local n = H.Text(gufa, "GameFontHighlightSmall", "piotte", 60) n:SetPoint("TOPLEFT", 186, -92)
    gufa.yes = H.Btn(gufa, "Gufa!", 120, function()
      local ok, msg = S.Gufa(gufa.on, gufa.stake:GetText())
      if Report(gufa, ok, msg) then Done(gufa, "Gufata partita: " .. Name(Members(), gufa.on) .. " c'ha 5 minuti.", 3) end
    end)
    gufa.no = H.Btn(gufa, "Lassa stà", 120, function() gufa:Hide() end)
    TwoButtons(gufa, "Gufa!", "Lassa stà")
    gufa.msg = H.Text(gufa, "GameFontNormal", "", 300, "CENTER")
    gufa.msg:SetPoint("CENTER", 0, -20)
    gufa.controls = { gufa.yes, gufa.no, gufa.stake, l, n }
  end
  Reset(gufa)
  gufa.on = guid
  gufa.text:SetText("Je gufi la morte a " .. H.Colored(all[guid]) .. " pe' 5 minuti.\nSi more, vinci mezza posta in più. Si campa, la posta è sua.")
  gufa.stake:SetText("10")
  gufa:Show()
end

----------------------------------------------------------------------
-- my own gogna, on my screen: a debuff as the old ones (icon, red border, time left under it), by the buffs
----------------------------------------------------------------------
local function Left(t)
  local d = math.max(0, t - Now())
  if d >= DAY then return math.floor(d / DAY + 0.5) .. " g" end
  if d >= 3600 then return math.floor(d / 3600 + 0.5) .. " h" end
  if d >= 60 then return math.floor(d / 60 + 0.5) .. " m" end
  return math.floor(d) .. " s"
end
S.Left = Left
-- la pecora: now and then (one minute, on average once every half hour) a sheep over the loser's own character, in
-- the middle of the screen, "Ricordate che Dario te ha 'mpecorato" over it and the seconds left under it. Clicks
-- go through it. Cost: one random number every five seconds while a la gogna (5 s / 1800 s per tick, so on
-- average once every 30 minutes), and a countdown four times a second only while it's up.
S.SHEEP_FOR = 60
S.SHEEP_EVERY = 1800
local card
local sheepUntil = 0
local function SheepUp()
  local now = GetTime and GetTime() or 0
  return now < sheepUntil, sheepUntil - now
end
local function ShowSantino(g)
  local pena = g and S.PENE[g.s.pena or 0]
  if not (pena and pena.key == "img") or not SheepUp() then if card then card:Hide() end return end
  if not card then
    card = CreateFrame("Frame", "ErPattoSantino", UIParent)
    card:SetSize(128, 128)
    card:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    card:SetFrameStrata("BACKGROUND")
    card:EnableMouse(false)
    card.face = card:CreateTexture(nil, "ARTWORK")
    card.face:SetAllPoints()
    card.who = card:CreateFontString(nil, "OVERLAY")
    card.who:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    card.who:SetTextColor(1, 0.82, 0)
    card.who:SetShadowOffset(2, -2)
    card.who:SetPoint("BOTTOM", card, "TOP", 0, 8)
    card.caption = card:CreateFontString(nil, "OVERLAY")
    card.caption:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    card.caption:SetTextColor(1, 1, 1)
    card.caption:SetShadowOffset(2, -2)
    card.caption:SetPoint("TOP", card, "BOTTOM", 0, -6)
    card.acc = 0
    card:SetScript("OnUpdate", function(self, el)
      self.acc = self.acc + (el or 0)
      if self.acc < 0.25 then return end
      self.acc = 0
      local up, left = SheepUp()
      if not up then self:Hide() return end
      self.caption:SetText(string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)))
    end)
  end
  local f = Figure(g.s.id, g.s.e)
  card.face:SetTexture(f.icon)
  card.who:SetText("Ricordate che " .. Short(Members()[g.s.w]) .. " te ha " .. (f.verb or "'mpecorato"))
  local _, left = SheepUp()
  card.caption:SetText(string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)))
  card:Show()
end
-- the dice for the sheep, every five seconds while a la gogna with la pecora
function S.SheepClock(now)
  local g = S.AtGogna(ns.recordGuid)
  local pena = g and S.PENE[g.s.pena or 0]
  if not (pena and pena.key == "img") then return end
  now = now or (GetTime and GetTime() or 0)
  if now < sheepUntil then return end
  if math.random() < 5 / S.SHEEP_EVERY then
    sheepUntil = now + S.SHEEP_FOR
    ShowSantino(g)
  end
end
function S.SheepNow(g) sheepUntil = (GetTime and GetTime() or 0) + S.SHEEP_FOR ShowSantino(g or S.AtGogna(ns.recordGuid)) end
S.ShowSantino = ShowSantino

function S.ShowMyGogna()
  ShowSantino(S.AtGogna(ns.recordGuid))
  if S.RefreshStrip then pcall(S.RefreshStrip) end
end

----------------------------------------------------------------------
-- what's going on for me, under the cap bar: a row of icons as the old buffs and debuffs (red border when it's
-- against me, time left under it, details in the tooltip): a la gogna, la corona, a duello a la gogna in ballo,
-- le sfide, le taje (on me and mine), le gufate (on me and mine). Without the bar, where the gogna icon was.
-- Cost: every ten seconds a look through the lists already worked out (the series are cached by Rebuild), a few
-- dozen entries at most; nothing else while it's shown.
----------------------------------------------------------------------
local strip
local STRIP_MAX, STRIP_SIZE = 8, 26
local function MyStatus()
  local me = ns.recordGuid
  local all = Members()
  local out = {}
  local function add(x) if #out < STRIP_MAX then out[#out + 1] = x end end
  if not (me and all[me]) then return out end
  -- a la gogna
  local g = S.AtGogna(me)
  if g then
    local p = S.PENE[g.s.pena or 0]
    add({ icon = S.PegnoIcon(g.s), bad = true, time = Left(g.til), click = "pena",
      tip = { "A la gogna" .. (p and (": " .. p.name) or ""), S.PegnoYou(g.s) or ("Er pegno lo sta a sceje " .. Name(all, g.by) .. "."),
        "T'ha mannato " .. Name(all, g.by) .. ". Ancora " .. Left(g.til) .. "." } })
  end
  -- la corona
  if S.Champion() == me then
    add({ icon = "Interface\\Icons\\INV_Crown_01", tip = { "La corona de la gogna", "Hai vinto l'urtimo duello a la gogna de chi c'aveva la corona. Chi te batte a la gogna se la pija." } })
  end
  -- a duello a la gogna in ballo
  for _, x in ipairs(S.Last() or {}) do
    if (x.a == me or x.b == me) and (x.state == "incorso" or x.state == "rivincita") then
      local other = x.a == me and x.b or x.a
      local what = x.state == "rivincita" and ((x.last and x.last.l == me) and "Hai perso: pòi chiede la rivincita." or "Ha perso: pò chiede la rivincita.")
        or "La richiesta de duello è partita: chi perde va a la gogna."
      add({ icon = "Interface\\Icons\\Ability_Warrior_Challange", tip = { "Duello a la gogna co' " .. Name(all, other), what } })
    end
  end
  -- le sfide a piotte
  for _, c in ipairs(S.All()) do
    if c.from == me or c.to == me then
      local state, _, ans = S.State(c, all)
      local other = c.from == me and c.to or c.from
      if state == "incorso" then
        local e = ans and ans.e or S.EndOf(ans and ans.at or c.at)
        add({ icon = "Interface\\Icons\\INV_Scroll_03", time = Left(e), click = "sfide",
          tip = { "Sfida co' " .. Name(all, other), S.What(c, all, ans) .. ".", "In palio: " .. Piotte((c.s or 0) * 2) .. ", chi vince se le pija tutte." } })
      elseif state == "aspetta" and c.to == me then
        add({ icon = "Interface\\Icons\\INV_Scroll_03", time = "?", click = "sfide",
          tip = { "Sfida da " .. Name(all, other), S.What(c, all, ans) .. ", " .. Piotte(c.s or 0) .. " a testa.", "Aspetta la risposta tua: Botteghino, Sfide." } })
      end
    end
  end
  -- le taje
  local onMe, onMeN, mine = 0, {}, {}
  for _, t in ipairs(S.Taje()) do
    if S.TajaState(t, all) == "aperta" then
      if t.on == me then onMe = onMe + (t.s or 0) onMeN[#onMeN + 1] = Name(all, t.by) .. " (" .. (t.s or 0) .. ")"
      elseif t.by == me then mine[#mine + 1] = t end
    end
  end
  if onMe > 0 then
    add({ icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath", bad = true, time = tostring(onMe), click = "sfide",
      tip = { "Taja su de te: " .. Piotte(onMe), "Chi te batte a duello pe' primo se le pija.", "L'hanno messa: " .. table.concat(onMeN, ", ") .. "." } })
  end
  for _, t in ipairs(mine) do
    add({ icon = "Interface\\Icons\\Ability_Hunter_MarkedForDeath", time = Left(t.at + S.TAJA_WINDOW), click = "sfide",
      tip = { "Taja tua su " .. Name(all, t.on) .. ": " .. Piotte(t.s or 0), "Chi lo batte a duello pe' primo se le pija. Si nessuno lo batte, te tornano." } })
  end
  -- le gufate
  for _, x in ipairs(S.Gufate()) do
    if (x.on == me or x.by == me) and S.GufaState(x, all) == "aperta" then
      local half = math.floor((x.s or 0) / 2)
      local secs = (x.at or Now()) + S.GUFA - Now()
      local tm = string.format("%d:%02d", math.max(0, math.floor(secs / 60)), math.max(0, math.floor(secs % 60)))
      if x.on == me then
        add({ icon = "Interface\\Icons\\Ability_Hunter_Pet_Owl", bad = true, time = tm,
          tip = { Name(all, x.by) .. " te sta a gufà", "In palio: " .. Piotte(x.s or 0) .. ". Si campi te le pij, si mori ne paghi " .. half .. "." } })
      else
        add({ icon = "Interface\\Icons\\Ability_Hunter_Pet_Owl", time = tm,
          tip = { "Stai a gufà " .. Name(all, x.on), "In palio: " .. Piotte(x.s or 0) .. ". Si more vinci " .. half .. ", si campa le perdi." } })
      end
    end
  end
  return out
end
S.MyStatus = MyStatus

local function BuildStrip()
  strip = CreateFrame("Frame", "ErPattoStato", UIParent)
  strip:SetSize(STRIP_SIZE, STRIP_SIZE + 14)
  strip:SetFrameStrata("MEDIUM")
  strip.icons = {}
  for i = 1, STRIP_MAX do
    local b = CreateFrame("Button", nil, strip)
    b:SetSize(STRIP_SIZE, STRIP_SIZE)
    b:SetPoint("TOPLEFT", (i - 1) * (STRIP_SIZE + 6), 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture("Interface\\Buttons\\UI-Debuff-Border")
    b.border:SetSize(STRIP_SIZE + 3, STRIP_SIZE + 2)
    b.border:SetPoint("CENTER")
    b.border:SetVertexColor(0.8, 0, 0)
    b.time = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.time:SetPoint("TOP", b, "BOTTOM", 0, -2)
    b:SetScript("OnEnter", function(self) if self.data then H.Tip(self, self.data.tip) end end)
    b:SetScript("OnLeave", H.HideTip)
    b:SetScript("OnClick", function(self)
      local d = self.data
      if not d then return end
      if d.click == "pena" then local x = S.AtGogna(ns.recordGuid) if x and x.s.pena then S.ShowPena(x.s) end
      elseif d.click == "sfide" and ns.Botteghino and ns.Botteghino.Show then pcall(ns.Botteghino.Show, "sfide") end
    end)
    strip.icons[i] = b
  end
  if C_Timer then C_Timer.NewTicker(10, function() pcall(S.RefreshStrip) end) end
end

function S.RefreshStrip()
  if not (ns.state and ns.db) or ns.alt then if strip then strip:Hide() end return end
  local list = MyStatus()
  if #list == 0 then if strip then strip:Hide() end return end
  if not strip then BuildStrip() end
  for i, b in ipairs(strip.icons) do
    local d = list[i]
    b.data = d
    if d then
      b.icon:SetTexture(d.icon)
      b.border:SetShown(d.bad and true or false)
      b.time:SetText(d.time or "")
      b:Show()
    else
      b:Hide()
    end
  end
  strip:SetWidth(#list * (STRIP_SIZE + 6) - 6)
  -- under the cap bar when it's there, else where the gogna icon used to be
  strip:ClearAllPoints()
  local hud = _G.ErPattoHUD
  if hud and hud.IsShown and hud:IsShown() then strip:SetPoint("TOP", hud, "BOTTOM", 0, -16)
  else strip:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -205, -110) end
  strip:Show()
end

----------------------------------------------------------------------
-- the gufate going on, mine or on me: a block in the style of the old quest tracker (gold title, "- " lines)
-- with a timer bar as the breath bar of the game (UI-CastingBar-Border-Small), under the minimap
----------------------------------------------------------------------
local watch
local function MMSS(sec) sec = math.max(0, math.floor(sec)) return string.format("%d:%02d", math.floor(sec / 60), sec % 60) end
local function BuildWatch()
  watch = CreateFrame("Frame", "ErPattoGufaWatch", UIParent)
  watch:SetSize(230, 80)
  local pos = ns.db.ui and ns.db.ui.gufa
  if type(pos) == "table" and pos[1] then watch:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else watch:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -40, -240) end
  watch:SetMovable(true)
  watch:EnableMouse(true)
  watch:SetClampedToScreen(true)
  watch:RegisterForDrag("LeftButton")
  watch:SetScript("OnDragStart", watch.StartMoving)
  watch:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.db.ui = ns.db.ui or {}
    ns.db.ui.gufa = { p, rp, x, y }
  end)
  watch.items = {}
  for i = 1, 2 do
    local it = {}
    it.title = watch:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    it.line1 = watch:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    it.line2 = watch:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    for _, f in ipairs({ it.title, it.line1, it.line2 }) do f:SetJustifyH("LEFT") f:SetWidth(230) end
    local bar = CreateFrame("StatusBar", nil, watch)
    bar:SetSize(195, 13)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.8, 0.1, 0.1)
    bar:SetMinMaxValues(0, S.GUFA)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    local border = bar:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border-Small")
    border:SetSize(256, 64)
    border:SetPoint("TOP", 0, 25)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", 0, 1)
    it.bar = bar
    watch.items[i] = it
  end
  watch.acc = 0
  watch:SetScript("OnUpdate", function(self, el)
    self.acc = self.acc + (el or 0)
    if self.acc < 0.25 then return end
    self.acc = 0
    S.GufaWatch()
  end)
  watch:Hide()
end
local ended = {} -- id -> when the result was first seen (shown a few seconds)
function S.GufaWatch()
  if not (ns.state and ns.db) then return end
  local me = ns.recordGuid
  local all = Members()
  local list = {}
  for _, g in ipairs(S.Gufate()) do
    if g.on == me or g.by == me then
      local state = S.GufaState(g, all)
      if state == "aperta" then list[#list + 1] = { g = g }
      elseif Now() - (g.at or 0) < S.GUFA * 3 then
        ended[g.id] = ended[g.id] or Now()
        if Now() - ended[g.id] < 10 then list[#list + 1] = { g = g, state = state } end
      end
    end
    if #list >= 2 then break end
  end
  if #list == 0 then if watch then watch:Hide() end return end
  if not watch then BuildWatch() end
  local y = 0
  for i, it in ipairs(watch.items) do
    local x = list[i]
    local shown = x ~= nil
    for _, f in ipairs({ it.title, it.line1, it.line2, it.bar }) do f:SetShown(shown) end
    if x then
      local g, half = x.g, math.floor(x.g.s / 2)
      local onMe = g.on == me
      local other = Name(all, onMe and g.by or g.on)
      it.title:ClearAllPoints() it.title:SetPoint("TOPLEFT", 0, -y)
      it.line1:ClearAllPoints() it.line1:SetPoint("TOPLEFT", 0, -y - 16)
      it.line2:ClearAllPoints() it.line2:SetPoint("TOPLEFT", 0, -y - 29)
      it.bar:ClearAllPoints() it.bar:SetPoint("TOPLEFT", 4, -y - 48)
      if onMe then
        it.title:SetText("Gufata: " .. other .. " te gufa")
        it.line1:SetText("- In palio: " .. Piotte(g.s))
        it.line2:SetText("- Si campi te le pij, si mori ne paghi " .. half)
      else
        it.title:SetText("Gufata: gufi " .. other)
        it.line1:SetText("- In palio: " .. Piotte(g.s))
        it.line2:SetText("- Si more vinci " .. half .. ", si campa le perdi")
      end
      local left = (g.at or Now()) + S.GUFA - Now()
      if x.state then
        it.bar:SetValue(0)
        local good = (x.state == "campato") == onMe
        it.bar.text:SetText(x.state == "nullo" and "Annullata, posta ridata" or (x.state == "campato" and (onMe and "Sei campato!" or "È campato") or (onMe and "Sei morto" or "È morto!")))
        it.bar:SetStatusBarColor(good and 0.1 or 0.8, good and 0.7 or 0.1, 0.1)
      else
        it.bar:SetStatusBarColor(0.8, 0.1, 0.1)
        it.bar:SetValue(math.max(0, left))
        it.bar.text:SetText(MMSS(left))
      end
      y = y + 72
    end
  end
  watch:SetHeight(math.max(72, y))
  watch:Show()
end

-- the pegni that act by themselves: la figuraccia when coming back to life, er servo bowing to his master
local lastEmote = 0
-- the game's emote. On the newest clients addons may not do emotes by themselves (the game shows its "blocked"
-- window): the first time that happens the build is remembered, and from then on the emote is a line in the emote
-- colour for me and the patto in the same zone (Say, below) instead
S.EMOTE_TEXT = { DANCE = "se mette a ballà.", CHICKEN = "fa la gallina.", KNEEL = "s'inginocchia.", CRY = "piagne.",
  SILLY = "fa lo scemo.", BOW = "s'inchina.", FLEX = "fa er bullo.", SURRENDER = "se arrende." }
local Say
-- the game's own emotes (the animation and the line everyone around reads). They are "AllowedWhenUntainted" only
-- for secret values, which we never pass, so an addon may call them; if the game ever blocks them anyway
-- (Util.lua catches it: ns.OnBlocked), we remember it for this build and write the line ourselves instead
local function Build() return GetBuildInfo and tostring(select(2, GetBuildInfo())) or "?" end
local function Refused(what) return ns.db and type(ns.db.refused) == "table" and ns.db.refused[what] == Build() end
ns.OnBlocked = function(x)
  if not ns.db then return end
  ns.db.refused = type(ns.db.refused) == "table" and ns.db.refused or {}
  local fn = tostring(x and x.fn or "")
  if fn:find("Emote") then ns.db.refused.emote = Build() end
  if fn:find("SendChatMessage") then ns.db.refused.chat = Build() end
end
local function Emote(tok, target)
  local now = GetTime and GetTime() or 0
  if now - lastEmote < 2 then return end
  lastEmote = now
  local perform = (C_ChatInfo and C_ChatInfo.PerformEmote) or DoEmote
  if perform and not Refused("emote") and not (InCombatLockdown and InCombatLockdown()) then
    pcall(perform, tok, target)
  elseif Say and S.EMOTE_TEXT[tok] then
    Say(S.EMOTE_TEXT[tok])
  end
end
S.Emote = Emote
-- er servo: his line when his master is near
local lastNear = 0
local function Master()
  local g = S.AtGogna(ns.recordGuid)
  local pena = g and S.PENE[g.s.pena or 0]
  if not (pena and pena.key == "servo") then return nil end
  return Members()[g.by]
end
-- what er servo says, in the emote colour, when his master is near: at most once every ten minutes
S.SERVO_LINE = "is the slave of %s."
S.SERVO_EVERY = 600
local saidAt, saidN = 0, 0
-- a line in the emote colour, as if said: addons can't write in the chat any more (SendChatMessage is blocked
-- for them and the game shows its "blocked" window), so it goes as a quick message to the patto in the same zone
-- and in my own chat window
local function EmoteLine(who, text)
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then f:AddMessage(tostring(who) .. " " .. text, 1, 0.5, 0.25) end
end
-- a /me line: the game's emote chat, read by everyone around (EMOTE needs no click, unlike SAY and YELL); if the
-- game refuses it, my chat and the patto's in the same zone instead
function Say(text)
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  if send and not Refused("chat") and not (InCombatLockdown and InCombatLockdown()) then
    if pcall(send, text, "EMOTE") then return end
  end
  local rec = ns.MyRecord and ns.MyRecord()
  EmoteLine(Short(rec), text)
  local z = GetRealZoneText and U.Plain(GetRealZoneText(), "string")
  Send({ t = "em", x = text, z = z })
end
S.Say = Say
local function NearBow()
  local master = Master()
  if not master then return end
  local now = GetTime and GetTime() or 0
  if now - lastNear < 60 or (InCombatLockdown and InCombatLockdown()) then return end
  local u = UnitFor(master.name)
  local near = u and CheckInteractDistance and select(2, pcall(CheckInteractDistance, u, 4))
  if near == true then
    lastNear = now
    Emote("BOW", u)
    -- he comes near (or stays): "X is the slave of Aldo.", once every ten minutes at most
    if saidAt == 0 or now - saidAt >= S.SERVO_EVERY then
      saidAt, saidN = now, saidN + 1
      Say(S.SERVO_LINE:format(Short(master)))
    end
  end
end
S.NearBow = NearBow
-- er karaoke: every kill starts one of the songs (and one plays anyway after ten minutes without); never two at once.
-- The speed: 0.5x and 1.5x one time in ten each (the jackpot, told in the chat), the rest round 1x. The pitch goes
-- with the speed. The speeds are ready-made files (the game can't change a sound's speed). Only the one a la
-- gogna hears it (the others aren't punished). Cost: one random number per kill and a look at the clock every five seconds.
S.KARAOKE_CHANCE = 1 -- every mob killed (never two songs at once)
S.KARAOKE_EVERY = 600
S.KARAOKE_SONGS = 4
S.KARAOKE_LENGTH = { 6.6, 7.8, 6.6, 22.9 } -- seconds at 1x
S.KARAOKE_SPEEDS = { 50, 70, 85, 100, 115, 130, 150 }
S.KARAOKE_WEIGHTS = { 10, 12, 16, 24, 16, 12, 10 } -- out of 100
local karaAt, karaUntil = 0, 0
local function KaraFile(i, sp) return H.MEDIA .. "karaoke\\k" .. i .. "_" .. string.format("%03d", sp) .. ".ogg" end
S.KaraFile = KaraFile
local function KaraSpeed()
  local r, acc = math.random(100), 0
  for k, wgt in ipairs(S.KARAOKE_WEIGHTS) do
    acc = acc + wgt
    if r <= acc then return S.KARAOKE_SPEEDS[k] end
  end
  return 100
end
S.KaraSpeed = KaraSpeed
local function PlayKara(i, sp)
  if PlaySoundFile then pcall(PlaySoundFile, KaraFile(i, sp), "Master") end
  local now = GetTime and GetTime() or 0
  karaUntil = now + (S.KARAOKE_LENGTH[i] or 8) * 100 / sp + 1
end
-- er burattino: the strings are pulled: the emote, the line everyone around reads, and for him alone the music of
-- the strings (Media/pupo, ten seconds)
S.PUPO_SOUND = "pupo\\fili.ogg"
function S.Puppet(e, master)
  if not e then return end
  lastEmote = 0
  Emote(e.tok)
  Say("se fa tirà li fili da " .. tostring(master) .. ".")
  if PlaySoundFile then pcall(PlaySoundFile, H.MEDIA .. S.PUPO_SOUND, "Master") end
  -- on his screen, in the raid warning letters (the game doesn't let an addon stop a character: no freezing)
  if RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, tostring(master) .. " te sta a tirà li fili: fa' er bravo burattino!", { r = 1, g = 0.5, b = 0.2 })
  end
end

-- er Giampaolato: a jump plays "ahia" (four times in five) or "basta"; a /thanks plays er Cerbero for him and for
-- the one thanked, if he's of the patto. Cost: one look at my gogna per jump or emote (hooks after the game's own)
S.GIAMPY = { ahia = "ahia.ogg", basta = "basta.ogg", cerbero = "cerbero.ogg", AHIA = 0.8 }
local function Giampy(file) if PlaySoundFile then pcall(PlaySoundFile, H.MEDIA .. "giampy\\" .. file, "Master") end end
S.Giampy = Giampy
local function Giampaolato()
  local g = S.AtGogna(ns.recordGuid)
  local pena = g and S.PENE[g.s.pena or 0]
  return pena and pena.key == "giampy"
end
local jumpAt = 0
function S.OnJump()
  if not Giampaolato() then return end
  local now = GetTime and GetTime() or 0
  if now - jumpAt < 0.7 then return end
  jumpAt = now
  Giampy(math.random() < S.GIAMPY.AHIA and S.GIAMPY.ahia or S.GIAMPY.basta)
end
function S.OnEmote(token, target)
  if type(token) ~= "string" or U.IsSecret(token) then return end
  local t = token:upper()
  if t ~= "THANK" and t ~= "THANKS" and t ~= "TY" then return end
  if not Giampaolato() then return end
  Giampy(S.GIAMPY.cerbero)
  local name = (type(target) == "string" and not U.IsSecret(target) and target ~= "") and target or nil
  if not name and UnitName then
    local ok, n = pcall(UnitName, "target")
    if ok and type(n) == "string" and not U.IsSecret(n) then name = n end
  end
  if not name then return end
  for guid, m in pairs(Members()) do
    if guid ~= ns.recordGuid and (m.name == name or Short(m) == name or Short(m) == name:match("^([^%-]+)")) then Send({ t = "gy", to = guid }) end
  end
end
if hooksecurefunc then
  if JumpOrAscendStart then pcall(hooksecurefunc, "JumpOrAscendStart", function() pcall(S.OnJump) end) end
  if C_ChatInfo and C_ChatInfo.PerformEmote then pcall(hooksecurefunc, C_ChatInfo, "PerformEmote", function(tok, tgt) pcall(S.OnEmote, tok, tgt) end)
  elseif DoEmote then pcall(hooksecurefunc, "DoEmote", function(tok, tgt) pcall(S.OnEmote, tok, tgt) end) end
end
-- the jackpot line, as a slot machine would say it
local function Jackpot(sp)
  local f = DEFAULT_CHAT_FRAME
  if not (f and f.AddMessage) then return end
  local what = sp < 100 and "|cffa335eeLA VERSIONE AR RALLENTATORE (0,5x)|r" or "|cffa335eeLA VERSIONE TURBO (1,5x)|r"
  f:AddMessage("|cffff8000***  J A C K P O T  ***|r")
  f:AddMessage("|cffffd100Daje! Hai trovato " .. what .. "|cffffd100, er pull più raro der karaoke: esce una vorta su dieci!|r")
  f:AddMessage("|cffffd100Arza er volume, fatte 'n giro e gòdete 'sto capolavoro. Er banco t'aringrazia.|r")
end
function S.Karaoke(force)
  local g = S.AtGogna(ns.recordGuid)
  local pena = g and S.PENE[g.s.pena or 0]
  if not (pena and pena.key == "kara") then return false end
  local now = GetTime and GetTime() or 0
  if now < karaUntil then return false end -- one at a time
  local chance = S.KARAOKE_CHANCE
  if not force and math.random() >= chance then return false end
  karaAt = now
  local i, sp = math.random(S.KARAOKE_SONGS), KaraSpeed()
  PlayKara(i, sp)
  if sp == 50 or sp == 150 then Jackpot(sp) end
  return true, i, sp
end
-- the ten minutes without a song: one comes anyway
local function KaraClock()
  local g = S.AtGogna(ns.recordGuid)
  local pena = g and S.PENE[g.s.pena or 0]
  if not (pena and pena.key == "kara") then return end
  local now = GetTime and GetTime() or 0
  if karaAt == 0 then karaAt = now return end
  if now - karaAt >= S.KARAOKE_EVERY then S.Karaoke(true) end
end
S.KaraClock = KaraClock
-- a kill: the target seen dead, or experience that isn't from a quest; one song per kill even when both say so
local killAt = 0
local function Killed()
  local now = GetTime and GetTime() or 0
  if now - killAt < 1 then return end
  killAt = now
  pcall(S.Karaoke)
end
ns.On("J_Kill", Killed)
ns.On("J_XpKill", Killed)
-- er piagnone: a cry every two minutes (not in a fight); "nguee nguee" too when his winner is near. The look for
-- the winner is cheap: the usual unit tokens, once every two minutes
local cryAt = 0
local function Crybaby()
  local g = S.AtGogna(ns.recordGuid)
  local pena = g and S.PENE[g.s.pena or 0]
  if not (pena and pena.key == "cry") then return end
  local now = GetTime and GetTime() or 0
  if now - cryAt < 120 or (InCombatLockdown and InCombatLockdown()) then return end
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
  cryAt = now
  lastEmote = 0
  local master = Members()[g.by]
  local u = master and UnitFor(master.name)
  local near = u and CheckInteractDistance and select(2, pcall(CheckInteractDistance, u, 4))
  Emote("CRY")
  if near == true then Say("piagne: \"nguee nguee\"") end
end
S.Crybaby = Crybaby


-- test mode: my pegni for two minutes, the dialogs, a duel to bet on, to see how they look
local function Fakes()
  local out = {}
  for _, m in ipairs(UI.Members()) do if m.fake then out[#out + 1] = m.guid end end
  return out
end
local testPena = 0
function S.TestGogna()
  local f = Fakes()
  testPena = testPena % #S.PENE + 1
  local pena = S.PENE[testPena]
  test.s = { id = "prova:" .. testPena, w = f[1] or ns.recordGuid, pena = testPena, t = pena.key == "bee" and "bee" or nil,
    e = 1, te = Now(), til = Now() + 120 }
  Rebuild()
  S.ShowMyGogna()
  local all = Members()
  if ns.News then ns.News.Banner(Short(ns.MyRecord()) .. " va a la gogna!", S.PegnoText(test.s, all) .. ", pe' du' minuti (prova).", { 1, 0.5, 0.2 }, "evento") end
  S.ShowPena(test.s, all)
  -- what the pegno does by itself, at once, so it can be seen and heard without anyone else
  local master = Short(all[test.s.w])
  local function Soon(fn) if C_Timer then C_Timer.After(1.5, fn) else fn() end end
  if pena.key == "img" then
    S.SheepNow()
  elseif pena.key == "pupo" then
    Soon(function() S.Puppet(S.PUPO[1], master) end)
  elseif pena.key == "cry" then
    Soon(function() lastEmote = 0 Emote("CRY") Say("piagne: \"nguee nguee\"") end)
  elseif pena.key == "servo" then
    Soon(function() lastEmote = 0 Emote("BOW") Say(S.SERVO_LINE:format(master)) end)
  elseif pena.key == "kara" then
    karaAt, karaUntil = 0, 0
    Soon(function() S.Karaoke(true) end)
  elseif pena.key == "giampy" then
    Soon(function() S.Giampy(S.GIAMPY.ahia) end)
  end
  if UI.Refresh then UI.Refresh() end
  if C_Timer then C_Timer.After(121, function() Rebuild() S.ShowMyGogna() UI.Refresh() end) end
  return pena.name
end
function S.TestAsk()
  local f = Fakes()
  if not f[1] then return end
  S.Called({ n = 1, cur = { id = "prova", from = f[1], to = ns.recordGuid } })
end
function S.TestRematch()
  local f = Fakes()
  if not f[1] then return end
  S.OfferRematch({ id = "prova", n = 1, last = { w = f[1], l = ns.recordGuid, at = Now() } })
end
-- the clip after a duel, alone: one click the winner's, the next the loser's
local testWon = false
function S.TestClip()
  testWon = not testWon
  local f = {}
  for guid, m in pairs(Members()) do if guid ~= ns.recordGuid then f[#f + 1] = Short(m) end end
  S.DuelClip(testWon, f[1] or "Er compare", testWon and 4 or 2, testWon and 2 or 4)
end

function S.TestPegno()
  local f = Fakes()
  if not f[1] then return end
  S.ShowPegno({ id = "prova", w = ns.recordGuid, l = f[1], te = Now(), duels = { {} } })
end
function S.TestBet()
  local f = Fakes()
  if f[2] then S.ShowBet(f[1], f[2], true) end
end

----------------------------------------------------------------------
-- events: quick messages, duel requests, the right click menu
----------------------------------------------------------------------
local function Txt(t, n) return type(t) == "string" and t:gsub("|", ""):sub(1, n) or nil end
ns.On("Live", function(from, data)
  if type(data) ~= "table" or not ns.state or type(from) ~= "string" then return end
  local me = ns.recordGuid
  local all = Members()
  if data.t == "sf" and type(data.c) == "table" and data.c.to == me then
    local st = Store()
    local c = data.c
    if st and type(c.id) == "string" and not ns.alt then
      local x = { id = c.id:sub(1, 40), from = from, to = me, k = Txt(c.k, 1), n = tonumber(c.n), st = Txt(c.st, 3), s = math.floor(tonumber(c.s) or 0), at = tonumber(c.at) or Now() }
      if x.k == "s" or x.k == "l" then
        liveSf[x.id] = x
        if not st.asked[x.id] then st.asked[x.id] = true S.Ask(x, all) end
      end
    end
  elseif data.t == "gd" and type(data.c) == "table" and type(data.c.id) == "string" then
    local c = data.c
    liveGd[c.id:sub(1, 40)] = { id = c.id:sub(1, 40), from = from, to = Txt(c.to, 60), rv = Txt(c.rv, 40), x = (tonumber(c.x) == 1 or tonumber(c.x) == 2) and tonumber(c.x) or nil, at = tonumber(c.at) or Now() }
    S.Update()
    return
  elseif data.t == "gp" and type(data.x) == "table" and type(data.x.id) == "string" then
    local x = data.x
    livePick[x.id:sub(1, 40)] = { id = x.id:sub(1, 40), p = tonumber(x.p), t = Txt(x.t, 20), e = tonumber(x.e), at = tonumber(x.at) or Now(), by = from }
    S.Update()
    return
  elseif data.t == "ans" and type(data.id) == "string" then
    liveAns[data.id:sub(1, 40)] = { id = data.id:sub(1, 40), a = tonumber(data.a) == 1 and 1 or 0, at = Now(), by = from }
    S.Update()
    return
  elseif data.t == "live" and data.a ~= me and data.b ~= me and not ns.alt then
    local z = GetRealZoneText and U.Plain(GetRealZoneText(), "string")
    if data.z and z == data.z and all[data.a] and all[data.b] then
      S.ShowBet(data.a, data.b, data.g == 1)
    elseif all[data.a] and all[data.b] and ns.News then
      ns.News.Add(GOLD .. Short(all[data.a]) .. "|r e " .. GOLD .. Short(all[data.b]) .. "|r se stanno a menà" .. (data.g == 1 and " a la gogna" or "") .. (data.z and (" a " .. tostring(data.z)) or "") .. ".")
    end
  elseif data.t == "gok" and type(data.id) == "string" then
    Accepted(data.id:sub(1, 40))
  elseif data.t == "gy" and data.to == ns.recordGuid and not ns.alt then
    -- the Giampaolato thanked me: er Cerbero
    local g = S.AtGogna(from)
    local pena = g and S.PENE[g.s.pena or 0]
    if pena and pena.key == "giampy" then S.Giampy(S.GIAMPY.cerbero) end
  elseif data.t == "em" and type(data.x) == "string" and not ns.alt then
    local z = GetRealZoneText and U.Plain(GetRealZoneText(), "string")
    if data.z and z == data.z and all[from] then EmoteLine(Short(all[from]), data.x:gsub("|", ""):sub(1, 120)) end
  elseif data.t == "pp" and data.on == me then
    local g = S.AtGogna(me)
    local pena = g and S.PENE[g.s.pena or 0]
    local e = S.PUPO[tonumber(data.e) or 0]
    if g and pena and pena.key == "pupo" and g.by == from and e and Now() - (pulled.me or 0) >= 1 then
      pulled.me = Now()
      S.Puppet(e, Short(all[from]))
    end
  elseif data.t == "gf" and type(data.id) == "string" and type(data.on) == "string" then
    liveGf[data.id:sub(1, 40)] = { id = data.id:sub(1, 40), on = data.on:sub(1, 60), s = math.floor(tonumber(data.s) or 0), at = tonumber(data.at) or Now(), by = from }
    if data.on == me then Epic() end
    S.GufaWatch()
  end
  if C_Timer then C_Timer.After(3, S.Update) end
end)

-- someone asks me for a duel: if both are in the patto, everyone near can bet
local function OnDuelRequested(name)
  if not ns.state or ns.alt or U.IsSecret(name) or type(name) ~= "string" then return end
  for guid, m in pairs(ns.state.members) do
    if guid ~= ns.recordGuid and (m.name == name or Short(m) == name) then
      local gogna = false
      for _, s in ipairs(S.Series()) do
        if s.state == "incorso" and ((s.a == guid and s.b == ns.recordGuid) or (s.b == guid and s.a == ns.recordGuid)) then gogna = true end
      end
      S.Live(guid, ns.recordGuid, gogna)
      return
    end
  end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
  if event == "DUEL_REQUESTED" then pcall(OnDuelRequested, ...)
  elseif event == "DUEL_COUNTDOWN" then pcall(S.DuelStarts)
  elseif event == "DUEL_FINISHED" then
    -- after a real duel the result is in by then; if not, the request was turned down
    if C_Timer then C_Timer.After(4, function() pcall(S.Update) pcall(TurnedDown) end) end
  end
end)
for _, e in ipairs({ "DUEL_REQUESTED", "DUEL_FINISHED", "DUEL_COUNTDOWN" }) do pcall(frame.RegisterEvent, frame, e) end

local function AddMenu()
  if not (Menu and Menu.ModifyMenu) then return end
  for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET" }) do
    pcall(Menu.ModifyMenu, tag, function(owner, root, data)
      if not (ns.state and not ns.alt and data and data.name) then return end
      for guid, m in pairs(ns.state.members) do
        if guid ~= ns.recordGuid and (m.name == data.name or Short(m) == data.name) then
          if root.CreateDivider then root:CreateDivider() end
          root:CreateButton("Duello a la gogna", function() S.OpenDuel(guid, data.unit) end)
          root:CreateButton("Gufata", function() S.OpenGufa(guid) end)
          root:CreateButton("Sfotti", function() S.OpenSfotti(guid) end)
          if S.PuppetOf(guid) then root:CreateButton("Tira li fili", function() S.OpenPuppet(guid) end) end
          return
        end
      end
    end)
  end
end

ns.On("MemberUpdated", function() S.Update() end)
ns.On("SelfChanged", function(state, reason) if reason ~= "pts" and reason ~= "sfide" then Rebuild() end end)
ns.On("Login", function()
  AddMenu()
  if C_Timer then
    C_Timer.NewTicker(5, function() pcall(NearBow) pcall(Crybaby) pcall(KaraClock) pcall(S.SheepClock) end)
    C_Timer.After(10, S.Update)
    C_Timer.NewTicker(30, S.Update)
  end
end)

----------------------------------------------------------------------
-- the Sfide page of Er Botteghino: sfide a piotte, taje, gufate
----------------------------------------------------------------------
local form = {}

-- a vanilla list under a button (the dropdown look: a dialog box); items: { { value, label }, ... }
local chooser
local function Choose(anchor, items, onPick)
  if not chooser then
    chooser = CreateFrame("Frame", "ErPattoChoose", UIParent)
    chooser:SetFrameStrata("DIALOG")
    chooser:SetToplevel(true)
    chooser:EnableMouse(true)
    H.Chrome(chooser)
    chooser.rows = {}
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoChoose") end
    -- a click anywhere else closes it: an invisible layer over the screen, under the list (as the old dropdowns)
    local catcher = CreateFrame("Button", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("DIALOG")
    catcher:EnableMouse(true)
    catcher:RegisterForClicks("AnyUp")
    catcher:SetScript("OnClick", function(self) self:Hide() chooser:Hide() end)
    catcher:Hide()
    chooser.catcher = catcher
    chooser:SetScript("OnShow", function(self)
      catcher:SetFrameLevel(math.max(1, self:GetFrameLevel() - 1))
      catcher:Show()
    end)
    chooser:SetScript("OnHide", function() catcher:Hide() end)
  end
  chooser:SetFrameLevel(100)
  chooser.anchor = anchor
  for _, r in ipairs(chooser.rows) do r:Hide() end
  local shown = math.min(20, #items)
  for i = 1, shown do
    local r = chooser.rows[i]
    if not r then
      r = CreateFrame("Button", nil, chooser)
      r:SetSize(170, 16)
      r:SetFrameLevel(chooser:GetFrameLevel() + 2)
      r:RegisterForClicks("LeftButtonUp")
      r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
      r.text = H.Text(r, "GameFontHighlightSmall", "", 166)
      r.text:SetPoint("LEFT", 4, 0)
      r:SetScript("OnClick", function(self) chooser:Hide() chooser.catcher:Hide() if chooser.onPick then chooser.onPick(self.value) end UI.Refresh() end)
      chooser.rows[i] = r
    end
    r.value = items[i][1]
    r.text:SetText(items[i][2])
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 16, -16 - (i - 1) * 16)
    r:Show()
  end
  chooser.onPick = onPick
  chooser:SetSize(202, 32 + shown * 16)
  chooser:ClearAllPoints()
  chooser:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  chooser:Show()
end
S.Choose = Choose

local function MemberItems()
  local items = {}
  local list = {}
  for _, m in ipairs(UI.Members()) do if m.guid ~= ns.recordGuid then list[#list + 1] = m end end
  table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
  for _, m in ipairs(list) do items[#items + 1] = { m.guid, H.Colored(m) .. GREY .. "  " .. tostring(m.lv or "?") .. "|r" } end
  return items
end

local function WhatItems(other)
  local items = {}
  for _, x in ipairs(S.STATS) do items[#items + 1] = { "s:" .. x.key, x.low and "Chi more de meno" or ("Chi fa più " .. x.name:lower()) } end
  local race = S.RaceLevel(other)
  if race then items[#items + 1] = { "l", "Chi arriva prima ar " .. race } end
  return items
end
local function WhatLabel(other)
  for _, it in ipairs(WhatItems(other)) do
    if (form.k == "s" and it[1] == "s:" .. tostring(form.st)) or (form.k == "l" and it[1] == "l") then return it[2] end
  end
  return "Scegli"
end

function S.Prefill(guid)
  form.to = guid
  if ns.Botteghino then ns.Botteghino.Show("sfide") end
end

-- the answers of the Sfide page go in the Botteghino's status line, by the piotte
local function PageSay(ok, msg, good)
  if ns.Botteghino and ns.Botteghino.Say then ns.Botteghino.Say(ok, msg or "Nun se pò fà.", good) end
end
function S.BuildPage(v)
  local p = CreateFrame("Frame", nil, v)
  p:SetAllPoints()
  v.sfide = p
  local function Label(box, text, y) local l = H.Text(box, "GameFontNormalSmall", text, 70) l:SetPoint("TOPLEFT", 14, y) return l end
  -- throw a sfida
  local a = H.Box(p, 360, 150)
  a:SetPoint("TOPLEFT", 0, -28)
  local t = H.Text(a, "GameFontNormal", "Lancia 'na sfida", 200) t:SetPoint("TOPLEFT", 12, -12)
  Label(a, "Contro", -38)
  p.who = H.Dropdown(a, 170, function(self) Choose(self, MemberItems(), function(g) form.to = g end) end)
  p.who:SetPoint("TOPLEFT", 84, -31)
  Label(a, "Su che", -68)
  p.what = H.Dropdown(a, 170, function(self)
    Choose(self, WhatItems(form.to and Members()[form.to]), function(x)
      if x:sub(1, 2) == "s:" then form.k, form.st = "s", x:sub(3) else form.k, form.st = x, nil end
    end)
  end)
  p.what:SetPoint("TOPLEFT", 84, -61)
  Label(a, "Posta", -98)
  p.stake = H.Input(a, 50, 5)
  if p.stake.SetNumeric then p.stake:SetNumeric(true) end
  p.stake:SetPoint("TOPLEFT", 90, -94)
  p.until_ = H.Text(a, "GameFontHighlightSmall", "", 200) p.until_:SetPoint("TOPLEFT", 148, -98)
  p.go = H.Btn(a, "Sfida!", 100, function()
    local ok, msg = S.Challenge({ to = form.to, k = form.k, st = form.st, s = p.stake:GetText() })
    if ok then p.stake:SetText("") end
    PageSay(ok, msg, "Sfida mannata a " .. Short(Members()[form.to] or {}) .. ".")
  end, 22)
  p.go:SetPoint("BOTTOMRIGHT", -12, 12)
  p.testGogna = H.Btn(a, "Prova: gogna", 92, function() S.TestGogna() end, 18)
  p.testGogna:SetPoint("TOPRIGHT", -10, -8)
  p.testClip = H.Btn(a, "Prova: filmato", 88, function() S.TestClip() end, 18)
  p.testClip:SetPoint("RIGHT", p.testGogna, "LEFT", -2, 0)

  -- put a taja: one line
  local b = H.Box(p, 360, 71)
  b:SetPoint("TOPLEFT", 0, -184)
  local tb = H.Text(b, "GameFontNormal", "Metti 'na taja", 200) tb:SetPoint("TOPLEFT", 12, -10)
  local l1 = H.Text(b, "GameFontNormalSmall", "Su chi", 50) l1:SetPoint("TOPLEFT", 14, -39)
  p.on = H.Dropdown(b, 110, function(self) Choose(self, MemberItems(), function(g) form.on = g end) end)
  p.on:SetPoint("TOPLEFT", 60, -32)
  local l2 = H.Text(b, "GameFontNormalSmall", "Taja", 40) l2:SetPoint("TOPLEFT", 180, -38)
  p.taja = H.Input(b, 40, 5)
  if p.taja.SetNumeric then p.taja:SetNumeric(true) end
  p.taja:SetPoint("TOPLEFT", 216, -34)
  p.put = H.Btn(b, "Metti", 70, function()
    local ok, msg = S.Taja(form.on, p.taja:GetText())
    if ok then p.taja:SetText("") end
    PageSay(ok, msg, "Taja messa: " .. Piotte(tonumber(p.taja:GetText()) or 0) .. " su " .. Short(Members()[form.on] or {}) .. ".")
  end, 20)
  p.put:SetPoint("TOPRIGHT", -12, -34)

  -- taje and gufate going on
  local d = H.Box(p, 360, 114)
  d:SetPoint("TOPLEFT", 0, -261)
  local td = H.Text(d, "GameFontNormal", "Taje e gufate", 240) td:SetPoint("TOPLEFT", 12, -12)
  -- all of them, the open ones first, with a vanilla scroll when they don't fit
  local scroll = CreateFrame("ScrollFrame", "ErPattoTajeScroll", d, "UIPanelScrollFrameTemplate")
  if H.VanillaScroll then H.VanillaScroll(scroll) end
  scroll:SetPoint("TOPLEFT", 12, -28)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)
  p.tajeBody = CreateFrame("Frame", nil, scroll)
  p.tajeBody:SetSize(316, 10)
  scroll:SetScrollChild(p.tajeBody)
  p.tajeScroll = scroll
  p.lines = {}

  -- the sfide
  local c = H.Box(p, 378, 347)
  c:SetPoint("TOPLEFT", 366, -28)
  local tc = H.Text(c, "GameFontNormal", "Le sfide", 200) tc:SetPoint("TOPLEFT", 12, -12)
  p.testBet = H.Btn(c, "Prova: scommessa", 104, function() S.TestBet() end, 18)
  p.testBet:SetPoint("TOPRIGHT", -10, -8)
  p.testPegno = H.Btn(c, "Prova: pegno", 80, function() S.TestPegno() end, 18)
  p.testPegno:SetPoint("RIGHT", p.testBet, "LEFT", -2, 0)
  p.testAsk = H.Btn(c, "Prova: duello", 84, function() S.TestAsk() end, 18)
  p.testAsk:SetPoint("RIGHT", p.testPegno, "LEFT", -2, 0)
  p.rows = {}
  for i = 1, 10 do
    local y = -34 - (i - 1) * 31
    local r = {}
    r.top = H.Text(c, "GameFontHighlightSmall", "", 230) r.top:SetPoint("TOPLEFT", 14, y)
    if r.top.SetWordWrap then r.top:SetWordWrap(false) end
    r.state = H.Text(c, "GameFontHighlightSmall", "", 120, "RIGHT") r.state:SetPoint("TOPRIGHT", -14, y)
    r.what = H.Text(c, "GameFontDisableSmall", "", 350) r.what:SetPoint("TOPLEFT", 14, y - 13)
    if r.what.SetWordWrap then r.what:SetWordWrap(false) end
    r.yes = H.Btn(c, "Ce sto", 58, function(self) local ok, msg = S.Answer(self.id, true) PageSay(ok, msg, "Sfida accettata: in bocca ar lupo.") end, 16)
    r.yes:SetPoint("TOPRIGHT", -54, y - 12)
    r.no = H.Btn(c, "No", 40, function(self) local ok, msg = S.Answer(self.id, false) PageSay(ok, msg, "Sfida rifiutata.") end, 16)
    r.no:SetPoint("TOPRIGHT", -12, y - 12)
    p.rows[i] = r
  end
  p.none = H.Text(c, "GameFontDisableSmall", "", 340) p.none:SetPoint("TOPLEFT", 14, -34)
end

local STATE_TEXT = { aspetta = GREY .. "aspetta risposta|r", rifiutata = GREY .. "rifiutata|r", scaduta = GREY .. "scaduta|r", incorso = GOLD .. "in corso|r" }

function S.RefreshPage(v)
  local p = v.sfide
  local all = Members()
  local testing = ns.Tombola and ns.Tombola.Testing() and true or false
  p.testGogna:SetShown(testing) p.testClip:SetShown(testing) p.testAsk:SetShown(testing) p.testBet:SetShown(testing) p.testPegno:SetShown(testing)
  local other = form.to and all[form.to]
  p.who:SetText(other and Short(other) or "Scegli")
  p.what:SetText(WhatLabel(other))
  p.until_:SetText("piotte, fino a " .. U.Day(S.EndOf(Now())))
  p.on:SetText(form.on and all[form.on] and Short(all[form.on]) or "Scegli")
  -- the buttons stay clickable: a click without what's needed says what's missing
  -- the sfide: mine first
  local list = S.All()
  table.sort(list, function(a, b)
    local am = (a.from == ns.recordGuid or a.to == ns.recordGuid) and 1 or 0
    local bm = (b.from == ns.recordGuid or b.to == ns.recordGuid) and 1 or 0
    if am ~= bm then return am > bm end
    return (a.at or 0) > (b.at or 0)
  end)
  local shown = 0
  for i, r in ipairs(p.rows) do
    local c = list[i]
    if c then
      shown = shown + 1
      local state, res, ans = S.State(c, all)
      r.top:SetText(H.Colored(all[c.from] or { name = "?" }) .. " contro " .. H.Colored(all[c.to] or { name = "?" }))
      local stText = STATE_TEXT[state]
      if state == "finita" then
        stText = res.w == "" and (GREY .. "pari, poste ridate|r") or ("vince " .. GOLD .. Short(all[res.w]) .. "|r")
      end
      r.state:SetText(stText or "")
      r.what:SetText(S.What(c, all, ans) .. ", " .. Piotte(c.s))
      local ask = state == "aspetta" and c.to == ns.recordGuid
      r.yes.id, r.no.id = c.id, c.id
      r.yes:SetShown(ask) r.no:SetShown(ask)
      r.top:Show() r.state:Show() r.what:Show()
    else
      r.top:Hide() r.state:Hide() r.what:Hide() r.yes:Hide() r.no:Hide()
    end
  end
  p.none:SetText(shown == 0 and (GREY .. "Ancora nessuna sfida.|r") or "")
  local open, done = {}, {}
  for _, t in ipairs(S.Taje()) do
    local st, r = S.TajaState(t, all)
    local who = "Taja de " .. Short(all[t.by] or { name = "?" }) .. " su " .. H.Colored(all[t.on] or { name = "?" })
    if st == "aperta" then open[#open + 1] = { who, Piotte(t.s) }
    else done[#done + 1] = { GREY .. who .. ((r and r.w and r.w ~= "" and all[r.w]) and (", presa da " .. Short(all[r.w])) or ", scaduta") .. "|r", GREY .. Piotte(t.s) .. "|r" } end
  end
  for _, g in ipairs(S.Gufate()) do
    local st = S.GufaState(g, all)
    local who = Short(all[g.by] or { name = "?" }) .. " gufa " .. H.Colored(all[g.on] or { name = "?" })
    if st == "aperta" then open[#open + 1] = { who, Piotte(g.s) }
    else done[#done + 1] = { GREY .. who .. (st == "morto" and ", è morto" or st == "campato" and ", è campato" or ", annullata") .. "|r", GREY .. Piotte(g.s) .. "|r" } end
  end
  local lines = open
  for _, x in ipairs(done) do lines[#lines + 1] = x end
  if #lines == 0 then lines[1] = { GREY .. "Nessuna taja o gufata.|r", "" } end
  for i, x in ipairs(lines) do
    local l = p.lines[i]
    if not l then
      l = H.Text(p.tajeBody, "GameFontHighlightSmall", "", 236) l:SetPoint("TOPLEFT", 2, -(i - 1) * 15)
      if l.SetWordWrap then l:SetWordWrap(false) end
      l.right = H.Text(p.tajeBody, "GameFontHighlightSmall", "", 76, "RIGHT") l.right:SetPoint("TOPRIGHT", 0, -(i - 1) * 15)
      p.lines[i] = l
    end
    l:SetText(x[1]) l.right:SetText(x[2])
  end
  for i = #lines + 1, #p.lines do p.lines[i]:SetText("") p.lines[i].right:SetText("") end
  p.tajeBody:SetHeight(math.max(10, #lines * 15))
  if UI.FitScroll then UI.FitScroll(p.tajeScroll, #lines * 15, 114 - 36) end
end
