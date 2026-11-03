-- Er Patto: le sfide, la gogna, le taje, le gufate e le scommesse sui duelli. The sfottò with something at stake.
--
-- La sfida: you challenge a member, with piotte at stake (the winner takes both) and a penitenza for whoever loses.
--   Duello a la gogna   from the right click menu on a player (or the Sfide page): the first duel between the two
--                       after the yes, within a day; on the yes the duel request starts by itself when it can
--   Corsa               the first to reach the next tenth level (10, 20...)
--   Quest, Sordi, Pesci, Raccolta, Strada, Dungeon, Rari, Boss, Morti (fewer wins): who does more in an hour,
--                       today (until midnight) or this week, counted from the yes
-- Le penitenze:
--   L'immagine      a week: a picture on the loser's screen and its name ("A Pecora") in front of theirs in chat
--   Er soprannome   a week: the nickname the winner chose, next to their name (never instead: Pietro "Pippa"),
--                   in the addon and in front of what they write in chat
--   Er verso        a day: a word the winner chose at the end of everything they write in chat
--   La figuraccia   at once: the loser's character kneels, clucks, cries or surrenders in front of everyone
--   Lo strillone    a week: every time they die, the whole patto is told on screen
-- A penitenza lasts 24 hours. Right after losing a duello a la gogna, the loser can ask for la rivincita (once,
-- within ten minutes, fought within the hour): win it and the penitenza passes to the other for 24 hours; lose it
-- and yours lasts a week. Two members can have one duello a la gogna a day (the rivincita aside).
-- Er Campione: whoever wins a duello a la gogna against the champion (or the first one) holds the crown, a title,
-- until someone beats them in one.
--
-- La taja: piotte on someone's head; the first to beat them in a duel takes them, and they get the picture for two
-- days. La gufata: piotte that someone dies in the next five minutes; if they live they take them, if they die they
-- pay half. Duelli in diretta: when two of the patto start a duel, everyone in the same zone gets a small window to
-- bet on one of the two (right doubles the stake).
--
-- Everything that lasts travels in the records (sf, sk, tg, gf, dd, rip: see Patto.CleanMember) and every client
-- works out the same results from them; what has to be seen at once (a sfida thrown, a duel starting, a gufata)
-- also goes as a quick message (kind "X"). Each client keeps the results it found and its own book of piotte.
local ADDON, ns = ...
local U, M, P, T, UI = ns.U, ns.M, ns.P, ns.T, ns.UI
local H = UI.H
local S = {}
ns.Sfide = S

local DAY = 86400
S.PENDING = DAY           -- time to answer
S.DUEL_WINDOW = DAY       -- time to fight the duel once accepted
S.RV_ASK = 600            -- the rivincita can be asked for ten minutes after losing
S.RV_WINDOW = 3600        -- and is fought within the hour
S.LONG = 7                -- days of penitenza after losing the rivincita too
S.RACE_WINDOW = 21 * DAY  -- time to reach the level
S.TAJA_WINDOW = 7 * DAY
S.GUFA = 300              -- five minutes
S.BET_WINDOW = 600        -- a bet on a duel waits ten minutes for the result

