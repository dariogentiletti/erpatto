-- Er Patto: talking to the other addons, with no internet.
-- Transport: a hidden chat channel named from the code (password-protected). Where the channel can't carry addon
-- messages (WoW Forever answers NOT_ALLOWED_IN_CHANNEL) it is only the meeting place: its member list says who of
-- the patto is online, and the messages go to each of them as addon whispers.
-- The guild: when the patto's members are in my guild, the guild carries the addon messages to all of them at
-- once (one message instead of a whisper each, on any internal realm); only the members outside the guild still
-- get whispers. Who is in it comes from the guild roster, by character guid.
-- Sync: everyone keeps a copy of everything and passes on what others are missing ("passaparola"), a record in
-- pieces with their own versions (see "sync protocol" below).
-- Limits respected: 255-byte messages (chunked), ~1 message/s per prefix (token bucket), no sends inside instances.
local ADDON, ns = ...
local U, P = ns.U, ns.P
local C = {}
ns.C = C

local PREFIX = "ErPatto"
local MAXLEN = 240
local HELLO_EVERY = 300
C.HELLO_WHISPER = 120
local ONLINE_WINDOW = 420
-- the game lets ~10 addon messages go at once, then about one a second: we keep 6 of them for what can't wait
-- (a flash, a hello's answer asked for), the rest of the traffic goes at the steady pace
local BUCKET_MAX, REFILL, RESERVE = 10, 1.1, 6

local state, me, myName
local chanName, chanPw, chanId
local queue, tokens, lastTick = {}, BUCKET_MAX, nil
local partsIn = {}
local seen, nameOf = {}, {}
local whisperPeers = {} -- members who can only be reached by whisper (their channel failed)
local guildSet = {}     -- guid -> true: patto members in my guild (from its roster)
local guildOnline = {}  -- guid -> true: of those, the ones online now
local guildHeard = {}   -- guid -> clock: heard through the guild
local guildFail = false -- the game refused an addon message to the guild: whispers as before
local chanBlocked = false -- the channel is there, but addon messages in it are refused: whispers to the roster
local roster, rosterOK, displayIdx = {}, false, nil -- guid -> name of who is in the patto's channel now
-- names to start from when we know nobody yet: who invited us, or the name written next to the code
local seeds = {}
local recent = {}
local helloReplyAt = {}
local lastHelloAt = 0
local firstHeardAt -- the first message from a friend this session
local pendingSends = {}
local whispered = {}
local seq = 0
local warnedProto = false
local ticker, helloTicker
local selfDueAt

C.stats = { sent = 0, received = 0, dropped = 0, held = 0, mode = "spento" }

local function Clock() return GetTime() end

----------------------------------------------------------------------
-- lockdown: Midnight rules block addon messages in instances, encounters and PvP matches
----------------------------------------------------------------------
-- Only there: the game says it (InChatMessagingLockdown) and that's all we ask. Without that call, an old
-- client (Forever, classic: interface under 12) sends from a dungeon as from anywhere; holding everything there
-- left who logged in inside one with nothing (no caciare, no deaths: their hello never went out)
function C.InLockdown()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    return ok and (U.IsSecret(locked) or locked == true) or false
  end
  local toc = GetBuildInfo and select(4, GetBuildInfo())
  if type(toc) == "number" and toc < 120000 then return false end
  if IsInInstance then
    local inInstance = IsInInstance()
    if U.IsSecret(inInstance) then return true end
    if inInstance then return true end
  end
  return false
end

----------------------------------------------------------------------
-- channel
----------------------------------------------------------------------
local function CurrentChannelId()
  if not chanName or not GetChannelName then return nil end
  local id = GetChannelName(chanName)
  if U.IsSecret(id) or type(id) ~= "number" or id <= 0 then return nil end
  return id
end

local function HideChannel()
  if type(ChatFrame_RemoveChannel) ~= "function" then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    if f then pcall(ChatFrame_RemoveChannel, f, chanName) end
  end
end

-- WoW Forever (interface 1.6x): custom channels refuse addon messages
local function ForeverClient()
  if not GetBuildInfo then return false end
  local toc = select(4, GetBuildInfo())
  return type(toc) == "number" and toc >= 16000 and toc < 20000
end

function C.JoinChannel()
  if not chanName or type(JoinChannelByName) ~= "function" then C.stats.mode = "sussurri" return end
  if C.InLockdown() then return end
  pcall(JoinChannelByName, chanName, chanPw)
  C_Timer.After(3, function()
    chanId = CurrentChannelId()
    if chanId then
      HideChannel()
      C.stats.mode = (C.GuildOn and C.GuildOn()) and "gilda" or (chanBlocked and "sussurri" or "canale")
      U.Log("Comms", "canale pronto", chanId, chanBlocked and "(solo pe' trovasse: li messaggi vanno a sussurri)" or "")
      C.RefreshRoster()
    else
      C.stats.mode = "sussurri"
      U.Log("Comms", "canale nun disponibile: uso li sussurri")
    end
    C.Hello()
  end)
end

----------------------------------------------------------------------
-- the channel's member list: who of the patto is online right now (everyone in it runs the addon)
----------------------------------------------------------------------
local function FindDisplay()
  if not (chanName and GetNumDisplayChannels and GetChannelDisplayInfo) then return nil end
  local okn, n = pcall(GetNumDisplayChannels)
  if not okn or type(n) ~= "number" then return nil end
  for i = 1, math.min(n, 60) do
    local ok, name, header, _, number = pcall(GetChannelDisplayInfo, i)
    if ok and not header and type(name) == "string" and not U.IsSecret(name) then
      local low = name:lower()
      if low == chanName or low:match("^%d+%.%s*(.+)$") == chanName or (chanId and number == chanId) then return i end
    end
  end
  return nil
end

local newPeer -- set below: a hello to someone just arrived
local function ReadRoster()
  if not (displayIdx and C_ChatInfo and C_ChatInfo.GetChannelRosterInfo) then return end
  local ok, _, _, _, _, count = pcall(GetChannelDisplayInfo, displayIdx)
  count = ok and U.Plain(count, "number") or 0
  local out, got = {}, 0
  for k = 1, math.min(count, 80) do
    local okr, name, _, _, guid = pcall(C_ChatInfo.GetChannelRosterInfo, displayIdx, k)
    if okr and type(name) == "string" and type(guid) == "string" and not U.IsSecret(name) and not U.IsSecret(guid) then
      out[guid] = name
      got = got + 1
    end
  end
  if got == 0 then return end
  local now = Clock()
  for g, name in pairs(out) do
    if g ~= me then
      nameOf[g] = name
      seen[g] = seen[g] and math.max(seen[g], now) or now
      if not roster[g] and newPeer then newPeer(g, name) end
    end
  end
  if not rosterOK then U.Log("Comms", "lista der canale:", got, "presenti") end
  roster, rosterOK = out, true
end

function C.RefreshRoster()
  if not chanName then return end
  displayIdx = FindDisplay()
  if not displayIdx then return end
  -- the game sends the list of the channel picked in the Chat Channels window; leave it alone while it's open
  local open = ChannelFrame and ChannelFrame.IsShown and ChannelFrame:IsShown()
  if not open and SetSelectedDisplayChannel then pcall(SetSelectedDisplayChannel, displayIdx) end
  ReadRoster()
end

function C.OnRosterUpdate(index)
  if displayIdx and index == displayIdx then ReadRoster() end
end

function C.OnChannelCount(index)
  if displayIdx and index == displayIdx then C.RefreshRoster() end
end

-- "NOT_ALLOWED_IN_CHANNEL" for our channel: from now on the channel only says who is there
function C.OnChannelNotice(notice, _, _, _, _, _, _, index, baseName)
  if U.IsSecret(notice) or notice ~= "NOT_ALLOWED_IN_CHANNEL" or chanBlocked then return end
  local mine = (type(baseName) == "string" and not U.IsSecret(baseName) and baseName:lower() == chanName)
    or (chanId and index == chanId)
  if not mine then return end
  chanBlocked = true
  C.stats.mode = "sussurri"
  U.Log("Comms", "er canale nun porta li messaggi de l'addon: mo' uso li sussurri")
  C.RefreshRoster()
  C_Timer.After(1.5, function() C.Hello() end)
end

----------------------------------------------------------------------
-- sending
----------------------------------------------------------------------
-- a quick message (X: a duel, a gufata, the strings pulled...) goes before the pieces of a record waiting to go
local urgentAt = 0
local function Push(kind, target, text, urgent, key, at)
  if #queue > 300 then C.stats.dropped = C.stats.dropped + 1 return end
  if at and not urgent then
    table.insert(queue, math.max(urgentAt + 1, math.min(at, #queue + 1)), { kind, target, text, key })
  elseif urgent then
    urgentAt = math.min(urgentAt + 1, #queue + 1)
    table.insert(queue, urgentAt, { kind, target, text, key })
  else
    queue[#queue + 1] = { kind, target, text, key }
  end
end

-- a newer copy of the same thing to the same place (my record, the settings, a hello) replaces the one still waiting
-- (the new copy takes the old one's place in the line: a hello asked again doesn't send it back to the end)
local function Supersede(key)
  local at
  for i = #queue, 1, -1 do
    if queue[i][4] == key then
      table.remove(queue, i)
      if i <= urgentAt then urgentAt = urgentAt - 1 end
      at = i
    end
  end
  return at
end

-- who is in my group, by whole name (looked at again every few seconds)
local groupAt, groupSet = -10, {}
local function GroupKind()
  local ok, grouped = pcall(IsInGroup or function() return false end)
  if not ok or grouped ~= true then return nil end
  local okr, raid = pcall(IsInRaid or function() return false end)
  return (okr and raid == true) and "RAID" or "PARTY"
end
local function InMyGroup(name)
  if type(name) ~= "string" then return false end
  local now = Clock()
  if now - groupAt > 3 then
    groupAt, groupSet = now, {}
    local kind = GroupKind()
    if kind then
      for i = 1, kind == "RAID" and 40 or 4 do
        local n = U.FullName((kind == "RAID" and "raid" or "party") .. i)
        if n then groupSet[U.Short(n)] = true end
      end
    end
  end
  return groupSet[U.Short(name)] == true
end
C.InMyGroup = InMyGroup

-- a friend reached over Battle.net is addressed "bn:<game account>": their messages go by SendGameData;
-- a friend in my group gets it over the group (it always arrives, whatever the name)
local function Enqueue(kind, target, body, urgent, key)
  if kind == "WHISPER" and type(target) == "string" and not target:match("^bn:") and InMyGroup(target) then
    kind, target = GroupKind() or kind, nil
    if key then key = key:gsub(">.*$", "") .. ">group" end
  end
  local bn = type(target) == "string" and tonumber(target:match("^bn:(%d+)$"))
  if bn then kind, target = "BN", bn end
  local at
  if key then
    -- a whole record also makes the changes still waiting useless
    key = key .. ">" .. tostring(target)
    at = Supersede(key) or at
  end
  if #body <= MAXLEN then Push(kind, target, "!" .. body, urgent, key, at) return end
  seq = seq % 999 + 1
  local size = MAXLEN - 14
  local n = math.ceil(#body / size)
  for i = 1, n do
    Push(kind, target, "#" .. seq .. "~" .. i .. "~" .. n .. "~" .. body:sub((i - 1) * size + 1, i * size), urgent, key, at and (at + i - 1))
  end
end

-- the guild as the patto's channel: I'm in a guild, the game didn't refuse it, and someone of the patto is in it
local function GuildOn()
  if guildFail or not (IsInGuild and IsInGuild()) then return false end
  return next(guildSet) ~= nil
end
C.GuildOn = GuildOn
-- the patto's members in my guild, from its roster (by character guid; a name alone only when it's whole)
function C.ReadGuild()
  if not (state and IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then guildSet, guildOnline = {}, {} return end
  local ok, n = pcall(GetNumGuildMembers)
  if not ok or type(n) ~= "number" or n <= 0 then return end
  local byName = {}
  for g, rec in pairs(state.members) do if type(rec.name) == "string" and rec.name:find(" ") then byName[rec.name] = g end end
  local set, on = {}, {}
  for i = 1, math.min(n, 1000) do
    local okr, name, _, _, _, _, _, _, _, online, _, _, _, _, _, _, _, guid = pcall(GetGuildRosterInfo, i)
    if okr then
      local g = type(guid) == "string" and not U.IsSecret(guid) and state.members[guid] and guid or nil
      if not g and type(name) == "string" and not U.IsSecret(name) then g = byName[name] or byName[(name:gsub("%-.*$", ""))] end
      if g and g ~= me then
        set[g] = true
        if online == true then on[g] = true end
      end
    end
  end
  local had = next(guildSet) ~= nil
  -- who spoke through the guild lately is in it, even before the roster knows him as one of the patto
  for g, t in pairs(guildHeard) do if g ~= me and Clock() - t < ONLINE_WINDOW then set[g] = true on[g] = true end end
  guildSet, guildOnline = set, on
  local count = 0
  for _ in pairs(set) do count = count + 1 end
  if not had and count > 0 then U.Log("Comms", "gilda: " .. count .. " der patto ce stanno, li messaggi passano da la gilda") end
  if count > 0 and not guildFail then C.stats.mode = "gilda" end
end
-- the guild's roster: asked at the start and once a minute (the answer comes as GUILD_ROSTER_UPDATE)
function C.AskGuild()
  if not (IsInGuild and IsInGuild()) then return end
  if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) elseif GuildRoster then pcall(GuildRoster) end
  C.ReadGuild()
end
function C.InGuild(guid) return GuildOn() and guildSet[guid] == true end
function C.GuildOnline(guid) return GuildOn() and guildOnline[guid] == true end

-- who to whisper: who is in the patto's channel (when its list is known), and who wrote to us lately;
-- without the list, hellos go to every member we know by name. The ones the guild reaches are left out.
local function WhisperTargets(isHello)
  local out, done = {}, {}
  local guild = GuildOn()
  local function add(who, g)
    if guild and g and guildSet[g] then return end
    if type(who) == "string" and who ~= "" and not done[who] then done[who] = true out[#out + 1] = who end
  end
  for g, who in pairs(roster) do if g ~= me then add(who, g) end end
  local now = Clock()
  -- whoever wrote to us lately, member or not yet (someone just come in with the code)
  for g, t in pairs(seen) do
    if g ~= me and nameOf[g] and now - t < ONLINE_WINDOW then add(nameOf[g], g) end
  end
  -- a hello goes to every member we know, online or not: on Forever the channel splits the realm in islands
  -- (each internal realm its own copy of the channel), whispers reach everyone; the offline ones' "no player
  -- named" is hidden (SystemFilter)
  for g, rec in pairs(state and state.members or {}) do
    if g ~= me then
      local who = nameOf[g] or rec.name
      if (seen[g] and now - seen[g] < ONLINE_WINDOW) or isHello then add(who, g) end
    end
  end
  if isHello then for who in pairs(seeds) do if who ~= myName then add(who) end end end
  return out
end

function C.AddSeed(name)
  if type(name) ~= "string" then return end
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" or name == myName then return end
  seeds[name] = true
  if ns.db and state then
    ns.db.seeds = type(ns.db.seeds) == "table" and ns.db.seeds or {}
    ns.db.seeds[state.code] = ns.db.seeds[state.code] or {}
    ns.db.seeds[state.code][name] = true
  end
  if state and C.HelloTo then C.HelloTo(name) end
end

-- no channel to speak in (refused, as on Forever, or never joined): every message is whispered
local function Whispering()
  if GuildOn() then return false end
  return chanBlocked or not CurrentChannelId()
end
C.Whispering = Whispering

local function Broadcast(body, urgent, key)
  chanId = CurrentChannelId()
  if GuildOn() then
    -- the guild once (everyone of the patto in it), then my group and a whisper to the members outside it
    Enqueue("GUILD", nil, body, urgent, key and (key .. ">guild"))
    local gk = GroupKind()
    local out = WhisperTargets(body:sub(1, 1) == "H")
    if gk and #out > 0 then Enqueue(gk, nil, body, urgent, key and (key .. ">group")) end
    for _, who in ipairs(out) do
      if not (gk and InMyGroup(who)) then Enqueue("WHISPER", who, body, urgent, key) end
    end
    return
  end
  if chanBlocked or not chanId then
    -- my group once (everyone in it), then a whisper to each one outside it
    local gk = GroupKind()
    if gk then Enqueue(gk, nil, body, urgent, key and (key .. ">group")) end
    for _, who in ipairs(WhisperTargets(body:sub(1, 1) == "H")) do
      if not (gk and InMyGroup(who)) then Enqueue("WHISPER", who, body, urgent, key) end
    end
    return
  end
  if chanId then
    Enqueue("CHANNEL", tostring(chanId), body, urgent, key)
    -- members stuck on whispers still need to hear us
    local now = Clock()
    for g, who in pairs(whisperPeers) do
      if seen[g] and now - seen[g] < ONLINE_WINDOW then Enqueue("WHISPER", who, body, urgent, key) end
    end
    return
  end
end

local function Body(kind, data)
  return kind .. "~" .. U.Serialize({ f = me, c = state and state.code, x = data })
end

-- what can be replaced by a newer copy while it waits: a member's record, the settings, the capi, the bans, a hello
local function KeyOf(kind, data)
  if kind == "M" then return type(data) == "table" and type(data.guid) == "string" and ("M:" .. data.guid) or nil end
  if kind == "Y" or kind == "S" or kind == "A" or kind == "B" then return kind end
  return nil
end

function C.Send(kind, data, urgent)
  if not state then return end
  Broadcast(Body(kind, data), kind == "X" or urgent == true, KeyOf(kind, data))
end

local function ResultIsThrottle(res)
  if res == nil or U.IsSecret(res) then return false end
  local enum = Enum and Enum.SendAddonMessageResult
  if type(enum) == "table" then
    for k, v in pairs(enum) do
      if v == res and tostring(k):find("Throttle") then return true end
    end
  end
  return false
end

local function ResultOk(res)
  if res == nil or res == true then return true end
  if U.IsSecret(res) then return false end
  local enum = Enum and Enum.SendAddonMessageResult
  if type(enum) == "table" and enum.Success ~= nil then return res == enum.Success end
  return res == 0
end

local function Tick()
  local now = Clock()
  if lastTick then tokens = math.min(BUCKET_MAX, tokens + (now - lastTick) / REFILL) end
  lastTick = now
  -- delayed replies
  for i = #pendingSends, 1, -1 do
    local p = pendingSends[i]
    if now >= p.at then
      table.remove(pendingSends, i)
      -- skip only if someone else sent the same thing after we decided to send it
      local heard = recent[p.key]
      if not heard or heard < p.created then
        recent[p.key] = now
        p.fn()
      end
    end
  end
  if selfDueAt and now >= selfDueAt then
    selfDueAt = nil
    C.SendSelf()
  end
  if #queue == 0 then return end
  if C.InLockdown() then C.stats.held = #queue return end
  C.stats.held = 0
  while #queue > 0 and tokens >= ((urgentAt > 0) and 1 or (1 + RESERVE)) do
    local item = table.remove(queue, 1)
    urgentAt = math.max(0, urgentAt - 1)
    local ok, res
    if item[1] == "BN" then
      if C_BattleNet and C_BattleNet.SendGameData then ok, res = pcall(C_BattleNet.SendGameData, item[2], PREFIX, item[3]) end
    else
      ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item[3], item[1], item[2])
    end
    if ok and ResultIsThrottle(res) then
      table.insert(queue, 1, item)
      tokens = 0
      C.stats.throttled = (C.stats.throttled or 0) + 1
      break
    end
    tokens = tokens - 1
    if ok and ResultOk(res) then
      C.stats.sent = C.stats.sent + 1
      if item[1] == "WHISPER" then whispered[item[2]] = now end
    else
      C.stats.dropped = C.stats.dropped + 1
      U.Log("Comms", "invio fallito", item[1], item[2], ok and res or "errore")
      if item[1] == "CHANNEL" then chanId = nil end
      -- the guild refused it: back to whispers for this session
      if item[1] == "GUILD" and not guildFail then
        guildFail = true
        C.stats.mode = "sussurri"
        U.Log("Comms", "la gilda nun porta li messaggi: torno ai sussurri")
      end
    end
  end
end

----------------------------------------------------------------------
-- sync protocol (sync 2). A record travels in pieces (Patto.lua, P.PIECES), each with its own version, given
-- by its owner when it changes:
--   Y  hello: who I am, the versions of the patto's rules, and for each member what I hold of each piece
--   P  pieces: some pieces of one member's record with their versions; taken by any copy holding them older
--   M  a whole record: an old life given back, a lost record to a new PC, or from an addon before sync 2
-- My changes go out as pieces as they happen: the ones to know at once (a ding, a death, a duel, a "Ce sto")
-- first in the line, in a second; the rest within a minute. A hello (at login, every few minutes, after a
-- loading screen) finds what anyone missed: whoever holds a piece newer than the asker's sends it, through the
-- guild, the owner first; the others hear it go and stay quiet. Nothing else: no deltas, no flashes, no relays.
----------------------------------------------------------------------
local selfUrgent
local Responder
local stillMissing = {} -- "asker>guid" -> when first seen missing from their hello
local heard = {}    -- "guid:piece" -> { v, at }: the newest of a piece that went by (mine included)
local pending = {}  -- guid -> { at, pieces }: pieces of someone not known yet, waiting for the one saying who
local function NoteHeard(g, p, v)
  local k = g .. ":" .. p
  local h = heard[k]
  if not h or v >= h.v then heard[k] = { v = v, at = Clock() } end
end

local function HelloData()
  local mine = state.members[me]
  return { p = ns.PROTO, ver = ns.VERSION, n = myName, sv = state.settings.v or 0, av = state.admins.v or 0,
    bv = state.bans.v or 0, m = P.Vectors(state), fr = mine and mine.fresh and true or nil,
    fb = mine and mine.fresh and tonumber(mine.base) or nil, sk = 1,
    lf = type(state.left) == "table" and next(state.left) and state.left or nil }
end

function C.Hello()
  if not state then return end
  lastHelloAt = Clock()
  C.Send("Y", HelloData())
end

-- someone just came into the patto's channel: a hello to them alone (they answer with what we miss, and the other way)
local introduced = {}
newPeer = function(guid, name, urgent)
  if not state or type(name) ~= "string" then return end
  -- through the guild everyone hears my hello anyway: a whisper only for who is outside it
  if not Whispering() and not (GuildOn() and not guildSet[guid]) then return end
  if introduced[guid] and Clock() - introduced[guid] < 60 then return end
  introduced[guid] = Clock()
  U.Log("Comms", urgent and "novo ner patto:" or "ner canale c'è", name)
  Enqueue("WHISPER", name, Body("Y", HelloData()), urgent == true, "Y")
end

-- my pieces as I last gave them (a checksum each), kept between sessions: what changed while nothing could go
-- (logged out first) still goes at the next login
-- (keys in order: the same piece read back from the saved file, its tables rebuilt, gives the same checksum)
local function Canon(v, depth)
  if type(v) ~= "table" then return U.Serialize(v) end
  if (depth or 0) > 6 then return "N" end
  local keys = {}
  for k, x in pairs(v) do if (type(k) == "string" or type(k) == "number") and type(x) ~= "function" then keys[#keys + 1] = k end end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) == "number" end
    return a < b
  end)
  local parts = {}
  for i, k in ipairs(keys) do parts[i] = U.Serialize(k) .. "=" .. Canon(v[k], (depth or 0) + 1) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function Sum(piece)
  local str = Canon(piece)
  local h = 5381
  for i = 1, #str do h = (h * 33 + str:byte(i)) % 4294967296 end
  return h .. ":" .. #str
end
local sumsHere = {}
local function Sums()
  local k = tostring(state.code) .. ":" .. tostring(me)
  if not ns.db then sumsHere[k] = sumsHere[k] or {} return sumsHere[k] end
  ns.db.sentSum = type(ns.db.sentSum) == "table" and ns.db.sentSum or {}
  ns.db.sentSum[k] = type(ns.db.sentSum[k]) == "table" and ns.db.sentSum[k] or {}
  return ns.db.sentSum[k]
end
-- (the tests move them from one PC to another, as a WTF folder would)
function C.SentSums(t)
  if t and state then local s = Sums() for k in pairs(s) do s[k] = nil end for k, v in pairs(t) do s[k] = v end end
  return state and Sums() or nil
end
-- what can't wait (who and what level, a death, a duel, the caciare, la gogna, le sfide)
-- (the counters right after, not ahead of the others' urgent pieces: a death carries its count on the stone)
C.URGENT_PIECE = { b = true, r = true, f = true, d = true, a = true, e = true, y = true, g = true, s = true }
-- while my record is fresh (a friend may hold it newer): what's mine for sure goes; never the counters, which a
-- record started on a new PC would send back at zero
local FRESH_OK = { b = true, r = true, f = true, d = true, a = true, e = true, y = true, g = true, s = true }
-- the pieces of my record that changed since I last gave them, each with a new version. only: just those pieces
local function ChangedPieces(only)
  local rec = state.members[me]
  if not rec then return {} end
  P.InitVersions(rec)
  local sums = Sums()
  local out = {}
  for _, p in ipairs(P.PIECE_ORDER) do
    if not only or only[p] then
      -- (the checksum with the version it went with: a record started again, at version zero, goes again)
      local sum = Sum(P.PieceData(rec, p)) .. "@" .. tostring(rec.sv[p] or 0)
      -- never given from this PC (a new one, or the first time with sync 2) while fresh: what it holds now is the
      -- starting point, not a change (a blank record on a new PC must not go over the friends' real copies)
      -- (and once it's no more fresh: a piece never given a version, that nobody has, goes now)
      if sums[p] == nil and rec.fresh then sums[p] = sum
      elseif sums[p] ~= sum or (not rec.fresh and (rec.sv[p] or 0) == 0) then
        rec.sv[p] = math.max(math.floor(U.Now()), (rec.sv[p] or 0) + 1)
        rec.up = math.max(rec.up or 0, rec.sv[p])
        sums[p] = Sum(P.PieceData(rec, p)) .. "@" .. tostring(rec.sv[p])
        out[#out + 1] = p
      end
    end
  end
  return out
end

-- pieces of one member's record, in messages of about a kilobyte (the small ones together, in their order)
-- (who, a death, the counters: one message, so whoever hears it has them all at once)
local PACK = 1400
local function SendPieces(g, list, to, urgent)
  local rec = state.members[g]
  if not rec or #list == 0 then return end
  local batches, cur, size = {}, nil, 0
  for _, p in ipairs(list) do
    local item = { v = rec.sv and rec.sv[p] or 0, d = P.PieceData(rec, p) }
    local n = #U.Serialize(item)
    if cur and size + n > PACK then batches[#batches + 1] = cur cur, size = nil, 0 end
    cur = cur or { g = g, p = {}, k = {} }
    cur.p[p] = item
    cur.k[#cur.k + 1] = p
    size = size + n
    NoteHeard(g, p, item.v)
  end
  if cur then batches[#batches + 1] = cur end
  for _, data in ipairs(batches) do
    local key = "P:" .. g .. ":" .. table.concat(data.k)
    data.k = nil
    if to then Enqueue("WHISPER", to, Body("P", data), urgent == true, key)
    else Broadcast(Body("P", data), urgent == true, key) end
  end
end
C.SendPieces = SendPieces

-- my changes: the urgent pieces at the head of the line, the rest after. While my record is "fresh" (just come
-- in: a friend may hold it newer, played on another computer) only the urgent ones go; the rest waits for them
function C.SendSelf()
  if not state or not state.members[me] then return end
  local rec = state.members[me]
  local list = ChangedPieces(rec.fresh and FRESH_OK or nil)
  -- while fresh, the others (the counters...) go too, but "weak": with the version they had, never a new one
  -- (at least 1). A friend holding a real copy keeps his; one who has none takes them. A new one when fresh ends
  if rec.fresh then
    local weak = {}
    local sums = Sums()
    for _, p in ipairs(P.PIECE_ORDER) do
      local sum = Sum(P.PieceData(rec, p)) .. "@" .. tostring(rec.sv[p] or 0)
      if sums[p] == nil then sums[p] = sum
      elseif not FRESH_OK[p] and sums[p] ~= sum then
        if (rec.sv[p] or 0) < 1 then rec.sv[p] = 1 end
        weak[#weak + 1] = p
      end
    end
    SendPieces(me, weak, nil, false)
  end
  local now, later = {}, {}
  for _, p in ipairs(list) do
    if selfUrgent and C.URGENT_PIECE[p] then now[#now + 1] = p else later[#later + 1] = p end
  end
  selfUrgent = nil
  SendPieces(me, now, nil, true)
  SendPieces(me, later, nil, false)
end

-- Send my record after `delay` seconds (XP ticks wait longer than dings or team changes).
function C.MarkSelfDirty(delay, urgent)
  if urgent then selfUrgent = true end
  local due = Clock() + (delay or 4)
  if not selfDueAt or due < selfDueAt then selfDueAt = due end
end

local function Schedule(key, fn, after)
  for _, p in ipairs(pendingSends) do if p.key == key then return end end
  pendingSends[#pendingSends + 1] = { key = key, created = Clock(), at = Clock() + (after or (0.5 + math.random() * 2.5)), fn = fn }
end

-- to one player only (whispered): the answers to a hello on Forever go to who asked, not to everyone
function C.SendTo(kind, data, who, urgent)
  if not state then return end
  if not who then C.Send(kind, data, urgent) return end
  Enqueue("WHISPER", who, Body(kind, data), urgent == true, KeyOf(kind, data))
end

function C.HelloTo(who, urgent)
  if not state then return end
  if who then Enqueue("WHISPER", who, Body("Y", HelloData()), urgent == true, "Y") else C.Hello() end
end

-- the patto's rules: small, rare, and without them who just came in can't start: first in the line
local function SendPiece(kind, to)
  if kind == "S" then C.SendTo("S", state.settings, to, true)
  elseif kind == "A" then C.SendTo("A", state.admins, to, true)
  elseif kind == "B" then C.SendTo("B", state.bans, to, true) end
end

-- who answers for member g to one asking: the owner when he's here with this addon, else one of those here with it
-- (me among them), picked by g. Everyone sees the same ones here (the guild's list, and who was heard), so one
-- answers; when two see it differently, two answer (the second goes for nothing), when none, the next hello asks
-- again
local sync2 = {} -- guid -> clock: heard speak sync 2 (an older addon can't answer)
local function Here(g)
  return g == me or (C.Around(g) and sync2[g] ~= nil and Clock() - sync2[g] < ONLINE_WINDOW)
end
Responder = function(g, asker, notOwner)
  if not notOwner and g ~= asker and Here(g) then return g end
  local list = {}
  for x in pairs(state.members) do if x ~= asker and x ~= g and Here(x) then list[#list + 1] = x end end
  if #list == 0 then return nil end
  table.sort(list)
  local hsh = 0
  for i = 1, #g do hsh = (hsh * 31 + g:byte(i)) % 1000003 end
  return list[(hsh % #list) + 1]
end

local prevSentAt = {}
local function OnHello(from, h, sender)
  if type(h) ~= "table" then return end
  if type(h.p) == "number" and h.p > ns.PROTO and not warnedProto then
    warnedProto = true
    U.Say("quarcuno usa 'na versione più nova. Aggiorna l'addon su CurseForge.")
  end
  local theyNewer = false
  -- the answers go through the guild when they're in it (everyone hears them: one answer for all); by whisper
  -- to them alone otherwise (on Forever without the guild, or one outside it)
  local viaGuild = GuildOn() and guildSet[from]
  local to = (not viaGuild and (Whispering() or GuildOn()) and type(sender) == "string") and sender or nil
  local tag = to and (">" .. to) or ""
  local function cmp(kind, mine, theirs)
    theirs = type(theirs) == "number" and theirs or 0
    if mine > theirs then
      Schedule(kind .. ":" .. mine .. tag, function() SendPiece(kind, to) end)
    elseif theirs > mine then
      theyNewer = true
    end
  end
  cmp("S", state.settings.v or 0, h.sv)
  cmp("A", state.admins.v or 0, h.av)
  cmp("B", state.bans.v or 0, h.bv)
  -- "my record is new on this PC" and I hold a real copy of it, newer than theirs: it goes back to them whole
  if h.fr == true then
    local theirs = state.members[from]
    if theirs and not theirs.fresh and (theirs.up or 0) > (tonumber(h.fb) or 0) then
      Schedule("R:" .. from .. tag, function()
        if state.members[from] and not state.members[from].fresh then C.SendTo("M", state.members[from], to) end
      end)
    end
  end
  -- an old life of theirs I keep aside (they left, were cacciati, started again): it goes back to them
  local pv = type(state.prev) == "table" and state.prev[from]
  if pv and (not state.members[from] or P.Behind(state.members[from], pv)) then
    local last = prevSentAt[from]
    if not last or Clock() - last > 120 then
      prevSentAt[from] = Clock()
      U.Log("Comms", "rimanno a", sender or from, "li dati de prima")
      Schedule("PV:" .. from .. tag, function()
        local p = type(state.prev) == "table" and state.prev[from]
        if p and to then Enqueue("WHISPER", to, Body("M", p), false, "PV:" .. from)
        elseif p then Broadcast(Body("M", p), false, "PV:" .. from) end
      end)
    end
  end
  -- who left: gone here too (and their old record no more asked for)
  if type(h.lf) == "table" then
    local n = 0
    for g, up in pairs(h.lf) do
      n = n + 1
      if n > P.MAX_LEFT then break end
      local rec = state.members[g]
      if g ~= me and P.MarkLeft(state, g, up) then
        if rec then ns.Fire("MemberLeft", rec) end
        ns.Fire("StateChanged", state, "L")
      end
    end
  end
  -- the pieces: mine as of now first (what changed and waited gets its version), then piece by piece
  if selfDueAt then selfDueAt = nil C.SendSelf() end
  local m = type(h.m) == "table" and h.m or {}
  for g, rec in pairs(state.members) do
    local theirs = m[g] and P.Unvector(m[g])
    local mine = g == me
    local list = {}
    for _, p in ipairs(P.PIECE_ORDER) do
      local v = rec.sv and rec.sv[p] or 0
      if not theirs or v > (theirs[p] or 0) then list[#list + 1] = p end
    end
    -- one of us answers for each member: its owner when he's here, else one picked by the member (so a whole
    -- patto to give is shared out among all who are online, each sending some, at the same time)
    -- (through the guild, the others too, a few seconds later, if nobody did: two who see the patto differently
    -- could each think it's the other's turn)
    local picked = #list > 0 and g ~= from and Responder(g, from) == me
    -- (and by whisper, where nobody hears the others: when the same asker still lacks it a minute and a half
    -- after asking the first time, whoever has it gives it)
    local k = from .. ">" .. g
    if #list == 0 then stillMissing[k] = nil elseif not stillMissing[k] then stillMissing[k] = Clock() end
    local late = stillMissing[k] and Clock() - stillMissing[k] > 90
    -- (by whisper, a member they don't have at all also goes from one of us besides its owner: the owner may not
    -- reach them, as one only on Battle.net)
    local backup = #list > 0 and g ~= from and not picked
      and (not to or late or (not theirs and g ~= me and Responder(g, from, true) == me))
    if picked or backup then
      local delay = picked and (mine and (0.2 + math.random() * 0.8) or (0.5 + math.random() * 1.5)) or (15 + math.random() * 10)
      local asked = Clock()
      Schedule("Y>" .. g .. tag .. ":" .. math.floor(asked / 10), function()
        local r = state.members[g]
        if not r then return end
        local still = {}
        for _, p in ipairs(list) do
          local v = r.sv and r.sv[p] or 0
          local hp = heard[g .. ":" .. p]
          -- through the guild: someone else gave it meanwhile, as new as mine (or newer): it's done
          if to or not (hp and hp.at >= asked and hp.v >= v) then still[#still + 1] = p end
        end
        -- (who and what level, the counters... at the head of my line: someone is waiting for them; the rest after)
        local now, later = {}, {}
        for _, p in ipairs(still) do if C.URGENT_PIECE[p] then now[#now + 1] = p else later[#later + 1] = p end end
        SendPieces(g, now, to, true)
        SendPieces(g, later, to, false)
      end, delay)
    end
  end
  for g, s in pairs(m) do
    if g ~= me and not P.IsBanned(state, g) then
      local rec = state.members[g]
      local theirs = P.Unvector(s)
      if theirs and not rec then
        local top = 0
        for _, v in pairs(theirs) do top = math.max(top, v) end
        if not P.HasLeft(state, g, top) then theyNewer = true end
      elseif theirs then
        for _, p in ipairs(P.PIECE_ORDER) do
          if (theirs[p] or 0) > (rec.sv and rec.sv[p] or 0) then theyNewer = true break end
        end
      end
    end
  end
  if theyNewer then
    local last = helloReplyAt[from]
    if not last or Clock() - last > 20 then
      helloReplyAt[from] = Clock()
      -- someone I never heard of (just come in): my hello goes first, so their record comes at once
      local stranger = not state.members[from]
      Schedule("H:" .. (to or "guild") .. ":" .. math.floor(Clock() / 20), function()
        -- (through the guild everyone hears my hello and answers it: one every half minute is enough for all)
        if not to and Clock() - lastHelloAt < 30 then return end
        C.HelloTo(to, stranger)
      end, 1 + math.random() * 3)
    end
  end
end

-- pieces arrived: on my copies, in their order (the one saying who they are first); the events once per message
local function OnPieces(from, data, sender)
  if type(data) ~= "table" or type(data.g) ~= "string" or type(data.p) ~= "table" then return false end
  local g = data.g
  local before = state.members[g]
  local got = false
  local function take(p, item)
    if type(item) ~= "table" or type(item.v) ~= "number" then return end
    NoteHeard(g, p, item.v)
    local ok = P.MergePiece(state, g, p, item.v, type(item.d) == "table" and item.d or {}, me)
    if ok == "nobase" then
      local w = pending[g]
      if not w or Clock() - w.at > 120 then w = { at = Clock(), pieces = {} } pending[g] = w end
      w.pieces[p] = item
    elseif ok then
      got = true
      C.stats.pieces = (C.stats.pieces or 0) + 1
    end
  end
  for _, p in ipairs(P.PIECE_ORDER) do take(p, data.p[p]) end
  if state.members[g] and pending[g] then
    local w = pending[g]
    pending[g] = nil
    for _, p in ipairs(P.PIECE_ORDER) do if w.pieces[p] then take(p, w.pieces[p]) end end
  end
  if not got then return false end
  local rec = state.members[g]
  if g == me then
    -- my record, lost on this PC, coming back from the friends (and from me it goes on as mine)
    if before and before.base == nil then ns.Fire("SelfRestored", rec) end
    C.MarkSelfDirty(1)
    return true
  end
  if before and before.lv and rec.lv and rec.lv > before.lv then ns.Fire("MemberDing", rec, before.lv) end
  if before and rec.team ~= before.team then ns.Fire("MemberSwitched", rec, before.team) end
  if not before and not seen[g] then newPeer(g, nameOf[g] or rec.name) end
  -- someone new, heard from them directly: the others online hear of them in one message, and say hello at once
  if not before and g == from and (Whispering() or GuildOn()) and type(sender) == "string" then
    Broadcast(Body("N", { g = from, n = sender }), true, nil)
  end
  ns.Fire("MemberUpdated", rec, before or nil)
  return true
end

local invitesOut = {}
-- who I invited and when (lower case names), kept half an hour: a cacciato I invite again may come back
local invitedAt = {}

local acksSfotto = {}
function C.AcksSfotto(guid) return acksSfotto[guid] == true end
local oldSeen = {}
local function Handle(body, sender, channel)
  local kind, payload = body:match("^(%u)~(.*)$")
  if not kind then return end
  local msg = U.Deserialize(payload)
  if type(msg) ~= "table" or type(msg.f) ~= "string" or msg.f == me then return end
  -- another patto's message (the group or the guild carry everyone's)
  if type(msg.c) == "string" and msg.c ~= state.code then return end
  local from = msg.f
  if P.IsBanned(state, from) then
    -- cacciato, but I (capo or vice) invited them again in the last half hour: they're back
    local asked = type(sender) == "string" and invitedAt[sender:lower()]
    if not (asked and Clock() - asked < 1800 and P.Unban(state, me, from)) then return end
    U.Log("Comms", sender, "era stato cacciato: l'hai reinvitato, mo' po' rientrà")
  end
  C.stats.received = C.stats.received + 1
  local wasOn = seen[from] and Clock() - seen[from] < ONLINE_WINDOW
  seen[from] = Clock()
  firstHeardAt = firstHeardAt or Clock()
  if type(sender) == "string" then nameOf[from] = sender end
  -- heard through the guild: they're in it, the guild reaches them (before its roster says so)
  -- (a newcomer too, not in my list yet: the guild reaches him, the answers go there, once for everyone)
  if channel == "GUILD" then
    guildHeard[from] = Clock()
    if not guildSet[from] then guildSet[from] = true guildOnline[from] = true end
  end
  -- back after a while (or heard for the first time): what was waiting for them goes now (a sfottò)
  if not wasOn then ns.Fire("PeerOnline", from) end
  if channel == "WHISPER" and type(sender) == "string" and CurrentChannelId() and not chanBlocked then
    whisperPeers[from] = sender
  elseif channel == "CHANNEL" then
    whisperPeers[from] = nil
  end
  local data = msg.x
  local changed = false
  if kind == "Y" or kind == "P" then sync2[from] = Clock() end
  if kind == "Y" then
    if type(data) == "table" and data.sk then acksSfotto[from] = true end
    OnHello(from, data, sender)
    if not state.members[from] and type(data) == "table" and type(data.n) == "string" then
      ns.Fire("PeerSeen", from)
    end
  elseif kind == "P" then
    changed = OnPieces(from, data, sender)
    if changed then kind = "M" end
  elseif kind == "H" then
    -- an addon before sync 2: it can't read us, nor we it; they're told to update when they see a newer one
    if type(data) == "table" and data.sk then acksSfotto[from] = true end
    if not oldSeen[from] or Clock() - oldSeen[from] > 1800 then
      oldSeen[from] = Clock()
      U.Log("Comms", tostring(sender), "c'ha 'na versione vecchia de l'addon (" .. tostring(type(data) == "table" and data.ver or "?") .. ")")
      -- a hello in their language, once in a while: it tells them a newer addon is around (they're told to
      -- update), and they still hand over the whole records they have newer than mine (taken as "M")
      local d = {}
      for g, r in pairs(state.members) do d[g] = r.up or 0 end
      local old = { p = ns.PROTO, ver = ns.VERSION, n = myName, sv = state.settings.v or 0, av = state.admins.v or 0,
        bv = state.bans.v or 0, d = d, sk = 1 }
      if type(sender) == "string" and not (GuildOn() and guildSet[from]) then C.SendTo("H", old, sender)
      else C.Send("H", old) end
    end
  elseif kind == "S" then
    changed = P.MergeSettings(state, data)
    if type(data) == "table" and data.v then recent["S:" .. data.v] = Clock() end
  elseif kind == "A" then
    changed = P.MergeAdmins(state, data)
    if type(data) == "table" and data.v then recent["A:" .. data.v] = Clock() end
  elseif kind == "B" then
    changed = P.MergeBans(state, data)
    if type(data) == "table" and data.v then recent["B:" .. data.v] = Clock() end
  elseif kind == "L" then
    -- they left the patto: out of the list, and their old record stays out
    if type(data) == "table" and data.g == from and type(data.up) == "number" then
      local rec = state.members[from]
      changed = P.MarkLeft(state, from, data.up)
      if changed and rec then ns.Fire("MemberLeft", rec) end
    end
  elseif kind == "N" then
    -- a friend tells me someone new is in the patto: a hello to them now (they answer with their record)
    if type(data) == "table" and type(data.g) == "string" and type(data.n) == "string" and data.g ~= me
      and not state.members[data.g] and not P.IsBanned(state, data.g) then
      nameOf[data.g] = nameOf[data.g] or data.n
      newPeer(data.g, data.n, true)
    end
  elseif kind == "F" then
    -- a sfottò: only the one it's for shows it
    ns.Fire("Sfotto", from, data)
  elseif kind == "X" then
    -- something happening now (a sfida thrown, a duel starting, a gufata): Sfide.lua shows it at once
    ns.Fire("Live", from, data)
  end
  if kind == "M" then
    if type(data) == "table" and type(data.guid) == "string" then
      recent["M:" .. data.guid .. ":" .. tostring(data.up)] = Clock()
    end
    local old = type(data) == "table" and type(data.guid) == "string" and state.members[data.guid]
    local oldLv, oldTeam = old and old.lv, old and old.team
    changed = P.MergeMember(state, data, me)
    if changed and data.guid == me then C.MarkSelfDirty(1) end
    if changed then
      local rec = state.members[data.guid]
      if oldLv and rec.lv and rec.lv > oldLv then ns.Fire("MemberDing", rec, oldLv) end
      if old and rec.team ~= oldTeam then ns.Fire("MemberSwitched", rec, oldTeam) end
      -- whispering, a member we hear of for the first time gets a hello from us: no waiting for the next round
      if not old and data.guid ~= me and not seen[data.guid] then newPeer(data.guid, nameOf[data.guid] or rec.name) end
      -- someone new, heard from them directly: the others online hear of them in one message, and say hello at once
      if not old and data.guid == from and (Whispering() or GuildOn()) and type(sender) == "string" then
        Broadcast(Body("N", { g = from, n = sender }), true, nil)
      end
      ns.Fire("MemberUpdated", rec, old or nil)
    end
  end
  if changed then ns.Fire("StateChanged", state, kind) end
end

----------------------------------------------------------------------
-- invites: "?I" asks a player to join (whispered, works even if they're in no patto), "?R" says it arrived
----------------------------------------------------------------------
C.PREFIX = PREFIX
function C.RegisterPrefix()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
end

function C.Invite(name)
  if not state or type(name) ~= "string" or name == "" then return false end
  local body = "?I~" .. U.Serialize({ c = state.code, n = state.settings and state.settings.name, by = myName })
  local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, body, "WHISPER", name)
  invitesOut[name:lower()] = Clock()
  invitedAt[name:lower()] = Clock()
  return ok
end

----------------------------------------------------------------------
-- the search: who comes in with the code alone asks "who is in patto X?" to everyone they can reach without a
-- name: their Battle.net friends in the game, their friends list, their group, their guild, the patto's channel.
-- Who is in that patto answers with a hello, and from there the data come. The code is the password: whoever
-- doesn't have it can't ask, and who isn't in that patto doesn't answer.
----------------------------------------------------------------------
local searchedAt, answered = 0, {}
function C.Search()
  if not state then return 0 end
  searchedAt = Clock()
  local msg = "?Q~" .. U.Serialize({ c = state.code, n = myName })
  local sent, done = 0, {}
  -- Battle.net friends playing this same game (across realms, the surest way between friends)
  if C_BattleNet and C_BattleNet.SendGameData and C_BattleNet.GetFriendAccountInfo and BNGetNumFriends then
    local okn, n = pcall(BNGetNumFriends)
    for i = 1, (okn and type(n) == "number" and math.min(n, 200) or 0) do
      local ok, info = pcall(C_BattleNet.GetFriendAccountInfo, i)
      local g = ok and type(info) == "table" and info.gameAccountInfo
      if type(g) == "table" and g.isOnline and g.clientProgram == "WoW" and type(g.gameAccountID) == "number"
        and (not WOW_PROJECT_ID or g.wowProjectID == nil or g.wowProjectID == WOW_PROJECT_ID) then
        if pcall(C_BattleNet.SendGameData, g.gameAccountID, PREFIX, msg) then sent = sent + 1 end
      end
    end
  end
  -- the friends list of the game
  if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    local okn, n = pcall(C_FriendList.GetNumFriends)
    for i = 1, (okn and type(n) == "number" and math.min(n, 100) or 0) do
      local ok, f = pcall(C_FriendList.GetFriendInfoByIndex, i)
      if ok and type(f) == "table" and f.connected and type(f.name) == "string" and not done[f.name] then
        done[f.name] = true
        Enqueue("WHISPER", f.name, msg:sub(1))
        sent = sent + 1
      end
    end
  end
  -- the group, the guild
  if IsInGroup and IsInGroup() then
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
    sent = sent + 1
  end
  if IsInGuild and IsInGuild() then
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
    sent = sent + 1
  end
  U.Log("Comms", "cerco er patto", state.code, "fra", sent, "amichi/gruppi")
  return sent
end

-- someone asks for my patto: if the code is mine, a hello to them (once in a while per name)
-- the answer goes back the way the question came (the whisper's sender, the Battle.net friend): a name typed
-- or built by the addon may not be the one the game wants for a whisper, the sender always is
local function OnSearch(d, route)
  if not (state and type(d) == "table" and d.c == state.code and type(d.n) == "string" and d.n ~= myName) then return end
  if answered[d.n] and Clock() - answered[d.n] < 20 then return end
  answered[d.n] = Clock()
  U.Log("Comms", d.n, "cerca er patto: je risponno", route or d.n)
  if type(route) == "string" and route ~= "" then C.HelloTo(route) else C.AddSeed(d.n) end
end

local function OnInviteMessage(text, sender)
  local kind, payload = text:match("^%?(%u)~?(.*)$")
  if kind == "Q" then
    OnSearch(U.Deserialize(payload), sender)
  elseif kind == "I" then
    local d = U.Deserialize(payload)
    if type(d) ~= "table" or type(d.c) ~= "string" then return end
    pcall(C_ChatInfo.SendAddonMessage, PREFIX, "?R~", "WHISPER", sender)
    ns.Fire("Invited", d.c, type(d.n) == "string" and d.n or nil, type(d.by) == "string" and d.by or sender)
  elseif kind == "R" then
    local short = tostring(sender):match("^([^%-]+)") or sender
    for who, at in pairs(invitesOut) do
      if (who == tostring(sender):lower() or who == short:lower()) and Clock() - at < 30 then
        invitesOut[who] = nil
        ns.Fire("InviteArrived", short)
      end
    end
  end
end

-- Battle.net (a friend's game, any realm): the search, and then everything else with that friend
function C.OnBNAddon(prefix, text, channel, senderID)
  if U.IsSecret(prefix) or U.IsSecret(text) or prefix ~= PREFIX or type(text) ~= "string" then return end
  senderID = U.Plain(senderID, "number")
  if not senderID then return end
  local route = "bn:" .. senderID
  if text:sub(1, 1) == "?" then
    if text:sub(1, 3) == "?Q~" then OnInviteMessage(text, route) end
    return
  end
  C.OnAddonMessage(prefix, text, "WHISPER", route)
end

-- who never answered an invite (no addon, or offline)
function C.PendingInvites(olderThan)
  local out = {}
  for who, at in pairs(invitesOut) do
    if Clock() - at > olderThan then out[#out + 1] = who invitesOut[who] = nil end
  end
  return out
end

function C.OnAddonMessage(prefix, text, channel, sender, target, zoneChannelID, localID, channelName)
  if U.IsSecret(prefix) or U.IsSecret(text) or U.IsSecret(sender) then return end
  if prefix ~= PREFIX or type(text) ~= "string" then return end
  if text:sub(1, 1) == "?" then
    if channel == "WHISPER" and type(sender) == "string" then OnInviteMessage(text, sender)
    elseif text:sub(1, 3) == "?Q~" then OnInviteMessage(text, sender) end
    return
  end
  if not state then return end
  if channel == "CHANNEL" then
    local id = CurrentChannelId()
    if not id or (type(localID) == "number" and localID ~= id) then return end
  end
  local first = text:sub(1, 1)
  if first == "!" then
    Handle(text:sub(2), sender, channel)
  elseif first == "#" then
    local id, i, n, part = text:match("^#(%d+)~(%d+)~(%d+)~(.*)$")
    i, n = tonumber(i), tonumber(n)
    -- (a whole record of an old addon could be 40 pieces and more: up to 80 taken)
    if not id or not i or not n or n > 80 or i > n then return end
    local key = tostring(sender) .. ":" .. id
    local entry = partsIn[key]
    if not entry or entry.n ~= n then entry = { n = n, got = 0, parts = {}, at = Clock() } partsIn[key] = entry end
    if not entry.parts[i] then entry.parts[i] = part entry.got = entry.got + 1 end
    entry.at = Clock()
    if entry.got == n then
      partsIn[key] = nil
      Handle(table.concat(entry.parts), sender, channel)
    end
  end
  -- forget a half-received message when no piece of it came for half a minute (a long one still coming is kept)
  for k, e in pairs(partsIn) do if Clock() - e.at > 30 then partsIn[k] = nil end end
end

----------------------------------------------------------------------
-- "No player named X is currently playing" after a fallback whisper is noise: hide it
----------------------------------------------------------------------
local notFound
if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" then
  notFound = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end

local notFoundAt = {}
local function SystemFilter(_, _, msg)
  if not notFound or U.IsSecret(msg) or type(msg) ~= "string" then return false end
  local name = msg:match(notFound)
  if name and whispered[name] and Clock() - whispered[name] < 20 then
    if not notFoundAt[name] or Clock() - notFoundAt[name] > 60 then
      notFoundAt[name] = Clock()
      U.Log("Comms", "sussurro nun arrivato a", name)
    end
    return true
  end
  return false
end

----------------------------------------------------------------------
-- life cycle
----------------------------------------------------------------------
function C.Start(st, myGuid, playerName)
  state, me, myName = st, myGuid, playerName
  chanName, chanPw = P.ChannelName(st.code), P.ChannelPassword(st.code)
  chanId = nil
  queue, pendingSends, partsIn, whisperPeers = {}, {}, {}, {}
  guildSet, guildOnline, guildHeard, guildFail = {}, {}, {}, false
  C.AskGuild()
  roster, rosterOK, displayIdx = {}, false, nil
  chanBlocked = ForeverClient()
  seeds = {}
  for who in pairs(ns.db and type(ns.db.seeds) == "table" and ns.db.seeds[st.code] or {}) do seeds[who] = true end
  heard, pending = {}, {}
  firstHeardAt = nil
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
  if not ticker then ticker = C_Timer.NewTicker(0.25, Tick) end
  if not helloTicker then
    helloTicker = C_Timer.NewTicker(10, function()
      if state and not P.HasSettings(state) and Clock() - searchedAt >= 60 and Clock() - (C.startedAt or 0) < 1800 then C.Search() end
      -- a minute after the first friend was heard, and nobody had an older record of mine: it's really new
      local mine = state and state.members[me]
      if mine and mine.fresh and firstHeardAt and Clock() - firstHeardAt > 60 then
        P.UpdateSelf(state, me, { fresh = false }, "fresh")
        mine.fsv = nil
        -- (what waited for it, the counters above all, goes now)
        C.MarkSelfDirty(1)
      end
      -- the guild says friends are online, but in five minutes not one message came through it (it doesn't carry
      -- them here, or they all have an older addon): back to whispers
      if GuildOn() and Clock() - (C.startedAt or 0) > 300 and not next(guildHeard) then
        local anyone = false
        for g in pairs(guildOnline) do if seen[g] and Clock() - seen[g] < ONLINE_WINDOW then anyone = true end end
        if anyone then
          guildFail = true
          C.stats.mode = "sussurri"
          U.Log("Comms", "da la gilda nun arriva gnente: torno ai sussurri")
        end
      end
      -- still waiting for the patto's data (a whisper lost on the way): ask again every 20 seconds, not every 2 minutes
      local every = (state and not P.HasSettings(state)) and 20 or (Whispering() and C.HELLO_WHISPER or HELLO_EVERY)
      if state and Clock() - lastHelloAt >= every then C.Hello() end
    end)
  end
  -- the channel's list, once a minute (a dozen names at most to read)
  if not C.rosterTicker then C.rosterTicker = C_Timer.NewTicker(60, function()
    if state and chanBlocked then C.RefreshRoster() end
    if state then C.AskGuild() end
  end) end
  if not C.filterSet and type(ChatFrame_AddMessageEventFilter) == "function" then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemFilter)
    C.filterSet = true
  end
  C.JoinChannel()
  C.startedAt = Clock()
  -- my pieces that changed while nothing could go (or never went: the first time with sync 2) go now
  C.MarkSelfDirty(8)
  if not P.HasSettings(st) and C_Timer then C_Timer.After(4, function() if state and not P.HasSettings(state) then C.Search() end end) end
end

-- leaving: a goodbye to everyone, sent at once (the queue goes with C.Stop); a dozen messages at most, once
function C.SayGoodbye()
  if not state then return 0 end
  local rec = state.members[me]
  local body = "!" .. Body("L", { g = me, up = math.max(U.Now(), (rec and rec.up or 0) + 1) })
  local sent, done = 0, {}
  local function send(kind, target)
    local key = kind .. ":" .. tostring(target)
    if done[key] or sent >= 12 then return end
    done[key] = true
    local ok
    if kind == "BN" then
      ok = C_BattleNet and C_BattleNet.SendGameData and pcall(C_BattleNet.SendGameData, target, PREFIX, body)
    else
      ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, body, kind, target)
    end
    if ok then sent = sent + 1 end
  end
  local gk = GroupKind()
  if gk then send(gk, nil) end
  local cid = CurrentChannelId()
  if cid and not chanBlocked then send("CHANNEL", tostring(cid)) end
  for _, who in ipairs(WhisperTargets(false)) do
    local bn = tonumber(who:match("^bn:(%d+)$"))
    if bn then send("BN", bn) elseif not (gk and InMyGroup(who)) then send("WHISPER", who) end
  end
  U.Log("Comms", "esco dar patto: saluti mannati", sent)
  return sent
end

function C.Stop()
  if chanName and type(LeaveChannelByName) == "function" then pcall(LeaveChannelByName, chanName) end
  state, chanId = nil, nil
  queue, pendingSends = {}, {}
  C.stats.mode = "spento"
end

-- leaving an instance: send what was held and ask for news
function C.OnZoneChanged()
  if not state or C.InLockdown() then return end
  if not CurrentChannelId() and C.stats.mode ~= "sussurri" then
    C.JoinChannel()
  else
    C.Hello()
  end
end

-- around to answer a hello himself: the guild roster says it when he's in it (it knows who logged off a minute
-- ago); else heard from in the last two and a half minutes. A record of someone not around goes from whoever has
-- it newest: the others get it without waiting for its owner to come back.
C.AROUND = 150
function C.Around(guid)
  if guid == me then return true end
  if GuildOn() and guildSet[guid] then return guildOnline[guid] == true end
  return seen[guid] ~= nil and Clock() - seen[guid] < C.AROUND
end
function C.IsOnline(guid)
  if guid == me then return true end
  return seen[guid] ~= nil and Clock() - seen[guid] < ONLINE_WINDOW
end

-- how to reach one member: the name (or Battle.net route) that last wrote from that guid, or the record's name
function C.RouteOf(guid)
  if type(guid) ~= "string" then return nil end
  return nameOf[guid] or (state and state.members[guid] and state.members[guid].name) or nil
end

function C.LastSeen(guid)
  return seen[guid]
end

function C.QueueSize() return #queue end
function C.Queue() return queue end
function C.Blocked() return chanBlocked end
function C.Roster() return roster end
function C.ChannelName() return chanName end
