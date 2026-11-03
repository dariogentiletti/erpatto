-- widget stubs: enough behaviour to build and click through the UI, and a list of any method we don't know
KNOWN = {}
for m in string.gmatch([[SetSize GetSize SetWidth SetHeight GetWidth GetHeight SetPoint ClearAllPoints SetAllPoints GetPoint Show Hide IsShown SetShown
SetScript GetScript HookScript CreateTexture CreateFontString SetBackdrop SetBackdropColor SetBackdropBorderColor SetText GetText
SetFontObject SetJustifyH SetJustifyV SetTexture SetTexCoord SetColorTexture SetVertexColor SetBlendMode SetFrameStrata SetFrameLevel
SetToplevel SetClampedToScreen EnableMouse SetMovable RegisterForDrag StartMoving StopMovingOrSizing RegisterEvent UnregisterEvent
SetAutoFocus SetMaxLetters ClearFocus HasFocus HighlightText SetEnabled Enable Disable IsEnabled SetChecked GetChecked SetMinMaxValues
SetValue GetValue SetStatusBarTexture SetStatusBarColor SetScrollChild SetVerticalScroll GetVerticalScrollRange SetMultiLine
SetFocus SetGradientAlpha SetFont SetNonSpaceWrap SetWordWrap SetHitRectInsets HookScript SetVertexColor RegisterForClicks Click GetParent SetParent SetNormalFontObject LockHighlight UnlockHighlight SetAlpha GetName SetNumeric SetDrawLayer]], "%S+") do KNOWN[m] = true end
UNKNOWN = {}
WIDGETS = {}
local W = {}
local function new(kind, parent, template)
  local o = { kind = kind, parent = parent, template = template, scripts = {}, events = {}, shown = kind ~= "Texture_hidden", w = 0, h = 0, text = nil, points = {} }
  setmetatable(o, W)
  table.insert(WIDGETS, o)
  return o
end
W.__index = function(self, k)
  local m = rawget(W, k)
  if m then return m end
  if type(k) == "string" and k:match("^%u") then
    UNKNOWN[k] = (UNKNOWN[k] or 0) + 1
    return function() end
  end
  return nil
end
function W.SetSize(self, w, h) self.w, self.h = w, h end
function W.GetSize(self) return self.w, self.h end
function W.SetWidth(self, w) self.w = w end
function W.SetHeight(self, h) self.h = h end
function W.GetWidth(self) return self.w end
function W.GetHeight(self) return self.h end
function W.SetPoint(self, ...) table.insert(self.points, { ... }) end
function W.ClearAllPoints(self) self.points = {} end
function W.SetAllPoints(self) end
function W.GetPoint(self) local p = self.points[1] or { "CENTER" } return p[1], UIParent, p[1], 0, 0 end
function W.Show(self) self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end
function W.Hide(self) self.shown = false end
function W.IsShown(self) return self.shown end
function W.SetShown(self, v) if v then self.shown = true else self.shown = false end end
function W.IsVisible(self) local p = self while p do if not p.shown then return false end p = p.parent end return true end
function W.SetScript(self, k, fn) self.scripts[k] = fn end
function W.GetScript(self, k) return self.scripts[k] end
function W.HookScript(self, k, fn) self.scripts[k] = fn end
function W.CreateTexture(self) return new("Texture", self) end
function W.CreateFontString(self, name, layer, font) local o = new("FontString", self) o.font = font return o end
function W.SetText(self, t)
  if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then error("SetText with " .. type(t)) end
  self.text = t ~= nil and tostring(t) or nil
  if self.kind == "EditBox" and self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function W.GetText(self) return self.text or "" end
function W.SetFontObject(self, f) if type(f) ~= "string" and type(f) ~= "table" then error("bad font") end self.font = f end
function W.HasFocus(self) return false end
function W.SetEnabled(self, v) self.enabled = v and true or false end
function W.Enable(self) self.enabled = true end
function W.Disable(self) self.enabled = false end
function W.IsEnabled(self) return self.enabled ~= false end
function W.SetChecked(self, v) self.checked = v and true or false end
function W.GetChecked(self) return self.checked end
function W.SetMinMaxValues(self, a, b) self.min, self.max = a, b end
function W.SetValue(self, v)
  if type(v) ~= "number" or v ~= v then error("SetValue bad " .. tostring(v)) end
  self.value = v
end
function W.GetValue(self) return self.value end
function W.GetParent(self) return self.parent end
function W.GetName(self) return self.name end
function W.GetVerticalScrollRange(self) return 0 end
function W.Click(self, button)
  if self.enabled == false then return end
  if self.kind == "CheckButton" then self.checked = not self.checked end
  if self.scripts.OnClick then self.scripts.OnClick(self, button or "LeftButton") end
