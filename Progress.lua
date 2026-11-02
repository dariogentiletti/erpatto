-- Er Patto: the "Progresso" tab. Three pages:
--   Classifiche: one card per thing worth doing well (level, time played, quests, dungeons, gold, gear, duels, BGs)
--   Diario: one member's adventure (time against the plan, milestones, quests and zones, dungeons, professions)
--   Confronto: you against another member, side by side, with your duels against each other
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H

local page = "rank"        -- "rank", "diary", "vs"
local mode = "t"           -- "t" since always, "w" this week
local diaryGuid, vsGuid
local GREEN, RED, WHITE, GREY = "|cff20ff20", "|cffff4040", "|cffffffff", "|cff9d9d9d"

local function R() return ns.Rank end

local function Ordinal(n) return n .. "º" end

local function Hours(sec)
  if not sec or sec <= 0 then return "0 ore" end
  return U.Hours(sec / 3600)
end

local function ItemLevelOf(m)
  if m.guid == ns.recordGuid and not ns.alt then return T.ItemLevel() or m.il or 0 end
  return m.il or 0
end

local function OneDecimal(x) return (string.format("%.1f", x):gsub("%.", ",")) end

-- what the cards, the diary and the comparison measure; low = true when less is better
local METRICS = {
  { key = "lv", title = "Livello", value = function(m) return H.Position(m) end, text = function(m) return tostring(m.lv or "?") end, fixed = true },
  { key = "pt", title = "Ore giocate", value = function(m, md) return H.StatOf(m, "pt", md) end, text = function(m, md) return Hours(H.StatOf(m, "pt", md)) end },
  { key = "q", title = "Quest" },
  { key = "dg", title = "Dungeon" },
  { key = "g", title = "Sordi fatti", text = function(m, md) return R().Money(H.StatOf(m, "g", md), true) end },
  { key = "rk", title = "Rari ammazzati" },
  { key = "hk", title = "Uccisioni PvP" },
  { key = "hn", title = "Onore", text = function(m, md) return U.Thousands(H.StatOf(m, "hn", md)) end },
  { key = "il", title = "Livello oggetti", value = ItemLevelOf, text = function(m) local v = ItemLevelOf(m) return v > 0 and OneDecimal(v) or "-" end, fixed = true, noCard = true },
  { key = "dw", title = "Duelli vinti", text = function(m, md) return H.StatOf(m, "dw", md) .. "-" .. H.StatOf(m, "dl", md) end,
    tie = function(a, b, md) return H.StatOf(a, "dl", md) < H.StatOf(b, "dl", md) end },
  { key = "bw", title = "BG vinte", text = function(m, md) return H.StatOf(m, "bw", md) .. "-" .. H.StatOf(m, "bl", md) end,
    tie = function(a, b, md) return H.StatOf(a, "bl", md) < H.StatOf(b, "bl", md) end },
}
local DEATHS = { key = "dt", title = "Morti", low = true }

local function Value(metric, m)
  if metric.value then return metric.value(m, mode) or 0 end
  return H.StatOf(m, metric.key, mode)
end

local function TextOf(metric, m)
  if metric.text then return metric.text(m, mode) end
  return tostring(H.StatOf(m, metric.key, mode))
end

