-- Er Patto: titles you win inside the patto. Each player picks one of the titles they hold; it shows next to their
-- name in the patto's windows and in front of what they write in chat. Every client checks titles from the shared
-- records, so nobody can show a title they don't hold.
local ADDON, ns = ...
local U, M, P, T, UI = ns.U, ns.M, ns.P, ns.T, ns.UI
local H = UI.H
local Ti = {}
ns.Titles = Ti

local function Stat(m, k) return H.StatOf(m, k, "t") end

local function InPattoDuels(m, idx)
  local w, l = 0, 0
  for name, h in pairs(m.h2h or {}) do
    local other = idx[name]
    if other and other.guid ~= m.guid and type(h) == "table" then
      w, l = w + (h.w or 0), l + (h.l or 0)
    end
  end
  return w, l
end

local function Count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- all the professions together: Fishing 70 and Blacksmithing 40 beat Fishing 70 alone
local function AllProfessions(m)
  local sum = 0
  for _, p in ipairs(m.pr or {}) do sum = sum + (tonumber(p.l) or 0) end
  return sum
end
-- the fewest deaths, among who played at least 5 hours; the same deaths: who played longer
local function FewestDeaths(m)
  local pt = Stat(m, "pt")
  if pt < 18000 then return 0 end
  return math.max(1, 10000 - Stat(m, "dt")) * 100000 + math.min(99999, math.floor(pt / 3600))
end