end
function W.RegisterEvent(self, e) self.events[e] = true end
function W.UnregisterEvent(self, e) self.events[e] = nil end
function W.StartMoving() end
function W.StopMovingOrSizing() end
function W.SetTexture(self, t) self.tex = t end
function W.SetWidthCheck() end
for k in pairs(KNOWN) do if not rawget(W, k) then W[k] = function() end end end
function CreateFrame(kind, name, parent, template)
  local o = new(kind, parent, template)
  o.name = name
  if name then _G[name] = o end
  table.insert(FRAMES, o)
  return o
end
UIParent = new("Frame")
UIParent.name = "UIParent"
UISpecialFrames = {}
GameTooltip = new("GameTooltip")
GameTooltip.SetOwner = function() end
GameTooltip.AddLine = function() end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92, colorStr = "ff3fc7eb" }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
GetBuildInfo = function() return "1.16.0", "60000", "Oct 1 2026", 16001 end
IsInGuild = function() return false end
IsInGroup = function() return false end
IsInRaid = function() return false end
tinsert = table.insert
GetChannelName = GetChannelName
function VISIBLE_TEXTS()
  local out = {}
  for _, o in ipairs(WIDGETS) do
    if (o.kind == "FontString" or o.kind == "Button" or o.kind == "EditBox") and o.text and o:IsVisible() then table.insert(out, o.text) end
  end
  return out
end
function FIND_BUTTON(label)
  for _, o in ipairs(WIDGETS) do
    if o.kind == "Button" and o.text == label and o:IsVisible() then return o end
  end
end
ChatFontNormal = { font = true }
for m in string.gmatch("SetUnit RefreshUnit SetFacing GetFacing SetNormalTexture SetPushedTexture SetHighlightTexture SetMask SetAlpha SetInventoryItem", "%S+") do
  KNOWN[m] = true
end
for k in pairs(KNOWN) do if not rawget(getmetatable(UIParent), k) then getmetatable(UIParent)[k] = function() end end end
local SLOT_IDS = { HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4, ChestSlot = 5, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8,
  WristSlot = 9, HandsSlot = 10, Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14, BackSlot = 15,
  MainHandSlot = 16, SecondaryHandSlot = 17, TabardSlot = 19 }
GetInventorySlotInfo = function(name)
  local id = SLOT_IDS[name]
  if not id then error("Invalid inventory slot " .. tostring(name)) end
  return id, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name
end
GEAR = { [1] = { "icon-head", 3 }, [5] = { "icon-chest", 2 }, [16] = { "icon-sword", 2 }, [8] = { "icon-feet", 1 } }
GetInventoryItemTexture = function(unit, id) return GEAR[id] and GEAR[id][1] or nil end
GetInventoryItemQuality = function(unit, id) return GEAR[id] and GEAR[id][2] or nil end
GetInventoryItemLink = function(unit, id) return GEAR[id] and "|Hitem:1|h[x]|h" or nil end
ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 } }
UnitRace = function() return "Umano", "Human" end
UnitClass = function() return "Mago", P_CLASS end
SetPortraitTexture = function() end
P_ILVL = 12.34
GetAverageItemLevel = function() return P_ILVL, P_ILVL, P_ILVL end
P_MONEY = 0
GetMoney = function() return P_MONEY end
GetCursorPosition = function() return 0, 0 end
IsModifiedClick = function() return false end
HEADSLOT = "Testa"
-- 0.4.0: frame levels, text sizes, model calls, mail, units
local WM = getmetatable(UIParent)
WM.GetFrameLevel = function(self) return self._level or (self.parent and self.parent.GetFrameLevel and (self.parent:GetFrameLevel() + 1)) or 1 end
WM.SetFrameLevel = function(self, l) if type(l) ~= "number" then error("SetFrameLevel " .. type(l)) end self._level = l end
WM.GetStringWidth = function(self) return #(self.text or "") * 6 end
WM.SetTextColor = function() end
WM.SetDisabledTexture = function() end
WM.GetButtonState = function(self) return self.state or "NORMAL" end
WM.SetHyperlink = function() return true end
WM.SetUnit = function(self, u) self.calls = self.calls or {} table.insert(self.calls, "SetUnit:" .. tostring(u)) end
WM.SetCustomRace = function(self, r, s) self.calls = self.calls or {} table.insert(self.calls, "SetCustomRace:" .. tostring(r) .. ":" .. tostring(s)) end
WM.Undress = function(self) self.calls = self.calls or {} table.insert(self.calls, "Undress") end
WM.TryOn = function(self, it) self.calls = self.calls or {} table.insert(self.calls, "TryOn:" .. tostring(it)) end
WM.ClearModel = function(self) self.calls = self.calls or {} table.insert(self.calls, "ClearModel") end
WM.SetTexCoord = function(self, ...) self.coords = { ... } end
UNIT_GUIDS = {}
UnitGUID = function(u) if u == "player" or u == nil then return P_GUID end return UNIT_GUIDS[u] end
UnitIsVisible = function(u) return UNIT_GUIDS[u] ~= nil end
UnitSex = function() return 2 end
UnitRace = function() return "Umano", "Human", 1 end
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.49, 0, 0.25 }, WARRIOR = { 0, 0.25, 0, 0.25 } }
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mago", WARRIOR = "Guerriero", PRIEST = "Sacerdote", ROGUE = "Ladro", HUNTER = "Cacciatore", WARLOCK = "Stregone", DRUID = "Druido", PALADIN = "Paladino", SHAMAN = "Sciamano" }
C_Item = { GetItemIconByID = function(id) return "icon-id-" .. tostring(id) end }
GetItemInfo = function() return nil end
GEAR = { [1] = { "icon-head", 3, 12345 }, [5] = { "icon-chest", 2, 6789, 567 }, [16] = { "icon-sword", 2, 1111 }, [8] = { "icon-feet", 1, 2222 } }
GetInventoryItemLink = function(unit, id)
  local g = GEAR[id]
  if not g then return nil end
  return "|cff1eff00|Hitem:" .. g[3] .. ":0:0:0:0:0:" .. (g[4] or 0) .. ":0:0|h[Roba]|h|r"
