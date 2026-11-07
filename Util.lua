-- Er Patto: shared helpers (secret-safe printing, server time, Italian time, formatting, safe serializer).
local ADDON, ns = ...

-- the version comes from the TOC; CurseForge builds write the git tag there, a copy straight from git says "dev"
do
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, v = pcall(get or function() end, ADDON, "Version")
  ns.VERSION = (ok and type(v) == "string" and v ~= "" and not v:find("@", 1, true)) and v:gsub("^v", "") or "dev"
end
ns.PROTO = 1
local U = {}
ns.U = U

-- what the game blocks or forbids to the addon (its "blocked" window): caught from the very first file, so even
-- what happens while loading is kept; /patto bloccati shows it. The SavedVariables keep the last five.
U.blocked = {}
do
  local f = CreateFrame and CreateFrame("Frame")
  if f then
    pcall(f.RegisterEvent, f, "ADDON_ACTION_BLOCKED")
    pcall(f.RegisterEvent, f, "ADDON_ACTION_FORBIDDEN")
    f:SetScript("OnEvent", function(_, event, addon, fn)
      if addon ~= ADDON then return end
      local st = debugstack and tostring(debugstack(2, 12, 0)) or ""
      local x = { at = time and time() or 0, ev = event == "ADDON_ACTION_FORBIDDEN" and "proibito" or "bloccato", fn = tostring(fn), st = st:sub(1, 900) }
      table.insert(U.blocked, 1, x)
      if ns.db then
        ns.db.blocked = type(ns.db.blocked) == "table" and ns.db.blocked or {}
        table.insert(ns.db.blocked, 1, x)
        while #ns.db.blocked > 5 do table.remove(ns.db.blocked) end
      end
      if ns.OnBlocked then pcall(ns.OnBlocked, x) end
    end)
  end
end

----------------------------------------------------------------------
-- secret values (Midnight rules): never compare, concatenate or print them directly
----------------------------------------------------------------------
function U.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

function U.S(v)
  if U.IsSecret(v) then return "<segreto>" end
  if v == nil then return "nil" end
  return tostring(v)
end

-- Returns v when it is a plain value of the wanted Lua type, otherwise nil.
function U.Plain(v, kind)
  if U.IsSecret(v) or type(v) ~= kind then return nil end
  return v
end

----------------------------------------------------------------------
-- names: on WoW Forever a character has a name and a surname ("Er Nia"), and UnitName gives them apart
-- (name, surname); on retail the second value is the realm. The game's own NameUtil knows which.
----------------------------------------------------------------------
function U.FullName(unit)
  if NameUtil and NameUtil.GetUnmodifiedUnitFullName and UnitNameUnmodified then
    local ok, n = pcall(NameUtil.GetUnmodifiedUnitFullName, unit)
    if ok and type(n) == "string" and not U.IsSecret(n) and n ~= "" then return n end
  end
  if not UnitName then return nil end
  local ok, n = pcall(UnitName, unit)
  return ok and U.Plain(n, "string") or nil
end

-- where a line is too narrow for "Er Nia", the surname alone ("Nia"): on Forever many share the first name, so the
-- first name alone tells nobody apart
function U.Surnames(t)
  local st = ns.state
  if type(t) ~= "string" or not st then return t end
  for _, m in pairs(st.members) do
    local n = type(m.name) == "string" and U.Short(m.name)
    local rest = n and n:match("^%S+%s+(.+)$")
    if rest and t:find(n, 1, true) then
      t = t:gsub(n:gsub("(%W)", "%%%1"), (rest:gsub("%%", "%%%%")))
    end
  end
  return t
end

-- WoW Forever (interface 1.6x): names are "Name Surname", custom channels don't carry addon messages
function U.IsForever()
  if not GetBuildInfo then return false end
  local toc = select(4, GetBuildInfo())
  return type(toc) == "number" and toc >= 16000 and toc < 20000
end

