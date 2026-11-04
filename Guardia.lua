-- Er Patto: la guardia. Who plays with the addon turned off (to get rid of la pecora, say) is found in two ways,
-- and the capo (and the vice) sees it in Capo, Membri, and gets a line in the news:
--   1. by himself: the game's /played total (asked once at every login) against the time the addon was actually
--      running on that character. When the addon comes back, the difference is the time played without it
--      (more than ten minutes counts), written in his record (na).
--   2. by the others: someone of the patto online in the guild, in my group, or writing in a chat I can read,
--      while his addon has said nothing for more than ten minutes. Written in my record (nv), once every six
--      hours for the same one.
-- Cost: an addition every 30 seconds; a look at the group every minute and at the guild roster every five
-- minutes (a few dozen names); one table lookup per chat line from someone.
local ADDON, ns = ...
local U, P, UI = ns.U, ns.P, ns.UI
local G = {}
ns.Guardia = G

G.GAP = 600          -- ten minutes played without the addon count
G.SILENT = 600       -- seen online, addon silent for ten minutes
G.AGAIN = 6 * 3600   -- the same sighting at most once every six hours
G.KIND = { gilda = "online in gilda", gruppo = "in gruppo", chat = "scriveva in chat" }

local function Now() return U.Now() end
local function Clock() return GetTime and GetTime() or 0 end
local function Char() return UnitGUID and U.Plain(UnitGUID("player"), "string") or nil end
local function Short(m) return (tostring(m and m.name or "?"):match("^(%S+)")) or "?" end
local function Ready() return ns.state and ns.db and P.HasSettings(ns.state) and not ns.alt and ns.recordGuid end

----------------------------------------------------------------------
-- 1. my own time without the addon
----------------------------------------------------------------------
local lastTick
local function Awake()
  local c = Char()
  if not (c and ns.db) then return end
  local now = Clock()
  if lastTick then
    ns.db.awake = type(ns.db.awake) == "table" and ns.db.awake or {}
    ns.db.awake[c] = (ns.db.awake[c] or 0) + math.max(0, math.min(120, now - lastTick))
  end
  lastTick = now
end

