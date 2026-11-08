-- Er Patto: Er Bollettino, the week told like a paper. It opens by itself at the first login after the weekly
-- reset (and from the Baretto). One big vanilla window: the headline, then la settimana tua (your card, your
-- schedina, the rest of your piotte), then the boxes:
-- li titoli de la settimana, li ricchi (piotte), li sordi (gold made in the week), er cimitero, er Colosseo (duels,
-- gogne, records), le mejo tombole, li primati (quest, rari, dungeon, ore), er PvP (pe' strada and in BG apart),
-- ar Botteghino (the Colosseo bets, sfottò, faccioni), la schedina. It shrinks to fit a small screen.
-- Cost: everything is counted once, when the window opens (a few loops over the members and their last ten
-- graves); nothing runs while it's open. The titles are remembered once a week (who held what when the week
-- began), a small table per week.
local ADDON, ns = ...
local U, M, P, UI = ns.U, ns.M, ns.P, ns.UI
local H = UI.H
local Home = ns.Home
local B = {}
ns.Bollettino = B

local GREY, GOLD, GREEN, RED, WHITE = "|cff9d9d9d", "|cffffd100", "|cff20ff20", "|cffff4040", "|cffffffff"
local ICON = "Interface\\Icons\\"
local GOLDICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local function Short(m) return U.Short(m and m.name) end
local function Colored(m) return "|c" .. H.ClassHex(m.cls) .. Short(m) .. "|r" end
local function W(m, wk, k)
  if ns.Tombola then return ns.Tombola.Weekly(m, wk)[k] or 0 end
  local w = m.stats and m.stats.w and m.stats.w[wk]
  return type(w) == "table" and (w[k] or 0) or 0
end
local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end
local function Coin() return ns.Tombola and ns.Tombola.Coin(12) or "" end
local function Signed(n) return n > 0 and (GREEN .. "+" .. n .. "|r") or n < 0 and (RED .. n .. "|r") or (GREY .. "0|r") end

-- best (or worst) of the list for a value; nil when nobody did anything
local function Leader(list, fn, lowest)
  local best, bestV
  for _, m in ipairs(list) do
    local v = fn(m) or 0
    local better = not bestV or (lowest and v < bestV) or (not lowest and v > bestV) or (v == bestV and tostring(m.name) < tostring(best.name))
    if (lowest or v > 0) and better then best, bestV = m, v end
  end
  return best, bestV
end

