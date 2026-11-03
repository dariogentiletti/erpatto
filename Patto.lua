-- Er Patto: the shared state of one patto.
-- Rules: the code only lets you in; capo and vice set the pace; every member picks and changes their own team.
-- Every shared piece carries a version, so the newest wins the same way on every client.
local ADDON, ns = ...
local U = ns.U
local P = {}
ns.P = P

P.MAX_TEAMS = 4
P.MAX_MEMBERS = 40
P.MAX_SWITCHES = 30

----------------------------------------------------------------------
-- codes
----------------------------------------------------------------------
function P.NewCode()
  return U.RandomCode(5)
end

-- Accepts "k7q2m", "K7Q 2M", "PATTO-K7Q2M"; also the 8-character codes of the first test versions.
-- Returns the canonical code or nil.
function P.NormalizeCode(text)
  local s = string.upper(tostring(text or "")):gsub("[%s%-]", "")
  if #s > 5 then s = s:gsub("^PATTO", "") end
  if #s ~= 5 and #s ~= 8 then return nil end
  for i = 1, #s do
    if not string.find(U.ALPHABET, s:sub(i, i), 1, true) then return nil end
  end
  if #s == 8 then return "PATTO-" .. s:sub(1, 4) .. "-" .. s:sub(5, 8) end
  return s
end

function P.ChannelName(code)
  return "ep" .. string.lower((code:gsub("PATTO%-", ""):gsub("%-", "")))
end