-- one death, one count: WoW Forever sends PLAYER_DEAD twice for one death of a hunter or a warlock (seen in the
-- saved data: two gravestones a second apart, the second without the killer);
-- each part of the addon that hears it asks here, by its own key, and goes on only the first time
-- a battleground or an arena: dying there is the game, not a death of the patto (world PvP still counts)
-- the battlegrounds by name, as the English client writes them (the zone of a gravestone says where it was)
U.BATTLEGROUNDS = { ["Warsong Gulch"] = true, ["Arathi Basin"] = true, ["Alterac Valley"] = true, ["Eye of the Storm"] = true,
  ["Strand of the Ancients"] = true, ["Isle of Conquest"] = true, ["Twin Peaks"] = true, ["The Battle for Gilneas"] = true,
  ["Silvershard Mines"] = true, ["Temple of Kotmogu"] = true, ["Deepwind Gorge"] = true, ["Seething Shore"] = true }
function U.IsBattlegroundZone(z) return type(z) == "string" and U.BATTLEGROUNDS[z] == true end
function U.InBattleground()
  if IsInInstance then
    local ok, inside, kind = pcall(IsInInstance)
    if ok and not U.IsSecret(kind) and inside == true and (kind == "pvp" or kind == "arena") then return true end
  end
  local z = GetRealZoneText and GetRealZoneText()
  return not U.IsSecret(z) and U.IsBattlegroundZone(z)
end

-- where I stand, in yards on the continent's map (nil inside instances or when the client won't say)
function U.WorldPos()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
  local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
  if not ok or type(map) ~= "number" then return nil end
  local ok2, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
  if not ok2 or not pos then return nil end
  local ok3, inst, world = pcall(C_Map.GetWorldPosFromMapPos, map, pos)
  if not ok3 or not world then return nil end
  local x, y = world.x, world.y
  if world.GetXY then x, y = world:GetXY() end
  if U.IsSecret(x) or U.IsSecret(y) or type(x) ~= "number" or type(y) ~= "number" or type(inst) ~= "number" then return nil end
  return inst, x, y
end

local deathAt = {}
function U.FirstDeath(key)
  local now = GetTime and GetTime() or 0
  if deathAt[key] and now - deathAt[key] < 15 then return false end
  deathAt[key] = now
  return true
end

-- the name to show: no realm, no test mark ("Er Nia-Realm", "Dario (prova)" -> "Er Nia", "Dario")
function U.Short(name)
  if type(name) ~= "string" then return "?" end
  local s = name:gsub(" %(prova%)$", ""):match("^([^%-]+)")
  return s or name
end

----------------------------------------------------------------------
-- time: always the game server's clock, shown in Italian time
----------------------------------------------------------------------
function U.Now()
  if GetServerTime then return GetServerTime() end
  return time()
end

local floor = math.floor

-- Howard Hinnant's civil date algorithms, so no local-time functions are involved.
local function DaysFromCivil(y, m, d)
  if m <= 2 then y = y - 1 end
  local era = floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

