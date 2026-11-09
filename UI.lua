-- Er Patto: the window (vanilla look from the game's own textures), the small cap bar and the quest warning.
local ADDON, ns = ...
local U, M, P, C, T = ns.U, ns.M, ns.P, ns.C, ns.T
local UI = {}
ns.UI = UI

local BD = BackdropTemplateMixin and "BackdropTemplate" or nil
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"

-- (77 taller than the first versions: Progresso shows three rows of rankings)
local W, H = 780, 534
local TAB_H = 30 -- how far the bottom tabs hang under the window
local f, content
local views, tabs = {}, {}
local current = "casa"
local refreshing = false

----------------------------------------------------------------------
-- small builders
----------------------------------------------------------------------
local function Safe(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then U.Log("Errore", "UI", err) end
end

-- The frame art:
--   borders  the game's own vanilla stat-box art (UI-Character-StatBackground): its thin metal rail, cut in nine
--            pieces (four corners, four edges) of 6 px, so every border here is the one of the vanilla character frame
--   marble   the game's own seamless marble (FrameGeneral\\UI-Background-Marble, 256x256, the same dark marble as the
--            vanilla frames), repeated at its own size: the inside of the window and of every panel
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local TILE = 256
local RAIL_FILE = "Interface\\PaperDollInfoFrame\\UI-Character-StatBackground"
local RS = 6 -- piece size: outer glow, the rail (2 px in), the shadow on the stone
local P_TL, P_TR, P_BL, P_BR, P_T, P_B, P_L, P_R = 0, 1, 2, 3, 4, 5, 6, 7
-- where each piece sits in the 128x128 texture (left, right, top, bottom in pixels); the edges are plain stretches
-- of rail with no studs, so they can be stretched to any length
local PIECES = {
  [P_TL] = { 0, 6, 0, 6 }, [P_TR] = { 110, 116, 0, 6 }, [P_BL] = { 0, 6, 73, 79 }, [P_BR] = { 110, 116, 73, 79 },
  [P_T] = { 8, 30, 0, 6 }, [P_B] = { 8, 30, 73, 79 }, [P_L] = { 0, 6, 8, 40 }, [P_R] = { 110, 116, 8, 24 },
}

-- the stone, at a random spot of the tile so two panels never look the same; Fit(w, h[, x, y]) places it
-- (x, y from the frame's top left) keeping the pattern fixed to the frame, so pieces of it join without seams
local function Stone(frame, ox, oy, dark)
  local t = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
  t:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
  local k = 1
  t:SetVertexColor(k, k, k)
  local st = { tex = t, u0 = math.random(0, TILE - 1), v0 = math.random(0, TILE - 1) }
  function st:Fit(w, h, x, y)
    x, y = x or ox, y or oy
    w, h = math.max(1, w), math.max(1, h)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    local u, v = (self.u0 + x) / TILE, (self.v0 + y) / TILE
    t:SetTexCoord(u, u + w / TILE, v, v + h / TILE)
  end
  return st
end

local function RailTex(frame, kind, i, layer, sub)
  local t = frame:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
  t:SetTexture(RAIL_FILE)
  local c = PIECES[i]
  t:SetTexCoord(c[1] / 128, c[2] / 128, c[3] / 128, c[4] / 128)
  return t
end

-- place a texture by its top left corner inside a frame; nothing to draw hides it
local function Put(t, frame, x, y, w, h)
  t:ClearAllPoints()
  if w < 1 or h < 1 then t:Hide() return end
  t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
  t:SetSize(w, h)
  t:Show()
end

-- a rail border that follows the frame's size: corners pinned, edges stretched between them.
-- noBottom/noTop leave that side open (tabs)
local function Border(frame, kind, layer, sub, open)
  local s = RS
  local p = {}
  for i = 0, 7 do p[i] = RailTex(frame, kind, i, layer, sub) end
  for i = 0, 3 do p[i]:SetSize(s, s) end
  p[P_TL]:SetPoint("TOPLEFT") p[P_TR]:SetPoint("TOPRIGHT")
  p[P_BL]:SetPoint("BOTTOMLEFT") p[P_BR]:SetPoint("BOTTOMRIGHT")
  p[P_T]:SetPoint("TOPLEFT", p[P_TL], "TOPRIGHT") p[P_T]:SetPoint("BOTTOMRIGHT", p[P_TR], "BOTTOMLEFT")
  p[P_B]:SetPoint("TOPLEFT", p[P_BL], "TOPRIGHT") p[P_B]:SetPoint("BOTTOMRIGHT", p[P_BR], "BOTTOMLEFT")
  if open == "bottom" then
    for _, i in ipairs({ P_BL, P_BR, P_B }) do p[i]:Hide() end
    p[P_L]:SetPoint("TOPLEFT", p[P_TL], "BOTTOMLEFT") p[P_L]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", s, 0)
    p[P_R]:SetPoint("TOPLEFT", p[P_TR], "BOTTOMLEFT") p[P_R]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
  elseif open == "top" then
    for _, i in ipairs({ P_TL, P_TR, P_T }) do p[i]:Hide() end
    p[P_L]:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0) p[P_L]:SetPoint("BOTTOMRIGHT", p[P_BL], "TOPRIGHT")
    p[P_R]:SetPoint("TOPLEFT", frame, "TOPRIGHT", -s, 0) p[P_R]:SetPoint("BOTTOMRIGHT", p[P_BR], "TOPRIGHT")
  else
    p[P_L]:SetPoint("TOPLEFT", p[P_TL], "BOTTOMLEFT") p[P_L]:SetPoint("BOTTOMRIGHT", p[P_BL], "TOPRIGHT")
    p[P_R]:SetPoint("TOPLEFT", p[P_TR], "BOTTOMLEFT") p[P_R]:SetPoint("BOTTOMRIGHT", p[P_BR], "TOPRIGHT")
  end
  return p
end

-- stone that refits itself whenever the frame changes size
local function FitStone(frame, inset, dark)
  local st = Stone(frame, inset, inset, dark)
  local function fit()
    local w, h = frame:GetSize()
    if w and h and w > 2 * inset and h > 2 * inset then st:Fit(w - 2 * inset, h - 2 * inset) end
  end
  fit()
  if frame.HookScript then frame:HookScript("OnSizeChanged", fit) end
  st.Refit = fit
  return st
end

-- The vanilla art everything is drawn with (all the game's own files):
--   GENERAL  the character frame (UI-Character-General): the window, and its dark marble for every inside
--   SLOTS    the frames round the weapon slots (UI-Character-CharacterTab-BottomLeft): a metal frame with a rivet in
--            each corner; cut in corners and edges it frames every panel
--   DIALOG   the dialog box (UI-DialogBox-Border/Background) for popups, as the game menu and the confirmations
local GENERAL = "Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft"
local SLOTS = "Interface\\PaperDollInfoFrame\\UI-Character-CharacterTab-BottomLeft"
local SC = 12 -- corner size of the slot frame
local SX, SY = 113, 121 -- the slot frame's top left in its 256x256 file

-- Fill a region with a piece of a texture at its own size (never stretched), repeated; every other copy mirrored so
-- the copies meet without a seam. tileX/tileY false: that direction is stretched instead (plain rails).
-- file sizes fw, fh; source sx0..sx1, sy0..sy1 in pixels; target x, y (down), w, h inside frame
local function Tile(frame, file, fw, fh, sx0, sy0, sx1, sy1, x, y, w, h, layer, sub, tileX, tileY)
  local out = {}
  local tw, th = sx1 - sx0, sy1 - sy0
  if tileX == false then tw = w end
  if tileY == false then th = h end
  local j, yy = 0, 0
  while yy < h - 0.5 do
    local ph = math.min(th, h - yy)
    local i, xx = 0, 0
    while xx < w - 0.5 do
      local pw = math.min(tw, w - xx)
      local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
      t:SetTexture(file)
      local l, r, tp, bt
      if tileX == false then l, r = sx0, sx1
      elseif i % 2 == 0 then l, r = sx0, sx0 + pw else l, r = sx1, sx1 - pw end
      if tileY == false then tp, bt = sy0, sy1
      elseif j % 2 == 0 then tp, bt = sy0, sy0 + ph else tp, bt = sy1, sy1 - ph end
      t:SetTexCoord(l / fw, r / fw, tp / fh, bt / fh)
      Put(t, frame, x + xx, y + yy, pw, ph)
      out[#out + 1] = t
      xx, i = xx + pw, i + 1
    end
    yy, j = yy + ph, j + 1
  end
  return out
end

-- the dark marble of the character frame's inside (UI-Character-General-TopLeft, 24..250 x 80..250, for small pieces)
-- and, for areas, the seamless tile made from it, repeated at its own size
local MX0, MY0, MX1, MY1 = 24, 80, 250, 250
-- The marble: the inside of the vanilla character frame (UI-Character-General, the four files together make a
-- 384x512 picture; its marble runs from 26..330 x 84..422), laid at its own size in copies side by side, every
-- other copy mirrored so they meet without a seam. It is the same art as the window's border, so it always loads
-- (the game's separate marble file draws nothing in some clients).
local GEN = "Interface\\PaperDollInfoFrame\\UI-Character-General-"
local PX0, PY0, PX1, PY1 = 26, 84, 330, 422
-- a piece of the 384x512 picture (cx0..cx1, cy0..cy1) drawn 1:1 at x, y (down) in the frame, maybe mirrored
local function Patch(frame, out, cx0, cy0, cx1, cy1, x, y, flipX, flipY, layer, sub)
  local xs = { cx0 }
  if cx0 < 256 and cx1 > 256 then xs[#xs + 1] = 256 end
  xs[#xs + 1] = cx1
  local ys = { cy0 }
  if cy0 < 256 and cy1 > 256 then ys[#ys + 1] = 256 end
  ys[#ys + 1] = cy1
  for i = 1, #xs - 1 do
    for j = 1, #ys - 1 do
      local a0, a1, b0, b1 = xs[i], xs[i + 1], ys[j], ys[j + 1]
      local right, bottom = a0 >= 256, b0 >= 256
      local ox, oy, fw = right and 256 or 0, bottom and 256 or 0, right and 128 or 256
      local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -7)
      t:SetTexture(GEN .. (bottom and "Bottom" or "Top") .. (right and "Right" or "Left"))
      local l, r, tp, bt = (a0 - ox) / fw, (a1 - ox) / fw, (b0 - oy) / 256, (b1 - oy) / 256
      if flipX then l, r = r, l end
      if flipY then tp, bt = bt, tp end
      t:SetTexCoord(l, r, tp, bt)
      local dx = flipX and (x + (cx1 - a1)) or (x + (a0 - cx0))
      local dy = flipY and (y + (cy1 - b1)) or (y + (b0 - cy0))
      Put(t, frame, dx, dy, a1 - a0, b1 - b0)
      out[#out + 1] = t
    end
  end
end

-- the marble as an endless plane of copies (every other one mirrored) whose grid starts at gx, gy; draw the part
-- that falls in x, y, w, h. Two areas drawn with the same grid join with no break (the window and its selected tab)
local function MarblePlane(frame, gx, gy, x, y, w, h, layer, sub, out)
  out = out or {}
  local TW, TH = PX1 - PX0, PY1 - PY0
  for j = math.floor((y - gy) / TH), math.floor((y + h - 1 - gy) / TH) do
    for i = math.floor((x - gx) / TW), math.floor((x + w - 1 - gx) / TW) do
      local tx, ty = gx + i * TW, gy + j * TH
      local ix0, ix1 = math.max(x, tx), math.min(x + w, tx + TW)
      local iy0, iy1 = math.max(y, ty), math.min(y + h, ty + TH)
      if ix1 - ix0 >= 1 and iy1 - iy0 >= 1 then
        local flipX, flipY = i % 2 ~= 0, j % 2 ~= 0
        local u0, u1, v0, v1 = ix0 - tx, ix1 - tx, iy0 - ty, iy1 - ty
        local cx0 = flipX and (PX1 - u1) or (PX0 + u0)
        local cy0 = flipY and (PY1 - v1) or (PY0 + v0)
        Patch(frame, out, cx0, cy0, cx0 + (u1 - u0), cy0 + (v1 - v0), ix0, iy0, flipX, flipY, layer, sub)
      end
    end
  end
  return out
end

local function MarbleTiles(frame, x, y, w, h, layer, sub)
  return MarblePlane(frame, x, y, x, y, w, h, layer, sub)
end

-- one piece of marble at its own size, for a small frame (w x h at most 226 x 170)
local function Marble(frame, layer, sub, w, h)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -7)
  t:SetTexture(GENERAL)
  w, h = math.min(w or 140, MX1 - MX0), math.min(h or 100, MY1 - MY0)
  local u0 = math.random(MX0, MX1 - w)
  local v0 = math.random(MY0, MY1 - h)
  t:SetTexCoord(u0 / 256, (u0 + w) / 256, v0 / 256, (v0 + h) / 256)
  return t
end

-- the slot frame round a frame: corners with the rivet, edges stretched (the right and bottom ones mirrored)
local function SlotBorder(frame, layer, sub, w, h)
  local p = {}
  local function piece(x0, y0, w, h, flipX, flipY)
    local t = frame:CreateTexture(nil, layer or "BORDER", nil, sub or 0)
    t:SetTexture(SLOTS)
    local l, r, tp, bt = x0 / 256, (x0 + w) / 256, y0 / 256, (y0 + h) / 256
    if flipX then l, r = r, l end
    if flipY then tp, bt = bt, tp end
    t:SetTexCoord(l, r, tp, bt)
    p[#p + 1] = t
    return t
  end
  local tl = piece(SX, SY, SC, SC) tl:SetSize(SC, SC) tl:SetPoint("TOPLEFT")
  local tr = piece(SX, SY, SC, SC, true) tr:SetSize(SC, SC) tr:SetPoint("TOPRIGHT")
  local bl = piece(SX, SY, SC, SC, false, true) bl:SetSize(SC, SC) bl:SetPoint("BOTTOMLEFT")
  local br = piece(SX, SY, SC, SC, true, true) br:SetSize(SC, SC) br:SetPoint("BOTTOMRIGHT")
  -- the rails: a one pixel cut across the rail, drawn along its whole length, so the line is smooth as in the game
  local t = piece(SX + SC + 4, SY, 1, SC) t:SetPoint("TOPLEFT", tl, "TOPRIGHT") t:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
  local b = piece(SX + SC + 4, SY, 1, SC, false, true) b:SetPoint("TOPLEFT", bl, "TOPRIGHT") b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
  local l = piece(SX, SY + SC + 4, SC, 1) l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT") l:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
  local r = piece(SX, SY + SC + 4, SC, 1, true) r:SetPoint("TOPLEFT", tr, "BOTTOMLEFT") r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
  return p
end

-- a popup in the vanilla dialog box (the game menu, the confirmations)
local DIALOG = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } }
local function Chrome(frame)
  if not frame.SetBackdrop and BackdropTemplateMixin and Mixin then
    Mixin(frame, BackdropTemplateMixin)
    if frame.OnBackdropLoaded then pcall(frame.OnBackdropLoaded, frame) end
    if frame.HookScript and frame.OnBackdropSizeChanged then frame:HookScript("OnSizeChanged", frame.OnBackdropSizeChanged) end
  end
  if frame.SetBackdrop then frame:SetBackdrop(DIALOG) end
  -- not see-through: the dark marble of the main window inside the border, laid again whenever the window changes
  -- size (a dialog grows or shrinks with its text), and the dialog box's own black background left out
  if not frame.ground then
    frame.ground = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.ground:SetColorTexture(0.05, 0.05, 0.05, 1)
    frame.ground:SetPoint("TOPLEFT", 12, -12)
    frame.ground:SetPoint("BOTTOMRIGHT", -12, 12)
    frame.marble = {}
    local lastW, lastH
    local function Lay()
      local w, h = frame:GetWidth(), frame:GetHeight()
      if type(w) ~= "number" or type(h) ~= "number" or w <= 40 or h <= 40 then return end
      w, h = math.floor(w + 0.5), math.floor(h + 0.5)
      if w == lastW and h == lastH then return end
      lastW, lastH = w, h
      for _, t in ipairs(frame.marble) do t:Hide() end
      frame.marble = MarbleTiles(frame, 12, 12, w - 24, h - 24, "BACKGROUND", -7) or {}
    end
    Lay()
    if frame.HookScript then frame:HookScript("OnSizeChanged", Lay) end
    frame.LayMarble = Lay
  end
  if frame.SetBackdropColor then frame:SetBackdropColor(0, 0, 0, 0) end
  frame.stone = { Refit = function() end }
  return frame.stone
end

-- the header plate of the dialog box, with a title on it: the plate's two ends as they are, its middle stretched
-- to the title (UI-DialogBox-Header: the plate sits at 118..394 x 2..80 of the 512x128 file)
local function DialogHeader(frame, text, minW)
  local HDR = "Interface\\DialogFrame\\UI-DialogBox-Header"
  local function piece(x0, x1)
    local t = frame:CreateTexture(nil, "ARTWORK")
    t:SetTexture(HDR)
    t:SetTexCoord(x0 / 512, x1 / 512, 2 / 128, 80 / 128)
    t:SetHeight(39)
    return t
  end
  local mid = piece(152, 360)
  mid:SetPoint("TOP", frame, "TOP", 0, 12)
  local l = piece(118, 152) l:SetWidth(17) l:SetPoint("RIGHT", mid, "LEFT")
  local r = piece(360, 394) r:SetWidth(17) r:SetPoint("LEFT", mid, "RIGHT")
  local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("CENTER", mid, "CENTER", 0, 0)
  local set = fs.SetText
  local function fit()
    local tw = fs.GetStringWidth and fs:GetStringWidth() or 100
    mid:SetWidth(math.max((minW or 120) - 34, math.floor(tw + 0.5) + 16))
  end
  fs.SetText = function(self, t) set(self, t) fit() end
  fs:SetText(text or "")
  return fs, mid
end

-- inner panels as in the vanilla character frame: the slot frame with its rivets round dark marble
local function Box(parent, w, h)
  local b = CreateFrame("Frame", nil, parent)
  if w then b:SetSize(w, h) end
  local solid = b:CreateTexture(nil, "BACKGROUND", nil, -8)
  solid:SetColorTexture(0.05, 0.05, 0.05, 1)
  solid:SetPoint("TOPLEFT", 4, -4)
  solid:SetPoint("BOTTOMRIGHT", -4, 4)
  if w and h then
    -- a little darker than the window, as the inside of the vanilla slots and stat box
    MarbleTiles(b, 5, 5, w - 10, h - 10)
  else
    local m = Marble(b)
    m:SetPoint("TOPLEFT", 5, -5)
    m:SetPoint("BOTTOMRIGHT", -5, 5)
  end
  b.rails = SlotBorder(b, nil, nil, w, h)
  function b:SetBorderColor(r, g, bl) for _, t in pairs(self.rails) do t:SetVertexColor(r, g, bl) end end
  return b
end

-- the scroll bar as in vanilla: gold arrows in their square buttons, the round knob, the thin double rail behind
-- (UIPanelScrollFrameTemplate drawn again with the old files, whatever the client puts in it)
local function VanillaScroll(scroll)
  local bar = scroll and (scroll.ScrollBar or (scroll.GetName and scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"]))
  if type(bar) ~= "table" or not bar.GetRegions then return end
  local B = "Interface\\Buttons\\UI-ScrollBar-"
  local thumb = bar.ThumbTexture
  if type(thumb) ~= "table" then thumb = bar.GetThumbTexture and bar:GetThumbTexture() end
  if type(thumb) ~= "table" then thumb = nil end
  -- whatever the client draws on the bar goes, the knob stays
  for _, r in ipairs({ bar:GetRegions() }) do if r ~= thumb and r.Hide then r:Hide() end end
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetTexture("Interface\\PaperDollInfoFrame\\UI-Character-ScrollBar")
  track:SetTexCoord(0, 0.45, 0.1, 0.95)
  track:SetPoint("TOPLEFT", -4, 18)
  track:SetPoint("BOTTOMRIGHT", 4, -18)
  if thumb then
    thumb:SetTexture(B .. "Knob")
    thumb:SetTexCoord(0.2, 0.8, 0.125, 0.875)
    thumb:SetSize(18, 24)
  end
  local name = bar.GetName and bar:GetName()
  for _, kind in ipairs({ "Up", "Down" }) do
    local btn = bar["Scroll" .. kind .. "Button"]
    if type(btn) ~= "table" then btn = name and _G[name .. "Scroll" .. kind .. "Button"] end
    if type(btn) == "table" and btn.SetNormalTexture then
      local f = B .. "Scroll" .. kind .. "Button-"
      btn:SetNormalTexture(f .. "Up")
      btn:SetPushedTexture(f .. "Down")
      if btn.SetDisabledTexture then btn:SetDisabledTexture(f .. "Disabled") end
      btn:SetHighlightTexture(f .. "Highlight", "ADD")
      btn:SetSize(16, 16)
      for _, k in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local t = btn[k] and btn[k](btn)
        if t and t.SetTexCoord then t:SetTexCoord(0.2, 0.8, 0.25, 0.75) t:ClearAllPoints() t:SetAllPoints() end
      end
      -- the client's own pieces on the button go too
      for _, r in ipairs({ btn:GetRegions() }) do
        local keep = false
        for _, k in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
          if btn[k] and btn[k](btn) == r then keep = true end
        end
        if not keep and r.Hide then r:Hide() end
      end
    end
  end
end

-- a narrow line (a column of a list) that doesn't fit: the names in it lose the first name, never the surname
local function FitNames(fs)
  local set = fs.SetText
  fs.SetText = function(self, t)
    set(self, t)
    if type(t) ~= "string" or not t:find(" ", 1, true) or not self.GetStringWidth then return end
    local w = self.GetWidth and self:GetWidth()
    if type(w) ~= "number" or w <= 0 or w > 220 then return end
    local ok, sw = pcall(self.GetStringWidth, self)
    if not ok or type(sw) ~= "number" or sw <= w + 0.5 then return end
    local short = U.Surnames(t)
    if short ~= t then set(self, short) end
  end
end

local function Text(parent, font, text, w, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  if w then fs:SetWidth(w) end
  fs:SetJustifyH(justify or "LEFT")
  if w and w <= 220 then FitNames(fs) end
  if text then fs:SetText(text) end
  return fs
end

-- the red button of the old game, drawn by hand: the client's UIPanelButtonTemplate is the new dark one.
-- Three cuts of UI-Panel-Button-Up/Down/Disabled (80x22 of 128x32), the highlight added on top, as 1.12 did.
local BUTTON = "Interface\\Buttons\\UI-Panel-Button-"
local function RedButton(parent, w, h)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w or 120, h or 22)
  local l = b:CreateTexture(nil, "BACKGROUND")
  l:SetPoint("TOPLEFT") l:SetPoint("BOTTOMLEFT") l:SetWidth(12)
  l:SetTexCoord(0, 0.09375, 0, 0.6875)
  local r = b:CreateTexture(nil, "BACKGROUND")
  r:SetPoint("TOPRIGHT") r:SetPoint("BOTTOMRIGHT") r:SetWidth(12)
  r:SetTexCoord(0.53125, 0.625, 0, 0.6875)
  local m = b:CreateTexture(nil, "BACKGROUND")
  m:SetPoint("TOPLEFT", l, "TOPRIGHT") m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  m:SetTexCoord(0.09375, 0.53125, 0, 0.6875)
  local function Skin(state) for _, t in ipairs({ l, m, r }) do t:SetTexture(BUTTON .. state) end end
  Skin("Up")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(BUTTON .. "Highlight")
  hl:SetTexCoord(0, 0.625, 0, 0.6875)
  hl:SetBlendMode("ADD")
  hl:SetAllPoints()
  local small = (h or 22) < 21
  local fs = b:CreateFontString(nil, "OVERLAY", small and "GameFontNormalSmall" or "GameFontNormal")
  fs:SetPoint("CENTER", 0, 1)
  if b.SetFontString then b:SetFontString(fs) end
  if b.SetNormalFontObject then
    b:SetNormalFontObject(small and "GameFontNormalSmall" or "GameFontNormal")
    b:SetHighlightFontObject(small and "GameFontHighlightSmall" or "GameFontHighlight")
    b:SetDisabledFontObject(small and "GameFontDisableSmall" or "GameFontDisable")
  end
  b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then Skin("Down") end end)
  b:SetScript("OnMouseUp", function(self) if self:IsEnabled() then Skin("Up") end end)
  b:SetScript("OnDisable", function() Skin("Disabled") end)
  b:SetScript("OnEnable", function() Skin("Up") end)
  return b
end

local function Btn(parent, text, w, onClick, h)
  local b = RedButton(parent, w, h)
  b:SetText(text)
  b:SetScript("OnClick", function(self, ...)
    Safe(onClick, self, ...)
    UI.Refresh()
  end)
  return b
end

-- the old dropdown (UIDropDownMenu of 1.12): the label frame of character creation in three cuts, the text on the
-- right, the round arrow; width is the visible box. A click anywhere on it calls onClick(self).
local function Dropdown(parent, width, onClick)
  local f = CreateFrame("Button", nil, parent)
  f:SetSize(width, 24)
  local LF = "Interface\\Glues\\CharacterCreate\\CharacterCreate-LabelFrame"
  local l = f:CreateTexture(nil, "ARTWORK")
  l:SetTexture(LF) l:SetSize(25, 64) l:SetTexCoord(0, 0.1953125, 0, 1)
  l:SetPoint("LEFT", f, "LEFT", -12, 0)
  local r = f:CreateTexture(nil, "ARTWORK")
  r:SetTexture(LF) r:SetSize(25, 64) r:SetTexCoord(0.8046875, 1, 0, 1)
  r:SetPoint("RIGHT", f, "RIGHT", 13, 0)
  local m = f:CreateTexture(nil, "ARTWORK")
  m:SetTexture(LF) m:SetTexCoord(0.1953125, 0.8046875, 0, 1)
  m:SetPoint("TOPLEFT", l, "TOPRIGHT") m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT")
  local label = Text(f, "GameFontHighlightSmall", "", width - 40, "RIGHT")
  label:SetPoint("RIGHT", f, "RIGHT", -28, 1)
  if label.SetWordWrap then label:SetWordWrap(false) end
  local arrow = CreateFrame("Button", nil, f)
  arrow:SetSize(24, 24)
  arrow:SetPoint("RIGHT", f, "RIGHT", -2, 1)
  arrow:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
  arrow:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
  arrow:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled")
  arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  local function Open() Safe(onClick, f) end
  f:SetScript("OnClick", Open)
  arrow:SetScript("OnClick", Open)
  f.label, f.arrow = label, arrow
  function f.SetText(self, t) label:SetText(t) end
  function f.GetText(self) return label:GetText() end
  return f
end

-- the old close button (the X in the corner of a dialog)
local function CloseX(parent, onClick)
  local x = CreateFrame("Button", nil, parent)
  x:SetSize(32, 32)
  x:SetPoint("TOPRIGHT", -2, -2)
  x:SetNormalTexture(MEDIA .. "close-up.tga")
  x:SetPushedTexture(MEDIA .. "close-down.tga")
  x:SetHighlightTexture(MEDIA .. "close-hl.tga", "ADD")
  if x.SetHitRectInsets then x:SetHitRectInsets(5, 5, 5, 5) end
  x:SetScript("OnClick", function() if onClick then onClick() else parent:Hide() end end)
  return x
end

-- first click arms, second click (within 4 s) confirms
local function ConfirmBtn(parent, text, w, onConfirm)
  local b
  b = Btn(parent, text, w, function(self)
    if self.armed and GetTime() - self.armed < 4 then
      self.armed = nil
      self:SetText(text)
      onConfirm(self)
    else
      self.armed = GetTime()
      self:SetText("Sicuro? Riclicca")
      if C_Timer then C_Timer.After(4, function() if self.armed then self.armed = nil self:SetText(text) end end) end
    end
  end)
  return b
end

local function Input(parent, w, maxLetters, onEnter)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, 20)
  e:SetAutoFocus(false)
  if maxLetters then e:SetMaxLetters(maxLetters) end
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if onEnter then Safe(onEnter, self) UI.Refresh() end
  end)
  return e
end

local function Label(parent, text, anchorTo, x, y)
  local fs = Text(parent, "GameFontNormalSmall", text)
  fs:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", x or -4, y or 2)
  return fs
end

local function Check(parent, label, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c.label = Text(parent, "GameFontHighlight", label)
  c.label:SetPoint("LEFT", c, "RIGHT", 2, 1)
  c:SetScript("OnClick", function(self) Safe(set, self:GetChecked() and true or false) UI.Refresh() end)
  c.Sync = function() c:SetChecked(get() and true or false) end
  return c
end

local function Num(text)
  local n = tonumber((tostring(text or ""):gsub(",", ".")))
  return n
end

local function Tip(owner, lines)
  if not GameTooltip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  for i, l in ipairs(lines) do
    if i == 1 then GameTooltip:SetText(l, 1, 0.82, 0) else GameTooltip:AddLine(l, 1, 1, 1, true) end
  end
  GameTooltip:Show()
end
local function HideTip() if GameTooltip then GameTooltip:Hide() end end

local function ClassHex(cls)
  local c = cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
  if c and c.colorStr then return c.colorStr end
  if c and c.r then return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) end
  return "ffffffff"
end

-- the name in its class colour, the nickname after (never instead); no pegno icon in front (too small to read,
-- the user removed it: who is a la gogna is in Progresso, Cimitero)
local function Colored(rec, plain)
  local base = "|c" .. ClassHex(rec.cls) .. tostring(rec.name) .. "|r"
  if plain or not ns.Sfide then return base end
  local n = ns.Sfide.NickOf(rec)
  return base .. (n and (" |cffff8040\"" .. n.t .. "\"|r") or "")
end

local function StateText(lv, cap)
  local s, d = M.PlayerState(lv, cap)
  if s == "over" then return "|cffff4040+" .. d .. " sopra|r" end
  if s == "at" then return "|cff40ff40ar cap|r" end
  if s == "behind" then return "|cffffd100-" .. d .. "|r" end
  return "|cff808080?|r"
end

-- level plus the part of the XP bar already filled (12.4 = level 12, 40% of the bar)
local function Position(rec)
  if not rec or not rec.lv then return 1 end
  local lv = math.min(60, rec.lv)
  local frac = (rec.xp and rec.xpm and rec.xpm > 0 and lv < 60) and math.min(0.999, rec.xp / rec.xpm) or 0
  return lv + frac
end

----------------------------------------------------------------------
-- the cap bar: allowed part (full up to the cap), my position, ticks for the next caps
----------------------------------------------------------------------
-- the level bar: 1 on the left, 60 on the right. Blue fill = where you are (green at the cap, red above it),
-- white line = this week's cap, faint lines = the caps of the next weeks.
local function BarColor(bar, pos, cap)
  local lv = math.floor(pos)
  if lv > cap then bar:SetStatusBarColor(0.85, 0.15, 0.15)
  elseif lv == cap then bar:SetStatusBarColor(0.1, 0.75, 0.1)
  else bar:SetStatusBarColor(0.0, 0.39, 0.88) end
end

local function CapBar(parent, w, h)
  local holder = Box(parent, w, h)
  local inner = CreateFrame("Frame", nil, holder)
  inner:SetPoint("TOPLEFT", 4, -4)
  inner:SetPoint("BOTTOMRIGHT", -4, 4)
  local bar = CreateFrame("StatusBar", nil, inner)
  bar:SetAllPoints()
  bar:SetStatusBarTexture(BAR)
  bar:SetMinMaxValues(0, 59)
  bar:SetValue(0)
  local capLine = bar:CreateTexture(nil, "OVERLAY", nil, 2)
  capLine:SetColorTexture(1, 1, 1, 1)
  capLine:SetWidth(2)
  holder.ticks = {}
  holder.innerWidth = w - 8
  function holder:Set(pos, cap, future)
    local iw = self.innerWidth
    bar:SetValue(math.max(0, math.min(59, pos - 1)))
    BarColor(bar, pos, cap)
    local x = (math.min(60, cap) - 1) / 59 * iw
    capLine:ClearAllPoints()
    capLine:SetPoint("TOPLEFT", inner, "TOPLEFT", x - 1, 2)
    capLine:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", x - 1, -2)
    for _, t in ipairs(self.ticks) do t:Hide() end
    for i, c in ipairs(future or {}) do
      local t = self.ticks[i]
      if not t then
        t = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetColorTexture(1, 1, 1, 0.3)
        t:SetWidth(1)
        self.ticks[i] = t
      end
      local tx = (math.min(60, c) - 1) / 59 * iw
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", inner, "TOPLEFT", tx, 0)
      t:SetPoint("BOTTOMLEFT", inner, "BOTTOMLEFT", tx, 0)
      t:Show()
    end
  end
  return holder
end

----------------------------------------------------------------------
-- members (plus fake ones in test mode, never sent to anyone)
----------------------------------------------------------------------
local FAKE = { "Aldo", "Bruno", "Carla", "Dino", "Elsa", "Franco", "Gina", "Ugo", "Lia", "Mario", "Nina", "Otto" }
local FAKE_CLS = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "HUNTER", "WARLOCK", "DRUID", "PALADIN", "SHAMAN" }

function UI.Members()
  local list = {}
  local state = ns.state
  if not state then return list end
  for _, r in pairs(state.members) do list[#list + 1] = r end
  if ns.db.opts.testMode and ns.IsCapo() and P.HasSettings(state) and #state.settings.teams > 0 then
    local teams = state.settings.teams
    local wk = math.max(1, M.WeekIndex(state.settings, U.Now()))
    -- the fake members wear my own items with different item levels, so the comparisons have something to show
    local myGear = T.ParseEquipment(ns.MyRecord() and ns.MyRecord().eq)
    local function FakeGear(i)
      local out = { "2" }
      for slot, it in pairs(myGear) do
        local il = math.max(1, (it.il or 10) + ((i * 7 + slot) % 9) - 4)
        out[#out + 1] = table.concat({ slot, it.id, it.q or 1, il }, ".")
      end
      return table.concat(out, "/")
    end
    for i, n in ipairs(FAKE) do
      local team = teams[(i - 1) % #teams + 1]
      local st = M.Status(state.settings, team.id, U.Now())
      local cap = st and st.cap or 10
      local lv = math.max(1, math.min(60, cap + ((i * 7) % 5) - 3))
      -- a few busy ones, so the tombola cards of the test have squares done
      local f = (i % 4 == 0) and 4 or ((i % 4 == 1) and 2 or 1)
      list[#list + 1] = {
        guid = "FAKE-" .. i, name = n .. " (prova)", fake = true,
        ti = ns.Titles and ns.Titles.LIST[(i * 5) % #ns.Titles.LIST + 1].id or nil,
        race = ({ "Human", "Dwarf", "NightElf", "Gnome", "Orc", "Scourge", "Tauren", "Troll" })[(i - 1) % 8 + 1], sex = 2 + i % 2, online = i % 2 == 1, team = team.id, lv = lv,
        xp = (i * 1234) % 5000, xpm = 5000, cls = FAKE_CLS[(i - 1) % #FAKE_CLS + 1], zone = "Elwynn Forest",
        up = U.Now() - i * 600, ver = ns.VERSION, alts = {}, h2h = {},
        il = 8 + lv * 0.9 + i % 4, eq = FakeGear(i),
        ms = (function() local t = {} for l = 10, lv, 10 do t[l] = state.settings.start + l * 3600 * (8 + i) end return t end)(),
        pr = { { n = ({ "Blacksmithing", "Alchemy", "Herbalism", "Mining" })[i % 4 + 1], l = 20 + i * 9, m = 150 }, { n = "Cooking", l = i * 7, m = 75 } },
        zq = { ["Elwynn Forest"] = 10 + i, ["Westfall"] = i * 2 }, dgl = { ["The Deadmines"] = i % 3 + 1, ["Wailing Caverns"] = i % 2 },
        lq = { { t = "The Killing Fields", z = "Westfall", at = U.Now() - i * 3000 } },
        wk = wk, zqw = { ["Westfall"] = i % 4 + 1 }, dgw = i % 2 == 0 and { ["The Deadmines"] = 1 } or {},
        stats = { t = { q = i * 9 % 50, dg = i % 6, dw = i % 4, dl = (i * 3) % 4, bw = i % 3, bl = (i + 1) % 3, ding = lv - 1, g = i * 123457 % 900000, dt = i % 5, pt = i * 9000, rk = i % 3, hk = i * 4 % 30, hn = i * 377 % 3000,
            fi = i * 13 % 70, he = i * 7 % 40, mi = i * 5 % 30, sk = i * 3 % 20, lb = i % 5, le = (i % 4 == 0) and 1 or 0, em = i % 3, nk = i % 6, tr = i * 9137 % 90000, fl = i % 7, hs = i % 5 },
          w = { [wk] = { q = (i * 3 % 20 + 5) * f, dg = (i % 3 + 1) * f, dw = (i % 2 + 1) * f, dl = (i + 1) % 2, bw = i % 2, bl = 0, ding = (i % 4) + f, g = (i * 23456 % 200000) * f, dt = i % 2, pt = i * 2400 * f, rk = i % 2 + (f > 2 and 1 or 0), hk = i % 7, hn = i * 61 % 500,
            fi = (i * 3 % 15 + 2) * f, he = (i * 2 % 12) * f, mi = (i % 9) * f, sk = (i % 4) * f, lb = i % 2 + f - 1, le = 0, em = i % 2, nk = i % 3 + f, tr = (i * 2311 % 25000) * f, fl = i % 4, hs = i % 3 } } },
        ne = { n = ({ "Hogger", "Defias Pillager", "Murloc Raider", "Hogger", "Riverpaw Gnoll" })[i % 5 + 1], c = i % 4 + 1 },
        nkl = { { n = "Hogger", c = i % 3 + 1 }, { n = "Bellygrub", c = i % 2 } },
        pts = { t = 20 + i * 7 % 40, w = i % 9, wk = wk, r = i % 4, n = i % 4 + 3, ps = 10 + i * 3, pw = (i * 7) % 30 },
        rip = { { at = U.Now() - i * 5400, lv = lv, k = ({ "mostro", "cascato", "mostro", "affogato", "pischello" })[i % 5 + 1],
          by = ({ "Hogger", "Defias Pillager", "Murloc Raider", "Kobold Vermin", "Young Wolf" })[i % 5 + 1], z = ({ "Elwynn Forest", "Westfall", "Redridge Mountains" })[i % 3 + 1],
          w = ({ "tranquilli, ce penso io", "nun è niente", nil, "daje che è facile", "aspetta che bevo" })[i % 5 + 1] } },
        vt = { wk = wk, a = "FAKE-" .. ((i * 3) % 4 + 1), b = "FAKE-" .. ((i * 5) % 5 + 1), c = "FAKE-" .. ((i * 7) % 3 + 1), sa = (i % 3) * 5 + 1, sb = 5, sc = i % 2 == 0 and 10 or 1 },
      }
    end
  end
  return list
end

local function Online(rec)
  if rec.fake then return rec.online end
  if rec.guid == ns.recordGuid then return true end
  return C.IsOnline(rec.guid)
end

local function StatOf(rec, key, mode)
  local s = rec.stats
  if not s then return 0 end
  if mode == "t" then return (s.t and s.t[key]) or 0 end
  local wk = ns.state and P.HasSettings(ns.state) and M.WeekIndex(ns.state.settings, U.Now()) or 0
  local w = s.w and s.w[wk]
  return (w and w[key]) or 0
end

----------------------------------------------------------------------
-- window and tabs
----------------------------------------------------------------------
local function SelectTab(key)
  if UI.CloseMenus then UI.CloseMenus() end
  current = key
  UI.Refresh()
end

-- bottom tabs as in the vanilla character frame: the unselected ones are black with a thin edge and tuck under
-- the window border; the selected one is part of the window, the border opens and runs round it (LayoutChrome).
-- Their art is drawn by the window itself, under its border; the buttons only take the click and the label.
local function MakeTab(i, key, label)
  local b = CreateFrame("Button", "ErPattoFrameTab" .. i, f)
  b:SetFrameLevel(f:GetFrameLevel() + 20)
  b.key = key
  b.text = Text(b, "GameFontNormalSmall", label, nil, "CENTER")
  local tw = math.floor((b.text.GetStringWidth and b.text:GetStringWidth() or 60) + 0.5)
  b:SetSize(math.max(64, tw + 30), TAB_H)
  -- no glow on the mouse: the label turns white, nothing else
  b.hl = { SetShown = function() end }
  b:SetScript("OnEnter", function(self) if not self.selected then self.text:SetFontObject("GameFontHighlightSmall") end end)
  b:SetScript("OnLeave", function(self) if not self.selected then self.text:SetFontObject("GameFontNormalSmall") end end)
  -- the unselected look, owned by the window so its border covers the top
  b.off = { fill = f:CreateTexture(nil, "BACKGROUND", nil, -6) }
  b.off.fill:SetColorTexture(0, 0, 0, 1)
  for _, k in ipairs({ P_L, P_R, P_BL, P_BR, P_B }) do b.off[k] = RailTex(f, nil, k, "BACKGROUND", -5) end
  b:SetScript("OnClick", function()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    SelectTab(key)
  end)
  function b:SetSelected(on)
    self.selected = on
    self.text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall")
    self.text:ClearAllPoints()
    self.text:SetPoint("CENTER", 0, on and 1 or 3)
    self.hl:SetShown(not on)
  end
  function b:Art(x, show)
    local w, s = self:GetWidth(), RS
    local top, bottom = H - 4, H + TAB_H - 6 -- under the window border, 6 px shorter than the selected one
    local o = self.off
    if not show then for _, t in pairs(o) do t:Hide() end return end
    Put(o.fill, f, x + 2, top, w - 4, bottom - top - 2)
    Put(o[P_L], f, x, top, s, bottom - top - s)
    Put(o[P_R], f, x + w - s, top, s, bottom - top - s)
    Put(o[P_BL], f, x, bottom - s, s, s)
    Put(o[P_BR], f, x + w - s, bottom - s, s, s)
    Put(o[P_B], f, x + s, bottom - s, w - 2 * s, s)
  end
  b:SetSelected(false)
  tabs[#tabs + 1] = b
  return b
end

-- the selected tab stands over the window's bottom border (a, b: its left and right edge), its inside the same
-- marble as the window, so the window opens into it, as in the vanilla frame
local function LayoutChrome(a, b)
  local t, s = f.selTab, RS
  for _, list in pairs(f.selFills) do for _, x in ipairs(list) do x:Hide() end end
  if a and b then
    -- the marble covers the window's bottom border across the tab (it is 6 px, H-6..H), so the window opens into
    -- it; the tab's sides start on the border's last line, so nothing sticks out above it
    local top, bottom = H - 7, H + TAB_H
    local side = H - 2
    local key = a .. ":" .. b
    if not f.selFills[key] then f.selFills[key] = MarblePlane(f, 10, 67, a + 3, top, b - a - 6, bottom - top - 3, "ARTWORK", 0) end
    for _, x in ipairs(f.selFills[key]) do x:Show() end
    Put(t[P_L], f, a, side, s, bottom - side - s)
    Put(t[P_R], f, b - s, side, s, bottom - side - s)
    Put(t[P_BL], f, a, bottom - s, s, s)
    Put(t[P_BR], f, b - s, bottom - s, s, s)
    Put(t[P_B], f, a + s, bottom - s, b - a - 2 * s, s)
  else
    for _, x in pairs(t) do x:Hide() end
  end
end

-- left to right from 20 px in, 2 px apart; the window border opens under the selected one
local function LayoutTabs()
  local x, a, b = 20, nil, nil
  for _, t in ipairs(tabs) do
    t:ClearAllPoints()
    if t:IsShown() then
      t:SetPoint("TOPLEFT", f, "TOPLEFT", x, -H)
      t:Art(x, not t.selected)
      if t.selected then a, b = x, x + t:GetWidth() end
      x = x + t:GetWidth() + 2
    else
      t:Art(x, false)
    end
  end
  LayoutChrome(a, b)
end

local function NewView(key)
  local v = CreateFrame("Frame", nil, content)
  v:SetAllPoints()
  v:Hide()
  views[key] = v
  return v
end

----------------------------------------------------------------------
-- welcome: create or join
----------------------------------------------------------------------
-- page tabs on top of a panel, the bottom tabs turned upside down: black with a yellow label, the selected one
-- in stone with a white label; open at the bottom, standing on the panel under them
local function TopTab(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetFrameLevel(parent:GetFrameLevel() + 10)
  b.text = Text(b, "GameFontNormalSmall", label, nil, "CENTER")
  b.text:SetPoint("CENTER", 0, -2)
  local tw = math.floor((b.text.GetStringWidth and b.text:GetStringWidth() or 60) + 0.5)
  b:SetSize(math.max(64, tw + 30), 26)
  local fill = b:CreateTexture(nil, "BACKGROUND", nil, -8)
  fill:SetColorTexture(0, 0, 0, 1)
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 0)
  local marble = Marble(b, "BACKGROUND", -7, b:GetWidth() - 4, 24)
  marble:SetPoint("TOPLEFT", 2, -2)
  marble:SetPoint("BOTTOMRIGHT", -2, 0)
  b.stone = { tex = marble }
  Border(b, nil, "BORDER", 0, "bottom")
  -- no glow on the mouse: the label turns white, nothing else
  b.hl = { SetShown = function() end }
  b:SetScript("OnEnter", function(self) if not self.selected then self.text:SetFontObject("GameFontHighlightSmall") end end)
  b:SetScript("OnLeave", function(self) if not self.selected then self.text:SetFontObject("GameFontNormalSmall") end end)
  b:SetScript("OnClick", function(self)
    if self.selected then return end
    Safe(onClick, self)
    UI.Refresh()
  end)
  function b:SetSelected(on)
    self.selected = on
    self.text:SetFontObject(on and "GameFontHighlightSmall" or "GameFontNormalSmall")
    self.stone.tex:SetShown(on)
    self.hl:SetShown(not on)
  end
  b:SetSelected(false)
  return b
end

-- vanilla radio button (UI-RadioButton) with its label; the whole line is clickable
local function Radio(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  local function part(layer, a, z)
    local t = b:CreateTexture(nil, layer)
    t:SetTexture("Interface\\Buttons\\UI-RadioButton")
    t:SetTexCoord(a, z, 0, 1)
    t:SetSize(16, 16)
    t:SetPoint("LEFT")
    return t
  end
  part("ARTWORK", 0, 0.25)
  b.dot = part("OVERLAY", 0.25, 0.5)
  local hl = part("HIGHLIGHT", 0.5, 0.75)
  hl:SetBlendMode("ADD")
  b.text = Text(b, "GameFontHighlightSmall", label)
  b.text:SetPoint("LEFT", 18, 0)
  local tw = math.floor((b.text.GetStringWidth and b.text:GetStringWidth() or 60) + 0.5)
  b:SetSize(18 + tw + 2, 16)
  b:SetScript("OnClick", function(self)
    if self.selected then return end
    Safe(onClick, self)
    UI.Refresh()
  end)
  function b:SetSelected(on)
    self.selected = on
    self.dot:SetShown(on)
  end
  b:SetSelected(false)
  return b
end

----------------------------------------------------------------------
-- calendar for the start date (Italian time): pick a day, then the time
----------------------------------------------------------------------
local MONTHS = { "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre" }
local FOREVER_LAUNCH = 1793833200 -- gio 5 nov 2026 a le 00:00 ora italiana (4 nov, 15:00 in California)
local picker

local function DaysIn(y, m)
  local ny, nm = y, m + 1
  if nm > 12 then ny, nm = y + 1, 1 end
  return math.floor((U.UTCEpoch(ny, nm, 1) - U.UTCEpoch(y, m, 1)) / 86400)
end

local function BuildPicker()
  picker = CreateFrame("Frame", "ErPattoDatePicker", UIParent)
  picker:SetSize(270, 340)
  picker:SetFrameStrata("DIALOG")
  picker:SetToplevel(true)
  picker:SetClampedToScreen(true)
  picker:EnableMouse(true)
  Chrome(picker)
  if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoDatePicker") end
  picker:Hide()
  local title = Text(picker, "GameFontNormal", "Quanno se parte?", 240, "CENTER")
  title:SetPoint("TOP", 0, -18)
  local function arrow(dir, onClick)
    local b = CreateFrame("Button", nil, picker)
    b:SetSize(26, 26)
    local base = dir < 0 and "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-" or "Interface\\Buttons\\UI-SpellbookIcon-NextPage-"
    b:SetNormalTexture(base .. "Up")
    b:SetPushedTexture(base .. "Down")
    b:SetDisabledTexture(base .. "Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function() onClick() picker:Update() end)
    return b
  end
  picker.month = Text(picker, "GameFontHighlight", "", 160, "CENTER")
  picker.month:SetPoint("TOP", 0, -42)
  local pm = arrow(-1, function() picker.m = picker.m - 1 if picker.m < 1 then picker.m, picker.y = 12, picker.y - 1 end end)
  pm:SetPoint("RIGHT", picker.month, "LEFT", 0, 0)
  local nm = arrow(1, function() picker.m = picker.m + 1 if picker.m > 12 then picker.m, picker.y = 1, picker.y + 1 end end)
  nm:SetPoint("LEFT", picker.month, "RIGHT", 0, 0)
  local dows = { "lu", "ma", "me", "gi", "ve", "sa", "do" }
  for i, d in ipairs(dows) do
    local t = Text(picker, "GameFontNormalSmall", d, 30, "CENTER")
    t:SetPoint("TOPLEFT", 24 + (i - 1) * 32, -66)
  end
  picker.days = {}
  for i = 1, 42 do
    local b = CreateFrame("Button", nil, picker)
    b:SetSize(30, 20)
    b:SetPoint("TOPLEFT", 24 + ((i - 1) % 7) * 32, -82 - math.floor((i - 1) / 7) * 22)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    b.sel:SetBlendMode("ADD")
    b.sel:SetVertexColor(1, 0.82, 0, 0.8)
    b.sel:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\UI-Listbox-Highlight2", "ADD")
    b.text = Text(b, "GameFontHighlightSmall", "", 30, "CENTER")
    b.text:SetPoint("CENTER")
    b:SetScript("OnClick", function(self)
      picker.d, picker.sm, picker.sy = self.day, picker.m, picker.y
      picker:Update()
    end)
    picker.days[i] = b
  end
  -- time on its own row, centred like the month: < 00:00 >
  local hl = Text(picker, "GameFontNormal", "Ora")
  hl:SetPoint("TOPLEFT", 28, -228)
  picker.time = Text(picker, "GameFontHighlight", "", 70, "CENTER")
  picker.time:SetPoint("TOP", 0, -228)
  local tp = arrow(-1, function() picker.min = (picker.min - 30) % 1440 end)
  tp:SetPoint("RIGHT", picker.time, "LEFT", 0, 0)
  local tn = arrow(1, function() picker.min = (picker.min + 30) % 1440 end)
  tn:SetPoint("LEFT", picker.time, "RIGHT", 0, 0)
  local launch = Btn(picker, "Lancio de Forever", 160, function()
    picker:Set(FOREVER_LAUNCH)
  end)
  launch:SetPoint("TOP", 0, -256)
  picker.summary = Text(picker, "GameFontNormalSmall", "", 230, "CENTER")
  picker.summary:SetPoint("TOP", 0, -286)
  local ok = Btn(picker, "Va bene", 100, function()
    local p = picker.min
    local t = U.FromRome(picker.sy, picker.sm, picker.d, math.floor(p / 60), p % 60)
    picker:Hide()
    if picker.onPick then picker.onPick(t) end
  end)
  ok:SetPoint("BOTTOMLEFT", 24, 18)
  local cancel = Btn(picker, "Lassa perde", 100, function() picker:Hide() end)
  cancel:SetPoint("BOTTOMRIGHT", -24, 18)
  function picker:Set(t)
    local p = U.RomeParts(t)
    self.y, self.m, self.d, self.sy, self.sm = p.year, p.month, p.day, p.year, p.month
    self.min = p.hour * 60 + math.floor(p.min / 30) * 30
    self:Update()
  end
  function picker:Update()
    self.month:SetText(MONTHS[self.m] .. " " .. self.y)
    local first = U.UTCParts(U.UTCEpoch(self.y, self.m, 1)).wday -- 0 = Sunday
    local offset = (first + 6) % 7                                 -- Monday first
    local n = DaysIn(self.y, self.m)
    for i, b in ipairs(self.days) do
      local day = i - offset
      if day >= 1 and day <= n then
        b.day = day
        b.text:SetText(tostring(day))
        b.sel:SetShown(day == self.d and self.m == self.sm and self.y == self.sy)
        b:Show()
      else
        b:Hide()
      end
    end
    self.time:SetText(string.format("%02d:%02d", math.floor(self.min / 60), self.min % 60))
    local t = U.FromRome(self.sy, self.sm, self.d, math.floor(self.min / 60), self.min % 60)
    self.summary:SetText("Partenza: " .. U.When(t) .. ", ora italiana")
  end
end

-- opens the calendar on `initial`; `onPick(epoch)` runs when the player confirms
function UI.PickDate(initial, onPick)
  if not picker then BuildPicker() end
  picker.onPick = onPick
  picker:Set(initial or FOREVER_LAUNCH)
  picker:ClearAllPoints()
  if f and f:IsShown() then picker:SetPoint("CENTER", f, "CENTER") else picker:SetPoint("CENTER") end
  picker:Show()
end

----------------------------------------------------------------------
-- first screen: join with a code, or go to the create form
----------------------------------------------------------------------
local wantCreate = false

local function BuildWelcome()
  local v = NewView("welcome")
  local left = Box(v, 362, 452)
  left:SetPoint("TOPLEFT", 0, 0)
  local jt = Text(left, "GameFontNormal", "Entra co' 'n codice")
  jt:SetPoint("TOPLEFT", 16, -16)
  local js = Text(left, "GameFontHighlight",
    "Chi è der patto t'ha dato 'n codice de 5 lettere e nummeri. Scrivilo qui sotto: entri subito e poi te scegli la squadra.", 330)
  js:SetPoint("TOPLEFT", 16, -44)
  local jerr = Text(left, "GameFontRedSmall", "", 330)
  local code
  local function DoJoin()
    jerr:SetText("")
    local st, e = ns.JoinPatto(code:GetText())
    if not st then jerr:SetText(e or "Nun so' riuscito a entrà.") return end
    current = "gruppi"
  end
  code = Input(left, 140, 40, DoJoin)
  code:SetPoint("TOPLEFT", 24, -122)
  Label(left, "Codice", code)
  local join = Btn(left, "Entra", 100, DoJoin)
  join:SetPoint("LEFT", code, "RIGHT", 10, 0)
  jerr:SetPoint("TOPLEFT", 16, -152)
  local note = Text(left, "GameFontDisableSmall",
    "L'addon parla co' l'altri dentro ar gioco, senza internet. Pe' ricevve i dati serve che armeno uno der patto sia online.", 330)
  note:SetPoint("BOTTOMLEFT", 16, 16)
  v.code, v.join, v.jerr = code, join, jerr

  local right = Box(v, 374, 452)
  right:SetPoint("TOPRIGHT", 0, 0)
  local ct = Text(right, "GameFontNormal", "Crea 'n patto novo")
  ct:SetPoint("TOPLEFT", 16, -16)
  local cs = Text(right, "GameFontHighlight",
    "Diventi er capo der patto. Decidi quanno se parte e quante ore a settimana gioca ogni squadra. L'addon calcola er cap de ogni settimana.", 340)
  cs:SetPoint("TOPLEFT", 16, -44)
  local go = Btn(right, "Crea 'n patto", 140, function() wantCreate = true end)
  go:SetPoint("TOPLEFT", 16, -122)
  v.go = go
end

-- another character of the account is in a patto: nothing of it here until this one joins as one of its own.
-- Linked as an alt only if the player asks (the friends see it under the main), and unlinked the same way
local function BuildAlt()
  local v = NewView("alt")
  local b = Box(v, 744, 452)
  b:SetPoint("TOPLEFT", 0, 0)
  local t = Text(b, "GameFontNormal", "Stai co' 'n alt")
  t:SetPoint("TOPLEFT", 16, -16)
  v.text = Text(b, "GameFontHighlight", "", 700)
  v.text:SetPoint("TOPLEFT", 16, -44)
  v.join = Btn(b, "Entra co' 'sto personaggio", 210, function()
    local st = ns.state or ns.AccountPatto()
    if not st then return end
    local ok, e = ns.JoinPatto(st.code)
    if ok == nil or ok == false then v.err:SetText(e or "Nun so' riuscito a entrà.") end
  end)
  v.join:SetPoint("TOPLEFT", v.text, "BOTTOMLEFT", 0, -16)
  v.link = Btn(b, "", 210, function()
    if ns.alt then ns.UnlinkAlt() else ns.LinkAlt() end
  end)
  v.link:SetPoint("LEFT", v.join, "RIGHT", 10, 0)
  v.link:SetScript("OnEnter", function(self) if self.tip then Tip(self, self.tip) end end)
  v.link:SetScript("OnLeave", HideTip)
  v.err = Text(b, "GameFontRedSmall", "", 500)
  v.err:SetPoint("TOPLEFT", v.join, "BOTTOMLEFT", 0, -10)
end

local function BuildCreate()
  local v = NewView("create")
  local box = Box(v, 744, 452)
  box:SetPoint("TOPLEFT", 0, 0)
  local t = Text(box, "GameFontNormal", "Crea 'n patto novo")
  t:SetPoint("TOPLEFT", 16, -14)

  local name = Input(box, 260, 40)
  name:SetPoint("TOPLEFT", 24, -64)
  name:SetText("Er Patto der Cap")
  Label(box, "Nome der patto", name)

  v.startAt = FOREVER_LAUNCH
  local sl = Text(box, "GameFontNormalSmall", "Partenza (ora italiana)")
  sl:SetPoint("TOPLEFT", 330, -48)
  local startBtn
  startBtn = Btn(box, "", 220, function()
    UI.PickDate(v.startAt, function(epoch) v.startAt = epoch UI.Refresh() end)
  end)
  startBtn:SetPoint("TOPLEFT", 326, -62)
  v.startBtn = startBtn

  local tl = Text(box, "GameFontNormal", "Squadre")
  tl:SetPoint("TOPLEFT", 16, -104)
  local th = Text(box, "GameFontHighlightSmall",
    "Pe' ogni squadra scrivi quante ore a settimana pensate de giocà. Chi gioca de più fa 'na squadra, chi gioca de meno 'n'artra. Er cap de ogni squadra viene da queste ore.", 700)
  th:SetPoint("TOPLEFT", 16, -122)
  local h1 = Text(box, "GameFontNormalSmall", "Nome de la squadra")
  h1:SetPoint("TOPLEFT", 24, -156)
  local h2 = Text(box, "GameFontNormalSmall", "Ore a settimana")
  h2:SetPoint("TOPLEFT", 266, -156)
  local defaults = { { "I Cesaroni", "12" }, { "Carabinieri 8", "30" }, { "", "" }, { "", "" } }
  local rows = {}
  for i = 1, 4 do
    local n = Input(box, 220, 24)
    n:SetPoint("TOPLEFT", 24, -172 - (i - 1) * 26)
    n:SetText(defaults[i][1])
    local hrs = Input(box, 50, 3)
    hrs:SetPoint("LEFT", n, "RIGHT", 24, 0)
    hrs:SetText(defaults[i][2])
    rows[i] = { n, hrs }
  end
  local opt = Text(box, "GameFontDisableSmall", "Le squadre 3 e 4 so' facortative: lassale vòte si nun te servono.", 400)
  opt:SetPoint("TOPLEFT", 24, -278)

  local err = Text(box, "GameFontRedSmall", "", 460)
  err:SetPoint("BOTTOMLEFT", 16, 46)
  local create = Btn(box, "Crea er patto", 150, function()
    err:SetText("")
    local teams = {}
    for _, r in ipairs(rows) do
      local nm = strtrim and strtrim(r[1]:GetText() or "") or (r[1]:GetText() or "")
      if nm ~= "" then teams[#teams + 1] = { name = nm:sub(1, 24), hours = Num(r[2]:GetText()) } end
    end
    if #teams < 2 then err:SetText("Servono armeno 2 squadre.") return end
    for _, tm in ipairs(teams) do
      if not tm.hours or tm.hours < 1 or tm.hours > 100 then err:SetText("Ore de " .. tm.name .. ": scrivi 'n nummero da 1 a 100.") return end
    end
    local nm = name:GetText() or ""
    if nm == "" then nm = "Er Patto" end
    local st, e = ns.CreatePatto({ name = nm:sub(1, 40), start = v.startAt, teams = teams })
    if not st then err:SetText(e or "Nun so' riuscito a crearlo.") return end
    wantCreate = false
    current = "gruppi"
  end)
  create:SetPoint("BOTTOMLEFT", 16, 16)
  local back = Btn(box, "Indietro", 110, function() wantCreate = false end)
  back:SetPoint("LEFT", create, "RIGHT", 10, 0)
  v.create, v.err, v.name, v.rows, v.back = create, err, name, rows, back
end

local function BuildWaiting()
  local v = NewView("waiting")
  local b = Box(v, 520, 190)
  b:SetPoint("TOP", 0, -60)
  local t = Text(b, "GameFontNormal", "Aspetto li dati der patto...", 490, "CENTER")
  t:SetPoint("TOP", 0, -18)
  v.info = Text(b, "GameFontHighlight", "", 490, "CENTER")
  v.info:SetPoint("TOP", t, "BOTTOM", 0, -12)
  -- "Riprova mo'": the search again (Battle.net friends, friends list, group, guild, the channel)
  v.msg = Text(b, "GameFontGreenSmall", "", 490, "CENTER")
  v.msg:SetPoint("BOTTOM", 0, 44)
  local again = Btn(b, "Riprova mo'", 140, function()
    local n = C.Search()
    C.Hello()
    v.msg:SetText(n > 0 and ("Ho chiesto er patto a " .. n .. (n == 1 and " amico o gruppo." or " amichi e gruppi.")) or
      "|cffff2020Nun c'è nessun amico tuo online da chiede: fatte invità da uno der patto (tasto destro sur ritratto tuo).|r")
  end)
  again:SetPoint("BOTTOM", 0, 14)
end

----------------------------------------------------------------------
-- Cap tab
----------------------------------------------------------------------
local function BuildCap()
  local v = NewView("cap")
  local top = Box(v, 744, 150)
  top:SetPoint("TOPLEFT", 0, 0)
  v.title = Text(top, "GameFontNormal", "", 520)
  v.title:SetPoint("TOPLEFT", 14, -12)
  v.capNum = Text(top, "GameFontNormalLarge", "", 200, "RIGHT")
  v.capNum:SetPoint("TOPRIGHT", -14, -10)
  v.status = Text(top, "GameFontHighlight", "", 520)
  v.status:SetPoint("TOPLEFT", 14, -36)
  v.bar = CapBar(top, 716, 24)
  v.bar:SetPoint("TOPLEFT", 14, -60)
  local l1 = Text(top, "GameFontDisableSmall", "1")
  l1:SetPoint("TOPLEFT", v.bar, "BOTTOMLEFT", 2, -2)
  local legend = Text(top, "GameFontDisableSmall", "", 560, "CENTER")
  legend:SetPoint("TOP", v.bar, "BOTTOM", 0, -2)
  local l60 = Text(top, "GameFontDisableSmall", "60")
  l60:SetPoint("TOPRIGHT", v.bar, "BOTTOMRIGHT", -2, -2)
  v.next = Text(top, "GameFontHighlight", "", 716)
  v.next:SetPoint("TOPLEFT", 14, -100)
  v.hours = Text(top, "GameFontHighlightSmall", "", 716)
  v.hours:SetPoint("TOPLEFT", 14, -120)

  local tb = Box(v, 744, 294)
  tb:SetPoint("TOPLEFT", 0, -158)
  v.tableTitle = Text(tb, "GameFontNormal", "Er calendario de li cap")
  v.tableTitle:SetPoint("TOPLEFT", 14, -10)
  local scroll = CreateFrame("ScrollFrame", "ErPattoCapScroll", tb, "UIPanelScrollFrameTemplate")
  VanillaScroll(scroll)
  scroll:SetPoint("TOPLEFT", 10, -50)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)
  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(330, 10)
  scroll:SetScrollChild(body)
  v.header = {}
  v.headerFrame = tb
  v.body, v.rows = body, {}
end

local function CapHeaders(v, settings, myTeam)
  local cols = { { "Sett.", 46 }, { "Da", 120 } }
  local n = #settings.teams
  local tw = math.floor((700 - 166) / math.max(1, n))
  for _, t in ipairs(settings.teams) do cols[#cols + 1] = { t.name, tw, t.id } end
  for _, h in ipairs(v.header) do h:Hide() end
  local x = 14
  for i, c in ipairs(cols) do
    local h = v.header[i] or Text(v.headerFrame, "GameFontNormalSmall", "")
    v.header[i] = h
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", x, -32)
    h:SetWidth(c[2] - 4)
    h:SetText(c[3] and c[3] == myTeam and ("|cffffffff" .. c[1] .. " (tu)|r") or c[1])
    h:Show()
    x = x + c[2]
  end
  return cols
end

local function RefreshCap(v)
  local state = ns.state
  local s = state.settings
  local rec = ns.MyRecord()
  local now = U.Now()
  local st = ns.MyStatus()
  if not st then
    v.title:SetText(rec and rec.team and "Squadra nun trovata" or "Nun hai scelto la squadra")
    v.capNum:SetText("")
    v.status:SetText(ns.alt and "Stai co' 'n alt: la squadra la sceglie er personaggio principale." or "Vai su Squadre e scegli co' chi livellà.")
    v.bar:Set(Position(rec), 1, {})
    v.next:SetText("")
    v.hours:SetText("")
  else
    local pos = Position(rec)
    local future = {}
    for k = math.max(1, st.week) + 1, #st.rows do
      if st.rows[k].cap > st.cap and #future < 12 then future[#future + 1] = st.rows[k].cap end
    end
    v.bar:Set(pos, st.cap, future)
    if not st.started then
      v.title:SetText(st.team.name .. ", se parte " .. U.When(s.start))
      v.capNum:SetText("Cap " .. st.cap)
      v.status:SetText("Manca " .. U.Until(s.start - now) .. ". Primo cap: livello " .. st.cap .. ".")
      v.next:SetText("Settimana 2: cap " .. (st.rows[2] and st.rows[2].cap or 60) .. ".")
    elseif st.lifted then
      v.title:SetText(st.team.name .. ", settimana " .. st.week)
      v.capNum:SetText("|cff40ff40Libbero|r")
      v.status:SetText("Er calendario è finito: niente più cap, se va ar 60.")
      v.next:SetText("")
    else
      v.title:SetText(st.team.name .. ", settimana " .. st.week)
      v.capNum:SetText("Cap " .. st.cap)
      local ps, d = M.PlayerState(rec and rec.lv, st.cap)
      local txt
      if ps == "over" then txt = "|cffff4040Sei sopra er cap de " .. d .. (d == 1 and " livello" or " livelli") .. ".|r Fermate co' l'XP fino a la settimana dopo."
      elseif ps == "at" then txt = "|cff40ff40Sei ar cap.|r La barra se pò riempì, ma nun fà ding."
      elseif ps == "behind" then txt = "Livello " .. rec.lv .. ": te " .. (d == 1 and "manca 1 livello" or ("mancano " .. d .. " livelli")) .. " pe' arrivà ar cap."
      else txt = "Livello nun ancora noto." end
      v.status:SetText(txt)
      if st.nextCap > st.cap then
        v.next:SetText("Prossimo cap: |cffffffff" .. st.nextCap .. "|r, se sblocca " .. U.When(st.unlockAt) .. " (tra " .. U.Until(st.unlockAt - now) .. ")")
      else
        v.next:SetText("Er cap resta " .. st.cap .. " pure la settimana dopo.")
      end
    end
    -- played hours still needed to reach the cap, from the calibration curve
    local calib = M.CalibFor(s, math.max(1, st.week))
    local cum = M.Curve(calib.h20, calib.h60)
    if rec and rec.lv and not st.lifted then
      local lv = math.min(60, rec.lv)
      local left = M.HoursToCap(s, st.week, lv, rec.xp, rec.xpm, st.cap)
      if left > 0.05 then
        v.hours:SetText("Pe' arrivà ar cap te servono più o meno " .. U.Hours(left) .. " de gioco.")
      else
        v.hours:SetText("")
      end
    else
      v.hours:SetText("")
    end
  end
  -- calendar
  local sched = M.Schedule(s)
  local cols = CapHeaders(v, s, rec and rec.team)
  local wk = M.WeekIndex(s, now)
  for _, r in ipairs(v.rows) do r:Hide() end
  for k = 1, sched.n do
    local row = v.rows[k]
    if not row then
      row = CreateFrame("Frame", nil, v.body)
      row:SetSize(700, 18)
      row.hl = row:CreateTexture(nil, "BACKGROUND")
      row.hl:SetAllPoints()
      row.hl:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar-Blue")
      row.hl:SetBlendMode("ADD")
      row.cells = {}
      v.rows[k] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -(k - 1) * 18)
    row.hl:SetShown(k == wk)
    for _, c in ipairs(row.cells) do c:Hide() end
    local x = 4
    for i, c in ipairs(cols) do
      local cell = row.cells[i] or Text(row, "GameFontHighlightSmall", "")
      row.cells[i] = cell
      cell:ClearAllPoints()
      cell:SetPoint("LEFT", x, 0)
      cell:SetWidth(c[2] - 4)
      local txt
      if i == 1 then txt = tostring(k)
      elseif i == 2 then txt = U.Day(sched.starts[k])
      else
        local tr = sched.teams[c[3]][k]
        if tr then
          txt = tr.cap .. (tr.gain > 0 and ("  |cff9d9d9d+" .. tr.gain .. "|r") or "")
          if c[3] == (rec and rec.team) then txt = "|cffffffff" .. txt .. "|r" end
          if tr.done then txt = "|cff9d9d9d60|r" end
        else
          txt = "60"
        end
      end
      cell:SetText(txt)
      cell:Show()
      x = x + c[2]
    end
    row:Show()
  end
  v.body:SetHeight(math.max(10, sched.n * 18))
  UI.FitScroll(_G.ErPattoCapScroll, sched.n * 18, 217 - 58)
end

----------------------------------------------------------------------
-- Squadre tab
----------------------------------------------------------------------
local function BuildGruppi()
  local v = NewView("gruppi")
  v.cols = {}
  v.switchBox = Box(v, 744, 58)
  v.switchBox:SetPoint("BOTTOMLEFT", 0, 0)
  local st = Text(v.switchBox, "GameFontNormal", "Ultimi cambi de squadra")
  st:SetPoint("TOPLEFT", 12, -8)
  v.switchText = Text(v.switchBox, "GameFontHighlightSmall", "", 720)
  v.switchText:SetPoint("TOPLEFT", 12, -25)
  v.switchText:SetJustifyV("TOP")
end

local function MemberRow(parent, w)
  local r = CreateFrame("Button", nil, parent)
  r:SetSize(w, 24)
  r.dot = r:CreateTexture(nil, "ARTWORK")
  r.dot:SetSize(8, 8)
  r.dot:SetPoint("TOPLEFT", 2, -4)
  r.dot:SetTexture(BAR)
  r.name = Text(r, "GameFontHighlightSmall", "", w - 90)
  r.name:SetPoint("TOPLEFT", 14, -2)
  r.lv = Text(r, "GameFontHighlightSmall", "", 30, "RIGHT")
  r.lv:SetPoint("TOPRIGHT", -54, -2)
  r.state = Text(r, "GameFontHighlightSmall", "", 52, "RIGHT")
  r.state:SetPoint("TOPRIGHT", 0, -2)
  r.bar = CreateFrame("StatusBar", nil, r)
  r.bar:SetStatusBarTexture(BAR)
  r.bar:SetMinMaxValues(0, 59)
  r.bar:SetPoint("TOPLEFT", 14, -15)
  r.bar:SetSize(w - 16, 6)
  r.barBg = r.bar:CreateTexture(nil, "BACKGROUND")
  r.barBg:SetAllPoints()
  r.barBg:SetColorTexture(0, 0, 0, 0.6)
  r.capLine = r.bar:CreateTexture(nil, "OVERLAY")
  r.capLine:SetColorTexture(1, 1, 1, 1)
  r.capLine:SetSize(2, 10)
  r.barW = w - 16
  r:SetScript("OnEnter", function(self)
    local rec = self.rec
    if not rec then return end
    local title = ns.Titles and ns.Titles.Of(rec)
    local lines = { tostring(rec.name) .. (title and ("  |cffffd100" .. title .. "|r") or "") }
    lines[#lines + 1] = "Livello " .. tostring(rec.lv or "?") .. ((rec.xp and rec.xpm and rec.xpm > 0) and (" (" .. math.floor(rec.xp / rec.xpm * 100) .. "% de la barra)") or "")
    if rec.zone then lines[#lines + 1] = "Zona: " .. rec.zone end
    lines[#lines + 1] = Online(rec) and "|cff40ff40Online mo'|r" or "|cff9d9d9dNun online (o nun se sente da 'n po')|r"
    lines[#lines + 1] = "Dati aggiornati: " .. U.Ago(U.Now() - (rec.up or 0))
    if rec.ld then lines[#lines + 1] = "Urtimo dungeon: " .. rec.ld end
    if rec.alts and #rec.alts > 0 then
      local a = {}
      for _, x in ipairs(rec.alts) do a[#a + 1] = x.name .. " " .. x.lv end
      lines[#lines + 1] = "Alt: " .. table.concat(a, ", ")
    end
    if rec.ver then lines[#lines + 1] = "|cff9d9d9dAddon " .. rec.ver .. "|r" end
    Tip(self, lines)
  end)
  r:SetScript("OnLeave", HideTip)
  r:SetScript("OnClick", function(self) if self.rec and UI.ShowCharacter then UI.ShowCharacter(self.rec.guid) end end)
  return r
end

local function GruppiColumn(v, i, w)
  local col = v.cols[i]
  if col then return col end
  col = Box(v, w, 386)
  col.title = Text(col, "GameFontNormal", "", w - 20, "CENTER")
  col.title:SetPoint("TOP", 0, -10)
  col.info = Text(col, "GameFontHighlightSmall", "", w - 20, "CENTER")
  col.info:SetPoint("TOP", col.title, "BOTTOM", 0, -4)
  col.btn = Btn(col, "Passa qui", 130, function(self)
    if col.teamId and ns.state and not ns.alt then
      P.ChooseTeam(ns.state, ns.recordGuid, col.teamId)
      T.RefreshSelf("team")
      -- the vanilla "joined a group" chime
      if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE) or 880) end
    end
  end)
  col.btn:SetPoint("TOP", col.info, "BOTTOM", 0, -6)
  col.mine = Text(col, "GameFontGreenSmall", "La squadra tua", w - 20, "CENTER")
  col.mine:SetPoint("TOP", col.info, "BOTTOM", 0, -10)
  col.rows = {}
  col.more = Text(col, "GameFontDisableSmall", "", w - 20, "CENTER")
  -- who the "e artri N" are: in the tooltip, each with level and how far from the cap
  col.moreHit = CreateFrame("Frame", nil, col)
  col.moreHit:SetPoint("BOTTOM", 0, 4)
  col.moreHit:SetSize(w - 20, 18)
  col.moreHit:EnableMouse(true)
  col.moreHit:SetScript("OnEnter", function(self) if self.lines then Tip(self, self.lines) end end)
  col.moreHit:SetScript("OnLeave", HideTip)
  v.cols[i] = col
  return col
end

local function RefreshGruppi(v)
  local state = ns.state
  local s = state.settings
  local rec = ns.MyRecord()
  local members = UI.Members()
  local groups, order = {}, {}
  for _, t in ipairs(s.teams) do
    groups[t.id] = {}
    order[#order + 1] = { id = t.id, name = t.name }
  end
  local loose = {}
  for _, m in ipairs(members) do
    if m.team and groups[m.team] then table.insert(groups[m.team], m) else loose[#loose + 1] = m end
  end
  if #loose > 0 then
    order[#order + 1] = { id = nil, name = "Da sceglie" }
  end
  local n = #order
  local gap = 8
  local w = math.floor((744 - gap * (n - 1)) / n)
  for _, c in ipairs(v.cols) do c:Hide() end
  for i, o in ipairs(order) do
    local col = v.cols[i]
    if col and math.abs(col:GetWidth() - w) > 1 then
      -- width changed (team added): rebuild that column
      col:Hide()
      v.cols[i] = nil
      col = nil
    end
    col = GruppiColumn(v, i, w)
    col:ClearAllPoints()
    col:SetPoint("TOPLEFT", (i - 1) * (w + gap), 0)
    col:Show()
    col.teamId = o.id
    local list = o.id and groups[o.id] or loose
    table.sort(list, function(a, b)
      if (a.lv or 0) ~= (b.lv or 0) then return (a.lv or 0) > (b.lv or 0) end
      return tostring(a.name) < tostring(b.name)
    end)
    local st = o.id and M.Status(s, o.id, U.Now())
    col.title:SetText(o.name)
    local online = 0
    for _, m in ipairs(list) do if Online(m) then online = online + 1 end end
    col.info:SetText((st and ("Cap " .. st.cap .. ", ") or "") .. #list .. (#list == 1 and " membro" or " membri") .. ", " .. online .. " online")
    local isMine = rec and o.id and rec.team == o.id
    col.mine:SetShown(isMine and true or false)
    col.btn:SetShown(o.id ~= nil and not isMine and not ns.alt)
    for _, r in ipairs(col.rows) do r:Hide() end
    -- as many as the column holds (11 in the window of now); the rest in the tooltip of "e artri"
    local maxRows = math.max(1, math.floor((col:GetHeight() - 80 - 24) / 24))
    for k, m in ipairs(list) do
      if k > maxRows then break end
      local r = col.rows[k] or MemberRow(col, w - 20)
      col.rows[k] = r
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", 10, -80 - (k - 1) * 24)
      r.rec = m
      local you = m.guid == ns.recordGuid
      r.name:SetText(Colored(m) .. (you and " |cffffd100(tu)|r" or ""))
      r.lv:SetText(tostring(m.lv or "?"))
      local cap = st and st.cap or 60
      r.state:SetText(st and StateText(m.lv, cap) or "")
      r.bar:SetValue(math.max(0, math.min(59, Position(m) - 1)))
      local over = st and m.lv and m.lv > cap
      BarColor(r.bar, Position(m), cap)
      r.capLine:ClearAllPoints()
      r.capLine:SetPoint("CENTER", r.bar, "LEFT", (math.min(60, cap) - 1) / 59 * r.barW, 0)
      r.capLine:SetShown(st ~= nil)
      local on = Online(m)
      r.dot:SetVertexColor(on and 0.1 or 0.35, on and 0.9 or 0.35, on and 0.1 or 0.35)
      r:Show()
    end
    col.more:ClearAllPoints()
    col.more:SetPoint("BOTTOM", 0, 8)
    col.more:SetText(#list > maxRows and ("... e artri " .. (#list - maxRows)) or (#list == 0 and "Ancora nessuno" or ""))
    local rest = nil
    if #list > maxRows then
      rest = { o.name .. ": l'artri" }
      for k = maxRows + 1, #list do
        local m = list[k]
        rest[#rest + 1] = Colored(m) .. "  |cffffffff" .. tostring(m.lv or "?") .. "|r" .. (st and ("  " .. StateText(m.lv, st.cap)) or "")
      end
    end
    col.moreHit.lines = rest
    col.moreHit:SetShown(rest ~= nil)
  end
  -- switches
  local lines = {}
  for i, sw in ipairs(state.switches or {}) do
    if i > 2 then break end
    lines[#lines + 1] = tostring(sw.name) .. " è passato da " .. P.TeamName(state, sw.from) .. " a " .. P.TeamName(state, sw.to) .. "  |cff9d9d9d" .. U.Ago(U.Now() - (sw.at or 0)) .. "|r"
  end
  v.switchText:SetText(#lines > 0 and table.concat(lines, "\n") or "|cff9d9d9dNessun cambio pe' ora.|r")
end

----------------------------------------------------------------------
-- Impostazioni tab
----------------------------------------------------------------------
local function BuildImp()
  local v = NewView("imp")
  local b1 = Box(v, 744, 124)
  b1:SetPoint("TOPLEFT", 0, 0)
  v.pattoName = Text(b1, "GameFontNormal", "", 480)
  v.pattoName:SetPoint("TOPLEFT", 12, -10)
  v.code = Input(b1, 190, 20)
  v.code:SetPoint("TOPLEFT", 20, -52)
  v.code:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  v.code:SetScript("OnTextChanged", function(self, user) if user and ns.state then self:SetText(ns.state.code) self:HighlightText() end end)
  Label(b1, "Codice der patto", v.code)
  -- one-click invite: they get a window with "Entra"
  v.invite = Input(b1, 150, 40, function(self)
    local name = self:GetText() or ""
    ns.InviteFriend(name, v.say) self:SetText("")
    self:ClearFocus()
  end)
  v.invite:SetPoint("TOPLEFT", 250, -52)
  Label(b1, "Invita 'n amico", v.invite)
  v.inviteBtn = Btn(b1, "Invita", 70, function()
    local name = v.invite:GetText() or ""
    ns.InviteFriend(name, v.say) v.invite:SetText("")
  end, 20)
  v.inviteBtn:SetPoint("LEFT", v.invite, "RIGHT", 6, 0)
  -- this page's status line: what a button did
  v.msg = Text(b1, "GameFontRedSmall", "", 300, "RIGHT")
  v.msg:SetPoint("TOPRIGHT", -150, -70)
  if v.msg.SetWordWrap then v.msg:SetWordWrap(false) end
  v.say = function(t, good) v.msg:SetText(good and ("|cff20ff20" .. t .. "|r") or t) end
  v.roles = Text(b1, "GameFontHighlightSmall", "", 480)
  v.roles:SetPoint("TOPLEFT", 12, -82)
  v.roles:SetJustifyV("TOP")
  v.link = Text(b1, "GameFontHighlightSmall", "", 240, "RIGHT")
  v.link:SetPoint("TOPRIGHT", -12, -14)
  v.sync = Btn(b1, "Sincronizza mo'", 130, function() C.Hello() v.say("Ho chiesto l'aggiornamenti a tutti.", true) end)
  v.sync:SetPoint("TOPRIGHT", -12, -40)
  v.diag = Btn(b1, "Diagnosi", 130, function() if ns.Diag then ns.Diag.Toggle() end end)
  v.diag:SetPoint("TOPRIGHT", -12, -66)

  local b3 = Box(v, 744, 172)
  b3:SetPoint("TOPLEFT", 0, -132)
  local ot = Text(b3, "GameFontNormal", "Opzioni")
  ot:SetPoint("TOPLEFT", 12, -10)
  local o = function() return ns.db.opts end
  v.checks = {
    Check(b3, "Avvisi in chat (ding dell'amichi, cambi de squadra, settimana nova)", function() return o().notify end, function(x) o().notify = x end),
    Check(b3, "Barretta cor cap sullo schermo (se trascina)", function() return o().hud end, function(x) o().hud = x end),
    Check(b3, "Avvisame si 'na quest me fa fa' ding oltre er cap", function() return o().questWarn end, function(x) o().questWarn = x end),
    Check(b3, "Titoli dell'amichi in chat davanti a quello che scriveno", function() return o().chatTitles ~= false end, function(x) o().chatTitles = x end),
    Check(b3, "Annunci der patto (ding, epici, morti ridicole, tombole, gogne)", function() return o().toasts end, function(x) o().toasts = x end),
    Check(b3, "Sonoro co' l'annunci", function() return o().toastSound end, function(x) o().toastSound = x end),
    Check(b3, "Bottone su la minimappa", function() return o().minimap ~= false end, function(x) o().minimap = x end),
  }
  for i, c in ipairs(v.checks) do c:SetPoint("TOPLEFT", 12, -26 - (i - 1) * 20) end

  local b4 = Box(v, 744, 140)
  b4:SetPoint("TOPLEFT", 0, -312)
  v.altText = Text(b4, "GameFontHighlightSmall", "", 470)
  v.altText:SetPoint("TOPLEFT", 12, -12)
  v.altText:SetJustifyV("TOP")
  v.altBtn = Btn(b4, "Entra co' 'sto personaggio", 210, function()
    if ns.alt and ns.state then ns.JoinPatto(ns.state.code) end
  end)
  v.altBtn:SetPoint("TOPRIGHT", -12, -12)
  -- the addon's version of everyone: who has to update
  v.verTitle = Text(b4, "GameFontNormal", "Versioni de l'addon", 300)
  v.verTitle:SetPoint("TOPLEFT", 12, -34)
  v.vers = Text(b4, "GameFontHighlightSmall", "", 480)
  v.vers:SetPoint("TOPLEFT", 12, -52)
  v.vers:SetJustifyV("TOP")
  v.leaveErr = Text(b4, "GameFontRedSmall", "", 470)
  v.leaveErr:SetPoint("BOTTOMLEFT", 12, 12)
  v.leave = ConfirmBtn(b4, "Esci dar patto", 170, function()
    v.leaveErr:SetText("")
    if ns.IsCapo() then
      local others = 0
      for g in pairs(ns.state.members) do if g ~= ns.me then others = others + 1 end end
      if others > 0 then v.leaveErr:SetText("Sei er capo: prima passa er comando a 'n artro (tab Capo).") return end
    end
    ns.LeavePatto()
    current = "cap"
  end)
  v.leave:SetPoint("BOTTOMRIGHT", -12, 12)
end

local function RefreshImp(v)
  local state = ns.state
  local s = state.settings
  v.pattoName:SetText(tostring(s.name or "Er Patto"))
  if not v.code:HasFocus() then v.code:SetText(state.code) end
  local capo = state.members[state.admins.capo]
  local vices = {}
  for g in pairs(state.admins.vice or {}) do
    local r = state.members[g]
    vices[#vices + 1] = r and r.name or "?"
  end
  local start = s.start and ("Partenza: " .. U.When(s.start) .. " (ora italiana)") or ""
  v.roles:SetText("Capo: " .. tostring(capo and capo.name or "?") .. (#vices > 0 and ("   Vice: " .. table.concat(vices, ", ")) or "") .. "\n" .. start)
  local mode = C.stats.mode
  local online = 0
  for g in pairs(state.members) do if g ~= ns.recordGuid and C.IsOnline(g) then online = online + 1 end end
  local col = (mode == "canale" or mode == "gilda") and "ff40ff40" or (mode == "sussurri" and "ffffd100" or "ff9d9d9d")
  v.link:SetText("Collegamento: |c" .. col .. mode .. "|r, " .. online .. " online")
  for _, c in ipairs(v.checks) do c.Sync() end
  if ns.alt then
    local main = state.members[ns.recordGuid]
    v.altText:SetText("Stai co' 'n alt de " .. tostring(main and main.name or "?") .. ": vedi tutto, ma livelli e statistiche contano solo pe' er principale. Se vòi che 'sto personaggio conti, entra cor codice.")
    v.altBtn:Show()
  else
    v.altText:SetText("Personaggio: " .. tostring(ns.myName))
    v.altBtn:Hide()
  end
  -- who's behind with the addon (the version each record carries)
  local function Parts(x) local t = {} for n in tostring(x or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end return t end
  local function Older(a, b)
    local x, y = Parts(a), Parts(b)
    for i = 1, math.max(#x, #y) do
      if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) < (y[i] or 0) end
    end
    return false
  end
  local newest = ns.VERSION
  for _, m in pairs(state.members) do if m.ver and Older(newest, m.ver) then newest = m.ver end end
  local old, unknown = {}, {}
  for _, m in pairs(state.members) do
    if not m.ver then unknown[#unknown + 1] = U.Short(m.name)
    elseif Older(m.ver, newest) then old[#old + 1] = U.Short(m.name) .. " |cff9d9d9d(" .. m.ver .. ")|r" end
  end
  table.sort(old) table.sort(unknown)
  local lines = { "L'urtima: |cffffffff" .. tostring(newest) .. "|r" .. (Older(ns.VERSION, newest) and "  |cffff4040(tu c'hai la " .. tostring(ns.VERSION) .. ": aggiorna)|r" or "  (tu ce l'hai)") }
  lines[#lines + 1] = #old > 0 and ("|cffff8033Da aggiorna':|r " .. table.concat(old, ", ")) or "|cff20ff20Tutti aggiornati.|r"
  if #unknown > 0 then lines[#lines + 1] = "|cff9d9d9dNun se sa:|r " .. table.concat(unknown, ", ") end
  v.vers:SetText(table.concat(lines, "\n"))
end

----------------------------------------------------------------------
-- Capo tab (capo and vice)
----------------------------------------------------------------------
local function BuildCapo()
  local v = NewView("capo")
  local b1 = Box(v, 744, 160)
  b1:SetPoint("TOPLEFT", 0, 0)
  -- the page's status line: what happened, or what went wrong
  v.err = Text(b1, "GameFontRedSmall", "", 440, "RIGHT")
  v.err:SetPoint("TOPRIGHT", -12, -10)
  if v.err.SetWordWrap then v.err:SetWordWrap(false) end
  v.ok = function(text) v.err:SetText("|cff20ff20" .. text .. "|r") end
  local t1 = Text(b1, "GameFontNormal", "Ritmo de le squadre")
  t1:SetPoint("TOPLEFT", 12, -10)
  v.fromText = Text(b1, "GameFontHighlightSmall", "", 720)
  v.fromText:SetPoint("TOPLEFT", 12, -27)
  local hs = { { "Squadra", 24 }, { "Ore a settimana", 192 }, { "Cap che ne viene fori", 360 } }
  for _, h in ipairs(hs) do
    local t = Text(b1, "GameFontNormalSmall", h[1])
    t:SetPoint("TOPLEFT", h[2], -43)
  end
  local function rowY(i) return -58 - (i - 1) * 19 end
  v.pace = {}
  for i = 1, P.MAX_TEAMS do
    local row = {}
    row.name = Input(b1, 150, 24)
    row.name:SetPoint("TOPLEFT", 28, rowY(i))
    row.hours = Input(b1, 40, 3)
    row.hours:SetPoint("TOPLEFT", 196, rowY(i))
    row.apply = Btn(b1, "Applica", 80, function()
      local t = ns.state.settings.teams[i]
      if not t then return end
      local h = Num(row.hours:GetText())
      if not h or h < 1 or h > 100 then v.err:SetText("Ore: da 1 a 100.") return end
      local nm = row.name:GetText() or ""
      if nm ~= "" and nm ~= t.name then P.RenameTeam(ns.state, ns.me, t.id, nm:sub(1, 24)) end
      local ok, e = P.SetPace(ns.state, ns.me, t.id, h)
      v.err:SetText(ok and "" or (e or "Nun è andata."))
      if ok then
        local st = M.Status(ns.state.settings, t.id, U.Now())
        local now = math.max(1, st and st.week or 1)
        if e == now then v.ok(t.name .. ": " .. h .. " ore a settimana da 'sta settimana, mo' cap " .. (st and st.cap or "?") .. ".")
        else v.ok(t.name .. ": " .. h .. " ore a settimana da la settimana " .. e .. " (quarcuno de la squadra è già sopra: er cap de 'sta settimana resta).") end
      end
    end, 20)
    row.apply:SetPoint("TOPLEFT", 250, rowY(i) + 1)
    row.info = Text(b1, "GameFontHighlightSmall", "", 370)
    row.info:SetPoint("TOPLEFT", 360, rowY(i) - 4)
    v.pace[i] = row
  end
  -- the first free row becomes "new team"
  v.addName = Input(b1, 150, 24)
  v.addHours = Input(b1, 40, 3)
  v.addBtn = Btn(b1, "Aggiungi", 80, function()
    local nm, h = v.addName:GetText() or "", Num(v.addHours:GetText())
    if nm == "" or not h or h < 1 or h > 100 then v.err:SetText("Squadra nova: nome e ore da 1 a 100.") return end
    local ok, e = P.AddTeam(ns.state, ns.me, nm:sub(1, 24), h)
    v.err:SetText(ok and "" or (e or "Nun è andata."))
    if ok then v.addName:SetText("") v.addHours:SetText("") v.ok("Squadra " .. nm:sub(1, 24) .. " aggiunta.") end
  end, 20)
  v.addHint = Text(b1, "GameFontDisableSmall", "Squadra nova (facortativa)", 300)
  v.rowY = rowY

  local b2 = Box(v, 368, 288)
  b2:SetPoint("TOPLEFT", 0, -164)
  local t2 = Text(b2, "GameFontNormal", "Partenza, regole e annuncio")
  t2:SetPoint("TOPLEFT", 12, -10)
  v.startText = Text(b2, "GameFontHighlightSmall", "", 340)
  v.startText:SetPoint("TOPLEFT", 16, -32)
  v.startBtn = Btn(b2, "Cambia partenza", 140, function()
    UI.PickDate(ns.state.settings.start, function(epoch)
      local ok, e = P.SetStart(ns.state, ns.me, epoch)
      v.err:SetText(ok and "" or (e or "Nun è andata."))
      if ok then v.ok("Partenza cambiata: " .. U.When(epoch) .. ".") end
      UI.Refresh()
    end)
  end)
  v.startBtn:SetPoint("TOPLEFT", 14, -48)
  v.ah = Check(b2, "Li sordi de l'asta contano come sordi fatti", function() return ns.state and not ns.state.settings.noAh end,
    function(on)
      local ok, e = P.SetAuctionGold(ns.state, ns.me, on)
      v.err:SetText(ok and "" or (e or "Nun è andata."))
    end)
  v.ah:SetPoint("TOPLEFT", 12, -74)
  v.test = Check(b2, "Modalità de prova (membri finti, solo pe' te)", function() return ns.db.opts.testMode end, function(x) ns.db.opts.testMode = x end)
  v.test:SetPoint("TOPLEFT", 12, -96)
  -- the announcement everyone has to confirm once
  local al = Text(b2, "GameFontNormalSmall", "Annuncio:")
  al:SetPoint("TOPLEFT", 16, -130)
  v.ann = Input(b2, 270, 250)
  v.ann:SetPoint("TOPLEFT", 80, -126)
  v.annPost = Btn(b2, "Pubblica", 90, function()
    local text = strtrim and strtrim(v.ann:GetText() or "") or (v.ann:GetText() or "")
    if text == "" then v.err:SetText("Scrivi prima l'annuncio.") return end
    local ok, e = P.SetAnnouncement(ns.state, ns.me, text, ns.myName)
    v.err:SetText(ok and "" or (e or "Nun è andata."))
    if ok then
      ns.db.annSeen = ns.db.annSeen or {}
      ns.db.annSeen[ns.state.code] = ns.state.settings.ann and ns.state.settings.ann.at
      v.ann:SetText("")
      v.ok("Annuncio pubblicato: lo vedono tutti appena entrano.")
    end
  end, 20)
  v.annPost:SetPoint("TOPLEFT", 76, -150)
  -- see it as the others will, the first time they log in
  v.annPreview = Btn(b2, "Anteprima", 90, function() UI.ShowAnnouncement(true) end, 20)
  v.annPreview:SetPoint("LEFT", v.annPost, "RIGHT", 6, 0)
  -- the one that's live now; the little X in front of it takes it down
  v.annDel = CreateFrame("Button", nil, b2)
  v.annDel:SetSize(20, 20)
  v.annDel:SetPoint("TOPLEFT", 12, -176)
  v.annDel:SetNormalTexture(MEDIA .. "close-up.tga")
  v.annDel:SetPushedTexture(MEDIA .. "close-down.tga")
  v.annDel:SetHighlightTexture(MEDIA .. "close-hl.tga", "ADD")
  v.annDel:SetScript("OnClick", function()
    local ok, e = P.SetAnnouncement(ns.state, ns.me, nil)
    v.err:SetText(ok and "" or (e or "Nun è andata."))
    if ok then v.ok("Annuncio tolto.") end
  end)
  v.annDel:SetScript("OnEnter", function(self) Tip(self, { "Togli l'annuncio" }) end)
  v.annDel:SetScript("OnLeave", HideTip)
  v.annNow = Text(b2, "GameFontHighlightSmall", "", 316)
  v.annNow:SetPoint("TOPLEFT", 36, -180)
  if v.annNow.SetMaxLines then v.annNow:SetMaxLines(2) end

  local b3 = Box(v, 372, 288)
  b3:SetPoint("TOPLEFT", 372, -164)
  v.memTitle = Text(b3, "GameFontNormal", "Membri")
  v.memTitle:SetPoint("TOPLEFT", 12, -10)
  local scroll = CreateFrame("ScrollFrame", "ErPattoCapoScroll", b3, "UIPanelScrollFrameTemplate")
  VanillaScroll(scroll)
  scroll:SetPoint("TOPLEFT", 8, -30)
  scroll:SetPoint("BOTTOMRIGHT", -30, 8)
  local body = CreateFrame("Frame", nil, scroll)
  body:SetSize(700, 10)
  scroll:SetScrollChild(body)
  v.body, v.rows = body, {}
end

local function RefreshCapo(v)
  local state = ns.state
  local s = state.settings
  local from = P.FirstEditableWeek(state)
  v.fromText:SetText("Er cap de ogni settimana lo calcola l'addon da le ore a settimana. Le ore nove valgono da 'sta settimana.")
  for i, row in ipairs(v.pace) do
    local t = s.teams[i]
    local show = t ~= nil
    for _, w in pairs(row) do w:SetShown(show) end
    if t then
      if not row.name:HasFocus() then row.name:SetText(t.name) end
      local act = M.Active(t.pace, from, "hours")
      if not row.hours:HasFocus() then row.hours:SetText(act and tostring(act.hours) or "") end
      local rows = M.TeamRows(s, t)
      local st = M.Status(s, t.id, U.Now())
      local nextRow = rows[from]
      local txt = st and (st.started and ("Mo' cap " .. st.cap) or ("Prima settimana cap " .. st.cap)) or ""
      if nextRow and from > math.max(1, st and st.week or 1) then txt = txt .. ", settimana " .. from .. " cap " .. nextRow.cap end
      local finish
      for k, r in ipairs(rows) do if r.cap >= 60 then finish = k break end end
      if finish then txt = txt .. ", ar 60 in settimana " .. finish end
      row.info:SetText(txt)
    end
  end
  local full = #s.teams >= P.MAX_TEAMS
  local y = v.rowY(#s.teams + 1)
  v.addName:ClearAllPoints()
  v.addName:SetPoint("TOPLEFT", 28, y)
  v.addHours:ClearAllPoints()
  v.addHours:SetPoint("TOPLEFT", 196, y)
  v.addBtn:ClearAllPoints()
  v.addBtn:SetPoint("TOPLEFT", 250, y + 1)
  v.addHint:ClearAllPoints()
  v.addHint:SetPoint("TOPLEFT", 360, y - 4)
  v.addName:SetShown(not full)
  v.addHours:SetShown(not full)
  v.addBtn:SetShown(not full)
  v.addHint:SetShown(not full)
  v.startText:SetText(s.start and ("Se parte " .. U.When(s.start) .. ", ora italiana.") or "")
  v.ah.Sync()
  v.test.Sync()
  v.test:SetShown(ns.IsCapo())
  v.test.label:SetShown(ns.IsCapo())
  if s.ann then
    v.annNow:SetText("|cffffd100Mo' c'è:|r " .. s.ann.t .. "  |cff9d9d9d(" .. U.When(s.ann.at) .. ")|r")
  else
    v.annNow:SetText("|cff9d9d9dNessun annuncio pubblicato.|r")
  end
  v.annDel:SetShown(s.ann ~= nil)
  v.annNow:ClearAllPoints()
  v.annNow:SetPoint("TOPLEFT", s.ann and 36 or 16, -180)
  v.annPreview:SetEnabled(s.ann ~= nil)
  local started = M.WeekIndex(s, U.Now()) >= 1
  v.startBtn:SetEnabled(not started)
  -- members with role buttons
  local list = P.SortedMembers(state)
  local capo = ns.IsCapo()
  for _, r in ipairs(v.rows) do r:Hide() end
  local guard = capo and ns.Guardia and ns.Guardia.Report()
  for i, m in ipairs(list) do
    local row = v.rows[i]
    if not row then
      row = CreateFrame("Frame", nil, v.body)
      row:SetSize(330, 22)
      row.name = Text(row, "GameFontHighlightSmall", "", 150)
      if row.name.SetWordWrap then row.name:SetWordWrap(false) end
      row.name:SetPoint("LEFT", 4, 0)
      -- played with the addon off: the details in the tooltip (Guardia.lua)
      row:SetScript("OnEnter", function(self)
        local lines = { self.title or "?" , self.sub }
        if self.off then
          lines[#lines + 1] = "|cffff4040Addon spento:|r"
          for k = 1, math.min(6, #self.off.lines) do lines[#lines + 1] = self.off.lines[k] end
        end
        Tip(self, lines)
      end)
      row:SetScript("OnLeave", HideTip)
      row.vice = Btn(row, "Vice", 66, function(self)
        local on = not (ns.state.admins.vice or {})[self.guid]
        local ok, e = P.SetVice(ns.state, ns.me, self.guid, on)
        local m = ns.state.members[self.guid]
        if ok == false then v.err:SetText(e or "Nun è andata.")
        else v.ok((m and m.name or "?") .. (on and " mo' è vice." or " nun è più vice.")) end
      end, 20)
      row.vice:SetPoint("LEFT", 156, 0)
      row.capo = ConfirmBtn(row, "Capo", 52, function(self)
        local m = ns.state.members[self.guid]
        local ok, e = P.TransferCapo(ns.state, ns.me, self.guid)
        if ok == false then v.err:SetText(e or "Nun è andata.") else v.ok("Er capo mo' è " .. (m and m.name or "?") .. ".") end
      end)
      row.capo:SetHeight(20)
      row.capo:SetPoint("LEFT", row.vice, "RIGHT", 4, 0)
      row.ban = ConfirmBtn(row, "Caccia", 54, function(self)
        local m = ns.state.members[self.guid]
        local ok, e = P.Ban(ns.state, ns.me, self.guid)
        if not ok then v.err:SetText(e or "Nun è andata.") else v.ok((m and m.name or "?") .. " è fori dar patto.") end
      end)
      row.ban:SetHeight(20)
      row.ban:SetPoint("LEFT", row.capo, "RIGHT", 4, 0)
      v.rows[i] = row
    end
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
    local role = (m.guid == state.admins.capo) and " |cffffd100(capo)|r" or (((state.admins.vice or {})[m.guid]) and " |cffffd100(vice)|r" or "")
    local off = guard and guard[m.guid]
    row.name:SetText(Colored(m) .. role .. (off and " |cffff4040spento|r" or ""))
    row.off = off
    row.title, row.sub = tostring(m.name), P.TeamName(state, m.team) .. ", livello " .. tostring(m.lv or "?")
    row:EnableMouse(true)
    local isSelf = m.guid == ns.me
    local isCapo = m.guid == state.admins.capo
    row.vice.guid, row.capo.guid, row.ban.guid = m.guid, m.guid, m.guid
    row.vice:SetText(((state.admins.vice or {})[m.guid]) and "Togli vice" or "Vice")
    row.vice:SetShown(capo and not isSelf)
    row.capo:SetShown(capo and not isSelf)
    row.ban:SetShown(not isSelf and not isCapo)
    row:Show()
  end
  v.body:SetHeight(math.max(10, #list * 22))
  v.memTitle:SetText("Membri |cffffffff(" .. #list .. ")|r")
  UI.FitScroll(_G.ErPattoCapoScroll, #list * 22, 211 - 38)
end

----------------------------------------------------------------------
-- build and refresh
----------------------------------------------------------------------
local function Build()
  f = CreateFrame("Frame", "ErPattoFrame", UIParent, BD)
  f:SetSize(W, H)
  local pt = ns.db and ns.db.ui and ns.db.ui.main
  if type(pt) == "table" and pt[1] then f:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else f:SetPoint("CENTER", 0, 40) end
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if ns.db then ns.db.ui.main = { p, rp, x, y } end
  end)
  -- the window: the vanilla character frame (UI-Character-General), cut so it fits this size: the top with the
  -- round portrait, the title strip and the close box as they are; the borders and the marble repeated at their own
  -- size (never stretched), so the stone looks as in the game
  local fill = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  fill:SetColorTexture(0.05, 0.05, 0.05, 1)
  fill:SetPoint("TOPLEFT", 2, -2)
  fill:SetPoint("BOTTOMRIGHT", -2, 2)
  local ART = "Interface\\PaperDollInfoFrame\\UI-Character-General-"
  -- x0, x1, y0, y1 in the 384x512 picture the four files make (left files 256 wide, right ones 128)
  local function Art(x0, x1, y0, y1, x, y, w, h)
    local right, bottom = x0 >= 256, y0 >= 256
    local t = f:CreateTexture(nil, "BACKGROUND", nil, 0)
    t:SetTexture(ART .. (bottom and "Bottom" or "Top") .. (right and "Right" or "Left"))
    local ox, oy, fw = right and 256 or 0, bottom and 256 or 0, right and 128 or 256
    t:SetTexCoord((x0 - ox) / fw, (x1 - ox) / fw, (y0 - oy) / 256, (y1 - oy) / 256)
    Put(t, f, x, y, w, h)
    return t
  end
  -- the picture's frame runs from x 10 to 348 and from y 13 to 436
  -- the same, repeated at its own size instead of stretched (left files only for the repeats)
  local function ArtTile(x0, x1, y0, y1, x, y, w, h, tileX, tileY)
    local right, bottom = x0 >= 256, y0 >= 256
    local ox, oy, fw = right and 256 or 0, bottom and 256 or 0, right and 128 or 256
    return Tile(f, ART .. (bottom and "Bottom" or "Top") .. (right and "Right" or "Left"), fw, 256,
      x0 - ox, y0 - oy, x1 - ox, y1 - oy, x, y, w, h, "BACKGROUND", 0, tileX, tileY)
  end
  Art(0, 100, 0, 80, -10, -13, 100, 80)
  -- the top between the portrait and the close box: the title strip as the art has it (its stone, its rails),
  -- repeated at its own size like the stone under it (a one pixel column stretched made streaks), and the
  -- stone under the title the same way
  ArtTile(100, 250, 0, 34, 90, -13, W - 138, 34, true, false)
  ArtTile(100, 250, 34, 72, 90, 21, W - 138, 38, true, false)
  Art(170, 171, 72, 80, 90, 59, W - 138, 8)
  Art(300, 352, 0, 80, W - 48, -13, 52, 80)
  -- the side and bottom rails: a one pixel cut drawn along the whole length (smooth, as in the game); the marble
  -- inside repeated at its own size
  -- (measured: the left border is x 10..19 of the picture, the right one 340..348, the bottom one y 430..436;
  -- inside them only marble)
  Art(0, 20, 150, 151, -10, 67, 20, H - 73)
  MarblePlane(f, 10, 67, 10, 67, W - 18, H - 73, "BACKGROUND", 0)
  Art(340, 352, 150, 151, W - 8, 67, 12, H - 73)
  Art(0, 20, 430, 440, -10, H - 6, 20, 10)
  Art(150, 151, 430, 440, 10, H - 6, W - 18, 10)
  Art(340, 352, 430, 440, W - 8, H - 6, 12, 10)
  -- the round portrait: the icon of the vanilla Social window (the patto is a group of friends)
  local portrait = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  Put(portrait, f, -5, -11, 63, 63)
  portrait:SetTexture("Interface\\FriendsFrame\\FriendsFrameScrollIcon")
  f.portrait = portrait
  local function Face() end
  f.Face = Face
  -- the selected tab, over the bottom border
  f.selTab = {}
  f.selFills = {} -- the inside of the selected tab, per place: the window's own marble plane, so it runs on
  for _, k in ipairs({ P_L, P_R, P_BL, P_BR, P_B }) do f.selTab[k] = RailTex(f, nil, k, "ARTWORK", 1) end
  if UISpecialFrames then table.insert(UISpecialFrames, "ErPattoFrame") end
  f:Hide()

  -- the name of the patto in the title strip, the close button in its box
  local title = Text(f, "GameFontHighlight", "Er Patto", W - 160, "CENTER")
  title:SetPoint("CENTER", f, "TOPLEFT", W / 2 + 18, -10)
  if title.SetWordWrap then title:SetWordWrap(false) end
  f.title = title
  function f.SetTitle(text) title:SetText(text) end
  local close = CreateFrame("Button", nil, f)
  close:SetSize(32, 32)
  close:SetPoint("CENTER", f, "TOPRIGHT", -12, -10)
  close:SetFrameLevel(f:GetFrameLevel() + 25)
  close:SetNormalTexture(MEDIA .. "close-up.tga")
  close:SetPushedTexture(MEDIA .. "close-down.tga")
  close:SetHighlightTexture(MEDIA .. "close-hl.tga", "ADD")
  if close.SetHitRectInsets then close:SetHitRectInsets(5, 5, 5, 5) end
  close:SetScript("OnClick", function() f:Hide() end)
  f.close = close
  -- the "i": what this tab is for, in its tooltip (Extras.INFO)
  local help = CreateFrame("Button", nil, f)
  help:SetSize(16, 16)
  help:SetPoint("TOPRIGHT", -26, -24)
  help:SetFrameLevel(f:GetFrameLevel() + 25)
  help:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
  help:SetHighlightTexture("Interface\\FriendsFrame\\InformationIcon-Highlight", "ADD")
  help:SetScript("OnEnter", function(self)
    local info = ns.Extras and ns.Extras.INFO
    if not info then return end
    -- a page with tabs of its own (the Botteghino) has one text per tab
    local sub = current == "botteghino" and ns.Botteghino and ns.Botteghino.Page and ns.Botteghino.Page()
    local lines = (sub and info[current .. ":" .. sub]) or info[current]
    if lines then Tip(self, lines) end
  end)
  help:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.help = help
  f.info = Text(f, "GameFontHighlightSmall", "", 300)
  f.info:SetPoint("TOPLEFT", 72, -34)
  f.alert = Text(f, "GameFontRedSmall", "", 260, "CENTER")
  f.alert:SetPoint("TOP", 0, -34)
  LayoutChrome()

  content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 18, -66)
  content:SetPoint("BOTTOMRIGHT", -18, 16)

  BuildWelcome()
  BuildCreate()
  BuildAlt()
  for _, x in ipairs(UI.extra) do x.build() end
  BuildWaiting()
  BuildCap()
  BuildGruppi()
  BuildImp()
  BuildCapo()
  local order = {}
  for _, x in ipairs(UI.extra) do if x.first then order[#order + 1] = { x.key, x.label } end end
  for _, t in ipairs({ { "botteghino", "Botteghino" }, { "progresso", "Progresso" }, { "cap", "Cap" }, { "gruppi", "Squadre" }, { "imp", "Impostazioni" }, { "capo", "Capo" } }) do
    order[#order + 1] = t
  end
  for i, t in ipairs(order) do MakeTab(i, t[1], t[2]) end
  f:SetScript("OnShow", function() f.Face() UI.Refresh() end)
  f:SetScript("OnHide", function() if UI.CloseMenus then UI.CloseMenus() end end)
end

UI._views, UI._tabs = views, tabs

-- other files add their own tabs: build() runs when the window is first built, refresh(view) when it shows
UI.extra = {}
function UI.AddView(key, label, build, refresh, first)
  UI.extra[#UI.extra + 1] = { key = key, label = label, build = build, first = first }
  UI.refreshers = UI.refreshers or {}
  UI.refreshers[key] = refresh
end
-- a scroll list shows its bar only when the content is taller than the list
-- viewH: the visible height, as built (the frame's own height can read 0 before the first layout)
function UI.FitScroll(scroll, contentH, viewH)
  if not scroll then return end
  local bar = scroll.ScrollBar
  if type(bar) ~= "table" then bar = scroll.GetName and scroll:GetName() and _G[scroll:GetName() .. "ScrollBar"] end
  if type(bar) ~= "table" or not bar.SetShown then bar = nil end
  local h = viewH or (scroll.GetHeight and scroll:GetHeight()) or 0
  local need = contentH > h + 1
  if bar then bar:SetShown(need) end
  if not need and scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
end

UI.H = { MarbleTiles = MarbleTiles, RedButton = RedButton, CloseX = CloseX, Dropdown = Dropdown, FitScroll = UI.FitScroll, Stone = Stone, Chrome = Chrome, DialogHeader = DialogHeader, Marble = Marble, VanillaScroll = VanillaScroll, Border = Border, MEDIA = MEDIA, Radio = Radio, BarColor = BarColor, Input = Input, Label = Label, TopTab = TopTab, Box = Box, Text = Text, Btn = Btn, Tip = Tip, HideTip = HideTip, Colored = Colored, StateText = StateText,
  Position = Position, CapBar = CapBar, NewView = NewView, StatOf = StatOf, Online = Online, Safe = Safe, ClassHex = ClassHex }
function UI.IsShown(key) return f and f:IsShown() and current == key end

local REFRESH = { cap = RefreshCap, gruppi = RefreshGruppi, imp = RefreshImp, capo = RefreshCapo }

function UI.Refresh()
  UI.RefreshHUD()
  if not f or not f:IsShown() or refreshing then return end
  refreshing = true
  Safe(function()
    local state = ns.state
    for _, v in pairs(views) do v:Hide() end
    local acct = not state and ns.AccountPatto and ns.AccountPatto() or nil
    if not state and not acct then
      for _, b in ipairs(tabs) do b:Hide() end
      LayoutTabs()
      f.SetTitle("Er Patto")
      f.info:SetText("Nun stai in nessun patto. Creane uno o entra co' 'n codice.")
      f.alert:SetText("")
      if wantCreate then
        views.create.startBtn:SetText(U.When(views.create.startAt))
        views.create:Show()
      else
        views.welcome:Show()
      end
      return
    end
    -- another character of the account is in a patto: this one sees nothing of it, only the way in (as a member
    -- of its own), and the link as an alt, which only the player turns on
    if ns.alt or acct then
      local st = state or acct
      for _, b in ipairs(tabs) do b:Hide() end
      LayoutTabs()
      f.SetTitle(P.HasSettings(st) and tostring(st.settings.name) or "Er Patto")
      f.info:SetText("|cff9d9d9dStai co' 'n alt|r")
      f.alert:SetText("")
      local main = st.members[ns.alt and ns.recordGuid or st.main]
      local name = tostring(main and main.name or "?")
      local v = views.alt
      v.text:SetText((ns.alt and ("'Sto personaggio è collegato come alt de " .. name .. ": l'amichi lo vedono sotto de lui, co' nome e livello.")
          or ("'Sto personaggio nun sta ner patto de " .. name .. ": l'amichi nun lo vedono.")) ..
        " Co' l'alt nun vedi gnente der patto e nun pòi giocà a gnente.\n\n" ..
        "Si vòi, entra co' 'sto personaggio: diventa 'n membro come l'artri, co' la squadra sua, er cap suo e le piotte sue. Er main nun pò scommette su de lui.")
      v.link:SetText(ns.alt and "Scollegalo" or "Collegalo come alt")
      v.link.tip = ns.alt and { "Scollegalo", "Esce dar patto: sparisce da sotto " .. name .. " appena entri co' " .. name .. "." }
        or { "Collegalo come alt", "L'amichi lo vedono sotto " .. name .. ", co' nome e livello. Nun conta pe' gnente." }
      v:Show()
      return
    end
    local admin = ns.CanAdmin()
    for _, b in ipairs(tabs) do b:SetShown(b.key ~= "capo" or admin) end
    if current == "capo" and not admin then current = "imp" end
    for _, b in ipairs(tabs) do b:SetSelected(b.key == current) end
    LayoutTabs()
    local s = state.settings
    f.SetTitle(P.HasSettings(state) and tostring(s.name) or "Er Patto")
    f.info:SetText((ns.alt and "|cff9d9d9dStai co' 'n alt|r  " or "") .. ((ns.db.opts.testMode and ns.IsCapo()) and "|cffff8000Modalità de prova|r" or ""))
    local rec = ns.MyRecord()
    local st = ns.MyStatus()
    if st and st.started and not st.lifted and rec and rec.lv and rec.lv > st.cap then f.alert:SetText("Sei sopra er cap!") else f.alert:SetText("") end
    if not P.HasSettings(state) and current ~= "imp" then
      local w = views.waiting
      local known = 0
      for _ in pairs(state.members) do known = known + 1 end
      w.info:SetText("Sei entrato cor codice " .. state.code .. ".\nAppena 'n artro der patto è online, l'addon riceve er ritmo e le squadre.\nCollegamento: " .. C.stats.mode .. ", membri conosciuti: " .. known)
      w:Show()
      return
    end
    if not P.HasSettings(state) then
      -- settings tab still works while waiting (leave, diagnostics)
      views.imp:Show()
      Safe(RefreshImp, views.imp)
      return
    end
    local v = views[current]
    if not v then current = "cap" v = views.cap end
    v:Show()
    local fn = REFRESH[current] or (UI.refreshers and UI.refreshers[current])
    fn(v)
  end)
  refreshing = false
end

function UI.Frame() return f end
function UI.Hide() if f then f:Hide() end end
function UI.StartDrag() if f then f:StartMoving() end end
function UI.StopDrag()
  if not f then return end
  f:StopMovingOrSizing()
  local p, _, rp, x, y = f:GetPoint()
  if ns.db then ns.db.ui.main = { p, rp, x, y } end
end

function UI.Toggle()
  if not f then Build() end
  if f:IsShown() then f:Hide() else f:Show() end
end

function UI.Show(tab)
  if not f then Build() end
  if tab then current = tab end
  f:Show()
  UI.Refresh()
end

----------------------------------------------------------------------
-- the small cap bar on screen
----------------------------------------------------------------------
-- the cap bar on screen, built like the vanilla casting bar (UI-CastingBar-Border, 195x13, spark).
-- It fills from last week's cap to this week's cap: blue while you're behind, green at the cap, red above it.
-- Text: the cap, how far you are from it, the next cap.
local hud
local function BuildHUD()
  hud = CreateFrame("StatusBar", "ErPattoHUD", UIParent)
  hud:SetSize(195, 13)
  local pt = ns.db and ns.db.ui and ns.db.ui.hud
  if type(pt) == "table" and pt[1] then hud:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4]) else hud:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 150) end
  hud:SetStatusBarTexture(BAR)
  hud:SetMinMaxValues(0, 1)
  hud:SetValue(0)
  local bg = hud:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.5)
  local border = hud:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
  border:SetSize(256, 64)
  border:SetPoint("TOP", 0, 28)
  hud.spark = hud:CreateTexture(nil, "OVERLAY", nil, 1)
  hud.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  hud.spark:SetBlendMode("ADD")
  hud.spark:SetSize(32, 32)
  hud.text = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  hud.text:SetPoint("TOP", 0, 5)
  hud.text:SetSize(185, 16)
  -- how far over or under the cap: small, just outside the right end of the bar (never red on red)
  hud.over = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hud.over:SetPoint("LEFT", hud, "RIGHT", 10, 1)
  -- above the bar, small and light grey, only while you wait for the next cap ("Prossimo cap: 22, tra 2 giorni")
  hud.next = hud:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hud.next:SetPoint("BOTTOM", hud, "TOP", 0, 12)
  hud.next:SetTextColor(0.85, 0.85, 0.85)
  hud:SetClampedToScreen(true)
  hud:SetMovable(true)
  hud:EnableMouse(true)
  hud:RegisterForDrag("LeftButton")
  hud:SetScript("OnDragStart", function(self) self.moved = true self:StartMoving() end)
  hud:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    if ns.db then ns.db.ui.hud = { p, rp, x, y } end
  end)
  -- a click opens the window; the end of a drag doesn't
  hud:SetScript("OnMouseUp", function(self, button)
    if self.moved then self.moved = false return end
    if button == "LeftButton" then UI.Toggle() end
  end)
  hud:SetScript("OnEnter", function(self) if self.tip then Tip(self, self.tip) end end)
  hud:SetScript("OnLeave", HideTip)
end

local function HudColor(r, g, b)
  hud:SetStatusBarColor(r, g, b)
  hud.spark:SetVertexColor(r, g, b)
end

function UI.RefreshHUD()
  local show = ns.db and ns.db.opts.hud and ns.state and P.HasSettings(ns.state) and not ns.alt
  if not show then
    if hud then hud:Hide() end
    return
  end
  if not hud then BuildHUD() end
  local st = ns.MyStatus()
  local rec = ns.MyRecord()
  local now = U.Now()
  local fill, text, nextText, over = 0, "", "", ""
  local tip = { "Er Patto" }
  if not st then
    HudColor(0.5, 0.5, 0.5)
    text = ns.alt and "Alt" or "Scegli la squadra"
  elseif st.lifted then
    HudColor(0.1, 0.75, 0.1)
    fill, text = 1, "Niente cap"
    tip[#tip + 1] = "Er calendario è finito: se va ar 60."
  else
    local pos = Position(rec)
    local lv = rec and rec.lv or 1
    -- from where the week starts (last week's cap) to this week's cap
    local wk = math.max(1, st.week)
    local from = wk > 1 and st.rows[wk - 1] and st.rows[wk - 1].cap or 1
    if from >= st.cap then from = st.cap - 1 end
    local ps, d = M.PlayerState(lv, st.cap)
    if ps == "over" then
      HudColor(0.85, 0.15, 0.15)
      fill, text, over = 1, "Cap " .. st.cap, "|cffff4040+" .. d .. "|r"
    elseif ps == "at" then
      HudColor(0.1, 0.75, 0.1)
      fill, text = 1, "Cap " .. st.cap
    else
      HudColor(0.0, 0.39, 0.88)
      fill = math.max(0, math.min(1, (pos - from) / math.max(1, st.cap - from)))
      text, over = "Cap " .. st.cap, "-" .. d
    end
    -- above the bar: when the patto starts, or (once you're at this cap) the next one: "Prossimo cap: 22, tra 2 giorni"
    local function short(sec)
      local d, h = math.floor(sec / 86400), math.floor(sec / 3600)
      if d >= 2 then return d .. " giorni" end
      if d == 1 then return "1 giorno" end
      if h >= 2 then return h .. " ore" end
      if h == 1 then return "1 ora" end
      local m = math.max(1, math.floor(sec / 60))
      return m .. (m == 1 and " minuto" or " minuti")
    end
    if not st.started then
      nextText = "Er patto parte tra " .. short(ns.state.settings.start - now)
    elseif ps ~= "behind" and st.nextCap > st.cap then
      nextText = "Prossimo cap: " .. st.nextCap .. ", tra " .. short(st.unlockAt - now)
    end
    tip[1] = "Cap de 'sta settimana: " .. st.cap
    tip[#tip + 1] = ps == "over" and ("Sei sopra de " .. d .. ".") or (ps == "at" and "Sei ar cap." or ("Te " .. (d == 1 and "manca 1 livello." or ("mancano " .. d .. " livelli."))))
    if not st.started then tip[#tip + 1] = "Se parte tra " .. U.Until(ns.state.settings.start - now) .. "." end
    if st.nextCap > st.cap then tip[#tip + 1] = "Prossimo cap " .. st.nextCap .. ", tra " .. U.Until(st.unlockAt - now) .. "." end
  end
  hud.tip = tip
  hud:SetValue(fill)
  hud.text:SetText(text)
  hud.over:SetText(over)
  hud.next:SetText(nextText)
  hud.spark:ClearAllPoints()
  hud.spark:SetPoint("CENTER", hud, "LEFT", fill * 195, 0)
  hud.spark:SetShown(fill > 0 and fill < 1)
  hud:Show()
end

----------------------------------------------------------------------
-- quest warning, above the quest reward window
----------------------------------------------------------------------
local qw
ns.On("QuestWarning", function(text)
  if not text then
    if qw then qw:Hide() end
    return
  end
  if not qw then
    qw = Box(UIParent, 340, 64)
    qw:SetFrameStrata("DIALOG")
    qw:SetBorderColor(1, 0.35, 0.3)
    qw.title = Text(qw, "GameFontNormal", "|cffff4040Occhio ar cap!|r", 320, "CENTER")
    qw.title:SetPoint("TOP", 0, -8)
    qw.text = Text(qw, "GameFontHighlightSmall", "", 320, "CENTER")
    qw.text:SetPoint("TOP", qw.title, "BOTTOM", 0, -4)
  end
  qw:ClearAllPoints()
  if QuestFrame and QuestFrame.IsShown and QuestFrame:IsShown() then
    qw:SetPoint("BOTTOM", QuestFrame, "TOP", 0, 4)
  else
    qw:SetPoint("TOP", UIParent, "TOP", 0, -140)
  end
  qw.text:SetText(text)
  qw:Show()
end)

----------------------------------------------------------------------
-- the capo's announcement: a vanilla dialog until you confirm, then a chat line at each login
----------------------------------------------------------------------
local annFrame
local function BuildAnnouncement()
  annFrame = CreateFrame("Frame", "ErPattoAnnouncement", UIParent)
  annFrame:SetSize(360, 200)
  annFrame:SetPoint("CENTER", 0, 120)
  annFrame:SetFrameStrata("DIALOG")
  annFrame:SetToplevel(true)
  annFrame:EnableMouse(true)
  Chrome(annFrame)
  DialogHeader(annFrame, "Annuncio der capo", 260)
  annFrame.text = Text(annFrame, "GameFontHighlight", "", 310, "CENTER")
  annFrame.text:SetPoint("TOP", 0, -36)
  annFrame.by = Text(annFrame, "GameFontNormalSmall", "", 310, "CENTER")
  annFrame.ok = Btn(annFrame, "Ho letto", 120, function()
    local ann = ns.state and ns.state.settings.ann
    if ann then
      ns.db.annSeen = ns.db.annSeen or {}
      ns.db.annSeen[ns.state.code] = ann.at
    end
    annFrame:Hide()
  end)
  annFrame.ok:SetPoint("BOTTOM", 0, 18)
  annFrame:Hide()
end

-- show the dialog even if already confirmed (preview for the capo, /patto annuncio for everyone)
function UI.ShowAnnouncement(preview)
  local ann = ns.state and P.HasSettings(ns.state) and ns.state.settings.ann
  if not ann then U.Say("nun c'è nessun annuncio.") return end
  if not annFrame then BuildAnnouncement() end
  annFrame.text:SetText(ann.t)
  annFrame.by:ClearAllPoints()
  annFrame.by:SetPoint("TOP", annFrame.text, "BOTTOM", 0, -10)
  annFrame.by:SetText((ann.by and (ann.by .. ", ") or "") .. U.When(ann.at))
  local h = (annFrame.text.GetStringHeight and annFrame.text:GetStringHeight() or 40)
  annFrame:SetHeight(math.max(150, 110 + h))
  annFrame.stone.Refit()
  annFrame:Show()
end

local saidThisSession
function UI.CheckAnnouncement(atLogin)
  local state = ns.state
  local ann = state and P.HasSettings(state) and state.settings.ann
  if not ann then
    if annFrame then annFrame:Hide() end
    return
  end
  ns.db.annSeen = ns.db.annSeen or {}
  if ns.db.annSeen[state.code] == ann.at then
    if atLogin and not saidThisSession then
      saidThisSession = true
      U.Say("annuncio der capo: |cffffffff" .. ann.t .. "|r")
    end
    return
  end
  if not annFrame then BuildAnnouncement() end
  annFrame.text:SetText(ann.t)
  annFrame.by:ClearAllPoints()
  annFrame.by:SetPoint("TOP", annFrame.text, "BOTTOM", 0, -10)
  annFrame.by:SetText((ann.by and (ann.by .. ", ") or "") .. U.When(ann.at))
  local h = (annFrame.text.GetStringHeight and annFrame.text:GetStringHeight() or 40)
  annFrame:SetHeight(math.max(150, 110 + h))
  annFrame.stone.Refit()
  annFrame:Show()
end

-- the squadra: who comes into the patto (or is still "da sceglie") is asked at once, one button per team
local teamFrame, teamAskedFor
local function BuildTeamAsk()
  teamFrame = CreateFrame("Frame", "ErPattoSquadra", UIParent)
  teamFrame:SetSize(380, 200)
  teamFrame:SetPoint("CENTER", 0, 140)
  teamFrame:SetFrameStrata("DIALOG")
  teamFrame:SetToplevel(true)
  teamFrame:EnableMouse(true)
  Chrome(teamFrame)
  DialogHeader(teamFrame, "Scegli la squadra", 230)
  CloseX(teamFrame, function() teamFrame:Hide() end)
  teamFrame.text = Text(teamFrame, "GameFontHighlight", "", 330, "CENTER")
  teamFrame.text:SetPoint("TOP", 0, -36)
  teamFrame.msg = Text(teamFrame, "GameFontGreenSmall", "", 330, "CENTER")
  teamFrame.rows = {}
  teamFrame:Hide()
end

function UI.AskTeam()
  local state = ns.state
  if not (state and not ns.alt and P.HasSettings(state)) then return end
  local s = state.settings
  local teams = s.teams or {}
  if #teams == 0 then return end
  if not teamFrame then BuildTeamAsk() end
  teamFrame.text:SetText("Benvenuto ner patto |cffffd100" .. tostring(s.name or "") .. "|r: in che squadra giochi?")
  teamFrame.msg:SetText("")
  teamFrame.done = false
  local y = -66
  for i, t in ipairs(teams) do
    local r = teamFrame.rows[i]
    if not r then
      r = {}
      r.btn = Btn(teamFrame, "", 150, function()
        if not (ns.state and r.teamId) then return end
        P.ChooseTeam(ns.state, ns.recordGuid, r.teamId)
        T.RefreshSelf("team")
        if PlaySound then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_PLAYER_INVITE) or 880) end
        teamFrame.msg:SetText("Mo' stai co' " .. P.TeamName(ns.state, r.teamId) .. ". La pòi cambià da Squadre.")
        teamFrame.done = true
        for _, x in ipairs(teamFrame.rows) do x.btn:Disable() end
        if C_Timer then C_Timer.After(2, function() teamFrame:Hide() end) else teamFrame:Hide() end
      end)
      r.info = Text(teamFrame, "GameFontHighlightSmall", "", 170, "LEFT")
      teamFrame.rows[i] = r
    end
    r.teamId = t.id
    r.btn:SetText(t.name)
    if r.btn.Enable then r.btn:Enable() end
    r.btn:ClearAllPoints()
    r.btn:SetPoint("TOPLEFT", 26, y)
    r.btn:Show()
    local st = M.Status(s, t.id, U.Now())
    local n = 0
    for _, m in pairs(state.members) do if m.team == t.id then n = n + 1 end end
    local pace = t.pace and t.pace[1] and t.pace[1].hours
    r.info:SetText((pace and (pace .. " ore a settimana") or "") .. (st and (", cap " .. st.cap) or "") ..
      "\n|cff9d9d9d" .. n .. (n == 1 and " membro" or " membri") .. "|r")
    r.info:ClearAllPoints()
    r.info:SetPoint("LEFT", r.btn, "RIGHT", 14, 0)
    r.info:Show()
    y = y - 34
  end
  for i = #teams + 1, #teamFrame.rows do teamFrame.rows[i].btn:Hide() teamFrame.rows[i].info:Hide() end
  teamFrame.msg:ClearAllPoints()
  teamFrame.msg:SetPoint("TOP", 0, y - 6)
  teamFrame:SetHeight(-y + 40)
  teamFrame:Show()
end

-- once per patto and session: when the data of the patto arrive, and at login, if my record has no squadra
function UI.CheckTeam()
  local state = ns.state
  if not (state and not ns.alt and P.HasSettings(state)) then return end
  local rec = ns.MyRecord and ns.MyRecord()
  if not rec or rec.team then
    -- chosen elsewhere (the Squadre page): the question is gone
    if teamFrame and teamFrame:IsShown() and rec and rec.team and not teamFrame.done then teamFrame:Hide() end
    return
  end
  if teamAskedFor == state.code then return end
  teamAskedFor = state.code
  UI.AskTeam()
end

ns.On("Login", function() if C_Timer then C_Timer.After(6, function() UI.CheckAnnouncement(true) end) end end)
ns.On("Login", function() if C_Timer then C_Timer.After(8, UI.CheckTeam) end end)
ns.On("StateChanged", function(_, kind) if kind == "S" then UI.CheckTeam() end end)
ns.On("PattoChanged", function() if C_Timer then C_Timer.After(2, UI.CheckTeam) end end)
ns.On("SelfChanged", function(_, reason) if reason == "team" then UI.CheckTeam() end end)
ns.On("StateChanged", function(_, kind) if kind == "S" then UI.CheckAnnouncement(false) end end)

-- many changes in the same moment (a click that writes my record, pays, updates the book...) make one redraw
local refreshSoon = false
ns.On("Refresh", function()
  if not C_Timer then UI.Refresh() return end
  if refreshSoon then return end
  refreshSoon = true
  C_Timer.After(0.05, function() refreshSoon = false UI.Refresh() end)
end)
ns.On("Login", function()
  UI.RefreshHUD()
  if C_Timer then C_Timer.NewTicker(20, function() UI.Refresh() end) end
end)
