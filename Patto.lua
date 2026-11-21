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

-- what a member gives to a friend: the code, 5 letters and numbers (the friend's addon finds the patto by itself)
function P.InviteCode(code) return code end

-- "98lx8", "PATTO-K7Q2M", or a code from 1.0.2 with a name after it ("98LX8 Er Gnomo"): the code, and that name
function P.ParseInvite(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local first, rest = text:match("^(%S+)%s+(.+)$")
  if first then
    local code = P.NormalizeCode(first)
    if code then return code, rest end
  end
  return P.NormalizeCode(text), nil
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
  -- the capo's swaps of tombola squares: week, square 1..9, the new square's id
  if type(s.tc) == "table" then
    local tc = {}
    for i = 1, 12 do
      local x = s.tc[i]
      if type(x) == "table" and Num(x.wk, 1, 260) and Num(x.i, 1, 9) and Str(x.id, 8) then
        tc[#tc + 1] = { wk = math.floor(x.wk), i = math.floor(x.i), id = Str(x.id, 8) }
      end
    end
    c.tc = #tc > 0 and tc or nil
  end
  -- the capo's swaps of schedina questions: week, slot a/b/c, the new question's id
  if type(s.qc) == "table" then
    local qc = {}
    for i = 1, 9 do
      local x = s.qc[i]
      local k = type(x) == "table" and Str(x.k, 1)
      if k and (k == "a" or k == "b" or k == "c") and Num(x.wk, 1, 260) and Str(x.id, 8) then
        qc[#qc + 1] = { wk = math.floor(x.wk), k = k, id = Str(x.id, 8), at = Num(x.at, 0, 4e9) }
      end
    end
    c.qc = #qc > 0 and qc or nil
  end
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
-- fl flights taken, hs hearthstones used, gp seconds played in a group with someone of the patto,
-- hw honorable kills out in the world ("pe' strada"), hb honorable kills in battlegrounds and arenas (hk: all of them),
-- gv copper given to the others of the patto (Tracker: generosity; it goes down when they give back)
local STAT_KEYS = { "q", "dg", "dw", "dl", "bw", "bl", "ding", "g", "dt", "pt", "rk", "hk", "hn",
  "fi", "he", "mi", "sk", "lb", "le", "em", "nk", "tr", "fl", "hs", "gp", "hw", "hb", "ga", "ap", "gv" }
local STAT_MAX = { g = 1e11, ga = 1e11, pt = 1e8, hn = 1e8, tr = 1e9, gp = 1e8, gv = 1e11 }

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

-- what an old life gave to each week (P.Absorb), the last three weeks
local function CleanWeeksTaken(t)
  if type(t) ~= "table" then return nil end
  local out, n = {}, 0
  for wk, v in pairs(t) do
    if n >= 3 then break end
    if type(wk) == "number" and wk >= 0 and wk <= 260 and type(v) == "table" then out[math.floor(wk)] = CleanStats(v) n = n + 1 end
  end
  return next(out) and out or nil
end

function P.CleanMember(r)
  if type(r) ~= "table" then return nil end
  local c = {
    guid = Str(r.guid, 60), name = Str(r.name, 40), team = Str(r.team, 8), tat = Num(r.tat, 0, 4e9),
    up = Num(r.up, 0, 4e9), lv = Num(r.lv, 0, 100), xp = Num(r.xp, 0, 1e7), xpm = Num(r.xpm, 0, 1e7),
    rest = Num(r.rest, 0, 1e7), zone = Str(r.zone, 40), cls = Str(r.cls, 20), ver = Str(r.ver, 12), ld = Str(r.ld, 40),
    il = Num(r.il, 0, 2000), race = Str(r.race, 20), rid = Num(r.rid, 1, 200), sex = Num(r.sex, 1, 3),
    eq = type(r.eq) == "string" and #r.eq <= 600 and r.eq:match("^[%d%./%-]*$") and r.eq or nil,
    stats = { t = CleanStats(r.stats and r.stats.t), w = {} }, h2h = {}, alts = {},
    ti = Str(r.ti, 24), fresh = r.fresh == true or nil, abt = type(r.abt) == "table" and CleanStats(r.abt) or nil, abw = CleanWeeksTaken(r.abw), lp = Num(r.lp, 0, 1e9),
    dl = type(r.dl) == "table" and Num(r.dl.lv, 1, 100) and { lv = Num(r.dl.lv, 1, 100), s = Num(r.dl.s, 0, 1e8), at = Num(r.dl.at, 0, 4e9) } or nil,
    zq = CleanCounts(r.zq, 6), zqw = CleanCounts(r.zqw, 6), dgw = CleanCounts(r.dgw, 8), wk = Num(r.wk, 0, 260), dgl = CleanCounts(r.dgl, 8), lq = {}, pr = {}, ms = {}, rl = {},
    nkl = {}, sv = P.CleanVersions and P.CleanVersions(r.sv) or nil,
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
    c.pts = { t = math.floor(Num(r.pts.t, 0, 1e7) or 0), w = math.floor(Num(r.pts.w, 0, 1e4) or 0), wk = Num(r.pts.wk, 0, 260),
      r = math.floor(Num(r.pts.r, 0, 1e4) or 0), n = math.floor(Num(r.pts.n, 0, 1e4) or 0),
      ps = math.floor(Num(r.pts.ps, 0, 1e7) or 0), pw = math.floor(Num(r.pts.pw, 0, 1e7) or 0) }
  end
  -- bets: this week's (vt) and last week's (vp): pick and stake per question
  local function Bets(v)
    if type(v) ~= "table" or not Num(v.wk, 0, 260) then return nil end
    local out = { wk = Num(v.wk, 0, 260) }
    for _, k in ipairs({ "a", "b", "c" }) do
      out[k] = Str(v[k], 60)
      out["s" .. k] = out[k] and math.floor(Num(v["s" .. k], 0, 1e5) or 0) or nil
      out["q" .. k] = out[k] and Num(v["q" .. k], 10, 1000) and math.floor(Num(v["q" .. k], 10, 1000)) or nil -- the odds taken, x10
      out["t" .. k] = out[k] and Num(v["t" .. k], 0, 4e9) or nil -- when it was played (a question changed later voids it)
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
      p = math.floor(Num(x.p, 0, 8) or 0), t = Plain(x.t, 20), e = math.floor(Num(x.e, 0, 8) or 0),
      st = Str(x.st, 3), w = Str(x.w, 1), m = Num(x.m, 0, 1) and math.floor(Num(x.m, 0, 1)) or nil, rv = Str(x.rv, 40), at = Num(x.at, 0, 4e9) }
  end)
  -- er duello a la gogna: the challenges I threw (gd: rv = the duel it's the rivincita of, x = 1: "basta", x = 2: the
  -- duel request turned down), the
  -- pegni I chose as winner (gp: id of the first challenge, which pegno, its text, the emote)
  -- (x: 1 "basta", 2 turned down / off, 3 accepted: the duel countdown started)
  -- er Lunario: the appuntamenti I put up (ev), my answers (ea), my bets on them (eb), how they went for me (er)
  local EVK = { dg = true, du = true, bg = true, lv = true, al = true, ca = true, wp = true, qu = true }
  c.ev = List(r.ev, 6, function(x)
    if not (Str(x.id, 40) and EVK[x.k] and Plain(x.n, 40) and Num(x.t, 0, 4e9)) then return nil end
    return { id = Str(x.id, 40), k = x.k, n = Plain(x.n, 40), t = math.floor(Num(x.t, 0, 4e9)), d = math.floor(Num(x.d, 15, 600) or 120),
      tm = Str(x.tm, 8) or "", m = math.floor(Num(x.m, 0, 40) or 0), no = Plain(x.no, 60), x = x.x == 1 and 1 or nil, at = Num(x.at, 0, 4e9), q = Str(x.q, 24) }
  end)
  c.ea = List(r.ea, 12, function(x)
    local a = tonumber(x.a)
    if not (Str(x.i, 40) and (a == 0 or a == 1 or a == 2)) then return nil end
    return { i = Str(x.i, 40), a = a, at = Num(x.at, 0, 4e9) }
  end)
  c.eb = List(r.eb, 14, function(x)
    if not (Str(x.i, 40) and Str(x.q, 3) and Str(x.p, 60) and Num(x.s, 1, 1e4)) then return nil end
    return { i = Str(x.i, 40), q = Str(x.q, 3), p = Str(x.p, 60), s = math.floor(Num(x.s, 1, 1e4)), at = Num(x.at, 0, 4e9) }
  end)
  c.er = List(r.er, 8, function(x)
    if not Str(x.i, 40) then return nil end
    local o = { i = Str(x.i, 40), ok = 1 }
    -- (what's zero is left out)
    for _, k in ipairs({ "d", "h", "k", "dt", "dw", "dl", "hk", "gn", "tk", "mx", "fd", "td", "g", "q", "lt" }) do
      local v = math.floor(Num(x[k], 0, 1e9) or 0)
      if v > 0 then o[k] = v end
    end
    return o
  end)
  -- (empty, they're left out: every record goes to everyone, a few bytes each count)
  for _, k in ipairs({ "ev", "ea", "eb", "er" }) do if c[k] and #c[k] == 0 then c[k] = nil end end
  c.gd = List(r.gd, 12, function(x)
    if not (Str(x.id, 40) and Str(x.to, 60) and Num(x.at, 0, 4e9)) then return nil end
    local k = tonumber(x.x)
    return { id = Str(x.id, 40), to = Str(x.to, 60), rv = Str(x.rv, 40), x = (k == 1 or k == 2 or k == 3) and k or nil, at = Num(x.at, 0, 4e9) }
  end)
  -- li scontrini: the last lines of my piotte (what, with whom, put in, taken)
  c.lg = List(r.lg, 20, function(x)
    if not (Num(x.at, 0, 4e9) and Str(x.k, 4)) then return nil end
    return { at = Num(x.at, 0, 4e9), k = Str(x.k, 4), o = Str(x.o, 60), w = Num(x.w, 0, 260), s = Num(x.s, 0, 1e6), g = Num(x.g, 0, 1e6),
      open = (Num(x.open, 1, 1) and 1) or nil }
  end)
  c.gp = List(r.gp, 4, function(x)
    if not (Str(x.id, 40) and Num(x.p, 1, 8) and Num(x.at, 0, 4e9)) then return nil end
    return { id = Str(x.id, 40), p = math.floor(Num(x.p, 1, 8)), t = Plain(x.t, 20), e = Num(x.e, 1, 16) and math.floor(Num(x.e, 1, 16)) or nil, at = Num(x.at, 0, 4e9) }
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
  -- the last death alone (small: it travels in the flash, so everyone is told at once)
  if type(r.lr) == "table" and Num(r.lr.at, 0, 4e9) then
    local x = r.lr
    c.lr = { at = Num(x.at, 0, 4e9), lv = Num(x.lv, 0, 100), by = Plain(x.by, 40), z = Str(x.z, 40), w = Plain(x.w, 80), k = Str(x.k, 12),
      n = Num(x.n, 0, 1e6), m = Num(x.m, 0, 1e6) }
  end
  c.rip = List(r.rip, 10, function(x)
    if not Num(x.at, 0, 4e9) then return nil end
    return { at = Num(x.at, 0, 4e9), lv = Num(x.lv, 0, 100), by = Plain(x.by, 40), z = Str(x.z, 40), w = Plain(x.w, 80), k = Str(x.k, 12) }
  end)
  -- when I first met each milestone title (Titles.lua), so only the first holds it
  if type(r.tt) == "table" then
    c.tt = {}
    local n = 0
    for k, v in pairs(r.tt) do
      if n < 40 and type(k) == "string" and #k <= 16 and Num(v, 0, 4e9) then c.tt[k] = Num(v, 0, 4e9) n = n + 1 end
    end
  end
  -- la guardia: my own time played without the addon (na), the ones I saw online with it off (nv)
  c.na = List(r.na, 5, function(x)
    if not (Num(x.at, 0, 4e9) and Num(x.s, 0, 1e7)) then return nil end
    return { at = Num(x.at, 0, 4e9), s = math.floor(Num(x.s, 0, 1e7)) }
  end)
  c.nv = List(r.nv, 5, function(x)
    local k = Str(x.k, 8)
    if not (Str(x.g, 60) and Num(x.at, 0, 4e9) and (k == "gilda" or k == "gruppo" or k == "chat")) then return nil end
    return { g = Str(x.g, 60), at = Num(x.at, 0, 4e9), k = k, v = Num(x.v, 1, 9) }
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
  if type(r.wp) == "table" and Num(r.wp.at, 0, 4e9) then
    c.wp = { at = Num(r.wp.at, 0, 4e9), z = Str(r.wp.z, 40), n = Str(r.wp.n, 160), c = Num(r.wp.c, 0, 40) }
  end
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
        c.alts[#c.alts + 1] = { name = Str(a.name, 40), lv = Num(a.lv, 1, 100) or 1, cls = Str(a.cls, 20) }
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
  -- fresh: made on this PC just now; until the friends have been heard, it may be a lost record coming back
  -- the real level from the start: a record born at 1 and corrected a second later looked like a ding
  local lv = UnitLevel and U.Plain(UnitLevel("player"), "number")
  -- (its pieces at version zero: whatever a friend holds of it is newer, and comes back to it)
  local sv = {}
  for _, p in ipairs(P.PIECE_ORDER or {}) do sv[p] = 0 end
  local fsv = {}
  for k, v in pairs(sv) do fsv[k] = v end
  return { guid = guid, name = name, up = U.Now(), lv = lv and lv >= 1 and lv or 1, stats = { t = {}, w = {} }, h2h = {}, alts = {}, ver = ns.VERSION, fresh = true, sv = sv, fsv = fsv }
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

-- the hours of a squadra: more hours count from this very week (its cap goes up now, and every week after is
-- worked out again from there); fewer hours too, unless someone of the squadra would find himself over this
-- week's cap: then from next week. Changed again in the same week, the last one wins.
-- Returns ok, the week it counts from.
local function PaceFrom(pace, from, hours, realLevel)
  local kept = {}
  for _, r in ipairs(pace or {}) do if r.from < from then kept[#kept + 1] = r end end
  kept[#kept + 1] = { from = from, hours = hours, level = realLevel }
  return kept
end

function P.SetPace(state, me, teamId, hours, realLevel)
  local M = ns.M
  local wk = math.max(1, M.WeekIndex(state.settings, U.Now()))
  local team = M.TeamById(state.settings, teamId)
  if not team then return false, "squadra nun trovata" end
  local from = wk
  -- would this week's cap go down? then from next week
  local oldRows = M.TeamRows(state.settings, team)
  local test = U.Copy(team)
  test.pace = PaceFrom(team.pace, wk, hours, realLevel)
  local newRows = M.TeamRows(state.settings, test)
  local function CapAt(rows, k) local r = rows[math.min(k, #rows)] return r and r.cap or 60 end
  local newCap = CapAt(newRows, wk)
  if newCap < CapAt(oldRows, wk) then
    -- lower, but nobody of the squadra is over it yet (a number typed wrong just now): still this week
    local top = 0
    for _, r in pairs(state.members or {}) do
      if type(r) == "table" and r.team == teamId and type(r.lv) == "number" and r.lv > top then top = r.lv end
    end
    if top > newCap then from = wk + 1 end
  end
  local ok, e = P.EditSettings(state, me, function(s)
    for _, t in ipairs(s.teams) do
      if t.id == teamId then t.pace = PaceFrom(t.pace, from, hours, realLevel) end
    end
  end)
  if not ok then return false, e end
  return true, from
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
  if state.members[guid] then P.KeepPrev(state, state.members[guid]) end
  state.members[guid] = nil
  ns.Fire("MembersChanged", state)
  return true
end

-- someone cacciato and invited again by a capo or vice: the ban is lifted
function P.Unban(state, me, guid)
  if not P.IsAdmin(state, me) or not P.IsBanned(state, guid) then return false end
  local new = U.Copy(state.bans)
  new.list[guid] = nil
  new.v = (state.bans.v or 0) + 1
  new.at = U.Now()
  new.by = me
  state.bans = CleanBans(new)
  P.BackFromBan(state, { [guid] = true })
  ns.Fire("MembersChanged", state)
  return true
end

local function LogSwitch(state, rec, from, to, at)
  table.insert(state.switches, 1, { name = rec.name, from = from, to = to, at = at or U.Now() })
  while #state.switches > P.MAX_SWITCHES do table.remove(state.switches) end
end
P.LogSwitch = LogSwitch

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

----------------------------------------------------------------------
-- old lives: a member's record that left the list (cacciato, a goodbye) or that came back started from zero
-- (left and in again, a new PC) is kept aside here; when its owner shows up, it goes back to them and what it
-- counted (rari, quest, ore...) is theirs again. Counters only ever grow, so a copy with more in one of them
-- than the record of now is an old life
----------------------------------------------------------------------
P.MAX_PREV = 20
P.PREV_DAYS = 60
local function Total(rec, k) return rec and rec.stats and rec.stats.t and rec.stats.t[k] or 0 end
-- deaths can go down (the doubles, the battlegrounds taken out): they never make a copy an "old life"
-- the honorable kills too: the addon itself takes out the ones counted twice (Tracker.RepairPvP), so a friend's
-- copy with more of them is the old wrong number, not an old life to give back (it went round every few minutes)
-- generosity too: it goes down when a friend gives back
local DOWN = { dt = true, em = true, hk = true, hw = true, hb = true, gv = true }
P.ABSORB_FOR = 2 * 3600
P.STAT_DOWN = DOWN
function P.Behind(now, old)
  if type(now) ~= "table" or type(old) ~= "table" then return false end
  for _, k in ipairs(STAT_KEYS) do if not DOWN[k] and Total(old, k) > Total(now, k) then return true end end
  return false
end

function P.KeepPrev(state, rec)
  if type(rec) ~= "table" or type(rec.guid) ~= "string" or rec.fresh then return end
  state.prev = type(state.prev) == "table" and state.prev or {}
  local had = state.prev[rec.guid]
  -- the copy with more in it stays
  if had and not P.Behind(had, rec) then return end
  state.prev[rec.guid] = rec
  local n, oldG, oldU, now = 0, nil, nil, U.Now()
  for g, r in pairs(state.prev) do
    if (r.up or 0) < now - P.PREV_DAYS * 86400 then state.prev[g] = nil
    else
      n = n + 1
      if not oldU or (r.up or 0) < oldU then oldG, oldU = g, r.up or 0 end
    end
  end
  if n > P.MAX_PREV then state.prev[oldG] = nil end
end

-- my old life coming back. born: when my record of now started from zero. An old life that ended before that is
-- apart from this one: its counters add to mine (what I do meanwhile isn't lost); `abt` remembers what was taken,
-- so a newer copy of the same old life only adds what's new in it. A copy that isn't clearly apart: every counter
-- takes the bigger of the two (never counted twice). What my record doesn't have yet (the rari list, the famous
-- kills, the squadra...) comes from the old one; the game's fields stay mine
local LIVE
-- does this old copy bring me something: more than I have, or (an old life apart) more than I took from it
function P.HasMore(mine, old, born)
  if P.Behind(mine, old) then return true end
  if not (type(born) == "number" and (old.up or 0) <= born and type(mine.abt) == "table") then return false end
  for _, k in ipairs(STAT_KEYS) do if not DOWN[k] and Total(old, k) > (mine.abt[k] or 0) then return true end end
  return false
end

function P.Absorb(mine, old, born)
  local t = mine.stats and mine.stats.t or {}
  mine.stats = mine.stats or { t = t, w = {} }
  mine.stats.t = t
  local apart = type(born) == "number" and (old.up or 0) <= born
  local took = type(mine.abt) == "table" and mine.abt or {}
  for _, k in ipairs(STAT_KEYS) do
    local o = Total(old, k)
    if DOWN[k] then
      -- (deaths: never added from another copy, they're only ever taken out)
    elseif apart then
      local had = took[k] or 0
      if o > had then t[k] = (t[k] or 0) + (o - had) took[k] = o end
    elseif o > (t[k] or 0) then
      t[k] = o
    end
  end
  if apart then mine.abt = took end
  -- the weeks too (the tombola, the schedina and the sfide count the week): the same way, week by week
  mine.stats.w = type(mine.stats.w) == "table" and mine.stats.w or {}
  local tookW = type(mine.abw) == "table" and mine.abw or {}
  for wk, ow in pairs(type(old.stats) == "table" and type(old.stats.w) == "table" and old.stats.w or {}) do
    if type(wk) == "number" and type(ow) == "table" then
      local w = mine.stats.w[wk] or {}
      mine.stats.w[wk] = w
      local tw = tookW[wk] or {}
      for _, k in ipairs(STAT_KEYS) do
        local o = type(ow[k]) == "number" and ow[k] or 0
        if DOWN[k] then
        elseif apart then
          local had = tw[k] or 0
          if o > had then w[k] = (w[k] or 0) + (o - had) tw[k] = o end
        elseif o > (w[k] or 0) then
          w[k] = o
        end
      end
      if apart then tookW[wk] = tw end
    end
  end
  if apart then mine.abw = tookW end
  local live = {}
  for _, k in ipairs(LIVE) do live[k] = true end
  for k, v in pairs(old) do
    if not live[k] and k ~= "guid" and k ~= "up" and k ~= "stats" and k ~= "fresh" and k ~= "abt" and k ~= "abw" then
      local m = mine[k]
      if m == nil or (type(m) == "table" and next(m) == nil) then mine[k] = U.Copy(v) end
    end
  end
end

-- who was cacciato and isn't anymore: their record comes back from aside (and from there to them)
function P.BackFromBan(state, was)
  if type(state.prev) ~= "table" then return end
  for g in pairs(was or {}) do
    local r = state.prev[g]
    if r and not P.IsBanned(state, g) and not state.members[g] then
      state.members[g] = r
      state.prev[g] = nil
    end
  end
end

function P.MergeBans(state, incoming)
  local b = CleanBans(incoming)
  if not b or not Newer(b, state.bans) then return false end
  if (state.admins.v or 0) > 0 and not P.IsAdmin(state, b.by) then return false end
  local was = state.bans and state.bans.list
  state.bans = b
  P.BackFromBan(state, was)
  for g in pairs(b.list) do
    if state.members[g] then P.KeepPrev(state, state.members[g]) end
    state.members[g] = nil
  end
  return true
end

-- myGuid: records about myself only ever come from me.
-- what the game says about me right now: kept when my old record comes back from a friend
LIVE = { "lv", "xp", "xpm", "rest", "zone", "eq", "il", "ver", "name", "cls", "race", "rid", "sex", "alts" }

-- a whole record (an old life given back, a lost record coming back to a new PC, or from an addon before sync 2)
function P.MergeMember(state, incoming, myGuid)
  local r = P.CleanMember(incoming)
  if not r or P.IsBanned(state, r.guid) then return false end
  -- (whole and without versions: every piece of it as new as the record)
  if not r.sv then P.InitVersions(r, r.up) end
  if r.guid == myGuid then
    -- my own record from a friend: taken back only when mine is new on this PC (the WTF folder lost, a new
    -- computer) and theirs is a real one; then it's mine again, with what the game says now on top
    local mine = state.members[myGuid]
    -- or an old life of mine (I left, was cacciato, came back): what it counted is mine again
    -- (only just after joining again: later, a friend's copy with more in it is an old number, not a lost life)
    if mine and not mine.fresh and not r.fresh and U.Now() - (state.joinedAt or 0) < P.ABSORB_FOR
      and P.HasMore(mine, r, state.joinedAt) then
      P.Absorb(mine, r, state.joinedAt)
      mine.up = math.max(U.Now(), (mine.up or 0) + 1)
      ns.Fire("SelfRestored", mine)
      return true
    end
    -- (base: a record I came in with from this PC; only a copy newer than it is taken, the rest is older news)
    if not (mine and mine.fresh and not r.fresh and (r.up or 0) > (tonumber(mine.base) or 0)) then return false end
    -- piece by piece: the friend's where it's newer than mine (what I changed since coming in stays mine); the
    -- counters each the bigger of the two; what the game says of me now stays mine
    local took = false
    for _, p in ipairs(P.PIECE_ORDER) do
      local theirs = r.sv and r.sv[p] or 0
      local ok = P.MergePiece(state, myGuid, p, theirs, P.PieceData(r, p), myGuid)
      if ok then took = true end
    end
    if not took then return false end
    -- (a whole copy taken: it's mine again, not new any more)
    state.members[myGuid].fresh, state.members[myGuid].fsv = nil, nil
    ns.Fire("SelfRestored", state.members[myGuid])
    return true
  end
  if P.HasLeft(state, r.guid, r.up) then return false end
  local cur = state.members[r.guid]
  -- a record started again from nothing never replaces a real copy: its owner is about to get the real one back
  if cur and not cur.fresh and r.fresh then return false end
  if cur and (cur.up or 0) >= r.up then return false end
  -- (a piece of it I already have newer stays mine)
  if cur and type(cur.sv) == "table" then
    for _, p in ipairs(P.PIECE_ORDER) do
      if (cur.sv[p] or 0) > (r.sv[p] or 0) then
        if p ~= "t" and p ~= "w" then for k in pairs(r) do if type(k) == "string" and P.PieceOf(k) == p then r[k] = nil end end end
        for k, v in pairs(P.PieceData(cur, p)) do
          if p == "t" then r.stats.t = v elseif p == "w" then r.stats.w = v else r[k] = v end
        end
        r.sv[p] = cur.sv[p]
      end
    end
  end
  -- newer but started again from zero: the old copy goes aside, for its owner to take back
  if cur and P.Behind(r, cur) then P.KeepPrev(state, cur) end
  -- an old life already given back: once the record of now has it all, it's done
  local pv = type(state.prev) == "table" and state.prev[r.guid]
  if pv and not P.Behind(r, pv) then state.prev[r.guid] = nil end
  if not cur then
    local n = 0
    for _ in pairs(state.members) do n = n + 1 end
    if n >= P.MAX_MEMBERS then return false end
  end
  if cur and cur.team ~= r.team then LogSwitch(state, r, cur.team, r.team, r.tat) end
  state.members[r.guid] = r
  return true
end

-- who left the patto, with the date of their last record: older copies of it never come back
-- (a friend who missed the goodbye would send it again); someone coming back with the code is newer
P.MAX_LEFT = 60
function P.MarkLeft(state, guid, up)
  if type(guid) ~= "string" or type(up) ~= "number" then return false end
  state.left = type(state.left) == "table" and state.left or {}
  if (state.left[guid] or 0) >= up then return false end
  local cur = state.members[guid]
  if cur and (cur.up or 0) > up then return false end
  state.left[guid] = up
  if cur then P.KeepPrev(state, cur) end
  state.members[guid] = nil
  -- the oldest goodbyes go first past the cap
  local n, oldG, oldU = 0, nil, nil
  for g, u in pairs(state.left) do
    n = n + 1
    if not oldU or u < oldU then oldG, oldU = g, u end
  end
  if n > P.MAX_LEFT then state.left[oldG] = nil end
  return true
end

function P.HasLeft(state, guid, up)
  local t = type(state.left) == "table" and state.left[guid]
  return t and (up or 0) <= t or false
end

----------------------------------------------------------------------
-- the pieces of a record (sync 2): a record is 6-9 KB, 30-40 messages at the game's pace; it travels in pieces,
-- each with its own version (rec.sv[piece] = when its owner last changed it). A "Ce sto" is one small piece, a
-- death another: they go at once and alone. The owner gives the versions; the others only keep and pass them on.
-- The order is the order they go in: what must be known at once first.
----------------------------------------------------------------------
P.PIECES = {
  { "b", { "name", "lv", "xp", "xpm", "rest", "zone", "team", "tat", "ver", "il", "ti", "dl", "cls", "race", "rid", "sex" } }, -- who, level
  -- the last death, the last silly one, a wipe; then the counters; then the first epic, the rares, the nemesis.
  -- What changes together goes in the same message (they're next to each other, and all go at once), so the news
  -- says them whole: a death with how many in all, a rare with its name
  { "r", { "lr", "ed", "wp", "dat", "dz" } },
  { "t", { "stats.t" } },                                      -- the counters
  { "f", { "fe", "rl", "ne" } },
  { "d", { "dd" } },                                           -- the last duels
  { "a", { "ea" } },                                           -- answers to the caciare
  { "e", { "ev" } },                                           -- the caciare put up
  { "y", { "eb", "er" } },                                     -- bets on them, how they went
  { "g", { "gd", "gp" } },                                     -- er duello a la gogna, the pegni
  { "s", { "sf", "sk", "tg", "gf" } },                         -- sfide, answers, taje, gufate
  { "w", { "stats.w" } },                                      -- the counters of the weeks
  { "v", { "vt", "vp", "pts" } },                              -- la schedina
  { "c", { "rip" } },                                          -- er cimitero
  { "o", { "lg" } },                                           -- li scontrini
  { "q", { "lq", "nkl" } },                                    -- the diary
  { "z", { "zq", "zqw", "dgw", "dgl", "pr", "tt" } },          -- zones, dungeons, professions, titles met
  { "k", { "eq", "alts", "h2h" } },                            -- gear, alts, head to head
  { "n", { "na", "nv" } },                                     -- la guardia
  { "x", {} },                                                 -- everything else
}
-- what the pieces are: a new one (or a field moved) bumps it, and every copy is asked again once
P.SCHEMA = "pezzi-2"
P.PIECE_ORDER, P.PIECE_OF, P.PIECE_FIELDS = {}, {}, {}
for _, p in ipairs(P.PIECES) do
  P.PIECE_ORDER[#P.PIECE_ORDER + 1] = p[1]
  P.PIECE_FIELDS[p[1]] = p[2]
  for _, f in ipairs(p[2]) do P.PIECE_OF[f] = p[1] end
end
-- not in any piece: the envelope (guid, versions, date) and what is only this PC's
local NOT_SENT = { guid = true, up = true, sv = true, fresh = true, base = true, stats = true, fsv = true }
function P.PieceOf(field)
  if NOT_SENT[field] then return nil end
  return P.PIECE_OF[field] or "x"
end
-- the fields of one piece of rec, as they travel (stats.t and stats.w as "t" and "w")
function P.PieceData(rec, piece)
  local out = {}
  if piece == "t" then out.t = rec.stats and rec.stats.t or {} return out end
  if piece == "w" then out.w = rec.stats and rec.stats.w or {} return out end
  for k, v in pairs(rec) do
    if type(k) == "string" and P.PieceOf(k) == piece then out[k] = v end
  end
  return out
end
-- a record without versions (made before sync 2, or come whole from an older addon): every piece as new as it
function P.InitVersions(rec, at)
  if type(rec) ~= "table" then return end
  rec.sv = type(rec.sv) == "table" and rec.sv or {}
  for _, p in ipairs(P.PIECE_ORDER) do
    if type(rec.sv[p]) ~= "number" then rec.sv[p] = at or rec.up or 0 end
  end
end
function P.CleanVersions(sv)
  local out = {}
  if type(sv) ~= "table" then return nil end
  for _, p in ipairs(P.PIECE_ORDER) do
    local v = sv[p]
    if type(v) == "number" and v == v and v >= 0 and v <= 4e9 then out[p] = math.floor(v) end
  end
  return out
end
-- a piece from someone (a member's or its copy): on my copy of the record when newer than what I have of it.
-- Returns changed, the record now, the record before; "nobase" when I don't know the member yet and it isn't the
-- piece that says who they are (it waits for it)
function P.MergePiece(state, guid, piece, ver, data, myGuid)
  if type(guid) ~= "string" or type(piece) ~= "string" or not P.PIECE_FIELDS[piece] or type(ver) ~= "number"
    or type(data) ~= "table" or P.IsBanned(state, guid) then return false end
  -- (a goodbye of mine noted here is my past: I'm in now)
  if guid ~= myGuid and P.HasLeft(state, guid, ver) then return false end
  local cur = state.members[guid]
  local own, mineHere = guid == myGuid, false
  if own then
    -- my own record is mine: a friend's copy of a piece of it only while mine is "fresh" (just come in: lost on
    -- this PC, or played on another one since), newer than what I came in with (fsv), not my own echo. A piece
    -- I changed since coming in stays mine (its counters, and who I am, merged)
    if not (cur and cur.fresh) then return false end
    local now = type(cur.sv) == "table" and cur.sv[piece] or 0
    local came = type(cur.fsv) == "table" and cur.fsv[piece] or now
    if ver <= came or ver == now then return false end
    mineHere = now > came
    if mineHere and piece ~= "t" and piece ~= "w" and piece ~= "b" then return false end
  elseif cur and type(cur.sv) == "table" and (cur.sv[piece] or 0) >= ver then
    return false
  end
  if not cur and piece ~= "b" then return "nobase" end
  if not cur then
    local n = 0
    for _ in pairs(state.members) do n = n + 1 end
    if n >= P.MAX_MEMBERS then return false end
  end
  local new = {}
  for k, v in pairs(cur or {}) do new[k] = v end
  new.guid = guid
  new.stats = { t = cur and cur.stats and cur.stats.t or {}, w = cur and cur.stats and cur.stats.w or {} }
  new.sv = {}
  for k, v in pairs(cur and cur.sv or {}) do new.sv[k] = v end
  local merge = guid == myGuid
  if piece == "t" and merge then
    -- my counters coming back: each the bigger of the two (what I did since coming in stays)
    new.stats.t = {}
    for k, v in pairs(cur.stats and cur.stats.t or {}) do new.stats.t[k] = v end
    for k, v in pairs(type(data.t) == "table" and data.t or {}) do
      if type(v) == "number" and v > (new.stats.t[k] or 0) then new.stats.t[k] = v end
    end
  elseif piece == "w" and merge then
    new.stats.w = {}
    for wk, kv in pairs(cur.stats and cur.stats.w or {}) do
      new.stats.w[wk] = {}
      for k, v in pairs(kv) do new.stats.w[wk][k] = v end
    end
    for wk, kv in pairs(type(data.w) == "table" and data.w or {}) do
      if type(kv) == "table" then
        new.stats.w[wk] = new.stats.w[wk] or {}
        for k, v in pairs(kv) do if type(v) == "number" and v > (new.stats.w[wk][k] or 0) then new.stats.w[wk][k] = v end end
      end
    end
  elseif piece == "t" then new.stats.t = type(data.t) == "table" and data.t or {}
  elseif piece == "w" then new.stats.w = type(data.w) == "table" and data.w or {}
  elseif piece == "b" and own then
    -- who I am: the game says it now (level, zone...); the squadra the newer of the two; the rest where I have none
    for k, v in pairs(data) do
      if P.PieceOf(k) == "b" then
        if k == "team" or k == "tat" then
          if (tonumber(data.tat) or 0) > (tonumber(cur.tat) or 0) or cur.team == nil then new.team, new.tat = data.team, data.tat end
        elseif new[k] == nil then new[k] = v end
      end
    end
  else
    -- this piece's fields, all of them (one gone in it is gone here); nothing of another piece rides in it
    for k in pairs(new) do if type(k) == "string" and P.PieceOf(k) == piece then new[k] = nil end end
    for k, v in pairs(data) do if type(k) == "string" and P.PieceOf(k) == piece then new[k] = v end end
  end
  new.sv[piece] = math.max(ver, own and (cur.sv and cur.sv[piece]) or 0)
  new.up = math.max(cur and cur.up or 0, ver)
  -- my lost record coming back piece by piece: what the game says of me now stays mine
  if own then for _, k in ipairs(LIVE) do if cur[k] ~= nil then new[k] = cur[k] end end end
  local r = P.CleanMember(new)
  if not r then return false end
  r.sv = P.CleanVersions(new.sv)
  if not cur then P.InitVersions(r, 0) r.sv[piece] = ver end
  -- started again from zero (left and back, a new PC): the old copy goes aside, for its owner to take back
  -- (its date: when its counters were last its own, not the pieces of the new life already come before them)
  if cur and piece == "t" and P.Behind(r, cur) then
    local old = {}
    for k, v in pairs(cur) do old[k] = v end
    old.up = cur.sv and cur.sv.t or cur.up
    P.KeepPrev(state, old)
  end
  if cur and cur.team ~= r.team then LogSwitch(state, r, cur.team, r.team, r.tat) end
  if own then r.fresh, r.base, r.fsv = cur.fresh, cur.base, cur.fsv end
  -- an old life already given back: once the record of now has it all, it's done
  local pv = type(state.prev) == "table" and state.prev[guid]
  if pv and piece == "t" and not P.Behind(r, pv) then state.prev[guid] = nil end
  state.members[guid] = r
  return true, r, cur
end
-- what I hold of each member, piece by piece, in a few characters: "<newest>:<how much older each piece is>"
-- (base 36; empty = as new as the newest, "-" = none)
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function To36(n)
  n = math.floor(n)
  if n <= 0 then return "0" end
  local s = ""
  while n > 0 do local d = n % 36 s = B36:sub(d + 1, d + 1) .. s n = math.floor(n / 36) end
  return s
end
P.To36 = To36
function P.Vector(rec)
  local sv = type(rec.sv) == "table" and rec.sv or {}
  local top = 0
  for _, p in ipairs(P.PIECE_ORDER) do top = math.max(top, sv[p] or 0) end
  local parts = {}
  for i, p in ipairs(P.PIECE_ORDER) do
    local v = sv[p] or 0
    parts[i] = (v <= 0 and top > 0) and "-" or (v == top and "" or To36(top - v))
  end
  return To36(top) .. ":" .. table.concat(parts, ",")
end
function P.Unvector(s)
  if type(s) ~= "string" then return nil end
  local top, rest = s:match("^([0-9a-z]+):(.*)$")
  top = top and tonumber(top, 36)
  if not top then return nil end
  local out, i = {}, 0
  for part in (rest .. ","):gmatch("([^,]*),") do
    i = i + 1
    local p = P.PIECE_ORDER[i]
    if not p then break end
    if part == "-" then out[p] = 0
    elseif part == "" then out[p] = top
    else local d = tonumber(part, 36) out[p] = d and math.max(0, top - d) or 0 end
  end
  return out
end
function P.Vectors(state)
  local d = {}
  for g, r in pairs(state.members) do d[g] = P.Vector(r) end
  return d
end

-- a new version of the addon (or the first with pieces): the others' copies may lack what an older one threw
-- away. Their versions go to zero: the owners, when they come, give everything again (once); the copies stay
-- meanwhile. Mine is mine.
function P.MarkStale(state, myGuid)
  for g, r in pairs(state.members) do
    if g ~= myGuid then
      r.sv = {}
      for _, p in ipairs(P.PIECE_ORDER) do r.sv[p] = 0 end
    else
      P.InitVersions(r)
    end
  end
  state.stale = nil
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
