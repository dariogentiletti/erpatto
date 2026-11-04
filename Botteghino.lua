-- Er Patto: the "Botteghino" tab, the betting shop of the patto (logic in Tombola.lua). Three pages:
--   Tombola    this week's card, and how far everybody is on it
--   Schedina   three questions side by side: every member with the piotte on them and the odds; click one, write
--              the stake, Punta. Your bet stays marked with what it pays
--   Li ricchi  everybody's piotte, with the button to send a sfottò
-- Top right: your piotte. And the window that closes a week (a vanilla dialog box) instead of lines in the chat.
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H
local TB = ns.Tombola

local GREY = "|cff9d9d9d"
local GOLD = "|cffffd100"
local page = "tombola"
local sel = {} -- the member clicked in each question, before Punta
local function Short(m) return (tostring(m and m.name or "?"):match("^(%S+)")) or "?" end
-- errors and confirmations in the page, under the purse, never in the chat
local view
local sayToken
local function Say(ok, msg, good)
  if not (view and view.status) then return end
  if not ok then view.status:SetText(msg or "Nun se pò fà.")
  elseif good then view.status:SetText("|cff20ff20" .. good .. "|r")
  else view.status:SetText("") end
  -- it stays a while, then goes
  local token = {}
  sayToken = token
  if C_Timer then C_Timer.After(8, function() if sayToken == token and view.status then view.status:SetText("") end end) end
  -- right next to the piotte, never over the tabs
  local w = view.purse and view.purse.GetStringWidth and view.purse:GetStringWidth() or 60
  view.status:ClearAllPoints()
  view.status:SetPoint("RIGHT", view.coin, "LEFT", -(tonumber(w) or 60) - 18, 0)
end
local function Sound(kit, fallback)
  if not (PlaySound and ns.db and ns.db.opts.toastSound ~= false) then return end
  local id = (SOUNDKIT and SOUNDKIT[kit]) or fallback
  if id then pcall(PlaySound, id) end
end
local HL = "Interface\\Buttons\\UI-Listbox-Highlight2"
local SEL = "Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue"

local GREEN, RED = "|cff20ff20", "|cffff4040"
ns.Botteghino = ns.Botteghino or {}
ns.Botteghino.Say = Say
-- the week closed: no window of its own any more, Er Bollettino tells it (with "La settimana tua")

----------------------------------------------------------------------
-- build
----------------------------------------------------------------------
local ROWS = 12
local function BuildTombola(v)
  local p = H.Box(v, 744, 347)
  p:SetPoint("TOPLEFT", 0, -28)
  v.tomb = p
  v.cardTitle = H.Text(p, "GameFontNormal", "", 300)
  v.cardTitle:SetPoint("TOPLEFT", 12, -12)
  v.cardSub = H.Text(p, "GameFontHighlight", "", 300, "RIGHT")
  v.cardSub:SetPoint("TOPRIGHT", p, "TOPLEFT", 484, -12)
  v.cells = {}
  for i = 1, 9 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local c = H.Box(p, 154, 92)
    c:SetPoint("TOPLEFT", 10 + col * 158, -34 - row * 96)
    c.text = H.Text(c, "GameFontNormal", "", 130, "CENTER")
    c.text:SetPoint("TOP", 0, -18)
    c.prog = H.Text(c, "GameFontHighlightSmall", "", 130, "CENTER")
    c.prog:SetPoint("BOTTOM", 0, 16)
    c.check = c:CreateTexture(nil, "OVERLAY")
    c.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    c.check:SetSize(24, 24)
    c.check:SetPoint("TOPRIGHT", -1, -1)
    -- the capo can swap a square that can't be done (two clicks: the second confirms)
    c.swap = H.Btn(c, "Cambia", 56, function(self)
      local now = GetTime and GetTime() or 0
      if not (self.armed and now - self.armed < 4) then
        self.armed = now
        self:SetText("Sicuro?")
        if C_Timer then C_Timer.After(4, function() self.armed = nil self:SetText("Cambia") end) end
        return
      end
      self.armed = nil
      self:SetText("Cambia")
      local ok, old, new = TB.Swap(i)
      if ok then Say(true, nil, "Casella cambiata: " .. new.t .. ".") else Say(false, old) end
    end, 16)
    c.swap:SetPoint("BOTTOM", 0, 8)
    v.cells[i] = c
  end
  -- under the card: how it pays, in one line
  v.pays = H.Text(p, "GameFontDisableSmall", "Casella = +1, terno = +2, tombola = +10", 470)
  v.pays:SetPoint("BOTTOMLEFT", 14, 8)
  -- right: how everybody is doing on this card
  local side = H.Box(p, 238, 323)
  side:SetPoint("TOPRIGHT", -8, -14)
  v.raceTitle = H.Text(side, "GameFontNormal", "A che stanno", 200)
  v.raceTitle:SetPoint("TOPLEFT", 12, -10)
  v.race = {}
  for i = 1, 16 do
    local y = -30 - (i - 1) * 17
    local r = {}
    r.name = H.Text(side, "GameFontHighlightSmall", "", 150)
    r.name:SetPoint("TOPLEFT", 14, y)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.val = H.Text(side, "GameFontHighlightSmall", "", 60, "RIGHT")
    r.val:SetPoint("TOPRIGHT", -14, y)
    v.race[i] = r
  end