-- kind "top": the one with the highest value, if above zero; nobody on a tie
-- kind "check": a condition on the member; of those who meet it, only the first who did (tt) holds it
Ti.LIST = {
  { id = "pariolino", name = "A Pariolino", kind = "top", value = function(m) return Stat(m, "g") end, desc = "Er primo der patto pe' sordi fatti." },
  { id = "bancarellaro", name = "A Bancarellaro", kind = "top", value = function(m) return Stat(m, "ga") end, desc = "Er primo pe' sordi fatti vennenno a l'asta: c'ha 'na bancarella a Porta Portese." },
  { id = "fattorino", name = "A Fattorino", kind = "top", value = function(m) return Stat(m, "q") end, desc = "Er primo pe' quest consegnate: te fai tutte le commissioni de Azeroth." },
  { id = "topo", name = "A Topo de Fogna", kind = "top", value = function(m) return Stat(m, "dg") end, desc = "Er primo pe' dungeon fatti: vivi sotto terra." },
  { id = "bullo", name = "A Bullo", kind = "top", value = function(m, c) return (InPattoDuels(m, c.idx)) end, desc = "Er primo pe' duelli vinti contro l'artri der patto." },
  { id = "sacco", name = "A Sacco da Boxe", kind = "top", value = function(m, c) return select(2, InPattoDuels(m, c.idx)) end, desc = "Chi ha perso più duelli ner patto. Armeno ce provi." },
  { id = "gladiatore", name = "A Gladiatore", kind = "top", value = function(m) return Stat(m, "bw") end, desc = "Er primo pe' campi de battaja vinti." },
  { id = "attaccabrighe", name = "A Attaccabrighe", kind = "top", value = function(m) return Stat(m, "hw") end, desc = "Er primo pe' uccisioni onorevoli pe' strada (fori dai battleground): nun te se pò incontrà." },
  { id = "presenzialista", name = "A Presenzialista", kind = "top", value = function(m) return Stat(m, "ap") end, desc = "Er primo pe' appuntamenti der Lunario fatti co' la squadra: nun ne salta uno." },
  { id = "legionario", name = "A Legionario", kind = "top", value = function(m) return Stat(m, "hb") end, desc = "Er primo pe' uccisioni onorevoli ner battleground: sempre in prima fila." },
  { id = "pretoriano", name = "A Pretoriano", kind = "top", value = function(m) return Stat(m, "hn") end, desc = "Er primo pe' onore guadagnato." },
  { id = "bracconiere", name = "A Bracconiere", kind = "top", value = function(m) return Stat(m, "rk") end, desc = "Er primo pe' mostri rari ammazzati." },
  { id = "fenomeno", name = "A Fenomeno", kind = "top", value = function(m) return H.Position(m) end, desc = "Er più avanti de livello de tutto er patto." },
  { id = "pensionato", name = "A Pensionato", kind = "top", value = function(m) return Stat(m, "pt") end, desc = "Chi ha giocato più ore da quanno è partito er patto. Ma nun lavori?" },
  { id = "nottambulo", name = "A Nottambulo", kind = "top", value = function(m) return H.StatOf(m, "pt", "w") end, desc = "Chi ha giocato de più 'sta settimana." },
  { id = "cascamorto", name = "A Cascamorto", kind = "top", value = function(m) return Stat(m, "dt") end, desc = "Chi è morto più vorte. Casca e more." },
  { id = "griffato", name = "A Griffato", kind = "top", value = function(m, c) return c.il(m) end, desc = "Er livello oggetti più arto der patto: tutto firmato." },
  { id = "mastro", name = "A Mastro", kind = "top", value = AllProfessions, desc = "Er mastro de le professioni: la somma de tutte le professioni sua è la più arta der patto." },
  { id = "pellaccia", name = "A Pellaccia", kind = "top", value = FewestDeaths, desc = "Chi è morto meno vorte (armeno 5 ore de gioco; a pari morti, chi ha giocato de più). C'ha la pelle dura." },
  { id = "fortunello", name = "A Fortunello", kind = "top", desc = "Er più fortunato: più blu e epici pe' ora de gioco (armeno 2 ore).",
    value = function(m) return Stat(m, "pt") >= 7200 and ns.Fun and ns.Fun.LuckOf(m, "t") or 0 end },
  { id = "iettato", name = "A Iettato", kind = "top", desc = "Er più sfigato: manco 'n blu (armeno 5 ore de gioco). Toccate quarcosa.",
    value = function(m) return Stat(m, "pt") >= 18000 and (1000 - math.min(999, ns.Fun and ns.Fun.LuckOf(m, "t") or 0)) or 0 end },
  { id = "pescivendolo", name = "A Pescivendolo", kind = "top", desc = "Chi ha pescato più pesci.", value = function(m) return Stat(m, "fi") end },
  { id = "fruttarolo", name = "A Fruttarolo", kind = "top", desc = "Chi ha raccorto più erbe, minerali e pelli.",
    value = function(m) return Stat(m, "he") + Stat(m, "mi") + Stat(m, "sk") end },
  { id = "pellegrino", name = "A Pellegrino", kind = "top", desc = "Chi ha camminato de più: le scarpe so' finite.", value = function(m) return Stat(m, "tr") end },
  { id = "cacciatore", name = "A Cacciatore", kind = "top", desc = "Chi ha ammazzato più boss e rari.", value = function(m) return Stat(m, "nk") end },
  { id = "imbranato", name = "A Imbranato", kind = "top", desc = "Chi è morto più vorte in modo ridicolo: cascato, affogato o da 'n pischello.",
    value = function(m) return Stat(m, "em") end },
  { id = "campione", name = "A Campione", kind = "check", desc = "Ha mannato a la gogna er campione: la corona è sua finché nun ce va lui.",
    check = function(m) return ns.Sfide and ns.Sfide.Champion() == m.guid end },
  { id = "pecore", name = "A Pecorone", kind = "top", desc = "Chi è stato più vorte a la gogna.",
    value = function(m) return ns.Sfide and ns.Sfide.ShameOf(m.guid) or 0 end },
  { id = "tombolaro", name = "A Strozzino", kind = "top", desc = "Er più ricco der Botteghino: più piotte de tutti.",
    value = function(m) return math.max(0, (ns.Tombola and ns.Tombola.TotalOf(m) or 0) - 20) end },
  { id = "imperatore", name = "A Imperatore", kind = "check", desc = "Er primo der patto a arrivà ar 60.",
    check = function(m, c) return c.first60 and c.first60 == m.guid end },
  { id = "centurione", name = "A Centurione", kind = "check", desc = "Er primo der patto a consegnà cento quest.", check = function(m) return Stat(m, "q") >= 100 end },
  { id = "bottegaio", name = "A Bottegaio", kind = "check", desc = "Er primo der patto a fà cento monete d'oro.", check = function(m) return Stat(m, "g") >= 1000000 end },
  { id = "turista", name = "A Turista", kind = "check", desc = "Er primo der patto a fà quest in sei zone diverse.", check = function(m) return Count(m.zq) >= 6 end },
  { id = "cavernicolo", name = "A Cavernicolo", kind = "check", desc = "Er primo der patto a fà cinque dungeon diversi.", check = function(m) return Count(m.dgl) >= 5 end },
  { id = "immortale", name = "A Immortale", kind = "check", desc = "Er primo a arrivà a dieci ore de gioco senza morì mai (finché nun more).",
    check = function(m) return Stat(m, "pt") >= 36000 and Stat(m, "dt") == 0 end },
  { id = "furbetto", name = "A Furbetto", kind = "check", desc = "Er primo che è passato sopra er cap de la squadra sua (finché ce sta). Se vede, eh.",
    check = function(m, c) local st = m.team and M.Status(c.settings, m.team, U.Now()) return st and st.started and not st.lifted and (m.lv or 0) > st.cap end },
  { id = "sorcapo", name = "A Sor Capo", kind = "check", desc = "Er capo der patto.", check = function(m, c) return c.admins.capo == m.guid end },
  { id = "braccio", name = "A Braccio", kind = "check", desc = "Er primo vice der capo.", check = function(m, c) return (c.admins.vice or {})[m.guid] and true or false end },
  { id = "pischello", name = "A Pischello", kind = "check", desc = "L'urtimo rimasto sotto ar livello 10.", check = function(m) return (m.lv or 0) > 0 and (m.lv or 0) < 10 end },
}

