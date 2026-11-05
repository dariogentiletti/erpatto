-- Er Patto: the fun counters the group compares on the "Avventure" page.
--   fish caught, herbs / ore / leather gathered, blue and epic drops (luck), silly deaths (falling, drowning, a much
--   lower mob), the nemesis (what killed you most), famous mobs and dungeon bosses killed, yards travelled, flights,
--   hearthstones. Counts go in the shared stats (week and total); the nemesis, famous kills and first epic travel as
--   small extra fields. Where the game keeps its own statistics (Statistics pane), they raise our totals.
local ADDON, ns = ...
local U, M, P, T = ns.U, ns.M, ns.P, ns.T
local F = {}
ns.Fun = F

local function Plain(v, kind) return U.Plain(v, kind) end
local function Safe(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, g, h = pcall(f, ...)
  if not ok then return nil end
  return a, b, c, d, e, g, h
end
local function Ready() return T.Ready and T.Ready() end
local function Rec() return ns.MyRecord and ns.MyRecord() end
local function Bump(key, n) if Ready() then T.Bump(key, n) end end
local function Zone()
  local z = GetRealZoneText and Plain(Safe(GetRealZoneText), "string")
  return (z and z ~= "") and z or nil
end

-- mobs everyone remembers; any rare, world boss or dungeon boss counts too
F.FAMOUS = { ["Hogger"] = true, ["Mor'Ladim"] = true, ["Bellygrub"] = true, ["Old Murk-Eye"] = true, ["Gath'Ilzogg"] = true,
  ["Princess"] = true, ["Mother Fang"] = true, ["Fedfennel"] = true, ["Morgaine the Sly"] = true, ["Foreman Oslow"] = true,
  ["Stitches"] = true, ["Bhag'thera"] = true, ["Sludge Beast"] = true, ["Mazzranache"] = true, ["Gazz'uz"] = true }

-- luck: blue and epic drops per ten hours played (an epic counts as five blues)
function F.LuckOf(m, mode)
  local H = ns.UI.H
  local lb, le, pt = H.StatOf(m, "lb", mode), H.StatOf(m, "le", mode), H.StatOf(m, "pt", mode)
  if lb + le == 0 then return 0 end
  return (lb + 5 * le) * 36000 / math.max(pt, 7200)
end

----------------------------------------------------------------------
-- the extra fields: nemesis, famous kills, first epic
----------------------------------------------------------------------
local function Journal() return ns.J and ns.J.Get and ns.J.Get() end

function F.Sync()
  if not Ready() then return end
  local j = Journal()
  if not j then return end
  local fields = {}
  -- nemesis: what (or who) killed me most
  local by = {}
  for _, d in ipairs(j.deaths or {}) do if d.by then by[d.by] = (by[d.by] or 0) + 1 end end
  local best, bestN
  for n, c in pairs(by) do if not best or c > bestN or (c == bestN and n < best) then best, bestN = n, c end end
  if best then fields.ne = { n = best, c = bestN } end
  -- famous kills: top five by count
  local list = {}
  for n, c in pairs(j.named or {}) do list[#list + 1] = { n = n, c = c } end
  table.sort(list, function(a, b) return a.c > b.c or (a.c == b.c and a.n < b.n) end)
  local nkl = {}
  for i = 1, math.min(5, #list) do nkl[i] = list[i] end
  fields.nkl = nkl
  local rec = Rec()
  if rec and not rec.fe and j.firstEpic then fields.fe = j.firstEpic end
  P.UpdateSelf(ns.state, ns.recordGuid, fields, "fun")
end

local syncDue
local function SyncSoon()
  if syncDue or not C_Timer then return end
  syncDue = true
  C_Timer.After(3, function() syncDue = nil F.Sync() end)
end

----------------------------------------------------------------------
-- fishing, gathering, luck
----------------------------------------------------------------------
ns.On("J_Fish", function(n) Bump("fi", n or 1) end)

-- trade goods (class 7): 9 herbs, 7 metal and stone, 6 leather
local GATHER = { [9] = "he", [7] = "mi", [6] = "sk" }
ns.On("J_Item", function(id, q, count, kind, link)
  if kind ~= "loot" or not Ready() then return end
  if C_Item and C_Item.GetItemInfoInstant then
    local _, _, _, _, _, classID, subID = Safe(C_Item.GetItemInfoInstant, id)
    classID, subID = Plain(classID, "number"), Plain(subID, "number")
    if classID == 7 and GATHER[subID] then Bump(GATHER[subID], count or 1) end
  end
  if q == 3 then Bump("lb") end
  if q and q >= 4 then
    Bump("le")
    local j = Journal()
    if j and not j.firstEpic then
      local name = type(link) == "string" and link:match("%[(.-)%]") or nil
      j.firstEpic = { at = U.Now(), n = name }
      SyncSoon()
    end
  end
end)

----------------------------------------------------------------------
-- famous mobs and bosses
----------------------------------------------------------------------
local function Named(name)
  local j = Journal()
  if not (j and name) then return end
  j.named = j.named or {}
  j.named[name] = (j.named[name] or 0) + 1
  Bump("nk")
  SyncSoon()
end

ns.On("J_Kill", function(id, k)
  if not k then return end
  if k.cl == "rare" or k.cl == "rareelite" or k.cl == "worldboss" or (k.n and F.FAMOUS[k.n]) then Named(k.n) end
end)

----------------------------------------------------------------------
-- deaths: what kind, and who did it
----------------------------------------------------------------------
-- what last hurt me from the world (the combat log: "Falling", "Drowning", "Lava"...), the breath bar running out,
-- and the last moment I was falling
local env, envAt = nil, 0
local breathEnd, lastFall = nil, 0
-- a jump is half a second in the air, a fall that hurts more than a second: only a long one makes the death "cascato"
local fallStart, lastFallDur = nil, 0
F.FALL_MIN = 1.2
local function Now() return GetTime and GetTime() or 0 end

function F.DeathKind()
  local myLv = Plain(Safe(UnitLevel, "player"), "number") or 1
  local killer, kLv, kPlayer, kType
  if Safe(UnitExists, "target") == true and Safe(UnitCanAttack, "player", "target") == true and Safe(UnitIsDead, "target") ~= true then
    killer = Plain(Safe(UnitName, "target"), "string")
    kLv = Plain(Safe(UnitLevel, "target"), "number")
    kPlayer = Safe(UnitIsPlayer, "target") == true
    kType = Plain(Safe(UnitCreatureType, "target"), "string")
  end
  local kind = "mostro"
  local recent = Now() - envAt < 3 and env
  if recent == "Falling" then kind = "cascato"
  elseif recent == "Drowning" then kind = "affogato"
  elseif (Safe(IsFalling) == true and fallStart and Now() - fallStart >= F.FALL_MIN)
    or (Now() - lastFall < 2.5 and lastFallDur >= F.FALL_MIN) then kind = "cascato"
  elseif breathEnd and Now() >= breathEnd - 2 then kind = "affogato"
  elseif kPlayer then kind = "pvp"
  elseif killer and (kType == "Critter" or (kLv and kLv > 0 and kLv <= myLv - 5)) then kind = "pischello"
  end
  return kind, killer, kLv
end

F.SILLY = { cascato = true, affogato = true, pischello = true }

-- the game's own death recap, where the client gives it: the blow that killed me and who dealt it ("Falling",
-- "Drowning", or a mob's name). Better than any guess; nil when there's none (or it's the one of a death before).
local lastRecapAt
function F.RecapKind()
  if not (C_DeathRecap and C_DeathRecap.GetRecapEvents) then return nil end
  local ok, events = pcall(C_DeathRecap.GetRecapEvents)
  if not ok or type(events) ~= "table" or U.IsSecret(events) then return nil end
  local blow = events[1]
  if type(blow) ~= "table" then return nil end
  local at = Plain(blow.timestamp, "number")
  if at and at == lastRecapAt then return nil end
  lastRecapAt = at
  local env = Plain(blow.environmentalType, "string")
  if env then
    env = env:upper()
    if env == "FALLING" then return "cascato" end
    if env == "DROWNING" then return "affogato" end
    return "mostro"
  end
  return nil, Plain(blow.sourceName, "string")
end

-- the last thing I wrote in chat, for the epitaph (only if said in the last ten minutes)
local lastWords
F.WORDS_FRESH = 600
function F.Said(msg, author)
  if type(msg) ~= "string" or U.IsSecret(msg) or type(author) ~= "string" or U.IsSecret(author) then return end
  local me = ns.myName or U.FullName("player")
  if not me or (author ~= me and author:match("^([^%-]+)") ~= me) then return end
  msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|", "")
  if msg ~= "" then lastWords = { t = msg:sub(1, 80), at = U.Now() } end
end

-- the gravestone: when, at what level, who, where, the last words
local function Grave(kind, killer)
  local rec = ns.MyRecord and ns.MyRecord()
  if not rec then return end
  local words = lastWords and U.Now() - lastWords.at <= F.WORDS_FRESH and lastWords.t or nil
  local stone = { at = U.Now(), lv = Plain(Safe(UnitLevel, "player"), "number"), by = killer, z = Zone(), w = words, k = kind }
  local rip = { stone }
  -- (a stone a few seconds from the one before it is the same death told twice by the game: it goes)
  for _, g in ipairs(rec.rip or {}) do
    local last = rip[#rip]
    if #rip >= 10 then break end
    if not (type(g.at) == "number" and type(last.at) == "number" and math.abs(last.at - g.at) <= 5) then rip[#rip + 1] = g end
  end
  lastWords = nil
  P.UpdateSelf(ns.state, ns.recordGuid, { rip = rip }, "rip")
end

function F.OnDeath()
  if not U.FirstDeath("Fun") then return end
  if not Ready() then return end
  -- what the screen says now (the target, the fall), then half a second for the game's recap to be there
  local kind, killer = F.DeathKind()
  local function finish()
    local ok, rk, rkiller = pcall(F.RecapKind)
    if ok and rk then kind = rk end
    if ok and rkiller then
      killer = rkiller
      -- the recap names who killed me: then it was a mob, whatever the screen seemed to say (a jump, a fall)
      if kind == "cascato" and not rk then kind = "mostro" end
    end
    F.Record(kind, killer)
  end
  if C_Timer then C_Timer.After(0.5, finish) else finish() end
end

function F.Record(kind, killer)
  pcall(Grave, kind, killer)
  local j = Journal()
  -- the journal wrote its own entry on the same event; give it the kind (and the killer, if it missed it)
  local function tag()
    local d = j and j.deaths and j.deaths[#j.deaths]
    if d and U.Now() - (d.at or 0) < 5 then d.kind = kind d.by = d.by or killer end
    SyncSoon()
  end
  if C_Timer then C_Timer.After(0.2, tag) else tag() end
  if F.SILLY[kind] then
    Bump("em")
    P.UpdateSelf(ns.state, ns.recordGuid, { ed = { k = kind, at = U.Now(), z = Zone(), by = killer } }, "silly")
  end
end

----------------------------------------------------------------------
-- travel: yards on foot or mounted (not on flights), sampled every two seconds in the open world
----------------------------------------------------------------------
local lastPos, pending = nil, 0
function F.SampleTravel()
  if not Ready() then lastPos = nil return end
  if Safe(UnitOnTaxi, "player") == true or Safe(IsInInstance) == true then lastPos = nil return end
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return end
  local map = Plain(Safe(C_Map.GetBestMapForUnit, "player"), "number")
  local pos = map and Safe(C_Map.GetPlayerMapPosition, map, "player")
  if not pos then lastPos = nil return end
  local inst, world = Safe(C_Map.GetWorldPosFromMapPos, map, pos)
  if type(world) ~= "table" and type(world) ~= "userdata" then lastPos = nil return end
  local x, y = world.x, world.y
  if world.GetXY then x, y = world:GetXY() end
  x, y, inst = Plain(x, "number"), Plain(y, "number"), Plain(inst, "number")
  if not (x and y) then lastPos = nil return end
  if lastPos and lastPos.inst == inst then
    local d = math.sqrt((x - lastPos.x) ^ 2 + (y - lastPos.y) ^ 2)
    if d > 0.5 and d < 120 then pending = pending + d end
  end
  lastPos = { x = x, y = y, inst = inst }
  if pending >= 200 then
    Bump("tr", math.floor(pending))
    pending = pending - math.floor(pending)
  end
end

----------------------------------------------------------------------
-- the game's own statistics (Statistics pane), when the client has them
----------------------------------------------------------------------
-- English names as the client writes them -> our key; the game's number only ever raises our total
local GAME = { ["Fish caught"] = "fi", ["Flight paths taken"] = "fl", ["Number of times hearthed"] = "hs" }
local SILLY_GAME = { "Deaths from falling", "Deaths from drowning" }

function F.ReadGameStats()
  if not (GetStatisticsCategoryList and GetCategoryNumAchievements and GetAchievementInfo and GetStatistic) then return nil end
  local cats = { Safe(GetStatisticsCategoryList) }
  if type(cats[1]) == "table" then cats = cats[1] end
  local out, n = {}, 0
  for _, cat in ipairs(cats) do
    local num = Plain(Safe(GetCategoryNumAchievements, cat), "number") or 0
    for i = 1, num do
      local id, name = Safe(GetAchievementInfo, cat, i)
      id, name = Plain(id, "number"), Plain(name, "string")
      if id and name then
        local v = Plain(Safe(GetStatistic, id), "string")
        local num2 = v and tonumber((v:gsub("[^%d]", "")))
        if num2 then out[name] = num2 n = n + 1 end
      end
    end
  end
  local j = Journal()
  if j then j.gstats = out j.gstatsAt = U.Now() end
  return out, n
end

-- only for a character of the patto's range (a level 80 test character would bring years of history)
function F.RaiseFromGame()
  if not Ready() then return end
  local lv = Plain(Safe(UnitLevel, "player"), "number") or 99
  if lv > 60 then return end
  local st = ns.MyStatus and ns.MyStatus()
  if st and not st.started then return end
  local g = F.ReadGameStats()
  if not g then return end
  local rec = Rec()
  rec.stats = rec.stats or { t = {}, w = {} }
  local t = rec.stats.t
  local changed = false
  local function raise(key, v)
    if v and v > (t[key] or 0) then t[key] = v changed = true end
  end
  for name, key in pairs(GAME) do raise(key, g[name]) end
  local silly = 0
  for _, name in ipairs(SILLY_GAME) do silly = silly + (g[name] or 0) end
  if silly > 0 then raise("em", silly) end
  if changed then
    rec.up = U.Now()
    ns.Fire("SelfChanged", ns.state, "fun")
  end
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {
  PLAYER_DEAD = function() F.OnDeath() end,
  -- the breath bar: value in ms, going down (scale -1); drowning only when it's about to end
  MIRROR_TIMER_START = function(timer, value, _, scale)
    if timer ~= "BREATH" then return end
    value, scale = Plain(value, "number"), Plain(scale, "number")
    breathEnd = (value and (scale or -1) < 0) and (Now() + value / 1000) or nil
  end,
  MIRROR_TIMER_STOP = function(timer) if timer == "BREATH" then breathEnd = nil end end,
  COMBAT_LOG_EVENT_UNFILTERED = function()
    if not (CombatLogGetCurrentEventInfo and UnitGUID) then return end
    local _, sub, _, _, _, _, _, dest, _, _, _, kind = CombatLogGetCurrentEventInfo()
    if sub ~= "ENVIRONMENTAL_DAMAGE" or U.IsSecret(dest) or dest ~= UnitGUID("player") then return end
    env, envAt = Plain(kind, "string"), Now()
  end,
  ENCOUNTER_END = function(_, name, _, _, success)
    if success == 1 or success == true then Named(Plain(name, "string")) end
  end,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit == "player" and Plain(spellID, "number") == 8690 then Bump("hs") end
  end,
  PLAYER_LEVEL_UP = function() if C_Timer then C_Timer.After(5, F.RaiseFromGame) end end,
}
for _, ev in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_CHANNEL" }) do
  handlers[ev] = function(msg, author) F.Said(msg, author) end
end
frame:SetScript("OnEvent", function(_, event, ...)
  local fn = handlers[event]
  if fn then
    local ok, err = pcall(fn, ...)
    if not ok then U.Log("Errore", "avventure", event, err) end
  end
end)
-- the combat log: on the new clients (the ones with secret values, Midnight rules) registering it is forbidden to
-- addons and the game shows its "blocked" window at every login, so there it's left alone (falling and drowning
-- are still found by IsFalling and the breath bar)
if issecretvalue ~= nil then handlers.COMBAT_LOG_EVENT_UNFILTERED = nil end
for ev in pairs(handlers) do
  if ev == "UNIT_SPELLCAST_SUCCEEDED" and frame.RegisterUnitEvent then pcall(frame.RegisterUnitEvent, frame, ev, "player")
  else pcall(frame.RegisterEvent, frame, ev) end
end
-- falling is a state, not an event: look at it often (and how long it lasts: a jump isn't a fall)
function F.WatchFall()
  if Safe(IsFalling) == true then
    fallStart = fallStart or Now()
    lastFall = Now()
    lastFallDur = Now() - fallStart
  else
    fallStart = nil
  end
end

-- the deaths the game told twice (hunters and warlocks on Forever: PLAYER_DEAD comes twice, a second apart),
-- counted twice before 1.0.7: once per character, the doubles go from the journal, the gravestones and the count
local function SameDeath(a, b) return type(a.at) == "number" and type(b.at) == "number" and math.abs(a.at - b.at) <= 3 end
function F.FixDoubleDeaths()
  if not (Ready() and ns.db) then return 0 end
  ns.db.fixed = type(ns.db.fixed) == "table" and ns.db.fixed or {}
  local key = "deaths2:" .. tostring(ns.recordGuid)
  if ns.db.fixed[key] then return 0 end
  ns.db.fixed[key] = true
  local rec = ns.MyRecord()
  local j = Journal()
  local doubles, silly = {}, 0
  if j and type(j.deaths) == "table" then
    local keep = {}
    for _, d in ipairs(j.deaths) do
      local last = keep[#keep]
      if last and SameDeath(last, d) then doubles[#doubles + 1] = d.at else keep[#keep + 1] = d end
    end
    j.deaths = keep
  end
  if type(rec.rip) == "table" then
    local keep = {}
    for _, g in ipairs(rec.rip) do
      local last = keep[#keep]
      if last and SameDeath(last, g) then
        if F.SILLY[g.k] then silly = silly + 1 end
      else keep[#keep + 1] = g end
    end
    rec.rip = keep
  end
  local n = #doubles
  local t = rec.stats and rec.stats.t
  if t and n > 0 then
    t.dt = math.max(0, (t.dt or 0) - n)
    if silly > 0 then t.em = math.max(0, (t.em or 0) - silly) end
    -- the weeks still kept lose theirs too
    if P.HasSettings(ns.state) and type(rec.stats.w) == "table" then
      for _, at in ipairs(doubles) do
        local wk = M.WeekIndex(ns.state.settings, at)
        local w = rec.stats.w[wk]
        if type(w) == "table" and (w.dt or 0) > 0 then w.dt = w.dt - 1 end
      end
    end
  end
  if n > 0 or silly > 0 then
    rec.up = math.max(U.Now(), (rec.up or 0) + 1)
    U.Log("Fun", "morti contate due vorte, tolte:", n, "ridicole:", silly)
    ns.Fire("SelfChanged", ns.state, "fun")
  end
  return n
end

ns.On("J_Flight", function() Bump("fl") end)
ns.On("Login", function()
  if C_Timer then C_Timer.After(15, function() pcall(F.FixDoubleDeaths) end) end
  if C_Timer then
    -- a look at IsFalling every 0.15 seconds: one call to the game, nothing else
    C_Timer.NewTicker(0.15, F.WatchFall)
    C_Timer.NewTicker(2, function() local ok, err = pcall(F.SampleTravel) if not ok then U.Log("Errore", "viaggi", err) end end)
    C_Timer.After(20, function() F.RaiseFromGame() F.Sync() end)
  end
end)
