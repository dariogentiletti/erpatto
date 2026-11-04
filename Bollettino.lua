-- Er Patto: Er Bollettino, the week told like a paper. It opens by itself at the first login after the weekly
-- reset (and from the Baretto). One big vanilla window: the headline on top, then six boxes: li premi, li ricchi,
-- er cimitero, la tombola, er Colosseo (duelli e gogna), la schedina.
-- Cost: everything is counted once, when the window opens (a few loops over the members and their last ten
-- graves); nothing runs while it's open.
local ADDON, ns = ...
local U, M, P, UI = ns.U, ns.M, ns.P, ns.UI
local H = UI.H
local Home = ns.Home
local B = {}
ns.Bollettino = B

local GREY, GOLD, GREEN, RED, WHITE = "|cff9d9d9d", "|cffffd100", "|cff20ff20", "|cffff4040", "|cffffffff"
local ICON = "Interface\\Icons\\"
local function Short(m) return (tostring(m and m.name or "?"):match("^(%S+)")) or "?" end
local function Colored(m) return "|c" .. H.ClassHex(m.cls) .. Short(m) .. "|r" end
local function W(m, wk, k)
  if ns.Tombola then return ns.Tombola.Weekly(m, wk)[k] or 0 end
  local w = m.stats and m.stats.w and m.stats.w[wk]
  return type(w) == "table" and (w[k] or 0) or 0
end
local function Plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

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
-- the numbers of a week
----------------------------------------------------------------------
-- the week's piotte of a member: tombola + schedina winnings - stakes
local function WeekPiotte(m, wk, list)
  local TB = ns.Tombola
  if not TB then return 0, 0 end
  local sc = TB.Score(m, wk)
  local tomb = sc and sc.points or 0
  local v = TB.VotesOf(m, wk)
  local won, stakes = 0, 0
  if v then
    won = TB.Payout(wk, list, v)
    for _, q in ipairs(TB.QUESTIONS) do if v[q.key] then stakes = stakes + (v["s" .. q.key] or 0) end end
  end
  return tomb + won - stakes, won - stakes
end

local DEATH = { cascato = "cascato", affogato = "affogato", pischello = "ammazzato da 'n pischello" }
local function DeathText(g)
  local s = DEATH[g.k] or (g.by and ("ammazzato da " .. g.by)) or "morto"
  if g.k == "pischello" and g.by then s = s .. " (" .. g.by .. ")" end
  if g.z then s = s .. " a " .. g.z end
  return s
end