local function Sorted(metric, list)
  local out = {}
  for _, m in ipairs(list) do out[#out + 1] = m end
  table.sort(out, function(a, b)
    local x, y = Value(metric, a), Value(metric, b)
    if x ~= y then
      if metric.low then return x < y end
      return x > y
    end
    if metric.tie then
      local ta, tb = metric.tie(a, b, mode), metric.tie(b, a, mode)
      if ta ~= tb then return ta end
    end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

-- members: me first, then by team and level
local function Ordered(list)
  local order = {}
  for _, m in ipairs(list) do order[#order + 1] = m end
  table.sort(order, function(a, b)
    if (a.guid == ns.recordGuid) ~= (b.guid == ns.recordGuid) then return a.guid == ns.recordGuid end
    if (a.team or "z") ~= (b.team or "z") then return (a.team or "z") < (b.team or "z") end
    if (a.lv or 0) ~= (b.lv or 0) then return (a.lv or 0) > (b.lv or 0) end
    return tostring(a.name) < tostring(b.name)
  end)
  return order
end

local function Find(list, guid)
  for _, m in ipairs(list) do if m.guid == guid then return m end end
  return nil
end

----------------------------------------------------------------------
-- a short member list (Diario and Confronto)
----------------------------------------------------------------------
local ROWS = 18

local function MemberList(parent, onClick)
  local box = H.Box(parent, 190, 347)
  box.title = H.Text(box, "GameFontNormal", "Membri", 170)
  box.title:SetPoint("TOPLEFT", 12, -10)
  box.rows = {}
  box.page = 1
  for i = 1, ROWS do
    local b = CreateFrame("Button", nil, box)
    b:SetSize(170, 16)
    b:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 16)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    b.sel:SetBlendMode("ADD")
    b.sel:SetVertexColor(1, 0.82, 0, 0.6)
    b.sel:SetAllPoints()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.text = H.Text(b, "GameFontHighlightSmall", "", 136)
    b.text:SetPoint("LEFT", 4, 0)
    b.lv = H.Text(b, "GameFontHighlightSmall", "", 28, "RIGHT")
    b.lv:SetPoint("RIGHT", -2, 0)
    b:SetScript("OnClick", function(self) onClick(self.guid) UI.Refresh() end)
    box.rows[i] = b
  end
  local function arrow(dir, x)
    local b = CreateFrame("Button", nil, box)
    b:SetSize(22, 22)
    b:SetPoint("BOTTOMRIGHT", x, 6)
    local base = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetScript("OnClick", function() box.page = box.page + dir UI.Refresh() end)
    return b
  end
  box.prev = arrow(-1, -34)
  box.next = arrow(1, -10)
  function box:Fill(order, selected, skip)
    local shown = {}
    for _, m in ipairs(order) do if m.guid ~= skip then shown[#shown + 1] = m end end
    local pages = math.max(1, math.ceil(#shown / ROWS))
    self.page = math.max(1, math.min(self.page, pages))
    for i, b in ipairs(self.rows) do
      local m = shown[(self.page - 1) * ROWS + i]
      if m then
        b.guid = m.guid
        b.text:SetText(H.Colored(m) .. (m.guid == ns.recordGuid and " |cffffd100(tu)|r" or ""))
        b.lv:SetText(tostring(m.lv or "?"))
        b.sel:SetShown(m.guid == selected)
        b:Show()
      else
        b:Hide()
      end
    end
    self.prev:SetShown(pages > 1)
    self.next:SetShown(pages > 1)
    self.prev:SetEnabled(self.page > 1)
    self.next:SetEnabled(self.page < pages)
  end
  return box
end

----------------------------------------------------------------------
-- Classifiche
----------------------------------------------------------------------
local CARD_W, CARD_H = 142, 169

local function BuildCards(v)
  local f = CreateFrame("Frame", nil, v)
  f:SetPoint("TOPLEFT", 0, -28)
  f:SetSize(744, 347)
  v.rank = f
  f.cards = {}
  local cardMetrics = {}
  for _, metric in ipairs(METRICS) do if not metric.noCard then cardMetrics[#cardMetrics + 1] = metric end end
  for i, metric in ipairs(cardMetrics) do
    local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
    local card = H.Box(f, CARD_W, CARD_H)
    card:SetPoint("TOPLEFT", col * (CARD_W + 8), -row * (CARD_H + 8))
    card.metric = metric
    card.title = H.Text(card, "GameFontNormalSmall", metric.title, 126)
    card.title:SetPoint("TOPLEFT", 10, -9)
    card.rows = {}
    for k = 1, 5 do
      local r = CreateFrame("Button", nil, card)
      r:SetSize(128, 22)
      r:SetPoint("TOPLEFT", 8, -28 - (k - 1) * 24)
      r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      r.pos = H.Text(r, "GameFontNormalSmall", "", 24)
      r.pos:SetPoint("TOPLEFT", 2, -2)
      r.name = H.Text(r, "GameFontHighlightSmall", "", 64)
      r.name:SetPoint("TOPLEFT", 26, -2)
      if r.name.SetWordWrap then r.name:SetWordWrap(false) end
      r.value = H.Text(r, "GameFontHighlightSmall", "", 44, "RIGHT")
      r.value:SetPoint("TOPRIGHT", -2, -2)
      r.bar = CreateFrame("StatusBar", nil, r)
      r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
      r.bar:SetMinMaxValues(0, 1)
      r.bar:SetSize(100, 3)
      r.bar:SetPoint("TOPLEFT", 26, -16)
      local bg = r.bar:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(0, 0, 0, 0.6)
      r:SetScript("OnClick", function(self)
        if not self.guid then return end
        if self.guid == ns.recordGuid then diaryGuid, page = nil, "diary" else vsGuid, page = self.guid, "vs" end
        UI.Refresh()
      end)
      card.rows[k] = r
    end
    card.me = H.Text(card, "GameFontNormalSmall", "", 126)
    card.me:SetPoint("BOTTOMLEFT", 10, 8)
    f.cards[i] = card
  end
end

local function RefreshCards(v, list)
  local me = ns.MyRecord()
  for _, card in ipairs(v.rank.cards) do
    local metric = card.metric
    local sorted = Sorted(metric, list)
    local best = sorted[1] and Value(metric, sorted[1]) or 0
    local myPos
    for i, m in ipairs(sorted) do if me and m.guid == me.guid then myPos = i end end
    local anyone = best > 0
    for k, r in ipairs(card.rows) do
      local m = sorted[k]
      if m and anyone then
        local val = Value(metric, m)
        local mine = me and m.guid == me.guid
        r.guid = m.guid
        r.pos:SetText(Ordinal(k))
        r.name:SetText(H.Colored(m) .. (mine and " |cffffd100<|r" or ""))
        r.value:SetText((mine and WHITE or "|cffd0d0d0") .. TextOf(metric, m) .. "|r")
        r.bar:SetValue(best > 0 and math.min(1, val / best) or 0)
        r.bar:SetStatusBarColor(mine and 1 or 0.55, mine and 0.82 or 0.55, mine and 0 or 0.6)
        r:Show()
      else
        r:Hide()
      end
    end
    if not anyone then
      card.me:SetText(GREY .. "Ancora gnente pe' nessuno.|r")
    elseif myPos and myPos > 5 and me then
      card.me:SetText("Tu: " .. Ordinal(myPos) .. " su " .. #sorted .. ", " .. TextOf(metric, me))
    else
      card.me:SetText("")
    end
    card.title:SetText(metric.title .. ((mode == "w" and not metric.fixed) and GREY .. ", 'sta settimana|r" or ""))
  end
end

----------------------------------------------------------------------
-- Diario
----------------------------------------------------------------------
local function Section(parent, w, h, title)
  local b = H.Box(parent, w, h)
  b.title = H.Text(b, "GameFontNormal", title, w - 20)
  b.title:SetPoint("TOPLEFT", 10, -8)
  return b
end

local function Lines(parent, n, x, y, w, step)
  local out = {}
  for i = 1, n do
    local l = H.Text(parent, "GameFontHighlightSmall", "", w - 92)
    l:SetPoint("TOPLEFT", x, y - (i - 1) * step)
    if l.SetWordWrap then l:SetWordWrap(false) end
    l.fullW = w
    l.right = H.Text(parent, "GameFontHighlightSmall", "", 90, "RIGHT")
    l.right:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + w, y - (i - 1) * step)
    out[i] = l
  end
  return out
end

local function BuildDiary(v)
  local f = CreateFrame("Frame", nil, v)
  f:SetPoint("TOPLEFT", 0, -28)
  f:SetSize(744, 347)
  v.diary = f
  f.list = MemberList(f, function(guid) diaryGuid = guid ~= ns.recordGuid and guid or nil end)
  f.list:SetPoint("TOPLEFT", 0, 0)

  local x0, colW = 198, 269
  -- column A: who, level bar, time and deaths; milestones; professions
  f.time = Section(f, colW, 96, "")
  f.time:SetPoint("TOPLEFT", x0, 0)
  f.time.bar = CreateFrame("StatusBar", nil, f.time)
  f.time.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  f.time.bar:SetMinMaxValues(0, 59)
  f.time.bar:SetSize(colW - 20, 8)
  f.time.bar:SetPoint("TOPLEFT", 10, -30)
  local tbg = f.time.bar:CreateTexture(nil, "BACKGROUND")
  tbg:SetAllPoints()
  tbg:SetColorTexture(0, 0, 0, 0.6)
  f.time.cap = f.time.bar:CreateTexture(nil, "OVERLAY")
  f.time.cap:SetColorTexture(1, 1, 1, 1)
  f.time.cap:SetSize(2, 12)
  f.time.lines = Lines(f.time, 3, 10, -46, colW - 20, 15)

  f.miles = Section(f, colW, 122, "Traguardi")
  f.miles:SetPoint("TOPLEFT", x0, -100)
  f.miles.lines = Lines(f.miles, 6, 10, -26, colW - 20, 15)

  f.prof = Section(f, colW, 121, "Professioni")
  f.prof:SetPoint("TOPLEFT", x0, -226)
  f.prof.lines = Lines(f.prof, 6, 10, -26, colW - 20, 15)

  -- column B: quests (scrolling, grouped by zone), then dungeons and rares
  local x1 = x0 + colW + 8
  f.quest = Section(f, colW, 136, "Quest")
  f.quest:SetPoint("TOPLEFT", x1, 0)
  f.quest.sub = H.Text(f.quest, "GameFontHighlightSmall", "", colW - 20)
  f.quest.sub:SetPoint("TOPLEFT", 10, -26)
  local scroll = CreateFrame("ScrollFrame", "ErPattoQuestScroll", f.quest, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -42)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)
  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(colW - 40, 10)
  scroll:SetScrollChild(body)
  f.quest.scroll, f.quest.body, f.quest.rows = scroll, body, {}

  -- titles held right now; hover one to read how it's won
  f.titles = Section(f, colW, 60, "Titoli")
  f.titles:SetPoint("TOPLEFT", x1, -140)
  f.titles.items = {}

  f.dung = Section(f, colW, 143, "Dungeon")
  f.dung:SetPoint("TOPLEFT", x1, -204)
  f.dung.lines = Lines(f.dung, 7, 10, -26, 126, 15)
  f.dung.rareTitle = H.Text(f.dung, "GameFontNormal", "Rari", 120)
  f.dung.rareTitle:SetPoint("TOPLEFT", 140, -8)
  f.dung.rares = Lines(f.dung, 7, 140, -26, 120, 15)
end

local function SetLines(lines, items)
  for i, l in ipairs(lines) do
    local it = items[i]
    l:SetText(it and it[1] or "")
    l.right:SetText(it and it[2] or "")
    l:SetWidth((it and it[2] and it[2] ~= "") and (l.fullW - 92) or l.fullW)
  end
end

-- one line of the quest list: a zone header or a quest
local function QuestRow(box, i)
  local r = box.rows[i]
  if r then return r end
  r = CreateFrame("Frame", nil, box.body)
  r:SetSize(229, 14)
  r.left = H.Text(r, "GameFontHighlightSmall", "", 170)
  r.left:SetPoint("LEFT", 0, 0)
  if r.left.SetWordWrap then r.left:SetWordWrap(false) end
  r.right = H.Text(r, "GameFontHighlightSmall", "", 58, "RIGHT")
  r.right:SetPoint("RIGHT", 0, 0)
  box.rows[i] = r
  return r
end

local function WeekStart()
  local s = ns.state.settings
  local wk = M.WeekIndex(s, U.Now())
  if wk < 1 then return s.start or 0 end
  return s.start + (wk - 1) * M.WEEK
end

-- quests grouped by zone, most recent zone first; inside a zone, newest first
local function QuestLines(rec, you)
  local out = {}
  if you and not ns.alt then
    local since = mode == "w" and WeekStart() or 0
    local zones, order = {}, {}
    for _, q in ipairs(T.QuestLog()) do
      if (q.at or 0) >= since then
        local z = q.z or "Unknown"
        if not zones[z] then zones[z] = {} order[#order + 1] = z end
        table.insert(zones[z], q)
      end
    end
    -- every zone gets its header; the quests under it are trimmed so the list stays around 150 lines
    local perZone = math.max(3, math.floor(140 / math.max(1, #order)) - 1)
    for _, z in ipairs(order) do
      out[#out + 1] = { "|cffffd100" .. z .. "|r", "|cffffd100" .. #zones[z] .. "|r", header = true }
      for k, q in ipairs(zones[z]) do
        if k > perZone then out[#out + 1] = { GREY .. "  e artre " .. (#zones[z] - perZone) .. "|r", "" } break end
        out[#out + 1] = { "  " .. tostring(q.t), q.at and (GREY .. U.Day(q.at) .. "|r") or "" }
      end
    end
  else
    -- friends share the zones they quest in and their last three quests
    local thisWeek = rec.wk and rec.wk == M.WeekIndex(ns.state.settings, U.Now())
    local src = mode == "w" and (thisWeek and rec.zqw or {}) or (rec.zq or {})
    local since = mode == "w" and WeekStart() or 0
    local zones = {}
    for z, n in pairs(src) do zones[#zones + 1] = { z = z, n = n } end
    table.sort(zones, function(a, b) return a.n > b.n end)
    for _, z in ipairs(zones) do out[#out + 1] = { "|cffffd100" .. z.z .. "|r", "|cffffd100" .. z.n .. "|r", header = true } end
    local recent = {}
    for _, q in ipairs(rec.lq or {}) do if (q.at or 0) >= since then recent[#recent + 1] = q end end
    if #recent > 0 then
      out[#out + 1] = { "|cffffd100Urtime consegnate|r", "", header = true }
      for _, q in ipairs(recent) do out[#out + 1] = { "  " .. tostring(q.t), q.at and (GREY .. U.Day(q.at) .. "|r") or "" } end
    end
  end
  return out
end

local function RefreshDiary(v, list)
  local f = v.diary
  local rec = Find(list, diaryGuid) or ns.MyRecord()
  if not rec then return end
  f.list:Fill(Ordered(list), rec.guid)
  local state = ns.state
  local s = state.settings
  local you = rec.guid == ns.recordGuid

  -- who, where they are against the cap, time and deaths
  local team = rec.team and M.TeamById(s, rec.team)
  local st = team and M.Status(s, team.id, U.Now())
  f.time.title:SetText(H.Colored(rec) .. "  |cffffffffLivello " .. tostring(rec.lv or "?") .. "|r" .. (team and (GREY .. ", " .. team.name .. "|r") or ""))
  local pos = H.Position(rec)
  f.time.bar:SetValue(math.max(0, math.min(59, pos - 1)))
  H.BarColor(f.time.bar, pos, st and st.cap or 60)
  f.time.cap:ClearAllPoints()
  f.time.cap:SetPoint("CENTER", f.time.bar, "LEFT", ((st and st.cap or 60) - 1) / 59 * (f.time.bar:GetWidth() or 249), 0)
  f.time.cap:SetShown(st ~= nil)
  local function deaths(n) return n == 1 and "1 morte" or (n .. " morti") end
  -- only the period chosen above: nothing from the other one
  local period = mode == "w" and "'Sta settimana" or "Da sempre"
  SetLines(f.time.lines, {
    { period .. ": " .. Hours(H.StatOf(rec, "pt", mode)) .. " de gioco, " .. deaths(H.StatOf(rec, "dt", mode)) },
    { "PvP: " .. H.StatOf(rec, "hk", mode) .. " uccisioni, " .. U.Thousands(H.StatOf(rec, "hn", mode)) .. " onore" },
    { "" },
  })

  -- titles: one after the other on at most two lines; what doesn't fit goes in "e artri N" (hover to read them)
  for _, b in ipairs(f.titles.items) do b:Hide() end
  local held = ns.Titles and ns.Titles.Held(rec) or {}
  local shown = rec.ti and rec.ti ~= "" and ns.Titles.BY_ID[rec.ti]
  local function item(i)
    local b = f.titles.items[i]
    if not b then
      b = CreateFrame("Button", nil, f.titles)
      b:SetHeight(12)
      b.text = H.Text(b, "GameFontHighlightSmall", "")
      b.text:SetPoint("LEFT")
      if b.text.SetWordWrap then b.text:SetWordWrap(false) end
      b:SetScript("OnEnter", function(self) if self.name then H.Tip(self, { self.name, self.desc }) end end)
      b:SetScript("OnLeave", H.HideTip)
      f.titles.items[i] = b
    end
    return b
  end
  local function width(b) return math.floor((b.text.GetStringWidth and b.text:GetStringWidth() or 60) + 8) end
  local LINES, LEFT, RIGHT, MORE = 2, 10, 259, 64
  local placed, line, x = {}, 1, LEFT
  for i, t in ipairs(held) do
    local b = item(i)
    b.name, b.desc = t.name, t.desc
    b.text:SetText(((shown and shown.id == t.id) and ("|cffffd100" .. t.name .. "|r") or t.name) .. ",")
    local w = width(b)
    if x + w > RIGHT then line, x = line + 1, LEFT end
    -- the last line keeps room for "e artri N" if more titles are coming after this one
    local room = (line == LINES and i < #held) and MORE or 0
    if line > LINES or x + w + room > RIGHT then break end
    placed[#placed + 1] = { b = b, x = x, line = line, w = w }
    x = x + w
  end
  local rest = #held - #placed
  if #placed > 0 and rest == 0 then
    local last = placed[#placed]
    last.b.text:SetText((last.b.text:GetText() or ""):gsub(",$", ""))
  end
  for _, p in ipairs(placed) do
    p.b:SetWidth(p.w)
    p.b:ClearAllPoints()
    p.b:SetPoint("TOPLEFT", p.x, -24 - (p.line - 1) * 12)
    p.b:Show()
  end
  if rest > 0 then
    local more = item(#held + 1)
    local names = {}
    for k = #placed + 1, #held do names[#names + 1] = held[k].name end
    more.name, more.desc = "Artri titoli", table.concat(names, ", ")
    more.text:SetText("e artri " .. rest)
    local lastP = placed[#placed]
    local mx, ml = lastP and (lastP.x + lastP.w) or LEFT, lastP and lastP.line or 1
    if mx + MORE > RIGHT then mx, ml = LEFT, math.min(LINES, ml + 1) end
    more:SetWidth(MORE)
    more:ClearAllPoints()
    more:SetPoint("TOPLEFT", mx, -24 - (ml - 1) * 12)
    more:Show()
  end
  if #held == 0 then
    local b = f.titles.items[1]
    if not b then
      b = CreateFrame("Button", nil, f.titles)
      b:SetHeight(12)
      b.text = H.Text(b, "GameFontHighlightSmall", "")
      b.text:SetPoint("LEFT")
      f.titles.items[1] = b
    end
    b.name, b.desc = nil, nil
    b.text:SetText(GREY .. "Ancora nessun titolo|r")
    b:SetWidth(200)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 10, -24)
    b:Show()
  end

  -- milestones, with who got there first
  local first = {}
  for _, m in ipairs(list) do
    for lv, at in pairs(m.ms or {}) do
      if not first[lv] or at < first[lv].at then first[lv] = { at = at, m = m } end
    end
  end
  local miles = {}
  local since = mode == "w" and WeekStart() or 0
  for lv = 10, 60, 10 do
    local at = rec.ms and rec.ms[lv]
    if mode == "t" or (at and at >= since) then
      local isFirst = at and first[lv] and first[lv].m.guid == rec.guid
      miles[#miles + 1] = { "Livello " .. lv .. (isFirst and " |cffffd100primo der patto|r" or ""), at and U.Day(at) or GREY .. "ancora no|r" }
    end
  end
  if #miles == 0 then miles[1] = { GREY .. "Nessun traguardo 'sta settimana|r" } end
  SetLines(f.miles.lines, miles)
  f.miles.title:SetText("Traguardi")

  -- professions
  local profs = {}
  for _, p in ipairs(rec.pr or {}) do profs[#profs + 1] = { p.n, (p.m and p.m > 0) and (p.l .. "/" .. p.m) or tostring(p.l) } end
  if #profs == 0 then profs[1] = { GREY .. "Nessuna professione condivisa|r" } end
  SetLines(f.prof.lines, profs)

  -- quests
  local qt, qw = H.StatOf(rec, "q", "t"), H.StatOf(rec, "q", "w")
  f.quest.title:SetText("Quest " .. GREY .. (mode == "w" and "'sta settimana" or "da sempre") .. "|r")
  f.quest.sub:SetText((mode == "w" and ("Fatte 'sta settimana: " .. qw) or ("Fatte da sempre: " .. qt)) ..
    ((not you or ns.alt) and (GREY .. "  (pe' zona, più l'urtime 3)|r") or ""))
  local items = QuestLines(rec, you)
  if you and not ns.alt and mode == "t" then
    local before = qt - #T.QuestLog()
    if before > 0 then items[#items + 1] = { GREY .. before .. " fatte prima dell'addon (senza dettagli)|r", "" } end
  end
  if #items == 0 then items[1] = { GREY .. "Ancora nessuna quest|r", "" } end
  for _, r in ipairs(f.quest.rows) do r:Hide() end
  for i, it in ipairs(items) do
    local r = QuestRow(f.quest, i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 14)
    r.left:SetText(it[1])
    r.right:SetText(it[2] or "")
    r:Show()
  end
  f.quest.body:SetHeight(math.max(10, #items * 14))
  H.FitScroll(f.quest.scroll, #items * 14, 136 - 50)

  -- dungeons and rares
  local dg = {}
  local thisWeek = rec.wk and rec.wk == M.WeekIndex(s, U.Now())
  local dsrc = mode == "w" and (thisWeek and rec.dgw or {}) or (rec.dgl or {})
  for name, n in pairs(dsrc) do dg[#dg + 1] = { name, "x" .. n, n = n } end
  table.sort(dg, function(a, b) return a.n > b.n end)
  for _, d in ipairs(dg) do d[1] = d[1] .. " " .. GREY .. d[2] .. "|r" d[2] = nil end
  if #dg == 0 then dg[1] = { GREY .. "Ancora nessuno|r" } end
  SetLines(f.dung.lines, dg)
  f.dung.title:SetText("Dungeon (" .. H.StatOf(rec, "dg", mode) .. ")")
  local rr = {}
  local rsince = mode == "w" and WeekStart() or 0
  for _, x in ipairs(rec.rl or {}) do if (x.at or 0) >= rsince then rr[#rr + 1] = { tostring(x.n) } end end
  if #rr == 0 then rr[1] = { GREY .. "Ancora nessuno|r" } end
  SetLines(f.dung.rares, rr)
  f.dung.rareTitle:SetText("Rari (" .. H.StatOf(rec, "rk", mode) .. ")")
end

----------------------------------------------------------------------
-- Confronto
----------------------------------------------------------------------
local VS = {}
for _, m in ipairs(METRICS) do VS[#VS + 1] = m end
VS[#VS + 1] = DEATHS
local BAR_W = 150

local function BuildVs(v)
  local f = CreateFrame("Frame", nil, v)
  f:SetPoint("TOPLEFT", 0, -28)
  f:SetSize(744, 347)
  v.vs = f
  f.list = MemberList(f, function(guid) vsGuid = guid end)
  f.list:SetPoint("TOPLEFT", 0, 0)
  local box = H.Box(f, 546, 347)
  box:SetPoint("TOPLEFT", 198, 0)
  f.box = box
  local mid = 273
  f.left = H.Text(box, "GameFontNormalLarge", "", 200, "RIGHT")
  f.left:SetPoint("TOPRIGHT", box, "TOPLEFT", mid - 40, -12)
  f.right = H.Text(box, "GameFontNormalLarge", "", 200, "LEFT")
  f.right:SetPoint("TOPLEFT", mid + 40, -12)
  local vsText = H.Text(box, "GameFontNormal", "contro", 60, "CENTER")
  vsText:SetPoint("TOP", box, "TOPLEFT", mid, -14)
  f.rows = {}
  for i, metric in ipairs(VS) do
    local y = -40 - (i - 1) * 18
    local r = {}
    r.label = H.Text(box, "GameFontNormalSmall", metric.title, 100, "CENTER")
    r.label:SetPoint("TOP", box, "TOPLEFT", mid, y)
    r.a = H.Text(box, "GameFontHighlightSmall", "", 70, "RIGHT")
    r.a:SetPoint("TOPRIGHT", box, "TOPLEFT", mid - 54, y)
    r.b = H.Text(box, "GameFontHighlightSmall", "", 70, "LEFT")
    r.b:SetPoint("TOPLEFT", mid + 54, y)
    r.barA = box:CreateTexture(nil, "ARTWORK")
    r.barA:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.barA:SetHeight(4)
    r.barA:SetPoint("TOPRIGHT", box, "TOPLEFT", mid - 54, y - 12)
    r.barB = box:CreateTexture(nil, "ARTWORK")
    r.barB:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.barB:SetHeight(4)
    r.barB:SetPoint("TOPLEFT", mid + 54, y - 12)
    r.metric = metric
    f.rows[i] = r
  end
  local line = box:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 0.82, 0, 0.35)
  line:SetHeight(1)
  line:SetPoint("TOPLEFT", 14, -264)
  line:SetPoint("TOPRIGHT", -14, -264)
  f.h2hTitle = H.Text(box, "GameFontNormal", "Duelli tra voi", 160)
  f.h2hTitle:ClearAllPoints()
  f.h2hTitle:SetPoint("TOP", box, "TOPLEFT", 273, -274)
  f.h2hTitle:SetJustifyH("CENTER")
  f.h2h = H.Text(box, "GameFontNormalHuge", "", 160)
  f.h2h:ClearAllPoints()
  f.h2h:SetPoint("TOP", f.h2hTitle, "BOTTOM", 0, -6)
  f.h2h:SetJustifyH("CENTER")
  f.notes = H.Text(box, "GameFontHighlightSmall", "", 340)
  f.notes:SetPoint("TOPLEFT", 190, -268)
  f.notes:SetJustifyV("TOP")
  f.empty = H.Text(box, "GameFontHighlight", "Scegli 'n membro a sinistra pe' confrontatte co' lui.", 400, "CENTER")
  f.empty:SetPoint("CENTER")
end

local function RefreshVs(v, list)
  local f = v.vs
  local me = ns.MyRecord()
  local other = Find(list, vsGuid)
  if other and me and other.guid == me.guid then other = nil end
  if not other then
    -- default: the member closest to my level
    local bestD
    for _, m in ipairs(list) do
      if me and m.guid ~= me.guid then
        local d = math.abs((m.lv or 0) - (me.lv or 0))
        if not bestD or d < bestD then bestD, other = d, m end
      end
    end
  end
  f.list:Fill(Ordered(list), other and other.guid, me and me.guid)
  local show = me and other
  f.empty:SetShown(not show)
  for _, r in ipairs(f.rows) do
    for _, w in pairs({ r.label, r.a, r.b, r.barA, r.barB }) do w:SetShown(show and true or false) end
  end
  f.left:SetText(show and H.Colored(me) or "")
  f.right:SetText(show and H.Colored(other) or "")
  f.h2hTitle:SetShown(show and true or false)
  f.h2h:SetShown(show and true or false)
  f.notes:SetShown(show and true or false)
  if not show then return end
  for _, r in ipairs(f.rows) do
    local metric = r.metric
    local a, b = Value(metric, me), Value(metric, other)
    local top = math.max(a, b)
    local aWins = metric.low and a < b or (not metric.low and a > b)
    local bWins = metric.low and b < a or (not metric.low and b > a)
    r.label:SetText(metric.title)
    r.a:SetText((aWins and GREEN or WHITE) .. TextOf(metric, me) .. "|r")
    r.b:SetText((bWins and GREEN or WHITE) .. TextOf(metric, other) .. "|r")
    r.barA:SetWidth(top > 0 and math.max(1, a / top * BAR_W) or 1)
    r.barB:SetWidth(top > 0 and math.max(1, b / top * BAR_W) or 1)
    r.barA:SetVertexColor(aWins and 0.1 or 0.45, aWins and 0.75 or 0.45, aWins and 0.1 or 0.45)
    r.barB:SetVertexColor(bWins and 0.1 or 0.45, bWins and 0.75 or 0.45, bWins and 0.1 or 0.45)
  end
  -- duels between the two, from my record (or theirs if I have nothing)
  local h = me.h2h and (me.h2h[other.name] or me.h2h[(tostring(other.name):match("^(%S+)"))])
  local w, l = h and h.w or 0, h and h.l or 0
  if not h and other.h2h then
    local hh = other.h2h[me.name] or other.h2h[(tostring(me.name):match("^(%S+)"))]
    if hh then w, l = hh.l or 0, hh.w or 0 end
  end
  f.h2h:SetText((w + l) > 0 and (GREEN .. w .. "|r - " .. RED .. l .. "|r") or (GREY .. "0 - 0|r"))
  f.notes:SetText("")
end

----------------------------------------------------------------------
local function Build()
  local v = H.NewView("progresso")
  v.tabRank = H.TopTab(v, "Classifiche", function() page = "rank" end)
  v.tabRank:SetPoint("TOPLEFT", 0, 0)
  v.tabDiary = H.TopTab(v, "Diario", function() page = "diary" end)
  v.tabDiary:SetPoint("LEFT", v.tabRank, "RIGHT", 2, 0)
  v.tabVs = H.TopTab(v, "Confronto", function() page = "vs" end)
  v.tabVs:SetPoint("LEFT", v.tabDiary, "RIGHT", 2, 0)
  v.totBtn = H.Radio(v, "Da sempre", function() mode = "t" end)
  v.totBtn:SetPoint("TOPRIGHT", -4, -6)
  v.weekBtn = H.Radio(v, "'Sta settimana", function() mode = "w" end)
  v.weekBtn:SetPoint("RIGHT", v.totBtn, "LEFT", -14, 0)
  BuildCards(v)
  BuildDiary(v)
  BuildVs(v)
end

local function Refresh(v)
  local list = UI.Members()
  v.tabRank:SetSelected(page == "rank")
  v.tabDiary:SetSelected(page == "diary")
  v.tabVs:SetSelected(page == "vs")
  v.weekBtn:SetSelected(mode == "w")
  v.totBtn:SetSelected(mode == "t")
  v.rank:SetShown(page == "rank")
  v.diary:SetShown(page == "diary")
  v.vs:SetShown(page == "vs")
  if page == "rank" then RefreshCards(v, list)
  elseif page == "diary" then RefreshDiary(v, list)
  else RefreshVs(v, list) end
end

UI.AddView("progresso", "Progresso", Build, Refresh, false)
