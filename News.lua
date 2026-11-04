-- Er Patto: what happens in the patto, told to everyone.
--   * a line in the chat with a soft ping when someone dings (and for epics, silly deaths, tombole); the big ones
--     also in the raid warning letters
--   * a news list (Baretto tab) built from the changes in everybody's records, kept between sessions
--   * the invite window: someone asks you to join, one click and you're in
-- Changes are found by comparing each record with the last copy seen (also across sessions), so a ding that arrives
-- while you were offline still makes the news, without a banner storm at login.
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H
local N = {}
ns.News = N

local MAX_NEWS = 80

----------------------------------------------------------------------
-- the announcements: what happens to the patto, as the old game told things. One line in the chat (the gold
-- "[Er Patto]" in front, a soft ping), nothing to close; the big ones (a gogna, a tombola, a wipe, the crown) also
-- go across the screen in the raid warning letters, which fade by themselves.
----------------------------------------------------------------------
local function Ping(sound)
  if not (ns.db and ns.db.opts.toastSound and PlaySound) then return end
  local kit = SOUNDKIT and ((sound == "big" and SOUNDKIT.RAID_WARNING) or SOUNDKIT.MAP_PING) or (sound == "big" and 8959 or 3175)
  pcall(PlaySound, kit, "Master")
end

function N.Banner(title, sub, color, sound, big)
  if not (ns.db and ns.db.opts.toasts) then return end
  local c = color or { 1, 0.82, 0 }
  local hex = string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then
    f:AddMessage("|cffffd100[Er Patto]|r " .. hex .. tostring(title) .. "|r" .. (sub and sub ~= "" and (" |cffffffff" .. tostring(sub) .. "|r") or ""))
  end
  if big and RaidNotice_AddMessage and RaidWarningFrame then
    pcall(RaidNotice_AddMessage, RaidWarningFrame, tostring(title), { r = c[1], g = c[2], b = c[3] })
  end
  Ping(big and "big" or sound)
end

----------------------------------------------------------------------
-- the news list
----------------------------------------------------------------------
local function Store()
  if not (ns.db and ns.state) then return nil end
  ns.db.news = type(ns.db.news) == "table" and ns.db.news or {}
  local s = ns.db.news[ns.state.code]
  if type(s) ~= "table" then s = { list = {}, snap = {} } ns.db.news[ns.state.code] = s end
  s.list = s.list or {}
  s.snap = s.snap or {}
  return s
end

function N.Add(text, at)
  local s = Store()
  if not s then return end
  table.insert(s.list, 1, { at = at or U.Now(), t = text })
  while #s.list > MAX_NEWS do table.remove(s.list) end
  ns.Fire("Refresh")
end

function N.List()
  local s = Store()
  return s and s.list or {}
end

----------------------------------------------------------------------
-- what changed in a record
----------------------------------------------------------------------
local QUIPS = { "Daje %s!", "Annamo %s!", "%s nun se ferma più.", "Ammazza oh, %s!", "%s vola.", "Bravo %s, mo' offri da beve." }
local SILLY = {
  cascato = "%s è cascato da 'n dirupo",
  affogato = "%s è affogato",
  pischello = "%s s'è fatto ammazzà da 'n %s",
}

local function Short(rec) return (tostring(rec.name or "?"):match("^(%S+)")) or "?" end
local function Hex(rec) return "|c" .. H.ClassHex(rec.cls) .. Short(rec) .. "|r" end
local function T0(rec, k) return rec.stats and rec.stats.t and rec.stats.t[k] or 0 end

local function Snapshot(rec)
  local s = { lv = rec.lv, le = T0(rec, "le"), em = T0(rec, "em"), rk = T0(rec, "rk"), dg = T0(rec, "dg"), dt = T0(rec, "dt"),
    ed = rec.ed and rec.ed.at, fe = rec.fe and rec.fe.at, nk = {} }
  for _, x in ipairs(rec.nkl or {}) do s.nk[x.n] = x.c end
  if ns.Tombola then
    local sc = ns.Tombola.Score(rec)
    if sc then s.tw, s.tl, s.tf = sc.wk, sc.lines, sc.full and 1 or 0 end
  end
  return s
end