end
function hooksecurefunc(name, fn)
  local orig = _G[name]
  _G[name] = function(...) local r = { orig(...) } fn(...) return unpack(r) end
end
MAILS = {}
GetInboxHeaderInfo = function(i) local m = MAILS[i] if not m then return nil end return nil, nil, m.sender, m.subject, m.money end
GetInboxInvoiceInfo = function(i) local m = MAILS[i] return m and m.invoice or nil end
TakeInboxMoney = function(i) end
AutoLootMailItem = function(i) end
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
WM.SetWordWrap = function() end
ILVL = { [12345] = 24, [6789] = 21, [2222] = 15, [1111] = 26 }
C_Item.GetDetailedItemLevelInfo = function(link) local id = tonumber(tostring(link):match("item:(%d+)")) return ILVL[id] end
TT = {}
GameTooltip.SetOwner = function() TT = {} end
GameTooltip.SetText = function(self, t) table.insert(TT, tostring(t)) end
GameTooltip.AddLine = function(self, t) table.insert(TT, tostring(t)) end
GameTooltip.ClearLines = function() end
GameTooltip.AddDoubleLine = function(self, a, b) table.insert(TT, tostring(a) .. " | " .. tostring(b)) end
GameTooltip.SetInventoryItem = function() table.insert(TT, "[oggetto]") return true end
C_QuestLog = { GetTitleForQuestID = function(id) return "La quest nummero " .. tostring(id) end }
GetTitleText = function() return "Titolo" end
WM.RegisterUnitEvent = function(self, e) self.events[e] = true end
UNITS = {}
UnitExists = function(u) return UNITS[u] ~= nil end
UnitClassification = function(u) return UNITS[u] and UNITS[u].class or "normal" end
UnitIsDead = function(u) return UNITS[u] and UNITS[u].dead or false end
UnitIsTapDenied = function(u) return UNITS[u] and UNITS[u].denied or false end
local oldGUID = UnitGUID
UnitGUID = function(u) if UNITS[u] then return UNITS[u].guid end return oldGUID(u) end
local oldName = UnitName
UnitName = function(u) if UNITS[u] then return UNITS[u].name end return oldName(u) end
WM.SetHorizTile = function() end WM.SetVertTile = function() end
WM.SetStatusBarColor = function(self, r, g, b) self.color = string.format("%.2f,%.2f,%.2f", r, g, b) end
PVP_HK, PVP_HONOR = 0, 0
GetPVPLifetimeStats = function() return PVP_HK, 0, 0 end
C_CurrencyInfo = { GetCurrencyInfo = function(id) if id == 1792 then return { quantity = PVP_HONOR } end end }
MOUSE_OVER = false
MouseIsOver = function() return MOUSE_OVER end
WM.GetStringHeight = function(self) return 14 end
COMPLETED_N = 0
C_QuestLog.GetAllCompletedQuestIDs = function() local t = {} for i = 1, COMPLETED_N do t[i] = 1000 + i end return t end
RequestTimePlayed = function() PLAYED_REQUESTED = true end
strsplit = function(sep, s) local out = {} for part in string.gmatch(s, "([^" .. sep .. "]+)") do out[#out + 1] = part end return unpack(out) end
LOOT = {}
GetNumLootItems = function() return #LOOT end
GetLootSourceInfo = function(slot) return LOOT[slot] and LOOT[slot].src, 1 end
GetLootSlotLink = function(slot) return LOOT[slot] and LOOT[slot].link end
IsFishingLoot = function() return false end
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
UnitCreatureType = function() return "Humanoid" end
IsResting = function() return false end
UnitCanAttack = function() return true end

local oldCF = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = oldCF(kind, name, parent, template)
  if kind == "ScrollFrame" and template == "UIPanelScrollFrameTemplate" then
    local bar = oldCF("Slider", name and (name .. "ScrollBar") or nil, f)
    rawset(f, "ScrollBar", bar)
  end
  return f
end