-- one title per profession, for whoever has it highest in the patto (names as the English client writes them)
local PROFESSIONS = {
  { "Engineering", "scienziato", "A Scienziato", "Er più bravo in Engineering: te fai esplode tutto." },
  { "Blacksmithing", "fabbro", "A Fabbro", "Er più bravo in Blacksmithing." },
  { "Alchemy", "alchimista", "A Alchimista", "Er più bravo in Alchemy: te le fai da solo, le pozioni." },
  { "Tailoring", "sarto", "A Sarto", "Er più bravo in Tailoring." },
  { "Leatherworking", "conciatore", "A Conciatore", "Er più bravo in Leatherworking." },
  { "Enchanting", "incantatore", "A Incantatore", "Er più bravo in Enchanting." },
  { "Mining", "minatore", "A Minatore", "Er più bravo in Mining." },
  { "Herbalism", "erborista", "A Erborista", "Er più bravo in Herbalism: a coje l'erbetta." },
  { "Skinning", "scortichino", "A Scortichino", "Er più bravo in Skinning." },
  { "Cooking", "cuoco", "A Cuoco", "Er più bravo in Cooking: amatriciana pe' tutti." },
  { "Fishing", "pescatore", "A Pescatore", "Er più bravo in Fishing." },
  { "First Aid", "infermiere", "A Infermiere", "Er più bravo in First Aid." },
}
for _, p in ipairs(PROFESSIONS) do
  local prof = p[1]
  Ti.LIST[#Ti.LIST + 1] = { id = p[2], name = p[3], kind = "top", group = "mestieri", desc = p[4], value = function(m)
    for _, x in ipairs(m.pr or {}) do if x.n == prof then return x.l or 0 end end
    return 0
  end }
end
Ti.BY_ID = {}
for _, t in ipairs(Ti.LIST) do
  Ti.BY_ID[t.id] = t
  t.group = t.group or (t.kind == "check" and "traguardi" or "primi")
end

local function Context(list)
  local state = ns.state
  local idx = ns.Rank and ns.Rank.NameIndex(list) or {}
  local c = { idx = idx, settings = state.settings, admins = state.admins or {},
    il = function(m) return (m.guid == ns.recordGuid and not ns.alt and T.ItemLevel()) or m.il or 0 end }
  local firstAt
  for _, m in ipairs(list) do
    local at = m.ms and m.ms[60]
    if at and (not firstAt or at < firstAt) then firstAt, c.first60 = at, m.guid end
  end
  return c
