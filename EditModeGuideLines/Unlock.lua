-- Unlock.lua — the same guides, and snapping to them, in EllesmereUI's
-- Unlock Mode.
--
-- EllesmereUI (github.com/EllesmereGaming/EllesmereUI) replaces Edit Mode
-- with its own layout editor, Unlock Mode: every element gets a draggable
-- mover, and while a mover is dragged its edges and center snap to the
-- edges and center of the closest other mover (EUI_UnlockMode_Tools.lua,
-- SnapPosition). This file is the only one that talks to EllesmereUI, and
-- only through the public API in the header of its EUI_UnlockMode.lua and
-- the element factory documented above EllesmereUI.MakeUnlockElement:
--   EllesmereUI:RegisterUnlockModeListener(owner, fn)   fn(active, closeAction)
--   EllesmereUI:IsUnlockModeActive()
--   EllesmereUI:GetUnlockModeTopBarAnchor()             the banner's hover zone
--   EllesmereUI:OpenUnlockMode()
--   EllesmereUI:RegisterUnlockElements(list, folder)    elements get movers
--
-- The lines show and hide with the session through the listener (it fires at
-- once when a session is already open), and the panel docks under the banner.
--
-- Snapping: each drawn line is registered as an unlock element of its own,
-- the way EllesmereUI's modules register their frames. Its frame is a 1x1
-- "strip" sitting on the line, a quarter screen outside the screen along it;
-- EllesmereUI sizes the mover from getSize (a frame under 10 units counts as
-- a tiny anchor and takes getSize's size, centered on the frame), so the
-- mover becomes a hair-thin strip three and a half screens long: its left
-- edge is on the line and its center and right edge within a ten-thousandth
-- of a unit of it, it overlaps every element vertically (so it competes for
-- "closest element" by horizontal distance alone), and its own top, center
-- and bottom are off screen, where nothing can snap to them. Horizontal
-- lines are the same rotated. The element is position-locked
-- (keepMoverWhenAnchored with isAnchored true), can't be resized, anchored
-- to, or size-matched, saves no position, and its sub-pixel mover has no
-- label or hit area to speak of.
-- Lines keep their element registered but hidden when they go away, since
-- EllesmereUI leaves a mover in place on unregistration; registering again
-- with isHidden() true hides it, and with isHidden() false re-syncs it.

local _, ns = ...
ns = ns or {}

local Unlock = {}
ns.Unlock = Unlock

local OWNER = "EditModeGuideLines"
local GROUP = "Guide Lines"   -- the group the lines are listed under in menus
local ORDER = 900             -- after EllesmereUI's own groups
local HAIR = 0.0001           -- the mover's thin side, UIParent units
local SPAN = 3.5              -- the mover's long side, in screens

local strips = {}             -- key -> { key, frame, spec, live, w, h }
local signature               -- what was last registered, to skip no-op calls
local hideAll = false         -- while true every strip reports hidden

local function eui()
  local e = _G.EllesmereUI
  if type(e) == "table" then return e end
end

-- EllesmereUI with an Unlock Mode is loaded.
function Unlock.Available()
  local e = eui()
  return e ~= nil and type(e.RegisterUnlockModeListener) == "function"
end

-- ...and it takes elements, so the guides can be snap targets.
function Unlock.CanSnap()
  local e = eui()
  return e ~= nil and type(e.RegisterUnlockElements) == "function"
end

function Unlock.IsActive()
  local e = eui()
  if not (e and type(e.IsUnlockModeActive) == "function") then return false end
  local ok, active = pcall(e.IsUnlockModeActive, e)
  return ok and active == true
end

-- The strips by key (for the tests).
function Unlock.Strips() return strips end

local function noop() end

-- The element table for a strip, through EllesmereUI's factory when it has
-- one (it whitelists and renames fields), else with the names the registry
-- reads.
local function makeSpec(e, s)
  local opts = {
    key = s.key, label = s.key, group = GROUP, order = ORDER,
    getFrame = function() return s.frame end,
    getSize = function() return s.w, s.h end,
    savePos = noop,
    isHidden = function() return hideAll or not s.live end,
    -- Position-locked: EllesmereUI never drags, nudges or links it.
    isAnchored = function() return true end,
    keepMoverWhenAnchored = true,
    noResize = true, noAnchorTo = true, noAnchorTarget = true, noSizeMatchTarget = true,
  }
  if type(e.MakeUnlockElement) == "function" then return e.MakeUnlockElement(opts) end
  opts.savePosition, opts.savePos = opts.savePos, nil
  return opts
end

local function newStrip(e, key)
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(1, 1)
  local s = { key = key, frame = f, live = false, w = HAIR, h = HAIR }
  s.spec = makeSpec(e, s)
  strips[key] = s
  return s
end

-- One key per line position, in screen pixels, so a line that moves (a new
-- percentage, another resolution) is a new element and the old one hides.
local function keyFor(t, origin, ppu)
  local px = math.floor((t.coord - origin) * ppu + 0.5)
  return string.format("EMG_%s_%d", t.orientation == "vertical" and "V" or "H", px)
end

local function register(e, list)
  if Unlock.active then
    -- EllesmereUI re-syncs a mover it re-shows, not one that stayed shown:
    -- hide them all first so the live ones are placed afresh.
    hideAll = true
    e:RegisterUnlockElements(list, ns.name)
    hideAll = false
  end
  e:RegisterUnlockElements(list, ns.name)
end

-- Put a strip on every drawn line and register the lot; lines that went
-- away stay registered as hidden. Called from Lines.Refresh.
function Unlock.Apply()
  if not Unlock.initialized then return end
  local e = eui()
  if not (e and type(e.RegisterUnlockElements) == "function") then return end
  local left, bottom, width, height = UIParent:GetRect()
  if not left then return end
  local ppu = ns.Lines.PixelsPerUnit()

  for _, s in pairs(strips) do s.live = false end
  local list, keys = {}, {}
  for i, t in ipairs(ns.Lines.SnapTargets()) do
    local vertical = t.orientation == "vertical"
    local origin = vertical and left or bottom
    local size = vertical and width or height
    local key = keyFor(t, origin, ppu)
    local s = strips[key] or newStrip(e, key)
    s.live = true
    s.spec.order = ORDER + i
    s.spec.label = string.format("%s guide at %s%%", vertical and "Vertical" or "Horizontal",
      ns.Guides.FormatPercent((t.coord - origin) / size * 100))
    -- The mover is centered on the strip; half a hair over puts its left
    -- (bottom) edge exactly on the line.
    s.frame:ClearAllPoints()
    if vertical then
      s.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", t.coord - left + HAIR / 2, -0.25 * height)
      s.w, s.h = HAIR, SPAN * height
    else
      s.frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", -0.25 * width, t.coord - bottom + HAIR / 2)
      s.w, s.h = SPAN * width, HAIR
    end
    keys[#keys + 1] = key
    list[#list + 1] = s.spec
  end
  for _, s in pairs(strips) do
    if not s.live then list[#list + 1] = s.spec end
  end
  if #list == 0 then return end

  table.sort(keys)
  local sig = string.format("%s|%s %s", table.concat(keys, " "), width, height)
  if sig == signature then return end
  signature = sig
  register(e, list)
end

-- An Unlock Mode session opened (active) or closed.
function Unlock.SetActive(active)
  Unlock.active = active and true or false
  ns.Lines.SetUnlockShown(Unlock.active)
  ns.UI.SetUnlockShown(Unlock.active)
end

-- Opens Unlock Mode, for /emg unlock and the settings button.
function Unlock.Open()
  local e = eui()
  if not (e and type(e.OpenUnlockMode) == "function") then
    ns.Print("EllesmereUI isn't loaded")
    return false
  end
  if _G.InCombatLockdown and _G.InCombatLockdown() then
    ns.Print("Unlock Mode can't be opened in combat")
    return false
  end
  e:OpenUnlockMode()
  return true
end

function Unlock.Init()
  if Unlock.initialized or not Unlock.Available() then return end
  Unlock.initialized = true
  local e = eui()
  e:RegisterUnlockModeListener(OWNER, function(active) Unlock.SetActive(active) end)
  if not Unlock.active and Unlock.IsActive() then Unlock.SetActive(true) end
  Unlock.Apply()
end
