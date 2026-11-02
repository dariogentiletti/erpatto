-- Er Patto: what happens in the patto, told to everyone.
--   * a banner in the middle-top of the screen with a sound when someone dings (and for epics, silly deaths, tombole)
--   * a news list (Casa tab) built from the changes in everybody's records, kept between sessions
--   * the invite window: someone asks you to join, one click and you're in
-- Changes are found by comparing each record with the last copy seen (also across sessions), so a ding that arrives
-- while you were offline still makes the news, without a banner storm at login.
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H
local N = {}
ns.News = N

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local FONT = (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
local MAX_NEWS = 80

----------------------------------------------------------------------
-- the banner
----------------------------------------------------------------------
local banner
local queue = {}

local function Gradient(tex, orient, a1, a2)
  tex:SetColorTexture(1, 1, 1, 1)
  local ok = false
  if CreateColor then ok = pcall(tex.SetGradient, tex, orient, CreateColor(0, 0, 0, a1), CreateColor(0, 0, 0, a2)) end
  if not ok and tex.SetGradientAlpha then ok = pcall(tex.SetGradientAlpha, tex, orient, 0, 0, 0, a1, 0, 0, 0, a2) end
  if not ok then tex:SetColorTexture(0, 0, 0, math.max(a1, a2) * 0.8) end
end

local function GoldLine(parent, y)
  local l = parent:CreateTexture(nil, "ARTWORK")
  l:SetColorTexture(1, 0.82, 0.2, 0.8)
  l:SetHeight(1)
  l:SetPoint("LEFT", 60, 0)
  l:SetPoint("RIGHT", -60, 0)
  l:SetPoint("TOP", 0, y)
  return l
end

local function BuildBanner()
  banner = CreateFrame("Button", "ErPattoBanner", UIParent)
  banner:SetSize(640, 92)
  banner:SetPoint("TOP", 0, -150)
  banner:SetFrameStrata("HIGH")
  banner:Hide()
  -- a dark band that fades out at both ends, gold lines above and below: like the vanilla level-up text
  local l = banner:CreateTexture(nil, "BACKGROUND") l:SetPoint("TOPLEFT") l:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", -120, 0)
  Gradient(l, "HORIZONTAL", 0, 0.75)
  local r = banner:CreateTexture(nil, "BACKGROUND") r:SetPoint("TOPRIGHT") r:SetPoint("BOTTOMLEFT", banner, "BOTTOM", 120, 0)
  Gradient(r, "HORIZONTAL", 0.75, 0)
  local m = banner:CreateTexture(nil, "BACKGROUND") m:SetPoint("TOPLEFT", l, "TOPRIGHT") m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  m:SetColorTexture(0, 0, 0, 0.75)
  banner.top = GoldLine(banner, 0)
  banner.bottom = GoldLine(banner, -91)
  banner.title = banner:CreateFontString(nil, "OVERLAY")
  banner.title:SetFont(FONT, 26, "OUTLINE")
  banner.title:SetPoint("TOP", 0, -16)
  banner.title:SetWidth(620)
  banner.sub = banner:CreateFontString(nil, "OVERLAY")
  banner.sub:SetFont(FONT, 15, "OUTLINE")
  banner.sub:SetPoint("TOP", banner.title, "BOTTOM", 0, -8)
  banner.sub:SetWidth(600)
  banner.sub:SetTextColor(1, 1, 1)
  banner:SetScript("OnClick", function(self) self.t = math.max(self.t or 0, 4.4) end)
  banner:SetScript("OnUpdate", function(self, elapsed)
    self.t = (self.t or 0) + (elapsed or 0)
    local t = self.t
    if t < 0.3 then self:SetAlpha(t / 0.3)
    elseif t < 4.4 then self:SetAlpha(1)
    elseif t < 5.0 then self:SetAlpha(1 - (t - 4.4) / 0.6)
    else
      self:Hide()
      if #queue > 0 then N.ShowNext() end
    end
  end)
end

local function PlayEvent(sound)
  if not (ns.db and ns.db.opts.toastSound) then return end
  -- your own file first (Media\ding.ogg, Media\evento.ogg), then the game's level-up fanfare
  if PlaySoundFile then
    local ok, willPlay = pcall(PlaySoundFile, MEDIA .. (sound == "ding" and "ding.ogg" or "evento.ogg"), "Master")
    if ok and willPlay then return end
  end
  if PlaySound then
    local ok, willPlay = pcall(PlaySound, 888, "Master") -- LEVELUP
    if ok and willPlay ~= false then return end
    if SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master") end
  end
end

function N.ShowNext()
  local e = table.remove(queue, 1)
  if not e then return end
  if not banner then BuildBanner() end
  banner.title:SetText(e.title)
  local c = e.color or { 1, 0.82, 0 }
  banner.title:SetTextColor(c[1], c[2], c[3])
  banner.sub:SetText(e.sub or "")
  banner.t = 0
  banner:SetAlpha(0)
  banner:Show()
  PlayEvent(e.sound)
end

function N.Banner(title, sub, color, sound)
  if not (ns.db and ns.db.opts.toasts) then return end
  if #queue >= 5 then return end
  queue[#queue + 1] = { title = title, sub = sub, color = color, sound = sound }
  if not (banner and banner:IsShown()) then N.ShowNext() end
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
  if not quiet then N.Banner("WIPE!", table.concat(names, ", ") .. (rec.dz and (" a " .. rec.dz) or ""), { 1, 0.3, 0.3 }, "evento") end
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
        if not quiet then N.Banner(Short(rec) .. " ha fatto TOMBOLA!", "Tutta la cartella de la settimana.", nil, "evento") end
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
  if n > 0 then N.Banner("Mentre eri via", n .. (n == 1 and " novità" or " novità") .. ": le trovi in Casa (/patto).", nil, "evento") end
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
    inv.title = H.Text(inv, "GameFontNormal", "Invito ner patto", 320, "CENTER")
    inv.title:SetPoint("TOP", 0, -16)
    inv.text = H.Text(inv, "GameFontHighlight", "", 320, "CENTER")
    inv.text:SetPoint("TOP", 0, -42)
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
  PlayEvent("evento")
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