end

local SCH_ROWS = 30 -- everyone in the list, with a scroll past what fits
local function BuildSchedina(v)
  v.sch = CreateFrame("Frame", nil, v)
  v.sch:SetAllPoints()
  -- the week of the schedina, as a bar: green while you can play, grey while the week is played, the end is when
  -- it's paid. A notch where it closes, the spark where we are now, the days under it.
  local tl = H.Box(v.sch, 744, 54)
  tl:SetPoint("TOPLEFT", 0, -28)
  v.tlOpen = tl:CreateTexture(nil, "ARTWORK")
  v.tlOpen:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  v.tlOpen:SetVertexColor(0.1, 0.6, 0.1)
  v.tlOpen:SetHeight(9)
  v.tlShut = tl:CreateTexture(nil, "ARTWORK")
  v.tlShut:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
  v.tlShut:SetVertexColor(0.4, 0.4, 0.4)
  v.tlShut:SetHeight(9)
  v.tlNow = tl:CreateTexture(nil, "OVERLAY")
  v.tlNow:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  v.tlNow:SetBlendMode("ADD")
  v.tlNow:SetSize(20, 28)
  v.tlA = H.Text(tl, "GameFontHighlightSmall", "", 360)
  v.tlA:SetPoint("TOPLEFT", 14, -10)
  v.tlC = H.Text(tl, "GameFontHighlightSmall", "", 300, "RIGHT")
  v.tlC:SetPoint("TOPRIGHT", -14, -10)
  v.tlDays = {}
  for d = 1, 7 do
    local t = H.Text(tl, "GameFontDisableSmall", "", 90, "CENTER")
    v.tlDays[d] = t
  end
  v.tlBox = tl
  v.q = {}
  for i, q in ipairs(TB.QUESTIONS) do
    local box = H.Box(v.sch, 244, 291)
    box:SetPoint("TOPLEFT", (i - 1) * 250, -84)
    local r = { key = q.key, box = box, i = i }
    r.title = H.Text(box, "GameFontNormal", "", 224, "CENTER")
    r.title:SetPoint("TOP", 0, -10)
    -- the capo can change a question nobody played yet (two clicks: the second confirms)
    r.swap = H.Btn(box, "Cambia", 56, function(self)
      local now = GetTime and GetTime() or 0
      if not (self.armed and now - self.armed < 4) then
        self.armed = now
        self:SetText("Sicuro?")
        if C_Timer then C_Timer.After(4, function() self.armed = nil self:SetText("Cambia") end) end
        return
      end
      self.armed = nil
      self:SetText("Cambia")
      local ok, x = TB.SwapQuestion(q.key)
      r.err:SetText(ok and ("|cff20ff20Domanda cambiata: " .. x.text .. "|r") or (x or "Nun se pò."))
      UI.Refresh()
    end, 16)
    r.swap:SetPoint("TOPRIGHT", -8, -24)
    r.status = H.Text(box, "GameFontDisableSmall", "", 224, "CENTER")
    r.status:SetPoint("TOP", 0, -26)
    local hName = H.Text(box, "GameFontDisableSmall", "Chi", 100) hName:SetPoint("TOPLEFT", 14, -44)
    local hSt = H.Text(box, "GameFontDisableSmall", "Piotte", 60, "RIGHT") hSt:SetPoint("TOPRIGHT", box, "TOPLEFT", 172, -44)
    local hHit = CreateFrame("Frame", nil, box) hHit:SetSize(60, 14) hHit:SetPoint("TOPRIGHT", box, "TOPLEFT", 172, -42) hHit:EnableMouse(true)
    hHit:SetScript("OnEnter", function(self) H.Tip(self, { "Piotte", "Quante piotte ha puntato er patto su de lui (in tutto, de tutti)." }) end)
    hHit:SetScript("OnLeave", H.HideTip)
    -- the list scrolls when the patto is big
    local scroll = CreateFrame("ScrollFrame", "ErPattoSchedina" .. i, box, "UIPanelScrollFrameTemplate")
    if H.VanillaScroll then H.VanillaScroll(scroll) end
    scroll:SetPoint("TOPLEFT", 8, -56)
    scroll:SetPoint("TOPRIGHT", -28, -56)
    scroll:SetHeight(146)
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(208, 10)
    scroll:SetScrollChild(body)
    r.scroll, r.body = scroll, body
    local hQ = H.Text(box, "GameFontDisableSmall", "Quota", 50, "RIGHT") hQ:SetPoint("TOPRIGHT", -14, -44)
    r.rows = {}
    for k = 1, SCH_ROWS do
      local b = CreateFrame("Button", nil, body)
      b:SetSize(208, 16)
      b:SetPoint("TOPLEFT", 2, -(k - 1) * 16)
      b:SetHighlightTexture(HL, "ADD")
      b.selTex = b:CreateTexture(nil, "BACKGROUND")
      b.selTex:SetAllPoints()
      b.selTex:SetTexture(SEL)
      b.selTex:SetBlendMode("ADD")
      b.mine = b:CreateTexture(nil, "OVERLAY")
      b.mine:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      b.mine:SetSize(16, 16)
      b.mine:SetPoint("RIGHT", b, "RIGHT", -46, 0)
      b.name = H.Text(b, "GameFontHighlightSmall", "", 100)
      b.name:SetPoint("LEFT", 6, 0)
      if b.name.SetWordWrap then b.name:SetWordWrap(false) end
      b.staked = H.Text(b, "GameFontHighlightSmall", "", 50, "RIGHT")
      b.staked:SetPoint("RIGHT", b, "LEFT", 150, 0)
      b.quota = H.Text(b, "GameFontHighlightSmall", "", 50, "RIGHT")
      b.quota:SetPoint("RIGHT", -4, 0)
      b:SetScript("OnClick", function(self)
        if not self.guid or not TB.CanVote() then return end
        if TB.Mine(self.guid) then r.err:SetText("Su te stesso (o su 'n alt tuo) nun se gioca.") return end
        sel[q.key] = self.guid
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
        UI.Refresh()
      end)
      r.rows[k] = b
    end
    -- your bet
    r.mineLine = H.Text(box, "GameFontHighlight", "", 224)
    r.mineLine:SetPoint("TOPLEFT", 12, -210)
    if r.mineLine.SetWordWrap then r.mineLine:SetWordWrap(false) end
    r.winLine = H.Text(box, "GameFontNormal", "", 224)
    r.winLine:SetPoint("TOPLEFT", 12, -228)
    -- what the last click did, right where you clicked
    r.err = H.Text(box, "GameFontRedSmall", "", 224)
    r.err:SetPoint("TOPLEFT", 12, -246)
    if r.err.SetWordWrap then r.err:SetWordWrap(false) end
    local function Place()
      local guid = sel[q.key]
      local ok, msg = TB.Bet(q.key, guid, r.stake:GetText())
      r.stake:ClearFocus()
      if ok then
        sel[q.key] = nil
        Sound("LOOT_WINDOW_COIN_SOUND", 120)
        r.flash = (GetTime and GetTime() or 0) + 3
        r.err:SetText("|cff20ff20Giocata! Mo' nun se cambia più.|r")
      else r.err:SetText(msg or "Nun se pò fà.") end
      local token = {}
      r.errToken = token
      if C_Timer then C_Timer.After(8, function() if r.errToken == token then r.err:SetText("") end end) end
      UI.Refresh()
    end
    r.stakeLabel = H.Text(box, "GameFontNormalSmall", "Posta", 40)
    r.stakeLabel:SetPoint("BOTTOMLEFT", 14, 20)
    r.stake = H.Input(box, 50, 5, Place)
    if r.stake.SetNumeric then r.stake:SetNumeric(true) end
    r.stake:SetPoint("BOTTOMLEFT", 58, 16)
    r.stake:SetScript("OnTextChanged", function() if r.preview then r.preview() end end)
    r.place = H.Btn(box, "Punta", 90, Place, 22)
    r.place:SetPoint("BOTTOMRIGHT", -12, 14)
    v.q[i] = r
  end
