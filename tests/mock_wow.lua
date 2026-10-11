-- tests/mock_wow.lua — just enough of the WoW API to run EditModeGuideLines
-- offline: frames with points, sizes and scripts, Line textures, a UIParent
-- with a screen rect, Blizzard's Edit Mode objects (the manager frame with
-- its grid, the magnetism manager), EllesmereUI's Unlock Mode API (on
-- request), the color picker, Settings and slash commands. Tests drive the
-- game side through the helpers and read back what the addon drew,
-- registered and printed.

local M = {}

-- ---- widgets --------------------------------------------------------------

-- A permissive stub: known methods keep state, everything else is a no-op,
-- so the UI can be built offline to catch nil-call and typo errors (layout
-- itself can only be checked in game).
local Widget = {}
local noop = function() end
local widgetMT = { __index = function(_, k) return Widget[k] or noop end }

local function newWidget(kind, name, parent)
  local w = setmetatable({
    kind = kind, name = name, parent = parent, events = {}, scripts = {}, hooks = {},
    text = "", shown = true, points = {}, width = 0, height = 0, children = {},
  }, widgetMT)
  if type(parent) == "table" and rawget(parent, "children") then
    parent.children[#parent.children + 1] = w
  end
  return w
end

function Widget:SetScript(name, fn)
  self.scripts[name] = fn
  if name == "OnEvent" then self.handler = fn end
end
function Widget:HookScript(name, fn)
  local h = self.hooks[name] or {}
  h[#h + 1] = fn
  self.hooks[name] = h
end
function Widget:GetScript(name) return self.scripts[name] end
function Widget:Run(name, ...)
  local fn = self.scripts[name]
  if fn then fn(self, ...) end
  for _, h in ipairs(self.hooks[name] or {}) do h(self, ...) end
end
function Widget:RegisterEvent(e) self.events[e] = true end
function Widget:UnregisterEvent(e) self.events[e] = nil end
function Widget:Fire(event, ...)
  if self.events[event] and self.handler then self.handler(self, event, ...) end
end
function Widget:Click(...) self:Run("OnClick", ...) end
function Widget:Enter() self:Run("OnEnterPressed") end
function Widget:SetText(t)
  self.text = t == nil and "" or tostring(t)
  self:Run("OnTextChanged", false)
end
function Widget:GetText() return self.text end
function Widget:SetChecked(v) self.checked = v and true or false end
function Widget:GetChecked() return self.checked end
function Widget:Show()
  if not self.shown then
    self.shown = true
    self:Run("OnShow")
  end
end
function Widget:Hide()
  if self.shown then
    self.shown = false
    self:Run("OnHide")
  end
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.shown end
function Widget:IsVisible() return self.shown end
function Widget:HasFocus() return self.focused == true end
function Widget:SetFocus() self.focused = true end
function Widget:ClearFocus()
  self.focused = false
  self:Run("OnEditFocusLost")
end
function Widget:SetSize(w, h) self.width, self.height = w, h end
function Widget:SetWidth(w) self.width = w end
function Widget:SetHeight(h) self.height = h end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:SetPoint(point, a, b, c, d) self.points[#self.points + 1] = { point, a, b, c, d } end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetNumPoints() return #self.points end
function Widget:GetPoint(i) local p = self.points[i]; if p then return p[1], p[2], p[3], p[4], p[5] end end
function Widget:SetAllPoints(rel) self.allPoints = rel end
function Widget:SetFrameStrata(s) self.strata = s end
function Widget:GetFrameStrata() return self.strata end
function Widget:GetParent() return self.parent end
function Widget:GetName() return self.name end
function Widget:SetBackdropColor(r, g, b, a) self.backdropColor = { r = r, g = g, b = b, a = a } end
function Widget:SetColorTexture(r, g, b, a) self.color = { r = r, g = g, b = b, a = a } end
function Widget:SetThickness(t) self.thickness = t end
function Widget:SetStartPoint(point, rel, x, y) self.startPoint = { point = point, rel = rel, x = x, y = y } end
function Widget:SetEndPoint(point, rel, x, y) self.endPoint = { point = point, rel = rel, x = x, y = y } end
function Widget:CreateFontString() return newWidget("FontString", nil, self) end
function Widget:CreateTexture() return newWidget("Texture", nil, self) end
function Widget:CreateLine()
  local line = newWidget("Line", nil, self)
  M.lines[#M.lines + 1] = line
  return line
end
function Widget:GetStringHeight() return 12 end
-- Only the one layout the addon's strips use: CENTER at an offset from
-- UIParent's bottom-left corner.
function Widget:GetCenter()
  local p = self.points[1]
  if p and p[1] == "CENTER" and p[2] == _G.UIParent and p[3] == "BOTTOMLEFT" then return p[4], p[5] end
end
function Widget:GetEffectiveScale() return 1 end

function _G.CreateFrame(kind, name, parent, template)
  local w = newWidget(kind, name, parent)
  w.template = template
  M.widgets[#M.widgets + 1] = w
  if name then _G[name] = w end
  return w
end

-- ---- screen and UIParent ----------------------------------------------------

M.screen = { width = 1000, height = 768 }   -- physical pixels
M.uiScale = 1                                -- UIParent's effective scale

-- Screen pixels per UIParent unit (the screen is 768 units tall at scale 1).
function M.ppu() return M.uiScale * M.screen.height / 768 end

local UIParent = newWidget("Frame", "UIParent")
_G.UIParent = UIParent
function UIParent:GetRect() return 0, 0, M.screen.width / M.ppu(), M.screen.height / M.ppu() end
function UIParent:GetWidth() return M.screen.width / M.ppu() end
function UIParent:GetHeight() return M.screen.height / M.ppu() end
function UIParent:GetCenter() return self:GetWidth() / 2, self:GetHeight() / 2 end
function UIParent:GetEffectiveScale() return M.uiScale end

function _G.GetPhysicalScreenSize() return M.screen.width, M.screen.height end

-- Called by the game when UIParent is resized; the magnetism manager hooks
-- it, and so does the addon (hooksecurefunc wraps the global in place), so
-- reset() puts the pristine function back or every test's hooks would stack.
local function updateUIParentPosition()
  if _G.EditModeMagnetismManager then _G.EditModeMagnetismManager:UpdateTopLevelParentPoints() end
end
_G.UpdateUIParentPosition = updateUIParentPosition

-- Change the screen as the game would, firing the same notifications.
function M.resize(width, height, uiScale)
  M.screen = { width = width, height = height }
  M.uiScale = uiScale or M.uiScale
  _G.UpdateUIParentPosition()
end

-- ---- Blizzard's Edit Mode -------------------------------------------------

function M.buildEditMode()
  local manager = newWidget("Frame", "EditModeManagerFrame")
  manager.shown = false
  manager.Grid = newWidget("Frame", nil, manager)
  manager.Grid.shown = false
  function manager:CanEnterEditMode() return not M.cannotEnterEditMode end
  function manager:IsEditModeActive() return self.shown end
  _G.EditModeManagerFrame = manager

  -- The parts of EditModeMagnetismManager the addon relies on, with the same
  -- table shapes as Blizzard's.
  local MM = { magneticFrames = {}, magnetismRange = 8 }
  function MM:UpdateTopLevelParentPoints()
    self.topLevelParentCenterX, self.topLevelParentCenterY = UIParent:GetCenter()
    local left, bottom, width, height = UIParent:GetRect()
    self.topLevelParentWidth, self.topLevelParentHeight = width, height
    self.topLevelParentLeft, self.topLevelParentRight = left, left + width
    self.topLevelParentBottom, self.topLevelParentTop = bottom, bottom + height
  end
  function MM:RegisterGrid() self.magneticGridLines = { horizontal = {}, vertical = {} } end
  function MM:UnregisterGrid() self.magneticGridLines = nil end
  function MM:RegisterGridLine(line, verticalLine, centerOffset)
    if verticalLine then
      self.magneticGridLines.vertical[line] = self.topLevelParentCenterX + centerOffset
    else
      self.magneticGridLines.horizontal[line] = self.topLevelParentCenterY + centerOffset
    end
  end
  MM:UpdateTopLevelParentPoints()
  _G.EditModeMagnetismManager = MM

  M.manager, M.magnetism = manager, MM
  M.gridLines = { { isGridLine = true }, { isGridLine = true } }
end

function M.removeEditMode()
  _G.EditModeManagerFrame = nil
  _G.EditModeMagnetismManager = nil
  M.manager, M.magnetism = nil, nil
end

function M.enterEditMode() M.manager:Show() end
function M.exitEditMode() M.manager:Hide() end

-- Blizzard's grid: showing it registers the grid and its lines (here just
-- the two center lines), hiding it unregisters the grid.
function M.showGrid()
  M.manager.Grid:Show()
  M.magnetism:RegisterGrid()
  M.magnetism:RegisterGridLine(M.gridLines[1], true, 0)
  M.magnetism:RegisterGridLine(M.gridLines[2], false, 0)
end
function M.hideGrid()
  M.manager.Grid:Hide()
  M.magnetism:UnregisterGrid()
end

-- The coordinates registered for one orientation, sorted, with Blizzard's
-- own grid lines left out.
function M.snapLines(orientation)
  local lines = M.magnetism.magneticGridLines
  local out = {}
  if lines and lines[orientation] then
    for key, coord in pairs(lines[orientation]) do
      if not key.isGridLine then out[#out + 1] = coord end
    end
  end
  table.sort(out)
  return out
end

-- ---- EllesmereUI ----------------------------------------------------------

-- The public Unlock Mode API from the header of EllesmereUI's
-- EUI_UnlockMode.lua (listeners, element registration with the same field
-- aliasing) and its EllesmereUI.MakeUnlockElement factory (left out with
-- opts.noFactory, like an older build). EllesmereUI pcalls listeners; the
-- mock calls them directly so test failures show.
M.ellesmereBannerHeight = 60   -- the hover zone's height, UIParent units

local FIELD_ALIASES = {
  savePos = "savePosition", loadPos = "loadPosition", clearPos = "clearPosition", applyPos = "applyPosition",
}

function M.buildEllesmere(opts)
  opts = opts or {}
  local E = {
    _unlockModeListeners = {}, _unlockModeSessionActive = false,
    _unlockRegisteredElements = {}, _unlockRegistrationDirty = false,
  }
  function E:RegisterUnlockModeListener(owner, listener)
    self._unlockModeListeners[owner] = listener
    if self._unlockModeSessionActive then listener(true) end
  end
  function E:UnregisterUnlockModeListener(owner) self._unlockModeListeners[owner] = nil end
  function E:IsUnlockModeActive() return self._unlockModeSessionActive == true end
  function E:_NotifyUnlockModeListeners(active, closeAction)
    self._unlockModeSessionActive = active == true
    for _, listener in pairs(self._unlockModeListeners) do listener(self._unlockModeSessionActive, closeAction) end
  end
  function E:RegisterUnlockElements(elements, folder)
    for _, elem in ipairs(elements) do
      for short, long in pairs(FIELD_ALIASES) do
        if elem[short] and not elem[long] then elem[long] = elem[short] end
      end
      if folder and not elem.folder then elem.folder = folder end
      self._unlockRegisteredElements[elem.key] = elem
    end
    self._unlockRegistrationDirty = true
    M.unlockRegistrations = M.unlockRegistrations + 1
    M.unlockHiddenOnRegister = {}
    for key, elem in pairs(self._unlockRegisteredElements) do
      M.unlockHiddenOnRegister[key] = elem.isHidden and elem.isHidden(key) or false
    end
  end
  function E:UnregisterUnlockElement(key) self._unlockRegisteredElements[key] = nil end
  if not opts.noFactory then
    -- The whitelist, as EllesmereUI.lua has it.
    function E.MakeUnlockElement(o)
      return {
        key = o.key, label = o.label, group = o.group, order = o.order,
        getFrame = o.getFrame, getSize = o.getSize,
        savePosition = o.savePos, loadPosition = o.loadPos, clearPosition = o.clearPos, applyPosition = o.applyPos,
        isHidden = o.isHidden, isAnchored = o.isAnchored, keepMoverWhenAnchored = o.keepMoverWhenAnchored,
        noResize = o.noResize, noAnchorTo = o.noAnchorTo, noAnchorTarget = o.noAnchorTarget,
        noSizeMatchTarget = o.noSizeMatchTarget,
      }
    end
  end
  local zone = newWidget("Frame", nil, UIParent)
  zone.shown = false
  function zone:GetBottom() return UIParent:GetHeight() - M.ellesmereBannerHeight end
  function E:GetUnlockModeTopBarAnchor() return zone end
  function E:OpenUnlockMode()
    if _G.InCombatLockdown() then return end
    M.enterUnlock()
  end
  _G.EllesmereUI = E
  M.ellesmere = E
  return E
end

function M.removeEllesmere()
  _G.EllesmereUI = nil
  M.ellesmere = nil
end

function M.enterUnlock() M.ellesmere:_NotifyUnlockModeListeners(true) end
function M.exitUnlock(action) M.ellesmere:_NotifyUnlockModeListeners(false, action or "exit") end

-- The movers EllesmereUI would build for the registered elements, with the
-- rect its Sync gives a "tiny anchor" element (a frame under 10 units wide):
-- centered on the element frame's center, sized by getSize. Keyed by element
-- key: { label, group, order, hidden, left, right, top, bottom, elem }.
function M.unlockMovers()
  local out = {}
  for key, elem in pairs(M.ellesmere._unlockRegisteredElements) do
    local f = elem.getFrame(key)
    local cx, cy = f:GetCenter()
    local w, h, yOff = elem.getSize(key)
    cy = cy + (yOff or 0)
    out[key] = {
      label = elem.label, group = elem.group, order = elem.order, elem = elem,
      hidden = elem.isHidden and elem.isHidden(key) or false,
      left = cx - w / 2, right = cx + w / 2, top = cy + h / 2, bottom = cy - h / 2,
    }
  end
  return out
end

-- ---- color picker ---------------------------------------------------------

function M.newColorPicker()
  local p = newWidget("Frame", "ColorPickerFrame")
  p.shown = false
  function p:SetupColorPickerAndShow(info)
    self.info = info
    M.colorPicker = info
    M.picked = { r = info.r, g = info.g, b = info.b, a = info.opacity }
    self:Show()
  end
  function p:GetColorRGB() return M.picked.r, M.picked.g, M.picked.b end
  function p:GetColorAlpha() return M.picked.a end
  return p
end

-- The user picks a color in the open picker.
function M.pickColor(r, g, b, a)
  M.picked = { r = r, g = g, b = b, a = a or M.picked.a }
  M.colorPicker.swatchFunc()
  if a then M.colorPicker.opacityFunc() end
end

function M.cancelColor()
  local i = M.colorPicker
  i.cancelFunc({ r = i.r, g = i.g, b = i.b, a = i.opacity })
  _G.ColorPickerFrame:Hide()
end

-- ---- other globals --------------------------------------------------------

function _G.wipe(t) for k in pairs(t) do t[k] = nil end return t end

-- Really wraps the function, so hooked Blizzard calls reach the addon.
function _G.hooksecurefunc(a, b, c)
  local tbl, name, fn = _G, a, b
  if type(a) == "table" then tbl, name, fn = a, b, c end
  local orig = tbl[name]
  assert(type(orig) == "function", "hooksecurefunc: no function named " .. tostring(name))
  tbl[name] = function(...)
    local results = { orig(...) }
    fn(...)
    return unpack(results)
  end
  M.hooks[name] = fn
end

function _G.IsLoggedIn() return M.loggedIn end
function _G.InCombatLockdown() return M.inCombat end
function _G.ShowUIPanel(frame) frame:Show() end
function _G.GetTime() return 0 end

_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.printed[#M.printed + 1] = msg end }
_G.GameTooltip = newWidget("GameTooltip")

-- Settings API (canvas categories).
_G.Settings = {}
function _G.Settings.RegisterCanvasLayoutCategory(frame, name)
  local cat = { frame = frame, name = name, GetID = function() return name end }
  M.categories[name] = cat
  return cat
end
function _G.Settings.RegisterAddOnCategory() end
function _G.Settings.OpenToCategory(id) M.opened = id end

-- ---- reset ----------------------------------------------------------------

function M.reset()
  M.screen = { width = 1000, height = 768 }
  M.uiScale = 1
  M.printed, M.widgets, M.lines, M.categories, M.hooks = {}, {}, {}, {}, {}
  M.opened, M.colorPicker = nil, nil
  M.picked = { r = 0, g = 0, b = 0, a = 1 }
  M.inCombat, M.loggedIn, M.cannotEnterEditMode = false, false, false
  M.unlockRegistrations, M.unlockHiddenOnRegister = 0, {}
  _G.UpdateUIParentPosition = updateUIParentPosition
  M.buildEditMode()
  M.removeEllesmere()
  _G.ColorPickerFrame = M.newColorPicker()
  _G.SlashCmdList = {}
end
M.reset()

return M
