-- Er Patto: start-up, saved data, events, notifications and slash commands.
local ADDON, ns = ...
local U, M, P, C, T = ns.U, ns.M, ns.P, ns.C, ns.T

local DEFAULT_OPTS = { hud = true, notify = true, sound = true, testMode = false, questWarn = true, toasts = true, toastSound = true, minimap = true }

ns.me, ns.myName, ns.state, ns.recordGuid, ns.alt = nil, nil, nil, nil, false

----------------------------------------------------------------------
-- saved data (account-wide): ErPattoDB = { patti = {[code] = state}, chars = {[guid] = {...}}, opts, log, run }
----------------------------------------------------------------------
function ns.InitDB()
  if type(ErPattoDB) ~= "table" then ErPattoDB = {} end
  local db = ErPattoDB
  if type(db.patti) ~= "table" then db.patti = {} end
  if type(db.chars) ~= "table" then db.chars = {} end
  if type(db.opts) ~= "table" then db.opts = {} end
  for k, v in pairs(DEFAULT_OPTS) do if db.opts[k] == nil then db.opts[k] = v end end
  if type(db.log) ~= "table" then db.log = {} end
  db.schema = 2
  -- Phase 0 left its own keys; they are harmless but the log format changed
  db.ui = type(db.ui) == "table" and db.ui or {}
  ns.db = db
  return db
end

local function MyChar()
  local c = ns.db.chars[ns.me]
  if not c then
    c = { name = ns.myName }
    ns.db.chars[ns.me] = c
  end
  c.name = ns.myName
  return c
end

----------------------------------------------------------------------
-- which patto this character belongs to
----------------------------------------------------------------------
-- returns state, recordGuid, isAlt
function ns.FindPatto()
  local c = ns.db.chars[ns.me]
  if c and c.code and ns.db.patti[c.code] then return ns.db.patti[c.code], ns.me, false end
  -- another character of this account is in a patto: this one is an alt of that main
  for code, st in pairs(ns.db.patti) do
    if type(st) == "table" and st.main and st.main ~= ns.me and st.members and st.members[st.main] then
      return st, st.main, true
    end
  end
  return nil
end

local function Activate(state, recordGuid, isAlt)
  ns.state, ns.recordGuid, ns.alt = state, recordGuid, isAlt and true or false
  local c = MyChar()
  c.alt = ns.alt or nil
  if not isAlt then c.code = state.code end
  state.lastWeek = state.lastWeek or (P.HasSettings(state) and M.WeekIndex(state.settings, U.Now()) or nil)
  C.Start(state, recordGuid, ns.myName)
  T.Start(state, recordGuid, ns.me, ns.myName, isAlt)
  U.Log("Patto", "attivo", state.code, isAlt and "alt" or "principale")
  ns.Fire("PattoChanged", state)
end

function ns.CreatePatto(opts)
  if ns.state and not ns.alt then return nil, "Stai già in un patto: prima esci da quello." end
  if ns.alt then ns.LeavePatto(true) end
  opts.guid, opts.playerName = ns.me, ns.myName
  local state = P.Create(opts)
  state.main = ns.me
  ns.db.patti[state.code] = state
  Activate(state, ns.me, false)
  U.Say("Patto creato! Er codice è |cffffffff" .. state.code .. "|r: dallo all'amichi.")
  return state
end

-- text: the code a friend gave ("98LX8 Er Gnomo": the code and their name, the first one to whisper on Forever);
-- by: the name of who sent an invite
function ns.JoinPatto(text, by)
  local code, named = P.ParseInvite(text)
  by = by or named
  if not code then return nil, "Er codice nun è giusto: so' 5 lettere o nummeri, tipo K7Q2M." end
  if ns.state and not ns.alt then
    if ns.state.code == code then return ns.state end
    return nil, "Stai già in un patto: prima esci da quello."
  end
  if ns.alt then ns.LeavePatto(true) end
  local old = ns.db.patti[code]
  local state
  if type(old) == "table" and type(old.members) == "table" then
    state = old
    P.AddMember(state, ns.me, ns.myName)
  else
    state = P.Join(code, ns.me, ns.myName)
  end
  -- back in a patto I left from this PC: what I had done in it is mine again
  local gone = type(ns.db.gone) == "table" and ns.db.gone[code]
  if type(gone) == "table" and gone.guid == ns.me and state.members[ns.me] then
    P.Absorb(state.members[ns.me], P.CleanMember(gone) or {}, state.joinedAt)
    ns.db.gone[code] = nil
    U.Log("Patto", "rientrato ner patto", code, ": ripresi li dati de prima")
  end
  state.main = ns.me
  ns.db.patti[code] = state
  Activate(state, ns.me, false)
  if type(by) == "string" and by:match("%S") then C.AddSeed(by) end
  U.Say("Sei entrato ner patto " .. code .. ". Mo' aspetta 'n attimo che l'altri te passino i dati.")
  return state
