-- Er Patto: the "Casa" tab, the first one you see, and Er Bollettino.
--   Casa answers four questions at a glance: where am I against the cap and what should I do now; who is playing
--   now; what happened lately; who is leading this week (and my tombola).
--   Er Bollettino is last week's recap: it opens by itself at the first login after the weekly reset.
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H
local Home = {}
ns.Home = Home

local GREY = "|cff9d9d9d"
local function Short(m) return (tostring(m.name or "?"):match("^(%S+)")) or "?" end
local function Colored(m) return "|c" .. H.ClassHex(m.cls) .. Short(m) .. "|r" end
local function Gold(c) return string.format("%d oro", math.floor((c or 0) / 10000)) end
local function Hours(sec) return U.Hours((sec or 0) / 3600) end

-- the leader of a week for a value: member, value (nil when nobody did anything)
local function Leader(list, fn)
  local best, bestV
  for _, m in ipairs(list) do
    local v = fn(m) or 0
    if v > 0 and (not bestV or v > bestV or (v == bestV and tostring(m.name) < tostring(best.name))) then best, bestV = m, v end
  end
  return best, bestV
end
-- a week's count (in test mode, before the start, the pre-start week stands in for week 1)
local function W(m, wk, k)
  if ns.Tombola then return ns.Tombola.Weekly(m, wk)[k] or 0 end
  local w = m.stats and m.stats.w and m.stats.w[wk]
  return type(w) == "table" and (w[k] or 0) or 0
end
-- level against the cap, short enough for a narrow column
local function ShortState(lv, cap)
  local s, d = M.PlayerState(lv, cap)
  if s == "over" then return "|cffff4040+" .. d .. "|r" end
  if s == "at" then return "|cff40ff40cap|r" end
  if s == "behind" then return "|cffffd100-" .. d .. "|r" end
  return ""
end

----------------------------------------------------------------------
-- build
----------------------------------------------------------------------
local function Title(box, text)
  local t = H.Text(box, "GameFontNormal", text, 330)
  t:SetPoint("TOPLEFT", 12, -10)
  return t
end