end

local function BuildRicchi(v)
  local p = H.Box(v, 744, 347)
  p:SetPoint("TOPLEFT", 0, -28)
  v.ricchi = p
  local cols = { { "", 30, 14 }, { "Chi", 200, 44 }, { "Piotte", 80, 250 }, { "Tombola", 80, 350 }, { "Schedine", 70, 440 }, { "Resa", 60, 520 } }
  for _, c in ipairs(cols) do
    local t = H.Text(p, "GameFontDisableSmall", c[1], c[2], c[1] == "Chi" and "LEFT" or "RIGHT")
    t:SetPoint("TOPLEFT", c[3], -12)
    if c[1] == "Resa" or c[1] == "Schedine" then
      local hit = CreateFrame("Frame", nil, p)
      hit:SetSize(c[2], 14) hit:SetPoint("TOPLEFT", c[3], -10) hit:EnableMouse(true)
      hit:SetScript("OnEnter", function(self)
        if c[1] == "Resa" then
          H.Tip(self, { "Resa de le schedine", "Quanto t'hanno reso: (vinto - giocato) / giocato. Vince de più chi azzecca dove nessuno punta: 'na quota arta vale tanto, la vittoria scontata poco." })
        else H.Tip(self, { "Schedine", "Domande azzeccate su quelle giocate." }) end
      end)
      hit:SetScript("OnLeave", H.HideTip)
    end
  end
  v.rich = {}
  for i = 1, 16 do
    local y = -30 - (i - 1) * 19
    local r = {}
    r.pos = H.Text(p, "GameFontHighlightSmall", "", 30, "RIGHT") r.pos:SetPoint("TOPLEFT", 14, y)
    r.name = H.Text(p, "GameFontHighlightSmall", "", 200) r.name:SetPoint("TOPLEFT", 44, y)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.money = H.Text(p, "GameFontHighlightSmall", "", 80, "RIGHT") r.money:SetPoint("TOPLEFT", 250, y)
    r.tomb = H.Text(p, "GameFontHighlightSmall", "", 80, "RIGHT") r.tomb:SetPoint("TOPLEFT", 350, y)
    r.sch = H.Text(p, "GameFontHighlightSmall", "", 70, "RIGHT") r.sch:SetPoint("TOPLEFT", 440, y)
    r.roi = H.Text(p, "GameFontHighlightSmall", "", 60, "RIGHT") r.roi:SetPoint("TOPLEFT", 520, y)
    r.dare = H.Btn(p, "Sfida", 60, function(self) ns.Sfide.Prefill(self.guid) end, 18)
    r.dare:SetPoint("TOPRIGHT", -14, y + 3)
    v.rich[i] = r
  end
