SECRET = setmetatable({}, { __tostring = function() error("secret printed") end, __concat = function() error("secret concatenated") end })
issecretvalue = function(v) return v == SECRET end
NOWV = 0
GetServerTime = function() return math.floor(NOWV) end
GetTime = function() return NOWV end
date = os.date; time = os.time
TIMERS, ERRORS, OUTBOX, SENDLOG = {}, {}, {}, {}
C_Timer = {
  After = function(d, fn) table.insert(TIMERS, { at = NOWV + d, fn = fn }) end,
  NewTicker = function(d, fn) local t = { at = NOWV + d, fn = fn, every = d }; table.insert(TIMERS, t); return { Cancel = function() t.cancel = true end } end,
}
function RUN_TIMERS()
  local due = {}
  for i = #TIMERS, 1, -1 do
    local t = TIMERS[i]
    if t.cancel then table.remove(TIMERS, i)
    elseif NOWV >= t.at then
      table.insert(due, t)
      if t.every then t.at = math.max(t.at + t.every, NOWV + t.every * 0.5) else table.remove(TIMERS, i) end
    end
  end
  for _, t in ipairs(due) do local ok, err = pcall(t.fn); if not ok then table.insert(ERRORS, tostring(err)) end end
end
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, NotInGroup = 5, ChannelThrottle = 8, GeneralError = 11 } }
C_ChatInfo = { RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, text, kind, target)
    if #text > 255 then error("message too long " .. #text) end
    if INSTANCE then return 11 end
    table.insert(OUTBOX, { prefix = prefix, text = text, kind = kind, target = target })
    table.insert(SENDLOG, NOWV)
    return 0
  end }
JOINED, CHANNEL_OK, INSTANCE = false, true, false
JoinChannelByName = function(name, pw) if CHANNEL_OK then JOINED = name end end
GetChannelName = function(name) if JOINED and JOINED == name then return 7, name end return 0 end
LeaveChannelByName = function() JOINED = false end
-- the channel's member list: the harness puts in ROSTER who else sits in the same channel ({ name, guid })
ROSTER = {}
GetNumDisplayChannels = function() return JOINED and 1 or 0 end
GetChannelDisplayInfo = function(i) if JOINED and i == 1 then return JOINED, false, false, 7, #ROSTER, true, "CHANNEL_CATEGORY_CUSTOM" end end
SetSelectedDisplayChannel = function() end
C_ChatInfo.GetChannelRosterInfo = function(i, k) local r = ROSTER[k] if i == 1 and r then return r.name, false, false, r.guid end end
IsInInstance = function() return INSTANCE, INSTANCE and "party" or "none" end
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
ChatFrame_AddMessageEventFilter = function() end
function TAKE_OUTBOX() local o = OUTBOX; OUTBOX = {}; return o end
function MAX_PER_SECOND()
  local best = 0
  for i = 1, #SENDLOG do
    local n = 0
    for j = i, #SENDLOG do if SENDLOG[j] - SENDLOG[i] < 1.0 then n = n + 1 end end
    if n > best then best = n end
  end
  return best
end

-- Battle.net friends: the harness fills BNFRIENDS with { id = gameAccountID } of friends online in this game
BNFRIENDS = {}
BNGetNumFriends = function() return #BNFRIENDS end
C_BattleNet = {
  GetFriendAccountInfo = function(i) local f = BNFRIENDS[i] if f then return { gameAccountInfo = { isOnline = true, clientProgram = "WoW", gameAccountID = f.id } } end end,
  SendGameData = function(id, prefix, text) table.insert(OUTBOX, { prefix = prefix, text = text, kind = "BN", target = id }) return 0 end,
}

-- the group: the harness puts in GROUPMATES the names of the others in my party
GROUPMATES = {}
IsInGroup = function() return #GROUPMATES > 0 end
IsInRaid = function() return false end
UnitName = function(u) local i = type(u) == "string" and u:match("^party(%d)$") if i then return GROUPMATES[tonumber(i)] end return nil end
-- the guild: the harness puts in GUILDROSTER everyone of the same GUILDNAME ({ name, guid, online })
GUILDNAME = nil
GUILDROSTER = {}
IsInGuild = function() return GUILDNAME ~= nil end
GetNumGuildMembers = function() return #GUILDROSTER end
GetGuildRosterInfo = function(i)
  local r = GUILDROSTER[i]
  if not r then return nil end
  return r.name, "Membro", 1, 20, "Mago", "Zona", "", "", r.online, 0, "MAGE", 0, 0, false, false, 0, r.guid
end
C_GuildInfo = { GuildRoster = function() end }