local function Build()
  local v = H.NewView("casa")
  -- my cap
  local a = H.Box(v, 368, 176)
  a:SetPoint("TOPLEFT", 0, 0)
  v.capTitle = Title(a, "Er cap tuo")
  v.team = H.Text(a, "GameFontHighlightSmall", "", 160, "RIGHT")
  v.team:SetPoint("TOPRIGHT", -12, -12)
  v.capBig = H.Text(a, "GameFontNormalHuge", "", 120)
  v.capBig:SetPoint("TOPLEFT", 14, -32)
  v.capState = H.Text(a, "GameFontHighlightLarge", "", 220)
  v.capState:SetPoint("TOPLEFT", 130, -36)
  v.bar = H.CapBar(a, 344, 18)
  v.bar:SetPoint("TOPLEFT", 12, -66)
  v.next = H.Text(a, "GameFontHighlightSmall", "", 344)
  v.next:SetPoint("TOPLEFT", 14, -90)
  v.tip = H.Text(a, "GameFontNormalSmall", "", 344)
  v.tip:SetPoint("TOPLEFT", 14, -110)
  v.tip:SetHeight(56)
  if v.tip.SetJustifyV then v.tip:SetJustifyV("TOP") end

  -- online now
  local b = H.Box(v, 368, 176)
  b:SetPoint("TOPLEFT", 376, 0)
  v.onTitle = Title(b, "Mo' online")
  v.online = {}
  for i = 1, 8 do
    local r = {}
    r.name = H.Text(b, "GameFontHighlightSmall", "", 120)
    r.name:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 17)
    r.lv = H.Text(b, "GameFontHighlightSmall", "", 76)
    r.lv:SetPoint("TOPLEFT", 134, -30 - (i - 1) * 17)
    if r.lv.SetWordWrap then r.lv:SetWordWrap(false) end
    r.zone = H.Text(b, "GameFontDisableSmall", "", 140)
    r.zone:SetPoint("TOPLEFT", 210, -30 - (i - 1) * 17)
    if r.zone.SetWordWrap then r.zone:SetWordWrap(false) end
    v.online[i] = r
  end

  -- news
  local c = H.Box(v, 368, 191)
  c:SetPoint("TOPLEFT", 0, -184)
  v.newsTitle = Title(c, "Notizie")
  v.news = {}
  for i = 1, 9 do
    local r = CreateFrame("Frame", nil, c)
    r:SetSize(344, 16)
    r:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 17)
    r:EnableMouse(true)
    r.text = H.Text(r, "GameFontHighlightSmall", "", 290)
    r.text:SetPoint("LEFT", 0, 0)
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r.when = H.Text(r, "GameFontDisableSmall", "", 52, "RIGHT")
    r.when:SetPoint("RIGHT", 0, 0)
    r:SetScript("OnEnter", function(self) if self.full then H.Tip(self, { self.full }) end end)
    r:SetScript("OnLeave", H.HideTip)
    v.news[i] = r
  end

  -- this week
  local d = H.Box(v, 368, 191)
  d:SetPoint("TOPLEFT", 376, -184)
  v.weekTitle = Title(d, "'Sta settimana")
  v.week = {}
  for i = 1, 6 do
    local l = H.Text(d, "GameFontHighlightSmall", "", 344)
    l:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 17)
    if l.SetWordWrap then l:SetWordWrap(false) end
    v.week[i] = l
  end
  v.tomb = H.Text(d, "GameFontNormalSmall", "", 344)
  v.tomb:SetPoint("TOPLEFT", 12, -136)
  v.tombBtn = H.Btn(d, "Botteghino", 88, function() UI.Show("botteghino") end, 20)
  v.tombBtn:SetPoint("BOTTOMLEFT", 12, 10)
  v.bullBtn = H.Btn(d, "Bollettino", 84, function() Home.ShowBulletin(true) end, 20)
  v.bullBtn:SetPoint("LEFT", v.tombBtn, "RIGHT", 6, 0)
  v.shareBtn = H.Btn(d, "Condividi", 84, function() if ns.Extras then ns.Extras.ShowShare() end end, 20)
  v.shareBtn:SetPoint("LEFT", v.bullBtn, "RIGHT", 6, 0)
  v.helpBtn = H.Btn(d, "Aiuto", 56, function() if ns.Extras then ns.Extras.ShowGuide() end end, 20)
  v.helpBtn:SetPoint("LEFT", v.shareBtn, "RIGHT", 6, 0)
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
local function CapAdvice(st, rec)
  if not st then return GREY .. "Scegli la squadra (tab Squadre) pe' vede er cap tuo.|r" end
  if not st.started then
    return "Er patto parte tra " .. U.Until(ns.state.settings.start - U.Now()) .. ". Intanto: fatte er personaggio, entra in gilda co' l'amichi e invitali (/patto invita Nome)."
  end
  if st.lifted then return "Niente più cap: vai ar 60!" end
  local s, d = M.PlayerState(rec and rec.lv, st.cap)
  if s == "over" then
    return "|cffff4040Sei sopra er cap de " .. d .. (d == 1 and " livello" or " livelli") .. ": fermete!|r Niente quest e niente mostri finché nun te raggiungono. Professioni, pesca o 'n alt."
  elseif s == "at" then
    return "|cff40ff40Sei ar cap.|r Pe' nun scappà: dungeon co' l'amichi più bassi, professioni, pesca (la tombola ringrazia) o 'n alt. Occhio a l'XP: consegna le quest dopo."
  elseif s == "behind" then
    local left = M.HoursToCap(ns.state.settings, st.week, rec.lv, rec.xp, rec.xpm, st.cap)
    local untilUnlock = st.unlockAt and (st.unlockAt - U.Now()) or 0
    return "Te " .. (d == 1 and "manca 1 livello" or ("mancano " .. d .. " livelli")) .. ": circa " .. U.Hours(left) .. " de gioco ar ritmo der patto" ..
      (untilUnlock > 0 and (", e er prossimo cap se sblocca tra " .. U.Until(untilUnlock)) or "") .. "."
  end
  return ""
end

