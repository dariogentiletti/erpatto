-- Er Patto: what happens in the patto, told to everyone.
--   * a line in the chat with a soft ping when someone dings (and for epics, silly deaths, tombole); the big ones
--     also in a box on screen, like the duel's and the death's
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
-- in a box on screen (N.Annuncio), which goes by itself.
----------------------------------------------------------------------
local function Ping(sound)
  if not (ns.db and ns.db.opts.toastSound and PlaySound) then return end
  -- a death: the game's soft falling "quest failed" note, heard in play only when a quest fails
  if sound == "rip" then
    pcall(PlaySound, SOUNDKIT and SOUNDKIT.IG_QUEST_FAILED or 847, "Master")
    return
  end
  -- a file of our own (Media)
  if type(sound) == "string" and sound:find("^Interface") then
    if PlaySoundFile then pcall(PlaySoundFile, sound, "Master") end
    return
  end
  local kit = SOUNDKIT and ((sound == "big" and SOUNDKIT.RAID_WARNING) or SOUNDKIT.MAP_PING) or (sound == "big" and 8959 or 3175)
  pcall(PlaySound, kit, "Master")
end

-- big: true, or { icon = texture, head = plate text } for the box on screen
function N.Banner(title, sub, color, sound, big)
  if not (ns.db and ns.db.opts.toasts) or ns.alt then return end
  local c = color or { 1, 0.82, 0 }
  local hex = string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
  local f = DEFAULT_CHAT_FRAME
  if f and f.AddMessage then
    f:AddMessage("|cffffd100[Er Patto]|r " .. hex .. tostring(title) .. "|r" .. (sub and sub ~= "" and (" |cffffffff" .. tostring(sub) .. "|r") or ""))
  end
  if big then
    local o = type(big) == "table" and big or {}
    N.Annuncio({ head = o.head, title = title, sub = sub, color = c, icon = o.icon, secs = o.secs })
  end
  Ping(big and "big" or sound)
end

----------------------------------------------------------------------
-- the announcements on screen: never letters across the screen (the raid warning, the red error line), always
-- a box like the duel's and the death's: the dialog border, the plate with what it is, an icon, the title and a
-- line or two. In the middle, under the HUD; it goes by itself; one after the other, never on top of each other.
-- o = { head, title, sub, icon, color = { r, g, b }, secs, force (shown even with the announcements off) }
-- Cost: one frame, built the first time; a timer while one is up.
----------------------------------------------------------------------
N.ANN_SECONDS = 7
N.Seen = {}            -- the last ones shown (title, sub), for who wants to look back
local annBox, annQueue = nil, {}
local ShowAnn
local function NextAnn()
  table.remove(annQueue, 1)
  if annQueue[1] then ShowAnn(annQueue[1]) elseif annBox then annBox:Hide() end
end
local function BuildAnn()
  local f = CreateFrame("Frame", "ErPattoAnnuncio", UIParent, "BackdropTemplate")
  f:SetSize(340, 90)
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  H.Chrome(f)
  f.head = H.DialogHeader(f, "Er Patto", 220)
  local x = H.CloseX(f)
  if x and x.SetScript then x:SetScript("OnClick", function() f.token = nil NextAnn() end) end
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(36, 36)
  f.icon:SetPoint("TOPLEFT", 18, -26)
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.title = H.Text(f, "GameFontNormal", "", 260, "LEFT")
  f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, -1)
  f.sub = H.Text(f, "GameFontHighlightSmall", "", 260, "LEFT")
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
  if f.sub.SetWordWrap then f.sub:SetWordWrap(true) end
  annBox = f
  return f