-- wipes: two or more members dying within 20 seconds in the same zone
local function Wipe(rec, quiet)
  local s = Store()
  if not (s and rec.dat) then return end
  s.deaths = s.deaths or {}
  s.wipes = s.wipes or {}
  table.insert(s.deaths, 1, { g = rec.guid, at = rec.dat, z = rec.dz })
  while #s.deaths > 60 do table.remove(s.deaths) end
  local group, seen = {}, {}
  for _, d in ipairs(s.deaths) do
    if math.abs(d.at - rec.dat) <= 20 and (d.z == rec.dz or not d.z or not rec.dz) and not seen[d.g] then
      seen[d.g] = true
      group[#group + 1] = d
    end
  end
  if #group < 2 then return end
  -- one wipe per cluster: keyed by the earliest death in it
  local first = rec.dat
  for _, d in ipairs(group) do first = math.min(first, d.at) end
  local key = tostring(math.floor(first / 30))
  local names = {}
  for _, d in ipairs(group) do
    local m = ns.state.members[d.g]
    names[#names + 1] = m and Short(m) or "?"
  end
  if s.wipes[key] then
    -- a later death joins a wipe already told: just count it
    if not s.wipes[key][rec.guid] then s.wipes[key][rec.guid] = true end
    return
  end
  s.wipes[key] = {}
  for _, d in ipairs(group) do s.wipes[key][d.g] = true end
  s.wipeCount = (s.wipeCount or 0) + 1
  N.Add("|cffff4040Wipe|r" .. (rec.dz and (" a " .. rec.dz) or "") .. ": " .. table.concat(names, ", "))
  if not quiet then N.Banner("WIPE!", table.concat(names, ", ") .. (rec.dz and (" a " .. rec.dz) or ""), { 1, 0.3, 0.3 }, "evento", true) end
end

function N.WipeCount()
  local s = Store()
  return s and s.wipeCount or 0
end

local quietUntil = 0
local function Diff(rec, old, quiet)
  if T0(rec, "dt") > (old.dt or 0) then Wipe(rec, quiet) end
  local you = rec.guid == ns.recordGuid
  local name = Hex(rec)
  local st = ns.state
  -- ding
  if old.lv and rec.lv and rec.lv > old.lv then
    local over
    if rec.team and P.HasSettings(st) then
      local s = M.Status(st.settings, rec.team, U.Now())
      if s and s.started and not s.lifted and rec.lv > s.cap then over = s.cap end
    end
    N.Add(name .. " è salito ar livello |cffffffff" .. rec.lv .. "|r" .. (over and (" |cffff4040(cap " .. over .. ")|r") or ""))
    if not quiet then
      local quip = QUIPS[math.random(#QUIPS)]:format(Short(rec))
      if over then quip = "Ma er cap è " .. over .. "... furbetto!" end
      N.Banner((you and "Sei" or Short(rec) .. " è") .. " ar livello " .. rec.lv .. "!", quip, over and { 1, 0.35, 0.3 } or nil, "ding")
    end
  end
  -- first epic, any epic
  if T0(rec, "le") > (old.le or 0) then
    local first = rec.fe and rec.fe.at ~= old.fe and rec.fe.n
    N.Add(name .. " ha trovato 'n |cffa335eeepico|r" .. (first and (": " .. first) or ""))
    if not quiet then N.Banner(Short(rec) .. " ha trovato 'n epico!", first or "Che culo.", { 0.75, 0.4, 1 }, "evento") end
  end
  -- silly death
  if rec.ed and rec.ed.at ~= old.ed and T0(rec, "em") > (old.em or 0) then
    local fmt = SILLY[rec.ed.k] or "%s è morto male"
    local txt = fmt:format(Short(rec), rec.ed.by or "pischello")
    N.Add(name .. txt:sub(#Short(rec) + 1) .. (rec.ed.z and (" a " .. rec.ed.z) or ""))
    if not quiet then N.Banner(txt .. "!", "Morti ridicole: " .. T0(rec, "em"), { 0.8, 0.8, 0.8 }, "evento") end
  end
  if T0(rec, "rk") > (old.rk or 0) then
    local r = rec.rl and rec.rl[1]
    N.Add(name .. " ha ammazzato 'n raro" .. (r and (": " .. r.n) or ""))
  end
  if T0(rec, "dg") > (old.dg or 0) then N.Add(name .. " ha finito 'n dungeon") end
  for _, x in ipairs(rec.nkl or {}) do
    if x.c > (old.nk and old.nk[x.n] or 0) then N.Add(name .. " ha ammazzato " .. x.n .. (x.c > 1 and (" (" .. x.c .. " vorte)") or "")) end
  end
  -- terno and tombola (same week only)
  if ns.Tombola then
    local sc = ns.Tombola.Score(rec)
    if sc and sc.wk == old.tw then
      if sc.full and (old.tf or 0) == 0 then
        N.Add(name .. " ha fatto |cffffd100TOMBOLA|r!")
        if not quiet then N.Banner(Short(rec) .. " ha fatto TOMBOLA!", "Tutta la cartella de la settimana.", nil, "evento", true) end
      elseif sc.lines > (old.tl or 0) then
        N.Add(name .. " ha fatto terno a la tombola")
        if not quiet then N.Banner(Short(rec) .. " ha fatto terno!", "'Na riga de la tombola completa.", nil, "evento") end
      end
    end
  end
end

function N.Check(rec, quiet)
  local s = Store()
  if not (s and rec and rec.guid) then return end
  local old = s.snap[rec.guid]
  local now = Snapshot(rec)
  s.snap[rec.guid] = now
  if old then Diff(rec, old, quiet or (GetTime and GetTime() or 0) < quietUntil) end
end

ns.On("MemberUpdated", function(rec) N.Check(rec) end)
ns.On("SelfChanged", function(state)
  if state ~= ns.state then return end
  local rec = ns.MyRecord()
  if rec and not ns.alt then N.Check(rec) end
end)

-- everyone once at login: what changed while you were away goes in the list, then one banner says so
local function CatchUp()
  if not ns.state then return end
  local s = Store()
  local before = #s.list
  quietUntil = (GetTime and GetTime() or 0) + 1
  for _, rec in pairs(ns.state.members) do N.Check(rec, true) end
  local n = #s.list - before
  if n > 0 then N.Banner("Mentre eri via", n .. (n == 1 and " novità" or " novità") .. ": le trovi ar Baretto (/patto).", nil, "evento") end
end
ns.On("Login", function() if C_Timer then C_Timer.After(25, CatchUp) end end)
ns.On("PattoChanged", function() if C_Timer then C_Timer.After(3, function() quietUntil = (GetTime and GetTime() or 0) + 10 end) end end)

-- titles: who took which, every half minute (top titles change hands, so this is news only)
local lastHolders
local function TitleNews()
  if not (ns.state and ns.Titles and ns.Titles.Holders) then return end
  local h = ns.Titles.Holders()
  if lastHolders then
    for id, set in pairs(h) do
      for guid in pairs(set) do
        if not (lastHolders[id] and lastHolders[id][guid]) then
          local rec = ns.state.members[guid]
          local t = ns.Titles.BY_ID[id]
          if rec and t then
            N.Add(Hex(rec) .. " mo' è |cffffd100" .. t.name .. "|r")
            if guid == ns.recordGuid then N.Banner("Mo' sei " .. t.name .. "!", t.desc, nil, "evento") end
          end
        end
      end
    end
  end
  lastHolders = h
end
ns.On("Login", function() if C_Timer then C_Timer.After(30, function() TitleNews() C_Timer.NewTicker(30, TitleNews) end) end end)

----------------------------------------------------------------------
-- invites: a small window, one click to join
----------------------------------------------------------------------
local inv
ns.On("Invited", function(code, pattoName, by)
  if ns.state and not ns.alt then
    if ns.state.code == code then return end
    U.Say(tostring(by) .. " te vorrebbe ner patto " .. tostring(pattoName or code) .. ", ma stai già in un artro.")
    return
  end
  if not inv then
    inv = CreateFrame("Frame", "ErPattoInvite", UIParent)
    inv:SetSize(360, 150)
    inv:SetPoint("CENTER", 0, 140)
    inv:SetFrameStrata("DIALOG")
    inv:EnableMouse(true)
    H.Chrome(inv)
    inv.title = H.DialogHeader(inv, "Invito ner patto", 260)
    inv.text = H.Text(inv, "GameFontHighlight", "", 320, "CENTER")
    inv.text:SetPoint("TOP", 0, -36)
    inv.yes = H.Btn(inv, "Entra", 110, function()
      inv:Hide()
      local ok, err = ns.JoinPatto(inv.code)
      if not ok then U.Say(err or "nun so' riuscito a entrà.") return end
      UI.Show("gruppi")
    end)
    inv.yes:SetPoint("BOTTOMRIGHT", inv, "BOTTOM", -6, 18)
    inv.no = H.Btn(inv, "No grazie", 110, function() inv:Hide() end)
    inv.no:SetPoint("BOTTOMLEFT", inv, "BOTTOM", 6, 18)
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoInvite") end
  end
  inv.code = code
  inv.text:SetText("|cffffffff" .. tostring(by) .. "|r te invita ner patto\n|cffffd100" .. tostring(pattoName or code) .. "|r")
  inv:Show()
  Ping("big")
end)

-- right click on a player: "Invita ner patto" (clients with the new menu system)
local function AddMenuEntry()
  if not (Menu and Menu.ModifyMenu) then return end
  for _, tag in ipairs({ "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_TARGET", "MENU_UNIT_CHAT_ROSTER" }) do
    pcall(Menu.ModifyMenu, tag, function(owner, root, data)
      if not (ns.state and not ns.alt and data and data.name) then return end
      local name = data.name
      if data.server and data.server ~= "" then name = name .. "-" .. data.server end
      if ns.state then
        for _, m in pairs(ns.state.members) do if m.name == data.name then return end end
      end
      if root.CreateDivider then root:CreateDivider() end
      root:CreateButton("Invita ner patto", function() ns.InviteFriend(name) end)
    end)
  end
end
ns.On("Login", AddMenuEntry)
