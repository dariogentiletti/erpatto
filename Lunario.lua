-- Er Patto: er Lunario, the patto's appuntamenti. Anyone puts one up for his squadra (or for the whole patto): a
-- dungeon, a torneo de duelli, a battleground, a livellata insieme, a rimpatriata; day, hour, how long, how many
-- places. Everyone says "Ce sto", "Forse" or "No"; before it starts, whoever wants bets piotte on how it'll go
-- (who does more damage, who dies more, who wins more duels...: the questions depend on the kind), all against
-- all: the piotte on a question go to who guessed, in proportion to their stake. While it runs, each one who said
-- he's in counts on his own PC what he does (damage, healing, killing blows, deaths, duels, honorable kills); when
-- it's over, everyone gets the summary and the bets are paid. Fifteen minutes before, a line in the chat; at the
-- start, the raid warning letters. And whoever walks into a dungeon his squadra has on the calendar is reminded.
-- Two pages: Prossimi (the list) and Mese (the month, a square a day); the appuntamento clicked on the right.
-- Everything travels in the records: ev (the ones I put up), ea (my answers), eb (my bets), er (how it went for me).
-- Cost: a look at the list every 30 seconds (a few dozen entries); while one I'm in is running, the combat log
-- read for my own lines only (one comparison per line for everyone else's); the windows only when open.
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H
local L = {}
ns.Lunario = L

local GREY, GOLD, GREEN, RED, WHITE = "|cff9d9d9d", "|cffffd100", "|cff20ff20", "|cffff4040", "|cffffffff"
local HL = "Interface\\Buttons\\UI-Listbox-Highlight2"
local SEL = "Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue"

L.KINDS = {
  dg = { name = "Dungeon", icon = "Interface\\Icons\\INV_Misc_Key_03", max = 5, qs = { "d", "h", "tk", "mx", "dt", "fd", "j", "c" } },
  du = { name = "Torneo de duelli", icon = "Interface\\Icons\\Ability_Warrior_Challange", max = 0, qs = { "dw", "dl", "mx", "j", "c" } },
  bg = { name = "Battleground", icon = "Interface\\Icons\\INV_BannerPVP_01", max = 10, qs = { "hk", "d", "h", "mx", "dt", "td" } },
  ca = { name = "Caccia grossa", icon = "Interface\\Icons\\Ability_Hunter_SniperShot", max = 5, qs = { "k", "d", "mx", "tk", "dt", "fd" } },
  wp = { name = "Scorribanda", icon = "Interface\\Icons\\Ability_DualWield", max = 0, qs = { "hk", "d", "mx", "dt", "fd", "td" } },
  qu = { name = "Questona", icon = "Interface\\Icons\\INV_Scroll_03", max = 5, qs = { "k", "q", "g", "dt", "fd", "j" } },
  lv = { name = "Livellata insieme", icon = "Interface\\Icons\\Ability_Rogue_Sprint", max = 0, qs = { "q", "k", "g", "lt", "dt", "j" } },
  al = { name = "Rimpatriata", icon = "Interface\\Icons\\INV_Drink_05", max = 0, qs = { "j", "em", "c", "dt" } },
}
-- ca: an elite, a boss, a rare to kill together; wp: world PvP (a raid on a town, an invasion); qu: a long quest
L.ORDER = { "dg", "ca", "du", "wp", "bg", "qu", "lv", "al" }
-- the questions to bet on, and what each counts (f: the field of the result; low: the lowest wins; fmt: how the
-- number is said)
L.Q = {
  d = { q = "Chi fa più danno?", f = "d", title = "Er macellaio", what = "danno" },
  h = { q = "Chi cura de più?", f = "h", title = "Er dottore", what = "cure" },
  dt = { q = "Chi more de più?", f = "dt", title = "Er più morto", what = "morti" },
  k = { q = "Chi ammazza de più?", f = "k", title = "Er boia", what = "colpi finali" },
  dw = { q = "Chi vince più duelli?", f = "dw", title = "Er re der torneo", what = "duelli vinti" },
  dl = { q = "Chi perde più duelli?", f = "dl", title = "Er sacco da boxe", what = "duelli persi" },
  hk = { q = "Chi fa più uccisioni?", f = "hk", title = "Er legionario", what = "uccisioni" },
  tk = { q = "Chi ne pija de più?", f = "tk", title = "Er sacco de botte", what = "danno preso" },
  mx = { q = "Chi tira la botta più grossa?", f = "mx", title = "Er cannone", what = "in una botta sola" },
  fd = { q = "Chi more pe' primo?", f = "fd", title = "Er primo a cascà", what = "dar via", low = true, fmt = "time" },
  td = { q = "Chi sta più tempo a tera?", f = "td", title = "Er tappeto", what = "da morto", fmt = "time" },
  j = { q = "Chi zompa de più?", f = "j", title = "Er grillo", what = "zompi" },
  c = { q = "Chi chiacchiera de più?", f = "c", title = "Er chiacchierone", what = "righe in chat" },
  em = { q = "Chi fa più er pajaccio?", f = "em", title = "Er pajaccio", what = "emote" },
  g = { q = "Chi se fa più sordi?", f = "g", title = "Er riccone", what = "", fmt = "money" },
  q = { q = "Chi consegna più quest?", f = "q", title = "Er secchione", what = "quest" },
  lt = { q = "Chi trova più robba bona?", f = "lt", title = "Er culone", what = "blu o epici" },
}
L.FIELDS = { "d", "h", "k", "dt", "dw", "dl", "hk", "tk", "mx", "fd", "td", "j", "c", "em", "g", "q", "lt" }
function L.Amount(q, v)
  local Q = L.Q[q] or {}
  if Q.fmt == "time" then
    v = math.floor(v or 0)
    local txt = v >= 60 and (math.floor(v / 60) .. " min" .. (v % 60 > 0 and (" e " .. (v % 60) .. " s") or "")) or (v .. " s")
    return (Q.low and "dopo " or "") .. txt .. (Q.low and "" or (" " .. Q.what))
  elseif Q.fmt == "money" then
    return ns.Money and ns.Money(v or 0, true) or (math.floor((v or 0) / 10000) .. " oro")
  end
  return (U.Thousands and U.Thousands(v) or tostring(v)) .. " " .. (Q.what or "")
end
L.DUNGEONS = { "Ragefire Chasm", "Wailing Caverns", "The Deadmines", "Shadowfang Keep", "Blackfathom Deeps", "The Stockade",
  "Gnomeregan", "Razorfen Kraul", "Scarlet Monastery", "Razorfen Downs", "Uldaman", "Zul'Farrak", "Maraudon",
  "The Temple of Atal'Hakkar", "Blackrock Depths", "Blackrock Spire", "Dire Maul", "Scholomance", "Stratholme" }
L.BGS = { "Warsong Gulch", "Arathi Basin", "Alterac Valley" }
L.MAX_STAKE = 25        -- as the schedina
L.SETTLE_AFTER = 180    -- the results wait three minutes after the end (the records come in)
L.SETTLE_LATEST = 3600  -- after an hour, with whatever came
L.KEEP = 7 * 86400      -- a finished one stays in the list a week

local function Now() return U.Now() end
local function Members() return ns.Sfide and ns.Sfide.Members() or {} end
local function MyRec() return ns.MyRecord and ns.MyRecord() end
local function Short(m) return U.Short(m and m.name) end
local function Colored(m) return m and H.Colored(m) or "?" end
local function MyList(key)
  local rec = MyRec()
  local out = {}
  for _, x in ipairs(rec and rec[key] or {}) do out[#out + 1] = x end
  return out
end
local function NewId() return tostring(ns.recordGuid):sub(-6) .. ":" .. math.floor(Now()) .. ":" .. math.random(100, 999) end
local function Piotte(n) return ns.Tombola and ns.Tombola.Piotte(n) or (n .. " piotte") end
local function Teams() return ns.state and ns.state.settings and ns.state.settings.teams or {} end
local function TeamName(tm)
  if not tm or tm == "" then return "Tutto er patto" end
  for _, t in ipairs(Teams()) do if t.id == tm then return t.name end end
  return "?"
end
local function MyTeam() local r = MyRec() return r and r.team end
local function Save(key, list) if ns.state and ns.recordGuid then P.UpdateSelf(ns.state, ns.recordGuid, { [key] = list }, "lunario") end end
local function Ready() return ns.state and P.HasSettings(ns.state) and not ns.alt end
local function CanAdmin() return ns.CanAdmin and ns.CanAdmin() end

----------------------------------------------------------------------
-- reading the records
----------------------------------------------------------------------
function L.Events()
  local out, seen = {}, {}
  for guid, m in pairs(Members()) do
    for _, e in ipairs(m.ev or {}) do
      if type(e.id) == "string" and not seen[e.id] then
        seen[e.id] = true
        out[#out + 1] = { id = e.id, by = guid, k = e.k, n = e.n, t = e.t, d = e.d or 120, tm = e.tm or "", m = e.m or 0, no = e.no, x = e.x }
      end
    end
  end
  table.sort(out, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.id < b.id end)
  return out
end
function L.Find(id) for _, e in ipairs(L.Events()) do if e.id == id then return e end end end
function L.End(e) return e.t + (e.d or 120) * 60 end
-- "prossimo", "incorso", "finito", "annullato"
function L.State(e, now)
  now = now or Now()
  if e.x == 1 then return "annullato" end
  if now < e.t then return "prossimo" end
  if now < L.End(e) then return "incorso" end
  return "finito"
end
-- an appuntamento for my squadra (or for everybody); filter: "mine", "all" or a team id
function L.Visible(e, filter)
  if filter == "all" then return true end
  if e.tm == "" then return true end
  if filter == nil or filter == "mine" then return e.tm == MyTeam() end
  return e.tm == filter
end
-- everyone's answer: yes, maybe (lists of members) and mine
function L.Answers(e)
  local yes, maybe, no = {}, {}, {}
  local mine
  for guid, m in pairs(Members()) do
    for _, a in ipairs(m.ea or {}) do
      if a.i == e.id then
        local l = a.a == 1 and yes or (a.a == 2 and maybe or no)
        l[#l + 1] = m
        if guid == ns.recordGuid then mine = a.a end
      end
    end
  end
  local function byName(x, y) return tostring(x.name) < tostring(y.name) end
  table.sort(yes, byName) table.sort(maybe, byName)
  return yes, maybe, mine, no
end
-- the bets on e, by question: { q = { total, bets = { { by, p, s } } } }
function L.Pools(e)
  local out = {}
  for _, q in ipairs(L.KINDS[e.k] and L.KINDS[e.k].qs or {}) do out[q] = { total = 0, bets = {} } end
  for guid, m in pairs(Members()) do
    for _, b in ipairs(m.eb or {}) do
      if b.i == e.id and out[b.q] then
        local pool = out[b.q]
        pool.total = pool.total + (b.s or 0)
        pool.bets[#pool.bets + 1] = { by = guid, p = b.p, s = b.s or 0 }
      end
    end
  end
  return out
end
-- how it went for each of those who were there: guid -> er entry
function L.Results(e)
  local out = {}
  for guid, m in pairs(Members()) do
    for _, r in ipairs(m.er or {}) do if r.i == e.id then out[guid] = r end end
  end
  return out
end
-- the results are in: three minutes after the end and everyone who said yes has written his (or an hour after)
function L.ResultsReady(e, now)
  now = now or Now()
  if L.State(e, now) ~= "finito" or now < L.End(e) + L.SETTLE_AFTER then return false end
  if now >= L.End(e) + L.SETTLE_LATEST then return true end
  local res = L.Results(e)
  local yes = L.Answers(e)
  for _, m in ipairs(yes) do if not res[m.guid] then return false end end
  return true
end
-- the winners of a question: who has the most (the least, for who dies first); all of them on a tie; nobody when
-- nobody did any
function L.Winners(e, q, res)
  res = res or L.Results(e)
  local f = L.Q[q] and L.Q[q].f
  local low = L.Q[q] and L.Q[q].low
  local best, out = 0, {}
  for guid, r in pairs(res) do
    local v = f and r[f] or 0
    if v > 0 then
      if best == 0 or (low and v < best) or (not low and v > best) then best, out = v, { [guid] = true }
      elseif v == best then out[guid] = true end
    end
  end
  return out, best
end

----------------------------------------------------------------------
-- doing: put one up, answer, bet, call it off
----------------------------------------------------------------------
-- o: { k, n, t, d, tm, m, no }
function L.Create(o)
  if not Ready() then return false, "Prima entra in un patto." end
  local kind = L.KINDS[o.k]
  if not kind then return false, "Scegli che se fa." end
  local n = type(o.n) == "string" and o.n:gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 40) or ""
  if n == "" then return false, "Scrivi che se fa (er nome)." end
  local t = tonumber(o.t)
  if not t or t < Now() + 60 then return false, "L'ora è già passata." end
  if t > Now() + 60 * 86400 then return false, "Troppo in là: ar massimo du' mesi." end
  local tm = o.tm or ""
  if tm ~= "" and tm ~= MyTeam() and not CanAdmin() then return false, "Pe' 'n'antra squadra lo pò mette solo er capo." end
  local e = { id = NewId(), k = o.k, n = n, t = math.floor(t), d = math.floor(tonumber(o.d) or 120), tm = tm,
    m = math.floor(tonumber(o.m) or kind.max or 0), no = type(o.no) == "string" and o.no:gsub("[%c|]", ""):sub(1, 60) or nil, at = Now() }
  if e.no == "" then e.no = nil end
  -- my list: the new one, then the ones not finished long ago
  local keep = { e }
  for _, x in ipairs(MyList("ev")) do
    if #keep < 6 and Now() < (x.t or 0) + (x.d or 120) * 60 + L.KEEP then keep[#keep + 1] = x end
  end
  Save("ev", keep)
  -- who puts it up is in
  L.Answer(e.id, 1)
  return true, e
end

function L.Answer(id, a)
  if not Ready() then return false, "Prima entra in un patto." end
  local e = L.Find(id) or { id = id }
  if e.t and L.State(e) == "finito" then return false, "È già finito." end
  local keep = { { i = id, a = a, at = Now() } }
  for _, x in ipairs(MyList("ea")) do if #keep < 12 and x.i ~= id then keep[#keep + 1] = x end end
  Save("ea", keep)
  return true
end

function L.Cancel(id)
  local e = L.Find(id)
  if not e then return false, "Nun c'è." end
  if e.by ~= ns.recordGuid and not CanAdmin() then return false, "Lo pò annullà solo chi l'ha messo, o er capo." end
  if e.by ~= ns.recordGuid then
    -- the capo calls off someone else's: a copy of it in his own list, called off (the newest copy wins: x)
    local keep = { { id = e.id, k = e.k, n = e.n, t = e.t, d = e.d, tm = e.tm, m = e.m, no = e.no, x = 1, at = Now() } }
    for _, x in ipairs(MyList("ev")) do if #keep < 6 and x.id ~= e.id then keep[#keep + 1] = x end end
    Save("ev", keep)
  else
    local list = MyList("ev")
    for i, x in ipairs(list) do if x.id == id then
      local c = {} for k, v in pairs(x) do c[k] = v end
      c.x = 1
      list[i] = c
    end end
    Save("ev", list)
  end
  L.SettleAll()
  return true
end

-- my bet on question q of e: one per question, before it starts, on one who said yes (never me or my alt)
function L.Bet(id, q, pick, stake)
  if not Ready() then return false, "Prima entra in un patto." end
  local e = L.Find(id)
  if not e then return false, "Nun c'è." end
  if L.State(e) ~= "prossimo" then return false, "Le puntate se chiudeno quanno comincia." end
  local kind = L.KINDS[e.k]
  local okq = false
  for _, x in ipairs(kind.qs) do if x == q then okq = true end end
  if not okq then return false, "Domanda sbajata." end
  for _, b in ipairs(MyList("eb")) do if b.i == id and b.q == q then return false, "Su 'sta domanda hai già puntato." end end
  local yes = L.Answers(e)
  local inn = false
  for _, m in ipairs(yes) do if m.guid == pick then inn = true end end
  if not inn then return false, "Scegli uno che ce sta." end
  if ns.Tombola and ns.Tombola.Mine(pick) then return false, "Su te stesso (o su 'n alt tuo) nun se punta." end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 1 then return false, "Punta armeno 'na piotta." end
  if stake > L.MAX_STAKE then return false, "Ar massimo " .. Piotte(L.MAX_STAKE) .. "." end
  if not ns.Tombola or stake > ns.Tombola.Balance() then return false, "Nun c'hai abbastanza piotte." end
  local keep = { { i = id, q = q, p = pick, s = stake, at = Now() } }
  for _, x in ipairs(MyList("eb")) do
    local old = L.Find(x.i)
    if #keep < 14 and (not old or Now() < L.End(old) + L.KEEP) then keep[#keep + 1] = x end
  end
  if ns.Sfide and ns.Sfide.Pay then ns.Sfide.Pay("ev:" .. id .. ":" .. q, stake, "ev", pick) end
  Save("eb", keep)
  if ns.Tombola then ns.Tombola.Update() end
  return true
end

-- my bets paid once the results are in (or given back: called off, nobody guessed, nobody did anything)
local function Book() return ns.Sfide and ns.Sfide.Store and ns.Sfide.Store() end
function L.Settle(e)
  local st = Book()
  if not (st and ns.Sfide.Got) then return 0 end
  local mine = {}
  for _, b in ipairs(MyList("eb")) do if b.i == e.id then mine[#mine + 1] = b end end
  if #mine == 0 then return 0 end
  local state = L.State(e)
  local cancelled = state == "annullato"
  if not cancelled and not L.ResultsReady(e) then return 0 end
  local res = not cancelled and L.Results(e) or {}
  local pools = L.Pools(e)
  local net, paid = 0, false
  for _, b in ipairs(mine) do
    local id = "ev:" .. e.id .. ":" .. b.q
    local entry = st.book[id]
    if not entry or entry.got == nil then
      local got = b.s
      if not cancelled then
        local win = L.Winners(e, b.q, res)
        local pool = pools[b.q] or { total = b.s, bets = {} }
        local winStake = 0
        for _, x in ipairs(pool.bets) do if win[x.p] then winStake = winStake + x.s end end
        if winStake > 0 then got = win[b.p] and math.floor(b.s * pool.total / winStake) or 0 end
      end
      ns.Sfide.Got(id, got, "ev", b.p)
      net = net + got - b.s
      paid = true
    end
  end
  if paid and ns.Tombola then ns.Tombola.Update() end
  return net, paid
end
function L.SettleAll()
  for _, e in ipairs(L.Events()) do pcall(L.Settle, e) end
end

----------------------------------------------------------------------
-- counting what I do while one I'm in is running
----------------------------------------------------------------------
local function Tracks()
  if not (ns.db and ns.state) then return {} end
  ns.db.evTrack = type(ns.db.evTrack) == "table" and ns.db.evTrack or {}
  return ns.db.evTrack
end
local active = {} -- id -> track, the ones running now that I'm in
local myGUID, petGUID
local cleu = CreateFrame("Frame")
local function Base()
  local t = MyRec() and MyRec().stats and MyRec().stats.t or {}
  return { dw = t.dw or 0, dl = t.dl or 0, hk = t.hk or 0, g = t.g or 0, q = t.q or 0, lt = (t.lb or 0) + (t.le or 0) }
end
-- what I did in e, as my record says it (er)
local deadAt
local function Write(e, tr)
  local t = MyRec() and MyRec().stats and MyRec().stats.t or {}
  local b = tr.base or {}
  local function delta(now, was) return math.max(0, (now or 0) - (was or now or 0)) end
  local td = (tr.td or 0) + (deadAt and math.max(0, (GetTime and GetTime() or 0) - deadAt) or 0)
  local r = { i = e.id, ok = 1, d = math.floor(tr.d or 0), h = math.floor(tr.h or 0), k = tr.k or 0, dt = tr.dt or 0,
    dw = delta(t.dw, b.dw), dl = delta(t.dl, b.dl), hk = delta(t.hk, b.hk),
    tk = math.floor(tr.tk or 0), mx = math.floor(tr.mx or 0), fd = tr.fd, td = math.floor(td), j = tr.j, c = tr.c, em = tr.em,
    g = delta(t.g, b.g), q = delta(t.q, b.q), lt = delta((t.lb or 0) + (t.le or 0), b.lt) }
  for _, k in ipairs(L.FIELDS) do if (r[k] or 0) <= 0 then r[k] = nil end end
  local keep = { r }
  for _, x in ipairs(MyList("er")) do if #keep < 8 and x.i ~= e.id then keep[#keep + 1] = x end end
  Save("er", keep)
end
-- what I say while one runs (er chiacchierone): the chats of who is with me
local CHATS = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }
function L.Track()
  if not Ready() then return end
  local now = Now()
  local tracks = Tracks()
  local any = false
  for _, e in ipairs(L.Events()) do
    local _, _, mine = L.Answers(e)
    local st = L.State(e, now)
    local tr = tracks[e.id]
    if st == "incorso" and (mine == 1 or mine == 2) then
      if not tr then
        tr = { base = Base(), d = 0, h = 0, k = 0, dt = 0, t = e.t }
        tracks[e.id] = tr
        U.Log("Lunario", "comincia", e.n)
      end
      active[e.id] = tr
      any = true
    elseif tr and not tr.done and (st == "finito" or st == "annullato") then
      active[e.id] = nil
      tr.done = true
      if st == "finito" then
        Write(e, tr)
        if ns.T and ns.T.Bump then pcall(ns.T.Bump, "ap", 1) end
        U.Log("Lunario", "finito", e.n, "danno", tr.d, "cure", tr.h, "colpi", tr.k, "morti", tr.dt)
      end
    end
  end
  for id, tr in pairs(tracks) do
    local e = L.Find(id)
    if (not e and tr.done) or (e and Now() > L.End(e) + L.KEEP) then tracks[id] = nil end
  end
  -- the combat log only while one runs
  if any and not cleu.on then
    cleu.on = true
    myGUID = UnitGUID and U.Plain(UnitGUID("player"), "string")
    petGUID = UnitGUID and U.Plain(UnitGUID("pet"), "string")
    pcall(cleu.RegisterEvent, cleu, "COMBAT_LOG_EVENT_UNFILTERED")
    for _, c in ipairs(CHATS) do pcall(cleu.RegisterEvent, cleu, c) end
  elseif not any and cleu.on then
    cleu.on = false
    pcall(cleu.UnregisterEvent, cleu, "COMBAT_LOG_EVENT_UNFILTERED")
    for _, c in ipairs(CHATS) do pcall(cleu.UnregisterEvent, cleu, c) end
  end
end
-- one line of the combat log: mine (or my pet's) only
local DMG15 = { SPELL_DAMAGE = true, SPELL_PERIODIC_DAMAGE = true, RANGE_DAMAGE = true, DAMAGE_SHIELD = true }
local HEAL = { SPELL_HEAL = true, SPELL_PERIODIC_HEAL = true }
function L.OnCombatLine(sub, src, a12, a15, a16, dst)
  if not next(active) then return end
  local mine = src == myGUID or (petGUID and src == petGUID)
  local dmg, heal, kill, took = 0, 0, 0, 0
  if sub == "SWING_DAMAGE" then dmg = tonumber(a12) or 0
  elseif DMG15[sub] then dmg = tonumber(a15) or 0
  elseif HEAL[sub] then heal = math.max(0, (tonumber(a15) or 0) - (tonumber(a16) or 0))
  elseif sub == "PARTY_KILL" then kill = 1 end
  -- what I take (from anyone but me)
  if dst and dst == myGUID and src ~= myGUID then took = dmg end
  if not mine then dmg, heal, kill = 0, 0, 0 end
  if dmg == 0 and heal == 0 and kill == 0 and took == 0 then return end
  for _, tr in pairs(active) do
    tr.d, tr.h, tr.k, tr.tk = (tr.d or 0) + dmg, (tr.h or 0) + heal, (tr.k or 0) + kill, (tr.tk or 0) + took
    if dmg > (tr.mx or 0) then tr.mx = dmg end
  end
end
cleu:SetScript("OnEvent", function(_, event, ...)
  if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then
    -- a line of chat: mine only (the author's guid is the twelfth argument)
    local guid = select(12, ...)
    if type(guid) == "string" and not U.IsSecret(guid) and guid == myGUID then L.Count("c") end
    return
  end
  if not CombatLogGetCurrentEventInfo then return end
  local ok, _, sub, _, src, _, _, _, dst, _, _, _, a12, _, _, a15, a16 = pcall(CombatLogGetCurrentEventInfo)
  if not ok or U.IsSecret(src) or U.IsSecret(sub) then return end
  if U.IsSecret(a12) or U.IsSecret(a15) or U.IsSecret(a16) then return end
  if U.IsSecret(dst) then dst = nil end
  L.OnCombatLine(sub, src, a12, a15, a16, dst)
end)
-- one more of something countable while one runs (zompi, chat, emote)
function L.Count(key)
  for _, tr in pairs(active) do tr[key] = (tr[key] or 0) + 1 end
end
local lastDeath, lastJump = 0, 0
function L.OnDeath()
  local now = GetTime and GetTime() or 0
  if now - lastDeath < 10 then return end -- (hunters and warlocks: the game says it twice)
  lastDeath = now
  if next(active) then deadAt = now end
  for _, tr in pairs(active) do
    tr.dt = (tr.dt or 0) + 1
    -- the first death: how long after the start
    if not tr.fd then tr.fd = math.max(1, math.floor(Now() - (tr.t or Now()))) end
  end
end
-- back on my feet: the time on the ground
function L.OnAlive()
  if not deadAt then return end
  if UnitIsDeadOrGhost then
    local ok, dead = pcall(UnitIsDeadOrGhost, "player")
    if ok and U.Plain(dead, "boolean") then return end
  end
  local sec = math.max(0, (GetTime and GetTime() or 0) - deadAt)
  deadAt = nil
  for _, tr in pairs(active) do tr.td = (tr.td or 0) + sec end
end
function L.OnJump()
  if not next(active) then return end
  local now = GetTime and GetTime() or 0
  if now - lastJump < 0.4 then return end
  lastJump = now
  L.Count("j")
end
if hooksecurefunc then
  if JumpOrAscendStart then pcall(hooksecurefunc, "JumpOrAscendStart", function() pcall(L.OnJump) end) end
  if C_ChatInfo and C_ChatInfo.PerformEmote then pcall(hooksecurefunc, C_ChatInfo, "PerformEmote", function() if next(active) then L.Count("em") end end)
  elseif DoEmote then pcall(hooksecurefunc, "DoEmote", function() if next(active) then L.Count("em") end end) end
end
-- logging out in the middle: what I did so far goes in my record now
function L.OnLogout()
  for id, tr in pairs(active) do
    local e = L.Find(id)
    if e then pcall(Write, e, tr) end
  end
end

----------------------------------------------------------------------
-- telling: a new one, fifteen minutes before, the start, the summary
----------------------------------------------------------------------
local function Told(key)
  if not ns.db then return true end
  ns.db.evTold = type(ns.db.evTold) == "table" and ns.db.evTold or {}
  if ns.db.evTold[key] then return true end
  ns.db.evTold[key] = Now()
  return false
end
local function Say(text) if ns.News and ns.News.Banner then ns.News.Banner("Caciare:", text, { 1, 0.82, 0 }, "evento") end end
local function Big(e, title, sub)
  if ns.News and ns.News.Annuncio then
    ns.News.Annuncio({ head = "Caciare", title = title, sub = sub, icon = (L.KINDS[e.k] or L.KINDS.al).icon, secs = 9 })
  end
end
function L.When(e)
  return U.Day(e.t) .. ", " .. U.HM(e.t) .. "-" .. U.HM(L.End(e))
end
-- "oggi", "domani", else the day ("dom 8 nov")
local function DayKey(t) local p = U.RomeParts(t) return p.year * 10000 + p.month * 100 + p.day end
function L.DayWord(t, now)
  now = now or Now()
  local k = DayKey(t)
  if k == DayKey(now) then return "oggi" end
  if k == DayKey(now + 86400) then return "domani" end
  return U.Day(t)
end
-- the ones of my squadra still to come or going on now, by time
function L.Upcoming(now)
  now = now or Now()
  local out = {}
  for _, e in ipairs(L.Events()) do
    local st = L.State(e, now)
    if L.Visible(e, "mine") and (st == "prossimo" or st == "incorso") then out[#out + 1] = e end
  end
  return out
end
-- once a day, at the first look: the ones I'm in today and tomorrow, and the ones I haven't answered yet
function L.Daily(now)
  now = now or Now()
  if Told("g:" .. DayKey(now)) then return end
  local mineSoon, open = {}, {}
  for _, e in ipairs(L.Upcoming(now)) do
    local _, _, mine = L.Answers(e)
    if L.State(e, now) == "prossimo" then
      if (mine == 1 or mine == 2) and e.t - now < 2 * 86400 then mineSoon[#mineSoon + 1] = e
      elseif mine == nil then open[#open + 1] = e end
    end
  end
  for i, e in ipairs(mineSoon) do
    if i > 2 then break end
    local day = L.DayWord(e.t, now)
    Say(day .. " a le " .. U.HM(e.t) .. " " .. GOLD .. e.n .. "|r: tu ce stai (tra " .. U.Until(e.t - now) .. ").")
    if i == 1 and day == "oggi" then Big(e, "Oggi a le " .. U.HM(e.t) .. ": " .. e.n, "Tu ce stai: tra " .. U.Until(e.t - now) .. ". Nun mancà.") end
  end
  if #open > 0 then
    local names = {}
    for i, e in ipairs(open) do if i <= 3 then names[#names + 1] = GOLD .. e.n .. "|r (" .. L.DayWord(e.t, now) .. ")" end end
    Say((#open == 1 and "una caciara aspetta la risposta tua: " or (#open .. " caciare aspettano la risposta tua: ")) .. table.concat(names, ", ") .. (#open > 3 and "..." or "") .. ". Ce stai?")
  end
end
local ticks = 0
function L.Tick()
  if not Ready() then return end
  local now = Now()
  L.Track()
  local firstLook = not (ns.db and ns.db.evTold and ns.db.evTold["_"])
  if firstLook then Told("_") end
  ticks = ticks + 1
  -- the daily one a minute after login, when the others' records are in
  if ticks >= 3 then pcall(L.Daily, now) end
  for _, e in ipairs(L.Events()) do
    local st = L.State(e, now)
    local _, _, mine = L.Answers(e)
    local me = L.Visible(e, "mine")
    -- a new one for my squadra, put up by someone else
    if me and st == "prossimo" and e.by ~= ns.recordGuid and not Told("n:" .. e.id) and not firstLook then
      local by = Members()[e.by]
      Say("caciara nova de " .. Short(by) .. ": " .. GOLD .. e.n .. "|r, " .. U.When(e.t) .. " (" .. TeamName(e.tm) .. ").")
      if ns.News then ns.News.Add("Caciara nova: " .. GOLD .. e.n .. "|r, " .. U.When(e.t) .. ".") end
    end
    -- an hour before, for who's in
    if me and st == "prossimo" and e.t - now <= 3600 and e.t - now > 20 * 60 and (mine == 1 or mine == 2) and not Told("h:" .. e.id) then
      Say("tra 'n'ora " .. GOLD .. e.n .. "|r, a le " .. U.HM(e.t) .. ". Nun mancà.")
    end
    -- fifteen minutes before
    if me and st == "prossimo" and e.t - now <= 15 * 60 and e.t - now > 60 and not Told("q:" .. e.id) then
      if mine == 1 or mine == 2 then Say("tra 15 minuti " .. GOLD .. e.n .. "|r. Preparate.")
      elseif mine == nil then Say("tra 15 minuti c'è " .. GOLD .. e.n .. "|r: ce vai?") end
    end
    -- the start
    if st == "incorso" and now - e.t < 300 and (mine == 1 or mine == 2) and not Told("s:" .. e.id) then
      Big(e, "Comincia " .. e.n .. "!", (L.KINDS[e.k] or L.KINDS.al).name .. ", " .. L.When(e) .. ". Daje!")
      if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960, "Master") end
      Say("comincia " .. GOLD .. e.n .. "|r!")
    end
    -- over: the bets, and the summary for who was in or bet
    if st == "finito" or st == "annullato" then
      local net, paid = L.Settle(e)
      if st == "finito" and L.ResultsReady(e, now) and now - L.End(e) < 6 * 3600 and not Told("r:" .. e.id) then
        local res = L.Results(e)
        local bet = false
        for _, b in ipairs(MyList("eb")) do if b.i == e.id then bet = true end end
        if res[ns.recordGuid] or bet then pcall(L.ShowSummary, e, paid and net or nil) end
        if ns.News and next(res) then ns.News.Add("Finito " .. GOLD .. e.n .. "|r: " .. L.SummaryLine(e, res)) end
      end
    end
  end
end

----------------------------------------------------------------------
-- the summary
----------------------------------------------------------------------
local function Thousands(n) return U.Thousands and U.Thousands(n) or tostring(n) end
-- the lines: who was there, then the best at each thing the kind counts
function L.SummaryLines(e, res)
  res = res or L.Results(e)
  local all = Members()
  local lines = {}
  local there = {}
  for guid in pairs(res) do if all[guid] then there[#there + 1] = all[guid] end end
  table.sort(there, function(a, b) return tostring(a.name) < tostring(b.name) end)
  local names = {}
  for i, m in ipairs(there) do if i <= 6 then names[#names + 1] = Colored(m) end end
  lines[#lines + 1] = "Ce so' stati (" .. #there .. "): " .. (#there > 0 and (table.concat(names, ", ") .. (#there > 6 and (GREY .. " e artri " .. (#there - 6) .. "|r") or "")) or (GREY .. "nessuno|r"))
  -- what the kind counts first, then anything else someone did
  local order, seen = {}, {}
  for _, q in ipairs((L.KINDS[e.k] or L.KINDS.al).qs) do order[#order + 1] = q seen[q] = true end
  for _, q in ipairs(L.FIELDS) do if not seen[q] then order[#order + 1] = q end end
  for _, q in ipairs(order) do
    local win, best = L.Winners(e, q, res)
    if best > 0 and #lines < 11 then
      local who = {}
      for guid in pairs(win) do who[#who + 1] = Colored(all[guid]) end
      table.sort(who)
      lines[#lines + 1] = GOLD .. L.Q[q].title .. ":|r " .. table.concat(who, ", ") .. GREY .. "  " .. L.Amount(q, best) .. "|r"
    end
  end
  return lines
end
function L.SummaryLine(e, res)
  local all = Members()
  local parts = {}
  for _, q in ipairs({ "d", "k", "hk", "dw", "dt" }) do
    local win, best = L.Winners(e, q, res)
    local g = next(win)
    if g and best > 0 and #parts < 3 then parts[#parts + 1] = L.Q[q].title:lower() .. " " .. Short(all[g]) end
  end
  return #parts > 0 and (table.concat(parts, ", ") .. ".") or "nessuno ha fatto gnente."
end
local sum
function L.ShowSummary(e, net)
  if not sum then
    local f = CreateFrame("Frame", "ErPattoRiepilogo", UIParent, "BackdropTemplate")
    f:SetSize(380, 200)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end end)
    H.Chrome(f)
    f.head = H.DialogHeader(f, "Er riepilogo", 220)
    local x = H.CloseX(f)
    if x and x.SetScript then x:SetScript("OnClick", function() f:Hide() end) end
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(28, 28)
    f.icon:SetPoint("TOPLEFT", 20, -24)
    f.title = H.Text(f, "GameFontNormal", "", 300)
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2)
    f.when = H.Text(f, "GameFontDisableSmall", "", 300)
    f.when:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    f.lines = {}
    for i = 1, 11 do
      local l = H.Text(f, "GameFontHighlightSmall", "", 340)
      l:SetPoint("TOPLEFT", 22, -60 - (i - 1) * 15)
      if l.SetWordWrap then l:SetWordWrap(false) end
      f.lines[i] = l
    end
    f.net = H.Text(f, "GameFontNormal", "", 340, "CENTER")
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoRiepilogo") end
    sum = f
  end
  local f = sum
  local kind = L.KINDS[e.k] or L.KINDS.al
  f.icon:SetTexture(kind.icon)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.title:SetText(e.n .. ": com'è annata")
  f.when:SetText(kind.name .. ", " .. L.When(e))
  local lines = L.SummaryLines(e)
  for i, l in ipairs(f.lines) do l:SetText(lines[i] or "") end
  local n = math.min(#lines, #f.lines)
  f.net:ClearAllPoints()
  f.net:SetPoint("TOP", f, "TOP", 0, -64 - n * 15)
  if net then
    f.net:SetText("Le puntate tue: " .. (net > 0 and (GREEN .. "+" .. net .. "|r") or net < 0 and (RED .. net .. "|r") or (GREY .. "pari|r")) .. " " .. (ns.Tombola and ns.Tombola.Coin(14) or ""))
  else f.net:SetText("") end
  f:SetHeight(64 + n * 15 + (net and 30 or 8) + 16)
  if ns.News and ns.News.PlaceTop then ns.News.PlaceTop(f, 90) end
  f:Show()
  if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE) or 878, "Master") end
end

----------------------------------------------------------------------
-- the dungeon on the calendar: walking into it before, a reminder
----------------------------------------------------------------------
function L.CheckInstance()
  if not (Ready() and GetInstanceInfo and IsInInstance) then return end
  local ok, inst, kindI = pcall(IsInInstance)
  if not ok or not inst or U.IsSecret(kindI) or kindI ~= "party" then return end
  local name = U.Plain((GetInstanceInfo()), "string")
  if not name then return end
  local low = name:lower()
  local now = Now()
  for _, e in ipairs(L.Events()) do
    if e.k == "dg" and L.Visible(e, "mine") and L.State(e, now) == "prossimo" and e.t - now > 30 * 60 and e.t - now < 7 * 86400 then
      local en = e.n:lower()
      if (low:find(en, 1, true) or en:find(low, 1, true)) and not Told("i:" .. e.id .. ":" .. math.floor(now / 3600)) then
        local yes = L.Answers(e)
        if ns.Sfide and ns.Sfide.Notice then
          ns.Sfide.Notice("Aspetta la squadra!", GOLD .. e.n .. "|r ce l'avete in programma " .. U.When(e.t) .. " (" .. #yes .. " ce stanno).\nSi lo fai mo', poi co' la squadra nun te serve più.", 20)
        end
      end
    end
  end
end

----------------------------------------------------------------------
-- the page
----------------------------------------------------------------------
local page = "list"
local filter = "mine"
local selected     -- id of the appuntamento clicked
local monthY, monthM -- the month shown
local view

local function Icon(parent, size)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size, size)
  t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  return t
end
local function StateText(e)
  local st = L.State(e)
  local now = Now()
  if st == "annullato" then return RED .. "Annullato|r" end
  if st == "incorso" then return GREEN .. "In corso!|r" end
  if st == "finito" then return GREY .. "Finito|r" end
  local d = e.t - now
  if d < 3600 then return GOLD .. "Tra " .. math.max(1, math.floor(d / 60)) .. " minuti|r" end
  if d < 86400 then return GOLD .. "Tra " .. math.floor(d / 3600) .. " ore|r" end
  return "Tra " .. math.floor(d / 86400) .. (math.floor(d / 86400) == 1 and " giorno" or " giorni")
end
local ANSWER = { [1] = GREEN .. "ce stai|r", [2] = GOLD .. "forse|r", [0] = GREY .. "nun ce stai|r" }

-- the list: the ones coming (and running), then the ones finished in the last week
local function ListOf()
  local now = Now()
  local up, done = {}, {}
  for _, e in ipairs(L.Events()) do
    if L.Visible(e, filter) then
      local st = L.State(e, now)
      if st == "prossimo" or st == "incorso" then up[#up + 1] = e
      elseif now < L.End(e) + L.KEEP then done[#done + 1] = e end
    end
  end
  table.sort(done, function(a, b) return a.t > b.t end)
  for _, e in ipairs(done) do up[#up + 1] = e end
  return up
end

local ROWS = 9
local function BuildList(v)
  local box = H.Box(v, 486, 424)
  box:SetPoint("TOPLEFT", 0, -28)
  v.listBox = box
  v.rows = {}
  for i = 1, ROWS do
    local r = CreateFrame("Button", nil, box)
    r:SetSize(466, 44)
    r:SetPoint("TOPLEFT", 10, -10 - (i - 1) * 45)
    r:SetHighlightTexture(HL, "ADD")
    r.selTex = r:CreateTexture(nil, "BACKGROUND")
    r.selTex:SetAllPoints()
    r.selTex:SetTexture(SEL)
    r.selTex:SetBlendMode("ADD")
    r.icon = Icon(r, 32)
    r.icon:SetPoint("LEFT", 4, 0)
    r.title = H.Text(r, "GameFontNormal", "", 330)
    r.title:SetPoint("TOPLEFT", 44, -6)
    if r.title.SetWordWrap then r.title:SetWordWrap(false) end
    r.sub = H.Text(r, "GameFontHighlightSmall", "", 330)
    r.sub:SetPoint("TOPLEFT", 44, -24)
    if r.sub.SetWordWrap then r.sub:SetWordWrap(false) end
    r.state = H.Text(r, "GameFontHighlightSmall", "", 90, "RIGHT")
    r.state:SetPoint("TOPRIGHT", -6, -8)
    r.mine = H.Text(r, "GameFontHighlightSmall", "", 90, "RIGHT")
    r.mine:SetPoint("TOPRIGHT", -6, -24)
    r:SetScript("OnClick", function(self) if self.id then selected = self.id UI.Refresh() end end)
    v.rows[i] = r
  end
  v.none = H.Text(box, "GameFontDisableSmall", "", 440)
  v.none:SetPoint("TOPLEFT", 16, -16)
  v.more = H.Text(box, "GameFontDisableSmall", "", 440)
  v.more:SetPoint("BOTTOMLEFT", 16, 10)
end
local function RefreshList(v)
  local list = ListOf()
  local all = Members()
  for i, r in ipairs(v.rows) do
    local e = list[i]
    if e then
      local kind = L.KINDS[e.k] or L.KINDS.al
      local yes, maybe, mine = L.Answers(e)
      r.id = e.id
      r.icon:SetTexture(kind.icon)
      local st = L.State(e)
      r.title:SetText((st == "finito" or st == "annullato") and (GREY .. U.Day(e.t) .. ", " .. U.HM(e.t) .. "  " .. e.n .. "|r") or (WHITE .. U.Day(e.t) .. ", " .. U.HM(e.t) .. "|r  " .. GOLD .. e.n .. "|r"))
      local places = (e.m or 0) > 0 and (#yes .. "/" .. e.m) or tostring(#yes)
      r.sub:SetText(kind.name .. ", " .. TeamName(e.tm) .. ", " .. places .. " ce stanno" .. (#maybe > 0 and (", " .. #maybe .. " forse") or ""))
      r.state:SetText(StateText(e))
      r.mine:SetText(mine ~= nil and ("Tu: " .. ANSWER[mine]) or (st == "prossimo" and (GREY .. "nun hai risposto|r") or ""))
      r.selTex:SetShown(e.id == selected)
      r:Show()
    else
      r.id = nil
      r:Hide()
    end
  end
  v.none:SetText(#list == 0 and (GREY .. "Gnente in programma. Mettine uno co' \"Novo\".|r") or "")
  v.more:SetText(#list > ROWS and (GREY .. "E artri " .. (#list - ROWS) .. ".|r") or "")
  if not selected and list[1] then selected = list[1].id end
end

-- the month: a square a day, the appuntamenti in it
local MONTHS = { "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre" }
local CW, CH = 66, 60
local function BuildMonth(v)
  local box = H.Box(v, 486, 424)
  box:SetPoint("TOPLEFT", 0, -28)
  v.monthBox = box
  v.monthTitle = H.Text(box, "GameFontNormal", "", 200, "CENTER")
  v.monthTitle:SetPoint("TOP", 0, -10)
  local function arrow(dir, x)
    local b = CreateFrame("Button", nil, box)
    b:SetSize(24, 24)
    b:SetPoint("TOP", box, "TOP", x, -5)
    local base = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
    b:SetNormalTexture(base .. "Up") b:SetPushedTexture(base .. "Down") b:SetDisabledTexture(base .. "Disabled")
    b:SetScript("OnClick", function()
      monthM = monthM + dir
      if monthM < 1 then monthM, monthY = 12, monthY - 1 elseif monthM > 12 then monthM, monthY = 1, monthY + 1 end
      UI.Refresh()
    end)
    return b
  end
  v.prevM = arrow(-1, -116)
  v.nextM = arrow(1, 116)
  for i, d in ipairs({ "lun", "mar", "mer", "gio", "ven", "sab", "dom" }) do
    local t = H.Text(box, "GameFontDisableSmall", d, CW, "CENTER")
    t:SetPoint("TOPLEFT", 12 + (i - 1) * (CW + 1), -34)
  end
  v.cells = {}
  for row = 1, 6 do
    for col = 1, 7 do
      local c = CreateFrame("Button", nil, box)
      c:SetSize(CW, CH)
      c:SetPoint("TOPLEFT", 12 + (col - 1) * (CW + 1), -48 - (row - 1) * (CH + 1))
      c:SetHighlightTexture(HL, "ADD")
      c.bg = c:CreateTexture(nil, "BACKGROUND")
      c.bg:SetAllPoints()
      c.bg:SetTexture("Interface\\Buttons\\UI-Quickslot2")
      c.bg:SetTexCoord(12 / 64, 52 / 64, 12 / 64, 52 / 64)
      c.bg:SetAlpha(0.35)
      c.sel = c:CreateTexture(nil, "ARTWORK")
      c.sel:SetAllPoints()
      c.sel:SetTexture(SEL)
      c.sel:SetBlendMode("ADD")
      c.num = H.Text(c, "GameFontHighlightSmall", "", 30)
      c.num:SetPoint("TOPLEFT", 4, -3)
      c.ev = {}
      for k = 1, 2 do
        local b = CreateFrame("Button", nil, c)
        -- two lines: the icon and the hour, then the name (cut where the square ends)
        b:SetSize(CW - 4, 21)
        b:SetPoint("TOPLEFT", 2, -15 - (k - 1) * 22)
        b:SetHighlightTexture(HL, "ADD")
        b.icon = Icon(b, 11)
        b.icon:SetPoint("TOPLEFT", 1, -1)
        b.time = H.Text(b, "GameFontHighlightSmall", "", CW - 18)
        b.time:SetPoint("TOPLEFT", 14, -1)
        b.text = H.Text(b, "GameFontNormalSmall", "", CW - 6)
        b.text:SetPoint("TOPLEFT", 1, -11)
        if b.text.SetWordWrap then b.text:SetWordWrap(false) end
        b:SetScript("OnClick", function(self) if self.id then selected = self.id UI.Refresh() end end)
        b:SetScript("OnEnter", function(self) if self.e then H.Tip(self, { self.e.n, L.When(self.e), (L.KINDS[self.e.k] or L.KINDS.al).name .. ", " .. TeamName(self.e.tm) }) end end)
        b:SetScript("OnLeave", H.HideTip)
        c.ev[k] = b
      end
      c.more = H.Text(c, "GameFontDisableSmall", "", CW - 30, "RIGHT")
      c.more:SetPoint("TOPRIGHT", -4, -3)
      -- an empty day to come: a new one on that day
      c:SetScript("OnClick", function(self) if self.day and self.day >= math.floor(Now() / 86400) * 86400 - 86400 then L.OpenNew(self.at) end end)
      v.cells[#v.cells + 1] = c
    end
  end
end
local function RefreshMonth(v)
  local now = Now()
  if not monthY then local p = U.RomeParts(now) monthY, monthM = p.year, p.month end
  v.monthTitle:SetText(MONTHS[monthM] .. " " .. monthY)
  local first = U.FromRome(monthY, monthM, 1, 12, 0)
  local wd = U.RomeParts(first).wday -- 0 = sunday
  local lead = (wd + 6) % 7          -- monday first
  local today = U.RomeParts(now)
  local byDay = {}
  for _, e in ipairs(L.Events()) do
    if L.Visible(e, filter) and e.x ~= 1 then
      local p = U.RomeParts(e.t)
      if p.year == monthY and p.month == monthM then byDay[p.day] = byDay[p.day] or {} table.insert(byDay[p.day], e) end
    end
  end
  for i, c in ipairs(v.cells) do
    local day = i - lead
    local at = U.FromRome(monthY, monthM, math.max(1, day), 20, 0)
    local p = U.RomeParts(at)
    local valid = day >= 1 and p.month == monthM and p.day == day
    if valid then
      c.day, c.at = at, at
      local isToday = today.year == monthY and today.month == monthM and today.day == day
      c.num:SetText((isToday and GOLD or WHITE) .. day .. "|r")
      local list = byDay[day] or {}
      local sel = false
      for k, b in ipairs(c.ev) do
        local e = list[k]
        if e then
          b.id, b.e = e.id, e
          b.icon:SetTexture((L.KINDS[e.k] or L.KINDS.al).icon)
          local past = L.State(e, now) == "finito"
          b.time:SetText((past and GREY or "") .. U.HM(e.t) .. (past and "|r" or ""))
          b.text:SetText((past and GREY or "") .. e.n .. (past and "|r" or ""))
          b:Show()
          if e.id == selected then sel = true end
        else
          b.id, b.e = nil, nil
          b:Hide()
        end
      end
      for _, e in ipairs(list) do if e.id == selected then sel = true end end
      c.more:SetText(#list > 2 and ("+" .. (#list - 2)) or "")
      c.sel:SetShown(sel)
      c.bg:SetAlpha(isToday and 0.8 or 0.35)
      c:Show()
    else
      c.day = nil
      c:Hide()
    end
  end
end

-- the one clicked: what, when, who's in, the bets, the buttons
local function BuildDetail(v)
  local box = H.Box(v, 252, 424)
  box:SetPoint("TOPLEFT", 492, -28)
  v.detail = box
  v.dIcon = Icon(box, 36)
  v.dIcon:SetPoint("TOPLEFT", 12, -12)
  v.dTitle = H.Text(box, "GameFontNormal", "", 186)
  v.dTitle:SetPoint("TOPLEFT", 54, -12)
  v.dState = H.Text(box, "GameFontHighlightSmall", "", 186)
  v.dState:SetPoint("TOPLEFT", 54, -32)
  v.dLines = {}
  for i = 1, 4 do
    local t = H.Text(box, "GameFontHighlightSmall", "", 228)
    t:SetPoint("TOPLEFT", 12, -54 - (i - 1) * 14)
    if t.SetWordWrap then t:SetWordWrap(false) end
    v.dLines[i] = t
  end
  -- ce sto / forse / no
  v.ans = {}
  for i, x in ipairs({ { 1, "Ce sto" }, { 2, "Forse" }, { 0, "No" } }) do
    local b = H.Btn(box, x[2], 72, function()
      if not selected then return end
      local ok, msg = L.Answer(selected, x[1])
      v.dErr:SetText(ok and "" or (msg or ""))
    end, 20)
    b:SetPoint("TOPLEFT", 12 + (i - 1) * 76, -116)
    v.ans[i] = b
  end
  v.dWho = H.Text(box, "GameFontNormalSmall", "", 228)
  v.dWho:SetPoint("TOPLEFT", 12, -144)
  v.dYes = H.Text(box, "GameFontHighlightSmall", "", 228)
  v.dYes:SetPoint("TOPLEFT", 12, -158)
  v.dYes:SetJustifyV("TOP")
  v.dMaybe = H.Text(box, "GameFontHighlightSmall", "", 228)
  v.dMaybe:SetPoint("TOPLEFT", 12, -200)
  if v.dMaybe.SetWordWrap then v.dMaybe:SetWordWrap(false) end
  local bt = H.Text(box, "GameFontNormal", "Le puntate", 228)
  bt:SetPoint("TOPLEFT", 12, -222)
  v.dBetTitle = bt
  v.dBets = {}
  for i = 1, 3 do
    local q = H.Text(box, "GameFontNormalSmall", "", 228)
    q:SetPoint("TOPLEFT", 12, -242 - (i - 1) * 34)
    if q.SetWordWrap then q:SetWordWrap(false) end
    local m = H.Text(box, "GameFontHighlightSmall", "", 228)
    m:SetPoint("TOPLEFT", 12, -256 - (i - 1) * 34)
    if m.SetWordWrap then m:SetWordWrap(false) end
    v.dBets[i] = { q = q, m = m }
  end
  v.dErr = H.Text(box, "GameFontRedSmall", "", 228, "CENTER")
  v.dErr:SetPoint("BOTTOM", 0, 40)
  v.betBtn = H.Btn(box, "Scommetti", 110, function() if selected then L.OpenBets(selected) end end, 22)
  v.betBtn:SetPoint("BOTTOMLEFT", 12, 12)
  v.sumBtn = H.Btn(box, "Riepilogo", 110, function() local e = selected and L.Find(selected) if e then L.ShowSummary(e) end end, 22)
  v.sumBtn:SetPoint("BOTTOMLEFT", 12, 12)
  v.cancelBtn = H.Btn(box, "Annulla", 100, function(self)
    local now = GetTime and GetTime() or 0
    if not (self.armed and now - self.armed < 4) then
      self.armed = now
      self:SetText("Sicuro?")
      if C_Timer then C_Timer.After(4, function() self.armed = nil self:SetText("Annulla") end) end
      return
    end
    self.armed = nil
    self:SetText("Annulla")
    local ok, msg = L.Cancel(selected)
    v.dErr:SetText(ok and "" or (msg or ""))
  end, 22)
  v.cancelBtn:SetPoint("BOTTOMRIGHT", -12, 12)
  v.dNone = H.Text(box, "GameFontDisableSmall", "Scegli 'na caciara.", 220)
  v.dNone:SetPoint("TOPLEFT", 14, -16)
end
local function RefreshDetail(v)
  local e = selected and L.Find(selected)
  local all = Members()
  local show = e ~= nil
  for _, x in ipairs({ v.dIcon, v.dTitle, v.dState, v.dWho, v.dYes, v.dMaybe, v.betBtn, v.sumBtn, v.cancelBtn }) do x:SetShown(show) end
  for _, b in ipairs(v.ans) do b:SetShown(show) end
  v.dNone:SetShown(not show)
  if not e then
    for _, t in ipairs(v.dLines) do t:SetText("") end
    for _, b in ipairs(v.dBets) do b.q:SetText("") b.m:SetText("") end
    return
  end
  local kind = L.KINDS[e.k] or L.KINDS.al
  local st = L.State(e)
  v.dIcon:SetTexture(kind.icon)
  v.dTitle:SetText(e.n)
  v.dState:SetText(StateText(e))
  local by = all[e.by]
  local lines = { L.When(e), kind.name .. ", " .. TeamName(e.tm), "L'ha messo " .. Colored(by), e.no and (GREY .. e.no .. "|r") or "" }
  for i, t in ipairs(v.dLines) do t:SetText(lines[i] or "") end
  local yes, maybe, mine = L.Answers(e)
  local open = st == "prossimo" or st == "incorso"
  for i, b in ipairs(v.ans) do
    local a = ({ 1, 2, 0 })[i]
    if open then b:Enable() else b:Disable() end
    b:SetText((mine == a and "> " or "") .. ({ "Ce sto", "Forse", "No" })[i] .. (mine == a and " <" or ""))
  end
  local places = (e.m or 0) > 0 and (" (" .. #yes .. "/" .. e.m .. ")") or (" (" .. #yes .. ")")
  v.dWho:SetText("Ce stanno" .. places)
  local names = {}
  for i, m in ipairs(yes) do
    if i <= 9 then names[#names + 1] = Colored(m) .. ((e.m or 0) > 0 and i > e.m and (GREY .. " (riserva)|r") or "") end
  end
  v.dYes:SetText(#names > 0 and (table.concat(names, ", ") .. (#yes > 9 and (GREY .. " e artri " .. (#yes - 9) .. "|r") or "")) or (GREY .. "Ancora nessuno.|r"))
  local mn = {}
  for i, m in ipairs(maybe) do if i <= 4 then mn[#mn + 1] = Short(m) end end
  v.dMaybe:SetText(#maybe > 0 and (GREY .. "Forse: " .. table.concat(mn, ", ") .. (#maybe > 4 and (" e artri " .. (#maybe - 4)) or "") .. "|r") or "")
  -- the bets: each question, what's on it, mine
  local pools = L.Pools(e)
  local my = {}
  for _, b in ipairs(MyList("eb")) do if b.i == e.id then my[b.q] = b end end
  local res = st == "finito" and L.ResultsReady(e) and L.Results(e) or nil
  local qs = {}
  for _, q in ipairs(kind.qs) do qs[#qs + 1] = q end
  local function rank(q) return (my[q] and 2 or 0) + ((pools[q] and pools[q].total or 0) > 0 and 1 or 0) end
  local pos = {}
  for i, q in ipairs(qs) do pos[q] = i end
  table.sort(qs, function(a, b) if rank(a) ~= rank(b) then return rank(a) > rank(b) end return pos[a] < pos[b] end)
  local total = 0
  for _, q in ipairs(kind.qs) do total = total + (pools[q] and pools[q].total or 0) end
  if v.dBetTitle then v.dBetTitle:SetText("Le puntate " .. GREY .. "(" .. #kind.qs .. " domande, " .. total .. " in palio)|r") end
  for i, row in ipairs(v.dBets) do
    local q = qs[i]
    if q then
      local pool = pools[q]
      row.q:SetText(L.Q[q].q .. GREY .. "  " .. pool.total .. " in palio|r")
      local b = my[q]
      if res then
        local win = L.Winners(e, q, res)
        local who = {}
        for g in pairs(win) do who[#who + 1] = Short(all[g]) end
        row.m:SetText((#who > 0 and ("L'ha fatto " .. GOLD .. table.concat(who, ", ") .. "|r") or (GREY .. "Nessuno|r")) ..
          (b and (b and win[b.p] and (GREEN .. ", hai vinto|r") or (RED .. ", hai perso|r")) or ""))
      elseif b then
        row.m:SetText("Tu: " .. Piotte(b.s) .. " su " .. Colored(all[b.p]))
      else
        row.m:SetText(GREY .. (st == "prossimo" and "Nun hai puntato" or "Puntate chiuse") .. "|r")
      end
    else
      row.q:SetText("") row.m:SetText("")
    end
  end
  v.betBtn:SetShown(st == "prossimo")
  v.sumBtn:SetShown(st == "finito" and L.ResultsReady(e))
  v.cancelBtn:SetShown(st == "prossimo" and (e.by == ns.recordGuid or CanAdmin()) and true or false)
end

local function Build()
  local v = H.NewView("lunario")
  view = v
  v.tabList = H.TopTab(v, "Prossimi", function() page = "list" end)
  v.tabList:SetPoint("TOPLEFT", 0, 0)
  v.tabMonth = H.TopTab(v, "Mese", function() page = "month" end)
  v.tabMonth:SetPoint("LEFT", v.tabList, "RIGHT", 2, 0)
  v.newBtn = H.Btn(v, "Nova", 90, function() L.OpenNew() end, 22)
  v.newBtn:SetPoint("TOPRIGHT", -4, -2)
  v.team = H.Dropdown(v, 170, function(self)
    local items = { { "mine", "La squadra mia" }, { "all", "Tutte" } }
    for _, t in ipairs(Teams()) do items[#items + 1] = { t.id, t.name } end
    ns.Sfide.Choose(self, items, function(x) filter = x end)
  end)
  v.team:SetPoint("RIGHT", v.newBtn, "LEFT", -24, 0)
  BuildList(v)
  BuildMonth(v)
  BuildDetail(v)
end

local function Refresh(v)
  v.tabList:SetSelected(page == "list")
  v.tabMonth:SetSelected(page == "month")
  v.listBox:SetShown(page == "list")
  v.monthBox:SetShown(page == "month")
  local label = filter == "mine" and "La squadra mia" or (filter == "all" and "Tutte" or TeamName(filter))
  v.team:SetText(label)
  if page == "list" then RefreshList(v) else RefreshMonth(v) end
  if selected and not L.Find(selected) then selected = nil end
  RefreshDetail(v)
end

UI.AddView("lunario", "Caciare", Build, Refresh, false)
function L.Show(id)
  if id then selected = id end
  UI.Show("lunario")
end

----------------------------------------------------------------------
-- the windows: a new appuntamento, the bets
----------------------------------------------------------------------
local newDlg
local form = {}
local function DayItems()
  local items = {}
  local now = Now()
  for i = 0, 19 do
    local at = now + i * 86400
    items[#items + 1] = { i, (i == 0 and "Oggi, " or (i == 1 and "Domani, " or "")) .. U.Day(at) }
  end
  return items
end
local HOURS = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 1 }
function L.OpenNew(at)
  local SU = ns.Sfide and ns.Sfide.UI
  if not (SU and Ready()) then return end
  local Choose = ns.Sfide.Choose
  if not newDlg then
    local d = SU.Dialog("ErPattoAppuntamento", 420, 300, "Caciara nova")
    local function Label(text, y) local l = H.Text(d, "GameFontNormalSmall", text, 80) l:SetPoint("TOPLEFT", 24, y) return l end
    local lk = Label("Che se fa", -40)
    d.kind = H.Dropdown(d, 180, function(self)
      local items = {}
      for _, k in ipairs(L.ORDER) do items[#items + 1] = { k, L.KINDS[k].name } end
      Choose(self, items, function(k) form.k = k form.m = L.KINDS[k].max if k ~= form.lastK then form.n = nil end form.lastK = k end)
    end)
    d.kind:SetPoint("TOPLEFT", 110, -34)
    local lw = Label("Dove", -70)
    d.where = H.Dropdown(d, 180, function(self)
      local list = form.k == "bg" and L.BGS or L.DUNGEONS
      local items = {}
      for _, n in ipairs(list) do items[#items + 1] = { n, n } end
      Choose(self, items, function(n) form.n = n d.name:SetText(n) end)
    end)
    d.where:SetPoint("TOPLEFT", 110, -64)
    local ln = Label("Nome", -100)
    d.name = H.Input(d, 180, 40)
    d.name:SetPoint("TOPLEFT", 116, -96)
    local ld = Label("Quanno", -130)
    d.day = H.Dropdown(d, 150, function(self) Choose(self, DayItems(), function(i) form.day = i end) end)
    d.day:SetPoint("TOPLEFT", 110, -124)
    d.hour = H.Dropdown(d, 60, function(self)
      local items = {}
      for _, h in ipairs(HOURS) do items[#items + 1] = { h, string.format("%02d", h) } end
      Choose(self, items, function(h) form.h = h end)
    end)
    d.hour:SetPoint("LEFT", d.day, "RIGHT", 14, 0)
    d.min = H.Dropdown(d, 60, function(self)
      Choose(self, { { 0, "00" }, { 15, "15" }, { 30, "30" }, { 45, "45" } }, function(mi) form.mi = mi end)
    end)
    d.min:SetPoint("LEFT", d.hour, "RIGHT", 14, 0)
    local ll = Label("Quanto dura", -160)
    d.dur = H.Dropdown(d, 110, function(self)
      Choose(self, { { 60, "'n'ora" }, { 90, "'n'ora e mezza" }, { 120, "du' ore" }, { 180, "tre ore" }, { 240, "quattro ore" } }, function(x) form.d = x end)
    end)
    d.dur:SetPoint("TOPLEFT", 110, -154)
    local lp = Label("Posti", -160)
    lp:ClearAllPoints() lp:SetPoint("TOPLEFT", 252, -160)
    d.places = H.Input(d, 34, 2)
    if d.places.SetNumeric then d.places:SetNumeric(true) end
    d.places:SetPoint("TOPLEFT", 296, -156)
    local lt = Label("Pe' chi", -190)
    d.team = H.Dropdown(d, 180, function(self)
      local items = {}
      for _, t in ipairs(Teams()) do
        if t.id == MyTeam() or CanAdmin() then items[#items + 1] = { t.id, t.name } end
      end
      items[#items + 1] = { "", "Tutto er patto" }
      Choose(self, items, function(x) form.tm = x end)
    end)
    d.team:SetPoint("TOPLEFT", 110, -184)
    local lo = Label("Nota", -220)
    d.note = H.Input(d, 260, 60)
    d.note:SetPoint("TOPLEFT", 116, -216)
    d.yes = H.Btn(d, "Mettila", 120, function()
      local now = Now()
      local p = U.RomeParts(now + (form.day or 1) * 86400)
      local t = U.FromRome(p.year, p.month, p.day, form.h or 21, form.mi or 0)
      -- the hours after midnight belong to the night of the day chosen
      if (form.h or 21) < 6 then t = t + 86400 end
      local ok, e = L.Create({ k = form.k, n = d.name:GetText(), t = t, d = form.d or 120, tm = form.tm, m = tonumber(d.places:GetText()) or 0, no = d.note:GetText() })
      if SU.Report(d, ok, e) then
        selected = e.id
        SU.Done(d, "Messo: " .. e.n .. ", " .. U.When(e.t) .. ".", 3)
      end
    end)
    d.no = H.Btn(d, "Lassa stà", 120, function() d:Hide() end)
    SU.TwoButtons(d, "Mettila", "Lassa stà")
    d.msg = H.Text(d, "GameFontNormal", "", 380, "CENTER")
    d.msg:SetPoint("CENTER", 0, -4)
    d.controls = { d.kind, d.where, d.name, d.day, d.hour, d.min, d.dur, d.places, d.team, d.note, d.yes, d.no, lk, lw, ln, ld, ll, lp, lt, lo }
    d.Sync = function()
      d.kind:SetText(form.k and L.KINDS[form.k].name or "Scegli")
      local where = form.k == "dg" or form.k == "bg"
      d.where:SetShown(where and d.yes:IsShown())
      lw:SetShown(where and d.yes:IsShown())
      d.where:SetText(form.n or "Scegli")
      local items = DayItems()
      d.day:SetText(items[(form.day or 1) + 1] and items[(form.day or 1) + 1][2] or "?")
      d.hour:SetText(string.format("%02d", form.h or 21))
      d.min:SetText(string.format("%02d", form.mi or 0))
      local durs = { [60] = "'n'ora", [90] = "'n'ora e mezza", [120] = "du' ore", [180] = "tre ore", [240] = "quattro ore" }
      d.dur:SetText(durs[form.d or 120] or "du' ore")
      if not d.places:HasFocus() then d.places:SetText(tostring(form.m or 0)) end
      d.team:SetText(TeamName(form.tm))
    end
    newDlg = d
  end
  local d = newDlg
  SU.Reset(d)
  form = { k = "dg", m = L.KINDS.dg.max, lastK = "dg", day = 1, h = 21, mi = 0, d = 120, tm = MyTeam() or "" }
  if at then
    local days = math.floor((at - Now()) / 86400 + 0.5)
    form.day = math.max(0, math.min(19, days))
  end
  d.name:SetText("")
  d.note:SetText("")
  d:Show()
  d.Sync()
end
-- keep the window in step with the choices (the dropdowns refresh the patto's window, not this one)
if C_Timer then C_Timer.NewTicker(0.5, function() if newDlg and newDlg:IsShown() and newDlg.Sync then pcall(newDlg.Sync) end end) end

local betDlg
function L.OpenBets(id)
  local SU = ns.Sfide and ns.Sfide.UI
  local e = L.Find(id)
  if not (SU and e) then return end
  local Choose = ns.Sfide.Choose
  if not betDlg then
    local d = SU.Dialog("ErPattoPuntateEv", 560, 300, "Le puntate")
    d.rows = {}
    for i = 1, 8 do
      local r = {}
      local y = -34 - (i - 1) * 28
      r.q = H.Text(d, "GameFontNormalSmall", "", 190)
      r.q:SetPoint("TOPLEFT", 22, y - 6)
      if r.q.SetWordWrap then r.q:SetWordWrap(false) end
      r.pick = H.Dropdown(d, 130, function(self)
        local ev = L.Find(d.id)
        if not ev then return end
        local items = {}
        for _, m in ipairs((L.Answers(ev))) do
          if not (ns.Tombola and ns.Tombola.Mine(m.guid)) then items[#items + 1] = { m.guid, H.Colored(m) } end
        end
        Choose(self, items, function(g) d.picks[i] = g end)
      end)
      r.pick:SetPoint("TOPLEFT", 210, y)
      r.stake = H.Input(d, 32, 2)
      if r.stake.SetNumeric then r.stake:SetNumeric(true) end
      r.stake:SetPoint("TOPLEFT", 366, y - 3)
      r.go = H.Btn(d, "Punta", 60, function()
        local ok, msg = L.Bet(d.id, r.key, d.picks[i], r.stake:GetText())
        d.err:SetText(ok and "" or (msg or ""))
        if ok and PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND) or 120) end
        if d.Sync then d.Sync() end
      end, 20)
      r.go:SetPoint("TOPLEFT", 406, y - 2)
      r.info = H.Text(d, "GameFontHighlightSmall", "", 76, "RIGHT")
      r.info:SetPoint("TOPRIGHT", -20, y - 6)
      r.mine = H.Text(d, "GameFontHighlightSmall", "", 250)
      r.mine:SetPoint("TOPLEFT", 216, y - 6)
      d.rows[i] = r
    end
    d.no = H.Btn(d, "Chiudi", 120, function() d:Hide() end)
    d.no:SetPoint("BOTTOM", 0, 16)
    d.Sync = function()
      local ev = L.Find(d.id)
      if not ev then return end
      local all = Members()
      local kind = L.KINDS[ev.k] or L.KINDS.al
      local pools = L.Pools(ev)
      local my = {}
      for _, b in ipairs(MyList("eb")) do if b.i == ev.id then my[b.q] = b end end
      d.title:SetText("Le puntate: " .. ev.n)
      for i, r in ipairs(d.rows) do
        local q = kind.qs[i]
        r.key = q
        local on = q ~= nil
        r.q:SetShown(on) r.info:SetShown(on)
        if on then
          local pool = pools[q]
          r.q:SetText(L.Q[q].q)
          r.info:SetText(pool.total .. " in palio")
          local b = my[q]
          r.pick:SetShown(not b) r.stake:SetShown(not b) r.go:SetShown(not b) r.mine:SetShown(b ~= nil)
          if b then r.mine:SetText("Tu: " .. Piotte(b.s) .. " su " .. Colored(all[b.p]))
          else
            r.pick:SetText(d.picks[i] and all[d.picks[i]] and Short(all[d.picks[i]]) or "Scegli")
            if not r.stake:HasFocus() and r.stake:GetText() == "" then r.stake:SetText("5") end
          end
        else
          r.pick:Hide() r.stake:Hide() r.go:Hide() r.mine:Hide()
        end
      end
      d:SetHeight(100 + #kind.qs * 28)
    end
    betDlg = d
  end
  local d = betDlg
  SU.Reset(d)
  d.id, d.picks = id, {}
  for _, r in ipairs(d.rows) do r.stake:SetText("5") end
  d:Show()
  d.Sync()
end
if C_Timer then C_Timer.NewTicker(0.5, function() if betDlg and betDlg:IsShown() and betDlg.Sync then pcall(betDlg.Sync) end end) end

----------------------------------------------------------------------
-- wiring
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UNIT_PET" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_DEAD" then pcall(L.OnDeath)
  elseif event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then pcall(L.OnAlive)
  elseif event == "PLAYER_LOGOUT" then pcall(L.OnLogout)
  elseif event == "UNIT_PET" then if unit == "player" and UnitGUID then petGUID = U.Plain(UnitGUID("pet"), "string") end
  elseif C_Timer then C_Timer.After(3, function() pcall(L.CheckInstance) end) end
end)
ns.On("Login", function()
  if not C_Timer then return end
  C_Timer.After(20, function() pcall(L.Tick) end)
  C_Timer.NewTicker(30, function() pcall(L.Tick) end)
end)
