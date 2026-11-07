-- Er Patto: the "Personaggio" tab, built like the vanilla (1.12) Character frame: same art, same 384x512 geometry,
-- same slot, model, stat box and tab positions. The stats are the adventure (level against the cap, quests,
-- dungeons, gold, duels inside the patto, BGs) and the resistance column shows your rank in the patto.
-- A side panel lists the members: click one to see their character pane from their point of view.
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H

local mode = "t"     -- "t" since always, "w" this week
local shownRec, shownList -- the pane on screen, for the item tooltips
local viewGuid       -- whose pane is shown; nil = mine
local page = 1
local PER_PAGE = 19

local ART = "Interface\\PaperDollInfoFrame\\"
local GREEN, RED, WHITE = "|cff20ff20", "|cffff2020", "|cffffffff"

----------------------------------------------------------------------
-- equipment slots (PaperDollFrame.xml, 1.12.1)
----------------------------------------------------------------------
local LEFT = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot", "TabardSlot", "WristSlot" }
local RIGHT = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local BOTTOM = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }
local FALLBACK = {
  HeadSlot = { 1, "Head" }, NeckSlot = { 2, "Neck" }, ShoulderSlot = { 3, "Shoulder" }, ShirtSlot = { 4, "Shirt" },
  ChestSlot = { 5, "Chest" }, WaistSlot = { 6, "Waist" }, LegsSlot = { 7, "Legs" }, FeetSlot = { 8, "Feet" },
  WristSlot = { 9, "Wrists" }, HandsSlot = { 10, "Hands" }, Finger0Slot = { 11, "Finger" }, Finger1Slot = { 12, "Finger" },
  Trinket0Slot = { 13, "Trinket" }, Trinket1Slot = { 14, "Trinket" }, BackSlot = { 15, "Chest" },
  MainHandSlot = { 16, "MainHand" }, SecondaryHandSlot = { 17, "SecondaryHand" }, TabardSlot = { 19, "Tabard" },
}
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 } }