S.PENE = {
  { key = "img", name = "L'immagine", days = 1, tip = "Pe' 24 ore 'na figura sur su' schermo e er nome suo davanti ar nome in chat." },
  { key = "nick", name = "Er soprannome", days = 1, ask = "Soprannome", tip = "Pe' 24 ore, accanto ar nome suo, er soprannome che je dai tu: ner patto e davanti a quello che scrive in chat." },
  { key = "bee", name = "Er verso", days = 1, ask = "Verso", tip = "Pe' 24 ore, a la fine de tutto quello che scrive in chat, 'sta parola." },
  { key = "emote", name = "La figuraccia", days = 0, tip = "Appena perde, er personaggio suo la fa davanti a tutti." },
  { key = "crier", name = "Lo strillone", days = 1, tip = "Pe' 24 ore, ogni vorta che more lo sa tutto er patto, scritto grosso sur su' schermo." },
}
S.FIGURE = {
  { name = "A Pecora", icon = "Interface\\Icons\\Spell_Nature_Polymorph", say = "Ha perso e mo' fa bee." },
  { name = "A Tartaruga", icon = "Interface\\Icons\\Ability_Hunter_Pet_Turtle", say = "Lento come la fame." },
  { name = "A Porchetta", icon = "Interface\\Icons\\Ability_Hunter_Pet_Boar", say = "Bono solo pe' 'n panino." },
  { name = "A Cadavere", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", say = "Più morto che vivo." },
  { name = "A Pagliaccio", icon = "Interface\\Icons\\Ability_Rogue_Disguise", say = "Fa ride tutto er patto." },
  { name = "A Granchio", icon = "Interface\\Icons\\Ability_Hunter_Pet_Crab", say = "Cammina de traverso." },
}
S.EMOTES = {
  { tok = "KNEEL", name = "S'inginocchia" },
  { tok = "CHICKEN", name = "Fa la gallina" },
  { tok = "CRY", name = "Piagne" },
  { tok = "SURRENDER", name = "Se arrende" },
}
S.STATS = {
  { key = "q", name = "Quest" }, { key = "g", name = "Sordi" }, { key = "fi", name = "Pesci" },
  { key = "ga", name = "Raccolta" }, { key = "tr", name = "Strada" }, { key = "dg", name = "Dungeon" },
  { key = "rk", name = "Rari" }, { key = "nk", name = "Boss" }, { key = "dt", name = "Morti", low = true },
}
S.DURATE = { { key = "h", name = "Un'ora" }, { key = "d", name = "Oggi" }, { key = "w", name = "'Sta settimana" } }

local GREY, GOLD = "|cff9d9d9d", "|cffffd100"
local function Now() return U.Now() end
local function Short(m) return (tostring(m and m.name or "?"):match("^(%S+)")) or "?" end
local function StatOf(key) for _, x in ipairs(S.STATS) do if x.key == key then return x end end end
local function DurOf(key) for _, x in ipairs(S.DURATE) do if x.key == key then return x end end end
local function Hash(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 1000003 end return h end
local function Figure(id) return S.FIGURE[(Hash(tostring(id)) % #S.FIGURE) + 1] end
local function Members()
  local out = {}
  if not ns.state then return out end
  for guid, m in pairs(ns.state.members) do out[guid] = m end
  for _, m in ipairs(UI.Members()) do out[m.guid] = m end -- test members too
  return out
end
S.Members = Members
local function Piotte(n) return ns.Tombola and ns.Tombola.Piotte(n) or (n .. " piotte") end
local function Say(ok, msg) if not ok and msg then U.Say("|cffff4040" .. msg .. "|r") end end

----------------------------------------------------------------------
-- my book: what I paid in and got back
----------------------------------------------------------------------
local function Store()
  if not (ns.db and ns.state) then return nil end
  ns.db.sfide = type(ns.db.sfide) == "table" and ns.db.sfide or {}
  local s = ns.db.sfide[ns.state.code]
  if type(s) ~= "table" then s = {} ns.db.sfide[ns.state.code] = s end
  s.res = s.res or {}     -- id -> the result, once known
  s.book = s.book or {}   -- id -> { s = paid, got = back }
  s.told = s.told or {}   -- what we already announced
  s.asked = s.asked or {} -- sfide already shown in a dialog
  s.bets = s.bets or {}   -- my bets on duels
  return s
end
S.Store = Store

function S.Delta()
  local st = Store()
  if not st then return 0 end
  local d = 0
  for _, e in pairs(st.book) do d = d - (e.s or 0) + (e.got or 0) end
  return d
end
local function Pay(id, s) local st = Store() st.book[id] = st.book[id] or { s = 0 } st.book[id].s = s end
local function Got(id, n) local st = Store() st.book[id] = st.book[id] or { s = 0 } if st.book[id].got == nil then st.book[id].got = n end end
local function Balance() return ns.Tombola and ns.Tombola.Balance() or 0 end

----------------------------------------------------------------------
-- reading the records
----------------------------------------------------------------------
function S.All()
  local out = {}
  for guid, m in pairs(Members()) do
    for _, c in ipairs(m.sf or {}) do
      local k, st, w = c.k, c.st, c.w
      if k == "q" then k, st, w = "s", "q", "w" end -- the old quest sfida
      out[#out + 1] = { id = c.id, from = guid, to = c.to, k = k, n = c.n, s = c.s or 0, p = c.p or 0, t = c.t, e = c.e or 0,
        st = st, w = w, m = c.m, rv = c.rv, at = c.at or 0 }
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

local function Lists(key, field)
  local out = {}
  for guid, m in pairs(Members()) do
    for _, x in ipairs(m[key] or {}) do
      local y = {}
      for k, v in pairs(x) do y[k] = v end
      y[field] = guid
      out[#out + 1] = y
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end
function S.Taje() return Lists("tg", "by") end
function S.Gufate() return Lists("gf", "by") end

local function Answer(c, all)
  local m = all[c.to]
  for _, a in ipairs(m and m.sk or {}) do if a.id == c.id then return a end end
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
  if key == "g" then return math.floor(n / 10000) .. " oro" end
  if key == "tr" then return string.format("%.1f km", n * 0.0009144) end
  return tostring(n)
end

-- when a counted sfida ends, from the moment of the yes
function S.EndOf(w, t)
  if w == "h" then return t + 3600 end
  if w == "d" then
    local d = date and date("*t", t)
    if d then return t + (23 - d.hour) * 3600 + (59 - d.min) * 60 + (60 - d.sec) end
    return t + DAY
  end
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
  local ans = Answer(c, all)
  if res then return "finita", res, ans end
  local now = Now()
  if not ans then return (now - c.at > S.PENDING) and "scaduta" or "aspetta", nil, nil end
  if ans.a ~= 1 then return "rifiutata", nil, ans end
  local t0 = ans.at or c.at
  local r
  if c.k == "d" then
    local d = FirstDuel(all, c.from, c.to, t0)
    local window = c.rv and S.RV_WINDOW or S.DUEL_WINDOW
    if d then r = { w = d.w, l = d.l, at = d.at }
    elseif now - t0 > window then r = { w = "", at = t0 + window } end
  elseif c.k == "l" then
    local a, b = all[c.from], all[c.to]
    local ta, tb = a and a.ms and a.ms[c.n], b and b.ms and b.ms[c.n]
    if ta and (not tb or ta < tb) then r = { w = c.from, l = c.to, at = ta }
    elseif tb and (not ta or tb < ta) then r = { w = c.to, l = c.from, at = tb }
    elseif ta and tb then r = { w = "", at = ta }
    elseif now - t0 > S.RACE_WINDOW then r = { w = "", at = t0 + S.RACE_WINDOW } end
  elseif c.k == "s" then
    local e = ans.e or S.EndOf(c.w, t0)
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
  elseif Now() > g.at + S.GUFA and ((m and (m.up or 0) >= g.at + S.GUFA) or Now() > g.at + 3 * S.GUFA) then
    r = { w = "campato", at = g.at + S.GUFA }
  end
  if r then
    if st then st.res[g.id] = r end
    return r.w, r
  end
  return "aperta"
end

----------------------------------------------------------------------
-- the penitenze in force: picture, nickname, verse (and how many each has taken)
----------------------------------------------------------------------
local gogne, nicks, verses, shame, criers = {}, {}, {}, {}, {}
local champion
local test = {}
function S.Champion() return champion end
function S.GognaOf(rec) local g = rec and gogne[rec.guid] if g and Now() < g.til then return g end end
function S.NickOf(rec) local g = rec and nicks[rec.guid] if g and Now() < g.til then return g end end
function S.VerseOf(rec) local g = rec and verses[rec.guid] if g and Now() < g.til then return g end end
function S.ShameOf(guid) return shame[guid] or 0 end
function S.CrierOf(rec) local g = rec and criers[rec.guid] if g and Now() < g.til then return g end end

local function Rebuild()
  gogne, nicks, verses, shame, criers = {}, {}, {}, {}, {}
  local all = Members()
  -- the crown: through the duels a la gogna in order, it goes to whoever beats the one holding it
  local duels = {}
  local function keep(map, guid, x)
    if Now() >= x.til then return end
    if not map[guid] or x.til > map[guid].til then map[guid] = x end
  end
  -- results first, and the rivincita of each duel (if any)
  local list = S.All()
  local res, rematch = {}, {}
  for _, c in ipairs(list) do
    local state, r = S.State(c, all)
    if state == "finita" and r.w ~= "" then res[c.id] = r end
    if c.rv then rematch[c.rv] = c end
  end
  for _, c in ipairs(list) do
    local r = res[c.id]
    local pena = S.PENE[c.p]
    local days = pena and pena.days or 0
    if r and pena and c.rv and res[c.rv] and res[c.rv].l == r.l then
      pena = nil -- lost the rivincita too: the first penitenza gets longer instead
    elseif r and pena and not c.rv then
      local rv = rematch[c.id]
      local rr = rv and res[rv.id]
      if rr and rr.l == r.l then days = S.LONG
      elseif rr then pena = nil end -- won the rivincita: this one is gone, the other one counts
    end
    if r and r.l and pena then
      shame[r.l] = (shame[r.l] or 0) + 1
      local til = r.at + days * DAY
      local why = "ha perso co' " .. Short(all[r.w])
      if pena.key == "img" then
        local f = Figure(c.id)
        keep(gogne, r.l, { name = f.name, icon = f.icon, say = f.say, til = til, why = why, by = r.w })
      elseif pena.key == "nick" and c.t then
        keep(nicks, r.l, { t = c.t, til = til, why = why, by = r.w })
      elseif pena.key == "bee" and c.t then
        keep(verses, r.l, { t = c.t, til = til, why = why, by = r.w })
      elseif pena.key == "crier" then
        keep(criers, r.l, { from = r.at, til = til, by = r.w })
      end
    end
    if r and c.k == "d" and c.p > 0 then duels[#duels + 1] = { w = r.w, l = r.l, at = r.at } end
  end
  table.sort(duels, function(a, b) return a.at < b.at end)
  champion = nil
  for _, d in ipairs(duels) do
    if not champion or champion == d.l or champion == d.w then champion = d.w end
  end
  for _, t in ipairs(S.Taje()) do
    local state, r = S.TajaState(t, all)
    if state == "finita" and r.w ~= "" then
      shame[t.on] = (shame[t.on] or 0) + 1
      local f = Figure(t.id)
      keep(gogne, t.on, { name = f.name, icon = f.icon, say = f.say, til = r.at + DAY, why = "c'aveva 'na taja e l'ha battuto " .. Short(all[r.w]), by = r.w })
    end
  end
  local me = ns.recordGuid
  if me then
    if test.g and Now() < test.g.til then gogne[me] = test.g end
    if test.n and Now() < test.n.til then nicks[me] = test.n end
    if test.v and Now() < test.v.til then verses[me] = test.v end
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

-- o: { to, k ("d", "l", "s"), st, w, s (stake), p (penitenza), t (its text), e (emote), m (1: from the menu) }
function S.Challenge(o)
  if not ns.state or ns.alt then return false end
  local all = Members()
  local other = all[o.to]
  if not other or o.to == ns.recordGuid then return false, "Scegli chi sfidà." end
  if o.k ~= "d" and o.k ~= "l" and o.k ~= "s" then return false, "Scegli la sfida." end
  if o.k == "s" and not (StatOf(o.st) and DurOf(o.w)) then return false, "Scegli su che cosa e pe' quanto." end
  local stake = math.floor(tonumber(o.s) or 0)
  if stake < 0 then return false, "La posta nun pò esse sotto zero." end
  if stake > Balance() then return false, "Nun c'hai abbastanza piotte." end
  local p = tonumber(o.p) or 0
  local text = Clean(o.t)
  if S.PENE[p] and S.PENE[p].ask and not text then return false, "Scrivi " .. S.PENE[p].ask:lower() .. "." end
  local n
  if o.k == "l" then
    n = S.RaceLevel(other)
    if not n then return false, "Ar 60 nun se corre più." end
  end
  if Open(all, ns.recordGuid, o.to) then return false, "Co' " .. Short(other) .. " c'è già 'na sfida aperta." end
  if o.rv then
    -- la rivincita: once, by the loser, right after
    local orig
    for _, x in ipairs(S.All()) do if x.id == o.rv then orig = x end if x.rv == o.rv then return false, "La rivincita s'è già fatta." end end
    local r
    if orig then _, r = S.State(orig, all) end
    if not (orig and r and r.l == ns.recordGuid and r.w == o.to and not orig.rv) then return false, "Nun c'è rivincita da chiede." end
    if Now() - r.at > S.RV_ASK then return false, "È passato troppo tempo pe' la rivincita." end
  elseif o.k == "d" and p > 0 then
    -- one duello a la gogna a day between the same two
    for _, x in ipairs(S.All()) do
      local pair = (x.from == ns.recordGuid and x.to == o.to) or (x.from == o.to and x.to == ns.recordGuid)
      if pair and x.k == "d" and x.p > 0 and not x.rv and Now() - x.at < DAY then
        local st = S.State(x, all)
        if st ~= "rifiutata" and st ~= "scaduta" then return false, "Co' " .. Short(other) .. " er duello a la gogna de oggi l'avete già fatto." end
      end
    end
  end
  local c = { id = NewId(), to = o.to, k = o.k, n = n, st = o.st, w = o.w, s = stake, p = p, t = text,
    e = tonumber(o.e) or 0, m = o.m and 1 or nil, rv = o.rv, at = Now() }
  local keep = { c }
  for _, x in ipairs(MyList("sf")) do if #keep < 6 then keep[#keep + 1] = x end end
  Pay(c.id, stake)
  P.UpdateSelf(ns.state, ns.recordGuid, { sf = keep }, "sfide")
  Send({ t = "sf", c = c })
  S.Update()
  return true, c
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

function S.Answer(id, yes, c)
  if not ns.state or ns.alt then return false end
  local all = Members()
  if not c then for _, x in ipairs(S.All()) do if x.id == id then c = x end end end
  if not c or c.to ~= ns.recordGuid then return false end
  if Answer(c, all) then return false, "Hai già risposto." end
  if c.at and Now() - c.at > S.PENDING then return false, "'Sta sfida è scaduta." end
  if yes and c.s > Balance() then return false, "Nun c'hai abbastanza piotte pe' 'sta posta." end
  local a = { id = id, a = yes and 1 or 0, at = Now() }
  if yes and c.k == "s" then
    a.e = S.EndOf(c.w, a.at)
    a.sa, a.sb = S.Total(all[c.from], c.st), S.Total(all[c.to], c.st)
  end
  local keep = { a }
  for _, x in ipairs(MyList("sk")) do if #keep < 10 and x.id ~= id then keep[#keep + 1] = x end end
  if yes then Pay(id, c.s) end
  P.UpdateSelf(ns.state, ns.recordGuid, { sk = keep }, "sfide")
  Send({ t = "ans", id = id, a = yes and 1 or 0 })
  if yes and c.k == "d" then
    -- the duel at once: everyone near can bet, and the request goes out if the other one is here
    S.Live(c.from, ns.recordGuid, c)
    local u = UnitFor(all[c.from] and all[c.from].name)
    if u and StartDuel then pcall(StartDuel, u) end
  end
  S.Update()
  return true
end

function S.Taja(on, stake)
  if not ns.state or ns.alt then return false end
  local all = Members()
  if not all[on] then return false, "Scegli su chi." end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 1 then return false, "La taja è armeno 'na piotta." end
  if stake > Balance() then return false, "Nun c'hai abbastanza piotte." end
  local t = { id = NewId(), on = on, s = stake, at = Now() }
  local keep = { t }
  for _, x in ipairs(MyList("tg")) do if #keep < 4 then keep[#keep + 1] = x end end
  Pay(t.id, stake)
  P.UpdateSelf(ns.state, ns.recordGuid, { tg = keep }, "sfide")
  S.Update()
  return true
end

function S.Gufa(on, stake)
  if not ns.state or ns.alt then return false end
  local all = Members()
  local m = all[on]
  if not m or on == ns.recordGuid then return false, "Scegli a chi gufà." end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 2 then return false, "La gufata è armeno du' piotte." end
  if stake > Balance() then return false, "Nun c'hai abbastanza piotte." end
  for _, g in ipairs(S.Gufate()) do
    if g.on == on and S.GufaState(g, all) == "aperta" then return false, "A " .. Short(m) .. " je sta già a gufà quarcuno." end
  end
  local g = { id = NewId(), on = on, s = stake, at = Now() }
  local keep = { g }
  for _, x in ipairs(MyList("gf")) do if #keep < 4 then keep[#keep + 1] = x end end
  Pay(g.id, stake)
  P.UpdateSelf(ns.state, ns.recordGuid, { gf = keep }, "sfide")
  Send({ t = "gf", on = on, s = stake, id = g.id })
  S.Update()
  return true
end

----------------------------------------------------------------------
-- duels live: everyone in the same zone can bet on one of the two
----------------------------------------------------------------------
local liveSeen = {}
-- tell the patto a duel between a and b is starting (c: the sfida, if it's a duel a la gogna)
function S.Live(a, b, c)
  local key = (a < b) and (a .. b) or (b .. a)
  local now = GetTime and GetTime() or 0
  if liveSeen[key] and now - liveSeen[key] < 90 then return end
  liveSeen[key] = now
  local z = GetRealZoneText and U.Plain(GetRealZoneText(), "string")
  Send({ t = "live", a = a, b = b, z = z, p = c and c.p or 0, pt = c and c.t or nil, id = c and c.id or nil })
end

function S.Bet(a, b, pick, stake)
  local st = Store()
  if not st then return false end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 1 then return false, "Punta armeno 'na piotta." end
  if stake > Balance() then return false, "Nun c'hai abbastanza piotte." end
  local id = "bet:" .. NewId()
  st.bets[id] = { a = a, b = b, pick = pick, s = stake, at = Now() }
  Pay(id, stake)
  if ns.Tombola then ns.Tombola.Update() end
  return true
end

----------------------------------------------------------------------
-- keeping up: my book, the news, the dialogs, my own penitenze
----------------------------------------------------------------------
local function Tell(st, key, fn)
  if st.told[key] then return end
  st.told[key] = true
  fn()
end
local function Name(all, guid) return Short(all[guid]) end

-- "Duello a la gogna, 5 piotte, chi perde: Er soprannome "Pippa""
function S.What(c, all)
  local w
  if c.k == "d" then w = (c.p > 0) and "Duello a la gogna" or "Duello"
  elseif c.k == "l" then w = "Corsa ar " .. tostring(c.n)
  else
    local x, d = StatOf(c.st), DurOf(c.w)
    w = (x and x.name or "?") .. (x and x.low and " (chi more de meno)" or "") .. ", " .. (d and d.name:lower() or "")
  end
  if c.s > 0 then w = w .. ", " .. Piotte(c.s) end
  local pena = S.PENE[c.p]
  if pena then
    w = w .. ", chi perde: " .. pena.name
    if c.t then w = w .. " \"" .. c.t .. "\"" end
    if pena.key == "emote" and S.EMOTES[c.e] then w = w .. " (" .. S.EMOTES[c.e].name:lower() .. ")" end
  end
  return w
end

local function Figuraccia(c, all, r)
  local e = S.EMOTES[c.e] or S.EMOTES[1]
  local winner = all[r.w]
  if DoEmote then pcall(DoEmote, e.tok, winner and Short(winner) or nil) end
end

local quiet = true -- the first pass after login only learns what is already there
function S.Update()
  local st = Store()
  if not st or not P.HasSettings(ns.state) then return end
  Rebuild()
  local all = Members()
  local News = ns.News
  local me = ns.recordGuid
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
          News.Add("|cffffd100" .. Name(all, c.to) .. "|r ha accettato la sfida de |cffffd100" .. Name(all, c.from) .. "|r: " .. S.What(c, all))
        end
      end)
    end
    if state == "finita" then
      Tell(st, c.id .. ":fine", function()
        if r.w ~= "" and r.l == me and S.PENE[c.p] and S.PENE[c.p].key == "emote" and Now() - (r.at or 0) < 600 then Figuraccia(c, all, r) end
        -- I lost a duello a la gogna: offer the rivincita
        if r.w ~= "" and r.l == me and c.k == "d" and c.p > 0 and not c.rv and Now() - (r.at or 0) < S.RV_ASK and not ns.alt then S.OfferRematch(c, r) end
        if quiet or not News then return end
        if r.w == "" then
          News.Add("La sfida tra " .. Name(all, c.from) .. " e " .. Name(all, c.to) .. " è finita pari: poste ridate.")
          return
        end
        local pena = S.PENE[c.p]
        -- a rivincita: the loser of the first duel either got even or lost twice
        local orig
        if c.rv then for _, x in ipairs(S.All()) do if x.id == c.rv then orig = x end end end
        local ro
        if orig then _, ro = S.State(orig, all) end
        local twice = ro and ro.l == r.l
        local span = twice and "pe' 'na settimana" or "pe' 24 ore"
        local tail = ""
        if pena and pena.key == "img" then tail = ". " .. Name(all, r.l) .. " va a la gogna " .. span .. ": " .. Figure((twice and orig or c).id).name
        elseif pena and pena.key == "nick" then tail = ". " .. Name(all, r.l) .. " è detto \"" .. tostring(c.t) .. "\" " .. span
        elseif pena and pena.key == "bee" then tail = ". " .. Name(all, r.l) .. " finisce tutto co' \"" .. tostring(c.t) .. "\" " .. span
        elseif pena and pena.key == "emote" then tail = ". " .. Name(all, r.l) .. " " .. (S.EMOTES[c.e] or S.EMOTES[1]).name:lower() .. " davanti a tutti"
        elseif pena and pena.key == "crier" then tail = ". " .. span .. ", ogni vorta che " .. Name(all, r.l) .. " more, lo sa tutto er patto" end
        local head
        if c.rv and twice then head = "|cffffd100" .. Name(all, r.l) .. "|r ha perso pure la rivincita co' |cffffd100" .. Name(all, r.w) .. "|r"
        elseif c.rv then head = "|cffffd100" .. Name(all, r.w) .. "|r s'è vennicato: ha vinto la rivincita co' |cffffd100" .. Name(all, r.l) .. "|r"
        else head = "|cffffd100" .. Name(all, r.w) .. "|r ha vinto la sfida co' |cffffd100" .. Name(all, r.l) .. "|r" end
        News.Add(head .. (c.s > 0 and (" (+" .. (2 * c.s) .. ")") or "") .. tail)
        if pena then
          local title = c.rv and (twice and (Name(all, r.l) .. " ha perso pure la rivincita!") or (Name(all, r.w) .. " s'è vennicato!")) or (Name(all, r.l) .. " ha perso!")
          News.Banner(title, pena.name .. (c.t and (": " .. c.t) or "") .. " " .. span .. ". " .. (c.rv and twice and "" or ("Lo ha battuto " .. Name(all, r.w) .. ".")), { 1, 0.5, 0.2 }, "evento")
        end
      end)
    end
    if state == "rifiutata" and c.rv then
      Tell(st, c.id .. ":no", function()
        if not quiet and News then News.Add("|cffffd100" .. Name(all, c.to) .. "|r nun ha voluto da' la rivincita a |cffffd100" .. Name(all, c.from) .. "|r.") end
      end)
    end
    if c.to == me and state == "aspetta" and not st.asked[c.id] and not ns.alt then
      st.asked[c.id] = true
      S.Ask(c, all)
    end
  end
  for _, t in ipairs(S.Taje()) do
    local state, r = S.TajaState(t, all)
    if state == "finita" and not ns.alt then
      if t.by == me then Got(t.id, (r.w == "" or r.w == me) and t.s or 0) end
      if r.w == me and t.by ~= me then st.book[t.id .. ":w"] = st.book[t.id .. ":w"] or { s = 0, got = t.s } end
    end
    Tell(st, t.id .. ":su", function()
      if quiet or not News then return end
      News.Add("Taja de |cffffffff" .. t.s .. "|r piotte su |cffffd100" .. Name(all, t.on) .. "|r: chi lo batte a duello se le pija.")
      News.Banner("Taja su " .. Name(all, t.on), Piotte(t.s) .. " a chi lo batte a duello", { 1, 0.5, 0.2 }, "evento")
    end)
    if state == "finita" and r.w ~= "" then
      Tell(st, t.id .. ":presa", function()
        if quiet or not News then return end
        News.Add("|cffffd100" .. Name(all, r.w) .. "|r s'è pijato la taja su |cffffd100" .. Name(all, t.on) .. "|r (" .. Piotte(t.s) .. ").")
      end)
    end
  end
  for _, g in ipairs(S.Gufate()) do
    local state = S.GufaState(g, all)
    if state ~= "aperta" and not ns.alt then
      local half = math.floor(g.s / 2)
      if g.by == me then Got(g.id, state == "morto" and (g.s + half) or 0) end
      if g.on == me then
        if state == "morto" then st.book[g.id .. ":t"] = st.book[g.id .. ":t"] or { s = half, got = 0 }
        else st.book[g.id .. ":t"] = st.book[g.id .. ":t"] or { s = 0, got = g.s } end
      end
    end
    if state ~= "aperta" then
      Tell(st, g.id .. ":fine", function()
        if quiet or not News then return end
        if state == "morto" then
          News.Add("La gufata de |cffffd100" .. Name(all, g.by) .. "|r ha funzionato: |cffffd100" .. Name(all, g.on) .. "|r è morto. Paga " .. Piotte(math.floor(g.s / 2)) .. ".")
          if g.on == me or g.by == me then News.Banner("La gufata ha funzionato!", Name(all, g.on) .. " è morto. Gufo: " .. Name(all, g.by), { 1, 0.5, 0.2 }, "evento") end
        else
          News.Add("|cffffd100" .. Name(all, g.on) .. "|r è campato a la gufata de |cffffd100" .. Name(all, g.by) .. "|r: se pija " .. Piotte(g.s) .. ".")
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
        Got(id, won and 2 * b.s or 0)
        if News then News.Add(won and ("Hai vinto " .. Piotte(2 * b.s) .. " puntando su |cffffd100" .. Name(all, b.pick) .. "|r.")
          or ("Hai perso " .. Piotte(b.s) .. " puntando su " .. Name(all, b.pick) .. ".")) end
      elseif Now() > b.at + S.BET_WINDOW then
        Got(id, b.s)
      end
    end
  end
  -- duels between patto members and the gravestones make the news
  for guid, m in pairs(all) do
    for _, d in ipairs(m.dd or {}) do
      if d.w == 1 then
        Tell(st, "duel:" .. guid .. ":" .. tostring(d.at), function()
          if not quiet and News then News.Add("|cffffd100" .. Short(m) .. "|r ha battuto |cffffd100" .. Name(all, d.o) .. "|r a duello.") end
        end)
      end
    end
    for _, g in ipairs(m.rip or {}) do
      Tell(st, "rip:" .. guid .. ":" .. tostring(g.at), function()
        if quiet or not News then return end
        if g.w then News.Add("R.I.P. |cffffd100" .. Short(m) .. "|r" .. S.GraveText(g) .. ". Urtime parole: \"" .. g.w .. "\"") end
        -- lo strillone: everyone is told
        local cr = criers[guid]
        if cr and g.at >= cr.from and g.at < cr.til and Now() - g.at < 600 then
          News.Banner("È morto de novo " .. Short(m) .. "!", S.GraveText(g):gsub("^, ", "") .. ". Lo strillone de " .. Name(all, cr.by) .. ".", { 1, 0.5, 0.2 }, "evento")
        end
      end)
    end
  end
  -- er Campione: say it when the crown changes hands
  if champion and st.champ ~= champion then
    local was = st.champ
    st.champ = champion
    if not quiet and News then
      News.Add("|cffffd100" .. Name(all, champion) .. "|r è er novo Campione der duello" .. (was and all[was] and (": ha battuto " .. Name(all, was)) or "") .. ".")
      News.Banner(Name(all, champion) .. " è er Campione!", "La corona der duello a la gogna è sua finché nun perde.", nil, "evento")
    end
  end
  quiet = false
  Rebuild()
  S.ShowMyGogna()
  if ns.Tombola then ns.Tombola.Update() end
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
-- dialogs: a sfida for me, the bet on a duel, the duel a la gogna and the gufata from the menu
----------------------------------------------------------------------
local function Dialog(name, w, h, title)
  local d = CreateFrame("Frame", name, UIParent)
  d:SetSize(w, h)
  d:SetPoint("CENTER", 0, 160)
  d:SetFrameStrata("DIALOG")
  d:SetToplevel(true)
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  H.Chrome(d)
  d.title = H.DialogHeader(d, title, 160)
  if UISpecialFrames then table.insert(UISpecialFrames, name) end
  d:Hide()
  return d
end

local ask
function S.Ask(c, all)
  all = all or Members()
  if not ask then
    ask = Dialog("ErPattoSfida", 400, 150, "Sfida!")
    ask.text = H.Text(ask, "GameFontHighlight", "", 360, "CENTER")
    ask.text:SetPoint("TOP", 0, -34)
    ask.yes = H.Btn(ask, "Ce sto", 110, function()
      if ask.c.id ~= "prova" then Say(S.Answer(ask.c.id, true, ask.c)) end
      ask:Hide()
    end)
    ask.yes:SetPoint("BOTTOMRIGHT", ask, "BOTTOM", -6, 18)
    ask.no = H.Btn(ask, "Me tiro indietro", 130, function() if ask.c.id ~= "prova" then S.Answer(ask.c.id, false, ask.c) end ask:Hide() end)
    ask.no:SetPoint("BOTTOMLEFT", ask, "BOTTOM", 6, 18)
  end
  ask.c = c
  ask.title:SetText(c.rv and "Rivincita!" or (c.k == "d" and c.p > 0 and "Duello a la gogna!" or "Sfida!"))
  local pena = S.PENE[c.p]
  if c.rv then
    ask.text:SetText("|cffffd100" .. Name(all, c.from) .. "|r vole la rivincita.\nSi vince lui, la penitenza passa a te pe' 24 ore.\nSi perde, la sua dura 'na settimana.")
  else
    ask.text:SetText("|cffffd100" .. Name(all, c.from) .. "|r te sfida.\n" .. S.What(c, all) ..
      (pena and ("\n|cff9d9d9d" .. pena.tip .. "|r") or ""))
  end
  ask:Show()
  if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE) or 880) end
end

-- right after losing a duello a la gogna: la rivincita?
local offer
function S.OfferRematch(c, r)
  local all = Members()
  if not offer then
    offer = Dialog("ErPattoRivincita", 380, 150, "Hai perso!")
    offer.text = H.Text(offer, "GameFontHighlight", "", 340, "CENTER")
    offer.text:SetPoint("TOP", 0, -32)
    offer.yes = H.Btn(offer, "Rivincita!", 110, function()
      local x = offer.c
      Say(S.Challenge({ to = offer.w, k = "d", s = x.s, p = x.p, t = x.t, e = x.e, m = 1, rv = x.id }))
      offer:Hide()
    end)
    offer.yes:SetPoint("BOTTOMRIGHT", offer, "BOTTOM", -6, 18)
    offer.no = H.Btn(offer, "Me la tengo", 110, function() offer:Hide() end)
    offer.no:SetPoint("BOTTOMLEFT", offer, "BOTTOM", 6, 18)
  end
  offer.c, offer.w = c, r.w
  local pena = S.PENE[c.p]
  offer.text:SetText((pena and pena.name or "La penitenza") .. " pe' 24 ore.\nRivincita co' " .. Name(all, r.w) .. "? Si la vinci, passa a lui.\nSi la perdi, la tua dura 'na settimana.")
  offer:Show()
  if C_Timer then C_Timer.After(S.RV_ASK, function() if offer and offer.c == c then offer:Hide() end end) end
end

local bet
function S.ShowBet(a, b, info)
  local all = Members()
  if not (all[a] and all[b]) then return end
  if not bet then
    bet = Dialog("ErPattoScommessa", 300, 150, "Duello!")
    bet:ClearAllPoints()
    bet:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
    bet.text = H.Text(bet, "GameFontHighlight", "", 270, "CENTER")
    bet.text:SetPoint("TOP", 0, -32)
    bet.label = H.Text(bet, "GameFontNormalSmall", "Punti", 40)
    bet.label:SetPoint("TOPLEFT", 24, -78)
    bet.stake = H.Input(bet, 40, 4)
    if bet.stake.SetNumeric then bet.stake:SetNumeric(true) end
    bet.stake:SetPoint("TOPLEFT", 66, -74)
    bet.note = H.Text(bet, "GameFontHighlightSmall", "piotte, chi indovina raddoppia", 160)
    bet.note:SetPoint("TOPLEFT", 112, -78)
    local function pick(i)
      return function()
        local ok, msg = S.Bet(bet.a, bet.b, i == 1 and bet.a or bet.b, bet.stake:GetText())
        Say(ok, msg)
        if ok then U.Say("hai puntato " .. Piotte(tonumber(bet.stake:GetText()) or 0) .. " su " .. Name(Members(), i == 1 and bet.a or bet.b) .. ".") bet:Hide() end
      end
    end
    bet.pa = H.Btn(bet, "", 100, pick(1), 22) bet.pa:SetPoint("BOTTOMLEFT", 18, 16)
    bet.pb = H.Btn(bet, "", 100, pick(2), 22) bet.pb:SetPoint("BOTTOMRIGHT", -18, 16)
    bet.no = H.Btn(bet, "Gnente", 60, function() bet:Hide() end, 22) bet.no:SetPoint("BOTTOM", 0, 16)
  end
  bet.a, bet.b = a, b
  bet.text:SetText(H.Colored(all[a]) .. " contro " .. H.Colored(all[b]) .. (info and ("\n|cff9d9d9d" .. info .. "|r") or ""))
  bet.pa:SetText(Short(all[a]))
  bet.pb:SetText(Short(all[b]))
  bet.stake:SetText("5")
  bet.shownAt = GetTime and GetTime() or 0
  bet:Show()
  if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960) end
  if C_Timer then C_Timer.After(60, function() if bet and bet.shownAt and (GetTime() - bet.shownAt) >= 59 then bet:Hide() end end) end
end

-- the penitenza chooser: a radio per penitenza, a field for the nickname or the verse, a button for the emote
local function PenaPicker(parent, x, y, form)
  local w = { radios = {} }
  local labels = { { 0, "Gnente" } }
  for i, p in ipairs(S.PENE) do labels[#labels + 1] = { i, p.name } end
  for k, l in ipairs(labels) do
    local r = H.Radio(parent, l[2], function() form.p = l[1] end)
    r:SetPoint("TOPLEFT", x, y - (k - 1) * 18)
    r.v = l[1]
    if l[1] > 0 then
      r:SetScript("OnEnter", function(self) H.Tip(self, { S.PENE[self.v].name, S.PENE[self.v].tip }) end)
      r:SetScript("OnLeave", H.HideTip)
    end
    w.radios[k] = r
  end
  w.text = H.Input(parent, 110, 20)
  w.text:SetScript("OnTextChanged", function(self) form.t = self:GetText() end)
  w.emote = H.Btn(parent, "", 110, function()
    form.e = ((form.e or 1) % #S.EMOTES) + 1
    UI.Refresh()
    if w.Refresh then w.Refresh() end
  end, 18)
  function w.Refresh()
    for _, r in ipairs(w.radios) do r:SetSelected((form.p or 0) == r.v) end
    local pena = S.PENE[form.p or 0]
    w.text:ClearAllPoints()
    w.emote:ClearAllPoints()
    w.text:Hide() w.emote:Hide()
    if pena and pena.ask then
      local row = w.radios[(form.p or 0) + 1]
      w.text:SetPoint("LEFT", row, "RIGHT", 10, 0)
      if not w.text:HasFocus() then w.text:SetText(form.t or "") end
      w.text:Show()
    elseif pena and pena.key == "emote" then
      local row = w.radios[(form.p or 0) + 1]
      w.emote:SetPoint("LEFT", row, "RIGHT", 10, 0)
      w.emote:SetText((S.EMOTES[form.e or 1] or S.EMOTES[1]).name)
      w.emote:Show()
    end
  end
  return w
end
S.PenaPicker = PenaPicker

local duel
function S.OpenDuel(guid)
  local all = Members()
  if not all[guid] or guid == ns.recordGuid then return end
  if not duel then
    duel = Dialog("ErPattoDuelloGogna", 360, 262, "Duello a la gogna")
    duel.form = { p = 1, e = 1 }
    duel.who = H.Text(duel, "GameFontHighlight", "", 320, "CENTER")
    duel.who:SetPoint("TOP", 0, -32)
    local l = H.Text(duel, "GameFontNormalSmall", "Chi perde", 80) l:SetPoint("TOPLEFT", 26, -58)
    duel.pena = PenaPicker(duel, 100, -54, duel.form)
    local ps = H.Text(duel, "GameFontNormalSmall", "Posta", 80) ps:SetPoint("TOPLEFT", 26, -176)
    duel.stake = H.Input(duel, 40, 4)
    if duel.stake.SetNumeric then duel.stake:SetNumeric(true) end
    duel.stake:SetPoint("TOPLEFT", 106, -172)
    local pn = H.Text(duel, "GameFontHighlightSmall", "piotte (si voi)", 120) pn:SetPoint("TOPLEFT", 152, -176)
    duel.go = H.Btn(duel, "Sfida!", 110, function()
      local f = duel.form
      local ok, msg = S.Challenge({ to = duel.to, k = "d", s = duel.stake:GetText(), p = f.p, t = f.t, e = f.e, m = 1 })
      Say(ok, msg)
      if ok then U.Say("duello a la gogna mannato a " .. Name(Members(), duel.to) .. ": aspetta che risponne.") duel:Hide() end
    end)
    duel.go:SetPoint("BOTTOMRIGHT", duel, "BOTTOM", -6, 18)
    duel.no = H.Btn(duel, "Lascia stà", 110, function() duel:Hide() end)
    duel.no:SetPoint("BOTTOMLEFT", duel, "BOTTOM", 6, 18)
    duel:HookScript("OnShow", function() duel.pena.Refresh() end)
  end
  duel.to = guid
  duel.who:SetText("Contro " .. H.Colored(all[guid]))
  duel.stake:SetText("")
  duel.form.t = nil
  duel.pena.Refresh()
  duel:Show()
end

local gufa
function S.OpenGufa(guid)
  local all = Members()
  if not all[guid] or guid == ns.recordGuid then return end
  if not gufa then
    gufa = Dialog("ErPattoGufata", 340, 186, "Gufata")
    gufa.text = H.Text(gufa, "GameFontHighlight", "", 300, "CENTER")
    gufa.text:SetPoint("TOP", 0, -32)
    local l = H.Text(gufa, "GameFontNormalSmall", "Posta", 60) l:SetPoint("TOPLEFT", 60, -104)
    gufa.stake = H.Input(gufa, 40, 4)
    if gufa.stake.SetNumeric then gufa.stake:SetNumeric(true) end
    gufa.stake:SetPoint("TOPLEFT", 110, -100)
    local n = H.Text(gufa, "GameFontHighlightSmall", "piotte", 60) n:SetPoint("TOPLEFT", 156, -104)
    gufa.go = H.Btn(gufa, "Gufa!", 110, function()
      local ok, msg = S.Gufa(gufa.on, gufa.stake:GetText())
      Say(ok, msg)
      if ok then gufa:Hide() end
    end)
    gufa.go:SetPoint("BOTTOMRIGHT", gufa, "BOTTOM", -6, 18)
    gufa.no = H.Btn(gufa, "Lascia stà", 110, function() gufa:Hide() end)
    gufa.no:SetPoint("BOTTOMLEFT", gufa, "BOTTOM", 6, 18)
  end
  gufa.on = guid
  gufa.text:SetText("Je gufi la morte a " .. H.Colored(all[guid]) .. " pe' 5 minuti.\nSi more, vinci mezza posta in più.\nSi campa, la posta è sua.")
  gufa.stake:SetText("10")
  gufa:Show()
end

----------------------------------------------------------------------
-- my own penitenza, on my screen: the picture in a vanilla slot, its name under it
----------------------------------------------------------------------
local pic
function S.ShowMyGogna()
  local rec = ns.MyRecord and ns.MyRecord()
  local g = S.GognaOf(rec)
  if not g then if pic then pic:Hide() end return end
  if not pic then
    pic = CreateFrame("Button", "ErPattoGogna", UIParent)
    pic:SetSize(64, 64)
    local pos = ns.db.ui and ns.db.ui.gogna
    if type(pos) == "table" and pos[1] then pic:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else pic:SetPoint("TOP", 0, -120) end
    pic:SetFrameStrata("MEDIUM")
    pic:SetMovable(true)
    pic:SetClampedToScreen(true)
    pic:RegisterForDrag("LeftButton")
    pic:SetScript("OnDragStart", pic.StartMoving)
    pic:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local p, _, rp, x, y = self:GetPoint()
      ns.db.ui = ns.db.ui or {}
      ns.db.ui.gogna = { p, rp, x, y }
    end)
    pic.icon = pic:CreateTexture(nil, "ARTWORK")
    pic.icon:SetSize(40, 40)
    pic.icon:SetPoint("CENTER")
    local border = pic:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    border:SetSize(64, 64)
    border:SetPoint("CENTER")
    pic.name = pic:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pic.name:SetPoint("TOP", pic, "BOTTOM", 0, 6)
    pic:SetScript("OnEnter", function(self)
      local x = S.GognaOf(ns.MyRecord())
      if x then H.Tip(self, { "La gogna: " .. x.name, x.say, x.why .. ".", "Fino a " .. U.When(x.til) }) end
    end)
    pic:SetScript("OnLeave", H.HideTip)
  end
  pic.icon:SetTexture(g.icon)
  pic.name:SetText(g.name)
  pic:Show()
end

-- test mode: my penitenze for two minutes, a sfida and a duel to bet on, to see how they look
local function Fakes()
  local out = {}
  for _, m in ipairs(UI.Members()) do if m.fake then out[#out + 1] = m.guid end end
  return out
end
function S.TestGogna()
  local f = Fakes()
  local fig = S.FIGURE[math.random(#S.FIGURE)]
  local til = Now() + 120
  test.g = { name = fig.name, icon = fig.icon, say = fig.say, til = til, why = "ha perso er duello (prova)", by = f[1] }
  test.n = { t = "Pippa", til = til, by = f[1] }
  test.v = { t = "bee", til = til, by = f[1] }
  Rebuild()
  S.ShowMyGogna()
  if ns.News then ns.News.Banner(Short(ns.MyRecord()) .. " ha perso!", fig.name .. ", er soprannome \"Pippa\" e er verso \"bee\" (prova).", { 1, 0.5, 0.2 }, "evento") end
  if UI.Refresh then UI.Refresh() end
  if C_Timer then C_Timer.After(121, function() Rebuild() S.ShowMyGogna() UI.Refresh() end) end
end
function S.TestAsk()
  local f = Fakes()
  if not f[1] then return end
  S.Ask({ id = "prova", from = f[1], to = ns.recordGuid, k = "d", s = 10, p = 2, t = "Pippa", e = 0, at = Now() })
end
function S.TestBet()
  local f = Fakes()
  if f[2] then S.ShowBet(f[1], f[2], "Duello a la gogna: chi perde, Er soprannome") end
end

----------------------------------------------------------------------
-- events: quick messages, duel requests, the right click menu
----------------------------------------------------------------------
ns.On("Live", function(from, data)
  if type(data) ~= "table" or not ns.state then return end
  local me = ns.recordGuid
  if data.t == "sf" and type(data.c) == "table" and data.c.to == me then
    local st = Store()
    local c = data.c
    if st and not st.asked[c.id] and not ns.alt then
      st.asked[c.id] = true
      local x = { id = c.id, from = from, to = me, k = c.k, n = c.n, st = c.st, w = c.w, s = tonumber(c.s) or 0, p = tonumber(c.p) or 0,
        t = c.t and tostring(c.t):gsub("|", ""):sub(1, 20) or nil, e = tonumber(c.e) or 0, m = c.m, rv = type(c.rv) == "string" and c.rv:sub(1, 40) or nil, at = tonumber(c.at) or Now() }
      S.Ask(x, Members())
    end
  elseif data.t == "live" and data.a ~= me and data.b ~= me and not ns.alt then
    local z = GetRealZoneText and U.Plain(GetRealZoneText(), "string")
    local all = Members()
    if data.z and z == data.z and all[data.a] and all[data.b] then
      local pena = S.PENE[tonumber(data.p) or 0]
      S.ShowBet(data.a, data.b, pena and ("Duello a la gogna: chi perde, " .. pena.name .. (data.pt and (" \"" .. tostring(data.pt):gsub("|", "") .. "\"") or "")) or nil)
    elseif all[data.a] and all[data.b] and ns.News then
      ns.News.Add("|cffffd100" .. Short(all[data.a]) .. "|r e |cffffd100" .. Short(all[data.b]) .. "|r se stanno a menà" .. (data.z and (" a " .. tostring(data.z)) or "") .. ".")
    end
  elseif data.t == "gf" and data.on == me and ns.News then
    local all = Members()
    ns.News.Banner(Short(all[from]) .. " te sta a gufà!", "Si campi 5 minuti, te pij " .. Piotte(tonumber(data.s) or 0) .. ".", { 1, 0.5, 0.2 }, "evento")
  end
  if C_Timer then C_Timer.After(3, S.Update) end
end)

-- someone asks me for a duel: if both are in the patto, everyone near can bet
local function OnDuelRequested(name)
  if not ns.state or ns.alt or U.IsSecret(name) or type(name) ~= "string" then return end
  for guid, m in pairs(ns.state.members) do
    if guid ~= ns.recordGuid and (m.name == name or Short(m) == name) then
      local c = Open(Members(), guid, ns.recordGuid)
      S.Live(guid, ns.recordGuid, c and c.k == "d" and c or nil)
      return
    end
  end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...) if event == "DUEL_REQUESTED" then pcall(OnDuelRequested, ...) end end)
pcall(frame.RegisterEvent, frame, "DUEL_REQUESTED")

local function AddMenu()
  if not (Menu and Menu.ModifyMenu) then return end
  for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET" }) do
    pcall(Menu.ModifyMenu, tag, function(owner, root, data)
      if not (ns.state and not ns.alt and data and data.name) then return end
      for guid, m in pairs(ns.state.members) do
        if guid ~= ns.recordGuid and (m.name == data.name or Short(m) == data.name) then
          if root.CreateDivider then root:CreateDivider() end
          root:CreateButton("Duello a la gogna", function() S.OpenDuel(guid) end)
          root:CreateButton("Gufata", function() S.OpenGufa(guid) end)
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
    C_Timer.After(10, S.Update)
    C_Timer.NewTicker(30, S.Update)
  end
end)

----------------------------------------------------------------------
-- the Sfide page of Er Botteghino
----------------------------------------------------------------------
local form = { k = "d", w = "h", p = 1, e = 1 }

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
    chooser:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    chooser:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    chooser:SetScript("OnEvent", function(self)
      local over = MouseIsOver and (MouseIsOver(self) or (self.anchor and MouseIsOver(self.anchor)))
      if not over then self:Hide() end
    end)
  end
  chooser.anchor = anchor
  for _, r in ipairs(chooser.rows) do r:Hide() end
  local shown = math.min(20, #items)
  for i = 1, shown do
    local r = chooser.rows[i]
    if not r then
      r = CreateFrame("Button", nil, chooser)
      r:SetSize(170, 16)
      r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
      r.text = H.Text(r, "GameFontHighlightSmall", "", 166)
      r.text:SetPoint("LEFT", 4, 0)
      r:SetScript("OnClick", function(self) chooser:Hide() if chooser.onPick then chooser.onPick(self.value) end UI.Refresh() end)
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
  local race = S.RaceLevel(other)
  local items = { { "d", "Duello a la gogna" } }
  if race then items[#items + 1] = { "l", "Chi arriva prima ar " .. race } end
  for _, x in ipairs(S.STATS) do items[#items + 1] = { "s:" .. x.key, x.low and "Chi more de meno" or ("Chi fa più: " .. x.name:lower()) } end
  return items
end
local function WhatLabel(other)
  for _, it in ipairs(WhatItems(other)) do
    if (form.k == "s" and it[1] == "s:" .. tostring(form.st)) or (form.k ~= "s" and it[1] == form.k) then return it[2] end
  end
  return "Scegli"
end

function S.Prefill(guid)
  form.to = guid
  if ns.Botteghino then ns.Botteghino.Show("sfide") end
end

function S.BuildPage(v)
  local p = CreateFrame("Frame", nil, v)
  p:SetAllPoints()
  v.sfide = p
  local function Label(box, text, y) local l = H.Text(box, "GameFontNormalSmall", text, 70) l:SetPoint("TOPLEFT", 14, y) return l end
  -- throw a sfida
  local a = H.Box(p, 360, 270)
  a:SetPoint("TOPLEFT", 0, -28)
  local t = H.Text(a, "GameFontNormal", "Lancia 'na sfida", 200) t:SetPoint("TOPLEFT", 12, -12)
  Label(a, "Contro", -38)
  p.who = H.Btn(a, "Scegli", 160, function(self) Choose(self, MemberItems(), function(g) form.to = g end) end, 20)
  p.who:SetPoint("TOPLEFT", 84, -34)
  Label(a, "Su che", -62)
  p.what = H.Btn(a, "Scegli", 200, function(self)
    Choose(self, WhatItems(form.to and Members()[form.to]), function(x)
      if x:sub(1, 2) == "s:" then form.k, form.st = "s", x:sub(3) else form.k, form.st = x, nil end
    end)
  end, 20)
  p.what:SetPoint("TOPLEFT", 84, -58)
  p.durLabel = Label(a, "Pe' quanto", -86)
  p.durs = {}
  local dx = 84
  for _, d in ipairs(S.DURATE) do
    local r = H.Radio(a, d.name, function() form.w = d.key end)
    r:SetPoint("TOPLEFT", dx, -84)
    r.k = d.key
    dx = dx + r:GetWidth() + 10
    p.durs[#p.durs + 1] = r
  end
  Label(a, "Posta", -110)
  p.stake = H.Input(a, 50, 5)
  if p.stake.SetNumeric then p.stake:SetNumeric(true) end
  p.stake:SetPoint("TOPLEFT", 90, -106)
  local pn = H.Text(a, "GameFontHighlightSmall", "piotte, chi vince se pija er doppio", 200) pn:SetPoint("TOPLEFT", 148, -110)
  Label(a, "Chi perde", -134)
  p.pena = PenaPicker(a, 84, -130, form)
  p.go = H.Btn(a, "Sfida!", 100, function()
    local ok, msg = S.Challenge({ to = form.to, k = form.k, st = form.st, w = form.w, s = p.stake:GetText(), p = form.p, t = form.t, e = form.e })
    if ok then p.stake:SetText("") U.Say("sfida mannata a " .. Short(Members()[form.to]) .. ".") end
    Say(ok, msg)
  end, 22)
  p.go:SetPoint("BOTTOMRIGHT", -12, 12)
  p.testGogna = H.Btn(a, "Prova: gogna", 92, function() S.TestGogna() end, 18)
  p.testGogna:SetPoint("TOPRIGHT", -10, -8)

  -- put a taja: one line
  local b = H.Box(p, 360, 71)
  b:SetPoint("TOPLEFT", 0, -304)
  local tb = H.Text(b, "GameFontNormal", "Metti 'na taja", 200) tb:SetPoint("TOPLEFT", 12, -10)
  local l1 = H.Text(b, "GameFontNormalSmall", "Su chi", 50) l1:SetPoint("TOPLEFT", 14, -38)
  p.on = H.Btn(b, "Scegli", 110, function(self) Choose(self, MemberItems(), function(g) form.on = g end) end, 20)
  p.on:SetPoint("TOPLEFT", 60, -34)
  local l2 = H.Text(b, "GameFontNormalSmall", "Taja", 40) l2:SetPoint("TOPLEFT", 180, -38)
  p.taja = H.Input(b, 40, 5)
  if p.taja.SetNumeric then p.taja:SetNumeric(true) end
  p.taja:SetPoint("TOPLEFT", 216, -34)
  p.put = H.Btn(b, "Metti", 70, function()
    local ok, msg = S.Taja(form.on, p.taja:GetText())
    if ok then p.taja:SetText("") end
    Say(ok, msg)
  end, 20)
  p.put:SetPoint("TOPRIGHT", -12, -34)

  -- the sfide
  local c = H.Box(p, 378, 270)
  c:SetPoint("TOPLEFT", 366, -28)
  local tc = H.Text(c, "GameFontNormal", "Le sfide", 200) tc:SetPoint("TOPLEFT", 12, -12)
  p.testBet = H.Btn(c, "Prova: scommessa", 112, function() S.TestBet() end, 18)
  p.testBet:SetPoint("TOPRIGHT", -10, -8)
  p.testAsk = H.Btn(c, "Prova: sfida", 88, function() S.TestAsk() end, 18)
  p.testAsk:SetPoint("RIGHT", p.testBet, "LEFT", -4, 0)
  p.rows = {}
  for i = 1, 7 do
    local y = -32 - (i - 1) * 32
    local r = {}
    r.top = H.Text(c, "GameFontHighlightSmall", "", 230) r.top:SetPoint("TOPLEFT", 14, y)
    if r.top.SetWordWrap then r.top:SetWordWrap(false) end
    r.state = H.Text(c, "GameFontHighlightSmall", "", 120, "RIGHT") r.state:SetPoint("TOPRIGHT", -14, y)
    r.what = H.Text(c, "GameFontDisableSmall", "", 350) r.what:SetPoint("TOPLEFT", 14, y - 13)
    if r.what.SetWordWrap then r.what:SetWordWrap(false) end
    r.yes = H.Btn(c, "Ce sto", 58, function(self) Say(S.Answer(self.id, true)) end, 16)
    r.yes:SetPoint("TOPRIGHT", -74, y - 12)
    r.no = H.Btn(c, "No", 40, function(self) S.Answer(self.id, false) end, 16)
    r.no:SetPoint("TOPRIGHT", -30, y - 12)
    p.rows[i] = r
  end
  p.none = H.Text(c, "GameFontDisableSmall", "", 340) p.none:SetPoint("TOPLEFT", 14, -32)

  -- penitenze in force, taje, gufate
  local d = H.Box(p, 378, 71)
  d:SetPoint("TOPLEFT", 366, -304)
  local td = H.Text(d, "GameFontNormal", "Gogne, taje e gufate", 240) td:SetPoint("TOPLEFT", 12, -12)
  p.lines = {}
  for i = 1, 3 do
    local l = H.Text(d, "GameFontHighlightSmall", "", 260) l:SetPoint("TOPLEFT", 14, -28 - (i - 1) * 13)
    if l.SetWordWrap then l:SetWordWrap(false) end
    l.right = H.Text(d, "GameFontHighlightSmall", "", 90, "RIGHT") l.right:SetPoint("TOPRIGHT", -14, -28 - (i - 1) * 13)
    p.lines[i] = l
  end
end

local STATE_TEXT = { aspetta = GREY .. "aspetta risposta|r", rifiutata = GREY .. "rifiutata|r", scaduta = GREY .. "scaduta|r", incorso = GOLD .. "in corso|r" }

function S.RefreshPage(v)
  local p = v.sfide
  local all = Members()
  local testing = ns.Tombola and ns.Tombola.Testing() and true or false
  p.testGogna:SetShown(testing) p.testAsk:SetShown(testing) p.testBet:SetShown(testing)
  local other = form.to and all[form.to]
  p.who:SetText(other and Short(other) or "Scegli")
  p.what:SetText(WhatLabel(other))
  for _, r in ipairs(p.durs) do r:SetSelected(form.w == r.k) r:SetShown(form.k == "s") end
  p.durLabel:SetShown(form.k == "s")
  p.pena.Refresh()
  p.on:SetText(form.on and all[form.on] and Short(all[form.on]) or "Scegli")
  p.go:SetEnabled(form.to ~= nil)
  p.put:SetEnabled(form.on ~= nil)
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
      local state, res = S.State(c, all)
      r.top:SetText(H.Colored(all[c.from] or { name = "?" }) .. " contro " .. H.Colored(all[c.to] or { name = "?" }))
      local stText = STATE_TEXT[state]
      if state == "finita" then
        stText = res.w == "" and (GREY .. "pari, poste ridate|r") or ("vince " .. GOLD .. Short(all[res.w]) .. "|r")
      end
      r.state:SetText(stText or "")
      r.what:SetText(S.What(c, all))
      local ask = state == "aspetta" and c.to == ns.recordGuid
      r.yes.id, r.no.id = c.id, c.id
      r.yes:SetShown(ask) r.no:SetShown(ask)
      r.top:Show() r.state:Show() r.what:Show()
    else
      r.top:Hide() r.state:Hide() r.what:Hide() r.yes:Hide() r.no:Hide()
    end
  end
  p.none:SetText(shown == 0 and (GREY .. "Ancora nessuna sfida.|r") or "")
  local lines = {}
  for _, m in ipairs(UI.Members()) do
    local g, n, x = S.GognaOf(m), S.NickOf(m), S.VerseOf(m)
    local who = H.Colored(m, true)
    if g then lines[#lines + 1] = { who .. " è " .. GOLD .. g.name .. "|r", "fino a " .. U.Day(g.til) } end
    if n then lines[#lines + 1] = { who .. " detto " .. GOLD .. "\"" .. n.t .. "\"|r", "fino a " .. U.Day(n.til) } end
    if x then lines[#lines + 1] = { who .. " fa " .. GOLD .. "\"" .. x.t .. "\"|r", "fino a " .. U.Day(x.til) } end
    local cr = criers[m.guid]
    if cr and Now() < cr.til then lines[#lines + 1] = { who .. " co' lo strillone", "fino a " .. U.Day(cr.til) } end
  end
  for _, t in ipairs(S.Taje()) do
    if S.TajaState(t, all) == "aperta" then lines[#lines + 1] = { "Taja su " .. H.Colored(all[t.on] or { name = "?" }), Piotte(t.s) } end
  end
  for _, g in ipairs(S.Gufate()) do
    if S.GufaState(g, all) == "aperta" then lines[#lines + 1] = { Short(all[g.by]) .. " gufa " .. H.Colored(all[g.on] or { name = "?" }), Piotte(g.s) } end
  end
  if #lines == 0 then lines[1] = { GREY .. "Nessuna gogna, taja o gufata.|r", "" } end
  for i, l in ipairs(p.lines) do
    local x = lines[i]
    l:SetText(x and x[1] or "")
    l.right:SetText(x and x[2] or "")
  end
end