end
ShowAnn = function(o)
  local f = annBox or BuildAnn()
  local c = o.color or { 1, 0.82, 0 }
  f.head:SetText(o.head or "Er Patto")
  f.icon:SetTexture(o.icon or "Interface\\Icons\\INV_Misc_Note_01")
  f.title:SetText(string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255)) .. tostring(o.title or "") .. "|r")
  f.sub:SetText(o.sub or "")
  -- as tall as its lines (the small font wraps at ~48 letters in 260 px)
  local lines = 0
  for part in tostring(o.sub or ""):gmatch("[^\n]+") do lines = lines + math.max(1, math.ceil(#part / 48)) end
  local sh = f.sub.GetStringHeight and tonumber(f.sub:GetStringHeight()) or 0
  local th = f.title.GetStringHeight and tonumber(f.title:GetStringHeight()) or 0
  f:SetHeight(math.max(84, 26 + math.max(th, 14) + 4 + math.max(sh, lines * 12) + 20))
  N.PlaceTop(f, 90)
  f:Show()
  local token = {}
  f.token = token
  if C_Timer then C_Timer.After(o.secs or N.ANN_SECONDS, function() if f.token == token then NextAnn() end end) end
end
function N.Annuncio(o)
  if type(o) ~= "table" or ns.alt then return end
  if not o.force and not (ns.db and ns.db.opts.toasts) then return end
  table.insert(N.Seen, 1, { title = tostring(o.title or ""), sub = tostring(o.sub or ""), head = o.head })
  while #N.Seen > 20 do table.remove(N.Seen) end
  -- the same one twice in a row (two records saying it) once
  local last = annQueue[#annQueue]
  if last and last.title == o.title and last.sub == o.sub then return end
  if #annQueue >= 4 then table.remove(annQueue, 2) end
  annQueue[#annQueue + 1] = o
  if #annQueue == 1 then ShowAnn(o) end
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

-- the same line twice within half an hour is said once (records arriving late, a title going back and forth)
function N.Add(text, at)
  local s = Store()
  if not s then return end
  local now = at or U.Now()
  for i = 1, math.min(12, #s.list) do
    local x = s.list[i]
    if x.t == text and math.abs(now - (x.at or 0)) < 1800 then return false end
  end
  table.insert(s.list, 1, { at = now, t = text })
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

local function Short(rec) return U.Short(rec and rec.name) end
local function Hex(rec) return "|c" .. H.ClassHex(rec.cls) .. Short(rec) .. "|r" end
local function T0(rec, k) return rec.stats and rec.stats.t and rec.stats.t[k] or 0 end

local function Snapshot(rec)
  local s = { lv = rec.lv, le = T0(rec, "le"), em = T0(rec, "em"), rk = T0(rec, "rk"), dg = T0(rec, "dg"), dt = T0(rec, "dt"),
    ed = rec.ed and rec.ed.at, fe = rec.fe and rec.fe.at, lr = rec.lr and rec.lr.at, wp = rec.wp and rec.wp.at, nk = {} }
  for _, x in ipairs(rec.nkl or {}) do s.nk[x.n] = x.c end
  if ns.Tombola then
    local sc = ns.Tombola.Score(rec)
    if sc then s.tw, s.tl, s.tf = sc.wk, sc.lines, sc.full and 1 or 0 end
  end
  return s
end

-- wipes: a member saw his whole group dead (Tracker, rec.wp). Everyone of the group may say it: one wipe per zone
-- within a minute and a half
local function Wipe(rec, old, quiet)
  local w = rec.wp
  if type(w) ~= "table" or not w.at or w.at == old.wp then return end
  local s = Store()
  if not s then return end
  s.wipes = type(s.wipes) == "table" and s.wipes or {}
  for _, x in ipairs(s.wipes) do
    if type(x) == "table" and math.abs((x.at or 0) - w.at) <= 90 and (x.z == w.z or not x.z or not w.z) then return end
  end
  table.insert(s.wipes, 1, { at = w.at, z = w.z })
  while #s.wipes > 20 do table.remove(s.wipes) end
  s.wipeCount = (s.wipeCount or 0) + 1
  local who = w.n or Short(rec)
  N.Add("|cffff4040Wipe|r" .. (w.z and (" a " .. w.z) or "") .. ": " .. who)
  if not quiet and N.Live and N.Live(w.at) then
    N.Banner("WIPE!", "Tutto er gruppo a tera" .. (w.z and (" a " .. w.z) or "") .. ": " .. who .. ".", { 1, 0.3, 0.3 }, "evento",
      { head = "Wipe", icon = "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01" })
  end
end

function N.WipeCount()
  local s = Store()
  return s and s.wipeCount or 0
end

----------------------------------------------------------------------
-- the ding clip: whoever of the patto levels, everyone gets six seconds of Giampy at the disco (frame sheets +
-- the music, as the duel clips), with who and to what level, and the time played the level took
----------------------------------------------------------------------
-- the overlays (ding, duel, bets, the Colosseo): on top, always in the middle of the screen. Under the cap bar
-- when the bar sits up there, taking only its height: a bar dragged to one side never pulls them off the centre
local function Num(x) return type(x) == "number" and x or nil end
function N.PlaceTop(f, fallback)
  if not (f and UIParent) then return end
  f:ClearAllPoints()
  if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end
  local h = UIParent.GetHeight and Num(UIParent:GetHeight()) or 0
  if h <= 0 then h = 768 end
  local y = -(fallback or 80)
  local hud = _G.ErPattoHUD
  local top = hud and hud.IsShown and hud:IsShown() and hud.GetTop and Num(hud:GetTop())
  local bottom = hud and hud.GetBottom and Num(hud:GetBottom())
  if top and bottom then
    local hs = hud.GetEffectiveScale and Num(hud:GetEffectiveScale()) or 1
    local us = UIParent.GetEffectiveScale and Num(UIParent:GetEffectiveScale()) or 1
    local r = (hs > 0 and us > 0) and hs / us or 1
    if top * r > h * 0.6 then y = bottom * r - h - 56 end
  end
  local s = f.GetScale and Num(f:GetScale()) or 1
  f:SetPoint("TOP", UIParent, "TOP", 0, y / ((s and s > 0) and s or 1))
end

N.DING = { sheets = 3, frames = 72, fps = 12, sound = "ding.ogg" }
local dingClip
function N.DingClip(rec)
  if not (rec and rec.lv) or ns.alt or not (ns.db and ns.db.opts.toasts) then return end
  local c = N.DING
  if not dingClip then
    local f = CreateFrame("Frame", "ErPattoDing", UIParent)
    f:SetSize(320, 250)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f.screen = f:CreateTexture(nil, "ARTWORK")
    f.screen:SetSize(320, 180)
    f.screen:SetPoint("TOP", 0, 0)
    f.box = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.box:SetSize(260, 64)
    f.box:SetPoint("TOP", f.screen, "BOTTOM", 0, -4)
    f.box:EnableMouse(true) f.box:RegisterForDrag("LeftButton")
    f.box:SetScript("OnDragStart", function() f:StartMoving() end)
    f.box:SetScript("OnDragStop", function() f:StopMovingOrSizing() if f.SetUserPlaced then pcall(f.SetUserPlaced, f, false) end end)
    H.Chrome(f.box)
    local x = H.CloseX(f.box)
    if x and x.SetScript then x:SetScript("OnClick", function() f:Hide() end) end
    f.title = H.Text(f.box, "GameFontNormal", "", 230, "CENTER")
    f.title:SetPoint("TOP", 0, -16)
    f.sub = H.Text(f.box, "GameFontHighlightSmall", "", 230, "CENTER")
    f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
    f:SetScript("OnUpdate", function(self, el)
      self.t = self.t + (el or 0)
      local i = math.floor(self.t * c.fps)
      if i >= c.frames then
        i = c.frames - 1
        if self.t > c.frames / c.fps + 0.3 then self:Hide() return end
      end
      if i == self.shown then return end
      self.shown = i
      local sheet, k = math.floor(i / 28) + 1, i % 28
      local col, row = k % 4, math.floor(k / 4)
      if sheet ~= self.sheet then
        self.sheet = sheet
        self.screen:SetTexture(H.MEDIA .. "livello\\ding" .. sheet .. ".tga")
      end
      self.screen:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 144 / 1024, (row + 1) * 144 / 1024)
    end)
    f:SetScript("OnHide", function(self) if self.handle and StopSound then pcall(StopSound, self.handle) end self.handle = nil end)
    dingClip = f
  end
  local f = dingClip
  if f.handle and StopSound then pcall(StopSound, f.handle) end
  f.t, f.shown, f.sheet = 0, nil, nil
  local you = rec.guid == ns.recordGuid
  f.title:SetText((you and "Sei salito" or (Hex(rec) .. " è salito")) .. " ar livello |cffffffff" .. rec.lv .. "|r!")
  local took = type(rec.dl) == "table" and rec.dl.lv == rec.lv and rec.dl.s
  f.sub:SetText(took and ("In " .. U.Until(took) .. " de gioco") or "")
  -- on top, in the middle of the screen (where the duel clip goes too)
  N.PlaceTop(f)
  f:Show()
  if PlaySoundFile and not (ns.db.opts.sound == false) then
    local ok, _, handle = pcall(PlaySoundFile, H.MEDIA .. "livello\\" .. c.sound, "Master")
    f.handle = ok and handle or nil
  end
end

-- a death on everyone's screen, up top like a ding: the dialog box with a skull, how, where, the last words and
-- how many in all; it goes by itself after a few seconds (or with its X), and can be dragged like the ding's
local ripBox
N.RIP_SECONDS = 8
-- the top of the action bars at the bottom of the screen (main bar, the two over it, pet and stance bars)
local BARS = { "MainMenuBar", "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "PetActionBar", "StanceBar",
  "StanceBarFrame", "PetActionBarFrame", "PossessBarFrame", "MainMenuBarArtFrame" }
function N.BarsTop()
  local h = UIParent.GetHeight and tonumber(UIParent:GetHeight()) or 768
  local top = 0
  for _, name in ipairs(BARS) do
    local b = _G[name]
    if b and b.IsShown and b.GetTop then
      local ok, shown = pcall(b.IsVisible or b.IsShown, b)
      local ok2, t = pcall(b.GetTop, b)
      t = ok2 and tonumber(t) or nil
      -- only bars down at the bottom (a bar moved up the screen isn't one to clear)
      if ok and shown and t and t < h * 0.4 and t > top then top = t end
    end
  end
  return top > 0 and top or 140
end
function N.DeathOverlay(rec)
  if not rec or ns.alt or not (ns.db and ns.db.opts.toasts) then return end
  if not ripBox then
    local f = CreateFrame("Frame", "ErPattoRip", UIParent, "BackdropTemplate")
    f:SetSize(300, 70)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true) f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end end)
    H.Chrome(f)
    local x = H.CloseX(f)
    if x and x.SetScript then x:SetScript("OnClick", function() f:Hide() end) end
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(32, 32)
    f.icon:SetPoint("TOPLEFT", 16, -16)
    f.icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    f.title = H.Text(f, "GameFontNormal", "", 230, "LEFT")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, 0)
    f.sub = H.Text(f, "GameFontHighlightSmall", "", 230, "LEFT")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    if f.sub.SetWordWrap then f.sub:SetWordWrap(true) end
    ripBox = f
  end
  local f = ripBox
  local you = rec.guid == ns.recordGuid
  local g = rec.lr or {}
  f.title:SetText("R.I.P. " .. (you and "tu" or Hex(rec)))
  f.sub:SetText(N.DeathHow(rec) .. "\n" .. N.DeathSub(rec))
  -- as tall as its lines (each line of the small font ~12 px; a long one wraps at ~52 letters)
  local lines = 0
  for part in (f.sub:GetText() or ""):gmatch("[^\n]+") do lines = lines + math.max(1, math.ceil(#part / 52)) end
  local sh = f.sub.GetStringHeight and tonumber(f.sub:GetStringHeight()) or 0
  f:SetHeight(math.max(64, 16 + 14 + 4 + math.max(sh, lines * 12) + 18))
  -- it goes by itself (a newer death keeps it up for its own time)
  local token = {}
  f.token = token
  if C_Timer then
    C_Timer.After(N.RIP_SECONDS + ((g.w and g.w ~= "") and 3 or 0), function() if f.token == token then f:Hide() end end)
  end
  -- in the middle, down low: just over the action bars (the highest one shown)
  f:ClearAllPoints()
  f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, N.BarsTop() + 16)
  f:Show()
end

-- "livello 12, ammazzato da Lightning Hide a Durotar"
function N.DeathHow(rec)
  local g = rec.lr or {}
  local how = ns.Sfide and ns.Sfide.GraveText and ns.Sfide.GraveText(g) or ""
  if g.k == "pischello" and g.by then how = how:gsub(", ammazzato da ", ", ammazzato da 'n pischello: ") end
  return (how:gsub("^, ", ""))
end

-- "R.I.P. Er Canaro, livello 12, ammazzato da Lightning Hide a Durotar"
function N.DeathLine(rec)
  local g = rec.lr or {}
  local how = ns.Sfide and ns.Sfide.GraveText and ns.Sfide.GraveText(g) or ""
  if g.k == "pischello" and g.by then how = how:gsub(", ammazzato da ", ", ammazzato da 'n pischello: ") end
  local you = rec.guid == ns.recordGuid
  return "R.I.P. " .. (you and "tu" or Hex(rec)) .. "|cffbfbfbf" .. how .. "|r"
end
-- "Urtime parole: "aiuto" (16 morti in tutto, 3 ridicole)"
function N.DeathSub(rec)
  local g = rec.lr or {}
  local dt, em = T0(rec, "dt"), T0(rec, "em")
  local count = "(" .. dt .. (dt == 1 and " morte" or " morti") .. " in tutto" .. (em > 0 and (", " .. em .. (em == 1 and " ridicola" or " ridicole")) or "") .. ")"
  if g.w and g.w ~= "" then return "Urtime parole: \"" .. g.w .. "\"\n" .. count end
  return count
end

local quietUntil = 0
-- live: it happened while I'm playing, not while I was away. With its time: in the last two minutes; without
-- (older versions, or no time kept): not in the first two minutes after I log in, while the records arrive
N.LIVE_FOR = 120
local function Live(at)
  if type(at) == "number" and at > 0 then return U.Now() - at <= N.LIVE_FOR end
  return (GetTime and GetTime() or 0) >= (N.settleUntil or 0)
end
N.Live = Live

local function Diff(rec, old, quiet)
  pcall(Wipe, rec, old, quiet)
  local you = rec.guid == ns.recordGuid
  local name = Hex(rec)
  local st = ns.state
  -- ding
  -- a record just started on a PC jumping several levels at once is its real level arriving, not a ding
  if old.lv and rec.lv and rec.lv > old.lv and not (rec.fresh and rec.lv - old.lv > 1) then
    local over
    if rec.team and P.HasSettings(st) then
      local s = M.Status(st.settings, rec.team, U.Now())
      if s and s.started and not s.lifted and rec.lv > s.cap then over = s.cap end
    end
    N.Add(name .. " è salito ar livello |cffffffff" .. rec.lv .. "|r" .. (over and (" |cffff4040(cap " .. over .. ")|r") or ""))
    -- the clip and the banner only for a ding just now; one from while I was away goes in the list only
    local dingAt = type(rec.dl) == "table" and rec.dl.lv == rec.lv and rec.dl.at or nil
    if not quiet and Live(dingAt) then
      local quip = QUIPS[math.random(#QUIPS)]:format(Short(rec))
      if over then quip = "Ma er cap è " .. over .. "... furbetto!" end
      N.Banner((you and "Sei" or Short(rec) .. " è") .. " ar livello " .. rec.lv .. "!", quip, over and { 1, 0.35, 0.3 } or nil, "ding")
      pcall(N.DingClip, rec)
    end
  end
  -- first epic, any epic
  if T0(rec, "le") > (old.le or 0) then
    local first = rec.fe and rec.fe.at ~= old.fe and rec.fe.n
    N.Add(name .. " ha trovato 'n |cffa335eeepico|r" .. (first and (": " .. first) or ""))
    if not quiet and Live(first and rec.fe.at or nil) then N.Banner(Short(rec) .. " ha trovato 'n epico!", first or "Che culo.", { 0.75, 0.4, 1 }, "evento") end
  end
  -- silly death: in the list (the chat line is the death's own, below)
  local silly = rec.ed and rec.ed.at ~= old.ed and T0(rec, "em") > (old.em or 0)
  if silly then
    local fmt = SILLY[rec.ed.k] or "%s è morto male"
    local txt = fmt:format(Short(rec), rec.ed.by or "pischello")
    N.Add(name .. txt:sub(#Short(rec) + 1) .. (rec.ed.z and (" a " .. rec.ed.z) or ""))
  end
  -- a death, as it happens: one line for everyone, how, where, the last words, how many in all
  if type(rec.lr) == "table" and rec.lr.at and rec.lr.at ~= old.lr and not quiet and Live(rec.lr.at) then
    N.DeathOverlay(rec)
    Ping("rip")
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
        if not quiet and Live(nil) then N.Banner(Short(rec) .. " ha fatto TOMBOLA!", "Tutta la cartella de la settimana.", nil, "evento", { head = "Tombola", icon = "Interface\\Icons\\INV_Misc_Ticket_Darkmoon_01" }) end
      elseif sc.lines > (old.tl or 0) then
        N.Add(name .. " ha fatto terno a la tombola")
        if not quiet and Live(nil) then N.Banner(Short(rec) .. " ha fatto terno!", "'Na riga de la tombola completa.", nil, "evento") end
      end
    end
  end
end

function N.Check(rec, quiet)
  local s = Store()
  if not (s and rec and rec.guid) then return end
  local old = s.snap[rec.guid]
  local now = Snapshot(rec)
  -- a level never goes down: a record started again from nothing (someone coming back in) keeps the one we knew
  if old and old.lv and now.lv and now.lv < old.lv then now.lv = old.lv end
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
-- who was last told to hold each title stays in the saved data: a title only makes news when it really changes hands,
-- not when the records come in after a login and the list settles
local function TitleNews()
  if not (ns.state and ns.Titles and ns.Titles.Holders) then return end
  local h = ns.Titles.Holders()
  local s = Store()
  if s then s.told = type(s.told) == "table" and s.told or {} end
  local settling = (GetTime and GetTime() or 0) < (N.settleUntil or 0)
  if lastHolders then
    for id, set in pairs(h) do
      for guid in pairs(set) do
        local key = id .. ":" .. guid
        local already = s and s.told[key]
        if s then s.told[key] = U.Now() end
        if not (lastHolders[id] and lastHolders[id][guid]) and not already and not settling then
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
ns.On("Login", function()
  -- the first two minutes the records of the others are still arriving (whispered one by one on Forever)
  N.settleUntil = (GetTime and GetTime() or 0) + 120
  if C_Timer then C_Timer.After(30, function() TitleNews() C_Timer.NewTicker(30, TitleNews) end) end
end)

----------------------------------------------------------------------
-- invites: a small window, one click to join
----------------------------------------------------------------------
local inv
ns.On("Invited", function(code, pattoName, by)
  if ns.state and not ns.alt then
    if ns.state.code == code then
      -- still waiting for the data of this very patto: who invited me is the friend to ask
      if not P.HasSettings(ns.state) and ns.C and ns.C.AddSeed then ns.C.AddSeed(by) ns.C.Hello() end
      return
    end
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
      local ok, err = ns.JoinPatto(inv.code, inv.by)
      if not ok then U.Say(err or "nun so' riuscito a entrà.") return end
      UI.Show("gruppi")
    end)
    inv.yes:SetPoint("BOTTOMRIGHT", inv, "BOTTOM", -6, 18)
    inv.no = H.Btn(inv, "No grazie", 110, function() inv:Hide() end)
    inv.no:SetPoint("BOTTOMLEFT", inv, "BOTTOM", 6, 18)
    if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoInvite") end
  end
  inv.code, inv.by = code, by
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
      -- the whole name: from the unit when there is one; else the menu's two parts, which on Forever are
      -- name and surname ("Er" "Nia" -> "Er Nia"), on retail name and realm ("Dario" "Realm" -> "Dario-Realm")
      local name = data.unit and U.FullName(data.unit)
      if not name then
        name = data.name
        if data.server and data.server ~= "" then name = name .. (U.IsForever() and " " or "-") .. data.server end
      end
      if ns.state then
        for _, m in pairs(ns.state.members) do if m.name == name or U.Short(m.name) == U.Short(name) then return end end
      end
      if root.CreateDivider then root:CreateDivider() end
      root:CreateButton("Invita ner patto", function() ns.InviteFriend(name) end)
    end)
  end
end
ns.On("Login", AddMenuEntry)