-- slot id and empty-slot art; nil when this client has no such slot (ranged and ammo on modern clients)
local function SlotInfo(name)
  if GetInventorySlotInfo then
    local ok, id, tex = pcall(GetInventorySlotInfo, name)
    if ok and type(id) == "number" then
      local fb = FALLBACK[name]
      return id, tex or (fb and ("Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. fb[2]))
    end
    if name == "RangedSlot" or name == "AmmoSlot" then return nil end
  end
  local fb = FALLBACK[name]
  if not fb then return nil end
  return fb[1], "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. fb[2]
end

local function QualityColor(q)
  local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c and c.r then return c.r, c.g, c.b end
  local f = QUALITY[q] or QUALITY[1]
  return f[1], f[2], f[3]
end

local function ItemIcon(id)
  if C_Item and C_Item.GetItemIconByID then
    local ok, icon = pcall(C_Item.GetItemIconByID, id)
    if ok and icon then return icon end
  end
  if GetItemIcon then
    local ok, icon = pcall(GetItemIcon, id)
    if ok and icon then return icon end
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ItemString(it)
  return string.format("item:%d:%d:0:0:0:0:%d", it.id, it.ench or 0, it.suffix or 0)
end

----------------------------------------------------------------------
-- whose pane, and how they stand in the patto
----------------------------------------------------------------------
local function Viewed(list)
  local guid = viewGuid or ns.recordGuid
  for _, m in ipairs(list) do if m.guid == guid then return m end end
  viewGuid = nil
  for _, m in ipairs(list) do if m.guid == ns.recordGuid then return m end end
  return nil
end

-- the live character is used only for my own pane on my main; alts and other members come from their records
local function IsLive(rec)
  return rec and rec.guid == ns.recordGuid and not ns.alt
end

-- a unit token for this member if the game can show them right now (group, raid, target)
local function UnitFor(guid)
  if not (UnitGUID and guid) then return nil end
  local units = { "target", "focus", "mouseover" }
  for i = 1, 4 do units[#units + 1] = "party" .. i end
  for i = 1, 40 do units[#units + 1] = "raid" .. i end
  for _, u in ipairs(units) do
    local g = UnitGUID(u)
    if g and not U.IsSecret(g) and g == guid then
      local vis = not UnitIsVisible or UnitIsVisible(u)
      if not U.IsSecret(vis) and vis then return u end
    end
  end
  return nil
end

local function Standing(list, rec, value)
  local mine = rec and value(rec) or 0
  local better, n, sum, best, bestRec = 0, 0, 0, 0, nil
  for _, m in ipairs(list) do
    local v = value(m) or 0
    n = n + 1
    sum = sum + v
    if v > best then best, bestRec = v, m end
    if v > mine then better = better + 1 end
  end
  return { mine = mine, rank = better + 1, n = n, sum = sum, avg = n > 0 and sum / n or 0, best = best, bestRec = bestRec }
end

local function NameIndex(list)
  local idx = {}
  for _, m in ipairs(list) do
    if type(m.name) == "string" then
      idx[m.name] = m
      local short = m.name:match("^(%S+)")
      if short and not idx[short] then idx[short] = m end
    end
  end
  return idx
end

-- duels against other patto members only, from the member's own head-to-head record
local function PattoDuels(rec, idx)
  local w, l, rival, rivalN, rivalRec = 0, 0, nil, 0, nil
  for name, h in pairs(rec and rec.h2h or {}) do
    local other = idx[name]
    if other and other.guid ~= rec.guid and type(h) == "table" then
      w = w + (h.w or 0)
      l = l + (h.l or 0)
      local n = (h.w or 0) + (h.l or 0)
      if n > rivalN then rival, rivalN, rivalRec = other, n, h end
    end
  end
  return w, l, rival, rivalRec
end

local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

local function Money(copper, short)
  copper = math.floor(copper or 0)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  if g > 0 then return U.Thousands(g) .. GOLD .. (short and "" or (" " .. s .. SILVER)) end
  if s > 0 then return s .. SILVER .. (short and "" or (" " .. c .. COPPER)) end
  return c .. COPPER
end
ns.Money = Money

local function Pct(x) return math.floor(x * 100 + 0.5) .. "%" end


-- vanilla colours a stat green when it's above normal and red when below: here "normal" is the patto average
local function ColorVs(text, mine, avg)
  if avg <= 0 or math.abs(mine / avg - 1) < 0.05 then return WHITE .. text .. "|r" end
  return (mine > avg and GREEN or RED) .. text .. "|r"
end

-- game names stay as the game writes them (English client): races, classes, professions, zones, quests
local RACES = { Human = "Human", Orc = "Orc", Dwarf = "Dwarf", NightElf = "Night Elf", Scourge = "Undead",
  Tauren = "Tauren", Gnome = "Gnome", Troll = "Troll" }

local CLASSES = { WARRIOR = "Warrior", MAGE = "Mage", PRIEST = "Priest", ROGUE = "Rogue", HUNTER = "Hunter",
  WARLOCK = "Warlock", DRUID = "Druid", PALADIN = "Paladin", SHAMAN = "Shaman" }

local function RaceName(rec)
  return RACES[rec.race or ""] or rec.race or ""
end

local function ClassName(rec)
  return CLASSES[rec.cls or ""] or (rec.cls and (rec.cls:sub(1, 1) .. rec.cls:sub(2):lower())) or ""
end

-- item level of one slot for a member (live for me, from the shared gear for the others)
local function SlotLevel(m, slot)
  if IsLive(m) then
    local link = GetInventoryItemLink and GetInventoryItemLink("player", slot)
    return T.LinkLevel(U.Plain(link, "string"))
  end
  local it = T.ParseEquipment(m.eq)[slot]
  return it and it.il and it.il > 0 and it.il or nil
end

-- under the item: the same slot of the other members, five lines around the one you're looking at
local function AddSlotCompare(slot, slotName)
  if not (GameTooltip and shownRec and shownList) then return end
  local rows = {}
  for _, m in ipairs(shownList) do
    local il = SlotLevel(m, slot)
    if il then rows[#rows + 1] = { m = m, il = il } end
  end
  if #rows < 2 then return end
  table.sort(rows, function(a, b)
    if a.il ~= b.il then return a.il > b.il end
    return tostring(a.m.name) < tostring(b.m.name)
  end)
  local at
  for i, r in ipairs(rows) do if r.m.guid == shownRec.guid then at = i end end
  local first = math.max(1, (at or 1) - 2)
  local last = math.min(#rows, first + 4)
  first = math.max(1, last - 4)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Livello de l'oggetto ner patto (" .. (_G[string.upper(slotName)] or slotName) .. ")", 1, 0.82, 0)
  for i = first, last do
    local r = rows[i]
    local me = r.m.guid == shownRec.guid
    local c = me and 1 or 0.75
    GameTooltip:AddDoubleLine(i .. ". " .. H.Colored(r.m) .. (me and " <" or ""), tostring(r.il), c, c, c, me and 1 or 0.75, me and 0.82 or 0.75, me and 0 or 0.75)
  end
  if not at then GameTooltip:AddLine("Slot vòto", 0.6, 0.6, 0.6) end
end

----------------------------------------------------------------------
-- pieces of the frame
----------------------------------------------------------------------
local function SlotButton(parent, name, v)
  local id, empty = SlotInfo(name)
  if not id then return nil end
  -- ItemButtonTemplate (1.12): 37x37, UI-Quickslot2 64x64 at (0,-1), Depress when pushed, square highlight
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(37, 37)
  b.id, b.empty, b.slotName = id, empty, name
  b.icon = b:CreateTexture(nil, "BORDER")
  b.icon:SetAllPoints()
  local nt = b:CreateTexture(nil, "ARTWORK")
  nt:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  nt:SetSize(64, 64)
  nt:SetPoint("CENTER", 0, -1)
  b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.glow:SetBlendMode("ADD")
  b.glow:SetSize(68, 68)
  b.glow:SetPoint("CENTER")
  b.glow:Hide()
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = false
    if self.live then
      local ok, has = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", self.id)
      shown = ok and has
    elseif self.item then
      shown = pcall(GameTooltip.SetHyperlink, GameTooltip, ItemString(self.item))
    end
    if not shown then GameTooltip:SetText(_G[string.upper(self.slotName)] or self.slotName, 1, 1, 1) end
    AddSlotCompare(self.id, self.slotName)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", H.HideTip)
  b:SetScript("OnClick", function(self)
    if not (IsModifiedClick and IsModifiedClick("CHATLINK") and HandleModifiedItemClick) then return end
    local link
    if self.live then link = GetInventoryItemLink and GetInventoryItemLink("player", self.id)
    elseif self.item and GetItemInfo then local _; _, link = GetItemInfo(ItemString(self.item)) end
    if link then pcall(HandleModifiedItemClick, link) end
  end)
  function b:Show_(tex, q)
    self.icon:SetTexture(tex or self.empty)
    if tex and q and q >= 2 then
      self.glow:SetVertexColor(QualityColor(q))
      self.glow:Show()
    else
      self.glow:Hide()
    end
  end
  function b:SetLive()
    self.live, self.item = true, nil
    local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", self.id)
    if U.IsSecret(tex) then tex = nil end
    local q = tex and GetInventoryItemQuality and U.Plain(GetInventoryItemQuality("player", self.id), "number")
    self:Show_(tex, q)
    return tex and (q or 1) or nil
  end
  function b:SetItem(it)
    self.live, self.item = false, it
    self:Show_(it and ItemIcon(it.id), it and it.q)
    return it and it.q or nil
  end
  return b
end

-- AttributeFrameTemplate / StatFrameTemplate: 104x13, label left (gold), value right (white)
local function StatLine(parent, x, y, label)
  local r = CreateFrame("Frame", nil, parent)
  r:SetSize(104, 13)
  r:SetPoint("TOPLEFT", x, y)
  r.label = H.Text(r, "GameFontNormalSmall", label)
  r.label:SetPoint("LEFT")
  r.value = H.Text(r, "GameFontHighlightSmall", "", nil, "RIGHT")
  r.value:SetPoint("RIGHT")
  r:EnableMouse(true)
  r:SetScript("OnEnter", function(self)
    if not (GameTooltip and self.tip) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tip[1], 1, 1, 1)
    for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 0.82, 0, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", H.HideTip)
  return r
end

-- the three-piece stat background (UI-Character-StatBackground) of the 1.12 frame
local function StatBackground(parent, x, y, middle)
  local top = parent:CreateTexture(nil, "BACKGROUND")
  top:SetTexture(ART .. "UI-Character-StatBackground")
  top:SetSize(115, 16)
  top:SetPoint("TOPLEFT", x, y)
  top:SetTexCoord(0, 0.8984375, 0, 0.125)
  local mid = parent:CreateTexture(nil, "BACKGROUND")
  mid:SetTexture(ART .. "UI-Character-StatBackground")
  mid:SetSize(115, middle)
  mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
  mid:SetTexCoord(0, 0.8984375, 0.125, 0.1953125)
  local bot = parent:CreateTexture(nil, "BACKGROUND")
  bot:SetTexture(ART .. "UI-Character-StatBackground")
  bot:SetSize(115, 16)
  bot:SetPoint("TOPLEFT", mid, "BOTTOMLEFT")
  bot:SetTexCoord(0, 0.8984375, 0.484375, 0.609375)
  return bot
end

-- the resistance column, used for ranks: icon 32x29, number at the bottom
local BADGES = {
  { key = "lv", icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", label = "Livello" },
  { key = "q", icon = "Interface\\Icons\\INV_Misc_Note_01", label = "Quest" },
  { key = "dg", icon = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01", label = "Dungeon" },
  { key = "g", icon = "Interface\\Icons\\INV_Misc_Coin_01", label = "Sordi fatti" },
  { key = "duel", icon = "Interface\\Icons\\Ability_Warrior_Challange", label = "Duelli ner patto" },
}

----------------------------------------------------------------------
-- build
----------------------------------------------------------------------
-- the character pane lives inside the window like every other tab:
-- [ paper doll: slots, model, stat boxes, weapons ] [ ranks in the patto ] [ members ]
local function BuildDoll(v)
  local doll = H.Box(v, 380, 375, "rock")
  doll:SetPoint("TOPLEFT", 0, 0)
  v.doll = doll
  local base = doll:GetFrameLevel()

  -- header: portrait, name, "Livello 21 Undead Warlock", team
  v.portrait = doll:CreateTexture(nil, "ARTWORK")
  v.portrait:SetSize(40, 40)
  v.portrait:SetPoint("TOPLEFT", 8, -7)
  v.name = H.Text(doll, "GameFontNormal", "", 300)
  v.name:SetPoint("TOPLEFT", 54, -9)
  v.name:SetTextColor(1, 1, 1)
  v.level = H.Text(doll, "GameFontNormalSmall", "", 300)
  v.level:SetPoint("TOPLEFT", 54, -24)
  v.guild = H.Text(doll, "GameFontNormalSmall", "", 300)
  v.guild:SetPoint("TOPLEFT", 54, -37)
  -- your title, top right of your own pane
  v.titleBtn = H.Btn(doll, "Titolo", 76, function(self) ns.CharTitleMenu(self) end, 20)
  v.titleBtn:SetPoint("TOPRIGHT", -8, -8)

  -- model between the two slot columns, rotate buttons in its corner, drag to turn
  local model = CreateFrame("DressUpModel", nil, doll)
  model:SetFrameLevel(base + 2)
  model:SetSize(278, 180)
  model:SetPoint("TOPLEFT", 51, -52)
  model.rotation = 0
  v.model = model
  local rl = CreateFrame("Button", nil, model)
  rl:SetSize(32, 32)
  rl:SetPoint("TOPLEFT")
  rl:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  rl:SetNormalTexture("Interface\\Buttons\\UI-RotationLeft-Button-Up")
  rl:SetPushedTexture("Interface\\Buttons\\UI-RotationLeft-Button-Down")
  rl:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
  local rr = CreateFrame("Button", nil, model)
  rr:SetSize(32, 32)
  rr:SetPoint("TOPLEFT", rl, "TOPRIGHT")
  rr:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  rr:SetNormalTexture("Interface\\Buttons\\UI-RotationRight-Button-Up")
  rr:SetPushedTexture("Interface\\Buttons\\UI-RotationRight-Button-Down")
  rr:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Round", "ADD")
  model:SetScript("OnUpdate", function(self, elapsed)
    local dir = 0
    if rl.GetButtonState and rl:GetButtonState() == "PUSHED" then dir = 1 end
    if rr.GetButtonState and rr:GetButtonState() == "PUSHED" then dir = -1 end
    if dir ~= 0 then
      self.rotation = self.rotation + dir * (elapsed or 0) * 2 * math.pi * 0.5
      self:SetFacing(self.rotation)
    elseif self.dragX and GetCursorPosition then
      local x = GetCursorPosition()
      self.rotation = self.rotation + (x - self.dragX) * 0.015
      self.dragX = x
      self:SetFacing(self.rotation)
    end
  end)
  model:EnableMouse(true)
  model:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and GetCursorPosition then self.dragX = GetCursorPosition() end
  end)
  model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
  model:SetScript("OnHide", function(self) self.dragX = nil end)
  v.modelNote = H.Text(doll, "GameFontNormalSmall", "", 240, "CENTER")
  v.modelNote:SetPoint("BOTTOM", model, "BOTTOM", 0, 8)

  -- slots: the vanilla order, two columns of eight, weapons under the stat boxes
  local slotFrame = CreateFrame("Frame", nil, doll)
  slotFrame:SetFrameLevel(base + 3)
  slotFrame:SetAllPoints()
  v.slots = {}
  local function column(names, x)
    local prev
    for _, name in ipairs(names) do
      local b = SlotButton(slotFrame, name, v)
      if b then
        if prev then b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2) else b:SetPoint("TOPLEFT", x, -52) end
        prev = b
        v.slots[#v.slots + 1] = b
      end
    end
  end
  column(LEFT, 8)
  column(RIGHT, 335)
  local weapons = {}
  for _, name in ipairs(BOTTOM) do
    local b = SlotButton(slotFrame, name, v)
    if b then weapons[#weapons + 1] = b v.slots[#v.slots + 1] = b end
  end
  local ammoId = SlotInfo("AmmoSlot")
  local rowW = #weapons * 37 + (#weapons - 1) * 5 + (ammoId and 42 or 0)
  local x0 = 51 + math.floor((278 - rowW) / 2)
  for i, b in ipairs(weapons) do b:SetPoint("TOPLEFT", x0 + (i - 1) * 42, -325) end
  if ammoId and #weapons > 0 then
    local a = CreateFrame("Button", nil, slotFrame)
    a:SetSize(27, 27)
    a:SetPoint("LEFT", weapons[#weapons], "RIGHT", 15, 0)
    a.id, a.slotName = ammoId, "AmmoSlot"
    a.icon = a:CreateTexture(nil, "BORDER")
    a.icon:SetAllPoints()
    local l = a:CreateTexture(nil, "ARTWORK")
    l:SetTexture(ART .. "UI-Character-AmmoSlot")
    l:SetSize(41, 41)
    l:SetPoint("CENTER")
    l:SetTexCoord(0, 0.640625, 0, 0.640625)
    a:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local ok = false
      if self.live then ok = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", self.id)
      elseif self.item then ok = pcall(GameTooltip.SetHyperlink, GameTooltip, ItemString(self.item)) end
      if not ok then GameTooltip:SetText(AMMOSLOT or "Munizioni", 1, 1, 1) end
      GameTooltip:Show()
    end)
    a:SetScript("OnLeave", H.HideTip)
    function a:SetLive()
      self.live, self.item = true, nil
      local tex = GetInventoryItemTexture and GetInventoryItemTexture("player", self.id)
      if U.IsSecret(tex) then tex = nil end
      self.icon:SetTexture(tex)
    end
    function a:SetItem(it)
      self.live, self.item = false, it
      self.icon:SetTexture(it and ItemIcon(it.id) or nil)
    end
    v.slots[#v.slots + 1] = a
  end

  -- the two vanilla stat boxes (UI-Character-StatBackground) under the model
  local attr = CreateFrame("Frame", nil, doll)
  attr:SetFrameLevel(base + 2)
  attr:SetSize(230, 85)
  attr:SetPoint("TOPLEFT", 75, -236)
  StatBackground(attr, 0, 0, 53)
  local meleeBottom = StatBackground(attr, 115, 0, 12)
  local rangedTop = attr:CreateTexture(nil, "BACKGROUND")
  rangedTop:SetTexture(ART .. "UI-Character-StatBackground")
  rangedTop:SetSize(115, 16)
  rangedTop:SetPoint("TOPLEFT", meleeBottom, "BOTTOMLEFT", 0, 2)
  rangedTop:SetTexCoord(0, 0.8984375, 0, 0.125)
  local rangedMid = attr:CreateTexture(nil, "BACKGROUND")
  rangedMid:SetTexture(ART .. "UI-Character-StatBackground")
  rangedMid:SetSize(115, 11)
  rangedMid:SetPoint("TOPLEFT", rangedTop, "BOTTOMLEFT")
  rangedMid:SetTexCoord(0, 0.8984375, 0.125, 0.1953125)
  local rangedBot = attr:CreateTexture(nil, "BACKGROUND")
  rangedBot:SetTexture(ART .. "UI-Character-StatBackground")
  rangedBot:SetSize(115, 16)
  rangedBot:SetPoint("TOPLEFT", rangedMid, "BOTTOMLEFT")
  rangedBot:SetTexCoord(0, 0.8984375, 0.484375, 0.609375)
  v.stats = {}
  local leftRows = { { "lv", "Livello:" }, { "cap", "Cap:" }, { "xp", "XP:" }, { "hours", "Ar cap:" }, { "team", "Squadra:" }, { "patto", "Patto:" } }
  for i, r in ipairs(leftRows) do v.stats[r[1]] = StatLine(attr, 6, -3 - (i - 1) * 13, r[2]) end
  local rightRows = { { "q", "Quest:", -3 }, { "dg", "Dungeon:", -16 }, { "g", "Sordi:", -29 },
    { "duel", "Duelli:", -46 }, { "bg", "BG:", -59 }, { "hk", "Uccisioni:", -72 } }
  for _, r in ipairs(rightRows) do v.stats[r[1]] = StatLine(attr, 121, r[3], r[2]) end


  -- ranks in the patto, one row each: icon, what it is, position
  local ranks = H.Box(v, 150, 375)
  ranks:SetPoint("TOPLEFT", 388, 0)
  local rt = H.Text(ranks, "GameFontNormal", "Classifica", 130)
  rt:SetPoint("TOPLEFT", 10, -10)
  v.rankSub = H.Text(ranks, "GameFontDisableSmall", "", 130)
  v.rankSub:SetPoint("TOPLEFT", 10, -26)
  v.badges = {}
  for i, b in ipairs(BADGES) do
    local fb = CreateFrame("Frame", nil, ranks)
    fb:SetSize(132, 34)
    fb:SetPoint("TOPLEFT", 9, -44 - (i - 1) * 40)
    local icon = fb:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(b.icon)
    icon:SetSize(30, 30)
    icon:SetPoint("LEFT")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    fb.label = H.Text(fb, "GameFontNormalSmall", b.label, 60)
    fb.label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    fb.text = H.Text(fb, "GameFontHighlight", "", 40, "RIGHT")
    fb.text:SetPoint("RIGHT", -2, 0)
    fb:EnableMouse(true)
    fb:SetScript("OnEnter", function(self)
      if not (GameTooltip and self.tip) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tip[1], 1, 1, 1)
      for k = 2, #self.tip do GameTooltip:AddLine(self.tip[k], 1, 0.82, 0, true) end
      GameTooltip:Show()
    end)
    fb:SetScript("OnLeave", H.HideTip)
    v.badges[b.key] = fb
  end
  -- which numbers: this week or since always. It drives every box of the pane, so it sits above them, in the
  -- window's header row
  v.totBtn = H.Radio(v, "Da sempre", function() mode = "t" end)
  v.totBtn:SetPoint("BOTTOMRIGHT", v, "TOPRIGHT", -4, 6)
  v.weekBtn = H.Radio(v, "'Sta settimana", function() mode = "w" end)
  v.weekBtn:SetPoint("RIGHT", v.totBtn, "LEFT", -14, 0)
end

local function BuildSide(v)
  local side = H.Box(v, 198, 375)
  side:SetPoint("TOPLEFT", 546, 0)
  v.side = side
  local title = H.Text(side, "GameFontNormal", "Membri")
  title:SetPoint("TOPLEFT", 10, -10)
  v.members = {}
  for i = 1, PER_PAGE do
    local b = CreateFrame("Button", nil, side)
    b:SetSize(180, 17)
    b:SetPoint("TOPLEFT", 9, -28 - (i - 1) * 17)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    b.sel:SetBlendMode("ADD")
    b.sel:SetVertexColor(1, 0.82, 0, 0.6)
    b.sel:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    b.text = H.Text(b, "GameFontHighlightSmall", "", 144)
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetHeight(17)
    if b.text.SetWordWrap then b.text:SetWordWrap(false) end
    if b.text.SetNonSpaceWrap then b.text:SetNonSpaceWrap(false) end
    b.lv = H.Text(b, "GameFontHighlightSmall", "", 30, "RIGHT")
    b.lv:SetPoint("RIGHT", -2, 0)
    b:SetScript("OnClick", function(self)
      viewGuid = (self.guid ~= ns.recordGuid) and self.guid or nil
      UI.CloseMenus()
      UI.Refresh()
    end)
    v.members[i] = b
  end
  local function pageButton(dir, x)
    local b = CreateFrame("Button", nil, side)
    b:SetSize(22, 22)
    b:SetPoint("BOTTOMRIGHT", x, 6)
    local base = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() page = page + dir UI.Refresh() end)
    return b
  end
  v.prev = pageButton(-1, -34)
  v.next = pageButton(1, -10)
  v.pageText = H.Text(side, "GameFontNormalSmall", "", 100, "RIGHT")
  v.pageText:SetPoint("RIGHT", v.prev, "LEFT", -4, 0)
end

local function Build()
  local v = H.NewView("pg")
  BuildDoll(v)
  BuildSide(v)
end

----------------------------------------------------------------------
-- refresh
----------------------------------------------------------------------
-- the model shows only someone the game can draw: you, or a member in your group or targeted. Anyone else gets
-- an empty stage and a note, never a stand-in (the game would fill an empty model with your own character)
local function RefreshModel(v, rec)
  local model = v.model
  local unit = IsLive(rec) and "player" or UnitFor(rec.guid)
  local key = tostring(rec.guid) .. "|" .. tostring(rec.eq) .. "|" .. tostring(unit)
  if v.modelKey == key and (unit == nil) == (not model:IsShown()) then return end
  v.modelKey = key
  model.rotation = 0
  if unit then
    v.modelNote:SetText("")
    model:Show()
    local ok = pcall(model.SetUnit, model, unit)
    if ok then
      model:SetFacing(0)
      return
    end
  end
  if model.ClearModel then pcall(model.ClearModel, model) end
  model:Hide()
  v.modelNote:SetText("Er modello 3D de " .. tostring(rec.name) .. " se vede quanno sta ner gruppo tuo o lo targhetti.")
end

local function RefreshDoll(v, rec, list)
  local live = IsLive(rec)
  local lv = rec.lv or 1
  -- name, "Livello 18 Human Mage", team where the guild line would be
  local title = ns.Titles and ns.Titles.Of(rec)
  v.name:SetText(tostring(rec.name) .. (title and ("  |cffffd100" .. title .. "|r") or ""))
  v.titleBtn:SetShown(live)
  local parts = { "Livello " .. lv }
  for _, x in ipairs({ RaceName(rec), ClassName(rec) }) do if x ~= "" then parts[#parts + 1] = x end end
  v.level:SetText(table.concat(parts, " "))
  local team = rec.team and P.TeamName(ns.state, rec.team)
  v.guild:SetText((team and (team .. " de ") or "") .. tostring(ns.state.settings.name or "Er Patto"))
  -- portrait: the real one when the game can draw it, otherwise the round class icon
  local unit = live and "player" or UnitFor(rec.guid)
  local drawn = false
  if unit and SetPortraitTexture then
    v.portrait:SetTexCoord(0, 1, 0, 1)
    drawn = pcall(SetPortraitTexture, v.portrait, unit)
  end
  if not drawn then
    v.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    local c = CLASS_ICON_TCOORDS and rec.cls and CLASS_ICON_TCOORDS[rec.cls]
    if c then v.portrait:SetTexCoord(c[1], c[2], c[3], c[4]) else v.portrait:SetTexCoord(0, 0.25, 0, 0.25) end
  end
  RefreshModel(v, rec)
  local gear = (not live) and T.ParseEquipment(rec.eq) or nil
  for _, b in ipairs(v.slots) do
    if live then b:SetLive() else b:SetItem(gear[b.id]) end
  end
end

local function Stat(v, key, value, tip)
  local r = v.stats[key]
  r.value:SetText(value)
  r.tip = tip
end

local function RefreshStats(v, rec, list)
  local state = ns.state
  local s = state.settings
  local now = U.Now()
  local who = rec.guid == ns.recordGuid and "Tu" or tostring(rec.name)
  local st = rec.team and M.Status(s, rec.team, now)
  local lv = rec.lv or 1
  local pos = H.Position(rec)
  local tname = rec.team and P.TeamName(state, rec.team)

  -- left box: the adventure
  Stat(v, "lv", tostring(lv), { "Livello " .. lv, (rec.xp and rec.xpm and rec.xpm > 0 and lv < 60) and ("XP: " .. U.Thousands(rec.xp) .. " / " .. U.Thousands(rec.xpm)) or "" })
  if st then
    local ps, d = M.PlayerState(lv, st.cap)
    local capText = st.lifted and (GREEN .. "libbero|r") or ((ps == "over" and RED) or (ps == "at" and GREEN) or WHITE) .. st.cap .. "|r"
    local lines = { "Cap de " .. tname .. ": " .. (st.lifted and "niente" or st.cap) }
    if not st.started then lines[#lines + 1] = "Se parte " .. U.When(s.start) .. "."
    elseif not st.lifted then
      lines[#lines + 1] = "Settimana " .. st.week .. ". Prossimo cap: " .. st.nextCap .. " " .. U.When(st.unlockAt) .. "."
      if ps == "over" then lines[#lines + 1] = RED .. "Sopra er cap de " .. d .. ".|r"
      elseif ps == "at" then lines[#lines + 1] = GREEN .. "Ar cap.|r"
      else lines[#lines + 1] = "Mancano " .. d .. (d == 1 and " livello." or " livelli.") end
    end
    Stat(v, "cap", capText, lines)
  else
    Stat(v, "cap", "-", { "Cap", "Nessuna squadra scelta." })
  end
  if rec.xp and rec.xpm and rec.xpm > 0 and lv < 60 then
    Stat(v, "xp", Pct(rec.xp / rec.xpm), { "Esperienza", U.Thousands(rec.xp) .. " / " .. U.Thousands(rec.xpm) .. " XP",
      (rec.rest or 0) > 0 and ("Riposata: " .. U.Thousands(rec.rest)) or "Niente XP riposata." })
  else
    Stat(v, "xp", "-", { "Esperienza", "Nun ancora nota." })
  end
  if st and not st.lifted and lv < 60 then
    local l = math.min(60, lv)
    local left = M.HoursToCap(s, st.week, l, rec.xp, rec.xpm, st.cap)
    local value = (lv > st.cap and (RED .. "sopra|r")) or (left > 0.05 and ("~" .. U.Hours(left))) or (GREEN .. "ar cap|r")
    Stat(v, "hours", value, { "Ore de gioco pe' arrivà ar cap",
      left > 0.05 and ("Più o meno " .. U.Hours(left) .. ", contando da dove sta la barra dell'XP ar livello " .. st.cap .. ".") or
        (lv > st.cap and "Già sopra er cap." or "Ar cap: la barra se pò riempì, ma niente ding."),
      "È 'na stima: 'n giocatore normale, senza rush." })
  else
    Stat(v, "hours", "-", { "Ore de gioco ar cap", st and st.lifted and "Er cap è tolto." or "Nessun cap." })
  end
  local teamList = {}
  for _, m in ipairs(list) do if rec.team and m.team == rec.team then teamList[#teamList + 1] = m end end
  local tl = Standing(teamList, rec, function(m) return H.Position(m) end)
  local pl = Standing(list, rec, function(m) return H.Position(m) end)
  if tname and tl.n > 0 then
    local avg = string.format("%.1f", tl.avg):gsub("%.", ",")
    local diff = string.format("%+.1f", pos - tl.avg):gsub("%.", ",")
    Stat(v, "team", tl.rank .. "º/" .. tl.n, { tname .. ": " .. tl.rank .. "º su " .. tl.n .. " pe' livello", "Media de la squadra: " .. avg .. " (" .. diff .. ")" })
  else
    Stat(v, "team", "-", { "Squadra", "Nessuna squadra scelta." })
  end
  Stat(v, "patto", pl.rank .. "º/" .. pl.n, { "Patto: " .. pl.rank .. "º su " .. pl.n .. " pe' livello",
    pl.bestRec and ("Er più avanti: " .. tostring(pl.bestRec.name) .. " (" .. tostring(pl.bestRec.lv) .. ")") or "" })

  -- right box: what was done, coloured against the patto average
  local idx = NameIndex(list)
  local modeText = mode == "w" and "'sta settimana" or "da sempre"
  local function counted(key, label, fmt)
    local sd = Standing(list, rec, function(m) return H.StatOf(m, key, mode) end)
    local text = fmt and fmt(sd.mine) or tostring(sd.mine)
    local tip = { label .. " " .. modeText .. ": " .. (fmt and fmt(sd.mine) or sd.mine) }
    if sd.sum > 0 then
      tip[#tip + 1] = sd.rank .. "º su " .. sd.n .. " ner patto, er " .. Pct(sd.mine / sd.sum) .. " der totale."
      tip[#tip + 1] = "Media der patto: " .. (fmt and fmt(sd.avg) or string.format("%.1f", sd.avg):gsub("%.0$", ""):gsub("%.", ",")) .. "."
      if sd.bestRec then tip[#tip + 1] = "Er mejo: " .. tostring(sd.bestRec.name) .. " co' " .. (fmt and fmt(sd.best) or sd.best) .. "." end
    else
      tip[#tip + 1] = "Ancora gnente pe' nessuno."
    end
    return ColorVs(text, sd.mine, sd.avg), tip, sd
  end
  local qt, qtip = counted("q", "Quest")
  Stat(v, "q", qt, qtip)
  local dt, dtip = counted("dg", "Dungeon")
  if rec.ld then dtip[#dtip + 1] = "Urtimo: " .. rec.ld .. "." end
  Stat(v, "dg", dt, dtip)
  local gt, gtip = counted("g", "Sordi fatti", function(x) return Money(x, true) end)
  gtip[#gtip + 1] = T.AuctionCounts() and "L'asta conta." or "L'asta nun conta."
  Stat(v, "g", gt, gtip)
  local w, l, rival, rh = PattoDuels(rec, idx)
  local ds = Standing(list, rec, function(m) return (PattoDuels(m, idx)) end)
  local dtipD = { "Duelli ner patto (da sempre): " .. w .. " vinti, " .. l .. " persi" }
  if w + l > 0 then dtipD[#dtipD + 1] = Pct(w / (w + l)) .. " vinti." end
  if ds.best > 0 then dtipD[#dtipD + 1] = ds.rank .. "º su " .. ds.n .. " pe' vittorie." end
  Stat(v, "duel", ColorVs(w .. "-" .. l, w, ds.avg), dtipD)
  local bw, bl = H.StatOf(rec, "bw", mode), H.StatOf(rec, "bl", mode)
  local bs = Standing(list, rec, function(m) return H.StatOf(m, "bw", mode) end)
  Stat(v, "bg", ColorVs(bw .. "-" .. bl, bw, bs.avg), { "Campi de battaja " .. modeText .. ": " .. bw .. " vinte, " .. bl .. " perse",
    bs.best > 0 and (bs.rank .. "º su " .. bs.n .. " pe' vittorie.") or "Ancora nessuna BG ner patto." })
  -- PvP: the kills out in the world ("pe' strada") and in battlegrounds apart; honor in the tooltip
  local hw, hb = H.StatOf(rec, "hw", mode), H.StatOf(rec, "hb", mode)
  local hws = Standing(list, rec, function(m) return H.StatOf(m, "hw", mode) end)
  local hbs = Standing(list, rec, function(m) return H.StatOf(m, "hb", mode) end)
  local hn = H.StatOf(rec, "hn", mode)
  Stat(v, "hk", ColorVs(hw .. " / " .. hb, hw, hws.avg), { "Uccisioni onorevoli " .. modeText .. ": " .. hw .. " pe' strada / " .. hb .. " in BG",
    hws.best > 0 and ("Pe' strada: " .. hws.rank .. "º su " .. hws.n .. " ner patto.") or "Pe' strada: ancora nessuno ner patto.",
    hbs.best > 0 and ("In BG: " .. hbs.rank .. "º su " .. hbs.n .. " ner patto.") or "In BG: ancora nessuno ner patto.",
    "Onore guadagnato: " .. U.Thousands(hn) .. "." })

  -- resistance column: ranks
  local function badge(key, sd, label)
    local b = v.badges[key]
    local top = sd.rank == 1 and sd.best > 0
    local medal = ({ "|cffffd100", "|cffd8d8e6", "|cffd98c4d" })[sd.rank] or WHITE
    b.text:SetText(sd.best > 0 and (medal .. sd.rank .. "º|r") or "|cff9d9d9d-|r")
    b.tip = { "Classifica " .. label .. ": " .. (sd.best > 0 and (sd.rank .. "º su " .. sd.n) or "ancora gnente") }
    if top then b.tip[2] = (who == "Tu") and "Sei er primo der patto." or (who .. " è er primo der patto.") end
  end
  badge("lv", pl, "Livello")
  badge("q", Standing(list, rec, function(m) return H.StatOf(m, "q", mode) end), "Quest")
  badge("dg", Standing(list, rec, function(m) return H.StatOf(m, "dg", mode) end), "Dungeon")
  badge("g", Standing(list, rec, function(m) return H.StatOf(m, "g", mode) end), "Sordi fatti")
  badge("duel", ds, "Duelli ner patto")
end

local function RefreshSide(v, rec, list)
  -- me first, then by team and level
  local order = {}
  for _, m in ipairs(list) do order[#order + 1] = m end
  table.sort(order, function(a, b)
    if (a.guid == ns.recordGuid) ~= (b.guid == ns.recordGuid) then return a.guid == ns.recordGuid end
    if (a.team or "z") ~= (b.team or "z") then return (a.team or "z") < (b.team or "z") end
    if (a.lv or 0) ~= (b.lv or 0) then return (a.lv or 0) > (b.lv or 0) end
    return tostring(a.name) < tostring(b.name)
  end)
  local pages = math.max(1, math.ceil(#order / PER_PAGE))
  page = math.max(1, math.min(page, pages))
  for i, b in ipairs(v.members) do
    local m = order[(page - 1) * PER_PAGE + i]
    if m then
      b.guid = m.guid
      local title = ns.Titles and ns.Titles.Of(m)
      b.text:SetText(H.Colored(m) .. (m.guid == ns.recordGuid and " |cffffd100(tu)|r" or "") .. (title and (" |cff9d9d9d" .. title .. "|r") or ""))
      b.lv:SetText(tostring(m.lv or "?"))
      b.sel:SetShown(m.guid == rec.guid)
      b:Show()
    else
      b:Hide()
    end
  end
  v.prev:SetShown(pages > 1)
  v.next:SetShown(pages > 1)
  v.prev:SetEnabled(page > 1)
  v.next:SetEnabled(page < pages)
  v.pageText:SetText(pages > 1 and (page .. " de " .. pages) or "")
  v.weekBtn:SetSelected(mode == "w")
  v.totBtn:SetSelected(mode == "t")
end

local function Refresh(v)
  local list = UI.Members()
  local rec = Viewed(list)
  if not rec then return end
  shownRec, shownList = rec, list
  RefreshDoll(v, rec, list)
  RefreshStats(v, rec, list)
  RefreshSide(v, rec, list)
end

UI.AddView("pg", "Personaggio", Build, Refresh, true)

-- the title picker: a small vanilla list under the "Titolo" button
local menu
local function CloseMenu()
  if not menu then return end
  menu:Hide()
  if menu.sheet then menu.sheet:Hide() end
end
function UI.CloseMenus() CloseMenu() end
function ns.CharTitleMenu(anchor)
  if menu and menu:IsShown() then CloseMenu() return end
  local titles = ns.Titles.Mine()
  if not menu then
    menu = CreateFrame("Frame", "ErPattoTitleMenu", UIParent)
    menu:SetFrameStrata("DIALOG")
    menu:SetToplevel(true)
    menu:EnableMouse(true)
    H.Chrome(menu)
    menu.head = H.Text(menu, "GameFontNormal", "Li titoli tua", 200)
    menu.head:SetPoint("TOPLEFT", 20, -18)
    menu.rows = {}
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoTitleMenu") end
    -- a click anywhere else closes it, like a vanilla dropdown: an invisible sheet over the screen, just under the
    -- list, takes that click. (It was a "mouse down anywhere" event that asked the game if the mouse was over the
    -- list: it only started from the second time the list opened, and in the game it closed the list under the
    -- click, so from the second time on a title could no longer be picked.)
    local sheet = CreateFrame("Button", nil, UIParent)
    sheet:SetAllPoints(UIParent)
    sheet:SetFrameStrata("DIALOG")
    sheet:EnableMouse(true)
    sheet:SetScript("OnClick", CloseMenu)
    sheet:Hide()
    menu.sheet = sheet
    sheet:SetFrameLevel(1)
    menu:SetFrameLevel(20)
    menu:SetScript("OnShow", function(self) self.sheet:Show() end)
    menu:SetScript("OnHide", function(self) self.sheet:Hide() end)
    menu:Hide()
  end
  menu.anchor = anchor
  for _, r in ipairs(menu.rows) do r:Hide() end
  local rec = ns.MyRecord()
  local entries = { { id = "", name = "Nessun titolo" } }
  for _, t in ipairs(titles) do entries[#entries + 1] = t end
  for i, t in ipairs(entries) do
    local r = menu.rows[i]
    if not r then
      r = H.Radio(menu, "", function(self) ns.Titles.Choose(self.id) CloseMenu() end)
      r:SetScript("OnEnter", function(self)
        if self.desc then H.Tip(self, { self.label, self.desc }) end
      end)
      r:SetScript("OnLeave", H.HideTip)
      menu.rows[i] = r
    end
    r.id, r.label, r.desc = t.id, t.name, t.desc
    r.text:SetText(t.name)
    r:SetWidth(200)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 20, -40 - (i - 1) * 18)
    r:SetSelected((rec and rec.ti or "") == t.id)
    r:Show()
  end
  menu.head:SetText(#titles > 0 and "Li titoli tua" or "Ancora nessun titolo: vinci quarcosa ner patto!")
  menu:SetSize(250, 56 + #entries * 18)
  menu.stone.Refit()
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
  menu:Show()
end

-- shared with the Progresso tab
ns.Rank = { Standing = Standing, NameIndex = NameIndex, PattoDuels = PattoDuels, Money = Money, Pct = Pct, ColorVs = ColorVs }

-- show a given member's pane (used by other tabs)
function UI.ShowCharacter(guid)
  viewGuid = guid ~= ns.recordGuid and guid or nil
  UI.Show("pg")
end

-- new gear or a new look: redraw my model next time
ns.On("Equipment", function()
  local v = UI._views and UI._views.pg
  if not v then return end
  if not viewGuid then v.modelKey = nil end
  if UI.IsShown("pg") then UI.Refresh() end
end)
