-- Er Patto: what my own character does (level, XP, quests, duels, dungeons, BGs) and the warnings before going over the cap.
-- Everything here only reads plain values; anything secret is skipped.
local ADDON, ns = ...
local U, M, P = ns.U, ns.M, ns.P
local T = {}
ns.T = T

local state, me, myName, myShort, myGuid
local Milestone -- defined with the adventure trackers below
local altMode = false
local warned = {}
local bg = nil

-- in alt mode the record belongs to the main character: nothing the alt does is counted
local function Ready()
  return state and not altMode and state.members[me] ~= nil
end

function T.IsAlt() return altMode end
function T.Ready() return Ready() end

local function Week()
  if not P.HasSettings(state) then return 0 end
  return M.WeekIndex(state.settings, U.Now())
end

local function Bump(key, n)
  local rec = state.members[me]
  rec.stats = rec.stats or { t = {}, w = {} }
  rec.stats.t = rec.stats.t or {}
  rec.stats.w = rec.stats.w or {}
  rec.stats.t[key] = (rec.stats.t[key] or 0) + (n or 1)
  local wk = Week()
  rec.stats.w[wk] = rec.stats.w[wk] or {}
  rec.stats.w[wk][key] = (rec.stats.w[wk][key] or 0) + (n or 1)
  for k in pairs(rec.stats.w) do if k < wk - 1 then rec.stats.w[k] = nil end end
  rec.up = U.Now()
  ns.Fire("SelfChanged", state, key)
end
T.Bump = Bump

-- my team's cap right now, or nil
function T.MyCap()
  if not Ready() or not P.HasSettings(state) then return nil end
  local rec = state.members[me]
  if not rec.team then return nil end
  local st = M.Status(state.settings, rec.team, U.Now())
  return st and st.cap, st
end

-- quiet: no box of its own (the quest warning has one, over the quest window)
local function Alert(text, key, quiet)
  if key then
    if warned[key] then return end
    warned[key] = true
  end
  U.Say("|cffff4040" .. text .. "|r")
  if not quiet and ns.News and ns.News.Annuncio then
    ns.News.Annuncio({ head = "Occhio ar cap!", title = text, color = { 1, 0.3, 0.3 }, icon = "Interface\\Icons\\INV_Misc_PocketWatch_01", secs = 8, force = true })
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
  ns.Fire("Alert", text)
end
T.Alert = Alert

----------------------------------------------------------------------
-- level, XP, zone
----------------------------------------------------------------------
-- the other characters of this account in this patto: the ones the player linked as alts, and the ones that joined
-- it as members of their own (so nobody bets on himself). One never linked stays out: the friends don't see it
local function AltsOf()
  local alts = {}
  local code = state and state.code
  for g, c in pairs(ns.db and ns.db.chars or {}) do
    if g ~= me and c.name and code and (c.alt == code or c.code == code) and #alts < 6 then
      alts[#alts + 1] = { name = c.name, lv = c.lv or 1, cls = c.cls }
    end
  end
  table.sort(alts, function(a, b) return a.lv > b.lv or (a.lv == b.lv and a.name < b.name) end)
  return alts
end

local function SameAlts(a, b)
  a, b = a or {}, b or {}
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i].name ~= b[i].name or a[i].lv ~= b[i].lv or a[i].cls ~= b[i].cls then return false end
  end
  return true
end

-- remember this character in the account-wide list (used for alts)
local function NoteChar(lv, cls)
  if not (ns.db and myGuid) then return end
  ns.db.chars = ns.db.chars or {}
  local c = ns.db.chars[myGuid] or {}
  c.name = myName or c.name
  if lv then c.lv = lv end
  if cls then c.cls = cls end
  ns.db.chars[myGuid] = c
end

function T.RefreshSelf(reason, levelOverride)
  if not state then return end
  local lv = levelOverride or U.Plain(UnitLevel("player"), "number")
  local cls
  if UnitClass then cls = select(2, UnitClass("player")) end
  cls = U.Plain(cls, "string")
  NoteChar(lv, cls)
  if altMode then
    -- an alt only refreshes the main's list of alts
    local rec = state.members[me]
    local alts = AltsOf()
    if rec and not SameAlts(alts, rec.alts) then P.UpdateSelf(state, me, { alts = alts }, "alts") end
    return
  end
  if not Ready() then return end
  -- the name too: on Forever the first versions kept only the first name ("Er" instead of "Er Nia")
  local fields = { ver = ns.VERSION, name = myName }
  if lv then fields.lv = lv end
  local xp, xpm = U.Plain(UnitXP("player"), "number"), U.Plain(UnitXPMax("player"), "number")
  if xp and xpm then fields.xp, fields.xpm = xp, xpm end
  if GetXPExhaustion then
    local rest = GetXPExhaustion()
    if not U.IsSecret(rest) then fields.rest = rest or 0 end
  end
  local zone = GetRealZoneText and GetRealZoneText()
  if type(zone) == "string" and not U.IsSecret(zone) and zone ~= "" then fields.zone = zone end
  if cls then fields.cls = cls end
  local il = T.ItemLevel()
  if il then fields.il = il end
  local raceFile, raceId
  if UnitRace then raceFile, raceId = select(2, UnitRace("player")) end
  fields.race = U.Plain(raceFile, "string")
  fields.rid = U.Plain(raceId, "number")
  fields.sex = UnitSex and U.Plain(UnitSex("player"), "number") or nil
  fields.eq = T.Equipment()
  -- alts of this account, so friends see them under my main
  local alts = AltsOf()
  if not SameAlts(alts, state.members[me].alts) then fields.alts = alts end
  local before = state.members[me].lv
  -- a ding: how long it took, in time played (from the ding before; unknown the first time)
  if fields.lv and before and fields.lv > before then
    local rec = state.members[me]
    local pt = rec.stats and rec.stats.t and rec.stats.t.pt
    -- when it happened, always (the others show the clip only for a ding just now)
    fields.dl = { lv = fields.lv, s = pt and rec.lp and math.max(0, pt - rec.lp) or nil, at = U.Now() }
    if pt then fields.lp = pt end
  end
  P.UpdateSelf(state, me, fields, reason)
  if fields.lv and before and fields.lv > before and fields.lv - before <= 5 and reason ~= "login" then
    for l = before + 1, fields.lv do Milestone(l) end
    Bump("ding", fields.lv - before)
  end
  if fields.lv and ((before and fields.lv > before) or reason == "login") then T.CheckCap(fields.lv) end
  T.CheckXp()