function P.ChannelPassword(code)
  local h = U.Hash("erpatto:" .. code)
  local out = {}
  for i = 1, 6 do
    local r = h % #U.ALPHABET
    out[i] = U.ALPHABET:sub(r + 1, r + 1)
    h = math.floor(h / #U.ALPHABET) + i * 7919
  end
  return table.concat(out)
end

----------------------------------------------------------------------
-- validation of anything that arrives from other players
----------------------------------------------------------------------
local function Str(v, max)
  if type(v) ~= "string" then return nil end
  v = v:gsub("[%c|]", "")
  if #v == 0 then return nil end
  return v:sub(1, max or 40)
end

local function Num(v, lo, hi)
  if type(v) ~= "number" or v ~= v then return nil end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function CleanRows(rows, fields)
  local out = {}
  if type(rows) ~= "table" then return out end
  for _, r in pairs(rows) do
    if type(r) == "table" and Num(r.from, 1, 260) then
      local c = { from = math.floor(r.from) }
      for f, range in pairs(fields) do
        local n = Num(r[f], range[1], range[2])
        if n then c[f] = n end
      end
      out[#out + 1] = c
      if #out >= 60 then break end
    end
  end
  table.sort(out, function(a, b) return a.from < b.from end)
  return out
end

function P.CleanSettings(s)
  if type(s) ~= "table" then return nil end
  local c = {
    v = Num(s.v, 0, 1e9), at = Num(s.at, 0, 4e9), by = Str(s.by, 60),
    name = Str(s.name, 40) or "Er Patto", start = Num(s.start, 0, 4e9),
    noAh = s.noAh == true or nil, -- true: auction sales don't count as gold earned
    ann = (type(s.ann) == "table" and Str(s.ann.t, 250) and Num(s.ann.at, 0, 4e9)) and { t = Str(s.ann.t, 250), at = Num(s.ann.at, 0, 4e9), by = Str(s.ann.by, 40) } or nil,
    calib = CleanRows(s.calib, { h20 = { 4, 100 }, h60 = { 40, 400 } }),
    teams = {},
  }
  if not (c.v and c.at and c.by and c.start) then return nil end
  if type(s.teams) == "table" then
    for i = 1, P.MAX_TEAMS do
      local t = s.teams[i]
      if type(t) == "table" and Str(t.id, 8) then
        c.teams[#c.teams + 1] = { id = Str(t.id, 8), name = Str(t.name, 30) or ("Squadra " .. i),
          pace = CleanRows(t.pace, { hours = { 1, 100 }, level = { 1, 60 } }) }
      end
    end
  end
  if #c.teams == 0 then return nil end
  return c
end

local function CleanAdmins(a)
  if type(a) ~= "table" then return nil end
  local c = { v = Num(a.v, 0, 1e9), at = Num(a.at, 0, 4e9), by = Str(a.by, 60), capo = Str(a.capo, 60), vice = {} }
  if not (c.v and c.at and c.by and c.capo) then return nil end
  if type(a.vice) == "table" then
    local n = 0
    for g, on in pairs(a.vice) do
      if Str(g, 60) and on == true and n < 10 then c.vice[g] = true n = n + 1 end
    end
  end
  return c
end

local function CleanBans(b)
  if type(b) ~= "table" then return nil end
  local c = { v = Num(b.v, 0, 1e9), at = Num(b.at, 0, 4e9), by = Str(b.by, 60), list = {} }
  if not (c.v and c.at and c.by) then return nil end
  if type(b.list) == "table" then
    local n = 0
    for g, on in pairs(b.list) do
      if Str(g, 60) and on == true and n < 50 then c.list[g] = true n = n + 1 end
    end
  end
  return c
end

-- q quests, dg dungeons, dw/dl duels won/lost, bw/bl battlegrounds won/lost, ding levels gained, g copper earned,
-- dt deaths, pt seconds played, rk rares killed, hk honorable kills, hn honor gained,
-- fi fish caught, he herbs, mi ore and stone, sk leather, lb blue items looted, le epic items looted,
-- em silly deaths (falling, drowning, a much lower mob), nk famous mobs and bosses killed, tr yards travelled,
-- fl flights taken, hs hearthstones used
local STAT_KEYS = { "q", "dg", "dw", "dl", "bw", "bl", "ding", "g", "dt", "pt", "rk", "hk", "hn",
  "fi", "he", "mi", "sk", "lb", "le", "em", "nk", "tr", "fl", "hs" }
local STAT_MAX = { g = 1e11, pt = 1e8, hn = 1e8, tr = 1e9 }

-- { [string] = count }, at most `max` entries
local function CleanCounts(t, max)
  local out, n = {}, 0
  if type(t) ~= "table" then return out end
  for k, v in pairs(t) do
    if n >= max then break end
    local key, num = Str(k, 40), Num(v, 0, 1e6)
    if key and num then out[key] = math.floor(num) n = n + 1 end
  end
  return out
end

local function CleanStats(t)
  local c = {}
  if type(t) ~= "table" then return c end
  for _, k in ipairs(STAT_KEYS) do
    local n = Num(t[k], 0, STAT_MAX[k] or 1e6)
    if n then c[k] = math.floor(n) end
  end
  return c
end
P.STAT_KEYS = STAT_KEYS

function P.CleanMember(r)
  if type(r) ~= "table" then return nil end
  local c = {
    guid = Str(r.guid, 60), name = Str(r.name, 40), team = Str(r.team, 8), tat = Num(r.tat, 0, 4e9),
    up = Num(r.up, 0, 4e9), lv = Num(r.lv, 0, 60), xp = Num(r.xp, 0, 1e7), xpm = Num(r.xpm, 0, 1e7),
    rest = Num(r.rest, 0, 1e7), zone = Str(r.zone, 40), cls = Str(r.cls, 20), ver = Str(r.ver, 12), ld = Str(r.ld, 40),
    il = Num(r.il, 0, 2000), race = Str(r.race, 20), rid = Num(r.rid, 1, 200), sex = Num(r.sex, 1, 3),
    eq = type(r.eq) == "string" and #r.eq <= 600 and r.eq:match("^[%d%./%-]*$") and r.eq or nil,
    stats = { t = CleanStats(r.stats and r.stats.t), w = {} }, h2h = {}, alts = {},
    ti = Str(r.ti, 24),
    zq = CleanCounts(r.zq, 6), zqw = CleanCounts(r.zqw, 6), dgw = CleanCounts(r.dgw, 8), wk = Num(r.wk, 0, 260), dgl = CleanCounts(r.dgl, 8), lq = {}, pr = {}, ms = {}, rl = {},
    nkl = {},
  }
  if not (c.guid and c.name and c.up) then return nil end
  -- the fun boards: nemesis, famous mobs killed, first epic, last silly death, points, predictions
  if type(r.ne) == "table" and Str(r.ne.n, 40) then c.ne = { n = Str(r.ne.n, 40), c = math.floor(Num(r.ne.c, 0, 1e5) or 0) } end
  if type(r.nkl) == "table" then
    for i = 1, 5 do
      local x = r.nkl[i]
      if type(x) == "table" and Str(x.n, 40) then c.nkl[#c.nkl + 1] = { n = Str(x.n, 40), c = math.floor(Num(x.c, 0, 1e5) or 0) } end
    end
  end
  if type(r.fe) == "table" and Num(r.fe.at, 0, 4e9) then c.fe = { at = Num(r.fe.at, 0, 4e9), n = Str(r.fe.n, 50) } end
  if type(r.ed) == "table" and Str(r.ed.k, 12) then
    c.ed = { k = Str(r.ed.k, 12), at = Num(r.ed.at, 0, 4e9), z = Str(r.ed.z, 40), by = Str(r.ed.by, 40) }
  end
  if type(r.pts) == "table" then
    c.pts = { t = math.floor(Num(r.pts.t, 0, 1e7) or 0), w = math.floor(Num(r.pts.w, 0, 1e4) or 0), wk = Num(r.pts.wk, 0, 260) }
  end
  -- bets: this week's (vt) and last week's (vp): pick and stake per question
  local function Bets(v)
    if type(v) ~= "table" or not Num(v.wk, 0, 260) then return nil end
    local out = { wk = Num(v.wk, 0, 260) }
    for _, k in ipairs({ "a", "b", "c" }) do
      out[k] = Str(v[k], 60)
      out["s" .. k] = out[k] and math.floor(Num(v["s" .. k], 0, 1e5) or 0) or nil
      out["q" .. k] = out[k] and Num(v["q" .. k], 10, 1000) and math.floor(Num(v["q" .. k], 10, 1000)) or nil -- the odds taken, x10
    end
    return out
  end
  c.vt, c.vp = Bets(r.vt), Bets(r.vp)
  -- le sfide: the ones I threw (sf), my answers to the ones thrown at me (sk), the bounties I put (tg), my last
  -- duels with patto members (dd: opponent guid, won or not, when)
  local function List(t, max, fn)
    local out = {}
    if type(t) ~= "table" then return out end
    for i = 1, max do
      local x = t[i]
      if type(x) == "table" then local y = fn(x) if y then out[#out + 1] = y end end
    end
    return out
  end
  -- free text that shows in chat (nicknames, the verse): plain, no escapes
  local function Plain(t, n)
    t = Str(t, n)
    if not t then return nil end
    t = t:gsub("|", ""):gsub("[%c]", "")
    return t ~= "" and t or nil
  end
  local KINDS = { d = true, l = true, s = true, q = true }
  c.sf = List(r.sf, 6, function(x)
    local k = Str(x.k, 1)
    if not (Str(x.id, 40) and Str(x.to, 60) and KINDS[k]) then return nil end
    return { id = Str(x.id, 40), to = Str(x.to, 60), k = k, n = Num(x.n, 2, 60), s = math.floor(Num(x.s, 0, 1e5) or 0),
      p = math.floor(Num(x.p, 0, 4) or 0), t = Plain(x.t, 20), e = math.floor(Num(x.e, 0, 6) or 0),
      st = Str(x.st, 3), w = Str(x.w, 1), m = Num(x.m, 0, 1) and math.floor(Num(x.m, 0, 1)) or nil, at = Num(x.at, 0, 4e9) }
  end)
  c.sk = List(r.sk, 10, function(x)
    if not Str(x.id, 40) then return nil end
    return { id = Str(x.id, 40), a = (Num(x.a, 0, 1) == 1) and 1 or 0, at = Num(x.at, 0, 4e9),
      e = Num(x.e, 0, 4e9), sa = Num(x.sa, 0, 1e9), sb = Num(x.sb, 0, 1e9) }
  end)
  c.tg = List(r.tg, 4, function(x)
    if not (Str(x.id, 40) and Str(x.on, 60)) then return nil end
    return { id = Str(x.id, 40), on = Str(x.on, 60), s = math.floor(Num(x.s, 0, 1e5) or 0), g = math.floor(Num(x.g, 0, 8) or 0), at = Num(x.at, 0, 4e9) }
  end)
  -- gufate: piotte bet that someone dies in the next five minutes
  c.gf = List(r.gf, 4, function(x)
    if not (Str(x.id, 40) and Str(x.on, 60) and Num(x.at, 0, 4e9)) then return nil end
    return { id = Str(x.id, 40), on = Str(x.on, 60), s = math.floor(Num(x.s, 0, 1e5) or 0), at = Num(x.at, 0, 4e9) }
  end)
  -- the graveyard: my last deaths with who, where, the level and my last words
  c.rip = List(r.rip, 10, function(x)
    if not Num(x.at, 0, 4e9) then return nil end
    return { at = Num(x.at, 0, 4e9), lv = Num(x.lv, 0, 60), by = Plain(x.by, 40), z = Str(x.z, 40), w = Plain(x.w, 80), k = Str(x.k, 12) }
  end)
  c.dd = List(r.dd, 8, function(x)
    if not (Str(x.o, 60) and Num(x.at, 0, 4e9)) then return nil end
    return { o = Str(x.o, 60), w = (Num(x.w, 0, 1) == 1) and 1 or 0, at = Num(x.at, 0, 4e9) }
  end)
  if type(r.lq) == "table" then
    for i = 1, 3 do
      local q = r.lq[i]
      if type(q) == "table" and Str(q.t, 40) then
        c.lq[#c.lq + 1] = { t = Str(q.t, 40), z = Str(q.z, 40), at = Num(q.at, 0, 4e9) }
      end
    end
  end
  if type(r.rl) == "table" then
    for i = 1, 5 do
      local x = r.rl[i]
      if type(x) == "table" and Str(x.n, 32) then c.rl[#c.rl + 1] = { n = Str(x.n, 32), z = Str(x.z, 40), at = Num(x.at, 0, 4e9) } end
    end
  end
  if type(r.pr) == "table" then
    for i = 1, 6 do
      local p = r.pr[i]
      if type(p) == "table" and Str(p.n, 30) then
        c.pr[#c.pr + 1] = { n = Str(p.n, 30), l = Num(p.l, 0, 1000) or 0, m = Num(p.m, 0, 1000) or 0 }
      end
    end
  end
  if type(r.ms) == "table" then
    for lv = 10, 60, 10 do
      local at = Num(r.ms[lv], 0, 4e9)
      if at then c.ms[lv] = at end
    end
  end
  if type(r.mp) == "table" then
    c.mp = {}
    for lv = 10, 60, 10 do
      local sec = Num(r.mp[lv], 0, 1e8)
      if sec then c.mp[lv] = math.floor(sec) end
    end
  end
  c.dat, c.dz = Num(r.dat, 0, 4e9), Str(r.dz, 40)
  if type(r.stats) == "table" and type(r.stats.w) == "table" then
    -- only the latest two weeks travel
    local newest = 0
    for wk in pairs(r.stats.w) do if Num(wk, 0, 260) and wk > newest then newest = wk end end
    for wk, st in pairs(r.stats.w) do
      if Num(wk, 0, 260) and wk >= newest - 1 then c.stats.w[math.floor(wk)] = CleanStats(st) end
    end
  end
  if type(r.h2h) == "table" then
    local n = 0
    for name, rec in pairs(r.h2h) do
      if Str(name, 40) and type(rec) == "table" and n < 30 then
        c.h2h[Str(name, 40)] = { w = math.floor(Num(rec.w, 0, 1e5) or 0), l = math.floor(Num(rec.l, 0, 1e5) or 0) }
        n = n + 1
      end
    end
  end
  if type(r.alts) == "table" then
    for i = 1, 6 do
      local a = r.alts[i]
      if type(a) == "table" and Str(a.name, 40) then
        c.alts[#c.alts + 1] = { name = Str(a.name, 40), lv = Num(a.lv, 1, 60) or 1, cls = Str(a.cls, 20) }
      end
    end
  end
  return c
end

----------------------------------------------------------------------
-- creating and joining
----------------------------------------------------------------------
function P.NewState(code)
  return { code = code, settings = { v = 0 }, admins = { v = 0 }, bans = { v = 0, list = {} }, members = {}, switches = {}, joinedAt = U.Now() }
end

local function NewMember(guid, name)
  return { guid = guid, name = name, up = U.Now(), lv = 1, stats = { t = {}, w = {} }, h2h = {}, alts = {}, ver = ns.VERSION }
end

-- opts: name, start (epoch), h20, h60, teams = { {name=, hours=}, ... }, guid, playerName, teamIndex
function P.Create(opts)
  local now = U.Now()
  local state = P.NewState(P.NewCode())
  local teams = {}
  for i, t in ipairs(opts.teams) do
    if i > P.MAX_TEAMS then break end
    teams[i] = { id = "t" .. i, name = t.name, pace = { { from = 1, hours = t.hours } } }
  end
  state.settings = { v = 1, at = now, by = opts.guid, name = opts.name, start = opts.start,
    calib = { { from = 1, h20 = opts.h20 or 25, h60 = opts.h60 or 190 } }, teams = teams }
  state.admins = { v = 1, at = now, by = opts.guid, capo = opts.guid, vice = {} }
  state.bans = { v = 1, at = now, by = opts.guid, list = {} }
  local me = NewMember(opts.guid, opts.playerName)
  me.team = opts.teamIndex and teams[opts.teamIndex] and teams[opts.teamIndex].id or nil
  me.tat = now
  state.members[opts.guid] = me
  return state
end

function P.Join(code, guid, playerName)
  local state = P.NewState(code)
  state.members[guid] = NewMember(guid, playerName)
  return state
end

-- adds this character to a patto already known on this account (e.g. an alt becoming a member)
function P.AddMember(state, guid, playerName)
  if not state.members[guid] then state.members[guid] = NewMember(guid, playerName) end
  return state.members[guid]
end

function P.HasSettings(state)
  return state and state.settings and (state.settings.v or 0) > 0
end

----------------------------------------------------------------------
-- permissions
----------------------------------------------------------------------
function P.IsCapo(state, guid)
  return state.admins and state.admins.capo == guid
end

function P.IsAdmin(state, guid)
  if not state.admins then return false end
  return state.admins.capo == guid or (state.admins.vice and state.admins.vice[guid]) or false
end

function P.IsBanned(state, guid)
  return state.bans and state.bans.list and state.bans.list[guid] or false
end

----------------------------------------------------------------------
-- local edits
----------------------------------------------------------------------
function P.EditSettings(state, me, mutate)
  if not P.IsAdmin(state, me) then return false, "nun c'hai er permesso" end
  local new = U.Copy(state.settings)
  mutate(new)
  new.v = (state.settings.v or 0) + 1
  new.at = U.Now()
  new.by = me
  local clean = P.CleanSettings(new)
  if not clean then return false, "impostazioni nun valide" end
  state.settings = clean
  ns.Fire("SettingsChanged", state)
  return true
end

-- Changes that count from next week (or from week 1 before the start).
function P.FirstEditableWeek(state, now)
  local wk = ns.M.WeekIndex(state.settings, now or U.Now())
  return math.max(1, wk + 1)
end

function P.SetPace(state, me, teamId, hours, realLevel)
  local from = P.FirstEditableWeek(state)
  return P.EditSettings(state, me, function(s)
    for _, t in ipairs(s.teams) do
      if t.id == teamId then
        local kept = {}
        for _, r in ipairs(t.pace) do if r.from < from then kept[#kept + 1] = r end end
        kept[#kept + 1] = { from = from, hours = hours, level = realLevel }
        t.pace = kept
      end
    end
  end)
end

function P.SetCalibration(state, me, h20, h60)
  local from = P.FirstEditableWeek(state)
  return P.EditSettings(state, me, function(s)
    local kept = {}
    for _, r in ipairs(s.calib) do if r.from < from then kept[#kept + 1] = r end end
    kept[#kept + 1] = { from = from, h20 = h20, h60 = h60 }
    s.calib = kept
  end)
end

-- the capo's announcement: everyone confirms it once; nil text removes it
function P.SetAnnouncement(state, me, text, byName)
  return P.EditSettings(state, me, function(s)
    if text and text ~= "" then s.ann = { t = text:sub(1, 250), at = U.Now(), by = byName } else s.ann = nil end
  end)
end

function P.SetAuctionGold(state, me, counts)
  return P.EditSettings(state, me, function(s) s.noAh = (not counts) or nil end)
end

function P.SetStart(state, me, start)
  if ns.M.WeekIndex(state.settings, U.Now()) >= 1 then return false, "er patto è già partito" end
  return P.EditSettings(state, me, function(s) s.start = start end)
end

function P.RenameTeam(state, me, teamId, name)
  return P.EditSettings(state, me, function(s)
    for _, t in ipairs(s.teams) do if t.id == teamId then t.name = name end end
  end)
end

function P.AddTeam(state, me, name, hours)
  if #state.settings.teams >= P.MAX_TEAMS then return false, "massimo " .. P.MAX_TEAMS .. " squadre" end
  local from = P.FirstEditableWeek(state)
  return P.EditSettings(state, me, function(s)
    local id = "t" .. (#s.teams + 1)
    s.teams[#s.teams + 1] = { id = id, name = name, pace = { { from = 1, hours = hours } } }
    if from > 1 then s.teams[#s.teams].pace[2] = { from = from, hours = hours } end
  end)
end

local function EditAdmins(state, me, mutate)
  if not P.IsCapo(state, me) then return false, "solo er capo pò fà 'sta cosa" end
  local new = U.Copy(state.admins)
  mutate(new)
  new.v = (state.admins.v or 0) + 1
  new.at = U.Now()
  new.by = me
  state.admins = CleanAdmins(new)
  ns.Fire("AdminsChanged", state)
  return true
end

function P.SetVice(state, me, guid, on)
  return EditAdmins(state, me, function(a) a.vice[guid] = on and true or nil end)
end

function P.TransferCapo(state, me, guid)
  return EditAdmins(state, me, function(a) a.capo = guid; a.vice[guid] = nil; a.vice[me] = true end)
end

function P.Ban(state, me, guid)
  if not P.IsAdmin(state, me) then return false, "nun c'hai er permesso" end
  if guid == state.admins.capo then return false, "er capo nun se pò caccià" end
  if guid == me then return false, "nun te poi caccià da solo" end
  local new = U.Copy(state.bans)
  new.list[guid] = true
  new.v = (state.bans.v or 0) + 1
  new.at = U.Now()
  new.by = me
  state.bans = CleanBans(new)
  state.members[guid] = nil
  ns.Fire("MembersChanged", state)
  return true
end

local function LogSwitch(state, rec, from, to, at)
  table.insert(state.switches, 1, { name = rec.name, from = from, to = to, at = at or U.Now() })
  while #state.switches > P.MAX_SWITCHES do table.remove(state.switches) end
end

function P.ChooseTeam(state, me, teamId)
  local rec = state.members[me]
  if not rec then return false end
  if teamId ~= nil and not ns.M.TeamById(state.settings, teamId) then return false, "squadra nun trovata" end
  if rec.team == teamId then return true end
  LogSwitch(state, rec, rec.team, teamId)
  rec.team = teamId
  rec.tat = U.Now()
  rec.up = U.Now()
  ns.Fire("SelfChanged", state, "team")
  return true
end

function P.UpdateSelf(state, me, fields, reason)
  local rec = state.members[me]
  if not rec then return end
  local changed = false
  for k, v in pairs(fields) do
    if rec[k] ~= v then rec[k] = v changed = true end
  end
  if changed then
    rec.up = U.Now()
    ns.Fire("SelfChanged", state, reason)
  end
end

----------------------------------------------------------------------
-- merging what arrives from others
----------------------------------------------------------------------
local function Newer(a, b)
  if not b or (b.v or 0) == 0 then return true end
  if a.v ~= b.v then return a.v > b.v end
  if a.at ~= b.at then return a.at > b.at end
  return tostring(a.by) > tostring(b.by)
end

function P.MergeAdmins(state, incoming)
  local a = CleanAdmins(incoming)
  if not a or not Newer(a, state.admins) then return false end
  -- the first copy we ever see is trusted; after that only the current capo can change it
  if (state.admins.v or 0) > 0 and a.by ~= state.admins.capo then return false end
  state.admins = a
  return true
end

function P.MergeSettings(state, incoming)
  local s = P.CleanSettings(incoming)
  if not s or not Newer(s, state.settings) then return false end
  if (state.admins.v or 0) > 0 and not P.IsAdmin(state, s.by) then return false end
  state.settings = s
  return true
end

function P.MergeBans(state, incoming)
  local b = CleanBans(incoming)
  if not b or not Newer(b, state.bans) then return false end
  if (state.admins.v or 0) > 0 and not P.IsAdmin(state, b.by) then return false end
  state.bans = b
  for g in pairs(b.list) do state.members[g] = nil end
  return true
end

-- myGuid: records about myself only ever come from me.
function P.MergeMember(state, incoming, myGuid)
  local r = P.CleanMember(incoming)
  if not r or r.guid == myGuid or P.IsBanned(state, r.guid) then return false end
  local cur = state.members[r.guid]
  if cur and (cur.up or 0) >= r.up then return false end
  if not cur then
    local n = 0
    for _ in pairs(state.members) do n = n + 1 end
    if n >= P.MAX_MEMBERS then return false end
  end
  if cur and cur.team ~= r.team then LogSwitch(state, r, cur.team, r.team, r.tat) end
  state.members[r.guid] = r
  return true
end

function P.Digest(state)
  local d = {}
  for g, r in pairs(state.members) do d[g] = r.up or 0 end
  return d
end

function P.TeamName(state, teamId)
  local t = ns.M.TeamById(state.settings or {}, teamId)
  return t and t.name or "Da sceglie"
end

function P.SortedMembers(state, teamId)
  local list = {}
  for _, r in pairs(state.members) do
    if teamId == nil or r.team == teamId then list[#list + 1] = r end
  end
  table.sort(list, function(a, b)
    if (a.lv or 0) ~= (b.lv or 0) then return (a.lv or 0) > (b.lv or 0) end
    return tostring(a.name) < tostring(b.name)
  end)
  return list
end