----------------------------------------------------------------------
-- the titles at the start of each week (to tell who took which this week)
----------------------------------------------------------------------
local SKIP = { sorcapo = true, braccio = true }
local function Holders()
  local out = {}
  if not (ns.Titles and ns.Titles.Holders) then return out end
  for id, set in pairs(ns.Titles.Holders()) do
    if not SKIP[id] then
      out[id] = {}
      for g in pairs(set) do out[id][#out[id] + 1] = g end
      table.sort(out[id])
    end
  end
  return out
end
local function Weeks()
  if not (ns.db and ns.state) then return nil end
  ns.db.titleWeeks = type(ns.db.titleWeeks) == "table" and ns.db.titleWeeks or {}
  local t = ns.db.titleWeeks[ns.state.code]
  if type(t) ~= "table" then t = {} ns.db.titleWeeks[ns.state.code] = t end
  return t
end
-- the first time we look in a week, we write down who holds what
function B.SnapTitles()
  if not (ns.state and P.HasSettings(ns.state)) or ns.alt then return end
  local wk = M.WeekIndex(ns.state.settings, U.Now())
  local t = Weeks()
  if not t or wk < 1 or t[wk] then return end
  t[wk] = Holders()
  for k in pairs(t) do if k < wk - 4 then t[k] = nil end end
end
-- the titles that changed hands in week wk: { t (the title), m (new holder), from (old holder or nil) }
local function NewTitles(wk, byGuid, testing)
  local t = Weeks() or {}
  -- who held what when the week began (or, if we didn't look that week, the last time we did)
  local before
  if not testing then
    for k = wk, wk - 4, -1 do if t[k] then before = t[k] break end end
  end
  local after = (not testing and t[wk + 1]) or Holders()
  local out = {}
  for _, title in ipairs(ns.Titles and ns.Titles.LIST or {}) do
    local now = after[title.id]
    if now and not SKIP[title.id] then
      local old = {}
      for _, g in ipairs(before and before[title.id] or {}) do old[g] = true end
      -- one line per title: the new holders (a tie shows the first and how many more)
      local got = {}
      for _, g in ipairs(now) do if byGuid[g] and not old[g] and (before or testing) then got[#got + 1] = byGuid[g] end end
      if #got > 0 then
        local from
        for _, og in ipairs(before and before[title.id] or {}) do if byGuid[og] and not from then from = byGuid[og] end end
        out[#out + 1] = { t = title, m = got[1], more = #got - 1, from = from }
      end
    end
  end
  -- the "first of the patto" ones before the milestones
  table.sort(out, function(a, b)
    local ka, kb = a.t.kind == "top" and 0 or 1, b.t.kind == "top" and 0 or 1
    if ka ~= kb then return ka < kb end
    return a.t.name < b.t.name
  end)
  return out
end

----------------------------------------------------------------------
-- the numbers of a week
----------------------------------------------------------------------
-- the week's piotte of a member: total, from the tombola, from the schedina (winnings - stakes)
local function WeekPiotte(m, wk, list)
  local TB = ns.Tombola
  if not TB then return 0, 0, 0 end
  local sc = TB.Score(m, wk)
  local tomb = sc and sc.points or 0
  local v = TB.VotesOf(m, wk)
  local won, stakes = 0, 0
  if v then
    won = TB.Payout(wk, list, v)
    for _, q in ipairs(TB.QUESTIONS) do if v[q.key] then stakes = stakes + (v["s" .. q.key] or 0) end end
  end
  return tomb + won - stakes, tomb, won - stakes
end

local DEATH = { cascato = "cascato", affogato = "affogato", pischello = "da 'n pischello" }

function B.Data(wk, testing)
  local list = UI.Members()
  local byGuid = {}
  for _, m in ipairs(list) do byGuid[m.guid] = m end
  local now = U.Now()
  local from, to
  if testing or not (ns.Tombola and ns.state and P.HasSettings(ns.state)) then from, to = now - M.WEEK, now + 1
  else from = ns.Tombola.WeekStart(wk) to = from + M.WEEK end
  local d = { wk = wk, list = list }

  d.titles = NewTitles(wk, byGuid, testing)

  -- li ricchi (piotte) and li sordi (gold made in the week)
  local rich, gold = {}, {}
  for _, m in ipairs(list) do
    local week, tomb, bets = WeekPiotte(m, wk, list)
    rich[#rich + 1] = { m = m, total = ns.Tombola and ns.Tombola.TotalOf(m) or 0, week = week, tomb = tomb, bets = bets }
    local g = W(m, wk, "g")
    if g > 0 then gold[#gold + 1] = { m = m, g = g } end
  end
  table.sort(rich, function(a, b) if a.total ~= b.total then return a.total > b.total end return tostring(a.m.name) < tostring(b.m.name) end)
  table.sort(gold, function(a, b) if a.g ~= b.g then return a.g > b.g end return tostring(a.m.name) < tostring(b.m.name) end)
  d.rich, d.gold = rich, gold

  -- er cimitero
  local byKiller, deaths, mine = {}, 0, {}
  for _, m in ipairs(list) do
    deaths = deaths + W(m, wk, "dt")
    mine[m.guid] = {}
    for _, g in ipairs(m.rip or {}) do
      if (g.at or 0) >= from and (g.at or 0) < to and not U.IsBattlegroundZone(g.z) then
        table.insert(mine[m.guid], g)
        if g.by and g.k ~= "pvp" and not DEATH[g.k] then byKiller[g.by] = (byKiller[g.by] or 0) + 1 end
      end
    end
  end
  local killer, kills
  for k, n in pairs(byKiller) do if not kills or n > kills or (n == kills and k < killer) then killer, kills = k, n end end
  local most, mostN = Leader(list, function(x) return W(x, wk, "dt") end)
  -- er più scemo: the most silly deaths (falling, drowning, killed by a much lower one), with his last words
  local silly, sillyN = Leader(list, function(x)
    local n = 0
    for _, g in ipairs(mine[x.guid]) do if DEATH[g.k] then n = n + 1 end end
    return math.max(n, W(x, wk, "em"))
  end)
  local kinds, words = {}, nil
  if silly then
    local cnt = {}
    for _, g in ipairs(mine[silly.guid]) do if DEATH[g.k] then cnt[g.k] = (cnt[g.k] or 0) + 1 end end
    for _, k in ipairs({ "cascato", "affogato", "pischello" }) do if cnt[k] then kinds[#kinds + 1] = cnt[k] .. " " .. DEATH[k] end end
    local last
    for _, g in ipairs(silly.rip or {}) do if g.w and (not last or (g.at or 0) > (last.at or 0)) then last = g end end
    words = last and last.w
  end
  d.dead = { total = deaths, most = most, mostN = mostN, silly = silly, sillyN = sillyN, kinds = kinds, words = words,
    killer = killer, kills = kills }

  -- le mejo tombole: only the best three
  local cards = {}
  local played = 0
  if ns.Tombola then
    for _, m in ipairs(list) do
      local sc = ns.Tombola.Score(m, wk)
      if sc and sc.points > 0 then cards[#cards + 1] = { m = m, sc = sc } played = played + 1 end
    end
    table.sort(cards, function(a, b) if a.sc.points ~= b.sc.points then return a.sc.points > b.sc.points end return tostring(a.m.name) < tostring(b.m.name) end)
  end
  while #cards > 3 do table.remove(cards) end
  d.cards, d.played = cards, played

  -- er Colosseo: i duelli a la gogna de la settimana, chi c'è finito, i duelli tutti
  local gogne, fought = {}, 0
  if ns.Sfide and ns.Sfide.Series then
    local ok, series = pcall(ns.Sfide.Series)
    for _, s in ipairs(ok and series or {}) do
      if byGuid[s.a] and byGuid[s.b] then
        for _, x in ipairs(s.duels or {}) do if (x.at or 0) >= from and (x.at or 0) < to then fought = fought + 1 end end
        if s.state == "chiusa" and (s.te or 0) >= from and (s.te or 0) < to and byGuid[s.w] and byGuid[s.l] then
          gogne[#gogne + 1] = { w = byGuid[s.w], l = byGuid[s.l], n = #s.duels, pena = s.pena and ns.Sfide.PENE[s.pena], te = s.te }
        end
      end
    end
    table.sort(gogne, function(a, b) return a.te > b.te end)
  end
  local bully, bullyN = Leader(list, function(x) return W(x, wk, "dw") end)
  local bag, bagN = Leader(list, function(x) return W(x, wk, "dl") end)
  local duels = 0
  for _, m in ipairs(list) do duels = duels + W(m, wk, "dw") end
  -- er mejo a duello: the best record of the week, with at least three duels
  local best, bestR
  for _, m in ipairs(list) do
    local w, l = W(m, wk, "dw"), W(m, wk, "dl")
    if w + l >= 3 then
      local r = (w + 1) / (w + l + 2)
      if not bestR or r > bestR or (r == bestR and w > W(best, wk, "dw")) then best, bestR = m, r end
    end
  end
  d.arena = { gogne = gogne, fought = fought, bully = bully, bullyN = bullyN, bully2 = bully and W(bully, wk, "dl") or 0,
    bag = bag, bagN = bagN, bag2 = bag and W(bag, wk, "dw") or 0, duels = duels,
    best = best ~= bully and best or nil, bestW = best and W(best, wk, "dw") or 0, bestL = best and W(best, wk, "dl") or 0 }

  -- li primati de la settimana
  local prim = {}
  local function lead(label, key, fmt)
    local m, n = Leader(list, function(x) return W(x, wk, key) end)
    if m then prim[#prim + 1] = { label = label, m = m, v = fmt and fmt(n) or tostring(n) } end
  end
  lead("Più quest", "q")
  lead("Più rari", "rk")
  lead("Più dungeon", "dg")
  lead("Più ore giocate", "pt", function(n) return U.Hours(n / 3600) end)
  lead("Più ore in compagnia", "gp", function(n) return U.Hours(n / 3600) end)
  lead("Più mostri famosi", "nk")
  d.prim = prim

  -- er PvP: pe' strada and in BG apart, and who got killed by players out in the world
  local pvp = { hw = 0, hb = 0, bw = 0, bl = 0 }
  for _, m in ipairs(list) do
    pvp.hw = pvp.hw + W(m, wk, "hw") pvp.hb = pvp.hb + W(m, wk, "hb")
    pvp.bw = pvp.bw + W(m, wk, "bw") pvp.bl = pvp.bl + W(m, wk, "bl")
  end
  pvp.street, pvp.streetN = Leader(list, function(x) return W(x, wk, "hw") end)
  pvp.legion, pvp.legionN = Leader(list, function(x) return W(x, wk, "hb") end)
  pvp.bgw, pvp.bgwN = Leader(list, function(x) return W(x, wk, "bw") end)
  pvp.victim, pvp.victimN = Leader(list, function(x)
    local n = 0
    for _, g in ipairs(mine[x.guid]) do if g.k == "pvp" then n = n + 1 end end
    return n
  end)
  d.pvp = pvp

  -- ar Botteghino, oltre tombola e schedina: the Colosseo, the sfottò and the faccioni (from the lines each one
  -- shares of his scontrini)
  local net, sfoBy, sfoOn, fcBy, fcOn = {}, {}, {}, {}, {}
  for _, m in ipairs(list) do
    local lines = ns.Tombola and ns.Tombola.LedgerOf(m) or {}
    for _, x in ipairs(lines) do
      if (x.at or 0) >= from and (x.at or 0) < to then
        if x.k == "sb" and x.g ~= nil then net[m.guid] = (net[m.guid] or 0) + (x.g or 0) - (x.s or 0) end
        if x.k == "fo" and x.o then
          sfoBy[m.guid] = (sfoBy[m.guid] or 0) + 1
          sfoOn[x.o] = (sfoOn[x.o] or 0) + 1
        end
        if x.k == "fc" and x.o then
          fcBy[m.guid] = (fcBy[m.guid] or 0) + 1
          fcOn[x.o] = (fcOn[x.o] or 0) + 1
        end
      end
    end
  end
  local shop = {}
  shop.bestBet, shop.bestBetN = Leader(list, function(x) return net[x.guid] or 0 end)
  shop.worstBet, shop.worstBetN = Leader(list, function(x) return -(net[x.guid] or 0) end)
  shop.mocker, shop.mockerN = Leader(list, function(x) return sfoBy[x.guid] or 0 end)
  shop.mocked, shop.mockedN = Leader(list, function(x) return sfoOn[x.guid] or 0 end)
  shop.facer, shop.facerN = Leader(list, function(x) return fcBy[x.guid] or 0 end)
  shop.faced, shop.facedN = Leader(list, function(x) return fcOn[x.guid] or 0 end)
  d.shop = shop

  -- la schedina
  local qs = {}
  if ns.Tombola then
    local TB = ns.Tombola
    local win = TB.Winners(wk, list)
    for _, q in ipairs(TB.Questions(wk)) do
      local names, val = {}, 0
      for _, m in ipairs(list) do
        if win[q.key][m.guid] then
          names[#names + 1] = Colored(m)
          local st = q.stat
          if type(st) == "table" then val = 0 for _, k in ipairs(st) do val = val + W(m, wk, k) end else val = W(m, wk, st) end
        end
      end
      qs[#qs + 1] = { text = q.text, names = names, val = val, stat = q.stat }
    end
  end
  d.questions = qs
  local right, pollo, polloN = {}, nil, 0
  for _, r in ipairs(rich) do
    if r.bets > 0 then right[#right + 1] = r end
    if r.bets < polloN then pollo, polloN = r.m, r.bets end
  end
  table.sort(right, function(a, b) return a.bets > b.bets end)
  d.right, d.pollo, d.polloN = right, pollo, -polloN

  -- the headline: the biggest story of the week, with its own icon
  local stories = {}
  local function story(score, icon, title, sub) stories[#stories + 1] = { score = score, icon = icon, title = title, sub = sub } end
  local function From(r)
    local parts = {}
    if r.tomb > 0 then parts[#parts + 1] = "+" .. r.tomb .. " da la tombola" end
    if r.bets ~= 0 then parts[#parts + 1] = (r.bets > 0 and "+" or "") .. r.bets .. " da la schedina" end
    return #parts > 0 and (table.concat(parts, ", ") .. ".") or nil
  end
  for _, c in ipairs(cards) do
    if c.sc.full then story(100 + c.sc.points, "INV_Misc_Ticket_Tarot_Stack_01", "TOMBOLA! " .. Short(c.m) .. " ha chiuso tutta la cartella",
      "Tutte e 9 le caselle: +" .. ns.Tombola.Piotte(c.sc.points) .. " da la tombola.") end
  end
  local top
  for _, r in ipairs(rich) do if r.week > 0 and (not top or r.week > top.week) then top = r end end
  if top then story(50 + top.week, "INV_Misc_Bag_10_Red", Short(top.m) .. " ha guadagnato più piotte de tutti: +" .. top.week, From(top)) end
  for _, g in ipairs(gogne) do
    story(70, g.pena and g.pena.icon and g.pena.icon:gsub("^Interface\\Icons\\", "") or "Ability_Warrior_Challange", Short(g.l) .. " è finito a la gogna",
      "L'ha battuto " .. Short(g.w) .. (g.n == 3 and " a la bella" or g.n == 2 and " a la rivincita" or "") .. (g.pena and (", e j'ha dato " .. g.pena.name:lower()) or "") .. ".")
  end
  if silly then story(60 + sillyN, "INV_Misc_Bone_HumanSkull_01", Short(silly) .. " è er più scemo de la settimana: " .. Plural(sillyN, "morte", "morti") .. " da scemo",
    words and ("Ultime parole: \"" .. words .. "\"") or (#kinds > 0 and (table.concat(kinds, ", ") .. ".") or nil)) end
  local fast, fastN = Leader(list, function(x) return W(x, wk, "ding") end)
  if fast then story(40 + fastN, "Ability_Rogue_Sprint", Short(fast) .. " è salito de più: +" .. Plural(fastN, "livello", "livelli"),
    fast.lv and ("Mo' è livello " .. fast.lv .. ".") or nil) end
  if pvp.street and pvp.streetN >= 5 then story(35 + pvp.streetN, "Ability_DualWield", Short(pvp.street) .. " ha fatto 'na strage pe' strada: " .. pvp.streetN .. " ammazzati",
    pvp.legion and (Short(pvp.legion) .. " invece in BG: " .. pvp.legionN .. ".") or nil) end
  if shop.bestBet and shop.bestBetN >= 20 then story(45 + shop.bestBetN, "Ability_Warrior_Challange", Short(shop.bestBet) .. " ha sbancato er Colosseo: +" .. shop.bestBetN .. " piotte",
    "Puntando sui duelli giusti.") end
  table.sort(stories, function(a, b) return a.score > b.score end)
  d.head = stories[1]

  -- your own week, in one line
  local me = byGuid[ns.recordGuid]
  if me then
    local rank, mineR
    for i, r in ipairs(rich) do if r.m == me then rank, mineR = i, r end end
    local parts = {}
    if rank then parts[#parts + 1] = "In tutto " .. Signed(mineR.week) .. " " .. Coin() .. ", " .. rank .. "° de " .. #rich end
    parts[#parts + 1] = "+" .. Plural(W(me, wk, "ding"), "livello", "livelli")
    parts[#parts + 1] = (ns.Money and ns.Money(W(me, wk, "g"), true) or "0") .. " fatti"
    parts[#parts + 1] = Plural(W(me, wk, "dt"), "morte", "morti")
    if W(me, wk, "dw") + W(me, wk, "dl") > 0 then parts[#parts + 1] = "duelli " .. W(me, wk, "dw") .. "-" .. W(me, wk, "dl") end
    if W(me, wk, "hw") + W(me, wk, "hb") > 0 then parts[#parts + 1] = W(me, wk, "hw") .. " ammazzati pe' strada, " .. W(me, wk, "hb") .. " in BG" end
    d.you = table.concat(parts, ", ")
    -- la tombola mia, la schedina mia, and every other piotta of the week (sfide, taje, gufate, Colosseo, sfottò)
    local TB = ns.Tombola
    local my = { sc = TB and TB.Score(me, wk), bets = {}, rest = {}, week = mineR and mineR.week or 0, rank = rank, of = #rich }
    local v = TB and TB.VotesOf(me, wk)
    if TB then
      local _, _, lines = TB.Payout(wk, list, v or {})
      for _, x in ipairs(lines) do
        local pick = v and v[x.q.key] and byGuid[v[x.q.key]]
        my.bets[#my.bets + 1] = { text = x.q.text, pick = pick, stake = x.mine, got = x.got, nobody = x.nobody, right = pick and x.winners[pick.guid] }
      end
      local KIND = { sf = "Sfide", tj = "Taje", tjw = "Taje", gu = "Gufate", gut = "Gufate", sb = "Ar Colosseo", fo = "Sfottò", fc = "Faccioni" }
      local ORDER = { "Sfide", "Taje", "Gufate", "Ar Colosseo", "Sfottò", "Faccioni" }
      local sum, open = {}, {}
      for _, x in ipairs(TB.Ledger()) do
        local k = KIND[x.k]
        if k and (x.at or 0) >= from and (x.at or 0) < to then
          if x.g == nil then open[k] = (open[k] or 0) + 1 sum[k] = sum[k] or 0
          else sum[k] = (sum[k] or 0) + (x.g or 0) - (x.s or 0) end
        end
      end
      for _, k in ipairs(ORDER) do if sum[k] then my.rest[#my.rest + 1] = { k = k, net = sum[k], open = open[k] } end end
    end
    d.my = my
  end
  return d
end

----------------------------------------------------------------------
-- the window: three columns
----------------------------------------------------------------------
local bull
local COL, GAP, LEFT = 306, 8, 20
local WIDTH = LEFT * 2 + COL * 3 + GAP * 2
local HEIGHT = 792

local function Title(box, text)
  local t = H.Text(box, "GameFontNormal", text, 260)
  t:SetPoint("TOPLEFT", 12, -10)
  return t
end
local function Icon(parent, size)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size, size)
  t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  return t
end
local function Corner(box, icon)
  local t = Icon(box, 16)
  t:SetTexture(ICON .. icon)
  t:SetPoint("TOPRIGHT", -12, -9)
  return t
end
-- a box with n lines of small text
local function Lines(box, n, w)
  local out = {}
  for i = 1, n do
    local l = H.Text(box, "GameFontHighlightSmall", "", w or (COL - 28))
    l:SetPoint("TOPLEFT", 14, -30 - (i - 1) * 15)
    if l.SetWordWrap then l:SetWordWrap(false) end
    out[i] = l
  end
  return out
end
-- a ranking with bars: name, bar, value (and a right column)
local function Ranking(box, n, barMax)
  local out = {}
  for i = 1, n do
    local r = { max = barMax }
    local y = -30 - (i - 1) * 18
    r.name = H.Text(box, "GameFontHighlightSmall", "", 88)
    r.name:SetPoint("TOPLEFT", 14, y - 2)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.bar = box:CreateTexture(nil, "ARTWORK")
    r.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.bar:SetHeight(10)
    r.bar:SetPoint("TOPLEFT", 104, y - 3)
    r.val = H.Text(box, "GameFontHighlightSmall", "", 70)
    r.right = H.Text(box, "GameFontHighlightSmall", "", 50, "RIGHT")
    r.right:SetPoint("TOPRIGHT", -14, y - 2)
    out[i] = r
  end
  return out
end
local function Bar(r, frac, first, gold)
  r.bar:SetWidth(math.max(2, math.floor(r.max * frac)))
  r.bar:Show()
  if first then r.bar:SetVertexColor(1, 0.82, 0) elseif gold then r.bar:SetVertexColor(0.75, 0.6, 0.2) else r.bar:SetVertexColor(0.6, 0.6, 0.6) end
  r.val:ClearAllPoints()
  r.val:SetPoint("LEFT", r.bar, "RIGHT", 6, 0)
end

local function Build()
  bull = CreateFrame("Frame", "ErPattoBulletin", UIParent, "BackdropTemplate")
  bull:SetSize(WIDTH, HEIGHT)
  bull:SetPoint("CENTER", 0, 0)
  bull:SetClampedToScreen(true)
  bull:SetFrameStrata("DIALOG")
  bull:SetToplevel(true)
  bull:EnableMouse(true)
  bull:SetMovable(true)
  bull:RegisterForDrag("LeftButton")
  bull:SetScript("OnDragStart", bull.StartMoving)
  bull:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() if self.SetUserPlaced then pcall(self.SetUserPlaced, self, false) end end)
  H.Chrome(bull)
  if bull.SetBackdropColor then bull:SetBackdropColor(0, 0, 0, 0) end
  bull.title = H.DialogHeader(bull, "", 300)
  H.CloseX(bull)
  local x = { LEFT, LEFT + COL + GAP, LEFT + 2 * (COL + GAP) }

  -- the headline, and your week
  local hd = H.Box(bull, WIDTH - 2 * LEFT, 52)
  hd:SetPoint("TOPLEFT", LEFT, -30)
  bull.face = Icon(hd, 40)
  bull.face:SetPoint("LEFT", 12, 0)
  bull.head = H.Text(hd, "GameFontNormal", "", WIDTH - 120)
  bull.head:SetPoint("TOPLEFT", 64, -12)
  if bull.head.SetWordWrap then bull.head:SetWordWrap(false) end
  bull.headSub = H.Text(hd, "GameFontHighlightSmall", "", WIDTH - 120)
  bull.headSub:SetPoint("TOPLEFT", 64, -30)
  if bull.headSub.SetWordWrap then bull.headSub:SetWordWrap(false) end
  bull.face:SetSize(34, 34)

  -- la settimana tua: my card, my schedina, the rest of my piotte
  local me = H.Box(bull, WIDTH - 2 * LEFT, 100)
  me:SetPoint("TOPLEFT", LEFT, -88)
  Title(me, "La settimana tua")
  bull.you = H.Text(me, "GameFontHighlightSmall", "", 520, "RIGHT")
  bull.you:SetPoint("TOPRIGHT", -14, -12)
  bull.myCells = {}
  for i = 1, 9 do
    local cell = me:CreateTexture(nil, "ARTWORK")
    cell:SetTexture("Interface\\Buttons\\UI-Quickslot2") cell:SetTexCoord(12 / 64, 52 / 64, 12 / 64, 52 / 64)
    cell:SetSize(18, 18)
    cell:SetPoint("TOPLEFT", 16 + ((i - 1) % 3) * 17, -30 - math.floor((i - 1) / 3) * 17)
    local check = me:CreateTexture(nil, "OVERLAY")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetSize(18, 18)
    check:SetPoint("CENTER", cell)
    bull.myCells[i] = { box = cell, check = check }
  end
  bull.myTomb = {}
  for i = 1, 3 do
    local l = H.Text(me, "GameFontHighlightSmall", "", 150)
    l:SetPoint("TOPLEFT", 80, -32 - (i - 1) * 15)
    bull.myTomb[i] = l
  end
  bull.myBets = {}
  for i = 1, 4 do
    local l = H.Text(me, "GameFontHighlightSmall", "", 400)
    l:SetPoint("TOPLEFT", 240, -32 - (i - 1) * 15)
    if l.SetWordWrap then l:SetWordWrap(false) end
    bull.myBets[i] = l
  end
  bull.myRest = {}
  for i = 1, 4 do
    local l = H.Text(me, "GameFontHighlightSmall", "", 250)
    l:SetPoint("TOPLEFT", 670, -32 - (i - 1) * 15)
    bull.myRest[i] = l
  end

  -- row 1: li titoli, li ricchi, li sordi
  local y1, h1 = -196, 166
  local ti = H.Box(bull, COL, h1)
  ti:SetPoint("TOPLEFT", x[1], y1)
  Title(ti, "Li titoli de la settimana")
  bull.titles = {}
  for i = 1, 7 do
    local r = {}
    local y = -30 - (i - 1) * 18
    r.name = H.Text(ti, "GameFontNormalSmall", "", 140)
    r.name:SetPoint("TOPLEFT", 14, y - 2)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.who = H.Text(ti, "GameFontHighlightSmall", "", 70)
    r.who:SetPoint("TOPLEFT", 158, y - 2)
    r.from = H.Text(ti, "GameFontDisableSmall", "", 70, "RIGHT")
    r.from:SetPoint("TOPRIGHT", -14, y - 2)
    -- the mouse over a title tells what it is
    r.hit = CreateFrame("Frame", nil, ti)
    r.hit:SetSize(COL - 28, 16)
    r.hit:SetPoint("TOPLEFT", 12, y)
    r.hit:EnableMouse(true)
    r.hit:SetScript("OnEnter", function(self) if self.t then H.Tip(self, { self.t.name, self.t.desc }) end end)
    r.hit:SetScript("OnLeave", H.HideTip)
    bull.titles[i] = r
  end

  local ri = H.Box(bull, COL, h1)
  ri:SetPoint("TOPLEFT", x[2], y1)
  Title(ri, "Le piotte")
  local rh = H.Text(ri, "GameFontDisableSmall", "Settimana", 70, "RIGHT") rh:SetPoint("TOPRIGHT", -14, -13)
  bull.rich = Ranking(ri, 7, 92)

  local so = H.Box(bull, COL, h1)
  so:SetPoint("TOPLEFT", x[3], y1)
  Title(so, "Li ricchi")
  -- the money made in the week (not what they have): copper and silver count too
  local sh = H.Text(so, "GameFontDisableSmall", "fatti 'sta settimana", 120, "RIGHT") sh:SetPoint("TOPRIGHT", -34, -13)
  Corner(so, "INV_Misc_Coin_01")
  bull.gold = Ranking(so, 7, 110)

  -- row 2: er cimitero, er Colosseo, le mejo tombole
  local y2, h2 = -370, 132
  local ci = H.Box(bull, COL, h2)
  ci:SetPoint("TOPLEFT", x[1], y2)
  Title(ci, "Er cimitero")
  Corner(ci, "INV_Misc_Bone_HumanSkull_01")
  bull.dead = Lines(ci, 6)

  local co = H.Box(bull, COL, h2)
  co:SetPoint("TOPLEFT", x[2], y2)
  Title(co, "Er Colosseo")
  Corner(co, "Ability_Warrior_Challange")
  bull.arena = Lines(co, 6)

  local tb = H.Box(bull, COL, h2)
  tb:SetPoint("TOPLEFT", x[3], y2)
  Title(tb, "Le mejo tombole")
  Corner(tb, "INV_Misc_Ticket_Tarot_Stack_01")
  bull.cards = {}
  for c = 1, 3 do
    local k = { cells = {} }
    local left = 24 + (c - 1) * 94
    for i = 1, 9 do
      local cell = tb:CreateTexture(nil, "ARTWORK")
      cell:SetTexture("Interface\\Buttons\\UI-Quickslot2") cell:SetTexCoord(12 / 64, 52 / 64, 12 / 64, 52 / 64)
      cell:SetSize(16, 16)
      cell:SetPoint("TOPLEFT", left + ((i - 1) % 3) * 15, -30 - math.floor((i - 1) / 3) * 15)
      local check = tb:CreateTexture(nil, "OVERLAY")
      check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      check:SetSize(16, 16)
      check:SetPoint("CENTER", cell)
      k.cells[i] = { box = cell, check = check }
    end
    k.name = H.Text(tb, "GameFontHighlightSmall", "", 86)
    k.name:SetPoint("TOPLEFT", left - 6, -78)
    k.pts = H.Text(tb, "GameFontNormalSmall", "", 86)
    k.pts:SetPoint("TOPLEFT", left - 6, -91)
    bull.cards[c] = k
  end
  bull.tombLine = H.Text(tb, "GameFontDisableSmall", "", COL - 28)
  bull.tombLine:SetPoint("TOPLEFT", 14, -104)
  if bull.tombLine.SetWordWrap then bull.tombLine:SetWordWrap(false) end

  -- row 3: li primati, er PvP, ar Botteghino (Colosseo, sfottò, faccioni)
  local y3 = -508
  local pr = H.Box(bull, COL, h2)
  pr:SetPoint("TOPLEFT", x[1], y3)
  Title(pr, "Li primati")
  Corner(pr, "INV_Misc_Book_09")
  bull.prim = {}
  for i = 1, 6 do
    local r = {}
    local y = -30 - (i - 1) * 15
    r.label = H.Text(pr, "GameFontNormalSmall", "", 130) r.label:SetPoint("TOPLEFT", 14, y)
    r.who = H.Text(pr, "GameFontHighlightSmall", "", 100) r.who:SetPoint("TOPLEFT", 146, y)
    if r.who.SetWordWrap then r.who:SetWordWrap(false) end
    r.val = H.Text(pr, "GameFontHighlightSmall", "", 60, "RIGHT") r.val:SetPoint("TOPRIGHT", -14, y)
    bull.prim[i] = r
  end
  local pv = H.Box(bull, COL, h2)
  pv:SetPoint("TOPLEFT", x[2], y3)
  Title(pv, "Er PvP")
  Corner(pv, "Ability_DualWield")
  bull.pvp = Lines(pv, 6)
  local bo = H.Box(bull, COL, h2)
  bo:SetPoint("TOPLEFT", x[3], y3)
  Title(bo, "Ar Botteghino")
  Corner(bo, "INV_Misc_Bag_10_Red")
  bull.shop = Lines(bo, 6)

  -- row 4: la schedina, all across
  local sc = H.Box(bull, WIDTH - 2 * LEFT, 104)
  sc:SetPoint("TOPLEFT", LEFT, -646)
  Title(sc, "La schedina")
  Corner(sc, "INV_Misc_Note_06")
  bull.bets = Lines(sc, 4, (WIDTH - 2 * LEFT) / 2 - 24)
  bull.bets2 = {}
  for i = 1, 4 do
    local l = H.Text(sc, "GameFontHighlightSmall", "", (WIDTH - 2 * LEFT) / 2 - 24)
    l:SetPoint("TOPLEFT", (WIDTH - 2 * LEFT) / 2 + 10, -30 - (i - 1) * 15)
    if l.SetWordWrap then l:SetWordWrap(false) end
    bull.bets2[i] = l
  end

  bull.foot = H.Text(bull, "GameFontNormalSmall", "", 520)
  bull.foot:SetPoint("BOTTOMLEFT", 26, 24)
  bull.ok = H.Btn(bull, "Daje", 110, function() bull:Hide() end)
  bull.ok:SetPoint("BOTTOMRIGHT", -24, 16)
  if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoBulletin") end
end

local function Fill(d, testing)
  bull.title:SetText("Er Bollettino, settimana " .. d.wk .. (testing and " |cffff8000(prova)|r" or ""))

  -- headline
  local h = d.head
  if h then
    bull.face:SetTexture(ICON .. h.icon) bull.face:Show()
    bull.head:SetText(h.title)
    bull.headSub:SetText(h.sub or "")
  else
    bull.face:Hide()
    bull.head:SetText("Settimana tranquilla")
    bull.headSub:SetText("Nun s'è mosso nessuno.")
  end
  bull.you:SetText(d.you or "")
  local my = d.my or { bets = {}, rest = {} }
  local sc = my.sc
  for i, cell in ipairs(bull.myCells) do cell.check:SetShown(sc and sc.done[i] and true or false) end
  local tl = {}
  if sc then
    tl[1] = "Tombola: " .. (sc.full and (GREEN .. "TOMBOLA!|r ") or "") .. GOLD .. "+" .. sc.points .. "|r " .. Coin()
    tl[2] = GREY .. Plural(sc.cells, "casella", "caselle") .. ", " .. Plural(sc.lines, "terno", "terni") .. "|r"
  else tl[1] = GREY .. "Nessuna cartella.|r" end
  for i, l in ipairs(bull.myTomb) do l:SetText(tl[i] or "") end
  local bl = {}
  local played = false
  for _, b in ipairs(my.bets) do
    if b.pick then
      played = true
      local res = b.nobody and (GREY .. "nessuno, ridate|r") or b.right and (GREEN .. "+" .. b.got .. "|r " .. Coin()) or (RED .. "-" .. b.stake .. "|r " .. Coin())
      bl[#bl + 1] = b.text .. " " .. Colored(b.pick) .. GREY .. " (" .. b.stake .. ")|r  " .. res
    end
  end
  if not played then bl[1] = GREY .. "La schedina nun l'hai giocata.|r" end
  for i, l in ipairs(bull.myBets) do l:SetText(bl[i] or "") end
  local rl = {}
  for _, x in ipairs(my.rest) do
    rl[#rl + 1] = x.k .. ": " .. Signed(x.net) .. " " .. Coin() .. (x.open and (GREY .. " (" .. x.open .. " in ballo)|r") or "")
  end
  if #rl == 0 then rl[1] = GREY .. "Gnente sfide, taje o gufate.|r" end
  for i, l in ipairs(bull.myRest) do l:SetText(rl[i] or "") end

  -- li titoli
  for i, r in ipairs(bull.titles) do
    local x = d.titles[i]
    if x then
      r.name:SetText(x.t.name) r.who:SetText(Colored(x.m) .. (x.more > 0 and (GREY .. " +" .. x.more .. "|r") or ""))
      r.from:SetText(x.from and ("da " .. Short(x.from)) or "")
      r.hit.t = x.t
    else
      r.name:SetText(i == 1 and (GREY .. "Nessun titolo cambiato de mano.|r") or "") r.who:SetText("") r.from:SetText("") r.hit.t = nil
    end
  end
  if #d.titles > #bull.titles then bull.titles[#bull.titles].from:SetText(GREY .. "e artri " .. (#d.titles - #bull.titles + 1) .. "|r") end

  -- li ricchi
  local max = 1
  for _, x in ipairs(d.rich) do max = math.max(max, x.total) end
  for i, r in ipairs(bull.rich) do
    local x = d.rich[i]
    if x then
      r.name:SetText(i .. ". " .. Colored(x.m))
      Bar(r, x.total / max, i == 1)
      r.val:SetText(WHITE .. x.total .. "|r " .. Coin())
      r.right:SetText(Signed(x.week))
    else
      r.name:SetText("") r.bar:Hide() r.val:SetText("") r.right:SetText("")
    end
  end

  -- li sordi
  local gmax = d.gold[1] and d.gold[1].g or 1
  for i, r in ipairs(bull.gold) do
    local x = d.gold[i]
    if x then
      r.name:SetText(i .. ". " .. Colored(x.m))
      Bar(r, x.g / gmax, i == 1, true)
      r.val:SetText(WHITE .. "+|r" .. (ns.Money and ns.Money(x.g) or tostring(x.g)))
      r.right:SetText("")
    else
      r.name:SetText(i == 1 and (GREY .. "Nessuno ha fatto manco 'n rame.|r") or "") r.bar:Hide() r.val:SetText("") r.right:SetText("")
    end
  end

  -- er cimitero
  local dd, lines = d.dead, {}
  if dd.total == 0 then lines[1] = GREEN .. "Nessun morto. Settimana da santi.|r"
  else
    lines[#lines + 1] = "Morti in tutto: " .. WHITE .. dd.total .. "|r"
    if dd.most then lines[#lines + 1] = "Er più morto: " .. Colored(dd.most) .. " " .. GREY .. Plural(dd.mostN, "vorta", "vorte") .. "|r" end
    if dd.silly then
      lines[#lines + 1] = "Er più scemo: " .. Colored(dd.silly) .. " " .. GREY .. Plural(dd.sillyN, "morte", "morti") .. " da scemo" ..
        (#dd.kinds > 0 and (" (" .. table.concat(dd.kinds, ", ") .. ")") or "") .. "|r"
      if dd.words then lines[#lines + 1] = GREY .. "Ultime parole sue: |r" .. WHITE .. "\"" .. dd.words .. "\"|r" end
    end
    if dd.killer then lines[#lines + 1] = "Er boia: " .. RED .. dd.killer .. "|r " .. GREY .. Plural(dd.kills, "vittima", "vittime") .. "|r" end
  end
  for i, l in ipairs(bull.dead) do l:SetText(lines[i] or "") end

  -- er Colosseo
  local a, al = d.arena, {}
  if a.fought > 0 or #a.gogne > 0 then
    al[#al + 1] = "Duelli a la gogna: " .. WHITE .. a.fought .. "|r, " .. GREY .. "a la gogna ce so' finiti " .. #a.gogne .. "|r"
    for i = 1, math.min(2, #a.gogne) do
      local g = a.gogne[i]
      al[#al + 1] = Colored(g.w) .. " ha messo a la gogna " .. Colored(g.l) .. GREY .. (g.pena and (", " .. g.pena.name:lower()) or "") ..
        (g.n == 3 and ", a la bella" or g.n == 2 and ", a la rivincita" or "") .. "|r"
    end
    if #a.gogne > 2 then al[#al] = al[#al] .. GREY .. " (e artre " .. (#a.gogne - 2) .. ")|r" end
  else
    al[#al + 1] = GREY .. "Nessun duello a la gogna 'sta settimana.|r"
  end
  if a.bully then al[#al + 1] = "Er bullo: " .. Colored(a.bully) .. " " .. GREY .. Plural(a.bullyN, "duello vinto", "duelli vinti") .. " (" .. a.bullyN .. "-" .. a.bully2 .. ")|r" end
  if a.best then al[#al + 1] = "Er mejo a duello: " .. Colored(a.best) .. " " .. GREY .. a.bestW .. "-" .. a.bestL .. "|r" end
  if a.bag then al[#al + 1] = "Er sacco da boxe: " .. Colored(a.bag) .. " " .. GREY .. Plural(a.bagN, "duello perso", "duelli persi") .. " (" .. a.bag2 .. "-" .. a.bagN .. ")|r" end
  if a.duels > 0 and #al < 6 then al[#al + 1] = GREY .. "Duelli in tutto 'sta settimana: " .. a.duels .. "|r" end
  for i, l in ipairs(bull.arena) do l:SetText(al[i] or "") end

  -- li primati
  for i, r in ipairs(bull.prim) do
    local x = d.prim[i]
    if x then r.label:SetText(x.label) r.who:SetText(Colored(x.m)) r.val:SetText(WHITE .. x.v .. "|r")
    else r.label:SetText(i == 1 and (GREY .. "Nessuno ha fatto gnente.|r") or "") r.who:SetText("") r.val:SetText("") end
  end

  -- er PvP: pe' strada and in BG apart
  local pv, pl = d.pvp, {}
  if pv.hw + pv.hb + pv.bw + pv.bl == 0 and not pv.victim then pl[1] = GREY .. "Gnente PvP 'sta settimana.|r"
  else
    pl[#pl + 1] = "Ammazzati pe' strada: " .. WHITE .. pv.hw .. "|r, in BG: " .. WHITE .. pv.hb .. "|r"
    if pv.street then pl[#pl + 1] = "Er più attaccabrighe: " .. Colored(pv.street) .. " " .. GREY .. pv.streetN .. " pe' strada|r" end
    if pv.legion then pl[#pl + 1] = "Er legionario: " .. Colored(pv.legion) .. " " .. GREY .. pv.legionN .. " in BG|r" end
    if pv.bw + pv.bl > 0 then pl[#pl + 1] = "BG: " .. GREEN .. pv.bw .. " vinte|r, " .. RED .. pv.bl .. " perse|r" end
    if pv.bgw then pl[#pl + 1] = "Er più vincente in BG: " .. Colored(pv.bgw) .. " " .. GREY .. Plural(pv.bgwN, "vinta", "vinte") .. "|r" end
    if pv.victim then pl[#pl + 1] = "Er più ammazzato pe' strada: " .. Colored(pv.victim) .. " " .. GREY .. Plural(pv.victimN, "vorta", "vorte") .. "|r" end
  end
  for i, l in ipairs(bull.pvp) do l:SetText(pl[i] or "") end

  -- ar Botteghino: the Colosseo, the sfottò, the faccioni
  local sh, sl = d.shop, {}
  if sh.bestBet then sl[#sl + 1] = "Er mago der Colosseo: " .. Colored(sh.bestBet) .. " " .. GREEN .. "+" .. sh.bestBetN .. "|r " .. Coin() end
  if sh.worstBet then sl[#sl + 1] = "Er pollo der Colosseo: " .. Colored(sh.worstBet) .. " " .. RED .. "-" .. sh.worstBetN .. "|r " .. Coin() end
  if sh.mocker then sl[#sl + 1] = "Er più sfottente: " .. Colored(sh.mocker) .. " " .. GREY .. Plural(sh.mockerN, "sfottò", "sfottò") .. "|r" end
  if sh.mocked then sl[#sl + 1] = "Er più sfottuto: " .. Colored(sh.mocked) .. " " .. GREY .. Plural(sh.mockedN, "vorta", "vorte") .. "|r" end
  if sh.facer then sl[#sl + 1] = "Er più faccia tosta: " .. Colored(sh.facer) .. " " .. GREY .. Plural(sh.facerN, "faccione", "faccioni") .. " mannati|r" end
  if sh.faced then sl[#sl + 1] = "Er più accecato: " .. Colored(sh.faced) .. " " .. GREY .. Plural(sh.facedN, "faccione", "faccioni") .. "|r" end
  if #sl == 0 then sl[1] = GREY .. "Gnente puntate, sfottò o faccioni.|r" end
  for i, l in ipairs(bull.shop) do l:SetText(sl[i] or "") end

  -- le mejo tombole
  for c, k in ipairs(bull.cards) do
    local x = d.cards[c]
    for i, cell in ipairs(k.cells) do
      cell.box:SetShown(x ~= nil)
      cell.check:SetShown(x ~= nil and x.sc.done[i] and true or false)
    end
    if x then
      k.name:SetText(c .. ". " .. Colored(x.m))
      k.pts:SetText(x.sc.full and (GREEN .. "TOMBOLA!|r") or ("+" .. x.sc.points .. " " .. Coin() .. (x.sc.lines > 0 and (" " .. GREY .. Plural(x.sc.lines, "linea", "linee") .. "|r") or "")))
    else
      k.name:SetText(c == 1 and (GREY .. "Gnente caselle fatte.|r") or "") k.pts:SetText("")
    end
  end
  bull.tombLine:SetText(#d.list > 0 and (GREY .. "Cartelle co' armeno 'na casella: " .. d.played .. " su " .. #d.list .. "|r") or "")

  -- la schedina: the questions on the left, who got it on the right
  local bl, br = {}, {}
  for _, q in ipairs(d.questions) do
    local names = {}
    for i = 1, math.min(2, #q.names) do names[i] = q.names[i] end
    if #q.names > 2 then names[#names + 1] = GREY .. "e artri " .. (#q.names - 2) .. "|r" end
    bl[#bl + 1] = q.text .. " " .. (#q.names > 0 and (table.concat(names, ", ") .. " " .. GREY .. "(" .. (q.stat == "pt" and U.Hours(q.val / 3600) or q.stat == "g" and (ns.Money and ns.Money(q.val, true) or q.val) or q.val) .. ")|r") or (GREY .. "nessuno|r"))
  end
  if #d.right > 0 then
    br[#br + 1] = "Ce l'hanno presa:"
    for i = 1, math.min(2, #d.right) do br[#br + 1] = "  " .. Colored(d.right[i].m) .. " " .. GREEN .. "+" .. d.right[i].bets .. "|r " .. Coin() end
  elseif #d.questions > 0 then
    br[#br + 1] = GREY .. "Nessuno ce l'ha presa.|r"
  end
  if d.pollo then br[#br + 1] = "Er pollo: " .. Colored(d.pollo) .. " " .. GREY .. "ha perso " .. ns.Tombola.Piotte(d.polloN) .. "|r" end
  for i, l in ipairs(bull.bets) do l:SetText(bl[i] or "") end
  for i, l in ipairs(bull.bets2) do l:SetText(br[i] or "") end

  local st = ns.MyStatus and ns.MyStatus()
  bull.foot:SetText(st and not st.lifted and ("Mo' er cap " .. (st.team and ("de " .. st.team.name .. " ") or "") .. "è " .. GOLD .. st.cap .. "|r.") or "")
end

function B.Show(wk, testing)
  if not bull then Build() end
  Fill(B.Data(wk, testing), testing)
  -- tall: on a small screen (or a big interface scale) it shrinks to fit
  local h = UIParent and UIParent.GetHeight and tonumber(UIParent:GetHeight()) or 0
  if h > 0 and bull.SetScale then bull:SetScale(math.min(1, (h - 16) / HEIGHT)) end
  -- always in the middle (a drag lasts until it closes)
  bull:ClearAllPoints()
  bull:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  bull:Show()
end

----------------------------------------------------------------------
-- when it opens
----------------------------------------------------------------------
function Home.ShowBulletin(force)
  local state = ns.state
  if ns.alt then return end
  if not (state and P.HasSettings(state)) then if force then U.Say("ancora nun c'è un bollettino.") end return end
  local wk = M.WeekIndex(state.settings, U.Now()) - 1
  -- test mode: the bulletin of this (test) week, as it stands now
  local testing = force and ns.Tombola and ns.Tombola.Testing()
  if testing then wk = ns.Tombola.Week() end
  if wk < 1 then if force then U.Say("er primo bollettino esce a la fine de la prima settimana (pe' provallo: /patto prova).") end return end
  ns.db.bulletin = type(ns.db.bulletin) == "table" and ns.db.bulletin or {}
  if not force and ns.db.bulletin[state.code] == wk then return end
  if not testing then ns.db.bulletin[state.code] = wk end
  B.Show(wk, testing)
end

-- the first login after the weekly reset; the titles are written down at the start of each week (before the
-- bulletin of the week that just ended counts them)
ns.On("Login", function()
  if not C_Timer then return end
  C_Timer.After(10, function() pcall(B.SnapTitles) end)
  C_Timer.After(12, function() pcall(Home.ShowBulletin, false) end)
  C_Timer.NewTicker(300, function() pcall(B.SnapTitles) pcall(Home.ShowBulletin, false) end)
end)