function B.Data(wk, testing)
  local list = UI.Members()
  local now = U.Now()
  local from, to
  if testing or not (ns.Tombola and ns.state and P.HasSettings(ns.state)) then from, to = now - M.WEEK, now + 1
  else from = ns.Tombola.WeekStart(wk) to = from + M.WEEK end
  local d = { wk = wk, list = list }

  -- li premi
  local awards = {}
  local function award(icon, label, fn, fmt, lowest)
    local m, v = Leader(list, fn, lowest)
    if m then awards[#awards + 1] = { icon = icon, label = label, m = m, v = fmt(v, m) } end
  end
  award("Ability_Rogue_Sprint", "Er più veloce", function(x) return W(x, wk, "ding") end, function(v) return "+" .. Plural(v, "livello", "livelli") end)
  award("INV_Misc_PocketWatch_01", "Lo stakanovista", function(x) return W(x, wk, "pt") end, function(v) return U.Hours(v / 3600) end)
  award("INV_Misc_Note_01", "Er mulo de le quest", function(x) return W(x, wk, "q") end, function(v) return Plural(v, "quest", "quest") end)
  award("INV_Misc_Coin_01", "Er paperone", function(x) return W(x, wk, "g") end, function(v) return math.floor(v / 10000) .. " oro" end)
  award("INV_Misc_Key_03", "Er topo de dungeon", function(x) return W(x, wk, "dg") end, function(v) return Plural(v, "dungeon", "dungeon") end)
  award("Trade_Fishing", "Er pescatore", function(x) return W(x, wk, "fi") end, function(v) return Plural(v, "pesce", "pesci") end)
  award("INV_Misc_Gem_Variety_01", "Er fortunato", function(x) return W(x, wk, "lb") + 5 * W(x, wk, "le") end,
    function(_, m) return W(m, wk, "lb") .. " blu, " .. W(m, wk, "le") .. " viola" end)
  if #list > 1 then
    award("Ability_Hunter_Pet_Turtle", "La tartaruga", function(x) return W(x, wk, "ding") end, function(v) return "+" .. Plural(v, "livello", "livelli") end, true)
  end
  d.awards = awards

  -- li ricchi
  local rich = {}
  for _, m in ipairs(list) do
    local week, bets = WeekPiotte(m, wk, list)
    rich[#rich + 1] = { m = m, total = ns.Tombola and ns.Tombola.TotalOf(m) or 0, week = week, bets = bets }
  end
  table.sort(rich, function(a, b) if a.total ~= b.total then return a.total > b.total end return tostring(a.m.name) < tostring(b.m.name) end)
  d.rich = rich

  -- er cimitero
  local graves, byKiller, deaths = {}, {}, 0
  for _, m in ipairs(list) do
    deaths = deaths + W(m, wk, "dt")
    for _, g in ipairs(m.rip or {}) do
      if (g.at or 0) >= from and (g.at or 0) < to then
        graves[#graves + 1] = { m = m, g = g }
        if g.by and g.k ~= "pvp" then byKiller[g.by] = (byKiller[g.by] or 0) + 1 end
      end
    end
  end
  table.sort(graves, function(a, b) return (a.g.at or 0) > (b.g.at or 0) end)
  local silly
  for _, x in ipairs(graves) do if DEATH[x.g.k] and (not silly or (x.g.w and not silly.g.w)) then silly = x end end
  if not silly then for _, x in ipairs(graves) do if x.g.w then silly = x break end end end
  local killer, kills
  for k, n in pairs(byKiller) do if not kills or n > kills or (n == kills and k < killer) then killer, kills = k, n end end
  local most, mostN = Leader(list, function(x) return W(x, wk, "dt") end)
  d.dead = { total = math.max(deaths, #graves), most = most, mostN = mostN, silly = silly, killer = killer, kills = kills }

  -- la tombola
  local cards = {}
  if ns.Tombola then
    local card = ns.Tombola.Card(math.max(1, wk))
    local doneBy = {}
    for _, m in ipairs(list) do
      local sc = ns.Tombola.Score(m, wk)
      if sc then
        cards[#cards + 1] = { m = m, sc = sc }
        for i, ok in ipairs(sc.done) do if ok then doneBy[i] = (doneBy[i] or 0) + 1 end end
      end
    end
    table.sort(cards, function(a, b) if a.sc.points ~= b.sc.points then return a.sc.points > b.sc.points end return tostring(a.m.name) < tostring(b.m.name) end)
    if card then
      local hard, easy
      for i, sq in ipairs(card) do
        local n = doneBy[i] or 0
        if not hard or n < hard.n then hard = { t = sq.t, n = n } end
        if not easy or n > easy.n then easy = { t = sq.t, n = n } end
      end
      d.hard, d.easy = hard, easy
    end
  end
  d.cards = cards

  -- er Colosseo: le gogne chiuse 'sta settimana, i duelli
  local gogne = {}
  if ns.Sfide and ns.Sfide.Series then
    local all = {}
    for _, m in ipairs(list) do all[m.guid] = m end
    local ok, series = pcall(ns.Sfide.Series)
    for _, s in ipairs(ok and series or {}) do
      if s.state == "chiusa" and (s.te or 0) >= from and (s.te or 0) < to and all[s.w] and all[s.l] then
        gogne[#gogne + 1] = { w = all[s.w], l = all[s.l], n = #s.duels, pena = s.pena and ns.Sfide.PENE[s.pena], long = s.long, te = s.te }
      end
    end
    table.sort(gogne, function(a, b) return a.te > b.te end)
  end
  local bully, bullyN = Leader(list, function(x) return W(x, wk, "dw") end)
  local bag, bagN = Leader(list, function(x) return W(x, wk, "dl") end)
  d.arena = { gogne = gogne, bully = bully, bullyN = bullyN, bag = bag, bagN = bagN }

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

  -- the headline: the biggest story of the week, and the next one
  local stories = {}
  local function story(score, m, title, sub) stories[#stories + 1] = { score = score, m = m, title = title, sub = sub } end
  for _, c in ipairs(cards) do
    if c.sc.full then story(100 + c.sc.points, c.m, "TOMBOLA! " .. Short(c.m) .. " ha chiuso tutta la cartella", "E se porta a casa " .. ns.Tombola.Piotte(c.sc.points) .. " de tombola.") end
  end
  local top = rich[1] and rich[1].week > 0 and rich[1]
  for _, r in ipairs(rich) do if r.week > (top and top.week or 0) then top = r end end
  if top then story(50 + top.week, top.m, Short(top.m) .. " se porta a casa " .. ns.Tombola.Piotte(top.week), "Tombola e schedina: er botteghino de 'sta settimana è suo.") end
  for _, g in ipairs(gogne) do
    story(70, g.w, Short(g.l) .. " è finito a la gogna", Short(g.w) .. " j'ha dato " .. (g.pena and g.pena.name:lower() or "er pegno") ..
      (g.n == 3 and ", a la bella." or g.n == 2 and ", a la rivincita." or "."))
  end
  if silly then story(65, silly.m, Short(silly.m) .. " è " .. DeathText(silly.g), silly.g.w and ("Ultime parole: \"" .. silly.g.w .. "\"") or "Senza manco 'na parola.") end
  local fast = awards[1] and awards[1].label == "Er più veloce" and awards[1]
  if fast then story(40 + W(fast.m, wk, "ding"), fast.m, Short(fast.m) .. " vola: " .. fast.v, "Nessuno è salito più de lui.") end
  table.sort(stories, function(a, b) return a.score > b.score end)
  d.head = stories[1]
  d.head2 = stories[2]
  return d
end

----------------------------------------------------------------------
-- the window
----------------------------------------------------------------------
local bull
local WIDTH, HEIGHT, COL = 784, 590, 368

local function Title(box, text)
  local t = H.Text(box, "GameFontNormal", text, 300)
  t:SetPoint("TOPLEFT", 12, -10)
  return t
end
local function Icon(parent, size)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetSize(size, size)
  t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  return t
end
-- a box with n lines of small text
local function Lines(box, n, top, w)
  local out = {}
  for i = 1, n do
    local l = H.Text(box, "GameFontHighlightSmall", "", w or (COL - 28))
    l:SetPoint("TOPLEFT", 14, -(top or 30) - (i - 1) * 15)
    if l.SetWordWrap then l:SetWordWrap(false) end
    out[i] = l
  end
  return out
end

local function Build()
  bull = CreateFrame("Frame", "ErPattoBulletin", UIParent, "BackdropTemplate")
  bull:SetSize(WIDTH, HEIGHT)
  bull:SetPoint("CENTER", 0, 20)
  bull:SetFrameStrata("DIALOG")
  bull:SetToplevel(true)
  bull:EnableMouse(true)
  bull:SetMovable(true)
  bull:RegisterForDrag("LeftButton")
  bull:SetScript("OnDragStart", bull.StartMoving)
  bull:SetScript("OnDragStop", bull.StopMovingOrSizing)
  H.Chrome(bull)
  bull.title = H.DialogHeader(bull, "", 300)
  H.CloseX(bull)
  local x0, x1 = 20, 20 + COL + 8

  -- the headline
  local hd = H.Box(bull, WIDTH - 40, 62)
  hd:SetPoint("TOPLEFT", x0, -30)
  bull.face = hd:CreateTexture(nil, "ARTWORK")
  bull.face:SetSize(44, 44)
  bull.face:SetPoint("LEFT", 12, 0)
  bull.crown = Icon(hd, 22)
  bull.crown:SetTexture(ICON .. "INV_Crown_01")
  bull.crown:SetPoint("BOTTOMRIGHT", bull.face, "BOTTOMRIGHT", 6, -4)
  bull.head = H.Text(hd, "GameFontNormal", "", WIDTH - 140)
  bull.head:SetPoint("TOPLEFT", 66, -12)
  if bull.head.SetWordWrap then bull.head:SetWordWrap(false) end
  bull.headSub = H.Text(hd, "GameFontHighlightSmall", "", WIDTH - 140)
  bull.headSub:SetPoint("TOPLEFT", 66, -30)
  if bull.headSub.SetWordWrap then bull.headSub:SetWordWrap(false) end
  bull.head2 = H.Text(hd, "GameFontDisableSmall", "", WIDTH - 140)
  bull.head2:SetPoint("TOPLEFT", 66, -45)
  if bull.head2.SetWordWrap then bull.head2:SetWordWrap(false) end

  -- li premi
  local pr = H.Box(bull, COL, 184)
  pr:SetPoint("TOPLEFT", x0, -98)
  Title(pr, "Li premi")
  bull.awards = {}
  for i = 1, 8 do
    local r = {}
    r.icon = Icon(pr, 16)
    r.icon:SetPoint("TOPLEFT", 14, -30 - (i - 1) * 18)
    r.label = H.Text(pr, "GameFontNormalSmall", "", 130)
    r.label:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.name = H.Text(pr, "GameFontHighlightSmall", "", 90)
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 140, 0)
    r.val = H.Text(pr, "GameFontHighlightSmall", "", 100, "RIGHT")
    r.val:SetPoint("TOPRIGHT", -14, -32 - (i - 1) * 18)
    bull.awards[i] = r
  end

  -- li ricchi
  local ri = H.Box(bull, COL, 184)
  ri:SetPoint("TOPLEFT", x1, -98)
  Title(ri, "Li ricchi")
  local h1 = H.Text(ri, "GameFontDisableSmall", "Settimana", 70, "RIGHT") h1:SetPoint("TOPRIGHT", -14, -13)
  bull.rich = {}
  for i = 1, 8 do
    local r = {}
    local y = -30 - (i - 1) * 18
    r.name = H.Text(ri, "GameFontHighlightSmall", "", 90)
    r.name:SetPoint("TOPLEFT", 14, y - 2)
    r.bar = ri:CreateTexture(nil, "ARTWORK")
    r.bar:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.bar:SetHeight(10)
    r.bar:SetPoint("TOPLEFT", 104, y - 3)
    r.total = H.Text(ri, "GameFontHighlightSmall", "", 60)
    r.week = H.Text(ri, "GameFontHighlightSmall", "", 60, "RIGHT")
    r.week:SetPoint("TOPRIGHT", -14, y - 2)
    bull.rich[i] = r
  end

  -- er cimitero
  local ci = H.Box(bull, COL, 122)
  ci:SetPoint("TOPLEFT", x0, -290)
  Title(ci, "Er cimitero")
  local sk = Icon(ci, 16) sk:SetTexture(ICON .. "INV_Misc_Bone_HumanSkull_01") sk:SetPoint("TOPRIGHT", -12, -9)
  bull.dead = Lines(ci, 5)

  -- la tombola: a little card for the best five
  local tb = H.Box(bull, COL, 122)
  tb:SetPoint("TOPLEFT", x1, -290)
  Title(tb, "La tombola")
  local ti = Icon(tb, 16) ti:SetTexture(ICON .. "INV_Misc_Ticket_Tarot_Stack_01") ti:SetPoint("TOPRIGHT", -12, -9)
  bull.cards = {}
  for c = 1, 5 do
    local k = { cells = {} }
    local left = 18 + (c - 1) * 68
    for i = 1, 9 do
      local cell = tb:CreateTexture(nil, "ARTWORK")
      cell:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
      cell:SetSize(14, 14)
      cell:SetPoint("TOPLEFT", left + ((i - 1) % 3) * 13, -30 - math.floor((i - 1) / 3) * 13)
      local check = tb:CreateTexture(nil, "OVERLAY")
      check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
      check:SetSize(14, 14)
      check:SetPoint("CENTER", cell)
      k.cells[i] = { box = cell, check = check }
    end
    k.name = H.Text(tb, "GameFontHighlightSmall", "", 66)
    k.name:SetPoint("TOPLEFT", left - 4, -72)
    k.pts = H.Text(tb, "GameFontNormalSmall", "", 66)
    k.pts:SetPoint("TOPLEFT", left - 4, -85)
    bull.cards[c] = k
  end
  bull.tombLine = H.Text(tb, "GameFontDisableSmall", "", COL - 28)
  bull.tombLine:SetPoint("TOPLEFT", 14, -101)
  if bull.tombLine.SetWordWrap then bull.tombLine:SetWordWrap(false) end

  -- er Colosseo
  local co = H.Box(bull, COL, 112)
  co:SetPoint("TOPLEFT", x0, -420)
  Title(co, "Er Colosseo")
  local sw = Icon(co, 16) sw:SetTexture(ICON .. "Ability_Warrior_Challange") sw:SetPoint("TOPRIGHT", -12, -9)
  bull.arena = Lines(co, 5)

  -- la schedina
  local sc = H.Box(bull, COL, 112)
  sc:SetPoint("TOPLEFT", x1, -420)
  Title(sc, "La schedina")
  local si = Icon(sc, 16) si:SetTexture(ICON .. "INV_Misc_Note_06") si:SetPoint("TOPRIGHT", -12, -9)
  bull.bets = Lines(sc, 5)

  bull.foot = H.Text(bull, "GameFontNormalSmall", "", 460)
  bull.foot:SetPoint("BOTTOMLEFT", 26, 24)
  bull.ok = H.Btn(bull, "Daje", 110, function() bull:Hide() end)
  bull.ok:SetPoint("BOTTOMRIGHT", -24, 16)
  bull.shop = H.Btn(bull, "Ar Botteghino", 120, function()
    bull:Hide()
    if ns.Botteghino and ns.Botteghino.Show then pcall(ns.Botteghino.Show, "schedina") end
  end)
  bull.shop:SetPoint("RIGHT", bull.ok, "LEFT", -6, 0)
  if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoBulletin") end
end

local function SetFace(tex, m)
  tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
  local c = CLASS_ICON_TCOORDS and m and m.cls and CLASS_ICON_TCOORDS[m.cls]
  if c then tex:SetTexCoord(c[1], c[2], c[3], c[4]) else tex:SetTexCoord(0, 0.25, 0, 0.25) end
end

local function Fill(d, testing)
  bull.title:SetText("Er Bollettino, settimana " .. d.wk .. (testing and " |cffff8000(prova)|r" or ""))

  -- headline
  local h = d.head
  if h then
    SetFace(bull.face, h.m) bull.face:Show() bull.crown:Show()
    bull.head:SetText(h.title)
    bull.headSub:SetText(h.sub or "")
    bull.head2:SetText(d.head2 and ("E poi: " .. d.head2.title .. ".") or "")
  else
    bull.face:Hide() bull.crown:Hide()
    bull.head:SetText("Settimana tranquilla")
    bull.headSub:SetText("Nun s'è mosso nessuno. Er bollettino aspetta notizie.")
    bull.head2:SetText("")
  end

  -- li premi
  for i, r in ipairs(bull.awards) do
    local a = d.awards[i]
    if a then
      r.icon:SetTexture(ICON .. a.icon) r.icon:Show()
      r.label:SetText(a.label) r.name:SetText(Colored(a.m)) r.val:SetText(a.v)
    else
      r.icon:Hide() r.label:SetText(i == 1 and (GREY .. "Ancora gnente.|r") or "") r.name:SetText("") r.val:SetText("")
    end
  end

  -- li ricchi
  local max = 1
  for _, x in ipairs(d.rich) do max = math.max(max, x.total) end
  for i, r in ipairs(bull.rich) do
    local x = d.rich[i]
    if x then
      r.name:SetText(i .. ". " .. Colored(x.m))
      local w = math.max(2, math.floor(150 * x.total / max))
      r.bar:SetWidth(w) r.bar:Show()
      if i == 1 then r.bar:SetVertexColor(1, 0.82, 0) else r.bar:SetVertexColor(0.6, 0.6, 0.6) end
      r.total:ClearAllPoints() r.total:SetPoint("LEFT", r.bar, "RIGHT", 6, 0)
      r.total:SetText(WHITE .. x.total .. "|r")
      r.week:SetText(x.week > 0 and (GREEN .. "+" .. x.week .. "|r") or x.week < 0 and (RED .. x.week .. "|r") or (GREY .. "0|r"))
    else
      r.name:SetText("") r.bar:Hide() r.total:SetText("") r.week:SetText("")
    end
  end

  -- er cimitero
  local dd, lines = d.dead, {}
  if dd.total == 0 then lines[1] = GREEN .. "Nessun morto. Settimana da santi.|r"
  else
    lines[#lines + 1] = "Morti in tutto: " .. WHITE .. dd.total .. "|r"
    if dd.most then lines[#lines + 1] = "Er più morto: " .. Colored(dd.most) .. " " .. GREY .. Plural(dd.mostN, "vorta", "vorte") .. "|r" end
    if dd.silly then
      lines[#lines + 1] = "La morte più scema: " .. Colored(dd.silly.m) .. " " .. GREY .. DeathText(dd.silly.g) .. "|r"
      if dd.silly.g.w then lines[#lines + 1] = GREY .. "Ultime parole: |r" .. WHITE .. "\"" .. dd.silly.g.w .. "\"|r" end
    end
    if dd.killer then lines[#lines + 1] = "Er boia: " .. RED .. dd.killer .. "|r " .. GREY .. Plural(dd.kills, "vittima", "vittime") .. "|r" end
  end
  for i, l in ipairs(bull.dead) do l:SetText(lines[i] or "") end

  -- la tombola
  for c, k in ipairs(bull.cards) do
    local x = d.cards[c]
    for _, cell in ipairs(k.cells) do cell.box:SetShown(x ~= nil) cell.check:SetShown(x ~= nil and false) end
    if x then
      for i, cell in ipairs(k.cells) do cell.check:SetShown(x.sc.done[i] and true or false) end
      k.name:SetText(Colored(x.m))
      k.pts:SetText(x.sc.full and (GREEN .. "TOMBOLA!|r") or ("+" .. x.sc.points .. (x.sc.lines > 0 and (" " .. GREY .. Plural(x.sc.lines, "linea", "linee") .. "|r") or "")))
    else
      k.name:SetText("") k.pts:SetText("")
    end
  end
  if d.hard and d.hard.n == 0 then bull.tombLine:SetText("Nessuno ha fatto: " .. WHITE .. d.hard.t .. "|r")
  elseif d.easy and d.easy.n > 0 then bull.tombLine:SetText("La più fatta: " .. WHITE .. d.easy.t .. "|r " .. GREY .. "(" .. d.easy.n .. ")|r")
  else bull.tombLine:SetText(#d.cards == 0 and (GREY .. "Gnente cartelle.|r") or "") end

  -- er Colosseo
  local a, al = d.arena, {}
  for i = 1, math.min(3, #a.gogne) do
    local g = a.gogne[i]
    al[#al + 1] = Colored(g.w) .. " ha messo a la gogna " .. Colored(g.l) .. GREY .. (g.pena and (", " .. g.pena.name:lower()) or "") ..
      (g.n == 3 and ", a la bella" or g.n == 2 and ", a la rivincita" or "") .. "|r"
  end
  if #a.gogne > 3 then al[#al] = al[#al] .. GREY .. " (e artre " .. (#a.gogne - 3) .. ")|r" end
  if a.bully then al[#al + 1] = "Er bullo: " .. Colored(a.bully) .. " " .. GREY .. Plural(a.bullyN, "duello vinto", "duelli vinti") .. "|r" end
  if a.bag then al[#al + 1] = "Er sacco da boxe: " .. Colored(a.bag) .. " " .. GREY .. Plural(a.bagN, "duello perso", "duelli persi") .. "|r" end
  if #al == 0 then al[1] = GREY .. "Nessun duello: tutti bravi regazzi.|r" end
  for i, l in ipairs(bull.arena) do l:SetText(al[i] or "") end

  -- la schedina
  local bl = {}
  for _, q in ipairs(d.questions) do
    local names = {}
    for i = 1, math.min(2, #q.names) do names[i] = q.names[i] end
    if #q.names > 2 then names[#names + 1] = GREY .. "e artri " .. (#q.names - 2) .. "|r" end
    bl[#bl + 1] = q.text .. " " .. (#q.names > 0 and (table.concat(names, ", ") .. " " .. GREY .. "(" .. (q.stat == "pt" and U.Hours(q.val / 3600) or q.stat == "g" and (math.floor(q.val / 10000) .. " oro") or q.val) .. ")|r") or (GREY .. "nessuno|r"))
  end
  if #d.right > 0 then
    local t = {}
    for i = 1, math.min(3, #d.right) do t[#t + 1] = Colored(d.right[i].m) .. " " .. GREEN .. "+" .. d.right[i].bets .. "|r" end
    bl[#bl + 1] = "Ce l'hanno presa: " .. table.concat(t, ", ")
  elseif #d.questions > 0 then
    bl[#bl + 1] = GREY .. "Nessuno ce l'ha presa: er banco aringrazia.|r"
  end
  if d.pollo then bl[#bl + 1] = "Er pollo: " .. Colored(d.pollo) .. " " .. GREY .. "ha buttato " .. ns.Tombola.Piotte(d.polloN) .. "|r" end
  for i, l in ipairs(bull.bets) do l:SetText(bl[i] or "") end

  local st = ns.MyStatus and ns.MyStatus()
  bull.foot:SetText(st and not st.lifted and ("Mo' er cap " .. (st.team and ("de " .. st.team.name .. " ") or "") .. "è " .. GOLD .. st.cap .. "|r. 'Na schedina nova t'aspetta.") or "")
end

function B.Show(wk, testing)
  if not bull then Build() end
  Fill(B.Data(wk, testing), testing)
  bull:Show()
end

----------------------------------------------------------------------
-- when it opens
----------------------------------------------------------------------
function Home.ShowBulletin(force)
  local state = ns.state
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

-- the first login after the weekly reset
ns.On("Login", function()
  if not C_Timer then return end
  C_Timer.After(12, function() pcall(Home.ShowBulletin, false) end)
  C_Timer.NewTicker(300, function() pcall(Home.ShowBulletin, false) end)
end)