local function Refresh(v)
  local state = ns.state
  local rec = ns.MyRecord()
  local st = ns.MyStatus()
  local list = UI.Members()
  -- my cap
  local team = st and st.team
  v.team:SetText(team and team.name or "")
  if st and not st.lifted then
    v.capBig:SetText("Cap " .. st.cap)
    v.capState:SetText(st.started and H.StateText(rec and rec.lv, st.cap) or (GREY .. "se parte tra " .. U.Until(state.settings.start - U.Now()) .. "|r"))
    local future = {}
    for _, r in ipairs(st.rows or {}) do if r.cap and r.cap > st.cap and #future < 8 then future[#future + 1] = r.cap end end
    v.bar:Set(H.Position(rec or {}), st.cap, future)
    v.bar:Show()
    v.next:SetText(st.nextCap and st.nextCap > st.cap and ("Prossimo cap |cffffffff" .. st.nextCap .. "|r, " .. U.When(st.unlockAt) .. " (tra " .. U.Until(st.unlockAt - U.Now()) .. ")") or "")
  elseif st and st.lifted then
    v.capBig:SetText("Niente cap")
    v.capState:SetText("|cff40ff40se va ar 60|r")
    v.bar:Hide()
    v.next:SetText("")
  else
    v.capBig:SetText("")
    v.capState:SetText("")
    v.bar:Hide()
    v.next:SetText("")
  end
  v.tip:SetText(CapAdvice(st, rec))

  -- online now: me first, then by level
  local on = {}
  for _, m in ipairs(list) do if H.Online(m) then on[#on + 1] = m end end
  table.sort(on, function(x, y)
    if (x.guid == ns.recordGuid) ~= (y.guid == ns.recordGuid) then return x.guid == ns.recordGuid end
    return (x.lv or 0) > (y.lv or 0)
  end)
  v.onTitle:SetText("Mo' online |cffffffff(" .. #on .. ")|r")
  for i, r in ipairs(v.online) do
    local m = on[i]
    if m then
      local mst = m.team and P.HasSettings(state) and M.Status(state.settings, m.team, U.Now())
      r.name:SetText(Colored(m))
      r.lv:SetText("Liv " .. tostring(m.lv or "?") .. (mst and mst.started and not mst.lifted and (" " .. ShortState(m.lv, mst.cap)) or ""))
      r.zone:SetText(m.zone or "")
    else
      r.name:SetText(i == 1 and (GREY .. "Nessuno, pe' mo'.|r") or "")
      r.lv:SetText("")
      r.zone:SetText("")
    end
  end
  if #on > #v.online then v.online[#v.online].zone:SetText("e artri " .. (#on - #v.online + 1)) end

  -- news
  local news = ns.News and ns.News.List() or {}
  for i, r in ipairs(v.news) do
    local n = news[i]
    if n then
      r.text:SetText(n.t)
      r.when:SetText(U.Ago(U.Now() - (n.at or 0)))
      r.full = n.t
    else
      r.text:SetText(i == 1 and (GREY .. "Ancora gnente. Qui escheno ding, epici, rari, titoli e tombole.|r") or "")
      r.when:SetText("")
      r.full = nil
    end
  end

  -- this week
  local testing = ns.Tombola and ns.Tombola.Testing()
  local wk = (testing and ns.Tombola.Week()) or (P.HasSettings(state) and M.WeekIndex(state.settings, U.Now())) or 0
  local lines = {}
  local function add(label, m, text) if m then lines[#lines + 1] = label .. ": " .. Colored(m) .. " " .. GREY .. text .. "|r" end end
  if wk >= 1 then
    local m, val = Leader(list, function(x) return W(x, wk, "ding") end)
    add("Più livelli", m, "+" .. tostring(val))
    m, val = Leader(list, function(x) return W(x, wk, "q") end)
    add("Più quest", m, tostring(val))
    m, val = Leader(list, function(x) return W(x, wk, "pt") end)
    add("Più ore", m, val and Hours(val) or "")
    m, val = Leader(list, function(x) return W(x, wk, "g") end)
    add("Più sordi", m, val and Gold(val) or "")
    m, val = Leader(list, function(x) return ns.Fun and ns.Fun.LuckOf(x, "w") or 0 end)
    add("Più fortunato", m, m and (W(m, wk, "lb") .. " blu, " .. W(m, wk, "le") .. " epici") or "")
    m, val = Leader(list, function(x) return W(x, wk, "dt") end)
    add("Più morti", m, tostring(val))
  end
  if #lines == 0 then lines[1] = GREY .. (wk >= 1 and "Ancora gnente 'sta settimana." or "Se comincia quanno parte er patto.") .. "|r" end
  for i, l in ipairs(v.week) do l:SetText(lines[i] or "") end
  local TB = ns.Tombola
  local sc = TB and rec and TB.Score(rec)
  v.tomb:SetText(sc and ("Tombola: " .. sc.cells .. "/9 caselle, +" .. sc.points .. (sc.full and " (TOMBOLA!)" or "") .. ".  " .. TB.Money(TB.Balance())) or "")
  v.bullBtn:SetEnabled(wk >= 2 or testing)
end

UI.AddView("casa", "Casa", Build, Refresh, true)

----------------------------------------------------------------------
-- Er Bollettino: last week, told
----------------------------------------------------------------------
local bull
function Home.Bulletin(wk)
  local list = UI.Members()
  local out = {}
  local function line(text) out[#out + 1] = text end
  local m, v = Leader(list, function(x) return W(x, wk, "ding") end)
  if m then line("Er più veloce: " .. Colored(m) .. ", +" .. v .. (v == 1 and " livello" or " livelli")) end
  m, v = Leader(list, function(x) return W(x, wk, "q") end)
  if m then line("Più quest: " .. Colored(m) .. " (" .. v .. ")") end
  m, v = Leader(list, function(x) return W(x, wk, "pt") end)
  if m then line("Chi ha giocato de più: " .. Colored(m) .. " (" .. Hours(v) .. ")") end
  m, v = Leader(list, function(x) return W(x, wk, "g") end)
  if m then line("Chi ha fatto più sordi: " .. Colored(m) .. " (" .. Gold(v) .. ")") end
  m, v = Leader(list, function(x) return W(x, wk, "dg") end)
  if m then line("Er topo de dungeon: " .. Colored(m) .. " (" .. v .. ")") end
  m, v = Leader(list, function(x) return W(x, wk, "lb") + 5 * W(x, wk, "le") end)
  if m then line("Er più fortunato: " .. Colored(m) .. " (" .. W(m, wk, "lb") .. " blu, " .. W(m, wk, "le") .. " epici)") end
  m, v = Leader(list, function(x) return W(x, wk, "dt") end)
  if m then line("Chi è morto de più: " .. Colored(m) .. " (" .. v .. (v == 1 and " vorta" or " vorte") .. ")") end
  m, v = Leader(list, function(x) return W(x, wk, "em") end)
  if m then line("Morte più ridicola: " .. Colored(m) .. " (" .. v .. ")") end
  m, v = Leader(list, function(x) return W(x, wk, "dw") end)
  if m then line("Er bullo: " .. Colored(m) .. " (" .. v .. (v == 1 and " duello vinto" or " duelli vinti") .. ")") end
  if ns.Tombola then
    m, v = Leader(list, function(x) local sc = ns.Tombola.Score(x, wk) return sc and sc.points or 0 end)
    if m then
      local sc = ns.Tombola.Score(m, wk)
      line("Tombola: " .. Colored(m) .. " " .. ns.Tombola.HEX .. ns.Tombola.Piotte(v) .. "|r" .. (sc and sc.full and " (TOMBOLA!)" or ""))
    end
  end
  if #out == 0 then line(GREY .. "Settimana tranquilla: nun s'è mosso nessuno.|r") end
  return out
end

function Home.ShowBulletin(force)
  local state = ns.state
  if not (state and P.HasSettings(state)) then if force then U.Say("ancora nun c'è un bollettino.") end return end
  local wk = M.WeekIndex(state.settings, U.Now()) - 1
  -- test mode: the bulletin of this (test) week, as it stands now
  local testing = force and ns.Tombola and ns.Tombola.Testing()
  if testing then wk = ns.Tombola.Week() end
  if wk < 1 then if force then U.Say("er primo bollettino esce a la fine de la prima settimana (pe' provallo: /patto prova).") end return end
  ns.db.bulletin = type(ns.db.bulletin) == "table" and ns.db.bulletin or {}
  if not force and ns.db.bulletin[state.code] == wk then return end
  if not testing then ns.db.bulletin[state.code] = wk end
  if not bull then
    bull = CreateFrame("Frame", "ErPattoBulletin", UIParent)
    bull:SetSize(460, 330)
    bull:SetPoint("CENTER", 0, 60)
    bull:SetFrameStrata("DIALOG")
    bull:SetToplevel(true)
    bull:EnableMouse(true)
    bull:SetMovable(true)
    bull:RegisterForDrag("LeftButton")
    bull:SetScript("OnDragStart", bull.StartMoving)
    bull:SetScript("OnDragStop", bull.StopMovingOrSizing)
    H.Chrome(bull)
    bull.title = H.Text(bull, "GameFontNormalLarge", "", 420, "CENTER")
    bull.title:SetPoint("TOP", 0, -18)
    bull.lines = {}
    for i = 1, 11 do
      local l = H.Text(bull, "GameFontHighlight", "", 420)
      l:SetPoint("TOPLEFT", 22, -50 - (i - 1) * 21)
      if l.SetWordWrap then l:SetWordWrap(false) end
      bull.lines[i] = l
    end
    bull.foot = H.Text(bull, "GameFontNormalSmall", "", 420, "CENTER")
    bull.foot:SetPoint("BOTTOM", 0, 46)
    bull.ok = H.Btn(bull, "Daje", 110, function() bull:Hide() end)
    bull.ok:SetPoint("BOTTOM", 0, 16)
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoBulletin") end
  end
  bull.title:SetText("Er Bollettino, settimana " .. wk .. (testing and " |cffff8000(prova)|r" or ""))
  local lines = Home.Bulletin(wk)
  for i, l in ipairs(bull.lines) do l:SetText(lines[i] or "") end
  local st = ns.MyStatus()
  bull.foot:SetText(st and not st.lifted and ("Mo' er cap " .. (st.team and ("de " .. st.team.name .. " ") or "") .. "è " .. st.cap .. ".") or "")
  bull:Show()
end

-- the first login after the weekly reset
ns.On("Login", function()
  if not C_Timer then return end
  C_Timer.After(12, function() pcall(Home.ShowBulletin, false) end)
  C_Timer.NewTicker(300, function() pcall(Home.ShowBulletin, false) end)
end)