function G.OnPlayed(total)
  total = U.Plain(total, "number")
  local c = Char()
  if not (total and c and ns.db) then return end
  Awake()
  ns.db.played = type(ns.db.played) == "table" and ns.db.played or {}
  local awake = ns.db.awake and ns.db.awake[c] or 0
  local last = ns.db.played[c]
  ns.db.played[c] = { t = total, a = awake }
  if type(last) ~= "table" or not last.t then return end
  local gap = math.floor((total - last.t) - (awake - (last.a or 0)))
  if gap < G.GAP or not Ready() or c ~= ns.recordGuid then return end
  local rec = ns.MyRecord and ns.MyRecord()
  if not rec then return end
  local list = { { at = Now(), s = gap } }
  for i = 1, 4 do if rec.na and rec.na[i] then list[#list + 1] = rec.na[i] end end
  P.UpdateSelf(ns.state, ns.recordGuid, { na = list }, "guardia")
end

----------------------------------------------------------------------
-- 2. the others: online, but their addon is silent
----------------------------------------------------------------------
local cand = {} -- guid -> { first = clock, k = kind }
local function ByName()
  local out = {}
  for g, m in pairs(ns.state and ns.state.members or {}) do
    if g ~= ns.recordGuid and type(m.name) == "string" then
      out[m.name] = g
      out[m.name:match("^([^%s%-]+)") or m.name] = g
    end
  end
  return out
end
local function Silent(guid)
  local C = ns.C
  if not (C and C.LastSeen) then return false end
  local last = C.LastSeen(guid)
  return not last or Clock() - last > G.SILENT
end
local function Saw(guid, kind)
  if not (guid and Silent(guid)) then return end
  local c = cand[guid]
  if not c then cand[guid] = { first = Clock(), k = kind } end
end
G.Saw = Saw

-- the ones seen online long enough with a silent addon: written down once
local function Settle()
  if not Ready() then return end
  local rec = ns.MyRecord and ns.MyRecord()
  if not rec then return end
  local now = Clock()
  local list
  for guid, c in pairs(cand) do
    if not Silent(guid) then cand[guid] = nil
    elseif now - c.first >= G.SILENT then
      cand[guid] = nil
      local recent
      for _, x in ipairs(rec.nv or {}) do if x.g == guid and Now() - (x.at or 0) < G.AGAIN then recent = true end end
      if not recent then
        list = list or { unpack(rec.nv or {}) }
        table.insert(list, 1, { g = guid, at = Now(), k = c.k })
        while #list > 5 do table.remove(list) end
      end
    end
  end
  if list then P.UpdateSelf(ns.state, ns.recordGuid, { nv = list }, "guardia") end
end

local function LookGroup()
  if not (Ready() and IsInGroup and UnitName) then return end
  local ok, grouped = pcall(IsInGroup)
  if not ok or U.IsSecret(grouped) or not grouped then return end
  local names = ByName()
  local raid = IsInRaid and IsInRaid()
  for i = 1, raid and 40 or 4 do
    local u = (raid and "raid" or "party") .. i
    local okn, n = pcall(UnitName, u)
    if okn and n and not U.IsSecret(n) and names[n] then
      local okc, on = pcall(UnitIsConnected, u)
      if okc and on == true then Saw(names[n], "gruppo") end
    end
  end
end

local guildAt = -1000
local function LookGuild()
  if Clock() - guildAt < 60 then return end
  guildAt = Clock()
  if not (Ready() and IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo) then return end
  local names = ByName()
  local ok, n = pcall(GetNumGuildMembers)
  if not ok or type(n) ~= "number" then return end
  for i = 1, math.min(n, 1000) do
    local okr, name, _, _, _, _, _, _, _, online = pcall(GetGuildRosterInfo, i)
    if okr and type(name) == "string" and not U.IsSecret(name) and online == true then
      local g = names[name] or names[name:match("^([^%-]+)") or name]
      if g then Saw(g, "gilda") end
    end
  end
end

function G.OnChat(author)
  if not (Ready() and type(author) == "string") or U.IsSecret(author) then return end
  local names = ByName()
  local g = names[author] or names[author:match("^([^%-]+)") or author]
  if g then Saw(g, "chat") end
end

----------------------------------------------------------------------
-- what the capo sees: per member, the time played without the addon and the sightings
----------------------------------------------------------------------
-- { [guid] = { gap = seconds (last 7 days), lines = { "..." }, at = last } }
function G.Report()
  local out = {}
  local all = ns.state and ns.state.members or {}
  local week = Now() - 7 * 86400
  local function get(g) out[g] = out[g] or { gap = 0, lines = {}, at = 0 } return out[g] end
  for g, m in pairs(all) do
    for _, x in ipairs(m.na or {}) do
      if (x.at or 0) >= week then
        local r = get(g)
        r.gap = r.gap + (x.s or 0)
        r.at = math.max(r.at, x.at or 0)
        r.lines[#r.lines + 1] = U.Day(x.at) .. ": " .. U.Until(x.s or 0) .. " de gioco senza addon (/played)"
      end
    end
    for _, x in ipairs(m.nv or {}) do
      if all[x.g] and (x.at or 0) >= week then
        local r = get(x.g)
        r.at = math.max(r.at, x.at or 0)
        r.lines[#r.lines + 1] = U.Day(x.at) .. ": " .. (G.KIND[x.k] or "online") .. " co' l'addon spento (l'ha visto " .. Short(m) .. ")"
      end
    end
  end
  return out
end

-- the capo hears it once, in the news
local function Tell()
  if not (Ready() and P.IsAdmin(ns.state, ns.recordGuid) and ns.News) then return end
  ns.db.guardia = type(ns.db.guardia) == "table" and ns.db.guardia or {}
  local told = ns.db.guardia
  for g, r in pairs(G.Report()) do
    if r.at > (told[g] or 0) then
      told[g] = r.at
      local m = ns.state.members[g]
      if m then ns.News.Add("|cffff4040" .. Short(m) .. " ha giocato co' l'addon spento|r: " .. (r.lines[1] or "") .. ".") end
    end
  end
end

----------------------------------------------------------------------
-- wiring
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
for _, e in ipairs({ "TIME_PLAYED_MSG", "GUILD_ROSTER_UPDATE", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD",
  "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER" }) do
  pcall(frame.RegisterEvent, frame, e)
end
frame:SetScript("OnEvent", function(_, event, a, b)
  if event == "TIME_PLAYED_MSG" then pcall(G.OnPlayed, a) if C_Timer then C_Timer.After(0, G.Loud) end
  elseif event == "GUILD_ROSTER_UPDATE" then pcall(LookGuild)
  else pcall(G.OnChat, b) end
end)

-- ask /played once per login, without the line in the chat windows (they listen again when the answer is in)
local quiet = {}
local function AskPlayed()
  if not RequestTimePlayed then return end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local f = _G["ChatFrame" .. i]
    if f and f.IsEventRegistered and f:IsEventRegistered("TIME_PLAYED_MSG") then
      pcall(f.UnregisterEvent, f, "TIME_PLAYED_MSG")
      quiet[#quiet + 1] = f
    end
  end
  pcall(RequestTimePlayed)
  if C_Timer then C_Timer.After(5, function() G.Loud() end) end
end
function G.Loud()
  for _, f in ipairs(quiet) do pcall(f.RegisterEvent, f, "TIME_PLAYED_MSG") end
  quiet = {}
end

ns.On("Login", function()
  if not C_Timer then return end
  lastTick = Clock()
  C_Timer.After(25, AskPlayed)
  C_Timer.NewTicker(30, function() pcall(Awake) end)
  C_Timer.NewTicker(60, function() pcall(LookGroup) pcall(Settle) pcall(Tell) end)
  C_Timer.NewTicker(300, function()
    if IsInGuild and IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
  end)
end)
G.Settle, G.LookGroup, G.LookGuild, G.Tell = Settle, LookGroup, LookGuild, Tell
