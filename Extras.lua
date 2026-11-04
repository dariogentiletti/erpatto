-- Er Patto: the small things that make it feel finished.
--   * a minimap button (click: the window; drag: move it round the minimap)
--   * a line on the tooltip of patto members you meet in the world: title, level against the cap
--   * a warning when a friend runs a newer version
--   * "Come funziona": a short guide, shown once when you join a patto
--   * "Condividi": the week as plain text, ready to paste on Discord
--   * /patto bug: the diagnostics report, ready to copy
local ADDON, ns = ...
local U, M, P, C, T, UI = ns.U, ns.M, ns.P, ns.C, ns.T, ns.UI
local H = UI.H
local X = {}
ns.Extras = X

local function Short(m) return U.Short(m and m.name) end

----------------------------------------------------------------------
-- versions: "0.10.2" -> comparable; "dev" (a copy from git) is never compared
----------------------------------------------------------------------
function X.VersionKey(v)
  if type(v) ~= "string" then return nil end
  local a, b, c = v:match("^v?(%d+)%.(%d+)%.?(%d*)")
  if not a then return nil end
  return tonumber(a) * 1e6 + tonumber(b) * 1e3 + (tonumber(c) or 0)
end

local told = false
local function CheckVersion(rec)
  if told or not rec or rec.guid == ns.recordGuid then return end
  local mine, theirs = X.VersionKey(ns.VERSION), X.VersionKey(rec.ver)
  if mine and theirs and theirs > mine then
    told = true
    U.Say(Short(rec) .. " usa Er Patto " .. tostring(rec.ver) .. ", tu la " .. ns.VERSION .. ": aggiorna da CurseForge, sennò te perdi le cose nove.")
  end
end
ns.On("MemberUpdated", CheckVersion)
ns.On("Login", function()
  if C_Timer then C_Timer.After(40, function()
    for _, r in pairs(ns.state and ns.state.members or {}) do CheckVersion(r) end
  end) end
end)