end

-- { [guid] = { [titleId] = true } } for everyone in the list
function Ti.Earned(list)
  local out = {}
  if not ns.state then return out end
  local c = Context(list)
  for _, m in ipairs(list) do out[m.guid] = {} end
  for _, t in ipairs(Ti.LIST) do
    if t.kind == "top" then
      local best = 0
      for _, m in ipairs(list) do
        local v = t.value(m, c) or 0
        if v > best then best = v end
      end
      -- a "first of the patto" title is one person's only: on a tie nobody has it until one is ahead
      if best > 0 then
        local who, n = nil, 0
        for _, m in ipairs(list) do if (t.value(m, c) or 0) == best then who, n = m, n + 1 end end
        if n == 1 then out[who.guid][t.id] = true end
      end
    else
      -- a milestone is one person's only too: the first who reached it (the time is in his record, tt), as long
      -- as he still qualifies
      local who, whenAt
      for _, m in ipairs(list) do
        local ok, yes = pcall(t.check, m, c)
        if ok and yes then
          local at = type(m.tt) == "table" and m.tt[t.id] or 4e9
          if not who or at < whenAt or (at == whenAt and tostring(m.guid) < tostring(who.guid)) then who, whenAt = m, at end
        end
      end
      if who then out[who.guid][t.id] = true end
    end
  end
  return out
end

-- the title a member shows, only if they still hold it
local cache = { at = -1, earned = {}, byName = {}, verse = {} }
-- names as the chat writes them: "Er Nia", "Er Nia-Realm", "Er-Nia" (Forever: the surname as if a realm),
-- "Dario-Realm", any case: all to one key
local function NameKey(name)
  name = tostring(name or ""):gsub(" %(prova%)$", "")
  return name:lower()
end
local function Index(map, name, value, firsts)
  local k = NameKey(name)
  map[k] = value
  local short = U.Short(name)
  if short ~= name then map[NameKey(short)] = value end
  local first = k:match("^(%S+)")
  if first and first ~= k and firsts[first] == 1 then map[first] = value end
end
local function Lookup(map, author)
  local k = NameKey(author)
  if map[k] then return map[k] end
  -- "Er-Nia": the dash as the space between name and surname
  local dashed = k:gsub("%-", " ", 1)
  if map[dashed] then return map[dashed] end
  local dashedNoRealm = dashed:match("^([^%-]+)")
  if dashedNoRealm and map[dashedNoRealm] then return map[dashedNoRealm] end
  -- "Er Nia-Realm" / "Dario-Realm": without the realm
  local noRealm = k:match("^([^%-]+)")
  return noRealm and map[noRealm] or nil
end
Ti.NameKey, Ti.Lookup, Ti.Index = NameKey, Lookup, Index

local function Refresh(force)
  if not ns.state then cache.earned, cache.byName = {}, {} return end
  local now = GetTime and GetTime() or 0
  if not force and now - cache.at < 5 then return end
  cache.at = now
  local list = UI.Members()
  cache.earned = Ti.Earned(list)
  cache.byName = {}
  cache.verse = {}
  -- first names that only one member has (on Forever everyone is "Er Something": "Er" alone is nobody)
  local firsts = {}
  for _, m in ipairs(list) do
    local f = type(m.name) == "string" and NameKey(m.name):match("^(%S+)")
    if f then firsts[f] = (firsts[f] or 0) + 1 end
  end
  for _, m in ipairs(list) do
    local t = m.ti and Ti.BY_ID[m.ti]
    if not (t and cache.earned[m.guid] and cache.earned[m.guid][t.id]) then t = nil end
    -- a penitenza wins over the title while it lasts: the nickname, or the picture's name
    local g = ns.Sfide and ns.Sfide.GognaOf(m)
    local n = ns.Sfide and ns.Sfide.NickOf(m)
    local sv = ns.Sfide and ns.Sfide.ServoOf(m)
    if g then t = { id = "gogna", name = g.name, icon = g.icon, desc = g.say } end
    if n then t = { id = "gogna", name = "detto " .. n.t, icon = g and g.icon } end
    if sv then t = { id = "gogna", name = "servo de " .. sv.name, icon = ns.Sfide.PENE[6].icon } end
    local v = ns.Sfide and ns.Sfide.VerseOf(m)
    if v and type(m.name) == "string" then Index(cache.verse, m.name, v.t, firsts) end
    if t and type(m.name) == "string" then Index(cache.byName, m.name, t, firsts) end
  end
