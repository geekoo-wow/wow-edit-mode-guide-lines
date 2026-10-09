-- Snap.lua — makes the guides snap targets for Edit Mode.
--
-- How Blizzard's snapping works (Blizzard_EditMode/Shared/EditModeUtil.lua,
-- the same on retail and Forever): EditModeMagnetismManager keeps
-- `magneticGridLines`, a table { vertical = { [key] = x }, horizontal =
-- { [key] = y } } of coordinates in UIParent space. When a frame is dropped
-- (and while it is dragged, for the red preview line) the manager snaps the
-- frame's nearest edge or its center to the closest line within 8 screen
-- pixels, anchoring the frame to UIParent at that position. Blizzard's grid
-- fills the table while it is shown: RegisterGrid resets it, RegisterGridLine
-- adds a line, UnregisterGrid (grid hidden) sets it to nil.
--
-- The guides are added to that same table under keys of their own, so they
-- behave exactly like grid lines: edges and centers snap to them, the preview
-- line shows, and the saved layout only ever references UIParent, never one
-- of this addon's frames. Hooks on RegisterGrid and UnregisterGrid put the
-- guides back whenever Blizzard rebuilds or clears the table.

local _, ns = ...
ns = ns or {}

local Snap = {}
ns.Snap = Snap

local keys = {}        -- one key table per line slot, reused so the set stays small
local registered = {}  -- the keys currently in Blizzard's table

local function manager() return _G.EditModeMagnetismManager end

function Snap.Available() return manager() ~= nil end

local function blizzardGridShown()
  local editMode = _G.EditModeManagerFrame
  return editMode and editMode.Grid and editMode.Grid:IsShown() and true or false
end

-- The keys registered right now (for the tests).
function Snap.Registered() return registered end

-- Replace whatever guide lines are registered with the current ones.
function Snap.Apply()
  local mm = manager()
  if not mm then return end
  local lines = mm.magneticGridLines
  if lines then
    for key in pairs(registered) do
      if lines.vertical then lines.vertical[key] = nil end
      if lines.horizontal then lines.horizontal[key] = nil end
    end
  end
  wipe(registered)

  local targets = ns.Lines.SnapTargets()
  if #targets == 0 then
    -- Nothing of ours to add: leave the table as Blizzard expects it, which
    -- is nil while the grid is hidden.
    if lines and not blizzardGridShown() then mm.magneticGridLines = nil end
    return
  end

  if not lines then
    lines = { horizontal = {}, vertical = {} }
    mm.magneticGridLines = lines
  end
  for i, t in ipairs(targets) do
    local key = keys[i]
    if not key then
      key = { isGuideLine = true }
      keys[i] = key
    end
    local bucket = lines[t.orientation]
    if not bucket then
      bucket = {}
      lines[t.orientation] = bucket
    end
    bucket[key] = t.coord
    registered[key] = true
  end
end

function Snap.Init()
  local mm = manager()
  if not mm or Snap.hooked then return end
  Snap.hooked = true
  if type(mm.RegisterGrid) == "function" then
    hooksecurefunc(mm, "RegisterGrid", function() Snap.Apply() end)
  end
  if type(mm.UnregisterGrid) == "function" then
    hooksecurefunc(mm, "UnregisterGrid", function() Snap.Apply() end)
  end
  -- Blizzard recomputes UIParent's size here (UI scale, resolution, debug
  -- menus); the guides' coordinates must follow.
  if type(mm.UpdateTopLevelParentPoints) == "function" then
    hooksecurefunc(mm, "UpdateTopLevelParentPoints", function() ns.Lines.Refresh() end)
  end
  Snap.Apply()
end
