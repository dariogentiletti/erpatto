-- Er Patto: talking to the other addons, with no internet.
-- Transport: a hidden chat channel named from the code (password-protected); if that fails, addon whispers to known members.
-- Sync: everyone keeps a copy of everything and passes on what others are missing ("passaparola").
-- Limits respected: 255-byte messages (chunked), ~1 message/s per prefix (token bucket), no sends inside instances.
local ADDON, ns = ...
local U, P = ns.U, ns.P
local C = {}
ns.C = C

local PREFIX = "ErPatto"
local MAXLEN = 240
local HELLO_EVERY = 300
local ONLINE_WINDOW = 420
local BUCKET_MAX, REFILL = 8, 1.1

local state, me, myName
local chanName, chanPw, chanId
local queue, tokens, lastTick = {}, BUCKET_MAX, nil
local partsIn = {}
local seen, nameOf = {}, {}
local whisperPeers = {} -- members who can only be reached by whisper (their channel failed)
local recent = {}
local helloReplyAt = {}
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
function C.InLockdown()
  if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
    local ok, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    if ok and (U.IsSecret(locked) or locked) then return true end
  end
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

function C.JoinChannel()
  if not chanName or type(JoinChannelByName) ~= "function" then C.stats.mode = "sussurri" return end
  if C.InLockdown() then return end
  pcall(JoinChannelByName, chanName, chanPw)
  C_Timer.After(3, function()
    chanId = CurrentChannelId()
    if chanId then
      HideChannel()
      C.stats.mode = "canale"
      U.Log("Comms", "canale pronto", chanId)
    else
      C.stats.mode = "sussurri"
      U.Log("Comms", "canale nun disponibile: uso li sussurri")
    end
    C.Hello()
  end)
end