local function CivilFromDays(z)
  z = z + 719468
  local era = floor(z / 146097)
  local doe = z - era * 146097
  local yoe = floor((doe - floor(doe / 1460) + floor(doe / 36524) - floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + floor(yoe / 4) - floor(yoe / 100))
  local mp = floor((5 * doy + 2) / 153)
  local d = doy - floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  if m <= 2 then y = y + 1 end
  return y, m, d
end

function U.UTCParts(t)
  local days = floor(t / 86400)
  local secs = t - days * 86400
  local y, m, d = CivilFromDays(days)
  return { year = y, month = m, day = d, hour = floor(secs / 3600), min = floor((secs % 3600) / 60),
    sec = secs % 60, wday = (days + 4) % 7 } -- wday: 0 = Sunday
end

function U.UTCEpoch(y, m, d, h, mi)
  return DaysFromCivil(y, m, d) * 86400 + (h or 0) * 3600 + (mi or 0) * 60
end

-- EU summer time: last Sunday of March 01:00 UTC to last Sunday of October 01:00 UTC.
local function LastSundayUTC(y, m)
  local ny, nm = y, m + 1
  if nm > 12 then ny, nm = y + 1, 1 end
  local lastDay = DaysFromCivil(ny, nm, 1) - 1
  local wd = (lastDay + 4) % 7
  return (lastDay - wd) * 86400 + 3600
end

function U.RomeOffset(t)
  local y = U.UTCParts(t).year
  if t >= LastSundayUTC(y, 3) and t < LastSundayUTC(y, 10) then return 7200 end
  return 3600
end

function U.RomeParts(t)
  return U.UTCParts(t + U.RomeOffset(t))
end

-- Italian wall-clock time to epoch seconds.
function U.FromRome(y, m, d, h, mi)
  local guess = U.UTCEpoch(y, m, d, h, mi)
  local t = guess - U.RomeOffset(guess)
  return guess - U.RomeOffset(t)
end

local WD = { "dom", "lun", "mar", "mer", "gio", "ven", "sab" }
local MO = { "gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic" }

function U.Day(t)
  local p = U.RomeParts(t)
  return WD[p.wday + 1] .. " " .. p.day .. " " .. MO[p.month]
end

function U.HM(t)
  local p = U.RomeParts(t)
  return string.format("%02d:%02d", p.hour, p.min)
end

function U.When(t)
  return U.Day(t) .. " a le " .. U.HM(t)
end

-- "2026-11-05 00:00" or "05/11/2026 00:00" (Italian time) to epoch, or nil.
function U.ParseRome(text)
  text = tostring(text or "")
  local y, m, d, h, mi = string.match(text, "^%s*(%d%d%d%d)%-(%d%d?)%-(%d%d?)%s*(%d?%d?):?(%d?%d?)%s*$")
  if not y then
    d, m, y, h, mi = string.match(text, "^%s*(%d%d?)/(%d%d?)/(%d%d%d%d)%s*(%d?%d?):?(%d?%d?)%s*$")
  end
  if not y then return nil end
  y, m, d, h, mi = tonumber(y), tonumber(m), tonumber(d), tonumber(h) or 0, tonumber(mi) or 0
  if m < 1 or m > 12 or d < 1 or d > 31 or h > 23 or mi > 59 then return nil end
  return U.FromRome(y, m, d, h, mi)
end

function U.FormatRomeInput(t)
  local p = U.RomeParts(t)
  return string.format("%04d-%02d-%02d %02d:%02d", p.year, p.month, p.day, p.hour, p.min)
end

----------------------------------------------------------------------
-- formatting in Roman dialect
----------------------------------------------------------------------
function U.Until(sec)
  if sec <= 0 then return "mo'" end
  local m = floor(sec / 60)
  local d, h, mm = floor(m / 1440), floor((m % 1440) / 60), m % 60
  if d > 0 then
    return d .. (d == 1 and " giorno" or " giorni") .. (h > 0 and (" e " .. h .. (h == 1 and " ora" or " ore")) or "")
  end
  if h > 0 then
    return h .. (h == 1 and " ora" or " ore") .. (mm > 0 and (" e " .. mm .. " min") or "")
  end
  return mm .. " min"
end

function U.Hours(h)
  if h < 1 then return math.max(1, floor(h * 60 + 0.5)) .. " min" end
  local r = floor(h * 2 + 0.5) / 2
  local txt = (r == floor(r)) and tostring(r) or string.gsub(string.format("%.1f", r), "%.", ",")
  return txt .. (r == 1 and " ora" or " ore")
end

function U.Thousands(n)
  local s = tostring(floor(n + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
  return (out:gsub("^%.", ""))
end

function U.Ago(sec)
  if not sec or sec < 0 then return "mai" end
  if sec < 90 then return "mo'" end
  if sec < 3600 then return floor(sec / 60) .. " min fa" end
  if sec < 86400 then return floor(sec / 3600) .. (floor(sec / 3600) == 1 and " ora fa" or " ore fa") end
  return floor(sec / 86400) .. (floor(sec / 86400) == 1 and " giorno fa" or " giorni fa")
end

function U.Copy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = U.Copy(v) end
  return c
end

----------------------------------------------------------------------
-- safe serializer: strings, numbers, booleans and nested tables only; never runs received text as code
----------------------------------------------------------------------
local function Esc(s)
  return (s:gsub("[\\|{}=,;~\n\r]", function(c) return string.format("\\%02X", string.byte(c)) end))
end

local function Ser(v, depth)
  local tv = type(v)
  if tv == "string" then return "s" .. Esc(v) end
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "n0" end
    if v == floor(v) then return "n" .. string.format("%d", v) end
    return "n" .. string.format("%.4f", v)
  end
  if tv == "boolean" then return v and "T" or "F" end
  if tv == "table" then
    if depth > 6 then return "N" end
    local parts = {}
    for k, val in pairs(v) do
      if (type(k) == "string" or type(k) == "number") and type(val) ~= "function" then
        parts[#parts + 1] = Ser(k, depth + 1) .. "=" .. Ser(val, depth + 1)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "N"
end

function U.Serialize(v)
  return Ser(v, 0)
end

local MAX_ITEMS = 2000

function U.Deserialize(text)
  if type(text) ~= "string" or #text > 60000 then return nil end
  local pos, items = 1, 0
  local function unesc(s)
    return (s:gsub("\\(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
  end
  local parse
  local function scalarEnd()
    local e = pos
    while e <= #text do
      local c = text:sub(e, e)
      if c == "," or c == "}" or c == "=" then break end
      e = e + 1
    end
    return e
  end
  parse = function(depth)
    items = items + 1
    if depth > 7 or items > MAX_ITEMS then error("troppo") end
    local c = text:sub(pos, pos)
    if c == "{" then
      pos = pos + 1
      local t = {}
      if text:sub(pos, pos) == "}" then pos = pos + 1 return t end
      while true do
        local k = parse(depth + 1)
        if text:sub(pos, pos) ~= "=" then error("manca =") end
        pos = pos + 1
        local v = parse(depth + 1)
        if type(k) == "string" or type(k) == "number" then t[k] = v end
        local sep = text:sub(pos, pos)
        pos = pos + 1
        if sep == "}" then return t end
        if sep ~= "," then error("separatore") end
      end
    elseif c == "s" then
      pos = pos + 1
      local e = scalarEnd()
      local s = unesc(text:sub(pos, e - 1))
      pos = e
      return s
    elseif c == "n" then
      pos = pos + 1
      local e = scalarEnd()
      local n = tonumber(text:sub(pos, e - 1))
      pos = e
      if not n then error("numero") end
      return n
    elseif c == "T" then pos = pos + 1 return true
    elseif c == "F" then pos = pos + 1 return false
    elseif c == "N" then pos = pos + 1 return nil
    end
    error("tipo")
  end
  local ok, res = pcall(parse, 0)
  if not ok or pos ~= #text + 1 then return nil end
  return res
end

----------------------------------------------------------------------
-- small string hash (codes, channel password); not security, just obfuscation
----------------------------------------------------------------------
function U.Hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 4294967296 end
  return h
end

local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
function U.RandomCode(n)
  local out = {}
  for i = 1, n do
    local r = math.random(1, #ALPHABET)
    out[i] = ALPHABET:sub(r, r)
  end
  return table.concat(out)
end
U.ALPHABET = ALPHABET

----------------------------------------------------------------------
-- log (kept in SavedVariables for the diagnostics tab)
----------------------------------------------------------------------
local pendingLog = {}
function U.Log(cat, ...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = U.S((select(i, ...))) end
  local line = (date and date("!%H:%M:%S", U.Now()) or "") .. " [" .. cat .. "] " .. table.concat(parts, " ")
  local db = ns.db
  if not db then pendingLog[#pendingLog + 1] = line return end
  db.log = db.log or {}
  for _, l in ipairs(pendingLog) do table.insert(db.log, l) end
  pendingLog = {}
  table.insert(db.log, line)
  while #db.log > 400 do table.remove(db.log, 1) end
  if ns.OnLog then ns.OnLog() end
end

function U.Say(msg)
  if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Er Patto:|r " .. msg) end
end

-- simple event bus between modules
local listeners = {}
function ns.On(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end
function ns.Fire(name, ...)
  for _, fn in ipairs(listeners[name] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then U.Log("Errore", name, err) end
  end
end