end

-- quiet = true when switching from alt mode: nothing is deleted
function ns.LeavePatto(quiet)
  if not ns.state then return end
  local code = ns.state.code
  if not quiet and not ns.alt then pcall(C.SayGoodbye) end
  C.Stop()
  T.Stop()
  if not quiet and not ns.alt then
    -- my record of this patto stays on this PC: coming back in with the same code, it's all there again
    local mine = ns.state.members[ns.recordGuid]
    if mine then
      ns.db.gone = type(ns.db.gone) == "table" and ns.db.gone or {}
      ns.db.gone[code] = U.Copy(mine)
    end
    ns.db.patti[code] = nil
    for _, c in pairs(ns.db.chars) do
      if c.code == code then c.code = nil end
      c.alt = nil
    end
    U.Say("Sei uscito dar patto " .. code .. ".")
  end
  ns.state, ns.recordGuid, ns.alt = nil, nil, false
  ns.Fire("PattoChanged", nil)
end

function ns.MyRecord()
  return ns.state and ns.state.members[ns.recordGuid]
end

function ns.MyStatus()
  local rec = ns.MyRecord()
  if not rec or not rec.team or not P.HasSettings(ns.state) then return nil end
  return M.Status(ns.state.settings, rec.team, U.Now())
end

function ns.CanAdmin()
  return ns.state and not ns.alt and P.IsAdmin(ns.state, ns.me)
end

function ns.IsCapo()
  return ns.state and not ns.alt and P.IsCapo(ns.state, ns.me)
end

----------------------------------------------------------------------
-- notifications
----------------------------------------------------------------------
local function Notify(text)
  if ns.db and ns.db.opts.notify then U.Say(text) end
end

ns.On("SelfChanged", function(state, reason)
  if state ~= ns.state then return end
  -- frequent small changes wait a minute, important ones go out in a few seconds
  local SLOW = { xp = 1, zone = 1, g = 1, equip = 1, pt = 1, prof = 1, hn = 1, tr = 1, fi = 1, he = 1, mi = 1, sk = 1, fun = 1, hs = 1, fl = 1, pts = 1 }
  local slow = SLOW[reason] ~= nil
  -- what the others must see at once goes before what waits: a squadra, a ding, a death, a duel or a pegno, a bet
  local FAST = { team = 1, level = 1, rip = 1, silly = 1, sfide = 1, vote = 1 }
  if FAST[reason] then C.MarkSelfDirty(0.3, true) else C.MarkSelfDirty(slow and 60 or 4) end
  ns.Fire("Refresh")
end)

-- my record came back from a friend (this PC had lost it): say so, and send it on as mine again
ns.On("SelfRestored", function()
  U.Say("ho ritrovato li dati tua dall'amichi der patto: piotte, statistiche e titoli so' tornati.")
  C.MarkSelfDirty(1)
  ns.Fire("Refresh")
end)

-- a ding of someone else: News.lua says it (one line with "[Er Patto]" and the ping), not here too
ns.On("MemberSwitched", function(rec, oldTeam)
  if not ns.state then return end
  Notify("|cffffffff" .. tostring(rec.name) .. "|r è passato da " .. P.TeamName(ns.state, oldTeam) .. " a " .. P.TeamName(ns.state, rec.team) .. ".")
end)

ns.On("MemberLeft", function(rec)
  if not ns.state then return end
  Notify("|cffffffff" .. tostring(rec.name) .. "|r è uscito dar patto.")
  ns.Fire("Refresh")
end)

-- my own admin edits go out right away
ns.On("SettingsChanged", function(state)
  if state ~= ns.state then return end
  C.Send("S", state.settings)
  T.RefreshSelf("settings")
  ns.Fire("Refresh")
end)
ns.On("AdminsChanged", function(state)
  if state ~= ns.state then return end
  C.Send("A", state.admins)
  ns.Fire("Refresh")
end)
ns.On("MembersChanged", function(state)
  if state ~= ns.state then return end
  C.Send("B", state.bans)
  ns.Fire("Refresh")
end)

