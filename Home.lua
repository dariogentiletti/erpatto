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
local function Short(m) return U.Short(m and m.name) end
local function Colored(m) return "|c" .. H.ClassHex(m.cls) .. Short(m) .. "|r" end
local function Gold(c) return ns.Money and ns.Money(c or 0, true) or string.format("%d oro", math.floor((c or 0) / 10000)) end
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
  v.capBig = H.Text(a, "GameFontNormalLarge", "", 120)
  v.capBig:SetPoint("TOPLEFT", 14, -32)
  v.capState = H.Text(a, "GameFontHighlight", "", 220)
  v.capState:SetPoint("TOPLEFT", 130, -36)
  v.bar = H.CapBar(a, 344, 18)
  v.bar:SetPoint("TOPLEFT", 12, -66)
  v.next = H.Text(a, "GameFontHighlightSmall", "", 344)
  v.next:SetPoint("TOPLEFT", 14, -90)
  v.tip = H.Text(a, "GameFontNormalSmall", "", 344)
  v.tip:SetPoint("TOPLEFT", 14, -106)
  v.tip:SetHeight(44)
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

  -- the caciare of my squadra still to come: when, how long to go, and if I'm in (a click opens it)
  local k = H.Box(v, 368, 104)
  k:SetPoint("TOPLEFT", 0, -184)
  v.cacTitle = Title(k, "Caciare")
  v.cacNew = H.Btn(k, "Nova", 60, function() if ns.Lunario then ns.Lunario.OpenNew() end end, 18)
  v.cacNew:SetPoint("TOPRIGHT", -10, -7)
  v.cac = {}
  for i = 1, 4 do
    local r = CreateFrame("Button", nil, k)
    r:SetSize(346, 16)
    r:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 17)
    r:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(14, 14)
    r.icon:SetPoint("LEFT", 2, 0)
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.text = H.Text(r, "GameFontHighlightSmall", "", 210)
    r.text:SetPoint("LEFT", 20, 0)
    if r.text.SetWordWrap then r.text:SetWordWrap(false) end
    r.right = H.Text(r, "GameFontHighlightSmall", "", 120, "RIGHT")
    r.right:SetPoint("RIGHT", -2, 0)
    if r.right.SetWordWrap then r.right:SetWordWrap(false) end
    r:SetScript("OnClick", function(self) if ns.Lunario then ns.Lunario.Show(self.id) end end)
    v.cac[i] = r
  end

  -- news
  local c = H.Box(v, 368, 156)
  c:SetPoint("TOPLEFT", 0, -296)
  v.newsTitle = Title(c, "Notizie")
  v.news = {}
  for i = 1, 7 do
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
  local d = H.Box(v, 368, 268)
  d:SetPoint("TOPLEFT", 376, -184)
  v.weekTitle = Title(d, "'Sta settimana")
  v.week = {}
  for i = 1, 9 do
    local l = H.Text(d, "GameFontHighlightSmall", "", 344)
    l:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 17)
    if l.SetWordWrap then l:SetWordWrap(false) end
    v.week[i] = l
  end
  -- my piotte of the week: from the tombola, and from all the rest (schedina, sfide, taje, gufate...)
  v.tomb = H.Text(d, "GameFontHighlightSmall", "", 344)
  v.tomb:SetPoint("TOPLEFT", 12, -191)
  -- the piotte for the hours played in a group with the patto: they're not winnings, so apart from er resto
  v.paga = H.Text(d, "GameFontHighlightSmall", "", 170, "RIGHT")
  v.paga:SetPoint("TOPRIGHT", -12, -191)
  v.rest = H.Text(d, "GameFontHighlightSmall", "", 344)
  v.rest:SetPoint("TOPLEFT", 12, -206)
  -- (no Botteghino button: it's the tab right under)
  v.bullBtn = H.Btn(d, "Bollettino", 84, function() Home.ShowBulletin(true) end, 20)
  v.bullBtn:SetPoint("BOTTOMLEFT", 12, 10)
  v.shareBtn = H.Btn(d, "Condividi", 84, function() if ns.Extras then ns.Extras.ShowShare() end end, 20)
  v.shareBtn:SetPoint("LEFT", v.bullBtn, "RIGHT", 6, 0)
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
  -- the caciare to come (a short count, to fit the column: "1g 20h", "23h 29m", "12 min")
  local function Left(sec)
    local m = math.max(0, math.floor(sec / 60))
    local d, h, mm = math.floor(m / 1440), math.floor((m % 1440) / 60), m % 60
    if d > 0 then return d .. "g" .. (h > 0 and (" " .. h .. "h") or "") end
    if h > 0 then return h .. "h" .. (mm > 0 and (" " .. mm .. "m") or "") end
    return mm .. " min"
  end
  local L = ns.Lunario
  local up = L and L.Upcoming() or {}
  local open = 0
  local now = U.Now()
  for _, e in ipairs(up) do local _, _, mine = L.Answers(e) if mine == nil and L.State(e, now) == "prossimo" then open = open + 1 end end
  v.cacTitle:SetText("Caciare" .. (open > 0 and (" |cffff8000(" .. open .. (open == 1 and " nova" or " nove") .. ")|r") or ""))
  for i, r in ipairs(v.cac) do
    local e = up[i]
    if e then
      local yes, _, mine = L.Answers(e)
      local live = L.State(e, now) == "incorso"
      r.id = e.id
      r.icon:SetTexture((L.KINDS[e.k] or L.KINDS.al).icon)
      r.icon:Show()
      r.text:SetText(GREY .. L.DayWord(e.t, now) .. " " .. U.HM(e.t) .. "|r " .. (mine == 1 and "|cffffd100" or "|cffffffff") .. e.n .. "|r " .. GREY .. "(" .. #yes .. ")|r")
      local right
      if live then right = (mine == 1 or mine == 2) and "|cff20ff20mo'! vai|r" or "|cff20ff20mo'|r"
      elseif mine == 1 then right = "|cff20ff20tra " .. Left(e.t - now) .. "|r"
      elseif mine == 2 then right = "|cffffd100forse, tra " .. Left(e.t - now) .. "|r"
      elseif mine == nil then right = "|cffff8000nova: ce stai?|r"
      else right = GREY .. "nun ce vai|r" end
      r.right:SetText(right)
      r:Show()
    else
      r.id = nil
      r.icon:Hide()
      r.text:SetText(i == 1 and (GREY .. "Gnente in programma.|r") or "")
      r.right:SetText("")
      r:SetShown(i == 1)
    end
  end

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
      r.text:SetText(i == 1 and (GREY .. "Ancora gnente.|r") or "")
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
    m, val = Leader(list, function(x) return W(x, wk, "rk") end)
    add("Più rari", m, tostring(val))
    m, val = Leader(list, function(x) return W(x, wk, "dg") end)
    add("Più dungeon", m, tostring(val))
    m, val = Leader(list, function(x) return W(x, wk, "hw") end)
    add("Più ammazzati pe' strada", m, tostring(val))
  end
  if #lines == 0 then lines[1] = GREY .. (wk >= 1 and "Ancora gnente 'sta settimana." or "Se comincia quanno parte er patto.") .. "|r" end
  for i, l in ipairs(v.week) do l:SetText(lines[i] or "") end
  local TB = ns.Tombola
  local sc = TB and rec and TB.Score(rec)
  local GOLDC = "|cffffd100"
  if sc then
    v.tomb:SetText(GOLDC .. "Tombola:|r " .. sc.cells .. "/9 caselle" .. (sc.full and " |cff20ff20TOMBOLA!|r" or "") .. "  |cff20ff20+" .. sc.points .. "|r " .. TB.Coin(12))
    -- the rest of the week, from li scontrini (an open bet counts what it took)
    local from = TB.WeekStart(math.max(1, wk))
    local net = 0
    for _, x in ipairs(TB.Ledger()) do
      if x.k ~= "st" and x.k ~= "tp" and x.k ~= "tb" and x.k ~= "gp" and (x.at or 0) >= from then net = net + (x.g or 0) - (x.s or 0) end
    end
    -- a piotta every hour in a group with the patto: those of this week
    local gt = rec.stats and rec.stats.t and rec.stats.t.gp or 0
    local hourS = TB.GROUP_HOUR or 3600
    local paga = math.floor(gt / hourS) - math.floor(math.max(0, gt - W(rec, wk, "gp")) / hourS)
    v.paga:SetText(GOLDC .. "Paghetta pe' fa' gruppo:|r " .. (paga > 0 and ("|cff20ff20+" .. paga) or (GREY .. "0")) .. "|r " .. TB.Coin(12))
    v.rest:SetText(GOLDC .. "Er resto:|r schedina, sfide, taje, gufate  " .. (net > 0 and "|cff20ff20+" or net < 0 and "|cffff4040" or GREY) .. net .. "|r " .. TB.Coin(12))
  else
    v.tomb:SetText("") v.rest:SetText("") v.paga:SetText("")
  end
  v.bullBtn:SetEnabled(wk >= 2 or testing)
end

UI.AddView("casa", "Baretto", Build, Refresh, true)

-- Er Bollettino lives in Bollettino.lua