end

-- Li scontrini: every piotta in and out of a member (me by default), newest first
local CONTI_ROWS = 15
local contiOf -- the guid shown (nil: me)
local function BuildConti(v)
  local p = H.Box(v, 744, 347)
  p:SetPoint("TOPLEFT", 0, -28)
  v.conti = p
  local l = H.Text(p, "GameFontNormalSmall", "De chi", 50) l:SetPoint("TOPLEFT", 14, -16)
  v.contiWho = H.Dropdown(p, 170, function(self)
    local items = { { ns.recordGuid, "Tu" } }
    local list = {}
    for _, m in ipairs(UI.Members()) do if m.guid ~= ns.recordGuid then list[#list + 1] = m end end
    table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
    for _, m in ipairs(list) do items[#items + 1] = { m.guid, H.Colored(m, true) } end
    ns.Sfide.Choose(self, items, function(g) contiOf = (g ~= ns.recordGuid) and g or nil end)
  end)
  v.contiWho:SetPoint("TOPLEFT", 64, -10)
  v.contiSum = H.Text(p, "GameFontHighlight", "", 420, "RIGHT")
  v.contiSum:SetPoint("TOPRIGHT", -16, -16)
  local cols = { { "Quanno", 14, 90, "LEFT" }, { "Che", 110, 360, "LEFT" }, { "Messe", 480, 70, "RIGHT" }, { "Prese", 560, 80, "RIGHT" }, { "Netto", 650, 80, "RIGHT" } }
  for _, c in ipairs(cols) do
    local t = H.Text(p, "GameFontDisableSmall", c[1], c[3], c[4]) t:SetPoint("TOPLEFT", c[2], -46)
  end
  v.contiRows = {}
  for i = 1, CONTI_ROWS do
    local y = -62 - (i - 1) * 17
    local r = {}
    for k, c in ipairs(cols) do
      local t = H.Text(p, "GameFontHighlightSmall", "", c[3], c[4]) t:SetPoint("TOPLEFT", c[2], y)
      if t.SetWordWrap then t:SetWordWrap(false) end
      r[k] = t
    end
    v.contiRows[i] = r
  end
  v.contiMore = H.Text(p, "GameFontDisableSmall", "", 500) v.contiMore:SetPoint("BOTTOMLEFT", 14, 12)
end

local function RefreshConti(v, list, byGuid)
  local m = contiOf and byGuid[contiOf]
  if contiOf and not m then contiOf = nil end
  v.contiWho:SetText(m and tostring(m.name):match("^(%S+)") or "Tu")
  local lines = TB.LedgerOf(m or ns.MyRecord())
  local put, took = 0, 0
  for _, x in ipairs(lines) do put = put + (x.s or 0) took = took + (x.g or 0) end
  v.contiSum:SetText("Messe " .. put .. "   Prese " .. took .. "   " .. (m and "C'ha " or "Mo' c'hai ") .. TB.Money(m and TB.TotalOf(m) or TB.Balance()))
  for i, r in ipairs(v.contiRows) do
    local x = lines[i]
    if x then
      r[1]:SetText(x.k == "gp" and "" or U.Day(x.at or 0))
      r[2]:SetText(TB.LedgerText(x))
      r[3]:SetText((x.s and x.s > 0) and tostring(x.s) or (GREY .. "-|r"))
      r[4]:SetText(x.g == nil and (GREY .. "in ballo|r") or tostring(x.g))
      local net = (x.g or 0) - (x.s or 0)
      r[5]:SetText(x.g == nil and (GREY .. "-|r") or (net > 0 and (GREEN .. "+" .. net .. "|r") or (net < 0 and (RED .. net .. "|r") or (GREY .. "0|r"))))
    else
      for _, t in ipairs(r) do t:SetText("") end
    end
  end
  v.contiMore:SetText(#lines > CONTI_ROWS and (GREY .. "E antre " .. (#lines - CONTI_ROWS) .. " righe più vecchie.|r") or
    (m and #lines == 0 and (GREY .. "Ancora gnente: le righe arriveno co' l'urtima versione de l'addon.|r") or ""))
end

local function Build()
  local v = H.NewView("botteghino")
  v.tabTomb = H.TopTab(v, "Tombola", function() page = "tombola" end)
  v.tabTomb:SetPoint("TOPLEFT", 0, 0)
  v.tabSch = H.TopTab(v, "Schedina", function() page = "schedina" end)
  v.tabSch:SetPoint("LEFT", v.tabTomb, "RIGHT", 2, 0)
  v.tabSfide = H.TopTab(v, "Sfide", function() page = "sfide" end)
  v.tabSfide:SetPoint("LEFT", v.tabSch, "RIGHT", 2, 0)
  v.tabConti = H.TopTab(v, "Scontrini", function() page = "conti" end)
  v.tabConti:SetPoint("LEFT", v.tabSfide, "RIGHT", 2, 0)
  v.tabRich = H.TopTab(v, "Li ricchi", function() page = "ricchi" end)
  v.tabRich:SetPoint("LEFT", v.tabConti, "RIGHT", 2, 0)
  -- my piotte, top right
  local purse = CreateFrame("Frame", nil, v)
  purse:SetSize(200, 24)
  purse:SetPoint("TOPRIGHT", -4, 0)
  v.coin = purse:CreateTexture(nil, "ARTWORK")
  v.coin:SetTexture(TB.ICON)
  v.coin:SetSize(20, 20)
  v.coin:SetPoint("RIGHT", 0, 0)
  v.purse = H.Text(purse, "GameFontHighlight", "", 170, "RIGHT")
  v.purse:SetPoint("RIGHT", v.coin, "LEFT", -6, 0)
  v.status = H.Text(v, "GameFontRedSmall", "", 290, "RIGHT")
  if v.status.SetWordWrap then v.status:SetWordWrap(false) end
  v.status:SetPoint("RIGHT", purse, "LEFT", -10, 0)
  view = v
  BuildTombola(v)
  BuildSchedina(v)
  BuildRicchi(v)
  ns.Sfide.BuildPage(v)
  BuildConti(v)
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
local function RefreshTombola(v, wk, me, list, testing)
  local card = TB.Card(wk)
  if not card then
    v.cardTitle:SetText("La Tombola")
    local start = ns.state and ns.state.settings and ns.state.settings.start
    v.cardSub:SetText(GREY .. "Parte co' er patto" .. (start and (", " .. U.When(start)) or "") .. "|r")
    for _, c in ipairs(v.cells) do c:Hide() end
  else
    local sc = TB.Score(me, wk) or { done = {}, cells = 0, lines = 0, points = 0 }
    v.cardTitle:SetText("Settimana " .. wk .. (testing and " |cffff8000(prova)|r" or ""))
    v.cardSub:SetText((sc.full and (GOLD .. "TOMBOLA!|r  ") or "") .. GOLD .. "+" .. TB.Piotte(sc.points) .. "|r")
    local w = TB.Weekly(me, wk)
    for i, c in ipairs(v.cells) do
      local sq = card[i]
      local done, cur, target = TB.Progress(sq, w)
      c.text:SetText(sq.t)
      c.prog:SetText(done and "|cff20ff20Fatto|r" or TB.ProgressText(sq, cur, target))
      c.check:SetShown(done)
      local swap = TB.CanSwap() and true or false
      c.swap:SetShown(swap)
      c.prog:ClearAllPoints()
      c.prog:SetPoint("BOTTOM", 0, swap and 28 or 16)
      c:Show()
    end
  end
  -- everybody on the card
  local order = {}
  for _, m in ipairs(list) do
    local sc = card and TB.Score(m, wk)
    order[#order + 1] = { m = m, cells = sc and sc.cells or 0, pts = sc and sc.points or 0 }
  end
  table.sort(order, function(a, b) if a.pts ~= b.pts then return a.pts > b.pts end return tostring(a.m.name) < tostring(b.m.name) end)
  for i, r in ipairs(v.race) do
    local o = order[i]
    if o and card then
      r.name:SetText(H.Colored(o.m) .. (o.m.guid == ns.recordGuid and (" " .. GOLD .. "(tu)|r") or ""))
      r.val:SetText(o.cells .. "/9")
    else r.name:SetText("") r.val:SetText("") end
  end
end

local function RefreshSchedina(v, wk, me, list, testing, byGuid)
  local can = TB.CanVote()
  local mine = TB.VotesOf(me, wk) or {}
  local closes = wk and wk >= 1 and not testing and TB.Closes(wk)
  local qs = TB.Questions(wk)
  -- the timeline: green while open, grey while it's played, the spark where we are, the days under it
  if wk and wk >= 1 and ns.state and P.HasSettings(ns.state) then
    local start = TB.WeekStart(wk)
    local close, pay = TB.Closes(wk), start + M.WEEK
    local W = 716
    local function X(t) return math.floor(W * math.max(0, math.min(1, (t - start) / (pay - start))) + 0.5) end
    local cx, nx = X(close), X(U.Now())
    v.tlOpen:ClearAllPoints() v.tlOpen:SetPoint("TOPLEFT", v.tlBox, "TOPLEFT", 14, -26) v.tlOpen:SetWidth(math.max(1, cx))
    v.tlShut:ClearAllPoints() v.tlShut:SetPoint("TOPLEFT", v.tlBox, "TOPLEFT", 14 + cx, -26) v.tlShut:SetWidth(math.max(1, W - cx))
    v.tlNow:ClearAllPoints() v.tlNow:SetPoint("CENTER", v.tlBox, "TOPLEFT", 14 + nx, -30)
    local open = U.Now() < close
    v.tlA:SetText(open and ("|cff20ff20Se pò puntà:|r fino a " .. U.When(close - 60)) or (GREY .. "Giocate chiuse: mo' se gioca la settimana|r"))
    v.tlC:SetText("|cffffd100Se paga|r " .. U.When(pay))
    -- the days: today in white, the rest grey
    local today = math.floor((U.Now() - start) / 86400) + 1
    for d, t in ipairs(v.tlDays) do
      local at = start + (d - 1) * 86400
      local p = U.RomeParts(at)
      local name = ({ "dom", "lun", "mar", "mer", "gio", "ven", "sab" })[(p.wday or 0) + 1]
      t:ClearAllPoints()
      t:SetPoint("TOP", v.tlBox, "TOPLEFT", 14 + math.floor(W * (d - 0.5) / 7), -38)
      t:SetText((d == today and "|cffffffff" or "") .. name .. (d == today and " (oggi)|r" or ""))
    end
  end
  for _, r in ipairs(v.q) do
    r.title:SetText(qs[r.i] and qs[r.i].text or "")
    r.swap:SetShown(ns.CanAdmin and ns.CanAdmin() and can and true or false)
    local status
    -- the dates are in the timeline above
    if testing then status = "|cffff8000prova|r"
    elseif can then status = ""
    else status = GREY .. "chiusa|r" end
    r.status:SetText(status)
    local odds = TB.Odds(wk or 0, list, r.key)
    local placed = mine[r.key] and (mine["s" .. r.key] or 0) > 0 and mine[r.key] or nil
    local picked = sel[r.key] or placed
    -- favourites first; my pick and the clicked one always in the list
    local order = {}
    for _, m in ipairs(list) do order[#order + 1] = m end
    table.sort(order, function(a, b)
      local x, y = odds[a.guid].q, odds[b.guid].q
      if x ~= y then return x < y end
      return tostring(a.name) < tostring(b.name)
    end)
    r.body:SetHeight(math.max(10, math.min(#order, SCH_ROWS) * 16))
    if UI.FitScroll then UI.FitScroll(r.scroll, math.min(#order, SCH_ROWS) * 16, 146) end
    for k, b in ipairs(r.rows) do
      local m = order[k]
      if m then
        local o = odds[m.guid]
        b.guid = m.guid
        b.name:SetText(H.Colored(m) .. (TB.Mine(m.guid) and (GREY .. " (tu)|r") or ""))
        b.staked:SetText(o.staked > 0 and (o.staked .. "") or (GREY .. "-|r"))
        b.quota:SetText(GOLD .. TB.Quota(o.q) .. "|r")
        b.selTex:SetShown(m.guid == picked)
        b.mine:SetShown(m.guid == placed)
        b:SetEnabled(can and true or false)
        b:Show()
      else
        b.guid = nil
        b:Hide()
      end
    end
    -- what I played, and what it pays
    local stake = mine["s" .. r.key] or 0
    local flash = r.flash and GetTime and GetTime() < r.flash
    if placed then
      local x10 = mine["q" .. r.key] or (odds[placed] and odds[placed].q) or 10
      r.mineLine:SetText((flash and "|cff20ff20Giocata!|r  " or "") .. stake .. " su " .. Short(byGuid[placed]) .. " a " .. TB.Quota(x10))
      r.winLine:SetText("Si vince: " .. GOLD .. TB.Piotte(math.floor(stake * x10 / 10)) .. "|r")
    else
      r.mineLine:SetText(GREY .. "Nun hai giocato|r")
      r.winLine:SetText("")
    end
    -- the clicked one, not played yet: what the stake would pay
    r.preview = function()
      local g = sel[r.key]
      if not g then return end
      local n = tonumber(r.stake:GetText()) or 0
      local q = odds[g] and odds[g].q or 10
      r.mineLine:SetText("Su " .. Short(byGuid[g]) .. " a " .. TB.Quota(q))
      r.winLine:SetText(n > 0 and ("Si vince: " .. GOLD .. TB.Piotte(math.floor(n * q / 10)) .. "|r") or (GREY .. "Scrivi la posta|r"))
    end
    if sel[r.key] then r.preview() end
    if not r.stake:HasFocus() then r.stake:SetText(stake > 0 and tostring(stake) or "") end
    -- open while the schedina is: Punta without a name says what's missing
    local open = can and true or false
    if r.stake.SetEnabled then r.stake:SetEnabled(open) end
    r.place:SetEnabled(open)
    r.place:SetText(placed and "Giocata" or "Punta")
    if placed and r.stake.SetEnabled then r.stake:SetEnabled(false) end
  end
end

local function RefreshRicchi(v, wk, list)
  local order = {}
  for _, m in ipairs(list) do order[#order + 1] = m end
  table.sort(order, function(a, b)
    local x, y = TB.TotalOf(a), TB.TotalOf(b)
    if x ~= y then return x > y end
    return tostring(a.name) < tostring(b.name)
  end)
  local myPos
  for i, m in ipairs(order) do if m.guid == ns.recordGuid then myPos = i end end
  for i, r in ipairs(v.rich) do
    local m = order[i]
    if i == #v.rich and myPos and myPos > #v.rich then m = order[myPos] end
    if m then
      local pos = (m.guid == ns.recordGuid and myPos) or i
      local sc = TB.Card(wk) and TB.Score(m, wk)
      local won, played, roi = TB.SchedineOf(m)
      r.pos:SetText(pos .. "º")
      r.name:SetText(H.Colored(m) .. ((m.guid == ns.recordGuid) and (" " .. GOLD .. "(tu)|r") or ""))
      r.money:SetText(TB.TotalOf(m) .. " " .. TB.Coin(12))
      r.tomb:SetText(sc and (sc.cells .. "/9") or (GREY .. "-|r"))
      r.sch:SetText(played > 0 and (won .. "/" .. played) or (GREY .. "-|r"))
      r.roi:SetText(roi and ((roi > 0 and "|cff20ff20+" or roi < 0 and "|cffff4040" or GREY) .. roi .. "%|r") or (GREY .. "-|r"))
      r.dare.guid = m.guid
      r.dare:SetShown(m.guid ~= ns.recordGuid and not m.fake)
    else
      r.pos:SetText("") r.name:SetText("") r.money:SetText("") r.tomb:SetText("") r.sch:SetText("") r.roi:SetText("") r.dare:Hide()
    end
  end
end

local function Refresh(v)
  local wk = TB.Week()
  local me = ns.MyRecord()
  local list = UI.Members()
  local testing = TB.Testing()
  local byGuid = {}
  for _, m in ipairs(list) do byGuid[m.guid] = m end
  v.purse:SetText(TB.Piotte(TB.Balance()))
  v.tabTomb:SetSelected(page == "tombola")
  v.tabSch:SetSelected(page == "schedina")
  v.tabRich:SetSelected(page == "ricchi")
  v.tabSfide:SetSelected(page == "sfide")
  v.tabConti:SetSelected(page == "conti")
  v.conti:SetShown(page == "conti")
  v.tomb:SetShown(page == "tombola")
  v.sch:SetShown(page == "schedina")
  v.ricchi:SetShown(page == "ricchi")
  v.sfide:SetShown(page == "sfide")
  if page == "tombola" then RefreshTombola(v, wk, me, list, testing)
  elseif page == "schedina" then RefreshSchedina(v, wk, me, list, testing, byGuid)
  elseif page == "sfide" then ns.Sfide.RefreshPage(v)
  elseif page == "conti" then RefreshConti(v, list, byGuid)
  else RefreshRicchi(v, wk, list) end
end

UI.AddView("botteghino", "Botteghino", Build, Refresh, false)

-- open the Botteghino on a page ("tombola", "schedina", "ricchi", "sfide")
function ns.Botteghino.Show(which)
  page = which or page
  UI.Show("botteghino")
end