----------------------------------------------------------------------
-- sending
----------------------------------------------------------------------
local function Push(kind, target, text)
  if #queue > 300 then C.stats.dropped = C.stats.dropped + 1 return end
  queue[#queue + 1] = { kind, target, text }
end

local function Enqueue(kind, target, body)
  if #body <= MAXLEN then Push(kind, target, "!" .. body) return end
  seq = seq % 999 + 1
  local size = MAXLEN - 14
  local n = math.ceil(#body / size)
  for i = 1, n do
    Push(kind, target, "#" .. seq .. "~" .. i .. "~" .. n .. "~" .. body:sub((i - 1) * size + 1, i * size))
  end
end

local function Broadcast(body)
  chanId = CurrentChannelId()
  if chanId then
    Enqueue("CHANNEL", tostring(chanId), body)
    -- members stuck on whispers still need to hear us
    local now = Clock()
    for g, who in pairs(whisperPeers) do
      if seen[g] and now - seen[g] < ONLINE_WINDOW then Enqueue("WHISPER", who, body) end
    end
    return
  end
  -- fallback: whisper the members we know, only those seen lately (plus everyone for hellos)
  local isHello = body:sub(1, 1) == "H"
  local now = Clock()
  for g, rec in pairs(state and state.members or {}) do
    local who = nameOf[g] or rec.name
    if g ~= me and who and (isHello or (seen[g] and now - seen[g] < ONLINE_WINDOW)) then
      Enqueue("WHISPER", who, body)
    end
  end
end

local function Body(kind, data)
  return kind .. "~" .. U.Serialize({ f = me, x = data })
end

function C.Send(kind, data)
  if not state then return end
  Broadcast(Body(kind, data))
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
  while #queue > 0 and tokens >= 1 do
    local item = table.remove(queue, 1)
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item[3], item[1], item[2])
    if ok and ResultIsThrottle(res) then
      table.insert(queue, 1, item)
      tokens = 0
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
    end
  end
end

----------------------------------------------------------------------
-- sync protocol
----------------------------------------------------------------------
function C.Hello()
  if not state then return end
  C.Send("H", { p = ns.PROTO, ver = ns.VERSION, n = myName, sv = state.settings.v or 0, av = state.admins.v or 0,
    bv = state.bans.v or 0, d = P.Digest(state) })
end

function C.SendSelf()
  if not state or not state.members[me] then return end
  local rec = state.members[me]
  recent["M:" .. me .. ":" .. (rec.up or 0)] = Clock()
  C.Send("M", rec)
end

-- Send my record after `delay` seconds (XP ticks wait longer than dings or team changes).
function C.MarkSelfDirty(delay)
  local due = Clock() + (delay or 4)
  if not selfDueAt or due < selfDueAt then selfDueAt = due end
end

local function Schedule(key, fn)
  for _, p in ipairs(pendingSends) do if p.key == key then return end end
  pendingSends[#pendingSends + 1] = { key = key, created = Clock(), at = Clock() + 0.5 + math.random() * 2.5, fn = fn }
end

local function SendPiece(kind)
  if kind == "S" then C.Send("S", state.settings)
  elseif kind == "A" then C.Send("A", state.admins)
  elseif kind == "B" then C.Send("B", state.bans) end
end

local function OnHello(from, h, sender)
  if type(h) ~= "table" then return end
  if type(h.p) == "number" and h.p > ns.PROTO and not warnedProto then
    warnedProto = true
    U.Say("quarcuno usa 'na versione più nova. Aggiorna l'addon su CurseForge.")
  end
  local theyNewer = false
  local function cmp(kind, mine, theirs)
    theirs = type(theirs) == "number" and theirs or 0
    if mine > theirs then
      Schedule(kind .. ":" .. mine, function() SendPiece(kind) end)
    elseif theirs > mine then
      theyNewer = true
    end
  end
  cmp("S", state.settings.v or 0, h.sv)
  cmp("A", state.admins.v or 0, h.av)
  cmp("B", state.bans.v or 0, h.bv)
  local d = type(h.d) == "table" and h.d or {}
  local count = 0
  for g, rec in pairs(state.members) do
    local theirs = type(d[g]) == "number" and d[g] or 0
    if (rec.up or 0) > theirs and count < 8 then
      count = count + 1
      local up = rec.up
      Schedule("M:" .. g .. ":" .. up, function()
        if state.members[g] and state.members[g].up == up then C.Send("M", state.members[g]) end
      end)
    end
  end
  for g, up in pairs(d) do
    if type(up) == "number" and not P.IsBanned(state, g) and (not state.members[g] or (state.members[g].up or 0) < up) then
      theyNewer = true
    end
  end
  if theyNewer then
    local last = helloReplyAt[from]
    if not last or Clock() - last > 20 then
      helloReplyAt[from] = Clock()
      Schedule("H:" .. from .. ":" .. math.floor(Clock() / 20), C.Hello)
    end
  end
end

local function Handle(body, sender, channel)
  local kind, payload = body:match("^(%u)~(.*)$")
  if not kind then return end
  local msg = U.Deserialize(payload)
  if type(msg) ~= "table" or type(msg.f) ~= "string" or msg.f == me then return end
  local from = msg.f
  if P.IsBanned(state, from) then return end
  C.stats.received = C.stats.received + 1
  seen[from] = Clock()
  if type(sender) == "string" then nameOf[from] = sender end
  if channel == "WHISPER" and type(sender) == "string" and CurrentChannelId() then
    whisperPeers[from] = sender
  elseif channel == "CHANNEL" then
    whisperPeers[from] = nil
  end
  local data = msg.x
  local changed = false
  if kind == "H" then
    OnHello(from, data, sender)
    if not state.members[from] and type(data) == "table" and type(data.n) == "string" then
      ns.Fire("PeerSeen", from)
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
  elseif kind == "M" then
    if type(data) == "table" and type(data.guid) == "string" then
      recent["M:" .. data.guid .. ":" .. tostring(data.up)] = Clock()
    end
    local old = type(data) == "table" and type(data.guid) == "string" and state.members[data.guid]
    local oldLv, oldTeam = old and old.lv, old and old.team
    changed = P.MergeMember(state, data, me)
    if changed then
      local rec = state.members[data.guid]
      if oldLv and rec.lv and rec.lv > oldLv then ns.Fire("MemberDing", rec, oldLv) end
      if old and rec.team ~= oldTeam then ns.Fire("MemberSwitched", rec, oldTeam) end
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

local invitesOut = {}
function C.Invite(name)
  if not state or type(name) ~= "string" or name == "" then return false end
  local body = "?I~" .. U.Serialize({ c = state.code, n = state.settings and state.settings.name, by = myName })
  local ok = pcall(C_ChatInfo.SendAddonMessage, PREFIX, body, "WHISPER", name)
  invitesOut[name:lower()] = Clock()
  return ok
end

local function OnInviteMessage(text, sender)
  local kind, payload = text:match("^%?(%u)~?(.*)$")
  if kind == "I" then
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
    if channel == "WHISPER" and type(sender) == "string" then OnInviteMessage(text, sender) end
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
    if not id or not i or not n or n > 40 or i > n then return end
    local key = tostring(sender) .. ":" .. id
    local entry = partsIn[key]
    if not entry or entry.n ~= n then entry = { n = n, got = 0, parts = {}, at = Clock() } partsIn[key] = entry end
    if not entry.parts[i] then entry.parts[i] = part entry.got = entry.got + 1 end
    if entry.got == n then
      partsIn[key] = nil
      Handle(table.concat(entry.parts), sender, channel)
    end
  end
  -- forget half-received messages after a minute
  for k, e in pairs(partsIn) do if Clock() - e.at > 60 then partsIn[k] = nil end end
end

----------------------------------------------------------------------
-- "No player named X is currently playing" after a fallback whisper is noise: hide it
----------------------------------------------------------------------
local notFound
if type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" then
  notFound = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
end

local function SystemFilter(_, _, msg)
  if not notFound or U.IsSecret(msg) or type(msg) ~= "string" then return false end
  local name = msg:match(notFound)
  if name and whispered[name] and Clock() - whispered[name] < 20 then return true end
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
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
  if not ticker then ticker = C_Timer.NewTicker(0.25, Tick) end
  if not helloTicker then helloTicker = C_Timer.NewTicker(HELLO_EVERY, function() C.Hello() end) end
  if not C.filterSet and type(ChatFrame_AddMessageEventFilter) == "function" then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemFilter)
    C.filterSet = true
  end
  C.JoinChannel()
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

function C.IsOnline(guid)
  if guid == me then return true end
  return seen[guid] ~= nil and Clock() - seen[guid] < ONLINE_WINDOW
end

function C.LastSeen(guid)
  return seen[guid]
end

function C.QueueSize() return #queue end
function C.ChannelName() return chanName end
