-- Er Patto: diagnosi (from Phase 0). Checks what the client allows (comms, events, textures) and keeps a copyable log.
-- Uses its own prefix so its pings never mix with the patto's messages.
-- Every value that may be a Midnight-style "secret value" goes through S() before it is printed or compared.

local ADDON, ns = ...
local U = ns.U
local PREFIX = "ErPattoD"
local VERSION = ns.VERSION
local TEST_CHANNEL = "erpattoprova"
local TEST_PASSWORD = "daje"

local pings = {}
local testChannelId
local secretSystemSeen = false

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

local function S(v)
  if IsSecret(v) then return "<segreto>" end
  if v == nil then return "nil" end
  return tostring(v)
end

local function Now()
  if GetServerTime then return GetServerTime() end
  return time()
end

local function Clock()
  if GetTimePreciseSec then return GetTimePreciseSec() end
  return GetTime()
end

local function Resolve(path)
  local t = _G
  for part in string.gmatch(path, "[^%.]+") do
    if type(t) ~= "table" then return nil end
    t = t[part]
  end
  return t
end

local Log, Say = U.Log, U.Say
local RefreshLog = function() end

local function ResultName(res)
  if res == nil then return "nessun risultato" end
  if IsSecret(res) then return "<segreto>" end
  local enum = Enum and Enum.SendAddonMessageResult
  if type(enum) == "table" then
    for k, v in pairs(enum) do
      if v == res then return tostring(k) .. " (" .. tostring(res) .. ")" end
    end
  end
  return tostring(res)
end

----------------------------------------------------------------------
-- addon messages
----------------------------------------------------------------------
local function Send(chatType, target, text)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
    Log("Invio", "manca C_ChatInfo.SendAddonMessage")
    return
  end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, chatType, target)
  if ok then
    Log("Invio", chatType, target or "-", "->", ResultName(res))
  else
    Log("Invio", chatType, target or "-", "ERRORE", res)
  end
end

local function Ping(chatType, target)
  local id = tostring(math.random(100000, 999999))
  pings[id] = Clock()
  Send(chatType, target, "PING|" .. id .. "|" .. VERSION)
end

local function OnAddonMessage(prefix, msg, channel, sender, target, zoneChannelID, localID, name)
  if IsSecret(prefix) or IsSecret(msg) or IsSecret(sender) then
    Log("Ricevo", "messaggio con valori segreti, canale:", channel)
    return
  end
  if prefix ~= PREFIX then return end
  local kind, id, ver = string.match(msg, "^(%u+)|(%d+)|?(.*)$")
  Log("Ricevo", kind or "?", "da", sender, "via", channel, "ver", ver, "zona canale", zoneChannelID, "id locale", localID, "nome canale", name)
  if kind == "PING" then
    local reply = "PONG|" .. id .. "|" .. VERSION
    if channel == "WHISPER" then
      Send("WHISPER", sender, reply)
    elseif channel == "CHANNEL" then
      Send("CHANNEL", tostring(localID or testChannelId or ""), reply)
    else
      Send(channel, nil, reply)
    end
  elseif kind == "PONG" and pings[id] then
    Log("Ricevo", string.format("risposta in %.2f s da %s", Clock() - pings[id], S(sender)))
  end
end

----------------------------------------------------------------------
-- test channel
----------------------------------------------------------------------
local function RemoveFromChatWindows(chan)
  local remove = ChatFrame_RemoveChannel
  if type(remove) ~= "function" then
    Log("Canale", "ChatFrame_RemoveChannel nun c'è: er canale resta visibile in chat")
    return
  end
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local frame = _G["ChatFrame" .. i]
    if frame then pcall(remove, frame, chan) end
  end
end

local function JoinTestChannel()
  if type(JoinChannelByName) ~= "function" then
    Log("Canale", "manca JoinChannelByName")
    return
  end
  local ok, a, b = pcall(JoinChannelByName, TEST_CHANNEL, TEST_PASSWORD)
  if ok then Log("Canale", "JoinChannelByName ok", a, b) else Log("Canale", "JoinChannelByName ERRORE", a) end
  C_Timer.After(2, function()
    local id, name = GetChannelName(TEST_CHANNEL)
    Log("Canale", "dopo 2 s: id", id, "nome", name)
    if not IsSecret(id) and type(id) == "number" and id > 0 then
      testChannelId = id
      RemoveFromChatWindows(TEST_CHANNEL)
      Say("sei entrato ner canale de prova. Mo' premi \"Ping canale\".")
    else
      Say("nun so' riuscito a entrà ner canale de prova. Guarda er registro.")
    end
  end)
