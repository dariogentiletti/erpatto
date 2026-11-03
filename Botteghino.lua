-- Er Patto: the "Botteghino" tab, the betting shop of the patto (logic in Tombola.lua).
--   left: la Tombola de la settimana (the card, who draws it, how it pays)
--   right: la Schedina (three bets with a pick and a stake, the pot and the top three picks with their payout)
--          and the richest (with a button to send a sfottò)
--   top right: your sesterzi
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H
local TB = ns.Tombola

local GREY = "|cff9d9d9d"
local COIN = "Interface\\Icons\\INV_Misc_Coin_01"
local function Short(m) return (tostring(m and m.name or "?"):match("^(%S+)")) or "?" end
local function Decimal(x) return (string.format("%.1f", x):gsub("%.", ",")) end

----------------------------------------------------------------------
-- choose a member: a small vanilla list under the button
----------------------------------------------------------------------
local pick
local function PickMember(anchor, onPick)
  if not pick then
    pick = CreateFrame("Frame", "ErPattoPickMember", UIParent)
    pick:SetFrameStrata("DIALOG")
    pick:SetToplevel(true)
    pick:EnableMouse(true)
    H.Chrome(pick)
    pick.title = H.Text(pick, "GameFontNormalSmall", "Su chi giochi?", 180)
    pick.title:SetPoint("TOPLEFT", 14, -12)
    pick.rows = {}
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoPickMember") end
    pick:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    pick:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    pick:SetScript("OnEvent", function(self)
      local over = MouseIsOver and (MouseIsOver(self) or (self.anchor and MouseIsOver(self.anchor)))
      if not over then self:Hide() end
    end)
  end
  pick.anchor = anchor
  local list = {}
  for _, m in ipairs(UI.Members()) do list[#list + 1] = m end
  table.sort(list, function(a, b) return (a.lv or 0) > (b.lv or 0) or ((a.lv or 0) == (b.lv or 0) and tostring(a.name) < tostring(b.name)) end)
  for _, r in ipairs(pick.rows) do r:Hide() end
  local shown = math.min(20, #list)
  for i = 1, shown do
    local m = list[i]
    local r = pick.rows[i]
    if not r then
      r = CreateFrame("Button", nil, pick)
      r:SetSize(176, 16)
      r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      r.text = H.Text(r, "GameFontHighlightSmall", "", 130)
      r.text:SetPoint("LEFT", 4, 0)
      r.lv = H.Text(r, "GameFontHighlightSmall", "", 40, "RIGHT")
      r.lv:SetPoint("RIGHT", -2, 0)
      r:SetScript("OnClick", function(self) pick:Hide() if pick.onPick then pick.onPick(self.guid) end UI.Refresh() end)
      pick.rows[i] = r
    end
    r.guid = m.guid
    r.text:SetText(H.Colored(m))
    r.lv:SetText(tostring(m.lv or "?"))
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 12, -28 - (i - 1) * 16)
    r:Show()
  end
  pick.onPick = onPick
  pick:SetSize(204, 40 + shown * 16)
  pick:ClearAllPoints()
  pick:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  pick:Show()
end

local function Say(ok, msg) if msg then U.Say(ok and msg or ("|cffff4040" .. msg .. "|r")) end end

----------------------------------------------------------------------
-- build
----------------------------------------------------------------------
local function Build()
  local v = H.NewView("botteghino")
  -- header: the name, and my sesterzi
  v.head = H.Text(v, "GameFontNormalLarge", "Er Botteghino", 300)
  v.head:SetPoint("TOPLEFT", 4, -2)
  v.headSub = H.Text(v, "GameFontHighlightSmall", "Tombola, Schedina e sfottò: se gioca a sesterzi.", 360)
  v.headSub:SetPoint("LEFT", v.head, "LEFT", 150, -2)
  local purse = CreateFrame("Frame", nil, v)
  purse:SetSize(200, 24)
  purse:SetPoint("TOPRIGHT", -4, 0)
  purse:EnableMouse(true)
  v.coin = purse:CreateTexture(nil, "ARTWORK")
  v.coin:SetTexture(COIN)
  v.coin:SetSize(20, 20)
  v.coin:SetPoint("RIGHT", 0, 0)
  v.purse = H.Text(purse, "GameFontHighlightLarge", "", 170, "RIGHT")
  v.purse:SetPoint("RIGHT", v.coin, "LEFT", -6, 0)
  purse:SetScript("OnEnter", function(self)
    H.Tip(self, { "Sesterzi", "Se parte co' " .. TB.START .. ". Se vinceno co' la Tombola (1 a casella, +2 a riga, +10 tutta) e co' la Schedina (er montepremi se lo dividono chi indovina).",
      "Se spenneno pe' giocà a la Schedina e pe' sfotte l'amichi (" .. TB.SFOTTO .. " l'uno). Chi ce n'ha de più è A Strozzino." })
  end)
  purse:SetScript("OnLeave", H.HideTip)

  -- la Tombola
  local card = H.Box(v, 372, 347)
  card:SetPoint("TOPLEFT", 0, -28)
  v.cardTitle = H.Text(card, "GameFontNormal", "", 240)
  v.cardTitle:SetPoint("TOPLEFT", 12, -10)
  v.cardSub = H.Text(card, "GameFontHighlightSmall", "", 350)
  v.cardSub:SetPoint("TOPLEFT", 12, -26)
  v.cells = {}
  for i = 1, 9 do
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local c = H.Box(card, 116, 82)
    c:SetPoint("TOPLEFT", 9 + col * 119, -44 - row * 86)
    c.glow = c:CreateTexture(nil, "ARTWORK")
    c.glow:SetPoint("TOPLEFT", 4, -4)
    c.glow:SetPoint("BOTTOMRIGHT", -4, 4)
    c.glow:SetColorTexture(1, 0.82, 0, 0.18)
    c.text = H.Text(c, "GameFontHighlightSmall", "", 100, "CENTER")
    c.text:SetPoint("TOP", 0, -10)
    c.prog = H.Text(c, "GameFontNormalSmall", "", 100, "CENTER")
    c.prog:SetPoint("BOTTOM", 0, 10)
    c.check = c:CreateTexture(nil, "OVERLAY")
    c.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    c.check:SetSize(20, 20)
    c.check:SetPoint("TOPRIGHT", -3, -3)
    v.cells[i] = c
  end
  v.legend = H.Text(card, "GameFontDisableSmall", "", 350)
  v.legend:SetPoint("TOPLEFT", 12, -306)
  v.legend:SetText("1 sesterzio a casella, +2 a riga, +10 tutta la cartella.\nLa cartella la tira er sacchetto: è uguale pe' tutti e cambia ogni settimana.")
  v.testBtn = H.Btn(card, "Prova: chiudi", 110, function()
    local total, sc, right, lines, won = TB.SimulateClose()
    if not total then return end
    U.Say("prova, settimana chiusa: tombola " .. sc.points .. ", Schedina " .. right .. "/3 (" .. won .. " sesterzi), totale " .. total .. ".")
    for _, l in ipairs(lines) do U.Say("  " .. l) end
    if ns.News then ns.News.Banner("Settimana chiusa (prova)", total .. " sesterzi: tombola " .. sc.points .. ", Schedina " .. won, nil, "evento") end
  end, 20)
  v.testBtn:SetPoint("TOPRIGHT", -8, -6)

  -- la Schedina
  local sch = H.Box(v, 364, 222)
  sch:SetPoint("TOPLEFT", 380, -28)
  v.schTitle = H.Text(sch, "GameFontNormal", "La Schedina", 200)
  v.schTitle:SetPoint("TOPLEFT", 12, -10)
  v.schSub = H.Text(sch, "GameFontHighlightSmall", "", 340)
  v.schSub:SetPoint("TOPLEFT", 12, -26)
  if v.schSub.SetWordWrap then v.schSub:SetWordWrap(false) end
  v.q = {}
  for i, q in ipairs(TB.QUESTIONS) do
    local y = -44 - (i - 1) * 58
    local r = {}
    r.text = H.Text(sch, "GameFontHighlight", q.text, 340)
    r.text:SetPoint("TOPLEFT", 12, y)
    r.pick = H.Btn(sch, "Scegli chi", 116, function(self)
      PickMember(self, function(guid) Say(TB.Bet(q.key, guid)) end)
    end, 20)
    r.pick:SetPoint("TOPLEFT", 12, y - 15)
    r.stakeLabel = H.Text(sch, "GameFontNormalSmall", "Posta:", 50)
    r.stakeLabel:SetPoint("TOPLEFT", 140, y - 19)
    r.stakes = {}
    for k, n in ipairs(TB.STAKES) do
      local b = H.Btn(sch, tostring(n), 30, function() Say(TB.Bet(q.key, nil, n)) end, 20)
      b:SetPoint("TOPLEFT", 184 + (k - 1) * 32, y - 15)
      b.n = n
      r.stakes[k] = b
    end
    r.info = H.Text(sch, "GameFontDisableSmall", "", 340)
    r.info:SetPoint("TOPLEFT", 12, y - 38)
    if r.info.SetWordWrap then r.info:SetWordWrap(false) end
    v.q[i] = r
  end

  -- the richest
  local rich = H.Box(v, 364, 121)
  rich:SetPoint("TOPLEFT", 380, -254)
  v.richTitle = H.Text(rich, "GameFontNormal", "Li più ricchi", 200)
  v.richTitle:SetPoint("TOPLEFT", 12, -10)
  v.rich = {}
  for i = 1, 5 do
    local y = -28 - (i - 1) * 17
    local r = {}
    r.name = H.Text(rich, "GameFontHighlightSmall", "", 180)
    r.name:SetPoint("TOPLEFT", 12, y)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.money = H.Text(rich, "GameFontHighlightSmall", "", 70, "RIGHT")
    r.money:SetPoint("TOPRIGHT", rich, "TOPLEFT", 270, y)
    r.btn = H.Btn(rich, "Sfotti", 64, function(self)
      local ok, msg = TB.Sfotti(self.guid)
      if ok then U.Say("hai sfottuto " .. tostring(self.who) .. ": \"" .. tostring(msg) .. "\" (-" .. TB.SFOTTO .. " sesterzi)") else Say(false, msg) end
    end, 16)
    r.btn:SetPoint("TOPRIGHT", -8, y + 2)
    r.btn:SetScript("OnEnter", function(self) H.Tip(self, { "Sfotti", "Je compare 'na scritta sullo schermo co' 'no sfottò. Costa " .. TB.SFOTTO .. " sesterzi." }) end)
    r.btn:SetScript("OnLeave", H.HideTip)
    v.rich[i] = r
  end
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
local function Refresh(v)
  local wk = TB.Week()
  local me = ns.MyRecord()
  local list = UI.Members()
  local testing = TB.Testing()
  local byGuid = {}
  for _, m in ipairs(list) do byGuid[m.guid] = m end
  v.purse:SetText("|cffffd100" .. TB.Balance() .. "|r sesterzi")

  -- the card
  local card = TB.Card(wk)
  v.testBtn:SetShown(testing)
  if not card then
    v.cardTitle:SetText("La Tombola")
    local start = ns.state and ns.state.settings and ns.state.settings.start
    v.cardSub:SetText(GREY .. "La prima cartella esce quanno parte er patto" .. (start and (" (" .. U.When(start) .. ")") or "") .. ". Pe' provalla: /patto prova.|r")
    for _, c in ipairs(v.cells) do c:Hide() end
  else
    local sc = TB.Score(me, wk) or { done = {}, cells = 0, lines = 0, points = 0 }
    v.cardTitle:SetText("La Tombola, settimana " .. wk .. (testing and " |cffff8000(prova)|r" or ""))
    v.cardSub:SetText("Caselle |cffffffff" .. sc.cells .. "/9|r, terni |cffffffff" .. sc.lines .. "|r: |cffffd100+" .. sc.points .. " sesterzi|r" ..
      (sc.full and "  |cffffd100TOMBOLA!|r" or ""))
    local w = TB.Weekly(me, wk)
    for i, c in ipairs(v.cells) do
      local sq = card[i]
      local done, cur, target = TB.Progress(sq, w)
      c.text:SetText(sq.t)
      c.prog:SetText(done and "|cff20ff20Fatto|r" or TB.ProgressText(sq, cur, target))
      c.check:SetShown(done)
      c.glow:SetShown(done)
      c:Show()
    end
  end

  -- la Schedina
  local can = TB.CanVote()
  if testing then
    v.schSub:SetText("|cffff8000Prova: giocate solo su 'sto computer, sempre aperte.|r")
  elseif wk and wk >= 1 then
    v.schSub:SetText(can and ("Aperta fino a " .. U.When(TB.Closes(wk)) .. ". Scegli chi e quanto ce metti.")
      or (GREY .. "Chiusa: se paga a fine settimana. Se riapre lunedì pe' du' giorni.|r"))
  else
    v.schSub:SetText(GREY .. "Se apre co' la prima settimana der patto.|r")
  end
  local mine = TB.VotesOf(me, wk) or {}
  for i, q in ipairs(TB.QUESTIONS) do
    local r = v.q[i]
    local g = mine[q.key]
    r.pick:SetText(g and byGuid[g] and Short(byGuid[g]) or "Scegli chi")
    r.pick:SetEnabled(can and true or false)
    local myStake = g and (mine["s" .. q.key] or 0) or 0
    for _, b in ipairs(r.stakes) do
      b:SetEnabled((can and g) and true or false)
      if b.n == myStake then b:LockHighlight() else b:UnlockHighlight() end
    end
    r.stakeLabel:SetText(myStake > 0 and ("Posta: |cffffffff" .. myStake .. "|r") or "Posta:")
    local pot, top = TB.Market(wk or 0, list, q.key)
    local parts = {}
    for k = 1, math.min(3, #top) do
      local t = top[k]
      parts[#parts + 1] = Short(byGuid[t.guid]) .. " " .. t.n .. (t.pays > 0 and (" (paga " .. Decimal(t.pays) .. ")") or "")
    end
    r.info:SetText(pot > 0 and ("Montepremi " .. pot .. ": " .. table.concat(parts, ", ")) or "Ancora nessuna giocata")
  end

  -- the richest
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
    -- the last row shows me if I'm not in the top
    if i == #v.rich and myPos and myPos > #v.rich then m = order[myPos] end
    if m then
      local pos = (m.guid == ns.recordGuid and myPos) or i
      r.name:SetText(pos .. "º  " .. H.Colored(m) .. ((m.guid == ns.recordGuid) and " |cffffd100(tu)|r" or ""))
      r.money:SetText("|cffffd100" .. TB.TotalOf(m) .. "|r")
      r.btn.guid, r.btn.who = m.guid, Short(m)
      r.btn:SetShown(m.guid ~= ns.recordGuid and not m.fake)
    else
      r.name:SetText("") r.money:SetText("") r.btn:Hide()
    end
  end
end

UI.AddView("botteghino", "Botteghino", Build, Refresh, false)
