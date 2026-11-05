-- Er Patto: talking to the other addons, with no internet.
-- Transport: a hidden chat channel named from the code (password-protected). Where the channel can't carry addon
-- messages (WoW Forever answers NOT_ALLOWED_IN_CHANNEL) it is only the meeting place: its member list says who of
-- the patto is online, and the messages go to each of them as addon whispers.
-- Sync: everyone keeps a copy of everything and passes on what others are missing ("passaparola").
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
local chanBlocked = false -- the channel is there, but addon messages in it are refused: whispers to the roster
local roster, rosterOK, displayIdx = {}, false, nil -- guid -> name of who is in the patto's channel now
-- names to start from when we know nobody yet: who invited us, or the name written next to the code
local seeds = {}
local recent = {}
local helloReplyAt = {}
local askedFull = {}
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
      C.stats.mode = chanBlocked and "sussurri" or "canale"
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
    if key:sub(1, 2) == "M:" then at = Supersede("D:" .. key:sub(3) .. ">" .. tostring(target)) end
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

-- who to whisper: who is in the patto's channel (when its list is known), and who wrote to us lately;
-- without the list, hellos go to every member we know by name
local function WhisperTargets(isHello)
  local out, done = {}, {}
  local function add(who)
    if type(who) == "string" and who ~= "" and not done[who] then done[who] = true out[#out + 1] = who end
  end
  for g, who in pairs(roster) do if g ~= me then add(who) end end
  local now = Clock()
  -- whoever wrote to us lately, member or not yet (someone just come in with the code)
  for g, t in pairs(seen) do
    if g ~= me and nameOf[g] and now - t < ONLINE_WINDOW then add(nameOf[g]) end
  end
  -- a hello goes to every member we know, online or not: on Forever the channel splits the realm in islands
  -- (each internal realm its own copy of the channel), whispers reach everyone; the offline ones' "no player
  -- named" is hidden (SystemFilter)
  for g, rec in pairs(state and state.members or {}) do
    if g ~= me then
      local who = nameOf[g] or rec.name
      if (seen[g] and now - seen[g] < ONLINE_WINDOW) or isHello then add(who) end
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
  return chanBlocked or not CurrentChannelId()
end
C.Whispering = Whispering

local function Broadcast(body, urgent, key)
  chanId = CurrentChannelId()
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
  if kind == "D" then return type(data) == "table" and type(data.g) == "string" and ("D:" .. data.g) or nil end
  if kind == "H" or kind == "S" or kind == "A" or kind == "B" then return kind end
  return nil
end

function C.Send(kind, data, urgent)
  if not state then return end
  Broadcast(Body(kind, data), kind == "X" or urgent == true, KeyOf(kind, data))
  -- my own whole record went out (from SendSelf or as an answer to a hello): the changes start from here
  if kind == "M" and type(data) == "table" and data.guid == me then C.NoteFull(data) end
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
    end
  end
end

----------------------------------------------------------------------
-- sync protocol
----------------------------------------------------------------------
local function HelloData()
  local mine = state.members[me]
  return { p = ns.PROTO, ver = ns.VERSION, n = myName, sv = state.settings.v or 0, av = state.admins.v or 0,
    bv = state.bans.v or 0, d = P.Digest(state), fr = mine and mine.fresh and true or nil,
    lf = type(state.left) == "table" and next(state.left) and state.left or nil }
end

function C.Hello()
  if not state then return end
  lastHelloAt = Clock()
  C.Send("H", HelloData())
end

-- someone just came into the patto's channel: a hello to them alone (they answer with what we miss, and the other way)
local introduced = {}
newPeer = function(guid, name, urgent)
  if not state or not Whispering() or type(name) ~= "string" then return end
  if introduced[guid] and Clock() - introduced[guid] < 60 then return end
  introduced[guid] = Clock()
  U.Log("Comms", urgent and "novo ner patto:" or "ner canale c'è", name)
  Enqueue("WHISPER", name, Body("H", HelloData()), urgent == true, "H")
end

-- my record goes whole at most every half hour; in between only what changed since the last whole one ("D").
-- Whispered to each member one by one (WoW Forever), a whole record is 7-10 messages, a change 1-2.
C.FULL_EVERY = 1800
local fullSer, fullUp, fullAt -- my record as last sent whole, field by field
local selfUrgent
function C.NoteFull(rec)
  fullSer, fullUp, fullAt = {}, rec.up, Clock()
  for k, v in pairs(rec) do fullSer[k] = U.Serialize(v) end
end

-- what changed since my last whole record, or nil when a whole one is due (none sent, too old, or too much changed)
local function SelfDelta(rec)
  if not (fullSer and fullUp and rec.up and rec.up > fullUp and fullAt and Clock() - fullAt < C.FULL_EVERY) then return nil end
  local ch, gone, size, total = {}, {}, 0, 0
  for k, v in pairs(rec) do
    local ser = U.Serialize(v)
    total = total + #ser
    if k ~= "up" and ser ~= fullSer[k] then ch[k] = v size = size + #ser end
  end
  for k in pairs(fullSer) do if rec[k] == nil then gone[#gone + 1] = k end end
  if size >= total * 0.6 then return nil end
  return { g = me, b = fullUp, up = rec.up, c = ch, r = #gone > 0 and gone or nil }
end

-- something the others must see now (a ding, a death, a squadra): a "flash" of just those fields, one message,
-- first in the queue, good on any copy of my record; the record itself follows at its pace
local sentT, sentW, sentTop = {}, {}, {}
local FLASH_FIELD = 160
local function Flash(rec)
  local wk = 0
  if P.HasSettings(state) and ns.M and ns.M.WeekIndex then wk = ns.M.WeekIndex(state.settings, U.Now()) or 0 end
  local e = { g = me, up = rec.up, c = {}, t = {}, w = {} }
  local any = false
  for k, v in pairs(rec) do
    if k ~= "up" and k ~= "guid" and k ~= "stats" and k ~= "fresh" and k ~= "abt" then
      local ser = U.Serialize(v)
      if ser ~= sentTop[k] and #ser <= FLASH_FIELD then e.c[k] = v any = true end
    end
  end
  local t = rec.stats and rec.stats.t or {}
  for k, v in pairs(t) do if v ~= sentT[k] then e.t[k] = v any = true end end
  local w = rec.stats and rec.stats.w and rec.stats.w[wk] or {}
  local ww = {}
  for k, v in pairs(w) do if v ~= sentW[k] then ww[k] = v any = true end end
  if next(ww) then e.w[wk] = ww end
  if not any then return end
  local body = Body("E", e)
  if #body <= MAXLEN then Broadcast(body, true, nil) end
end
-- what the others have of me now, to tell a flash what's new
local function NoteSent(rec)
  sentTop = {}
  for k, v in pairs(rec) do if k ~= "stats" then sentTop[k] = U.Serialize(v) end end
  sentT = {}
  for k, v in pairs(rec.stats and rec.stats.t or {}) do sentT[k] = v end
  sentW = {}
  local wk = P.HasSettings(state) and ns.M and ns.M.WeekIndex and ns.M.WeekIndex(state.settings, U.Now()) or 0
  for k, v in pairs(rec.stats and rec.stats.w and rec.stats.w[wk] or {}) do sentW[k] = v end
end

function C.SendSelf()
  if not state or not state.members[me] then return end
  local rec = state.members[me]
  recent["M:" .. me .. ":" .. (rec.up or 0)] = Clock()
  if selfUrgent then pcall(Flash, rec) end
  selfUrgent = nil
  NoteSent(rec)
  local d = SelfDelta(rec)
  if d then C.Send("D", d) return end
  C.Send("M", rec)
end

-- my record to one who asked (their copy is from `theirUp`): only the changes when they have my last whole one
function C.SendSelfTo(to, theirUp)
  local rec = state and state.members[me]
  if not rec then return end
  local d = (theirUp or 0) >= (fullUp or math.huge) and SelfDelta(rec)
  -- someone who never had me (just come in): first in the line
  if d then C.SendTo("D", d, to) else C.SendTo("M", rec, to, (theirUp or 0) == 0) end
end

-- Send my record after `delay` seconds (XP ticks wait longer than dings or team changes).
function C.MarkSelfDirty(delay, urgent)
  if urgent then selfUrgent = true end
  local due = Clock() + (delay or 4)
  if not selfDueAt or due < selfDueAt then selfDueAt = due end
end

local function Schedule(key, fn)
  for _, p in ipairs(pendingSends) do if p.key == key then return end end
  pendingSends[#pendingSends + 1] = { key = key, created = Clock(), at = Clock() + 0.5 + math.random() * 2.5, fn = fn }
end

-- to one player only (whispered): the answers to a hello on Forever go to who asked, not to everyone
function C.SendTo(kind, data, who, urgent)
  if not state then return end
  if not who then C.Send(kind, data, urgent) return end
  Enqueue("WHISPER", who, Body(kind, data), urgent == true, KeyOf(kind, data))
  -- (a whole record to one friend isn't "the last whole one" for everyone else: the changes stay counted from that)
end

function C.HelloTo(who, urgent)
  if not state then return end
  if who then Enqueue("WHISPER", who, Body("H", HelloData()), urgent == true, "H") else C.Hello() end
end

-- the patto's rules: small, rare, and without them who just came in can't start: first in the line
local function SendPiece(kind, to)
  if kind == "S" then C.SendTo("S", state.settings, to, true)
  elseif kind == "A" then C.SendTo("A", state.admins, to, true)
  elseif kind == "B" then C.SendTo("B", state.bans, to, true) end
end

local prevSentAt = {}
local function OnHello(from, h, sender)
  if type(h) ~= "table" then return end
  if type(h.p) == "number" and h.p > ns.PROTO and not warnedProto then
    warnedProto = true
    U.Say("quarcuno usa 'na versione più nova. Aggiorna l'addon su CurseForge.")
  end
  local theyNewer = false
  -- whispering (Forever): what they miss goes to them alone
  local to = Whispering() and type(sender) == "string" and sender or nil
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
  -- "my record is new on this PC": if I hold a real copy of it, it goes back to them, whatever its date
  if h.fr == true then
    local theirs = state.members[from]
    if theirs and not theirs.fresh then
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
      Schedule("P:" .. from .. tag, function()
        local p = type(state.prev) == "table" and state.prev[from]
        -- its own key: it mustn't take the place of their record of now in the queue
        if p and to then Enqueue("WHISPER", to, Body("M", p), false, "P:" .. from)
        elseif p then Broadcast(Body("M", p), false, "P:" .. from) end
      end)
    end
  end
  local d = type(h.d) == "table" and h.d or {}
  local count = 0
  for g, rec in pairs(state.members) do
    local theirs = type(d[g]) == "number" and d[g] or 0
    -- whispering, every record sent is 7-10 whispers: someone else's goes from me only when they aren't around
    -- to send it themselves (or nobody has it: they never had it at all)
    local mine = g == me
    local relay = mine or not to or not C.IsOnline(g) or theirs == 0
    if (rec.up or 0) > theirs and count < 8 and relay then
      count = count + 1
      local up = rec.up
      Schedule("M:" .. g .. ":" .. up .. tag, function()
        if not state.members[g] or state.members[g].up ~= up then return end
        if mine then C.SendSelfTo(to, theirs) else C.SendTo("M", state.members[g], to) end
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
  for g, up in pairs(d) do
    if type(up) == "number" and not P.IsBanned(state, g) and not P.HasLeft(state, g, up)
      and (not state.members[g] or (state.members[g].up or 0) < up) then
      theyNewer = true
    end
  end
  if theyNewer then
    local last = helloReplyAt[from]
    if not last or Clock() - last > 20 then
      helloReplyAt[from] = Clock()
      -- someone I never heard of (just come in): my hello goes first, so their record comes at once
      local stranger = not state.members[from]
      Schedule("H:" .. from .. ":" .. math.floor(Clock() / 20), function() C.HelloTo(to, stranger) end)
    end
  end
end

local invitesOut = {}
-- who I invited and when (lower case names), kept half an hour: a cacciato I invite again may come back
local invitedAt = {}

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
  seen[from] = Clock()
  firstHeardAt = firstHeardAt or Clock()
  if type(sender) == "string" then nameOf[from] = sender end
  if channel == "WHISPER" and type(sender) == "string" and CurrentChannelId() and not chanBlocked then
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
  elseif kind == "E" then
    -- a flash: a ding, a death, a squadra, on top of my copy of their record at once (its date stays: the
    -- record itself, with everything else, still comes and is still asked for)
    local cur = state.members[from]
    if cur and type(data) == "table" and data.g == from and type(data.up) == "number" and data.up > (cur.up or 0) then
      local new = U.Copy(cur)
      if type(data.c) == "table" then
        for k, v in pairs(data.c) do if k ~= "guid" and k ~= "up" and k ~= "stats" and k ~= "fresh" then new[k] = v end end
      end
      new.stats = type(new.stats) == "table" and new.stats or { t = {}, w = {} }
      new.stats.t = type(new.stats.t) == "table" and new.stats.t or {}
      new.stats.w = type(new.stats.w) == "table" and new.stats.w or {}
      if type(data.t) == "table" then
        for k, v in pairs(data.t) do if type(v) == "number" and v > (new.stats.t[k] or 0) then new.stats.t[k] = v end end
      end
      if type(data.w) == "table" then
        for wk, kv in pairs(data.w) do
          if type(wk) == "number" and type(kv) == "table" then
            new.stats.w[wk] = type(new.stats.w[wk]) == "table" and new.stats.w[wk] or {}
            for k, v in pairs(kv) do if type(v) == "number" and v > (new.stats.w[wk][k] or 0) then new.stats.w[wk][k] = v end end
          end
        end
      end
      local r = P.CleanMember(new)
      if r then
        r.up = cur.up
        local oldLv, oldTeam = cur.lv, cur.team
        if r.team ~= oldTeam and P.LogSwitch then P.LogSwitch(state, r, oldTeam, r.team, r.tat) end
        state.members[from] = r
        C.stats.flash = (C.stats.flash or 0) + 1
        if oldLv and r.lv and r.lv > oldLv then ns.Fire("MemberDing", r, oldLv) end
        if r.team ~= oldTeam then ns.Fire("MemberSwitched", r, oldTeam) end
        ns.Fire("MemberUpdated", r, cur)
        changed = true
      end
    end
  elseif kind == "F" then
    -- a sfottò: only the one it's for shows it
    ns.Fire("Sfotto", from, data)
  elseif kind == "X" then
    -- something happening now (a sfida thrown, a duel starting, a gufata): Sfide.lua shows it at once
    ns.Fire("Live", from, data)
  elseif kind == "D" then
    -- what changed in someone's record since their last whole one: good on any copy at least that new
    if type(data) == "table" and type(data.g) == "string" and data.g == from and type(data.c) == "table"
      and type(data.b) == "number" and type(data.up) == "number" then
      local cur = state.members[data.g]
      if cur and (cur.up or 0) >= data.b and data.up > (cur.up or 0) then
        local new = {}
        for k, v in pairs(cur) do new[k] = v end
        for k, v in pairs(data.c) do new[k] = v end
        if type(data.r) == "table" then for _, k in ipairs(data.r) do if type(k) == "string" then new[k] = nil end end end
        new.guid, new.up = data.g, data.up
        data = new
        kind = "M"
        C.stats.deltas = (C.stats.deltas or 0) + 1
      elseif not cur or (cur.up or 0) < data.b then
        -- my copy is too old for this change (a whole record got lost on the way): a hello, and they send it whole
        C.stats.stale = (C.stats.stale or 0) + 1
        local last = askedFull[from]
        if type(sender) == "string" and (not last or Clock() - last > 20) then
          askedFull[from] = Clock()
          Schedule("H:" .. from .. ":full", function() C.HelloTo(Whispering() and sender or nil) end)
        end
      end
    end
  end
  if kind == "M" then
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
      -- whispering, a member we hear of for the first time gets a hello from us: no waiting for the next round
      if not old and data.guid ~= me and not seen[data.guid] then newPeer(data.guid, nameOf[data.guid] or rec.name) end
      -- someone new, heard from them directly: the others online hear of them in one message, and say hello at once
      if not old and data.guid == from and Whispering() and type(sender) == "string" then
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
  roster, rosterOK, displayIdx = {}, false, nil
  chanBlocked = ForeverClient()
  seeds = {}
  for who in pairs(ns.db and type(ns.db.seeds) == "table" and ns.db.seeds[st.code] or {}) do seeds[who] = true end
  fullSer, fullUp, fullAt = nil, nil, nil
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
      end
      -- still waiting for the patto's data (a whisper lost on the way): ask again every 20 seconds, not every 2 minutes
      local every = (state and not P.HasSettings(state)) and 20 or (Whispering() and C.HELLO_WHISPER or HELLO_EVERY)
      if state and Clock() - lastHelloAt >= every then C.Hello() end
    end)
  end
  -- the channel's list, once a minute (a dozen names at most to read)
  if not C.rosterTicker then C.rosterTicker = C_Timer.NewTicker(60, function() if state and chanBlocked then C.RefreshRoster() end end) end
  if not C.filterSet and type(ChatFrame_AddMessageEventFilter) == "function" then
    ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", SystemFilter)
    C.filterSet = true
  end
  C.JoinChannel()
  C.startedAt = Clock()
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

function C.IsOnline(guid)
  if guid == me then return true end
  return seen[guid] ~= nil and Clock() - seen[guid] < ONLINE_WINDOW
end

function C.LastSeen(guid)
  return seen[guid]
end

function C.QueueSize() return #queue end
function C.Queue() return queue end
function C.Blocked() return chanBlocked end
function C.Roster() return roster end
function C.ChannelName() return chanName end
