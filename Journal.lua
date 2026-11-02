-- Er Patto: the journal. A raw record of the adventure, kept on this account for every character, so that a future
-- version can show (or turn into titles) things nobody thought of yet: which mobs you killed and how many times,
-- what dropped, where the gold came from and where it went, who you played with, how you died, and so on.
-- Nothing here is sent to the others: a later version can share totals computed from it.
-- Every list has a cap and every table only grows by keys that matter, so the saved file stays small.
local ADDON, ns = ...
local U, T = ns.U, ns.T
local J = {}
ns.J = J

J.VERSION = 1
local CAP = { deaths = 300, levels = 70, loot = 600, equip = 300, dungeons = 300, bgs = 300, duels = 400, flights = 300,
  profs = 400, sessions = 200, rep = 60 }

local function Plain(v, kind) return U.Plain(v, kind) end
local function Safe(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, g, h, i = pcall(f, ...)
  if not ok then return nil end
  return a, b, c, d, e, g, h, i
end

local function Zone()
  local z = GetRealZoneText and Plain(Safe(GetRealZoneText), "string")
  return (z and z ~= "") and z or nil
end

local function Level() return Plain(Safe(UnitLevel, "player"), "number") end

-- the journal of the logged-in character
function J.Get()
  if not (ns.db and ns.me) then return nil end
  ns.db.journal = ns.db.journal or {}
  local j = ns.db.journal[ns.me]
  if not j then
    j = { v = J.VERSION, name = ns.myName, since = U.Now() }
    ns.db.journal[ns.me] = j
  end
  for _, k in ipairs({ "kills", "items", "spells", "zones", "together", "money", "xp", "deaths", "levels", "loot", "equip",
    "dungeons", "bgs", "duels", "flights", "profs", "sessions", "rep", "counters" }) do
    j[k] = j[k] or {}
  end
  return j
end

local function Push(list, entry, cap)
  table.insert(list, entry)
  while #list > cap do table.remove(list, 1) end
end

local function Add(t, key, n)
  t[key] = (t[key] or 0) + (n or 1)
end

----------------------------------------------------------------------
-- kills: mobs you had targeted when they died with your tag, and corpses you looted. Each mob counts once.
----------------------------------------------------------------------
local counted, seenName = {}, {}

local function NpcOf(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, _, _, id = guid:match("^(%a+)%-([^-]*)%-([^-]*)%-([^-]*)%-([^-]*)%-([^-]*)")
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end

local function Remember(unit)
  local guid = Plain(Safe(UnitGUID, unit), "string")
  if not guid or not NpcOf(guid) then return end
  local name = Plain(Safe(UnitName, unit), "string")
  if name then
    seenName[guid] = { n = name, lv = Plain(Safe(UnitLevel, unit), "number"), c = Plain(Safe(UnitClassification, unit), "string"),
      t = Plain(Safe(UnitCreatureType, unit), "string") }
  end
end

local function CountKill(guid)
  if counted[guid] then return end
  counted[guid] = true
  local j = J.Get()
  local id = NpcOf(guid)
  if not (j and id) then return end
  local info = seenName[guid] or {}
  local k = j.kills[id] or { n = info.n, c = 0 }
  k.c = k.c + 1
  k.n = k.n or info.n
  k.lv = info.lv or k.lv
  k.cl = info.c or k.cl
  k.ty = info.t or k.ty
  k.last = U.Now()
  k.z = Zone() or k.z
  j.kills[id] = k
  Add(j.counters, "kills")
  if info.c == "elite" or info.c == "rareelite" or info.c == "worldboss" then Add(j.counters, "eliteKills") end
  ns.Fire("J_Kill", id, k)
end

function J.CheckDeath(unit)
  local guid = Plain(Safe(UnitGUID, unit), "string")
  if not guid or not NpcOf(guid) then return end
  Remember(unit)
  if Safe(UnitIsDead, unit) == true and Safe(UnitIsTapDenied, unit) ~= true then CountKill(guid) end
end

----------------------------------------------------------------------
-- loot window: every corpse you loot is a kill; items with source, fishing apart
----------------------------------------------------------------------
local function QualityOfLink(link)
  local id = link and tonumber(link:match("item:(%d+)"))
  if not id then return nil, nil end
  local q
  if C_Item and C_Item.GetItemQualityByID then q = Plain(Safe(C_Item.GetItemQualityByID, id), "number") end
  if not q then
    local hex = link:match("|c(%x%x%x%x%x%x%x%x)")
    local map = { ff9d9d9d = 0, ffffffff = 1, ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5 }
    q = hex and map[hex:lower()]
  end
  return id, q
end

function J.OnLootOpened()
  local j = J.Get()
  if not j then return end
  local fishing = Safe(IsFishingLoot) == true
  if fishing then
    Add(j.counters, "fishingLoots")
    local caught = 0
    for slot = 1, Plain(Safe(GetNumLootItems), "number") or 0 do
      local _, _, qty = Safe(GetLootSlotInfo, slot)
      caught = caught + (Plain(qty, "number") or 1)
    end
    ns.Fire("J_Fish", math.max(1, caught))
  end
  local n = Plain(Safe(GetNumLootItems), "number") or 0
  for slot = 1, n do
    if GetLootSourceInfo then
      local src = { Safe(GetLootSourceInfo, slot) }
      for i = 1, #src, 2 do
        local g = Plain(src[i], "string")
        if g and NpcOf(g) then CountKill(g) end
      end
    end
    local link = Plain(Safe(GetLootSlotLink, slot), "string")
    if link then
      local id, q = QualityOfLink(link)
      if id and q and q >= 2 then
        Push(j.loot, { id = id, q = q, at = U.Now(), z = Zone(), lv = Level(), fish = fishing or nil }, CAP.loot)
      end
    end
  end
end

-- what lands in the bags (loot, quest rewards, crafts, purchases), counted by item
local lootPats
-- "You receive loot: %sx%d." -> "^You receive loot: (.+)x(%d+)%.$" (positional %1$s too)
local function LootPattern(fmt)
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%%d%%%$d", "(%%d+)"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end

function J.OnLootMessage(msg)
  if type(msg) ~= "string" or U.IsSecret(msg) then return end
  local j = J.Get()
  if not j then return end
  lootPats = lootPats or {}
  if not lootPats.ready then
    lootPats.ready = true
    for _, k in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF",
      "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }) do
      local fmt = _G[k]
      if type(fmt) == "string" then
        lootPats[#lootPats + 1] = { pat = LootPattern(fmt), created = k:find("CREATED") and true, pushed = k:find("PUSHED") and true }
      end
    end
  end
  for _, p in ipairs(lootPats) do
    local caps = p.pat and { string.match(msg, p.pat) }
    if caps and #caps > 0 then
      local link = caps[1]
      local count = tonumber(caps[2] or "") or 1
      local id, q = QualityOfLink(link)
      if id then
        local it = j.items[id] or { c = 0 }
        it.c = it.c + count
        it.q = q or it.q
        it.first = it.first or U.Now()
        if p.created then it.made = (it.made or 0) + count end
        j.items[id] = it
        ns.Fire("J_Item", id, q, count, p.created and "created" or (p.pushed and "pushed" or "loot"), link)
      end
      return
    end
  end
end

----------------------------------------------------------------------
-- experience: from quests and from everything else
----------------------------------------------------------------------
local lastXp, lastXpMax, lastLevel
function J.OnXp()
  local j = J.Get()
  if not j then return end
  local xp, xpm, lv = Plain(Safe(UnitXP, "player"), "number"), Plain(Safe(UnitXPMax, "player"), "number"), Level()
  if not (xp and xpm and lv) then return end
  if lastXp and lastLevel then
    local gain
    if lv == lastLevel then gain = xp - lastXp
    elseif lv == lastLevel + 1 then gain = (lastXpMax - lastXp) + xp end
    if gain and gain > 0 then Add(j.xp, "total", gain) end
  end
  lastXp, lastXpMax, lastLevel = xp, xpm, lv
end

----------------------------------------------------------------------
-- gold: every change, filed under where you were when it happened
----------------------------------------------------------------------
local open = {}
local lastMoney, lastQuestAt = nil, 0
local PLACES = { MERCHANT_SHOW = "merchant", TRAINER_SHOW = "trainer", TAXIMAP_OPENED = "taxi", MAIL_SHOW = "mail",
  AUCTION_HOUSE_SHOW = "auction", TRADE_SHOW = "trade", BANKFRAME_OPENED = "bank", LOOT_OPENED = "loot" }
local CLOSES = { MERCHANT_CLOSED = "merchant", TRAINER_CLOSED = "trainer", TAXIMAP_CLOSED = "taxi", MAIL_CLOSED = "mail",
  AUCTION_HOUSE_CLOSED = "auction", TRADE_CLOSED = "trade", BANKFRAME_CLOSED = "bank", LOOT_CLOSED = "loot" }

local function Where()
  if U.Now() - lastQuestAt <= 2 then return "quest" end
  for _, k in ipairs({ "auction", "mail", "trade", "taxi", "trainer", "merchant", "bank", "loot" }) do
    if open[k] then return k end
  end
  return "other"
end

function J.OnMoney()
  local j = J.Get()
  local m = Plain(Safe(GetMoney), "number")
  if not (j and m) then return end
  if lastMoney and m ~= lastMoney then
    local d = m - lastMoney
    local where = Where()
    if d > 0 then Add(j.money, "in_" .. where, d) else Add(j.money, "out_" .. where, -d) end
    if where == "taxi" and d < 0 then
      Push(j.flights, { at = U.Now(), from = Zone(), cost = -d }, CAP.flights)
      Add(j.counters, "flights")
      ns.Fire("J_Flight")
    end
  end
  lastMoney = m
  if m > (j.money.peak or 0) then j.money.peak = m end
end

----------------------------------------------------------------------
-- places, people, time
----------------------------------------------------------------------
local currentZone
function J.OnZone()
  local j = J.Get()
  local z = Zone()
  if not (j and z) then return end
  currentZone = z
  local e = j.zones[z] or { first = U.Now(), sec = 0, visits = 0 }
  e.visits = e.visits + 1
  j.zones[z] = e
end

-- every minute: time in the zone, time grouped, and with which patto members
function J.Minute()
  local j = J.Get()
  if not j then return end
  local z = currentZone or Zone()
  if z then
    local e = j.zones[z] or { first = U.Now(), sec = 0, visits = 1 }
    e.sec = e.sec + 60
    j.zones[z] = e
  end
  local inGroup = Safe(IsInGroup) == true
  if inGroup then
    Add(j.counters, "groupSec", 60)
    local state = ns.state
    local units = {}
    if Safe(IsInRaid) == true then for i = 1, 40 do units[#units + 1] = "raid" .. i end
    else for i = 1, 4 do units[#units + 1] = "party" .. i end end
    for _, u in ipairs(units) do
      local g = Plain(Safe(UnitGUID, u), "string")
      if g and g ~= ns.me then
        local key = (state and state.members[g]) and g or nil
        if key then Add(j.together, key, 60) end
      end
    end
  end
  if Safe(IsResting) == true then Add(j.counters, "restingSec", 60) end
end

----------------------------------------------------------------------
-- life events
----------------------------------------------------------------------
function J.OnDeath()
  local j = J.Get()
  if not j then return end
  local killer
  if Safe(UnitExists, "target") == true and Safe(UnitCanAttack, "player", "target") == true then
    killer = Plain(Safe(UnitName, "target"), "string")
  end
  local _, kind = Safe(GetInstanceInfo)
  Push(j.deaths, { at = U.Now(), z = Zone(), lv = Level(), by = killer, inst = Plain(kind, "string") }, CAP.deaths)
end

function J.OnLevel(level)
  local j = J.Get()
  if not j then return end
  local rec = ns.MyRecord and ns.MyRecord()
  Push(j.levels, { lv = Plain(level, "number") or Level(), at = U.Now(), z = Zone(),
    pt = rec and rec.stats and rec.stats.t and rec.stats.t.pt or nil }, CAP.levels)
end

function J.OnSpell(unit, _, spellID)
  if unit ~= "player" then return end
  local j = J.Get()
  local id = Plain(spellID, "number")
  if not (j and id) then return end
  local e = j.spells[id]
  if not e then
    local n = 0
    for _ in pairs(j.spells) do n = n + 1 end
    if n >= 1500 then return end
    local name = C_Spell and C_Spell.GetSpellName and Plain(Safe(C_Spell.GetSpellName, id), "string")
      or (GetSpellInfo and Plain(Safe(GetSpellInfo, id), "string"))
    e = { n = name, c = 0 }
    j.spells[id] = e
  end
  e.c = e.c + 1
end

function J.OnEquip(slot)
  local j = J.Get()
  slot = Plain(slot, "number")
  if not (j and slot and GetInventoryItemLink) then return end
  local link = Plain(Safe(GetInventoryItemLink, "player", slot), "string")
  if not link then return end
  local id, q = QualityOfLink(link)
  local last = j.equip[#j.equip]
  if last and last.slot == slot and last.id == id then return end
  Push(j.equip, { slot = slot, id = id, q = q, il = T.LinkLevel and T.LinkLevel(link), at = U.Now(), lv = Level() }, CAP.equip)
end

-- professions: a line each time a skill goes up
local lastProf = {}
function J.OnProfessions()
  local j = J.Get()
  if not (j and T.Professions) then return end
  for _, p in ipairs(T.Professions()) do
    if lastProf[p.n] and p.l > lastProf[p.n] then
      Push(j.profs, { n = p.n, l = p.l, at = U.Now() }, CAP.profs)
    end
    lastProf[p.n] = p.l
  end
end

-- reputation, once a day
function J.Reputation()
  local j = J.Get()
  if not j then return end
  if j.repAt and U.Now() - j.repAt < 86400 then return end
  local snap = {}
  if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
    for i = 1, (Safe(C_Reputation.GetNumFactions) or 0) do
      local d = Safe(C_Reputation.GetFactionDataByIndex, i)
      if type(d) == "table" and not d.isHeader and d.name then snap[d.name] = { s = d.reaction, v = d.currentStanding } end
    end
  elseif GetNumFactions and GetFactionInfo then
    for i = 1, (Safe(GetNumFactions) or 0) do
      local name, _, standing, _, _, value, _, _, header = Safe(GetFactionInfo, i)
      if name and not header then snap[name] = { s = standing, v = value } end
    end
  end
  if next(snap) then
    j.repAt = U.Now()
    Push(j.rep, { at = U.Now(), f = snap }, CAP.rep)
  end
end

----------------------------------------------------------------------
-- from the tracker: quests, dungeons, battlegrounds, duels
----------------------------------------------------------------------
ns.On("J_Quest", function(entry)
  local j = J.Get()
  if not j then return end
  lastQuestAt = U.Now()
  Add(j.counters, "quests")
  if entry and entry.xp then Add(j.xp, "quest", entry.xp) end
  if entry and entry.money then Add(j.money, "questRewards", entry.money) end
end)

ns.On("J_Dungeon", function(run, counted)
  local j = J.Get()
  if not (j and run) then return end
  local mates = {}
  local state = ns.state
  for i = 1, 4 do
    local g = Plain(Safe(UnitGUID, "party" .. i), "string")
    if g and state and state.members[g] then mates[#mates + 1] = state.members[g].name end
  end
  Push(j.dungeons, { n = run.name, at = run.at, sec = U.Now() - (run.at or U.Now()), bosses = run.bosses, lv = Level(),
    counted = counted or nil, with = #mates > 0 and mates or nil }, CAP.dungeons)
end)

ns.On("J_BG", function(won, sec)
  local j = J.Get()
  if not j then return end
  local name = Safe(GetInstanceInfo)
  Push(j.bgs, { n = Plain(name, "string"), won = won and true or false, sec = sec, at = U.Now(), lv = Level() }, CAP.bgs)
end)

ns.On("J_Duel", function(opp, won)
  local j = J.Get()
  if not j then return end
  Push(j.duels, { o = opp, won = won and true or false, at = U.Now(), z = Zone(), lv = Level() }, CAP.duels)
end)

ns.On("J_Boss", function()
  local j = J.Get()
  if j then Add(j.counters, "bossKills") end
end)

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {
  PLAYER_TARGET_CHANGED = function() J.CheckDeath("target") end,
  UPDATE_MOUSEOVER_UNIT = function() Remember("mouseover") end,
  NAME_PLATE_UNIT_ADDED = function(unit) Remember(unit) end,
  UNIT_HEALTH = function(unit) if unit == "target" then J.CheckDeath("target") end end,
  LOOT_OPENED = function() open.loot = true J.CheckDeath("target") J.OnLootOpened() end,
  CHAT_MSG_LOOT = function(msg) J.OnLootMessage(msg) end,
  PLAYER_XP_UPDATE = function() J.OnXp() end,
  PLAYER_LEVEL_UP = function(level) J.OnLevel(level) J.OnXp() end,
  PLAYER_MONEY = function() J.OnMoney() end,
  ZONE_CHANGED_NEW_AREA = function() J.OnZone() end,
  PLAYER_DEAD = function() J.OnDeath() end,
  UNIT_SPELLCAST_SUCCEEDED = function(...) J.OnSpell(...) end,
  PLAYER_EQUIPMENT_CHANGED = function(slot) J.OnEquip(slot) end,
  SKILL_LINES_CHANGED = function() J.OnProfessions() end,
  UPDATE_FACTION = function() J.Reputation() end,
  PLAYER_LOGOUT = function()
    local j = J.Get()
    local s = j and j.sessions[#j.sessions]
    if s and not s.out then s.out = U.Now() end
  end,
}
for ev, place in pairs(PLACES) do
  local prev = handlers[ev]
  handlers[ev] = function(...) open[place] = true if prev then prev(...) end end
end
for ev, place in pairs(CLOSES) do
  local prev = handlers[ev]
  -- the money can arrive just after the window closes
  handlers[ev] = function(...)
    if C_Timer then C_Timer.After(2, function() open[place] = nil end) else open[place] = nil end
    if prev then prev(...) end
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local fn = handlers[event]
  if fn then
    local ok, err = pcall(fn, ...)
    if not ok then U.Log("Errore", "diario", event, err) end
  end
end)

local UNIT_ONLY = { UNIT_HEALTH = "target", UNIT_SPELLCAST_SUCCEEDED = "player" }
for ev in pairs(handlers) do
  if UNIT_ONLY[ev] and frame.RegisterUnitEvent then pcall(frame.RegisterUnitEvent, frame, ev, UNIT_ONLY[ev])
  else pcall(frame.RegisterEvent, frame, ev) end
end

ns.On("Login", function()
  local j = J.Get()
  if not j then return end
  Push(j.sessions, { at = U.Now(), lv = Level() }, CAP.sessions)
  Add(j.counters, "logins")
  lastMoney = Plain(Safe(GetMoney), "number")
  J.OnXp()
  J.OnZone()
  for _, p in ipairs(T.Professions and T.Professions() or {}) do lastProf[p.n] = p.l end
  if C_Timer then
    C_Timer.NewTicker(60, function() pcall(J.Minute) end)
    C_Timer.After(20, function() pcall(J.Reputation) end)
  end
end)