end

-- item level of one item link (live items are always cached)
function T.LinkLevel(link)
  if type(link) ~= "string" then return nil end
  local api = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  if api then
    local ok, lvl = pcall(api, link)
    if ok and U.Plain(lvl, "number") and lvl > 0 then return lvl end
  end
  if GetItemInfo then
    local ok, _, _, _, lvl = pcall(GetItemInfo, link)
    if ok and U.Plain(lvl, "number") and lvl > 0 then return lvl end
  end
  return nil
end

-- what I'm wearing, compact: "2/slot.item.quality.itemlevel[.enchant[.suffix]]/..."
local EQUIP_SLOTS = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
function T.Equipment()
  if not GetInventoryItemLink then return nil end
  local out = { "2" }
  for _, slot in ipairs(EQUIP_SLOTS) do
    local ok, link = pcall(GetInventoryItemLink, "player", slot)
    link = ok and U.Plain(link, "string") or nil
    local fields = link and link:match("item:([%-%d:]+)")
    if fields then
      local f = {}
      for x in (fields .. ":"):gmatch("([%-%d]*):") do f[#f + 1] = tonumber(x) or 0 end
      local q = GetInventoryItemQuality and U.Plain(GetInventoryItemQuality("player", slot), "number") or 1
      local item = { slot, f[1] or 0, q or 1, math.floor(T.LinkLevel(link) or 0) }
      local ench, suffix = f[2] or 0, f[7] or 0
      if ench ~= 0 or suffix ~= 0 then item[5] = ench end
      if suffix ~= 0 then item[6] = suffix end
      if item[2] > 0 then out[#out + 1] = table.concat(item, ".") end
    end
  end
  local s = table.concat(out, "/")
  return #s <= 600 and s or s:sub(1, 600):match("^(.*)/") or ""
end

-- the reverse, for showing someone else's gear: { [slot] = { id, q, il, ench, suffix } }
function T.ParseEquipment(s)
  local gear = {}
  if type(s) ~= "string" then return gear end
  local v2 = s:sub(1, 2) == "2/"
  for item in s:gmatch("[^/]+") do
    local f = {}
    for x in item:gmatch("[^%.]+") do f[#f + 1] = tonumber(x) end
    if f[1] and f[2] then
      if v2 then
        gear[f[1]] = { id = f[2], q = f[3] or 1, il = f[4] or 0, ench = f[5] or 0, suffix = f[6] or 0 }
      else
        gear[f[1]] = { id = f[2], q = f[3] or 1, il = 0, ench = f[4] or 0, suffix = f[5] or 0 }
      end
    end
  end
  return gear
end

-- average item level of what I'm wearing, one decimal; nil if the client can't tell
function T.ItemLevel()
  if not GetAverageItemLevel then return nil end
  local ok, avg, equipped = pcall(GetAverageItemLevel)
  if not ok then return nil end
  local v = U.Plain(equipped, "number") or U.Plain(avg, "number")
  if not v or v <= 0 then return nil end
  return math.floor(v * 10 + 0.5) / 10
end

----------------------------------------------------------------------
-- gold: what comes in from the world (loot, quests, what you sell to vendors) and, unless the capo turned it off,
-- auction sales. Money from other players (mail that isn't an auction sale, trades) is kept apart: a gift isn't
-- money made. At a merchant every sale counts; buying something back takes its price off again (sold and bought
-- back makes nothing), while buying new things and repairs are spending, like a trainer or a flight, and take
-- nothing off. Each window (mail, trade, merchant) counts as open until 2 s after it closes, for the money that
-- lands late; one whose closing never arrived is taken as closed once the game says it isn't open.
----------------------------------------------------------------------
local lastMoney
local win = {}        -- mail, trade, merchant: { at = opened, closed = closed at }
local pendingAH = 0   -- auction sale money taken from the mailbox, still to land
local sold = {}       -- this session's sales to a vendor, newest last (the buyback tab keeps 12)
local debt = 0        -- bought back after it was counted: comes off the next gold made

local function AuctionCounts()
  return not (state and state.settings and state.settings.noAh)
end
T.AuctionCounts = AuctionCounts

-- is the game still showing it? true, false, or nil when it can't tell
local KIND = { mail = "MailInfo", trade = "TradePartner", merchant = "Merchant" }
local FRAME = { mail = "MailFrame", trade = "TradeFrame", merchant = "MerchantFrame" }
local function StillOpen(source)
  local pim, kinds = C_PlayerInteractionManager, Enum and Enum.PlayerInteractionType
  if pim and pim.IsInteractingWithNpcOfType and kinds and kinds[KIND[source]] then
    local ok, v = pcall(pim.IsInteractingWithNpcOfType, kinds[KIND[source]])
    if ok and v == true then return true end
  end
  local f = _G[FRAME[source]]
  if type(f) == "table" and type(f.IsShown) == "function" then
    local ok, v = pcall(f.IsShown, f)
    if ok then return v and true or false end
  end
  return nil
end
T.StillOpen = StillOpen

local function IsOpen(source)
  local w = win[source]
  if not w then return false end
  local now = GetTime()
  if w.closed then
    if now - w.closed <= 2 then return true end
    win[source] = nil
    return false
  end
  if now - w.at > 5 and StillOpen(source) == false then win[source] = nil return false end
  return true
end
T.IsOpen = IsOpen

function T.SetWindow(source, open)
  if open then
    win[source] = { at = GetTime() }
    if source == "mail" then pendingAH = 0 end
  elseif win[source] and not win[source].closed then
    win[source].closed = GetTime()
  end
end
-- (the old name, for the events in Main.lua)
function T.SetMoneyBlock(source, on) T.SetWindow(source, on) end
function T.OnMerchant(open) T.SetWindow("merchant", open) end
T.InMerchant = function() return IsOpen("merchant") end

-- where the gold came from, kept on this account for the tooltip: w the world (loot, quests), v vendors,
-- a auctions, x what doesn't count (gifts, trades, auctions when the capo switched them off)
local function Sources()
  if not (ns.db and me) then return nil end
  ns.db.gsrc = ns.db.gsrc or {}
  local s = ns.db.gsrc[me]
  if not s then s = { since = U.Now() } ns.db.gsrc[me] = s end
  return s
end
function T.Sources() return ns.db and ns.db.gsrc and ns.db.gsrc[me] end
local function Note(key, n)
  local s = Sources()
  if s then s[key] = math.max(0, (s[key] or 0) + n) end
end

local function Made(n, key)
  Note(key, n)
  if debt > 0 then local k = math.min(debt, n) debt, n = debt - k, n - k end
  if n > 0 then Bump("g", n) end
end

local soldPat
-- is mail number `index` the money from an auction I sold?
local function IsAuctionSale(index)
  if GetInboxInvoiceInfo then
    local ok, kind = pcall(GetInboxInvoiceInfo, index)
    if ok and kind == "seller" then return true end
    if ok and type(kind) == "string" then return false end
  end
  if GetInboxHeaderInfo and AUCTION_SOLD_MAIL_SUBJECT then
    local ok, _, _, _, subject = pcall(GetInboxHeaderInfo, index)
    soldPat = soldPat or T.PatternFrom(AUCTION_SOLD_MAIL_SUBJECT)
    if ok and type(subject) == "string" and soldPat and string.match(subject, soldPat.pattern) then return true end
  end
  return false
end

local function MailMoney(index)
  if not GetInboxHeaderInfo then return 0 end
  local ok, _, _, _, _, money = pcall(GetInboxHeaderInfo, index)
  return ok and U.Plain(money, "number") or 0
end

-- called right after the game takes the money of a mail (by hand or with "open all")
function T.OnTakeMail(index)
  if type(index) ~= "number" then return end
  local m = MailMoney(index)
  if m > 0 and IsAuctionSale(index) then pendingAH = pendingAH + m end
end

if type(hooksecurefunc) == "function" then
  for _, fn in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
    if type(_G[fn]) == "function" then hooksecurefunc(fn, function(index) T.OnTakeMail(index) end) end
  end
end

function T.OnMoney()
  local m = U.Plain(GetMoney and GetMoney(), "number")
  if not m then return end
  local before = lastMoney
  lastMoney = m
  if not (before and m ~= before and Ready()) then return end
  local d = m - before
  if d < 0 then
    -- bought back at the merchant: the sale it undoes comes off
    if not IsOpen("merchant") then return end
    for i = #sold, 1, -1 do
      if sold[i] == -d then
        table.remove(sold, i)
        debt = debt - d
        Note("v", d)
        return
      end
    end
    return
  end
  if IsOpen("trade") then Note("x", d) return end
  if IsOpen("mail") then
    -- only the part that came from auction sales
    local credit = math.min(d, pendingAH)
    pendingAH = pendingAH - credit
    if credit > 0 then
      Bump("ga", credit)
      if AuctionCounts() then Made(credit, "a") else Note("x", credit) end
    end
    if d > credit then Note("x", d - credit) end
    return
  end
  if IsOpen("merchant") then
    table.insert(sold, d)
    while #sold > 12 do table.remove(sold, 1) end
    Made(d, "v")
    return
  end
  Made(d, "w")
end

function T.CheckCap(level)
  local cap = T.MyCap()
  if not cap or not level then return end
  if level > cap then
    Alert("Sei sopra er cap! Livello " .. level .. ", cap de 'sta settimana " .. cap .. ".", "over:" .. Week() .. ":" .. level)
  end
end

function T.CheckXp()
  local cap = T.MyCap()
  local rec = Ready() and state.members[me]
  if not cap or not rec or not rec.lv or not rec.xp or not rec.xpm or rec.xpm <= 0 then return end
  if rec.lv ~= cap then return end
  local pct = rec.xp / rec.xpm
  if pct >= 0.95 then
    Alert("Occhio: stai ar " .. math.floor(pct * 100) .. "% der livello " .. cap .. ". 'N altro po' e fai ding oltre er cap!", "xp95:" .. Week() .. ":" .. cap)
  elseif pct >= 0.85 then
    Alert("Barra ar " .. math.floor(pct * 100) .. "%: stai vicino ar ding oltre er cap " .. cap .. ".", "xp85:" .. Week() .. ":" .. cap)
  end
end

----------------------------------------------------------------------
-- quests
----------------------------------------------------------------------
local pendingTitle

function T.OnQuestComplete()
  pendingTitle = GetTitleText and U.Plain(GetTitleText(), "string") or nil
  local cap = T.MyCap()
  if not cap then return end
  local lv = U.Plain(UnitLevel("player"), "number")
  local xp, xpm = U.Plain(UnitXP("player"), "number"), U.Plain(UnitXPMax("player"), "number")
  local reward = GetRewardXP and U.Plain(GetRewardXP(), "number")
  if not (lv and xp and xpm and reward) then return end
  local text
  if lv > cap then
    text = "Stai già sopra er cap (" .. cap .. "). Questa quest te dà altri " .. U.Thousands(reward) .. " XP."
  elseif lv == cap and xp + reward >= xpm then
    text = "Se consegni 'sta quest fai ding ar " .. (lv + 1) .. ", sopra er cap " .. cap .. "! Tienila pe' la settimana dopo."
  end
  if text then
    Alert(text, nil, true)
    ns.Fire("QuestWarning", text)
  else
    ns.Fire("QuestWarning", nil)
  end
end

-- a { [key] = count } table that keeps only the `max` biggest entries
local function Count(t, key, max)
  t[key] = (t[key] or 0) + 1
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  while n > max do
    local low, lowKey
    for k, v in pairs(t) do if k ~= key and (not low or v < low) then low, lowKey = v, k end end
    if not lowKey then break end
    t[lowKey] = nil
    n = n - 1
  end
end

-- this week's zone and dungeon lists start empty every week
local function WeekLists(rec)
  local wk = Week()
  if rec.wk ~= wk then rec.wk, rec.zqw, rec.dgw = wk, {}, {} end
  rec.zqw, rec.dgw = rec.zqw or {}, rec.dgw or {}
end

-- the quest diary: the full list stays on this account, friends get the last 5 and the zones
function T.OnQuestTurnedIn(questID, xpReward, moneyReward)
  if not Ready() then return end
  local title
  if type(questID) == "number" and C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, questID)
    if ok then title = U.Plain(t, "string") end
  end
  title = title or pendingTitle or "Quest"
  pendingTitle = nil
  local zone = GetRealZoneText and U.Plain(GetRealZoneText(), "string") or nil
  if zone == "" then zone = nil end
  local lv = U.Plain(UnitLevel("player"), "number")
  local entry = { t = title:sub(1, 32), z = zone and zone:sub(1, 40), at = U.Now() }
  ns.db.qlog = ns.db.qlog or {}
  local log = ns.db.qlog[me] or {}
  ns.db.qlog[me] = log
  table.insert(log, 1, { t = entry.t, z = entry.z, at = entry.at, lv = lv, id = type(questID) == "number" and questID or nil,
    xp = U.Plain(xpReward, "number"), money = U.Plain(moneyReward, "number") })
  ns.Fire("J_Quest", log[1])
  while #log > 300 do table.remove(log) end
  local rec = state.members[me]
  rec.lq = rec.lq or {}
  table.insert(rec.lq, 1, entry)
  while #rec.lq > 3 do table.remove(rec.lq) end
  rec.zq = rec.zq or {}
  WeekLists(rec)
  if zone then
    Count(rec.zq, zone:sub(1, 40), 6)
    Count(rec.zqw, zone:sub(1, 40), 6)
  end
  Bump("q")
end

function T.QuestLog()
  return ns.db and ns.db.qlog and ns.db.qlog[me] or {}
end

-- rare mobs: remember the rares you fight; when one of them dies while you had the tag, it counts once
local rares, rareDone = {}, {}

local function Plain(f, ...)
  local ok, v = pcall(f, ...)
  if not ok or U.IsSecret(v) then return nil end
  return v
end

function T.CheckRare(unit)
  if not Ready() or not UnitExists or not Plain(UnitExists, unit) then return end
  local guid = Plain(UnitGUID, unit)
  if not guid or rareDone[guid] then return end
  local class = Plain(UnitClassification, unit)
  if class ~= "rare" and class ~= "rareelite" and not rares[guid] then return end
  if Plain(UnitIsDead, unit) then
    local r = rares[guid]
    if r and not Plain(UnitIsTapDenied, unit) then
      rareDone[guid] = true
      rares[guid] = nil
      local rec = state.members[me]
      rec.rl = rec.rl or {}
      table.insert(rec.rl, 1, { n = r.name:sub(1, 32), z = (GetRealZoneText and U.Plain(GetRealZoneText(), "string") or ""):sub(1, 40), at = U.Now() })
      while #rec.rl > 5 do table.remove(rec.rl) end
      Bump("rk")
      U.Say("raro ammazzato: |cffffffff" .. r.name .. "|r.")
    end
  elseif not Plain(UnitIsTapDenied, unit) then
    rares[guid] = { name = Plain(UnitName, unit) or "Raro", at = GetTime() }
  end
end

-- world PvP: honorable kills and honor, read from the game's own counters; only the increases count
local function ReadPvP()
  local hk, honor
  if GetPVPLifetimeStats then
    local ok, a = pcall(GetPVPLifetimeStats)
    if ok then hk = U.Plain(a, "number") end
  end
  if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, 1792) -- honor
    if ok and type(info) == "table" then honor = U.Plain(info.quantity, "number") end
  end
  if not honor and GetPVPThisWeekStats then
    local ok, _, h = pcall(GetPVPThisWeekStats)
    if ok then honor = U.Plain(h, "number") end
  end
  return hk, honor
end

function T.CheckPvP()
  if not (Ready() and ns.db) then return end
  local hk, honor = ReadPvP()
  ns.db.pvp = ns.db.pvp or {}
  local last = ns.db.pvp[myGuid] or {}
  ns.db.pvp[myGuid] = last
  -- where the kills were made: in a battleground or out in the world. Read when the game says a kill was made
  -- (and every minute); if the place changed since the last look, the kills were made where I was before
  local bg = U.InBattleground()
  if hk then
    if last.hk and hk > last.hk then
      local n = hk - last.hk
      local wasBG = last.bg
      if wasBG == nil then wasBG = bg end
      Bump("hk", n)
      Bump(wasBG and "hb" or "hw", n)
    end
    last.hk = hk
  end
  last.bg = bg
  if honor then
    if last.hn and honor > last.hn then Bump("hn", honor - last.hn) end
    last.hn = honor -- spending honor lowers it: only gains count
  end
end

-- catch-up for whoever installs the addon late: the game itself remembers some totals.
-- Quests completed, lifetime honorable kills and /played go in once, as "da sempre" numbers (never lowering them).
local pendingPlayed = false

local function CompletedQuests()
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, ids = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(ids) == "table" then return #ids end
  end
  if GetQuestsCompleted then
    local ok, ids = pcall(GetQuestsCompleted)
    if ok and type(ids) == "table" then
      local n = 0
      for _ in pairs(ids) do n = n + 1 end
      return n
    end
  end
  return nil
end

function T.Backfill()
  if not (Ready() and ns.db) then return end
  ns.db.bf = ns.db.bf or {}
  local key = tostring(state.code) .. ":" .. tostring(myGuid)
  if ns.db.bf[key] then return end
  ns.db.bf[key] = true
  local rec = state.members[me]
  rec.stats = rec.stats or { t = {}, w = {} }
  rec.stats.t = rec.stats.t or {}
  local t = rec.stats.t
  local found = {}
  -- the game also marks hidden bookkeeping "quests" as done: only trust a number that a real character could have
  local q = CompletedQuests()
  local lv = U.Plain(UnitLevel("player"), "number") or 1
  if q and lv <= 60 and q <= lv * 25 + 20 and q > (t.q or 0) then t.q = q found[#found + 1] = q .. " quest" end
  local hk = ReadPvP()
  if hk and hk > (t.hk or 0) then t.hk = hk found[#found + 1] = hk .. " uccisioni" end
  if #found > 0 then
    rec.up = U.Now()
    ns.Fire("SelfChanged", state, "backfill")
    U.Say("ho recuperato dar gioco quello che hai fatto prima dell'addon: " .. table.concat(found, ", ") .. ".")
  end
  if RequestTimePlayed then
    pendingPlayed = true
    pcall(RequestTimePlayed)
  end
end

-- TIME_PLAYED_MSG: total seconds on this character; counted up to the time since the patto started
function T.OnTimePlayed(total)
  if not pendingPlayed or not Ready() then return end
  pendingPlayed = false
  total = U.Plain(total, "number")
  if not total then return end
  local s = state.settings
  local since = (s and s.start and U.Now() > s.start) and (U.Now() - s.start) or 0
  total = math.min(total, since)
  local t = state.members[me].stats.t
  if total > (t.pt or 0) then
    t.pt = math.floor(total)
    state.members[me].up = U.Now()
    ns.Fire("SelfChanged", state, "backfill")
  end
end

-- deaths
function T.OnDeath()
  if U.InBattleground() then return end
  if not U.FirstDeath("Tracker") then return end
  if not Ready() then return end
  -- when and where: two members dying close together is a wipe
  local rec = state.members[me]
  rec.dat = U.Now()
  local z = GetRealZoneText and U.Plain(GetRealZoneText(), "string")
  rec.dz = (z and z ~= "") and z or nil
  Bump("dt")
  T.WatchWipe()
end

-- a wipe: everyone of my group who's there dead at the same time (two out of five isn't one). Seen from inside the
-- group, where the game says who is dead: after my death, a look every second for half a minute (the others may
-- die after me). Who's there: connected and in sight (the game draws them, ~100 yards), or dead. A hunter faking
-- his death counts as dead. Written in my record (wp): everyone hears it from there, once even when five say it.
-- Cost: at most 30 looks at the group after a death of mine, nothing else.
T.WIPE_WATCH = 30
local function DeadUnit(u)
  local ok, dead = pcall(UnitIsDeadOrGhost, u)
  if ok and U.Plain(dead, "boolean") then return true end
  if UnitIsFeignDeath then
    local okf, fd = pcall(UnitIsFeignDeath, u)
    if okf and U.Plain(fd, "boolean") then return true end
  end
  return false
end
function T.GroupDead()
  if not (IsInGroup and UnitIsDeadOrGhost and UnitName) then return nil end
  local ok, grouped = pcall(IsInGroup)
  if not ok or U.IsSecret(grouped) or not grouped then return nil end
  local raid = IsInRaid and IsInRaid()
  local units = raid and {} or { "player" }
  for i = 1, raid and 40 or 4 do units[#units + 1] = (raid and "raid" or "party") .. i end
  local names, there = {}, 0
  for _, u in ipairs(units) do
    local okE, exists = pcall(UnitExists or function() return true end, u)
    local n = U.Plain(UnitName(u), "string")
    if okE and U.Plain(exists, "boolean") ~= false and n and n ~= "" and n ~= UNKNOWNOBJECT then
      local okC, on = pcall(UnitIsConnected or function() return true end, u)
      if not (okC and U.Plain(on, "boolean") == false) then
        local dead = DeadUnit(u)
        local seen = true
        if not dead and UnitIsVisible then
          local okV, vis = pcall(UnitIsVisible, u)
          seen = okV and U.Plain(vis, "boolean") == true
        end
        if dead or seen then
          there = there + 1
          if not dead then return false end
          names[#names + 1] = U.Short(n)
        end
      end
    end
  end
  if there < 2 then return false end
  return true, names
end
local wipeWatch
function T.WatchWipe()
  if not C_Timer then return end
  local id = {}
  wipeWatch = id
  local tries = 0
  local function look()
    if wipeWatch ~= id or not Ready() then return end
    tries = tries + 1
    local all, names = T.GroupDead()
    if all then
      wipeWatch = nil
      local z = GetRealZoneText and U.Plain(GetRealZoneText(), "string")
      table.sort(names)
      P.UpdateSelf(state, me, { wp = { at = U.Now(), z = (z and z ~= "") and z or nil, n = table.concat(names, ", "):sub(1, 160), c = #names } }, "wipe")
      return
    end
    if all == nil or tries >= T.WIPE_WATCH then wipeWatch = nil return end
    C_Timer.After(1, look)
  end
  look()
end

-- in a party or raid with someone of the patto: how many of them, and how many right next to me (in range, ~40
-- yards: playing together, not just sharing a group). Names whole: on Forever everyone is "Er Something"
local function Near(unit)
  if UnitIsConnected then
    local on = U.Plain(UnitIsConnected(unit), "boolean")
    if on == false then return false end
  end
  if UnitInRange then
    -- (in range, checked): not checked = the game doesn't know, try the other way
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if ok then
      inRange, checked = U.Plain(inRange, "boolean"), U.Plain(checked, "boolean")
      if inRange ~= nil and checked ~= false then return inRange end
    end
  end
  if CheckInteractDistance then
    local ok, close = pcall(CheckInteractDistance, unit, 4)
    if ok and U.Plain(close, "boolean") then return true end
  end
  return false
end
local function GroupedWithPatto()
  if not (IsInGroup and UnitName) then return false, 0, 0 end
  local ok, grouped = pcall(IsInGroup)
  if not ok or U.IsSecret(grouped) or not grouped then return false, 0, 0 end
  local names = {}
  for g, r in pairs(state.members) do
    if g ~= me and type(r.name) == "string" then names[U.Short(r.name):lower()] = true end
  end
  local raid = IsInRaid and IsInRaid()
  local with, near = 0, 0
  for i = 1, raid and 40 or 4 do
    local unit = (raid and "raid" or "party") .. i
    local n = U.FullName(unit)
    if n and names[U.Short(n):lower()] then
      with = with + 1
      if Near(unit) then near = near + 1 end
    end
  end
  return with > 0, with, near
end
-- piotte an hour in a group: 1 with someone of the patto in it, +1 for each of them right next to me, at most 5
T.GROUP_RATE_MAX = 5
function T.GroupRate()
  local yes, _, near = GroupedWithPatto()
  if not yes then return 0, 0 end
  return math.min(T.GROUP_RATE_MAX, 1 + near), near
end
T.GroupedWithPatto = GroupedWithPatto

-- time played while the patto runs: one minute at a time, not while away
local playTicker
local function PlayedMinute()
  if not Ready() then return end
  if UnitIsAFK then
    local afk = UnitIsAFK("player")
    if not U.IsSecret(afk) and afk then return end
  end
  T.CheckPvP()
  if P.HasSettings(state) and M.WeekIndex(state.settings, U.Now()) < 1 then return end
  Bump("pt", 60)
  -- "gp": a piotta every 3600 of it; a minute in a group counts 60 for each piotta an hour it's worth now
  local rate, near = T.GroupRate()
  if rate > 0 then
    local before = state.members[me].stats.t.gp or 0
    Bump("gp", 60 * rate)
    local after = state.members[me].stats.t.gp or 0
    if math.floor(after / 3600) > math.floor(before / 3600) and ns.News then
      ns.News.Add("+1 piotta pe' fa' gruppo co' er patto" .. (near > 0 and (" (" .. rate .. " l'ora: " .. near .. (near == 1 and " amico vicino" or " amici vicini") .. ")") or "") .. ".")
    end
  end
end

-- level milestones (10, 20 ... 60) with the date they were reached
function Milestone(level)
  local rec = state.members[me]
  rec.ms = rec.ms or {}
  if level % 10 == 0 and level >= 10 and level <= 60 and not rec.ms[level] then
    rec.ms[level] = U.Now()
    -- the race: time played (since the patto started) when the milestone came
    rec.mp = rec.mp or {}
    rec.mp[level] = rec.stats and rec.stats.t and rec.stats.t.pt or nil
  end
end

-- professions: modern API if present, otherwise the classic skill list (professions are the ones you can unlearn)
-- profession names as the English client writes them, whatever the client's language, so titles and boards
-- match between friends with different clients: the spell of each profession gives its local name
local EN_BY_SPELL = { [2259] = "Alchemy", [2018] = "Blacksmithing", [7411] = "Enchanting", [4036] = "Engineering",
  [2575] = "Mining", [8613] = "Skinning", [2108] = "Leatherworking", [3908] = "Tailoring", [2550] = "Cooking",
  [7620] = "Fishing", [3273] = "First Aid" }
local EN_STATIC = { ["Erbalismo"] = "Herbalism", ["Kräuterkunde"] = "Herbalism", ["Herboristería"] = "Herbalism",
  ["Herboristerie"] = "Herbalism", ["Alchimia"] = "Alchemy", ["Forgiatura"] = "Blacksmithing", ["Incantamento"] = "Enchanting",
  ["Ingegneria"] = "Engineering", ["Estrazione"] = "Mining", ["Scuoiatura"] = "Skinning", ["Conciatura"] = "Leatherworking",
  ["Sartoria"] = "Tailoring", ["Cucina"] = "Cooking", ["Pesca"] = "Fishing", ["Primo Soccorso"] = "First Aid", ["Primo soccorso"] = "First Aid" }
local enBySpellName
local function English(name)
  if EN_STATIC[name] then return EN_STATIC[name] end
  if not enBySpellName then
    enBySpellName = {}
    for id, en in pairs(EN_BY_SPELL) do
      local ok, n = pcall(function() return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)) or (GetSpellInfo and GetSpellInfo(id)) end)
      n = ok and U.Plain(n, "string")
      if n then enBySpellName[n] = en end
    end
  end
  return enBySpellName[name] or name
end
T.EnglishProfession = English

function T.Professions()
  local out = {}
  if GetProfessions and GetProfessionInfo then
    local list = { GetProfessions() }
    for i = 1, 6 do
      local idx = list[i]
      if type(idx) == "number" then
        local ok, name, _, lvl, max = pcall(GetProfessionInfo, idx)
        if ok and U.Plain(name, "string") then out[#out + 1] = { n = English(name):sub(1, 30), l = U.Plain(lvl, "number") or 0, m = U.Plain(max, "number") or 0 } end
      end
    end
  elseif GetNumSkillLines and GetSkillLineInfo then
    local secondary = {}
    for _, id in ipairs({ 2550, 7620, 3273 }) do -- cooking, fishing, first aid
      local n = GetSpellInfo and GetSpellInfo(id)
      if type(n) == "string" then secondary[n] = true end
    end
    for i = 1, GetNumSkillLines() do
      local ok, name, header, _, rank, _, _, max, abandon = pcall(GetSkillLineInfo, i)
      if ok and name and not header and (abandon or secondary[name]) and #out < 6 then
        out[#out + 1] = { n = English(tostring(name)):sub(1, 30), l = rank or 0, m = max or 0 }
      end
    end
  end
  return out
end

function T.RefreshProfessions()
  if not Ready() then return end
  local pr = T.Professions()
  local rec = state.members[me]
  local same = rec.pr and #rec.pr == #pr
  if same then
    for i = 1, #pr do
      if rec.pr[i].n ~= pr[i].n or rec.pr[i].l ~= pr[i].l or rec.pr[i].m ~= pr[i].m then same = false end
    end
  end
  if not same then P.UpdateSelf(state, me, { pr = pr }, "prof") end
end

----------------------------------------------------------------------
-- duels: parsed from the client's own format strings, so any client language works
----------------------------------------------------------------------
local function PatternFrom(fmt)
  if type(fmt) ~= "string" then return nil end
  local order, n = {}, 0
  for d in string.gmatch(fmt, "%%(%d)%$s") do order[#order + 1] = tonumber(d) end
  if #order == 0 then for _ in string.gmatch(fmt, "%%s") do n = n + 1 order[#order + 1] = n end end
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%s", "(.+)")
  return { pattern = "^" .. p .. "$", order = order }
end
T.PatternFrom = PatternFrom

local function MatchArgs(msg, pat)
  if not pat then return nil end
  local caps = { string.match(msg, pat.pattern) }
  if #caps == 0 then return nil end
  local args = {}
  for i, pos in ipairs(pat.order) do args[pos] = caps[i] end
  return args
end

local duelKO, duelFled

local function IsMe(name)
  return name == myName or name == myShort or (state and state.members[me] and name == state.members[me].name)
end

-- duel messages may carry "Name" or "Name Surname": use the patto member's name when it matches
local function Canon(name)
  for _, r in pairs(state.members) do
    if r.name == name then return name end
  end
  for _, r in pairs(state.members) do
    if type(r.name) == "string" and r.name:match("^(%S+)") == name then return r.name end
  end
  return name
end
T.Canon = function(name) return state and Canon(name) or name end

local function Duel(winner, loser)
  if not Ready() then return end
  winner, loser = Canon(winner), Canon(loser)
  -- every duel the game tells me about (mine, or one I'm watching): the bets on it are paid at once
  ns.Fire("SeenDuel", winner, loser)
  local rec = state.members[me]
  rec.h2h = rec.h2h or {}
  local function h(name)
    local n = 0
    for _ in pairs(rec.h2h) do n = n + 1 end
    if not rec.h2h[name] and n >= 30 then return nil end
    rec.h2h[name] = rec.h2h[name] or { w = 0, l = 0 }
    return rec.h2h[name]
  end
  -- the duel log for le sfide: only duels with patto members, by guid
  local function Log(name, won)
    for guid, r in pairs(state.members) do
      if guid ~= me and type(r.name) == "string" and (r.name == name or U.Short(r.name) == U.Short(name)) then
        local dd = {}
        table.insert(dd, { o = guid, w = won and 1 or 0, at = U.Now() })
        for i = 1, 7 do if rec.dd and rec.dd[i] then dd[#dd + 1] = rec.dd[i] end end
        rec.dd = dd
        return
      end
    end
  end
  if IsMe(winner) then Log(loser, true) elseif IsMe(loser) then Log(winner, false) end
  if IsMe(winner) then
    local e = h(loser)
    if e then e.w = e.w + 1 end
    Bump("dw")
    ns.Fire("J_Duel", loser, true)
  elseif IsMe(loser) then
    local e = h(winner)
    if e then e.l = e.l + 1 end
    Bump("dl")
    ns.Fire("J_Duel", winner, false)
  end
end

function T.OnSystemMessage(msg)
  if type(msg) ~= "string" or U.IsSecret(msg) then return end
  duelKO = duelKO or PatternFrom(DUEL_WINNER_KNOCKOUT)
  duelFled = duelFled or PatternFrom(DUEL_WINNER_RETREAT)
  local a = MatchArgs(msg, duelKO) or MatchArgs(msg, duelFled)
  if a and a[1] and a[2] then Duel(a[1], a[2]) end
end

----------------------------------------------------------------------
-- dungeons: a run counts when you leave after a boss kill or after 5 minutes inside
----------------------------------------------------------------------
function T.OnEnteringWorld()
  if not Ready() or not GetInstanceInfo then return end
  local name, kind = GetInstanceInfo()
  if U.IsSecret(kind) then return end
  local run = ns.db.run
  if kind == "party" then
    if not run then
      ns.db.run = { name = U.Plain(name, "string") or "Dungeon", at = U.Now(), bosses = 0 }
    end
  elseif run then
    ns.Fire("J_Dungeon", run, run.bosses > 0 or U.Now() - run.at >= 300)
    if run.bosses > 0 or U.Now() - run.at >= 300 then
      state.members[me].ld = run.name
      state.members[me].dgl = state.members[me].dgl or {}
      Count(state.members[me].dgl, tostring(run.name):sub(1, 40), 8)
      WeekLists(state.members[me])
      Count(state.members[me].dgw, tostring(run.name):sub(1, 40), 8)
      Bump("dg")
    end
    ns.db.run = nil
  end
  if kind ~= "pvp" then bg = nil end
end

function T.OnBossKill(success)
  -- a secret result can't be compared: count it, the 5-minute rule covers the rest anyway
  if ns.db and ns.db.run and (U.IsSecret(success) or success == nil or success == 1 or success == true) then
    ns.db.run.bosses = ns.db.run.bosses + 1
    ns.Fire("J_Boss")
  end
end

----------------------------------------------------------------------
-- battlegrounds
----------------------------------------------------------------------
local function BGResult(winner)
  if not Ready() or bg == nil or bg.done then return end
  if U.IsSecret(winner) or (winner ~= 0 and winner ~= 1) then return end -- 255 or nil: draw or unknown
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  if U.IsSecret(faction) then return end
  local mine = (faction == "Alliance") and 1 or 0
  bg.done = true
  Bump(winner == mine and "bw" or "bl")
  ns.Fire("J_BG", winner == mine, U.Now() - (bg.at or U.Now()))
end

function T.OnBattlefieldStatus(index)
  if not GetBattlefieldStatus then return end
  local status = GetBattlefieldStatus(index)
  if status == "active" and not bg then bg = { at = U.Now(), done = false } end
end

function T.OnMatchComplete(winner)
  local w = winner
  if (w == nil or U.IsSecret(w)) and C_PvP and C_PvP.GetActiveMatchWinner then w = C_PvP.GetActiveMatchWinner() end
  if (w == nil or U.IsSecret(w)) and GetBattlefieldWinner then w = GetBattlefieldWinner() end
  BGResult(w)
end

function T.OnBattlefieldScore()
  if bg and not bg.done and GetBattlefieldWinner then BGResult(GetBattlefieldWinner()) end
end

----------------------------------------------------------------------
-- recordGuid: the patto record this session writes (the main's, in alt mode); guid/playerName: the logged-in character
function T.Start(st, recordGuid, guid, playerName, isAlt)
  state, me, myGuid, myName, altMode = st, recordGuid, guid, playerName, isAlt and true or false
  myShort = playerName and U.Short(playerName) or playerName
  bg = nil
  lastMoney = U.Plain(GetMoney and GetMoney(), "number")
  win, pendingAH, sold, debt = {}, 0, {}, 0
  T.RefreshSelf("login")
  T.RefreshProfessions()
  T.CheckPvP()
  if C_Timer then C_Timer.After(8, T.Backfill) else T.Backfill() end
  if not playTicker and C_Timer then playTicker = C_Timer.NewTicker(60, PlayedMinute) end
end

function T.Stop()
  state = nil
end

function T.ResetWarnings()
  warned = {}
end
