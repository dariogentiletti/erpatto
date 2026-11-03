-- Er Patto: le sfide, la gogna e le taje. The sfottò with something at stake.
--
-- La sfida: you challenge a member, with piotte at stake and a gogna for whoever loses. Three kinds:
--   Duello   the first duel between the two after the yes (3 days to fight it, then the stakes go back)
--   Corsa    the first to reach the next tenth level (10, 20...), from the milestones every record carries
--   Quest    who hands in more quests in the week of the yes
-- The one challenged answers yes or no (a dialog on their screen, or the Sfide page). Each pays the stake when it
-- starts (the one who throws it at once, back if refused or expired); the winner takes both.
--
-- La gogna: whoever loses carries it for a week: a title in front of their name in chat and in the patto's windows
-- ("A Pecora"), its icon next to their name, and on their own screen a picture that stays all week.
--
-- La taja: piotte on someone's head. The first of the patto to beat them in a duel takes them, and they go to the
-- gogna for two days. After a week with nobody collecting, the piotte go back.
--
-- Everything travels in the records (sf, sk, tg, dd: see Patto.CleanMember) and every client works out the same
-- results from them; each keeps the results it found (so short logs can't change them) and its own book of piotte.
local ADDON, ns = ...
local U, M, P, T, UI = ns.U, ns.M, ns.P, ns.T, ns.UI
local H = UI.H
local S = {}
ns.Sfide = S

local DAY = 86400
S.PENDING = DAY           -- time to answer
S.DUEL_WINDOW = 3 * DAY   -- time to fight the duel once accepted
S.RACE_WINDOW = 21 * DAY  -- time to reach the level
S.GOGNA_DAYS = 7
S.TAJA_GOGNA_DAYS = 2
S.TAJA_WINDOW = 7 * DAY

S.KINDS = { d = "Duello", l = "Corsa", q = "Quest" }
S.GOGNE = {
  { name = "A Pecora", icon = "Interface\\Icons\\Spell_Nature_Polymorph", say = "Ha perso e mo' fa bee." },
  { name = "A Tartaruga", icon = "Interface\\Icons\\Ability_Hunter_Pet_Turtle", say = "Lento come la fame." },
  { name = "A Porchetta", icon = "Interface\\Icons\\Ability_Hunter_Pet_Boar", say = "Bono solo pe' 'n panino." },
  { name = "A Cadavere", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", say = "Più morto che vivo." },
  { name = "A Pagliaccio", icon = "Interface\\Icons\\Ability_Rogue_Disguise", say = "Fa ride tutto er patto." },
  { name = "A Granchio", icon = "Interface\\Icons\\Ability_Hunter_Pet_Crab", say = "Cammina de traverso." },
}

local function Now() return U.Now() end
local function Short(m) return (tostring(m and m.name or "?"):match("^(%S+)")) or "?" end
local function Members()
  local out = {}
  if not ns.state then return out end
  for guid, m in pairs(ns.state.members) do out[guid] = m end
  for _, m in ipairs(UI.Members()) do out[m.guid] = m end -- test members too
  return out
end

----------------------------------------------------------------------
-- my book: what I paid in and got back, per sfida or taja
----------------------------------------------------------------------
local function Store()
  if not (ns.db and ns.state) then return nil end
  ns.db.sfide = type(ns.db.sfide) == "table" and ns.db.sfide or {}
  local s = ns.db.sfide[ns.state.code]
  if type(s) ~= "table" then s = {} ns.db.sfide[ns.state.code] = s end
  s.res = s.res or {}     -- id -> { w = winner guid or "" (stakes back), l = loser guid, at = when }
  s.book = s.book or {}   -- id -> { s = paid, got = back }
  s.told = s.told or {}   -- id..":"..what -> true, what we already announced
  s.asked = s.asked or {} -- incoming sfide already shown in a dialog
  return s
end
S.Store = Store

-- piotte in or out because of sfide and taje (Tombola.Balance adds it)
function S.Delta()
  local st = Store()
  if not st then return 0 end
  local d = 0
  for _, e in pairs(st.book) do d = d - (e.s or 0) + (e.got or 0) end
  return d
end

local function Pay(id, s)
  local st = Store()
  st.book[id] = st.book[id] or { s = 0 }
  st.book[id].s = s
end
local function Got(id, n)
  local st = Store()
  st.book[id] = st.book[id] or { s = 0 }
  if st.book[id].got == nil then st.book[id].got = n end
end

----------------------------------------------------------------------
-- reading the records
----------------------------------------------------------------------
-- every sfida, with who threw it
function S.All()
  local out = {}
  for guid, m in pairs(Members()) do
    for _, c in ipairs(m.sf or {}) do
      out[#out + 1] = { id = c.id, from = guid, to = c.to, k = c.k, n = c.n, s = c.s or 0, g = c.g or 0, at = c.at or 0 }
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

function S.Taje()
  local out = {}
  for guid, m in pairs(Members()) do
    for _, t in ipairs(m.tg or {}) do
      out[#out + 1] = { id = t.id, by = guid, on = t.on, s = t.s or 0, g = t.g or 0, at = t.at or 0 }
    end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

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

-- the first to beat x in a duel at or after t (not x): winner, when
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

local function WeekOf(t) return ns.state and P.HasSettings(ns.state) and M.WeekIndex(ns.state.settings, t) or 0 end

-- where a sfida stands: "aspetta", "rifiutata", "scaduta", "incorso", "finita" (+ the result)
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
    if d then r = { w = d.w, l = d.l, at = d.at }
    elseif now - t0 > S.DUEL_WINDOW then r = { w = "", at = t0 + S.DUEL_WINDOW } end
  elseif c.k == "l" then
    local a, b = all[c.from], all[c.to]
    local ta, tb = a and a.ms and a.ms[c.n], b and b.ms and b.ms[c.n]
    if ta and (not tb or ta < tb) then r = { w = c.from, l = c.to, at = ta }
    elseif tb and (not ta or tb < ta) then r = { w = c.to, l = c.from, at = tb }
    elseif ta and tb then r = { w = "", at = ta }
    elseif now - t0 > S.RACE_WINDOW then r = { w = "", at = t0 + S.RACE_WINDOW } end
  elseif c.k == "q" then
    local wk = WeekOf(t0)
    if WeekOf(now) > wk and ns.Tombola then
      local qa = ns.Tombola.Weekly(all[c.from], wk).q or 0
      local qb = ns.Tombola.Weekly(all[c.to], wk).q or 0
      local at = ns.state.settings.start + wk * M.WEEK
      if qa > qb then r = { w = c.from, l = c.to, at = at } elseif qb > qa then r = { w = c.to, l = c.from, at = at } else r = { w = "", at = at } end
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
  if b then
    local r = { w = b.w, l = t.on, at = b.at }
    if st then st.res[t.id] = r end
    return "finita", r
  end
  if Now() - t.at > S.TAJA_WINDOW then
    local r = { w = "", at = t.at + S.TAJA_WINDOW }
    if st then st.res[t.id] = r end
    return "finita", r
  end
  return "aperta"
end

----------------------------------------------------------------------
-- la gogna: who carries one right now
----------------------------------------------------------------------
local gogne = {}
local testG -- test mode: a gogna on me for two minutes, to see it
function S.GognaOf(rec)
  local g = rec and gogne[rec.guid]
  if g and Now() < g.til then return g end
  return nil
end

local function Rebuild()
  gogne = {}
  local all = Members()
  local function put(guid, g, til, why, by)
    local kind = S.GOGNE[g]
    if not kind or Now() >= til then return end
    local cur = gogne[guid]
    if not cur or til > cur.til then
      gogne[guid] = { name = kind.name, icon = kind.icon, say = kind.say, til = til, why = why, by = by }
    end
  end
  for _, c in ipairs(S.All()) do
    local state, r = S.State(c, all)
    if state == "finita" and r.w ~= "" and r.l and c.g > 0 then
      put(r.l, c.g, r.at + S.GOGNA_DAYS * DAY, "ha perso " .. (c.k == "d" and "er duello" or (c.k == "l" and "la corsa ar " .. tostring(c.n) or "la sfida de le quest")), r.w)
    end
  end
  for _, t in ipairs(S.Taje()) do
    local state, r = S.TajaState(t, all)
    if state == "finita" and r.w ~= "" and t.g > 0 then put(t.on, t.g, r.at + S.TAJA_GOGNA_DAYS * DAY, "c'aveva 'na taja ed è stato battuto", r.w) end
  end
  if testG and Now() < testG.til then gogne[ns.recordGuid] = testG end
end
S.Rebuild = Rebuild

-- test mode: me at the gogna for two minutes, and a sfida from a test member, to see how they look
function S.TestGogna()
  local g = S.GOGNE[math.random(#S.GOGNE)]
  local by
  for _, m in ipairs(UI.Members()) do if m.fake then by = m.guid break end end
  testG = { name = g.name, icon = g.icon, say = g.say, til = Now() + 120, why = "ha perso er duello (prova)", by = by }
  Rebuild()
  S.ShowMyGogna()
  if ns.News then ns.News.Banner(Short(ns.MyRecord()) .. " va a la gogna!", g.name .. " (prova). " .. g.say, { 1, 0.5, 0.2 }, "evento") end
  if UI.Refresh then UI.Refresh() end
  if C_Timer then C_Timer.After(121, function() Rebuild() S.ShowMyGogna() UI.Refresh() end) end
end
function S.TestAsk()
  local from
  for _, m in ipairs(UI.Members()) do if m.fake then from = m.guid break end end
  if not from then return end
  S.Ask({ id = "prova", from = from, to = ns.recordGuid, k = "d", s = 10, g = 1, at = Now() })
end

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

-- the next tenth level neither has reached
function S.RaceLevel(other)
  local me = ns.MyRecord()
  local top = math.max(me and me.lv or 1, other and other.lv or 1)
  local n = (math.floor(top / 10) + 1) * 10
  return n <= 60 and n or nil
end

function S.Challenge(to, kind, stake, gogna)
  if not ns.state or ns.alt then return false end
  local all = Members()
  local other = all[to]
  if not other or to == ns.recordGuid then return false, "Scegli chi sfidà." end
  if not S.KINDS[kind] then return false, "Scegli la sfida." end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 0 then return false, "La posta nun pò esse sotto zero." end
  if ns.Tombola and stake > ns.Tombola.Balance() then return false, "Nun c'hai abbastanza piotte." end
  local n
  if kind == "l" then
    n = S.RaceLevel(other)
    if not n then return false, "Ar 60 nun se corre più." end
  end
  for _, c in ipairs(S.All()) do
    local st = S.State(c, all)
    if (st == "aspetta" or st == "incorso") and ((c.from == ns.recordGuid and c.to == to) or (c.from == to and c.to == ns.recordGuid)) then
      return false, "Co' " .. Short(other) .. " c'è già 'na sfida aperta."
    end
  end
  local list = MyList("sf")
  local keep = { { id = NewId(), to = to, k = kind, n = n, s = stake, g = tonumber(gogna) or 0, at = Now() } }
  for _, c in ipairs(list) do if #keep < 6 then keep[#keep + 1] = c end end
  Pay(keep[1].id, stake)
  P.UpdateSelf(ns.state, ns.recordGuid, { sf = keep }, "sfide")
  S.Update()
  return true, keep[1]
end

function S.Answer(id, yes)
  if not ns.state or ns.alt then return false end
  local all = Members()
  local c
  for _, x in ipairs(S.All()) do if x.id == id then c = x end end
  if not c or c.to ~= ns.recordGuid then return false end
  if S.State(c, all) ~= "aspetta" then return false, "'Sta sfida nun aspetta più." end
  if yes and ns.Tombola and c.s > ns.Tombola.Balance() then return false, "Nun c'hai abbastanza piotte pe' 'sta posta." end
  local list = MyList("sk")
  local keep = { { id = id, a = yes and 1 or 0, at = Now() } }
  for _, a in ipairs(list) do if #keep < 10 and a.id ~= id then keep[#keep + 1] = a end end
  if yes then Pay(id, c.s) end
  P.UpdateSelf(ns.state, ns.recordGuid, { sk = keep }, "sfide")
  S.Update()
  return true
end

function S.Taja(on, stake, gogna)
  if not ns.state or ns.alt then return false end
  local all = Members()
  if not all[on] then return false, "Scegli su chi." end
  stake = math.floor(tonumber(stake) or 0)
  if stake < 1 then return false, "La taja è armeno 'na piotta." end
  if ns.Tombola and stake > ns.Tombola.Balance() then return false, "Nun c'hai abbastanza piotte." end
  local list = MyList("tg")
  local keep = { { id = NewId(), on = on, s = stake, g = tonumber(gogna) or 0, at = Now() } }
  for _, t in ipairs(list) do if #keep < 4 then keep[#keep + 1] = t end end
  Pay(keep[1].id, stake)
  P.UpdateSelf(ns.state, ns.recordGuid, { tg = keep }, "sfide")
  S.Update()
  return true
end

----------------------------------------------------------------------
-- keeping up: my book, the news, the dialogs, my own gogna
----------------------------------------------------------------------
local function Tell(st, id, what, fn)
  local k = id .. ":" .. what
  if st.told[k] then return end
  st.told[k] = true
  fn()
end

local function Name(all, guid) return Short(all[guid]) end
local function What(c, all)
  local w = S.KINDS[c.k] .. (c.k == "l" and (" ar " .. tostring(c.n)) or "")
  if c.s > 0 then w = w .. ", " .. (ns.Tombola and ns.Tombola.Piotte(c.s) or (c.s .. " piotte")) end
  local g = S.GOGNE[c.g]
  if g then w = w .. ", chi perde: " .. g.name end
  return w
end
S.What = What

local quiet = true -- the first pass after login only learns what is already there
function S.Update()
  local st = Store()
  if not st or not P.HasSettings(ns.state) then return end
  local all = Members()
  local News = ns.News
  local me = ns.recordGuid
  for _, c in ipairs(S.All()) do
    local state, r, ans = S.State(c, all)
    local mine = c.from == me or c.to == me
    -- my book
    if mine and not ns.alt then
      if state == "rifiutata" or state == "scaduta" then
        if c.from == me then Got(c.id, c.s) end
      elseif state == "finita" then
        if r.w == "" then Got(c.id, st.book[c.id] and st.book[c.id].s or 0)
        elseif r.w == me then Got(c.id, 2 * c.s)
        else Got(c.id, 0) end
      end
    end
    -- the news, once each
    if ans and ans.a == 1 then
      Tell(st, c.id, "si", function()
        if not quiet and News then
          News.Add("|cffffd100" .. Name(all, c.to) .. "|r ha accettato la sfida de |cffffd100" .. Name(all, c.from) .. "|r: " .. What(c, all))
          if c.k == "d" then News.Banner(Name(all, c.from) .. " contro " .. Name(all, c.to), "Sfida a duello: " .. What(c, all), nil, "evento") end
        end
      end)
    end
    if state == "finita" then
      Tell(st, c.id, "fine", function()
        if quiet or not News then return end
        if r.w == "" then
          News.Add("La sfida tra " .. Name(all, c.from) .. " e " .. Name(all, c.to) .. " è finita pari: poste ridate.")
        else
          local g = S.GOGNE[c.g]
          News.Add("|cffffd100" .. Name(all, r.w) .. "|r ha vinto la sfida co' |cffffd100" .. Name(all, r.l) .. "|r" ..
            (c.s > 0 and (" (+" .. (2 * c.s) .. ")") or "") .. (g and (". " .. Name(all, r.l) .. " va a la gogna: " .. g.name) or ""))
          if g then News.Banner(Name(all, r.l) .. " va a la gogna!", g.name .. " pe' 'na settimana. " .. g.say, { 1, 0.5, 0.2 }, "evento") end
        end
      end)
    end
    -- a sfida for me: ask
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
    Tell(st, t.id, "su", function()
      if quiet or not News then return end
      News.Add("Taja de |cffffffff" .. t.s .. "|r piotte su |cffffd100" .. Name(all, t.on) .. "|r: chi lo batte a duello se le pija.")
      News.Banner("Taja su " .. Name(all, t.on), t.s .. " piotte a chi lo batte a duello", { 1, 0.5, 0.2 }, "evento")
    end)
    if state == "finita" and r.w ~= "" then
      Tell(st, t.id, "presa", function()
        if quiet or not News then return end
        local g = S.GOGNE[t.g]
        News.Add("|cffffd100" .. Name(all, r.w) .. "|r s'è pijato la taja su |cffffd100" .. Name(all, t.on) .. "|r (" .. t.s .. " piotte)" ..
          (g and (". " .. Name(all, t.on) .. " a la gogna pe' du' giorni: " .. g.name) or ""))
      end)
    end
  end
  -- duels between patto members make the news (told by the winner's record)
  for guid, m in pairs(all) do
    for _, d in ipairs(m.dd or {}) do
      if d.w == 1 then
        Tell(st, "duel:" .. guid .. ":" .. tostring(d.at), "x", function()
          if not quiet and News then News.Add("|cffffd100" .. Short(m) .. "|r ha battuto |cffffd100" .. Name(all, d.o) .. "|r a duello.") end
        end)
      end
    end
  end
  quiet = false
  Rebuild()
  S.ShowMyGogna()
  if ns.Tombola then ns.Tombola.Update() end
end

----------------------------------------------------------------------
-- the dialog for a sfida thrown at me
----------------------------------------------------------------------
local ask
function S.Ask(c, all)
  all = all or Members()
  if not ask then
    ask = CreateFrame("Frame", "ErPattoSfida", UIParent)
    ask:SetSize(380, 150)
    ask:SetPoint("CENTER", 0, 160)
    ask:SetFrameStrata("DIALOG")
    ask:SetToplevel(true)
    ask:EnableMouse(true)
    H.Chrome(ask)
    H.DialogHeader(ask, "Sfida!", 160)
    ask.text = H.Text(ask, "GameFontHighlight", "", 340, "CENTER")
    ask.text:SetPoint("TOP", 0, -34)
    ask.yes = H.Btn(ask, "Accetto", 110, function()
      if ask.id == "prova" then ask:Hide() return end
      local ok, msg = S.Answer(ask.id, true)
      if not ok and msg then U.Say("|cffff4040" .. msg .. "|r") end
      ask:Hide()
    end)
    ask.yes:SetPoint("BOTTOMRIGHT", ask, "BOTTOM", -6, 18)
    ask.no = H.Btn(ask, "Me tiro indietro", 130, function() if ask.id ~= "prova" then S.Answer(ask.id, false) end ask:Hide() end)
    ask.no:SetPoint("BOTTOMLEFT", ask, "BOTTOM", 6, 18)
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoSfida") end
  end
  ask.id = c.id
  ask.text:SetText("|cffffd100" .. Name(all, c.from) .. "|r te sfida.\n" .. What(c, all))
  ask:Show()
  if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE) or 880) end
end

----------------------------------------------------------------------
-- my gogna, on my own screen all week: the icon in a vanilla slot, its name under it
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
      if x then H.Tip(self, { "La gogna: " .. x.name, x.say, "Te l'ha data " .. Short(Members()[x.by]) .. ": " .. x.why .. ".", "Fino a " .. U.When(x.til) }) end
    end)
    pic:SetScript("OnLeave", H.HideTip)
  end
  pic.icon:SetTexture(g.icon)
  pic.name:SetText(g.name)
  pic:Show()
end

ns.On("MemberUpdated", function() S.Update() end)
ns.On("SelfChanged", function(state, reason) if reason ~= "pts" and reason ~= "sfide" then Rebuild() end end)
ns.On("Login", function()
  if C_Timer then
    C_Timer.After(10, S.Update)
    C_Timer.NewTicker(60, S.Update)
  end
end)

----------------------------------------------------------------------
-- the Sfide page of Er Botteghino
----------------------------------------------------------------------
local GREY, GOLD = "|cff9d9d9d", "|cffffd100"
local form = { kind = "d", g = 1, tg = 1 }

-- a vanilla list of the members under a button (the dropdown look: a dialog box)
local picker
local function Pick(anchor, onPick)
  if not picker then
    picker = CreateFrame("Frame", "ErPattoSfidePick", UIParent)
    picker:SetFrameStrata("DIALOG")
    picker:SetToplevel(true)
    picker:EnableMouse(true)
    H.Chrome(picker)
    picker.rows = {}
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoSfidePick") end
    picker:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    picker:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    picker:SetScript("OnEvent", function(self)
      local over = MouseIsOver and (MouseIsOver(self) or (self.anchor and MouseIsOver(self.anchor)))
      if not over then self:Hide() end
    end)
  end
  picker.anchor = anchor
  local list = {}
  for _, m in ipairs(UI.Members()) do if m.guid ~= ns.recordGuid then list[#list + 1] = m end end
  table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
  for _, r in ipairs(picker.rows) do r:Hide() end
  local shown = math.min(20, #list)
  for i = 1, shown do
    local r = picker.rows[i]
    if not r then
      r = CreateFrame("Button", nil, picker)
      r:SetSize(160, 16)
      r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
      r.text = H.Text(r, "GameFontHighlightSmall", "", 120)
      r.text:SetPoint("LEFT", 4, 0)
      r.lv = H.Text(r, "GameFontHighlightSmall", "", 36, "RIGHT")
      r.lv:SetPoint("RIGHT", -2, 0)
      r:SetScript("OnClick", function(self) picker:Hide() if picker.onPick then picker.onPick(self.guid) end UI.Refresh() end)
      picker.rows[i] = r
    end
    r.guid = list[i].guid
    r.text:SetText(H.Colored(list[i]))
    r.lv:SetText(tostring(list[i].lv or "?"))
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 16, -16 - (i - 1) * 16)
    r:Show()
  end
  picker.onPick = onPick
  picker:SetSize(192, 32 + shown * 16)
  picker:ClearAllPoints()
  picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  picker:Show()
end

-- a row of the gogna icons in vanilla slots; click one to choose it, again to have none
local function GognaRow(parent, x, y, key)
  local row = {}
  for i, g in ipairs(S.GOGNE) do
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 26)
    b:SetPoint("TOPLEFT", x + (i - 1) * 30, y)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(g.icon)
    b.on = b:CreateTexture(nil, "OVERLAY")
    b.on:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.on:SetBlendMode("ADD")
    b.on:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetScript("OnClick", function() form[key] = (form[key] == i) and 0 or i UI.Refresh() end)
    b:SetScript("OnEnter", function(self) H.Tip(self, { g.name, g.say }) end)
    b:SetScript("OnLeave", H.HideTip)
    row[i] = b
  end
  return row
end

local function Say(ok, msg) if not ok and msg then U.Say("|cffff4040" .. msg .. "|r") end end

-- open the Sfide page with someone already chosen
function S.Prefill(guid)
  form.to = guid
  if ns.Botteghino then ns.Botteghino.Show("sfide") end
end

function S.BuildPage(v)
  local p = CreateFrame("Frame", nil, v)
  p:SetAllPoints()
  v.sfide = p
  -- throw a sfida
  local a = H.Box(p, 360, 206)
  a:SetPoint("TOPLEFT", 0, -28)
  local t = H.Text(a, "GameFontNormal", "Lancia 'na sfida", 200) t:SetPoint("TOPLEFT", 12, -12)
  local function Label(box, text, y) local l = H.Text(box, "GameFontNormalSmall", text, 60) l:SetPoint("TOPLEFT", 14, y) return l end
  Label(a, "Contro", -38)
  p.who = H.Btn(a, "Scegli", 150, function(self) Pick(self, function(g) form.to = g end) end, 20)
  p.who:SetPoint("TOPLEFT", 76, -34)
  Label(a, "Sfida", -64)
  p.kinds = {}
  local kx = 76
  for _, k in ipairs({ "d", "l", "q" }) do
    local r = H.Radio(a, k == "d" and "Duello" or (k == "l" and "Corsa ar livello" or "Più quest"), function() form.kind = k end)
    r:SetPoint("TOPLEFT", kx, -62)
    r.k = k
    kx = kx + r:GetWidth() + 12
    p.kinds[#p.kinds + 1] = r
  end
  Label(a, "Posta", -90)
  p.stake = H.Input(a, 50, 5)
  if p.stake.SetNumeric then p.stake:SetNumeric(true) end
  p.stake:SetPoint("TOPLEFT", 82, -86)
  p.stakeNote = H.Text(a, "GameFontHighlightSmall", "", 180) p.stakeNote:SetPoint("TOPLEFT", 140, -90)
  Label(a, "Chi perde", -118)
  p.gRow = GognaRow(a, 76, -112, "g")
  p.gText = H.Text(a, "GameFontHighlightSmall", "", 260) p.gText:SetPoint("TOPLEFT", 76, -144)
  p.go = H.Btn(a, "Sfida!", 110, function()
    local ok, msg = S.Challenge(form.to, form.kind, p.stake:GetText(), form.g)
    if ok then p.stake:SetText("") U.Say("sfida lanciata a " .. Short(Members()[form.to]) .. ".") end
    Say(ok, msg)
  end, 22)
  p.go:SetPoint("BOTTOMRIGHT", -12, 12)
  p.testGogna = H.Btn(a, "Prova: gogna", 100, function() S.TestGogna() end, 18)
  p.testGogna:SetPoint("TOPRIGHT", -10, -8)
  p.testAsk = H.Btn(a, "Prova: sfida", 100, function() S.TestAsk() end, 18)
  p.testAsk:SetPoint("BOTTOMLEFT", 12, 12)

  -- put a taja
  local b = H.Box(p, 360, 135)
  b:SetPoint("TOPLEFT", 0, -240)
  local tb = H.Text(b, "GameFontNormal", "Metti 'na taja", 200) tb:SetPoint("TOPLEFT", 12, -12)
  Label(b, "Su chi", -38)
  p.on = H.Btn(b, "Scegli", 150, function(self) Pick(self, function(g) form.on = g end) end, 20)
  p.on:SetPoint("TOPLEFT", 76, -34)
  Label(b, "Taja", -64)
  p.taja = H.Input(b, 50, 5)
  if p.taja.SetNumeric then p.taja:SetNumeric(true) end
  p.taja:SetPoint("TOPLEFT", 82, -60)
  local pt = H.Text(b, "GameFontHighlightSmall", "piotte", 60) pt:SetPoint("TOPLEFT", 140, -64)
  Label(b, "Gogna", -92)
  p.tRow = GognaRow(b, 76, -86, "tg")
  p.put = H.Btn(b, "Metti", 80, function()
    local ok, msg = S.Taja(form.on, p.taja:GetText(), form.tg)
    if ok then p.taja:SetText("") end
    Say(ok, msg)
  end, 22)
  p.put:SetPoint("BOTTOMRIGHT", -12, 12)

  -- the sfide
  local c = H.Box(p, 378, 232)
  c:SetPoint("TOPLEFT", 366, -28)
  local tc = H.Text(c, "GameFontNormal", "Le sfide", 200) tc:SetPoint("TOPLEFT", 12, -12)
  p.rows = {}
  for i = 1, 6 do
    local y = -32 - (i - 1) * 32
    local r = {}
    r.top = H.Text(c, "GameFontHighlightSmall", "", 230) r.top:SetPoint("TOPLEFT", 14, y)
    if r.top.SetWordWrap then r.top:SetWordWrap(false) end
    r.state = H.Text(c, "GameFontHighlightSmall", "", 120, "RIGHT") r.state:SetPoint("TOPRIGHT", -14, y)
    r.what = H.Text(c, "GameFontDisableSmall", "", 250) r.what:SetPoint("TOPLEFT", 14, y - 13)
    if r.what.SetWordWrap then r.what:SetWordWrap(false) end
    r.yes = H.Btn(c, "Accetto", 58, function(self) local ok, msg = S.Answer(self.id, true) Say(ok, msg) end, 16)
    r.yes:SetPoint("TOPRIGHT", -74, y - 12)
    r.no = H.Btn(c, "No", 40, function(self) S.Answer(self.id, false) end, 16)
    r.no:SetPoint("TOPRIGHT", -30, y - 12)
    p.rows[i] = r
  end
  p.none = H.Text(c, "GameFontDisableSmall", "", 340) p.none:SetPoint("TOPLEFT", 14, -32)

  -- who is at the gogna, the open taje
  local d = H.Box(p, 378, 109)
  d:SetPoint("TOPLEFT", 366, -266)
  local td = H.Text(d, "GameFontNormal", "La gogna e le taje", 200) td:SetPoint("TOPLEFT", 12, -12)
  p.lines = {}
  for i = 1, 5 do
    local l = H.Text(d, "GameFontHighlightSmall", "", 250) l:SetPoint("TOPLEFT", 14, -30 - (i - 1) * 14)
    if l.SetWordWrap then l:SetWordWrap(false) end
    l.right = H.Text(d, "GameFontHighlightSmall", "", 110, "RIGHT") l.right:SetPoint("TOPRIGHT", -14, -30 - (i - 1) * 14)
    p.lines[i] = l
  end
end

local STATE_TEXT = { aspetta = GREY .. "aspetta risposta|r", rifiutata = GREY .. "rifiutata|r", scaduta = GREY .. "scaduta|r", incorso = GOLD .. "in corso|r" }

function S.RefreshPage(v)
  local p = v.sfide
  local all = Members()
  local testing = ns.Tombola and ns.Tombola.Testing()
  p.testGogna:SetShown(testing and true or false)
  p.testAsk:SetShown(testing and true or false)
  p.who:SetText(form.to and all[form.to] and Short(all[form.to]) or "Scegli")
  p.on:SetText(form.on and all[form.on] and Short(all[form.on]) or "Scegli")
  local race = S.RaceLevel(form.to and all[form.to])
  for _, r in ipairs(p.kinds) do
    r:SetSelected(form.kind == r.k)
    if r.k == "l" then r.text:SetText("Corsa ar " .. tostring(race or "60")) end
  end
  p.stakeNote:SetText("piotte, chi vince se pija er doppio")
  for i, b in ipairs(p.gRow) do b.on:SetShown(form.g == i) end
  for i, b in ipairs(p.tRow) do b.on:SetShown(form.tg == i) end
  local g = S.GOGNE[form.g]
  p.gText:SetText(g and (GOLD .. g.name .. "|r pe' 'na settimana") or (GREY .. "nessuna gogna|r"))
  p.go:SetEnabled(form.to ~= nil)
  p.put:SetEnabled(form.on ~= nil)
  -- the sfide: mine first, then the others
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
      r.what:SetText(What(c, all))
      local ask = state == "aspetta" and c.to == ns.recordGuid
      r.yes.id, r.no.id = c.id, c.id
      r.yes:SetShown(ask) r.no:SetShown(ask)
      r.top:Show() r.state:Show() r.what:Show()
    else
      r.top:Hide() r.state:Hide() r.what:Hide() r.yes:Hide() r.no:Hide()
    end
  end
  p.none:SetText(shown == 0 and (GREY .. "Ancora nessuna sfida.|r") or "")
  -- the gogna and the taje
  local lines = {}
  for _, m in ipairs(UI.Members()) do
    local x = S.GognaOf(m)
    if x then lines[#lines + 1] = { H.Colored(m) .. " " .. GOLD .. x.name .. "|r", "fino a " .. U.Day(x.til) } end
  end
  for _, t in ipairs(S.Taje()) do
    if S.TajaState(t, all) == "aperta" then
      lines[#lines + 1] = { "Taja su " .. H.Colored(all[t.on] or { name = "?" }), t.s .. " " .. (ns.Tombola and ns.Tombola.Coin(12) or "") }
    end
  end
  if #lines == 0 then lines[1] = { GREY .. "Nessuno a la gogna, nessuna taja.|r", "" } end
  for i, l in ipairs(p.lines) do
    local x = lines[i]
    l:SetText(x and x[1] or "")
    l.right:SetText(x and x[2] or "")
  end
end
