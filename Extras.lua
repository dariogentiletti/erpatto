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

local function Short(m) return (tostring(m.name or "?"):match("^(%S+)")) or "?" end

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
  d.title = H.Text(d, "GameFontNormalLarge", "", w - 40, "CENTER")
  d.title:SetPoint("TOP", 0, -16)
  d.sub = H.Text(d, "GameFontHighlightSmall", "", w - 40, "CENTER")
  d.sub:SetPoint("TOP", d.title, "BOTTOM", 0, -4)
  local scroll = CreateFrame("ScrollFrame", name .. "Scroll", d, "UIPanelScrollFrameTemplate")
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
-- Come funziona
----------------------------------------------------------------------
X.GUIDE = table.concat({
  "|cffffd100Er cap|r",
  "Ogni settimana c'è 'n livello massimo, diverso pe' ogni squadra (dipende da quante ore a settimana gioca). Nun lo superà: la barretta sotto lo schermo è blu se stai indietro, verde ar cap, rossa se sei scappato avanti. Si 'na quest te farebbe passà er cap, l'addon t'avvisa prima de consegnalla.",
  "",
  "|cffffd100Casa|r",
  "Quello che te serve subito: er cap tuo e che fà mo', chi è online, le notizie (ding, epici, rari, titoli, tombole) e chi guida la settimana. Ar primo login dopo er reset esce Er Bollettino co' la settimana passata.",
  "",
  "|cffffd100Personaggio e Progresso|r",
  "Er personaggio tuo (o de 'n amico) co' l'equipaggiamento e li piazzamenti. In Progresso: le classifiche, le Avventure (fortuna, pesca, raccolta, morti ridicole, nemesi, teste famose...), er Diario de ognuno e er Confronto testa a testa.",
  "",
  "|cffffd100Tombola e Totopatto|r",
  "Ogni settimana 'na cartella 3x3 de sfide, uguale pe' tutti, che se spunta da sola. 1 punto a casella, +2 a riga (terno), +10 si la finisci (tombola). Nei primi 2 giorni de la settimana scommetti su chi sale de più, chi fa più quest e chi more de più: 3 punti a risposta giusta. Li punti fanno la classifica de la stagione.",
  "",
  "|cffffd100Titoli|r",
  "Chi è er primo in quarcosa vince 'n titolo (A Pariolino, A Topo de Fogna...). Lo scegli ner Personaggio, in arto a destra, e compare in chat davanti ar nome. Er titolo se perde si quarcuno te supera. La lista completa sta in Progresso, Titoli.",
  "",
  "|cffffd100Amichi|r",
  "/patto invita Nome: all'amico je compare 'na finestra pe' entrà co' 'n clic. Oppure daje er codice (in Impostazioni). L'addon passa li dati da 'n amico all'artro, quindi basta che uno sia online.",
  "",
  "|cffffd100Comandi|r",
  "/patto apre la finestra, /patto stato er cap in chat, /patto bollettino, /patto condividi (testo pe' Discord), /patto bug (rapporto pe' segnalà 'n problema), /patto hud la barretta.",
}, "\n")

local guide
function X.ShowGuide()
  if not guide then guide = TextDialog("ErPattoGuide", 560, 440, false) end
  guide.title:SetText("Come funziona Er Patto")
  guide.sub:SetText("")
  guide.body:SetText(X.GUIDE)
  local h = (guide.body.GetStringHeight and guide.body:GetStringHeight()) or 600
  guide.bodyFrame:SetHeight(math.max(10, h))
  if ns.db then ns.db.guideSeen = true end
  guide:Show()
end
ns.On("PattoChanged", function(state)
  if state and ns.db and not ns.db.guideSeen and C_Timer then C_Timer.After(3, X.ShowGuide) end
end)

----------------------------------------------------------------------
-- Condividi: plain text for Discord
----------------------------------------------------------------------
function X.ShareText()
  local state = ns.state
  if not (state and P.HasSettings(state)) then return "" end
  local s = state.settings
  local wk = M.WeekIndex(s, U.Now())
  local list = UI.Members()
  local out = {}
  local st = ns.MyStatus()
  out[#out + 1] = "**" .. tostring(s.name or "Er Patto") .. "**, settimana " .. math.max(0, wk) .. (st and not st.lifted and (" (cap " .. st.cap .. ")") or "")
  table.sort(list, function(a, b) return (a.lv or 0) > (b.lv or 0) or ((a.lv or 0) == (b.lv or 0) and tostring(a.name) < tostring(b.name)) end)
  local function W(m, k) local w = m.stats and m.stats.w and m.stats.w[wk] return type(w) == "table" and (w[k] or 0) or 0 end
  for i, m in ipairs(list) do
    if i > 15 then break end
    local title = ns.Titles and ns.Titles.Of(m)
    local up = W(m, "ding")
    out[#out + 1] = i .. ". " .. Short(m) .. " " .. tostring(m.lv or "?") .. (up > 0 and (" (+" .. up .. ")") or "") .. (title and (", " .. title) or "")
  end
  local function lead(label, fn, fmt)
    local best, bv
    for _, m in ipairs(list) do local v = fn(m) if v > 0 and (not bv or v > bv) then best, bv = m, v end end
    if best then out[#out + 1] = label .. ": " .. Short(best) .. " (" .. (fmt and fmt(bv) or bv) .. ")" end
  end
  if wk >= 1 then
    out[#out + 1] = ""
    out[#out + 1] = "'Sta settimana"
    lead("Più quest", function(m) return W(m, "q") end)
    lead("Più ore", function(m) return W(m, "pt") end, function(v) return math.floor(v / 3600) .. " ore" end)
    lead("Più morti", function(m) return W(m, "dt") end)
    lead("Morti ridicole", function(m) return W(m, "em") end)
    lead("Più fortunato", function(m) return W(m, "lb") + 5 * W(m, "le") end, function() return "che culo" end)
    if ns.Tombola then lead("Tombola", function(m) local sc = ns.Tombola.Score(m, wk) return sc and sc.points or 0 end, function(v) return v .. " punti" end) end
    local wipes = ns.News and ns.News.WipeCount() or 0
    if wipes > 0 then out[#out + 1] = "Wipe der patto: " .. wipes end
  end
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
