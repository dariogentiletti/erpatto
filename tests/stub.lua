SECRET = setmetatable({}, { __tostring = function() error("secret value printed!") end, __concat = function() error("secret value concatenated!") end })
issecretvalue = function(v) return v == SECRET end
local objects = {}
local function newObj(kind, name)
  local o = { __kind = kind, scripts = {}, shown = false, text = "", name = name }
  setmetatable(o, { __index = function(t, k) return function(self, ...) return nil end end })
  o.SetScript = function(self, n, fn) self.scripts[n] = fn end
  o.IsShown = function(self) return self.shown end
  o.Show = function(self) self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
  o.Hide = function(self) self.shown = false end
  o.SetText = function(self, t) self.text = t end
  o.GetText = function(self) return self.text end
  o.CreateTexture = function(self) return newObj("Texture") end
  o.CreateFontString = function(self) return newObj("FontString") end
  o.GetVerticalScrollRange = function() return 0 end
  o.RegisterEvent = function(self, e) if e == "PVP_MATCH_COMPLETE" then error("Attempt to register unknown event") end end
  objects[#objects + 1] = o
  return o
end
OBJECTS = objects
CreateFrame = function(kind, name, parent, template) local o = newObj(kind, name); if name then _G[name] = o end; return o end
UIParent = newObj("Frame"); ChatFrame1 = newObj("Frame"); NUM_CHAT_WINDOWS = 1
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(self, m) CHAT[#CHAT + 1] = m end }
SENT = {}
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, NotInGroup = 5 } }
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, kind, target) SENT[#SENT + 1] = kind .. ">" .. tostring(target) .. ":" .. msg; if kind == "GUILD" then return 5 end return 0 end }
C_Timer = { After = function(t, fn) fn() end }
C_PvP = {}
date = os.date; time = os.time
GetServerTime = function() return 1793600000 end
GetTime = function() return 100 end
GetBuildInfo = function() return "1.60.1", "70500", "Nov 1 2026", 16001 end
WOW_PROJECT_ID = 18; WOW_PROJECT_CAMELOT = 18
UnitName = function() return "Pietro Cesaroni", nil end
UnitFullName = function() return "Pietro Cesaroni", "" end
GetUnitName = function() return "Pietro Cesaroni" end
UnitGUID = function() return "Player-1-0ABC" end
UnitLevel = function() return 12 end
UnitXP = function() return 9000 end
UnitXPMax = function() return 10100 end
GetXPExhaustion = function() return 3000 end
UnitFactionGroup = function() return "Alliance" end
IsInGuild = function() return true end
IsInGroup = function() return true end
IsInRaid = function() return false end
GetNumGuildMembers = function() return 2 end
GetGuildRosterInfo = function(i) return "Membro" .. i, "Rank", 1, 10 + i, "Mago", "Elwynn", "[CES]" end
C_GuildInfo = { GuildRoster = function() end }
GetInstanceInfo = function() return "Le Miniere della Morte", "party", 1, "Normale", 5, 0, false, 36 end
GetRewardXP = function() return 1500 end
JoinChannelByName = function() return 1, "erpattoprova" end
GetChannelName = function() return 5, "erpattoprova" end
ChatFrame_RemoveChannel = function() end
GetBattlefieldStatus = function() return "active", "Gola di Warsong" end
GetBattlefieldWinner = function() return 1 end
DUEL_WINNER_KNOCKOUT = "%1$s has defeated %2$s in a duel"
DUEL_WINNER_RETREAT = "%2$s has fled from %1$s in a duel"
tinsert = table.insert; UISpecialFrames = {}
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
Mixin = function(o, m) return o end; BackdropTemplateMixin = {}; ChatFontNormal = {}
SlashCmdList = {}