end

----------------------------------------------------------------------
-- environment report
----------------------------------------------------------------------
local API_LIST = {
  "C_ChatInfo.SendAddonMessage", "C_ChatInfo.RegisterAddonMessagePrefix", "JoinChannelByName", "JoinTemporaryChannel",
  "GetChannelName", "ChatFrame_RemoveChannel", "issecretvalue", "GetServerTime", "C_Timer.After",
  "GetRewardXP", "GetQuestReward", "GetQuestLogRewardXP", "C_QuestLog.GetQuestLogRewardXP",
  "GetBattlefieldWinner", "C_PvP.GetActiveMatchWinner", "C_PvP.IsMatchComplete", "GetBattlefieldStatus",
  "IsInGuild", "C_GuildInfo.GuildRoster", "GetGuildRosterInfo", "GetNumGuildMembers",
  "C_FriendList.GetNumOnlineFriends", "C_Map.GetBestMapForUnit", "RequestTimePlayed",
  "GetInstanceInfo", "UnitFullName", "BackdropTemplateMixin", "Settings.RegisterCanvasLayoutCategory",
}

local function EnvReport()
  Log("Ambiente", "---- rapporto ambiente, Er Patto " .. VERSION .. " ----")
  local version, build, bdate, toc = GetBuildInfo()
  Log("Ambiente", "versione", version, "build", build, "data", bdate, "interfaccia", toc)
  Log("Ambiente", "WOW_PROJECT_ID", WOW_PROJECT_ID, "CAMELOT", WOW_PROJECT_CAMELOT)
  if GetServerTime then
    Log("Ambiente", "ora server UTC", date("!%Y-%m-%d %H:%M:%S", GetServerTime()), "ora PC", date("%Y-%m-%d %H:%M:%S"))
  else
    Log("Ambiente", "manca GetServerTime")
  end
  local n, r = UnitName("player")
  Log("Ambiente", "UnitName", n, "reame", r)
  if UnitFullName then
    local a, b = UnitFullName("player")
    Log("Ambiente", "UnitFullName", a, "reame", b)
  end
  if GetUnitName then Log("Ambiente", "GetUnitName(true)", GetUnitName("player", true)) end
  Log("Ambiente", "GUID", UnitGUID("player"))
  Log("Ambiente", "livello", UnitLevel("player"), "XP", UnitXP("player"), "su", UnitXPMax("player"), "riposata", GetXPExhaustion and GetXPExhaustion())
  Log("Ambiente", "in gilda", IsInGuild and IsInGuild(), "in gruppo", IsInGroup and IsInGroup(), "in raid", IsInRaid and IsInRaid())
  if ns.C then
    local st = ns.C.stats
    Log("Patto", "codice", ns.state and ns.state.code, "alt", ns.alt, "canale", ns.C.ChannelName(), "modo", st.mode,
      "inviati", st.sent, "ricevuti", st.received, "scartati", st.dropped, "trattenuti", st.held, "in coda", ns.C.QueueSize(),
      "frenati", st.throttled or 0, "cambi", st.deltas or 0, "cambi vecchi", st.stale or 0,
      "blocco messaggi", ns.C.InLockdown())
    if ns.state then
      local n, online = 0, 0
      for g in pairs(ns.state.members) do
        n = n + 1
        if ns.C.IsOnline(g) then online = online + 1 end
      end
      Log("Patto", "membri", n, "online", online, "impostazioni v", ns.state.settings.v, "capi v", ns.state.admins.v)
      local inChan, names = 0, {}
      for _, who in pairs(ns.C.Roster and ns.C.Roster() or {}) do inChan = inChan + 1 names[#names + 1] = who end
      Log("Patto", "ner canale", inChan, table.concat(names, ", "))
    end
  end
  local missing = {}
  for _, path in ipairs(API_LIST) do
    if Resolve(path) == nil then missing[#missing + 1] = path end
  end
  Log("Ambiente", "API mancanti:", #missing == 0 and "nessuna" or table.concat(missing, ", "))
  if IsInGuild and IsInGuild() and GetNumGuildMembers and GetGuildRosterInfo then
    if C_GuildInfo and C_GuildInfo.GuildRoster then pcall(C_GuildInfo.GuildRoster) end
    local total = GetNumGuildMembers()
    Log("Gilda", "membri", total)
    for i = 1, math.min(3, total or 0) do
      local gname, _, _, glevel, _, _, publicNote = GetGuildRosterInfo(i)
      Log("Gilda", "membro", i, gname, "livello", glevel, "nota", publicNote)
    end
  end
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------
-- Turns a client format string ("%2$s has fled from %1$s in a duel") into a Lua pattern,
-- remembering which argument each capture is, so it works in any client language.
local function PatternFrom(fmt)
  if type(fmt) ~= "string" then return nil end
  local order, n = {}, 0
  for d in string.gmatch(fmt, "%%(%d)%$s") do order[#order + 1] = tonumber(d) end
  if #order == 0 then
    for _ in string.gmatch(fmt, "%%s") do n = n + 1; order[#order + 1] = n end
  end
  local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%s", "(.+)")
  return { pattern = "^" .. p .. "$", order = order }
end

local function MatchArgs(msg, pat)
  if not pat then return nil end
  local caps = { string.match(msg, pat.pattern) }
  if #caps == 0 then return nil end
  local args = {}
  for i, pos in ipairs(pat.order) do args[pos] = caps[i] end
  return args
end

local DUEL_KO = PatternFrom(DUEL_WINNER_KNOCKOUT)
local DUEL_FLED = PatternFrom(DUEL_WINNER_RETREAT)

local EVENTS = {
  "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "QUEST_COMPLETE", "QUEST_TURNED_IN",
  "DUEL_REQUESTED", "DUEL_FINISHED", "CHAT_MSG_SYSTEM",
  "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL",
  "PLAYER_ENTERING_WORLD", "UPDATE_BATTLEFIELD_STATUS", "PVP_MATCH_COMPLETE", "UPDATE_BATTLEFIELD_SCORE",
  "CHAT_MSG_ADDON", "CHAT_MSG_CHANNEL_NOTICE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN",
}

local handlers = {}

function handlers.PLAYER_LOGIN()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    local ok, res = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    Log("Avvio", "registro prefisso diagnosi", PREFIX, ok and "ok" or "ERRORE", res)
  end
end

function handlers.PLAYER_LEVEL_UP(level)
  Log("Livello", "ding! nuovo livello", level)
end

function handlers.QUEST_COMPLETE()
  local xp = GetRewardXP and GetRewardXP()
  local cur, max = UnitXP("player"), UnitXPMax("player")
  local ding = (not IsSecret(xp) and not IsSecret(cur) and not IsSecret(max) and type(xp) == "number") and (cur + xp >= max) or "?"
  Log("Quest", "finestra de consegna: XP premio", xp, "barra", cur, "/", max, "farebbe ding:", ding)
end

function handlers.QUEST_TURNED_IN(questID, xpReward, money)
  Log("Quest", "consegnata", questID, "XP", xpReward, "soldi", money)
end

function handlers.DUEL_REQUESTED(challenger)
  Log("Duello", "sfida da", challenger)
end

function handlers.DUEL_FINISHED()
  Log("Duello", "DUEL_FINISHED")
end

function handlers.CHAT_MSG_SYSTEM(msg)
  if IsSecret(msg) then
    if not secretSystemSeen then
      secretSystemSeen = true
      Log("Sistema", "i messaggi de sistema arriveno segreti qui")
    end
    return
  end
  local me = UnitName("player")
  local a = MatchArgs(msg, DUEL_KO)
  if a then Log("Duello", "vince", a[1], "perde", a[2], "io:", me) return end
  a = MatchArgs(msg, DUEL_FLED)
  if a then Log("Duello", "scappato:", a[2], "vince", a[1], "io:", me) return end
end

function handlers.ENCOUNTER_START(id, name, difficulty, size)
  Log("Boss", "inizio", id, name, "difficoltà", difficulty, "gruppo", size)
end

function handlers.ENCOUNTER_END(id, name, difficulty, size, success)
  Log("Boss", "fine", id, name, "riuscito", success)
end

function handlers.BOSS_KILL(id, name)
  Log("Boss", "BOSS_KILL", id, name)
end

function handlers.PLAYER_ENTERING_WORLD(isLogin, isReload)
  if GetInstanceInfo then
    local name, kind, difficulty, _, maxPlayers, _, _, instanceID = GetInstanceInfo()
    Log("Zona", "entrato:", name, "tipo", kind, "difficoltà", difficulty, "max", maxPlayers, "id istanza", instanceID)
  end
end

function handlers.UPDATE_BATTLEFIELD_STATUS(index)
  if not GetBattlefieldStatus then return end
  local status, mapName = GetBattlefieldStatus(index)
  Log("BG", "stato", index, status, mapName)
end

function handlers.PVP_MATCH_COMPLETE(winner, duration)
  local active = C_PvP and C_PvP.GetActiveMatchWinner and C_PvP.GetActiveMatchWinner()
  local old = GetBattlefieldWinner and GetBattlefieldWinner()
  Log("BG", "PVP_MATCH_COMPLETE vincitore", winner, "durata", duration, "GetActiveMatchWinner", active, "GetBattlefieldWinner", old,
    "mia fazione", UnitFactionGroup("player"))
end

local bgWinnerLogged = false
function handlers.UPDATE_BATTLEFIELD_SCORE()
  if bgWinnerLogged or not GetBattlefieldWinner then return end
  local w = GetBattlefieldWinner()
  if w ~= nil then
    bgWinnerLogged = true
    Log("BG", "GetBattlefieldWinner", w, "mia fazione", UnitFactionGroup("player"))
    C_Timer.After(60, function() bgWinnerLogged = false end)
  end
end

function handlers.ADDON_ACTION_BLOCKED(addon, func)
  Log("Bloccato", "er gioco ha bloccato", func, "pe'", addon)
end

function handlers.ADDON_ACTION_FORBIDDEN(addon, func)
  Log("Bloccato", "azione proibita", func, "pe'", addon)
end

function handlers.CHAT_MSG_ADDON(...)
  OnAddonMessage(...)
end

function handlers.CHAT_MSG_CHANNEL_NOTICE(notice, _, _, _, _, _, _, _, channelName)
  if IsSecret(channelName) or channelName ~= nil and string.find(string.lower(tostring(channelName)), TEST_CHANNEL, 1, true) then
    Log("Canale", "avviso", notice, channelName)
  end
end

local events = CreateFrame("Frame")
for _, e in ipairs(EVENTS) do
  local ok = pcall(events.RegisterEvent, events, e)
  if not ok then Log("Avvio", "evento che nun esiste su 'sto client:", e) end
end
events:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if not h then return end
  local ok, err = pcall(h, ...)
  if not ok then Log("Errore", event, err) end
end)

----------------------------------------------------------------------
-- window (vanilla look, built from the game's own textures)
----------------------------------------------------------------------
local frame

local function MakeButton(parent, text, width, onClick)
  local H = ns.UI and ns.UI.H
  local b = H and H.RedButton and H.RedButton(parent, width or 150, 22) or CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 150, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function Sample(parent, label, x, build)
  local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  holder:SetSize(110, 46)
  holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -180)
  build(holder)
  local fs = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("TOP", holder, "BOTTOM", 0, -2)
  fs:SetText(label)
  return holder
end

local function BuildWindow()
  frame = CreateFrame("Frame", "ErPattoDiagFrame", UIParent, "BackdropTemplate")
  frame:SetSize(660, 540)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })
  tinsert(UISpecialFrames, "ErPattoDiagFrame")

  local header = frame:CreateTexture(nil, "ARTWORK")
  header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
  header:SetSize(340, 64)
  header:SetPoint("TOP", 0, 12)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", header, "TOP", 0, -14)
  title:SetText("Er Patto, diagnosi " .. VERSION)
  frame:SetFrameLevel(50)

  local close = (ns.UI and ns.UI.H and ns.UI.H.CloseX) and ns.UI.H.CloseX(frame) or CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  local intro = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  intro:SetPoint("TOPLEFT", 24, -34)
  intro:SetWidth(610)
  intro:SetJustifyH("LEFT")
  intro:SetText("Prova cosa fa er gioco. Usa li pulsanti, fai 'na quest, 'n duello, 'n dungeon, 'na BG. Poi clicca ner registro, Ctrl+A, Ctrl+C e mandalo a chi te l'ha chiesto.")

  -- row 1: environment and channel
  MakeButton(frame, "Rapporto ambiente", 150, EnvReport):SetPoint("TOPLEFT", 24, -78)
  MakeButton(frame, "Entra ner canale de prova", 190, JoinTestChannel):SetPoint("TOPLEFT", 182, -78)
  MakeButton(frame, "Ping canale", 120, function()
    if not testChannelId then Say("prima entra ner canale de prova.") return end
    Ping("CHANNEL", tostring(testChannelId))
  end):SetPoint("TOPLEFT", 380, -78)
  MakeButton(frame, "Pulisci registro", 120, function() ns.db.log = {} RefreshLog() end):SetPoint("TOPLEFT", 508, -78)

  -- row 2: group, guild, whisper
  MakeButton(frame, "Ping gruppo", 120, function()
    if IsInRaid() then Ping("RAID") elseif IsInGroup() then Ping("PARTY") else Say("nun sei in gruppo.") end
  end):SetPoint("TOPLEFT", 24, -124)
  MakeButton(frame, "Ping gilda", 120, function()
    if IsInGuild() then Ping("GUILD") else Say("nun sei in gilda.") end
  end):SetPoint("TOPLEFT", 152, -124)
  local who = CreateFrame("EditBox", "ErPattoDiagWhisper", frame, "InputBoxTemplate")
  who:SetSize(170, 20)
  who:SetPoint("TOPLEFT", 290, -125)
  who:SetAutoFocus(false)
  local whoLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  whoLabel:SetPoint("BOTTOMLEFT", who, "TOPLEFT", -4, 2)
  whoLabel:SetText("Nome d'un amico, come lo vedi in gioco")
  MakeButton(frame, "Ping sussurro", 130, function()
    local target = strtrim(who:GetText() or "")
    if target == "" then Say("scrivi prima er nome.") return end
    Ping("WHISPER", target)
  end):SetPoint("TOPLEFT", 470, -124)

  -- texture check: if a sample is empty or green, that texture is missing on this client
  local check = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  check:SetPoint("TOPLEFT", 24, -160)
  check:SetText("Prova de le texture classiche (se uno è vòto o verde, manca):")
  Sample(frame, "Bordo tooltip", 24, function(h)
    h:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    h:SetBackdropColor(0, 0, 0, 0.9)
  end):SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -180)
  Sample(frame, "Barra stato", 150, function(h)
    local bar = CreateFrame("StatusBar", nil, h)
    bar:SetAllPoints()
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.58, 0, 0.55)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.6)
  end):SetPoint("TOPLEFT", frame, "TOPLEFT", 150, -180)
  Sample(frame, "Bordo addon", 276, function(h)
    local t = h:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\rail.tga")
  end):SetPoint("TOPLEFT", frame, "TOPLEFT", 276, -180)
  Sample(frame, "Pietra addon", 402, function(h)
    local t = h:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints()
    t:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\bg.tga")
  end):SetPoint("TOPLEFT", frame, "TOPLEFT", 402, -180)
  Sample(frame, "Barra XP", 528, function(h)
    local bar = CreateFrame("StatusBar", nil, h)
    bar:SetAllPoints()
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.0, 0.39, 0.88)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0.35)
    local border = h:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\MainMenuBar\\UI-XP-Bar")
    border:SetAllPoints()
  end):SetPoint("TOPLEFT", frame, "TOPLEFT", 528, -180)

  -- copyable log
  local logTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  logTitle:SetPoint("TOPLEFT", 24, -262)
  logTitle:SetText("Registro")
  local scroll = CreateFrame("ScrollFrame", "ErPattoDiagLogScroll", frame, "UIPanelScrollFrameTemplate")
  if ns.UI and ns.UI.H then ns.UI.H.VanillaScroll(scroll) end
  scroll:SetPoint("TOPLEFT", 24, -280)
  scroll:SetPoint("BOTTOMRIGHT", -42, 22)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject(ChatFontNormal)
  box:SetWidth(580)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then RefreshLog() end
  end)
  scroll:SetScrollChild(box)
  local bg = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  bg:SetColorTexture(0, 0, 0, 0.5)
  bg:SetPoint("TOPLEFT", scroll, -4, 4)
  bg:SetPoint("BOTTOMRIGHT", scroll, 24, -4)

  RefreshLog = function()
    if not (frame and frame:IsShown() and ns.db) then return end
    box:SetText(table.concat(ns.db.log, "\n"))
    C_Timer.After(0, function() scroll:SetVerticalScroll(scroll:GetVerticalScrollRange()) end)
  end
  frame:SetScript("OnShow", RefreshLog)
end

local function Toggle()
  -- a frame is shown when it's made: the first /patto diag just opens it
  if not frame then BuildWindow() frame:Show() return end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

ns.OnLog = function() RefreshLog() end
ns.Diag = { Toggle = Toggle, EnvReport = EnvReport }
