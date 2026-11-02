-- game stubs for Tracker/Main tests (on top of stub3.lua)
FRAMES = {}
local FrameMT = {}
FrameMT.__index = FrameMT
function FrameMT:RegisterEvent(e) self.events[e] = true end
function FrameMT:UnregisterEvent(e) self.events[e] = nil end
function FrameMT:SetScript(k, fn) self.scripts[k] = fn end
function FrameMT:GetScript(k) return self.scripts[k] end
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ events = {}, scripts = {}, kind = kind }, FrameMT)
  table.insert(FRAMES, f)
  if name then _G[name] = f end
  return f
end
function FIRE(event, ...)
  for _, f in ipairs(FRAMES) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) table.insert(CHAT, m) end }
ERRORS_SHOWN = {}
UIErrorsFrame = { AddMessage = function(self, m) table.insert(ERRORS_SHOWN, m) end }
SOUNDKIT = { RAID_WARNING = 8959 }
PlaySound = function() end
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
P_GUID, P_NAME, P_LEVEL, P_XP, P_XPMAX, P_ZONE, P_CLASS, P_FACTION = "Player-1-0001", "Dario", 1, 0, 400, "Elwynn Forest", "MAGE", "Alliance"
REWARD_XP = 0
INST_NAME, INST_KIND = "Elwynn Forest", "none"
BF_STATUS, BF_WINNER = "none", nil
UnitGUID = function() return P_GUID end
UnitName = function() return P_NAME, nil end
UnitLevel = function() return P_LEVEL end
UnitXP = function() return P_XP end
UnitXPMax = function() return P_XPMAX end
GetXPExhaustion = function() return nil end
GetRealZoneText = function() return P_ZONE end
UnitClass = function() return "Mage", P_CLASS end
UnitFactionGroup = function() return P_FACTION end
GetRewardXP = function() return REWARD_XP end
GetInstanceInfo = function() return INST_NAME, INST_KIND end
GetBattlefieldStatus = function() return BF_STATUS end
GetBattlefieldWinner = function() return BF_WINNER end
SlashCmdList = {}