end

function Ti.Of(rec)
  if not rec then return nil end
  -- a penitenza wins over any title while it lasts
  local n = ns.Sfide and ns.Sfide.NickOf(rec)
  if n then return "detto \"" .. n.t .. "\"" end
  local sv = ns.Sfide and ns.Sfide.ServoOf(rec)
  if sv then return "servo de " .. sv.name end
  local g = ns.Sfide and ns.Sfide.GognaOf(rec)
  if g then return g.name end
  Refresh()
  local t = rec.ti and Ti.BY_ID[rec.ti]
  if t and cache.earned[rec.guid] and cache.earned[rec.guid][t.id] then return t.name end
  return nil
end

-- { [titleId] = { [guid] = true } }: who holds each title right now
function Ti.Holders()
  Refresh()
  local out = {}
  for guid, set in pairs(cache.earned) do
    for id in pairs(set) do
      out[id] = out[id] or {}
      out[id][guid] = true
    end
  end
  return out
end

-- every title a member holds right now (for the diary)
function Ti.Held(rec)
  Refresh()
  local held = rec and cache.earned[rec.guid] or {}
  local out = {}
  for _, t in ipairs(Ti.LIST) do if held[t.id] then out[#out + 1] = t end end
  return out
end

function Ti.Mine()
  Refresh()
  local mine = cache.earned[ns.recordGuid] or {}
  local out = {}
  for _, t in ipairs(Ti.LIST) do if mine[t.id] then out[#out + 1] = t end end
  return out
end

function Ti.Choose(id)
  if not ns.state or ns.alt then return end
  local rec = ns.state.members[ns.recordGuid]
  if not rec then return end
  if id == "" then id = nil end
  -- write it straight into my record, then let UpdateSelf stamp and send it (an empty value is how "none" travels)
  P.UpdateSelf(ns.state, ns.recordGuid, { ti = id or "" }, "title")
  rec.ti = id
  rec.up = U.Now()
  cache.at = -1
  Refresh(true)
  ns.Fire("SelfChanged", ns.state, "title")
end

----------------------------------------------------------------------
-- new titles: say it once
----------------------------------------------------------------------
function Ti.Stamp()
  local rec = ns.state and ns.state.members[ns.recordGuid]
  if not rec or ns.alt then return end
  local c = Context(UI.Members())
  local tt, changed = {}, false
  for k, v in pairs(type(rec.tt) == "table" and rec.tt or {}) do tt[k] = v end
  for _, t in ipairs(Ti.LIST) do
    if t.kind == "check" then
      local ok, yes = pcall(t.check, rec, c)
      if ok and yes and not tt[t.id] then tt[t.id] = U.Now() changed = true end
      -- lost it (a vice no more, back under the cap...): when it comes back, it counts from then
      if ok and not yes and tt[t.id] and (t.id == "immortale" or t.id == "furbetto" or t.id == "braccio" or t.id == "pischello") then tt[t.id] = nil changed = true end
    end
  end
  if changed then P.UpdateSelf(ns.state, ns.recordGuid, { tt = tt }, "title") end
end

function Ti.CheckNew()
  if not (ns.state and ns.db) or ns.alt then return end
  pcall(Ti.Stamp)
  Refresh(true)
  ns.db.titles = ns.db.titles or {}
  local seen = ns.db.titles[ns.state.code] or {}
  ns.db.titles[ns.state.code] = seen
  for _, t in ipairs(Ti.Mine()) do
    if not seen[t.id] then
      seen[t.id] = true
      U.Say("hai vinto er titolo |cffffd100" .. t.name .. "|r. Lo scegli ner Personaggio, in arto a destra.")
    end
  end
end

----------------------------------------------------------------------
-- chat: "[A Pariolino] ciao" in front of what patto members write
----------------------------------------------------------------------
local CHAT_EVENTS = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
  "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER", "CHAT_MSG_CHANNEL",
  "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }

local function ChatFilter(_, _, msg, author, ...)
  if not ns.state or (ns.db and ns.db.opts.chatTitles == false) then return false end
  if U.IsSecret(msg) or U.IsSecret(author) or type(msg) ~= "string" or type(author) ~= "string" then return false end
  Refresh()
  local t = Lookup(cache.byName, author)
  local verse = cache.verse and Lookup(cache.verse, author)
  if verse then msg = msg .. " |cffff8040" .. verse .. "|r" end
  if not t then
    if verse then return false, msg, author, ... end
    return false
  end
  -- a link: clicking it explains the title
  if t.icon then
    return false, "|T" .. t.icon .. ":0|t |cffff8040|Haddon:ErPatto:title:gogna|h[" .. t.name .. "]|h|r " .. msg, author, ...
  end
  return false, "|cffffd100|Haddon:ErPatto:title:" .. t.id .. "|h[" .. t.name .. "]|h|r " .. msg, author, ...
end

-- the explanation of a title clicked in chat, in the game's own link window
function Ti.ShowLink(id)
  local t = Ti.BY_ID[id]
  local tip = ItemRefTooltip or GameTooltip
  if id == "gogna" and tip then
    if tip.SetOwner then tip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
    tip:ClearLines()
    tip:AddLine("A la gogna", 1, 0.5, 0.25)
    tip:AddLine("Ha perso 'n duello a la gogna, e mo' se porta er pegno.", 1, 1, 1, true)
    tip:AddLine("Er Patto", 0.6, 0.6, 0.6)
    tip:Show()
    return
  end
  if not (t and tip) then return end
  if tip.SetOwner then tip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
  tip:ClearLines()
  tip:AddLine(t.name, 1, 0.82, 0)
  if t.desc then tip:AddLine(t.desc, 1, 1, 1, true) end
  local holders = {}
  for _, m in ipairs(UI.Members()) do
    if cache.earned[m.guid] and cache.earned[m.guid][t.id] then holders[#holders + 1] = tostring(m.name) end
  end
  if #holders > 0 then tip:AddLine("Ce l'ha: " .. table.concat(holders, ", "), 0.6, 0.6, 0.6, true) end
  tip:AddLine("Titolo de Er Patto", 0.6, 0.6, 0.6)
  tip:Show()
end

local lastLink = 0
local function OnLink(link)
  if type(link) ~= "string" then return end
  local id = link:match("^addon:ErPatto:title:([%w_]+)")
  if not id then return end
  local now = GetTime and GetTime() or 0
  if now - lastLink < 0.05 then return end -- the event and the hook can both report one click
  lastLink = now
  Refresh(true)
  Ti.ShowLink(id)
end

function Ti.Start()
  if Ti.started or type(ChatFrame_AddMessageEventFilter) ~= "function" then return end
  Ti.started = true
  for _, e in ipairs(CHAT_EVENTS) do pcall(ChatFrame_AddMessageEventFilter, e, ChatFilter) end
  -- clicks on "addon:" links: the game reports them through EventRegistry; older clients only through SetItemRef
  if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link) OnLink(link) end, Ti)
  end
  if hooksecurefunc and SetItemRef then pcall(hooksecurefunc, "SetItemRef", function(link) OnLink(link) end) end
end

ns.On("Login", function()
  Ti.Start()
  if C_Timer then
    C_Timer.After(10, Ti.CheckNew)
    C_Timer.NewTicker(60, Ti.CheckNew)
  end
end)
ns.On("StateChanged", function() cache.at = -1 end)
ns.On("SelfChanged", function() cache.at = -1 end)
ns.Titles.ChatFilter = ChatFilter
ns.Titles.OnLink = OnLink