local hadSettings
ns.On("StateChanged", function(state, kind)
  if state ~= ns.state then return end
  if kind == "S" then
    if not hadSettings then
      Notify("Dati der patto arrivati: " .. tostring(state.settings.name or "") .. ".")
    else
      Notify("Er capo ha aggiornato er patto (ritmo o squadre): controlla er cap.")
    end
    hadSettings = true
    T.RefreshSelf("settings")
  end
  ns.Fire("Refresh")
end)

ns.On("PattoChanged", function(state)
  hadSettings = state and P.HasSettings(state) or false
  ns.Fire("Refresh")
end)

-- new week: say the new cap once
function ns.CheckWeek()
  local state = ns.state
  if not state or not P.HasSettings(state) then return end
  local wk = M.WeekIndex(state.settings, U.Now())
  if state.lastWeek == wk then return end
  local first = state.lastWeek == nil
  state.lastWeek = wk
  if first or wk < 1 then return end
  local st = ns.MyStatus()
  if st then
    if st.lifted then
      Notify("Settimana " .. wk .. ": er cap è tolto, se va ar 60.")
    else
      Notify("Settimana " .. wk .. " sbloccata: er cap de " .. st.team.name .. " mo' è |cffffffff" .. st.cap .. "|r.")
    end
  end
  T.RefreshSelf("week")
  ns.Fire("Refresh")
end

----------------------------------------------------------------------
-- slash commands
----------------------------------------------------------------------
local function Help()
  U.Say("comandi:")
  U.Say("  /patto - apre la finestra")
  U.Say("  /patto stato - er cap tuo in chat")
  U.Say("  /patto sync - chiede subito l'aggiornamenti all'altri")
  U.Say("  /patto annuncio - rivedi l'annuncio der capo")
  U.Say("  /patto invita Nome - invita 'n amico ner patto")
  U.Say("  /patto bollettino - er riassunto de la settimana scorsa")
  U.Say("  /patto condividi - la settimana in testo, da incollà su Discord")
  U.Say("  /patto bug - rapporto pe' segnalà 'n problema")
  U.Say("  /patto prova - modalità de prova, solo pe' er capo (membri finti, li vedi solo te)")
  U.Say("  /patto diag - diagnosi (pe' segnalà problemi)")
end

function ns.PrintStatus()
  if not ns.state then U.Say("nun stai in nessun patto. Scrivi /patto pe' creanne uno o entrà co' 'n codice.") return end
  if not P.HasSettings(ns.state) then U.Say("aspetto ancora i dati der patto dall'altri (" .. ns.state.code .. ").") return end
  local st = ns.MyStatus()
  if not st then U.Say("nun hai scelto la squadra: apri /patto.") return end
  local rec = ns.MyRecord()
  if not st.started then
    U.Say(st.team.name .. ": er patto parte " .. U.When(ns.state.settings.start) .. " (tra " .. U.Until(ns.state.settings.start - U.Now()) .. "). Primo cap: " .. st.cap .. ".")
  elseif st.lifted then
    U.Say(st.team.name .. ": niente più cap, vai ar 60.")
  else
    local state = M.PlayerState(rec and rec.lv, st.cap)
    local word = ({ over = "sei sopra", at = "sei ar cap", behind = "te mancano " .. (st.cap - (rec.lv or 0)) .. " livelli", unknown = "" })[state]
    U.Say(st.team.name .. ", settimana " .. st.week .. ": cap " .. st.cap .. " (" .. word .. "). Prossimo: " .. st.nextCap .. " " .. U.When(st.unlockAt) .. ".")
  end
end

