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
local breathUntil, lastFall = 0, 0
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
  if Now() < breathUntil then kind = "affogato"
  elseif Safe(IsFalling) == true or Now() - lastFall < 2.5 then kind = "cascato"
  elseif kPlayer then kind = "pvp"
  elseif killer and (kType == "Critter" or (kLv and kLv > 0 and kLv <= myLv - 5)) then kind = "pischello"
  end
  return kind, killer, kLv
end

F.SILLY = { cascato = true, affogato = true, pischello = true }

function F.OnDeath()
  if not Ready() then return end
  local kind, killer = F.DeathKind()
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
  MIRROR_TIMER_START = function(timer) if timer == "BREATH" then breathUntil = Now() + 600 end end,
  MIRROR_TIMER_STOP = function(timer) if timer == "BREATH" then breathUntil = Now() + 1 end end,
  ENCOUNTER_END = function(_, name, _, _, success)
    if success == 1 or success == true then Named(Plain(name, "string")) end
  end,
  UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
    if unit == "player" and Plain(spellID, "number") == 8690 then Bump("hs") end
  end,
  PLAYER_LEVEL_UP = function() if C_Timer then C_Timer.After(5, F.RaiseFromGame) end end,
}
frame:SetScript("OnEvent", function(_, event, ...)
  local fn = handlers[event]
  if fn then
    local ok, err = pcall(fn, ...)
    if not ok then U.Log("Errore", "avventure", event, err) end
  end
end)
for ev in pairs(handlers) do
  if ev == "UNIT_SPELLCAST_SUCCEEDED" and frame.RegisterUnitEvent then pcall(frame.RegisterUnitEvent, frame, ev, "player")
  else pcall(frame.RegisterEvent, frame, ev) end
end
-- falling is a state, not an event: look at it often while it lasts
local acc = 0
frame:SetScript("OnUpdate", function(_, elapsed)
  acc = acc + (elapsed or 0)
  if acc < 0.15 then return end
  acc = 0
  if Safe(IsFalling) == true then lastFall = Now() end
end)

ns.On("J_Flight", function() Bump("fl") end)
ns.On("Login", function()
  if C_Timer then
    C_Timer.NewTicker(2, function() local ok, err = pcall(F.SampleTravel) if not ok then U.Log("Errore", "viaggi", err) end end)
    C_Timer.After(20, function() F.RaiseFromGame() F.Sync() end)
  end
end)
