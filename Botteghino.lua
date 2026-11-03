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
local function Say(ok, msg, good)
  if not (view and view.status) then return end
  if not ok and msg then view.status:SetText(msg)
  elseif ok and good then view.status:SetText("|cff20ff20" .. good .. "|r")
  else view.status:SetText("") end
end
local function Sound(kit, fallback)
  if not (PlaySound and ns.db and ns.db.opts.toastSound ~= false) then return end
  local id = (SOUNDKIT and SOUNDKIT[kit]) or fallback
  if id then pcall(PlaySound, id) end
end
local HL = "Interface\\Buttons\\UI-Listbox-Highlight2"
local SEL = "Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue"

----------------------------------------------------------------------
-- the closing window: one vanilla dialog per closed week
----------------------------------------------------------------------
local closing
local waiting = {}
local GREEN, RED = "|cff20ff20", "|cffff4040"

local function BuildClosing()
  local f = CreateFrame("Frame", "ErPattoChiusura", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(440, 336)
  f:SetPoint("CENTER", 0, 90)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
  end
  f.title = H.DialogHeader(f, "", 200)
  f.sub = H.Text(f, "GameFontHighlight", "", 390, "CENTER")
  f.sub:SetPoint("TOP", 0, -32)

  local function Head(y, label)
    local l = H.Text(f, "GameFontNormal", label, 250)
    l:SetPoint("TOPLEFT", 26, y)
    local r = H.Text(f, "GameFontHighlight", "", 130, "RIGHT")
    r:SetPoint("TOPRIGHT", -26, y)
    return l, r
  end
  f.tombHead, f.tombMoney = Head(-58, "La Tombola")
  f.tombLine = H.Text(f, "GameFontHighlightSmall", "", 380)
  f.tombLine:SetPoint("TOPLEFT", 26, -78)
  f.schHead, f.schMoney = Head(-102, "La Schedina")
  f.rows = {}
  for i = 1, #TB.QUESTIONS do
    local y = -124 - (i - 1) * 36
    local r = {}
    r.q = H.Text(f, "GameFontNormal", "", 270)
    r.q:SetPoint("TOPLEFT", 26, y)
    r.res = H.Text(f, "GameFontHighlight", "", 110, "RIGHT")
    r.res:SetPoint("TOPRIGHT", -26, y)
    r.detail = H.Text(f, "GameFontHighlightSmall", "", 388)
    r.detail:SetPoint("TOPLEFT", 26, y - 16)
    if r.detail.SetWordWrap then r.detail:SetWordWrap(false) end
    f.rows[i] = r
  end
  f.total = H.Text(f, "GameFontNormal", "", 390, "CENTER")
  f.total:SetPoint("TOP", 0, -240)
  f.balance = H.Text(f, "GameFontHighlight", "", 390, "CENTER")
  f.balance:SetPoint("TOP", 0, -268)
  f.ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.ok:SetSize(120, 22)
  f.ok:SetText("Daje")
  f.ok:SetPoint("BOTTOM", 0, 20)
  f.ok:SetScript("OnClick", function() f:Hide() end)
  local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  x:SetPoint("TOPRIGHT", -4, -4)
  f:SetScript("OnHide", function()
    if #waiting > 0 and C_Timer then C_Timer.After(0.3, function() ns.Botteghino.ShowClosing(table.remove(waiting, 1)) end) end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoChiusura") end
  f:Hide()
  closing = f
end

local function Signed(n) return n > 0 and (GREEN .. "+" .. n .. "|r") or (n < 0 and (RED .. n .. "|r") or "0") end

local function FillClosing(f, res)
  f.title:SetText("Settimana " .. res.wk .. " chiusa" .. (res.test and " (prova)" or ""))
  f.sub:SetText(res.test and "|cffff8000Prova: nun vale|r" or "")
  local sc = res.tomb
  f.tombMoney:SetText(Signed(sc.points) .. " " .. TB.Coin(16))
  f.tombLine:SetText("Caselle |cffffffff" .. (sc.cells or 0) .. "/9|r, terni |cffffffff" .. (sc.lines or 0) .. "|r" ..
    (sc.full and "  |cffffd100TOMBOLA!|r" or ""))
  f.schMoney:SetText(res.played and (Signed(res.won) .. " " .. TB.Coin(16)) or (GREY .. "nun hai giocato|r"))
  for i, r in ipairs(f.rows) do
    local b = res.bets[i]
    r.q:SetText(b and b.text or "")
    if not b then r.res:SetText("") r.detail:SetText("")
    else
      local who = #b.winners > 0 and table.concat(b.winners, ", ") or "nessuno"
      local detail = "Ha vinto: |cffffffff" .. who .. "|r"
      if b.pick then detail = detail .. ".  Tu: |cffffffff" .. b.pick .. "|r, " .. b.stake .. " a " .. TB.Quota(b.quota) end
      r.detail:SetText(detail)
      if not b.pick or b.stake == 0 then r.res:SetText(GREY .. "gnente|r")
      elseif b.nobody then r.res:SetText(GREY .. "ridate " .. b.stake .. "|r")
      elseif b.got > 0 then r.res:SetText(GREEN .. "+" .. b.got .. "|r")
      else r.res:SetText(RED .. "persa|r") end
    end
  end
  f.total:SetText((res.total > 0 and ("|cffffd100+" .. TB.Piotte(res.total) .. "|r") or (GREY .. "Gnente 'sta vorta|r")))
  if res.balance then
    f.balance:SetText((res.test and "C'avresti " or "Mo' c'hai ") .. TB.Money(res.balance))
  else f.balance:SetText("") end
end

ns.Botteghino = ns.Botteghino or {}
function ns.Botteghino.ShowClosing(res)
  if not res then return end
  if not closing then BuildClosing() end
  if closing:IsShown() then waiting[#waiting + 1] = res return end
  -- not in the middle of a fight
  if not res.test and UnitAffectingCombat and UnitAffectingCombat("player") and C_Timer then
    C_Timer.After(5, function() ns.Botteghino.ShowClosing(res) end)
    return
  end
  FillClosing(closing, res)
  closing:Show()
  if ns.db and ns.db.opts.toastSound and PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
    pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_COMPLETE)
  end
end
ns.On("WeekClosed", function(res) ns.Botteghino.ShowClosing(res) end)

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
    v.cells[i] = c
  end
  -- right: how it pays, and how everybody is doing on this card
  local side = H.Box(p, 238, 323)
  side:SetPoint("TOPRIGHT", -8, -14)
  v.paysTitle = H.Text(side, "GameFontNormal", "Quanto paga", 200)
  v.paysTitle:SetPoint("TOPLEFT", 12, -10)
  v.pays = {}
  for i, t in ipairs({ { "Casella", 1 }, { "Terno", 2 }, { "Tombola", 10 } }) do
    local l = H.Text(side, "GameFontHighlightSmall", t[1], 120)
    l:SetPoint("TOPLEFT", 14, -12 - i * 16)
    local r = H.Text(side, "GameFontHighlightSmall", "+" .. t[2] .. " " .. TB.Coin(12), 80, "RIGHT")
    r:SetPoint("TOPRIGHT", -14, -12 - i * 16)
  end
  v.raceTitle = H.Text(side, "GameFontNormal", "A che stanno", 200)
  v.raceTitle:SetPoint("TOPLEFT", 12, -90)
  v.race = {}
  for i = 1, 12 do
    local y = -108 - (i - 1) * 17
    local r = {}
    r.name = H.Text(side, "GameFontHighlightSmall", "", 150)
    r.name:SetPoint("TOPLEFT", 14, y)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.val = H.Text(side, "GameFontHighlightSmall", "", 60, "RIGHT")
    r.val:SetPoint("TOPRIGHT", -14, y)
    v.race[i] = r
  end
  v.testBtn = H.Btn(side, "Prova: chiudi", 100, function()
    local total, _, _, _, _, res = TB.SimulateClose()
    if not total then return end
    ns.Botteghino.ShowClosing(res)
    if ns.News then ns.News.Add("Settimana " .. res.wk .. " chiusa (prova): |cffffffff+" .. TB.Piotte(res.total) .. "|r") end
  end, 20)
  v.testBtn:SetPoint("TOPRIGHT", side, "TOPRIGHT", -8, -6)
end

local function BuildSchedina(v)
  v.sch = CreateFrame("Frame", nil, v)
  v.sch:SetAllPoints()
  v.q = {}
  for i, q in ipairs(TB.QUESTIONS) do
    local box = H.Box(v.sch, 244, 347)
    box:SetPoint("TOPLEFT", (i - 1) * 250, -28)
    local r = { key = q.key, box = box }
    r.title = H.Text(box, "GameFontNormal", q.text, 224, "CENTER")
    r.title:SetPoint("TOP", 0, -10)
    r.status = H.Text(box, "GameFontDisableSmall", "", 224, "CENTER")
    r.status:SetPoint("TOP", 0, -26)
    local hName = H.Text(box, "GameFontDisableSmall", "Chi", 100) hName:SetPoint("TOPLEFT", 14, -44)
    local hSt = H.Text(box, "GameFontDisableSmall", "Puntate", 60, "RIGHT") hSt:SetPoint("TOPRIGHT", box, "TOPLEFT", 172, -44)
    local hQ = H.Text(box, "GameFontDisableSmall", "Quota", 50, "RIGHT") hQ:SetPoint("TOPRIGHT", -14, -44)
    r.rows = {}
    for k = 1, ROWS do
      local b = CreateFrame("Button", nil, box)
      b:SetSize(224, 16)
      b:SetPoint("TOPLEFT", 10, -58 - (k - 1) * 16)
      b:SetHighlightTexture(HL, "ADD")
      b.selTex = b:CreateTexture(nil, "BACKGROUND")
      b.selTex:SetAllPoints()
      b.selTex:SetTexture(SEL)
      b.selTex:SetBlendMode("ADD")
      b.mine = b:CreateTexture(nil, "OVERLAY")
      b.mine:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      b.mine:SetSize(16, 16)
      b.mine:SetPoint("RIGHT", b, "RIGHT", -52, 0)
      b.name = H.Text(b, "GameFontHighlightSmall", "", 110)
      b.name:SetPoint("LEFT", 6, 0)
      if b.name.SetWordWrap then b.name:SetWordWrap(false) end
      b.staked = H.Text(b, "GameFontHighlightSmall", "", 50, "RIGHT")
      b.staked:SetPoint("RIGHT", b, "LEFT", 160, 0)
      b.quota = H.Text(b, "GameFontHighlightSmall", "", 50, "RIGHT")
      b.quota:SetPoint("RIGHT", -4, 0)
      b:SetScript("OnClick", function(self)
        if not self.guid or not TB.CanVote() then return end
        sel[q.key] = self.guid
        Sound("IG_MAINMENU_OPTION_CHECKBOX_ON", 856)
        UI.Refresh()
      end)
      r.rows[k] = b
    end
    -- your bet
    r.mineLine = H.Text(box, "GameFontHighlight", "", 224)
    r.mineLine:SetPoint("TOPLEFT", 12, -260)
    if r.mineLine.SetWordWrap then r.mineLine:SetWordWrap(false) end
    r.winLine = H.Text(box, "GameFontNormal", "", 224)
    r.winLine:SetPoint("TOPLEFT", 12, -278)
    local function Place()
      local guid = sel[q.key]
      local ok, msg = TB.Bet(q.key, guid, r.stake:GetText())
      r.stake:ClearFocus()
      if ok then
        sel[q.key] = nil
        Sound("LOOT_WINDOW_COIN_SOUND", 120)
        r.flash = (GetTime and GetTime() or 0) + 3
      else Say(false, msg) end
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
  local cols = { { "", 30, 14 }, { "Chi", 200, 44 }, { "Piotte", 80, 250 }, { "Tombola", 80, 350 }, { "Schedina", 120, 450 } }
  for _, c in ipairs(cols) do
    local t = H.Text(p, "GameFontDisableSmall", c[1], c[2], c[1] == "Chi" and "LEFT" or "RIGHT")
    t:SetPoint("TOPLEFT", c[3], -12)
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
    r.sch = H.Text(p, "GameFontHighlightSmall", "", 120, "RIGHT") r.sch:SetPoint("TOPLEFT", 450, y)
    r.btn = H.Btn(p, "Sfotti", 70, function(self)
      local ok, msg = TB.Sfotti(self.guid)
      if ok then
        Say(true, nil, "Hai sfottuto " .. tostring(self.who) .. ": \"" .. tostring(msg) .. "\"")
        Sound("LOOT_WINDOW_COIN_SOUND", 120)
      else Say(false, msg) end
    end, 18)
    r.btn:SetPoint("TOPRIGHT", -14, y + 3)
    r.dare = H.Btn(p, "Sfida", 60, function(self) ns.Sfide.Prefill(self.guid) end, 18)
    r.dare:SetPoint("RIGHT", r.btn, "LEFT", -4, 0)
    r.btn:SetScript("OnEnter", function(self) H.Tip(self, { "Sfotti", TB.Piotte(TB.SFOTTO) }) end)
    r.btn:SetScript("OnLeave", H.HideTip)
    v.rich[i] = r
  end
end

local function Build()
  local v = H.NewView("botteghino")
  v.tabTomb = H.TopTab(v, "Tombola", function() page = "tombola" end)
  v.tabTomb:SetPoint("TOPLEFT", 0, 0)
  v.tabSch = H.TopTab(v, "Schedina", function() page = "schedina" end)
  v.tabSch:SetPoint("LEFT", v.tabTomb, "RIGHT", 2, 0)
  v.tabRich = H.TopTab(v, "Li ricchi", function() page = "ricchi" end)
  v.tabRich:SetPoint("LEFT", v.tabSch, "RIGHT", 2, 0)
  v.tabSfide = H.TopTab(v, "Sfide", function() page = "sfide" end)
  v.tabSfide:SetPoint("LEFT", v.tabRich, "RIGHT", 2, 0)
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
  v.status = H.Text(v, "GameFontRedSmall", "", 300, "RIGHT")
  v.status:SetPoint("RIGHT", purse, "LEFT", -10, 0)
  view = v
  BuildTombola(v)
  BuildSchedina(v)
  BuildRicchi(v)
  ns.Sfide.BuildPage(v)
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
local function RefreshTombola(v, wk, me, list, testing)
  local card = TB.Card(wk)
  v.testBtn:SetShown(testing)
  if not card then
    v.cardTitle:SetText("La Tombola")
    local start = ns.state and ns.state.settings and ns.state.settings.start
    v.cardSub:SetText(GREY .. "Parte co' er patto" .. (start and (", " .. U.When(start)) or "") .. "|r")
    for _, c in ipairs(v.cells) do c:Hide() end
  else
    local sc = TB.Score(me, wk) or { done = {}, cells = 0, lines = 0, points = 0 }
    v.cardTitle:SetText("Settimana " .. wk .. (testing and " |cffff8000(prova)|r" or ""))
    v.cardSub:SetText(sc.cells .. "/9, terni " .. sc.lines .. ":  " .. GOLD .. "+" .. TB.Piotte(sc.points) .. "|r" .. (sc.full and "  " .. GOLD .. "TOMBOLA!|r" or ""))
    local w = TB.Weekly(me, wk)
    for i, c in ipairs(v.cells) do
      local sq = card[i]
      local done, cur, target = TB.Progress(sq, w)
      c.text:SetText(sq.t)
      c.prog:SetText(done and "|cff20ff20Fatto|r" or TB.ProgressText(sq, cur, target))
      c.check:SetShown(done)
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
  for _, r in ipairs(v.q) do
    local status
    if testing then status = "|cffff8000prova|r"
    elseif not (wk and wk >= 1) then status = "se apre co' er patto"
    elseif can then status = "chiude " .. U.When(closes)
    else status = "chiusa, se paga a fine settimana" end
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
    if #order > ROWS then
      for _, g in ipairs({ placed, picked }) do
        local at
        for k, m in ipairs(order) do if m.guid == g then at = k end end
        if at and at > ROWS then local m = table.remove(order, at) table.insert(order, ROWS, m) end
      end
    end
    for k, b in ipairs(r.rows) do
      local m = order[k]
      if m then
        local o = odds[m.guid]
        b.guid = m.guid
        b.name:SetText(H.Colored(m))
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
    local open = (can and picked) and true or false
    if r.stake.SetEnabled then r.stake:SetEnabled(open) end
    r.place:SetEnabled(open)
    r.place:SetText(placed and "Cambia" or "Punta")
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
      local bets = TB.VotesOf(m, wk)
      local n = 0
      for _, q in ipairs(TB.QUESTIONS) do if bets and bets[q.key] and (bets["s" .. q.key] or 0) > 0 then n = n + 1 end end
      r.pos:SetText(pos .. "º")
      r.name:SetText(H.Colored(m) .. ((m.guid == ns.recordGuid) and (" " .. GOLD .. "(tu)|r") or ""))
      r.money:SetText(TB.TotalOf(m) .. " " .. TB.Coin(12))
      r.tomb:SetText(sc and (sc.cells .. "/9") or (GREY .. "-|r"))
      r.sch:SetText(n > 0 and (n .. "/3 giocate") or (GREY .. "-|r"))
      r.btn.guid, r.btn.who = m.guid, Short(m)
      r.btn:SetShown(m.guid ~= ns.recordGuid and not m.fake)
      r.dare.guid = m.guid
      r.dare:SetShown(m.guid ~= ns.recordGuid and not m.fake)
    else
      r.pos:SetText("") r.name:SetText("") r.money:SetText("") r.tomb:SetText("") r.sch:SetText("") r.btn:Hide() r.dare:Hide()
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
  v.tomb:SetShown(page == "tombola")
  v.sch:SetShown(page == "schedina")
  v.ricchi:SetShown(page == "ricchi")
  v.sfide:SetShown(page == "sfide")
  if page == "tombola" then RefreshTombola(v, wk, me, list, testing)
  elseif page == "schedina" then RefreshSchedina(v, wk, me, list, testing, byGuid)
  elseif page == "sfide" then ns.Sfide.RefreshPage(v)
  else RefreshRicchi(v, wk, list) end
end

UI.AddView("botteghino", "Botteghino", Build, Refresh, false)

-- open the Botteghino on a page ("tombola", "schedina", "ricchi", "sfide")
function ns.Botteghino.Show(which)
  page = which or page
  UI.Show("botteghino")
end