----------------------------------------------------------------------
-- minimap button, the vanilla way (tracking border, round icon)
----------------------------------------------------------------------
local mm
local function PlaceButton()
  local a = math.rad(ns.db.ui.mmAngle or 200)
  local r = (Minimap:GetWidth() or 140) / 2 + 10
  mm:ClearAllPoints()
  mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function X.MinimapButton()
  if not Minimap or not ns.db then return end
  if not mm then
    mm = CreateFrame("Button", "ErPattoMinimapButton", Minimap)
    mm:SetSize(31, 31)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(8)
    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")
    local bg = mm:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    local icon = mm:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = mm:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    mm:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
        ns.db.opts.hud = not ns.db.opts.hud
        ns.Fire("Refresh")
      else
        UI.Toggle()
      end
    end)
    mm:SetScript("OnDragStart", function(self)
      self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / scale, cy / scale
        ns.db.ui.mmAngle = math.deg(math.atan2(cy - my, cx - mx))
        PlaceButton()
      end)
    end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnEnter", function(self)
      local st = ns.MyStatus and ns.MyStatus()
      local lines = { "Er Patto" }
      if st and not st.lifted then lines[#lines + 1] = "Cap " .. st.cap .. (st.started and "" or (", se parte tra " .. U.Until(ns.state.settings.start - U.Now()))) end
      lines[#lines + 1] = "|cff9d9d9dClic: apre. Destro: la barretta der cap. Trascina pe' spostà.|r"
      H.Tip(self, lines)
    end)
    mm:SetScript("OnLeave", H.HideTip)
  end
  PlaceButton()
  mm:SetShown(ns.db.opts.minimap ~= false)
end
ns.On("Login", X.MinimapButton)
ns.On("Refresh", function() if mm then mm:SetShown(ns.db.opts.minimap ~= false) end end)

----------------------------------------------------------------------
-- tooltips of patto members met in the world
----------------------------------------------------------------------
local function TooltipLine(tt, unit)
  if not (ns.state and unit and tt and tt.AddLine) then return end
  local guid = U.Plain(UnitGUID and UnitGUID(unit), "string")
  local rec = guid and ns.state.members[guid]
  if not rec then return end
  local parts = { "|cffffd100Er Patto|r" }
  local title = ns.Titles and ns.Titles.Of(rec)
  if title then parts[#parts + 1] = "|cffffd100" .. title .. "|r" end
  if rec.team and P.HasSettings(ns.state) then
    local st = M.Status(ns.state.settings, rec.team, U.Now())
    if st and st.started and not st.lifted then parts[#parts + 1] = "cap " .. st.cap .. " " .. H.StateText(rec.lv, st.cap) end
  end
  tt:AddLine(table.concat(parts, "  "))
  if tt.Show then tt:Show() end
end

ns.On("Login", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Unit, function(tt)
      if tt ~= GameTooltip or not tt.GetUnit then return end
      local ok, _, unit = pcall(tt.GetUnit, tt)
      if ok then pcall(TooltipLine, tt, unit) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt)
      local ok, _, unit = pcall(tt.GetUnit, tt)
      if ok then pcall(TooltipLine, tt, unit) end
    end)
  end
end)
X.TooltipLine = TooltipLine

----------------------------------------------------------------------
-- a dialog with a scrolling text: the guide, and the text to share
----------------------------------------------------------------------
local function TextDialog(name, w, h, editable)
  local d = CreateFrame("Frame", name, UIParent)
  d:SetSize(w, h)
  d:SetPoint("CENTER", 0, 40)
  d:SetFrameStrata("DIALOG")
  d:SetToplevel(true)
  d:EnableMouse(true)
  d:SetMovable(true)
  d:RegisterForDrag("LeftButton")
  d:SetScript("OnDragStart", d.StartMoving)
  d:SetScript("OnDragStop", d.StopMovingOrSizing)
  H.Chrome(d)
  d.title = H.DialogHeader(d, "", 320)
  d.sub = H.Text(d, "GameFontHighlightSmall", "", w - 40, "CENTER")
  d.sub:SetPoint("TOP", 0, -32)
  local scroll = CreateFrame("ScrollFrame", name .. "Scroll", d, "UIPanelScrollFrameTemplate")
  UI.H.VanillaScroll(scroll)
  scroll:SetPoint("TOPLEFT", 20, -58)
  scroll:SetPoint("BOTTOMRIGHT", -38, 46)
  d.scroll = scroll
  if editable then
    local e = CreateFrame("EditBox", nil, scroll)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetWidth(w - 70)
    e:SetScript("OnEscapePressed", function() d:Hide() end)
    e:SetScript("OnTextChanged", function(self, user) if user and d.text then self:SetText(d.text) self:HighlightText() end end)
    scroll:SetScrollChild(e)
    d.edit = e
  else
    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(w - 70, 10)
    d.body = H.Text(body, "GameFontHighlight", "", w - 70)
    d.body:SetPoint("TOPLEFT")
    d.body:SetJustifyV("TOP")
    scroll:SetScrollChild(body)
    d.bodyFrame = body
  end
  d.ok = H.Btn(d, "Chiudi", 110, function() d:Hide() end)
  d.ok:SetPoint("BOTTOM", 0, 14)
  if UISpecialFrames then table.insert(UISpecialFrames, name) end
  d:Hide()
  return d
end

----------------------------------------------------------------------
-- what each tab is for: the tooltip of the "i" at the top right of the window
----------------------------------------------------------------------
X.INFO = {
  casa = { "Baretto", "Er cap tuo e che fà mo', chi è online, le notizie der patto e chi guida la settimana.",
    "Ar primo login dopo er reset esce er Bollettino co' la settimana passata: la settimana tua, li titoli, le piotte, li ricchi, er cimitero, er Colosseo, le tombole e la schedina." },
  pg = { "Personaggio", "Er personaggio tuo o de 'n amico (lo scegli a destra): equipaggiamento e piazzamenti ner patto.",
    "Er bottone Titolo sceje er titolo che mostri in chat davanti ar nome." },
  cap = { "Cap", "Ogni settimana c'è 'n livello massimo pe' squadra, che dipende da quante ore gioca. Nun lo superà.",
    "La barretta sotto lo schermo è blu si stai indietro, verde ar cap, rossa sopra. Si 'na quest te fa passà er cap, l'addon t'avvisa prima.",
    "Sotto: er calendario de li cap de tutte le squadre." },
  gruppi = { "Squadre", "Le squadre der patto, chi c'è e a che livello sta. \"Passa qui\" pe' cambià squadra." },
  progresso = { "Progresso", "Corsa: chi va più forte (livelli, ore, quest, dungeon, sordi, rari, PvP).",
    "Chicche: fortuna, pesca, raccolta, strada, morti ridicole, boss, nemesi.",
    "Titoli: chi è er primo in quarcosa vince 'n titolo, che compare in chat davanti ar nome.",
    "Diario: la settimana de ognuno. Confronto: tu contro 'n amico.",
    "Cimitero: tutti li morti der patto, co' l'urtime parole scritte in chat prima de morì, e chi sta a la gogna.",
    "Er duello a la gogna (tasto destro su 'n amico): parte la richiesta de duello der gioco, e accettalla vor dì accettà la gogna. Chi perde sta a la gogna 'n giorno, e chi vince sceje er pegno: la pecora (ogni tanto, in mezzo a lo schermo: \"Ricordate che Dario te ha 'mpecorato\"), er burattino, er verso, er piagnone, lo strillone, er servo, er karaoke o er Giampaolato. L'icona de la gogna sotto la barretta der cap dice che te succede.",
    "Chi perde pò chiede la rivincita entro 10 minuti; si l'artro la perde, pò chiede la bella. Chi chiede la rivincita (o la bella) e la perde sta a la gogna 'na settimana. Chi sta a la gogna nun ne pò fà; chi vince, invece, pò sfidà chi je pare.",
    "Er Campione: chi manna a la gogna er campione se pija la corona.",
    "'Sta settimana e Da sempre cambiano er periodo contato." },
  -- the Botteghino has one text per tab of its own (botteghino:<page>); this one is the fallback
  botteghino = { "Botteghino", "Se gioca a piotte, li sordi finti der patto: se parte co' 20, e ogni ora in gruppo co' quarcuno der patto te dà 'na piotta." },
  ["botteghino:tombola"] = { "Tombola", "'Na cartella de 9 imprese a settimana, uguale pe' tutti.",
    "1 piotta a casella, +2 a terno, +10 tombola.", "Si 'na casella nun se pò fà, er capo la pò cambià." },
  ["botteghino:schedina"] = { "Schedina", "Tre domande nove ogni settimana: chi sale de più, chi pesca de più, chi more de più...",
    "Se gioca dar reset fino ar sabato sera; poi se pò ancora ribartà tutto, e ar reset de mercoledì se paga (la linea in arto lo fa vede).",
    "Una giocata pe' domanda, ar massimo 25 piotte, e nun se cambia. Mai su te stesso o su 'n alt tuo.",
    "Più piotte ce stanno sopra a uno, meno paga: vinci la posta per la quota de quanno hai puntato. Chi azzecca dove nessuno punta vince de più." },
  ["botteghino:sfide"] = { "Sfide", "Sfidi 'n amico a chi fa de più (quest, sordi, pesci...) o a chi arriva prima ar livello, fino a la fine de la settimana. Chi vince se pija la posta.",
    "Taja: piotte su la testa de quarcuno, se le pija chi lo batte a duello.",
    "Gufata (tasto destro su 'n amico): scommetti che more entro 5 minuti. Si more vinci mezza posta, si campa se la pija lui.",
    "Duelli: quanno due der patto se menano, chi sta ne la stessa zona pò puntà su uno: chi indovina raddoppia.",
    "Sfotti (tasto destro su 'n amico): pe' 3 piotte je scrivi grosso sur su' schermo 'na frase su li numeri sua." },
  ["botteghino:conti"] = { "Scontrini", "Ogni piotta che hai messo e preso, riga pe' riga. Scegli 'n amico pe' vede li sua.",
    "Se parte co' 20 piotte, e ogni ora in gruppo co' quarcuno der patto te ne dà una." },
  ["botteghino:ricchi"] = { "Li ricchi", "Chi c'ha più piotte.",
    "Schedine: quante n'ha vinte su quante n'ha giocate. Resa: quanto j'hanno fruttato le piotte puntate; dice chi è bravo davero." },
  imp = { "Impostazioni", "Er codice pe' fa' entrà l'amichi, l'inviti e l'opzioni." },
  capo = { "Capo", "Solo pe' er capo: squadre, ore, partenza, annunci e vice.",
    "\"Addon spento\" vicino a 'n nome: ha giocato senza addon (lo dice er /played suo quanno lo riaccenne) o l'hanno visto online in gilda, in gruppo o in chat co' l'addon zitto. Er mouse sopra pe' li dettagli." },
}

----------------------------------------------------------------------
-- Condividi: plain text for Discord
----------------------------------------------------------------------
-- the week as a Discord message: the same things Er Bollettino tells, as text (Discord turns :trophy: and the
-- others into emoji when it's sent; the ``` block keeps the table straight)
function X.ShareText()
  local state = ns.state
  if not (state and P.HasSettings(state)) then return "" end
  local s = state.settings
  local wk = math.max(1, M.WeekIndex(s, U.Now()))
  local B = ns.Bollettino
  local d = B and B.Data and B.Data(wk, true)
  local function plain(t) return (tostring(t or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|", "")) end
  local function money(c)
    c = math.floor(c or 0)
    local g, sv, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    if g > 0 then return g .. "g " .. sv .. "s" end
    if sv > 0 then return sv .. "s " .. cu .. "c" end
    return cu .. "c"
  end
  local out = {}
  local function add(t) out[#out + 1] = t end
  local st = ns.MyStatus()
  add("**" .. plain(s.name or "Er Patto") .. "**, settimana " .. wk .. (st and not st.lifted and (" (cap " .. st.cap .. ")") or ""))
  if d and d.head then add(":newspaper: " .. plain(d.head.title) .. (d.head.sub and (", " .. plain(d.head.sub)) or "")) end
  -- the race: level, the levels of the week, against the cap
  local list = UI.Members()
  table.sort(list, function(a, b) return (a.lv or 0) > (b.lv or 0) or ((a.lv or 0) == (b.lv or 0) and tostring(a.name) < tostring(b.name)) end)
  local function W(m, k) return ns.Tombola and ns.Tombola.Weekly(m, wk)[k] or 0 end
  add("") add(":checkered_flag: **La corsa**") add("```")
  for i, m in ipairs(list) do
    if i > 20 then break end
    local up = W(m, "ding")
    local mst = m.team and M.Status(s, m.team, U.Now())
    local vs = ""
    if mst and mst.started and not mst.lifted then
      local ps, dd = M.PlayerState(m.lv or 1, mst.cap)
      vs = ps == "over" and ("+" .. dd .. " sopra er cap") or ps == "at" and "ar cap" or ("-" .. dd)
    end
    add(string.format("%2d. %-12s %2s %-5s %s", i, Short(m):sub(1, 12), tostring(m.lv or "?"), up > 0 and ("+" .. up) or "", vs))
  end
  add("```")
  if d then
    if #d.titles > 0 then
      local t = {}
      for i = 1, math.min(6, #d.titles) do t[#t + 1] = plain(d.titles[i].t.name) .. ": " .. Short(d.titles[i].m) end
      add(":crown: **Titoli de la settimana:** " .. table.concat(t, ", "))
    end
    local p = {}
    for i = 1, math.min(3, #d.rich) do p[#p + 1] = i .. ". " .. Short(d.rich[i].m) .. " " .. d.rich[i].total .. (d.rich[i].week ~= 0 and (" (" .. (d.rich[i].week > 0 and "+" or "") .. d.rich[i].week .. ")") or "") end
    if #p > 0 then add(":moneybag: **Le piotte:** " .. table.concat(p, ", ")) end
    local g = {}
    for i = 1, math.min(3, #d.gold) do g[#g + 1] = Short(d.gold[i].m) .. " +" .. money(d.gold[i].g) end
    if #g > 0 then add(":coin: **Li ricchi (fatti 'sta settimana):** " .. table.concat(g, ", ")) end
    local dd = d.dead
    if dd.total > 0 then
      local t = { dd.total .. " morti" }
      if dd.most then t[#t + 1] = "er più morto " .. Short(dd.most) .. " (" .. dd.mostN .. ")" end
      if dd.silly then t[#t + 1] = "er più scemo " .. Short(dd.silly) .. (dd.words and (", ultime parole: \"" .. plain(dd.words) .. "\"") or "") end
      if dd.killer then t[#t + 1] = "er boia " .. plain(dd.killer) .. " (" .. dd.kills .. ")" end
      add(":skull: **Er cimitero:** " .. table.concat(t, "; "))
    else
      add(":angel: **Er cimitero:** nessun morto")
    end
    local a = d.arena
    local t = {}
    if a.fought > 0 then t[#t + 1] = a.fought .. " duelli a la gogna" end
    for i = 1, math.min(3, #a.gogne) do local x = a.gogne[i] t[#t + 1] = Short(x.w) .. " ha messo a la gogna " .. Short(x.l) .. (x.pena and (" (" .. plain(x.pena.name):lower() .. ")") or "") end
    if a.bully then t[#t + 1] = "er bullo " .. Short(a.bully) .. " (" .. a.bullyN .. " vinti)" end
    if #t > 0 then add(":crossed_swords: **Er Colosseo:** " .. table.concat(t, "; ")) end
    local tb = {}
    for i, c in ipairs(d.cards) do tb[#tb + 1] = Short(c.m) .. " " .. (c.sc.full and "TOMBOLA!" or (c.sc.cells .. "/9")) end
    if #tb > 0 then add(":ticket: **Tombola:** " .. table.concat(tb, ", ")) end
    local q = {}
    for _, x in ipairs(d.questions) do q[#q + 1] = plain(x.text) .. " " .. (#x.names > 0 and plain(x.names[1]) or "nessuno") end
    if #q > 0 then add(":memo: **Schedina:** " .. table.concat(q, " / ")) end
  end
  local wipes = ns.News and ns.News.WipeCount() or 0
  if wipes > 0 then add(":boom: **Wipe der patto:** " .. wipes) end
  return table.concat(out, "\n")
end

local share
function X.ShowShare()
  if not ns.state then U.Say("prima entra in un patto.") return end
  if not share then share = TextDialog("ErPattoShare", 460, 380, true) end
  share.title:SetText("Condividi")
  share.sub:SetText("Ctrl+A e Ctrl+C, poi incolla su Discord.")
  share.text = X.ShareText()
  share.edit:SetText(share.text)
  share:Show()
  share.edit:SetFocus()
  share.edit:HighlightText()
end

function X.BugReport()
  if not ns.Diag then return end
  ns.Diag.EnvReport()
  ns.Diag.Toggle()
  U.Say("ner registro (in basso) c'è er rapporto: selezionalo, Ctrl+C, e mannalo a chi cura l'addon.")
end
