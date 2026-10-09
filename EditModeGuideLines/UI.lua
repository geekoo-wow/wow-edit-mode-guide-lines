-- UI.lua — the guide panel that opens next to the Edit Mode window, and the
-- same editor in Options > AddOns > EditModeGuideLines. This file only draws
-- widgets; every change goes through ns.Config, which redraws the lines and
-- calls ns.OnConfigChanged so whatever is showing gets refreshed.

local _, ns = ...
ns = ns or {}

local UI = {}
ns.UI = UI

local Config, Guides = ns.Config, ns.Guides

local PAD = 14
local ROW_H = 26
local EDITOR_W = 400
local EDITOR_H = 392
local LIST_H = 180

local COLOR_ERR = "|cffff5555"
local COLOR_DIM = "|cff999999"

-- ---------------------------------------------------------------------------
-- Widget helpers
-- ---------------------------------------------------------------------------

local function Label(parent, text, font)
  local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
  fs:SetJustifyH("LEFT")
  fs:SetText(text or "")
  return fs
end

local function Button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 100, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function Tooltip(frame, title, body)
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    if body then GameTooltip:AddLine(body, nil, nil, nil, true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Check(parent, label, tip, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(26, 26)
  cb.label = Label(parent, label)
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  if tip then
    if label ~= "" then Tooltip(cb, label, tip) else Tooltip(cb, tip) end
  end
  function cb:Refresh() self:SetChecked(get() and true or false) end
  return cb
end

-- A one-line text box; onEnter(editBox, text) runs when Enter is pressed,
-- after which the box loses focus (so an OnEditFocusLost script can reset it).
local function Input(parent, width, onEnter)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetSize(width, 20)
  eb:SetAutoFocus(false)
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  eb:SetScript("OnEnterPressed", function(self)
    if onEnter then onEnter(self, self:GetText()) end
    self:ClearFocus()
  end)
  return eb
end

local BACKDROP = {
  bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function Box(parent, width, height)
  local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  box:SetSize(width, height)
  box:SetBackdrop(BACKDROP)
  box:SetBackdropColor(0, 0, 0, 0.45)
  box:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
  return box
end

-- Scrolling area inside a Box; returns box, scrollFrame, child.
local function ScrollBox(parent, width, height)
  local box = Box(parent, width, height)
  local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -28, 6)
  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(width - 34, 1)
  sf:SetScrollChild(child)
  return box, sf, child
end

-- Opens the game's color picker on `color`. onChange(r, g, b, a) runs as the
-- user picks, and once more with the original color if they cancel.
local function openColorPicker(color, onChange)
  local picker = _G.ColorPickerFrame
  if not (picker and picker.SetupColorPickerAndShow) then
    ns.Print("the color picker isn't available; use /emg color <n> <name or #hex>")
    return false
  end
  local orig = { r = color.r, g = color.g, b = color.b, a = color.a }
  local function apply()
    local r, g, b = picker:GetColorRGB()
    local a = picker.GetColorAlpha and picker:GetColorAlpha() or orig.a
    onChange(r, g, b, a)
  end
  picker:SetupColorPickerAndShow({
    r = color.r, g = color.g, b = color.b,
    opacity = color.a, hasOpacity = true,
    swatchFunc = apply,
    opacityFunc = apply,
    cancelFunc = function() onChange(orig.r, orig.g, orig.b, orig.a) end,
  })
  return true
end

-- A colored square that opens the color picker. get() returns the color,
-- set(color) stores a new one.
local function Swatch(parent, get, set)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(20, 20)
  b.isSwatch = true
  local border = b:CreateTexture(nil, "BACKGROUND")
  border:SetAllPoints(b)
  border:SetColorTexture(0.6, 0.6, 0.6, 1)
  b.fill = b:CreateTexture(nil, "ARTWORK")
  b.fill:SetPoint("TOPLEFT", 1, -1)
  b.fill:SetPoint("BOTTOMRIGHT", -1, 1)
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetScript("OnClick", function()
    openColorPicker(get(), function(r, g, bl, a) set({ r = r, g = g, b = bl, a = a }) end)
  end)
  function b:Refresh()
    local c = get()
    self.fill:SetColorTexture(c.r, c.g, c.b, c.a)
  end
  Tooltip(b, "Color", "Click to pick a color.")
  return b
end

-- ---------------------------------------------------------------------------
-- The editor: settings, the "new guide" row and the guide list. Built once
-- for the Edit Mode panel and once for the settings category.
-- ---------------------------------------------------------------------------

local refreshables = {}

local function BuildEditor(parent, width)
  local ed = CreateFrame("Frame", nil, parent)
  ed:SetSize(width, EDITOR_H)
  ed.new = { orientation = "vertical", color = Guides.ParseColor(Guides.DEFAULT_COLOR) }
  local col2 = math.floor(width / 2)

  -- Settings
  local enabled = Check(ed, "Enabled", "Draw the guides and let frames snap to them.",
    function() return Config.GetSetting("enabled") end,
    function(v) Config.SetSetting("enabled", v) end)
  enabled:SetPoint("TOPLEFT", 0, 0)
  local outside = Check(ed, "Show outside Edit Mode", "Keep the guides on screen after Edit Mode is closed.",
    function() return Config.GetSetting("showOutsideEditMode") end,
    function(v) Config.SetSetting("showOutsideEditMode", v) end)
  outside:SetPoint("TOPLEFT", col2, 0)
  local above = Check(ed, "Draw above frames", "Draw the guides over the UI instead of behind it.",
    function() return Config.GetSetting("aboveFrames") end,
    function(v) Config.SetSetting("aboveFrames", v) end)
  above:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -2)
  local thickLabel = Label(ed, "Thickness (px)")
  thickLabel:SetPoint("LEFT", above, "LEFT", col2 + 6, 0)
  local thick = Input(ed, 36, function(_, text)
    local err = Config.SetThickness(text)
    ed:ShowError(err)
  end)
  thick:SetPoint("LEFT", thickLabel, "RIGHT", 12, 0)
  thick:SetScript("OnEditFocusLost", function(self) self:SetText(tostring(Config.GetSetting("thickness"))) end)
  Tooltip(thick, "Thickness", string.format("Line thickness in screen pixels, %d to %d.",
    Guides.MIN_THICKNESS, Guides.MAX_THICKNESS))
  ed.checks = { enabled = enabled, showOutsideEditMode = outside, aboveFrames = above }
  ed.thicknessInput = thick

  -- New guide
  local newHeader = Label(ed, "New guide", "GameFontNormal")
  newHeader:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -10)
  local orient = Button(ed, Guides.LABELS.vertical, 90, function(self)
    ed.new.orientation = Guides.Other(ed.new.orientation)
    self:SetText(Guides.LABELS[ed.new.orientation])
  end)
  orient:SetPoint("TOPLEFT", newHeader, "BOTTOMLEFT", 0, -6)
  Tooltip(orient, "Orientation", "Click to switch between vertical and horizontal.")
  local percent = Input(ed, 46, function() ed:Add() end)
  percent:SetPoint("LEFT", orient, "RIGHT", 10, 0)
  Tooltip(percent, "Width of the band",
    "The band is centered: 50 draws lines at 25% and 75% of the screen, 0 one line through the middle.")
  local pct = Label(ed, "%")
  pct:SetPoint("LEFT", percent, "RIGHT", 2, 0)
  local swatch = Swatch(ed, function() return ed.new.color end, function(c)
    ed.new.color = c
    ed:Refresh()
  end)
  swatch:SetPoint("LEFT", pct, "RIGHT", 10, 0)
  local add = Button(ed, "Add", 60, function() ed:Add() end)
  add:SetPoint("LEFT", swatch, "RIGHT", 10, 0)
  local err = Label(ed, "", "GameFontHighlightSmall")
  err:SetPoint("TOPLEFT", orient, "BOTTOMLEFT", 0, -4)
  err:SetWidth(width)
  err:SetHeight(12)
  ed.orientButton, ed.percentInput, ed.newSwatch, ed.addButton, ed.errorLabel = orient, percent, swatch, add, err

  function ed:ShowError(msg)
    err:SetText(msg and (COLOR_ERR .. msg .. "|r") or "")
  end

  function ed:Add()
    local _, e = Config.Add(ed.new.orientation, percent:GetText(), ed.new.color)
    ed:ShowError(e)
    if not e then percent:SetText("") end
  end

  -- Guide list
  local listHeader = Label(ed, "Guides", "GameFontNormal")
  listHeader:SetPoint("TOPLEFT", err, "BOTTOMLEFT", 0, -6)
  local box, _, child = ScrollBox(ed, width, LIST_H)
  box:SetPoint("TOPLEFT", listHeader, "BOTTOMLEFT", 0, -4)
  local empty = Label(child, COLOR_DIM .. "No guides yet. Add one above, or with /emg add v 50 green.|r")
  empty:SetPoint("TOPLEFT", 4, -6)
  ed.rows = {}

  local function row(i)
    local r = ed.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, child)
    r:SetSize(width - 40, ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.swatch = Swatch(r,
      function() return Config.Get(r.index).color end,
      function(c) ed:ShowError(Config.SetColor(r.index, c)) end)
    r.swatch:SetPoint("LEFT", 2, 0)
    r.swatch.guideIndex = i
    r.orient = Button(r, "", 90, function() ed:ShowError(Config.Flip(r.index)) end)
    r.orient:SetPoint("LEFT", r.swatch, "RIGHT", 8, 0)
    Tooltip(r.orient, "Orientation", "Click to switch between vertical and horizontal.")
    r.percent = Input(r, 46, function(_, text)
      local e = Config.SetPercent(r.index, text)
      ed:ShowError(e)
      if e then ed:Refresh() end
    end)
    r.percent:SetPoint("LEFT", r.orient, "RIGHT", 10, 0)
    r.percent:SetScript("OnEditFocusLost", function(self)
      local g = Config.Get(r.index)
      if g then self:SetText(Guides.FormatPercent(g.percent)) end
    end)
    r.pct = Label(r, "%")
    r.pct:SetPoint("LEFT", r.percent, "RIGHT", 2, 0)
    r.enabled = Check(r, "", "Shown: untick to hide this guide without deleting it.",
      function() local g = Config.Get(r.index); return g and g.enabled end,
      function(v) ed:ShowError(Config.SetEnabled(r.index, v)) end)
    r.enabled:SetPoint("LEFT", r.pct, "RIGHT", 8, 0)
    r.delete = Button(r, "X", 24, function() Config.Remove(r.index) end)
    r.delete:SetPoint("LEFT", r.enabled, "RIGHT", 6, 0)
    Tooltip(r.delete, "Delete", "Remove this guide.")
    ed.rows[i] = r
    return r
  end

  local help = Label(ed, COLOR_DIM .. "A guide is centered: 50% draws two lines, at 25% and 75% of the screen; "
    .. "0% draws one line through the middle. Frames snap to the lines while Edit Mode's "
    .. "Snap to Frames is on.|r", "GameFontHighlightSmall")
  help:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -8)
  help:SetWidth(width)

  function ed:Refresh()
    for _, cb in pairs(ed.checks) do cb:Refresh() end
    if not thick:HasFocus() then thick:SetText(tostring(Config.GetSetting("thickness"))) end
    orient:SetText(Guides.LABELS[ed.new.orientation])
    swatch:Refresh()
    local guides = Config.List()
    empty:SetShown(#guides == 0)
    for i, g in ipairs(guides) do
      local r = row(i)
      r.index = i
      r.swatch:Refresh()
      r.orient:SetText(Guides.LABELS[g.orientation])
      if not r.percent:HasFocus() then r.percent:SetText(Guides.FormatPercent(g.percent)) end
      r.enabled:Refresh()
      r:Show()
    end
    for i = #guides + 1, #ed.rows do ed.rows[i]:Hide() end
    child:SetHeight(math.max(1, #guides * ROW_H))
  end

  refreshables[#refreshables + 1] = ed
  return ed
end

-- ---------------------------------------------------------------------------
-- The Edit Mode panel
-- ---------------------------------------------------------------------------

local PANEL_W = EDITOR_W + 2 * PAD
local PANEL_H = EDITOR_H + 2 * PAD + 34

function UI.AnchorPanel()
  local panel = UI.panel
  if not panel then return end
  panel:ClearAllPoints()
  local manager = _G.EditModeManagerFrame
  if manager then
    panel:SetPoint("TOPLEFT", manager, "TOPRIGHT", 12, 0)
  else
    panel:SetPoint("CENTER")
  end
end

local function BuildPanel()
  local f = CreateFrame("Frame", "EditModeGuideLinesPanel", UIParent, "BackdropTemplate")
  f:Hide()
  f:SetSize(PANEL_W, PANEL_H)
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(0.06, 0.06, 0.08, 0.95)
  f:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

  local title = Label(f, "Guide lines", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", PAD, -PAD)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -2, -2)

  local ed = BuildEditor(f, EDITOR_W)
  ed:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
  f.editor = ed
  f:SetScript("OnShow", function() ed:Refresh() end)
  return f
end

function UI.ShowPanel()
  if not UI.panel then return false end
  UI.AnchorPanel()
  UI.panel:Show()
  return true
end

function UI.HidePanel()
  if UI.panel then UI.panel:Hide() end
end

-- ---------------------------------------------------------------------------
-- Options > AddOns > EditModeGuideLines
-- ---------------------------------------------------------------------------

local function BuildSettings()
  local f = CreateFrame("Frame")
  f:Hide()
  local t = Label(f, "EditModeGuideLines", "GameFontNormalLarge")
  t:SetPoint("TOPLEFT", PAD, -PAD)
  local s = Label(f, "Guide lines for Edit Mode: centered vertical or horizontal pairs, at any percentage "
    .. "of the screen and in any color, that frames snap to.", "GameFontHighlightSmall")
  s:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -6)
  s:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)

  local open = Button(f, "Open Edit Mode", 140, function() UI.OpenEditMode() end)
  open:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -12)
  f.openButton = open
  local showPanel = Check(f, "Show the guide panel in Edit Mode",
    "Open the guide panel next to the Edit Mode window whenever Edit Mode opens.",
    function() return Config.GetSetting("showPanel") end,
    function(v) Config.SetSetting("showPanel", v) end)
  showPanel:SetPoint("LEFT", open, "RIGHT", 16, 0)
  f.showPanelCheck = showPanel
  refreshables[#refreshables + 1] = showPanel

  local ed = BuildEditor(f, EDITOR_W)
  ed:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -14)
  f.editor = ed

  function f:Refresh()
    showPanel:Refresh()
    ed:Refresh()
  end
  -- Settings canvas callbacks; changes are applied immediately, so no-ops.
  f.OnCommit = function() end
  f.OnDefault = function() end
  f.OnRefresh = function() f:Refresh() end
  f:SetScript("OnShow", function() f:Refresh() end)
  return f
end

-- ---------------------------------------------------------------------------

function UI.Refresh()
  for _, w in ipairs(refreshables) do
    if w:IsVisible() then w:Refresh() end
  end
end

-- The panel while Edit Mode is open, the settings category otherwise.
function UI.Open()
  local manager = _G.EditModeManagerFrame
  if UI.panel and manager and manager:IsShown() then return UI.ShowPanel() end
  if UI.category and _G.Settings and _G.Settings.OpenToCategory then
    _G.Settings.OpenToCategory(UI.category:GetID())
    return true
  end
  return false
end

function UI.OpenEditMode()
  local manager = _G.EditModeManagerFrame
  if not manager then
    ns.Print("Edit Mode isn't available on this client")
    return false
  end
  if _G.InCombatLockdown and _G.InCombatLockdown() then
    ns.Print("Edit Mode can't be opened in combat")
    return false
  end
  if manager.CanEnterEditMode and not manager:CanEnterEditMode() then
    ns.Print("Edit Mode can't be opened right now")
    return false
  end
  if _G.ShowUIPanel then _G.ShowUIPanel(manager) else manager:Show() end
  return true
end

function UI.Init()
  if UI.initialized then return end
  UI.initialized = true
  ns.OnConfigChanged = UI.Refresh

  local manager = _G.EditModeManagerFrame
  if manager then
    UI.panel = BuildPanel()
    manager:HookScript("OnShow", function()
      if Config.GetSetting("showPanel") then UI.ShowPanel() end
    end)
    manager:HookScript("OnHide", function() UI.HidePanel() end)
    if manager:IsShown() and Config.GetSetting("showPanel") then UI.ShowPanel() end
  end

  local S = _G.Settings
  if S and S.RegisterCanvasLayoutCategory then
    UI.settings = BuildSettings()
    UI.category = S.RegisterCanvasLayoutCategory(UI.settings, "EditModeGuideLines")
    if S.RegisterAddOnCategory then S.RegisterAddOnCategory(UI.category) end
  end
end