SLASH_ERPATTO1 = "/patto"
SLASH_ERPATTO2 = "/erpatto"
SlashCmdList.ERPATTO = function(raw)
  raw = tostring(raw or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local msg = string.lower(raw)
  -- the whole name after "invita": on Forever it's name and surname ("/patto invita Er Nia")
  local invite = raw:match("^[Ii][Nn][Vv][Ii][Tt][Aa]%s+(.-)%s*$")
  if invite == "" then invite = nil end
  if invite then
    ns.InviteFriend(invite)
  elseif msg == "invita" then
    U.Say("scrivi /patto invita Nome (o tasto destro sur ritratto, \"Invita ner patto\").")
  elseif msg == "bollettino" then
    if ns.Home then ns.Home.ShowBulletin(true) end
  elseif msg == "condividi" or msg == "discord" then
    if ns.Extras then ns.Extras.ShowShare() end
  elseif msg == "bug" then
    if ns.Extras then ns.Extras.BugReport() end
  elseif msg == "minimappa" then
    ns.db.opts.minimap = not ns.db.opts.minimap
    ns.Fire("Refresh")
  elseif msg == "" then
    if ns.UI then ns.UI.Toggle() end
  elseif msg == "diag" or msg == "diagnosi" then
    if ns.Diag then ns.Diag.Toggle() end
  elseif msg == "prova" or msg == "test" then
    if not ns.IsCapo() then U.Say("la modalità de prova la pò accenne solo er capo.") return end
    ns.db.opts.testMode = not ns.db.opts.testMode
    U.Say("modalità de prova " .. (ns.db.opts.testMode and "accesa: vedi membri finti (solo te)." or "spenta."))
    ns.Fire("Refresh")
  elseif msg == "annuncio" then
    if ns.UI then ns.UI.ShowAnnouncement() end
  elseif msg == "stato" or msg == "cap" then
    ns.PrintStatus()
  elseif msg == "sync" then
    if ns.state then C.Hello() U.Say("ho chiesto l'aggiornamenti.") end
  elseif msg == "bloccati" then
    -- what the game blocked, and from where (to find it and fix it)
    local list = (#U.blocked > 0) and U.blocked or (ns.db.blocked or {})
    if #list == 0 then U.Say("er gioco nun ha bloccato gnente.") end
    for i = 1, math.min(3, #list) do
      local x = list[i]
      U.Say(U.When(x.at) .. " (" .. tostring(x.ev or "bloccato") .. "): " .. tostring(x.fn))
      for l in tostring(x.st or ""):gmatch("[^\n]+") do
        local short = l:match("AddOns[/\\](.-%:%d+)") or l:sub(1, 90)
        U.Say("   " .. short)
      end
    end
  elseif msg == "hud" then
    ns.db.opts.hud = not ns.db.opts.hud
    ns.Fire("Refresh")
  else
    Help()
  end
end

-- invite a player by name: they get a window to join in one click. out(text, good) writes where the button is
-- (the Impostazioni page); from /patto the answer goes in the chat
local inviteOut
function ns.InviteFriend(name, out)
  inviteOut = out
  local function tell(t, good) if out then out(t, good) else U.Say(t) end end
  if not ns.state or ns.alt then tell("Prima entra (o crea) 'n patto.") return end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then tell("Scrivi er nome der personaggio.") return end
  if not C.Invite(name) then tell("Nun so' riuscito a manda l'invito a " .. name .. ".") return end
  tell("Invito mannato a " .. name .. ".", true)
  if C_Timer then
    C_Timer.After(8, function()
      for _, who in ipairs(C.PendingInvites(7)) do
        tell(who .. " nun risponne: forse nun ha l'addon o nun è online. Daje er codice " .. ns.state.code .. ".")
      end
    end)
  end
end
ns.On("InviteArrived", function(who)
  local t = who .. " ha ricevuto l'invito."
  if inviteOut then inviteOut(t, true) else U.Say(t) end
end)

function ErPatto_OnCompartmentClick()
  if ns.UI then ns.UI.Toggle() end
end

----------------------------------------------------------------------
-- events
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
ns.eventFrame = frame
local handlers = {}

handlers.ADDON_LOADED = function(name)
  if name ~= ADDON then return end
  ns.InitDB()
  C.RegisterPrefix() -- invites reach you even before you're in a patto
  U.Log("Avvio", "versione", ns.VERSION)
end

handlers.PLAYER_LOGIN = function()
  if not ns.db then ns.InitDB() end
  ns.me = U.Plain(UnitGUID("player"), "string")
  ns.myName = U.FullName("player") or "?"
  if not ns.me then U.Log("Errore", "GUID segreto o mancante") return end
  MyChar()
  local state, recordGuid, isAlt = ns.FindPatto()
  if state then
    Activate(state, recordGuid, isAlt)
    if isAlt then
      local main = state.members[recordGuid]
      U.Say("'sto personaggio è 'n alt de " .. tostring(main and main.name) .. ": vedi er patto ma nun conta pe' i livelli.")
    end
    if P.HasSettings(state) and M.WeekIndex(state.settings, U.Now()) == 0 then
      U.Say("er patto parte " .. U.When(state.settings.start) .. " (tra " .. U.Until(state.settings.start - U.Now()) .. ").")
    end
  else
    U.Say("nun stai in nessun patto: scrivi |cffffffff/patto|r pe' creallo o entrà co' 'n codice.")
  end
  if C_Timer then
    C_Timer.NewTicker(30, function() ns.CheckWeek() end)
    C_Timer.After(5, function() ns.CheckWeek() end)
  end
  ns.Fire("Login")
end

handlers.PLAYER_ENTERING_WORLD = function()
  T.OnEnteringWorld()
  if ns.state then C.OnZoneChanged() T.RefreshSelf("zone") end
end
handlers.ZONE_CHANGED_NEW_AREA = function()
  if ns.state then C.OnZoneChanged() T.RefreshSelf("zone") end
end
handlers.PLAYER_LEVEL_UP = function(level)
  T.RefreshSelf("level", U.Plain(level, "number"))
end
handlers.PLAYER_XP_UPDATE = function(unit)
  if unit == nil or unit == "player" then T.RefreshSelf("xp") end
end
handlers.QUEST_COMPLETE = function()
  if ns.db.opts.questWarn then T.OnQuestComplete() end
end
handlers.QUEST_FINISHED = function() ns.Fire("QuestWarning", nil) end
handlers.QUEST_TURNED_IN = function(questID, xp, money) T.OnQuestTurnedIn(U.Plain(questID, "number"), xp, money) end
handlers.PLAYER_DEAD = function() T.OnDeath() end
handlers.TIME_PLAYED_MSG = function(total) T.OnTimePlayed(total) end
handlers.PLAYER_PVP_KILLS_CHANGED = function() T.CheckPvP() end
handlers.CURRENCY_DISPLAY_UPDATE = function() T.CheckPvP() end
handlers.PLAYER_PVP_RANK_CHANGED = function() T.CheckPvP() end
handlers.PLAYER_TARGET_CHANGED = function() T.CheckRare("target") end
handlers.UNIT_HEALTH = function(unit) if unit == "target" then T.CheckRare("target") end end
handlers.LOOT_OPENED = function() T.CheckRare("target") end
handlers.SKILL_LINES_CHANGED = function() T.RefreshProfessions() end
handlers.CHAT_MSG_SYSTEM = function(msg) T.OnSystemMessage(msg) end
handlers.ENCOUNTER_END = function(_, _, _, _, success) T.OnBossKill(success) end
handlers.UPDATE_BATTLEFIELD_STATUS = function(index) T.OnBattlefieldStatus(index) end
handlers.PVP_MATCH_COMPLETE = function(winner) T.OnMatchComplete(winner) end
handlers.UPDATE_BATTLEFIELD_SCORE = function() T.OnBattlefieldScore() end
handlers.CHAT_MSG_ADDON = function(...) C.OnAddonMessage(...) end
handlers.BN_CHAT_MSG_ADDON = function(...) C.OnBNAddon(...) end
-- the patto's channel: its member list, and the notice that it refuses addon messages (WoW Forever)
handlers.CHANNEL_ROSTER_UPDATE = function(index) C.OnRosterUpdate(index) end
handlers.CHANNEL_COUNT_UPDATE = function(index) C.OnChannelCount(index) end
handlers.CHAT_MSG_CHANNEL_NOTICE = function(...) C.OnChannelNotice(...) end
handlers.PLAYER_MONEY = function() T.OnMoney() end
handlers.MAIL_SHOW = function() T.SetMoneyBlock("mail", true) end
handlers.MAIL_CLOSED = function() T.SetMoneyBlock("mail", false) end
handlers.TRADE_SHOW = function() T.SetMoneyBlock("trade", true) end
handlers.TRADE_CLOSED = function() T.SetMoneyBlock("trade", false) end
handlers.PLAYER_EQUIPMENT_CHANGED = function()
  T.RefreshSelf("equip")
  ns.Fire("Equipment")
end
handlers.UNIT_MODEL_CHANGED = function(unit)
  if unit == "player" then ns.Fire("Equipment") end
end
handlers.PLAYER_LOGOUT = function()
  if ns.state then ns.state.savedAt = U.Now() end
end

frame:SetScript("OnEvent", function(_, event, ...)
  local fn = handlers[event]
  if not fn then return end
  local ok, err = pcall(fn, ...)
  if not ok then U.Log("Errore", event, err) end
end)

-- unit events only for the unit we care about, so they don't fire for every mob around
local UNIT_ONLY = { UNIT_HEALTH = "target", UNIT_MODEL_CHANGED = "player" }
for event in pairs(handlers) do
  -- some events may not exist in every client: never let one break the rest
  if UNIT_ONLY[event] and frame.RegisterUnitEvent then
    pcall(frame.RegisterUnitEvent, frame, event, UNIT_ONLY[event])
  else
    pcall(frame.RegisterEvent, frame, event)
  end
end

ns.handlers = handlers
