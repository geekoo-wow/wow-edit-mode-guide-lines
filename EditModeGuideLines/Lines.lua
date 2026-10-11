-- Lines.lua — draws the guides. One full-screen frame under UIParent holds a
-- pool of Line textures, one per guide line. Positions are rounded to whole
-- screen pixels, and those same rounded positions are what Snap.lua registers
-- (and Unlock.lua hands to EllesmereUI), so a frame that snaps to a guide
-- lands exactly on the drawn line. The lines are visible while Edit Mode or
-- EllesmereUI's Unlock Mode is open, or always with showOutsideEditMode.

local _, ns = ...
ns = ns or {}

local Lines = {}
ns.Lines = Lines

local container      -- the full-screen frame; nil until Lines.Init
local pool = {}      -- Line textures, reused between refreshes
local targets = {}   -- the lines currently drawn: { orientation, coord, color, guide }
local editModeShown = false
local unlockShown = false   -- an EllesmereUI Unlock Mode session is open
local inCombat = false

-- Screen pixels per UIParent unit. The UI is 768 units tall at scale 1
-- whatever the resolution, so a unit is (physical height / 768) pixels,
-- times UIParent's scale.
function Lines.PixelsPerUnit()
  local physHeight = 768
  if _G.GetPhysicalScreenSize then
    local _, h = _G.GetPhysicalScreenSize()
    if h and h > 0 then physHeight = h end
  end
  local scale = UIParent:GetEffectiveScale() or 1
  return scale * physHeight / 768
end

-- The nearest whole pixel, in UIParent units.
local function snapToPixel(coord, ppu)
  return math.floor(coord * ppu + 0.5) / ppu
end

-- The lines for a list of guides on a screen rect (UIParent units), each
-- rounded to a whole pixel. Pure, so the tests can check the arithmetic.
function Lines.Compute(guides, left, bottom, width, height, ppu)
  local out = {}
  for index, guide in ipairs(guides) do
    if guide.enabled then
      local vertical = guide.orientation == "vertical"
      local origin = vertical and left or bottom
      local size = vertical and width or height
      for _, offset in ipairs(ns.Guides.LinePositions(guide.percent, size)) do
        out[#out + 1] = {
          orientation = guide.orientation,
          coord = snapToPixel(origin + offset, ppu),
          color = guide.color,
          guide = index,
        }
      end
    end
  end
  return out
end

-- The lines currently drawn (recomputed by Refresh).
function Lines.Targets() return targets end

-- What Snap.lua registers and Unlock.lua hands out: the drawn lines, or
-- nothing while the addon is off.
function Lines.SnapTargets()
  if not (ns.db and ns.db.enabled) then return {} end
  return targets
end

local function acquire(i)
  local line = pool[i]
  if not line then
    line = container:CreateLine(nil, "ARTWORK")
    pool[i] = line
  end
  return line
end

function Lines.UpdateVisibility()
  if not container then return end
  local db = ns.db
  -- Unlock Mode suspends itself in combat (its grid and movers hide until
  -- the fight is over); the guides follow it.
  local unlock = unlockShown and not inCombat
  local shown = db.enabled and #targets > 0 and (editModeShown or unlock or db.showOutsideEditMode)
  container:SetShown(shown and true or false)
end

-- Recompute and redraw everything, then re-register the snap targets (Edit
-- Mode's and Unlock Mode's). Called after every config change and whenever
-- the screen or the UI scale changes.
function Lines.Refresh()
  if not container then return end
  local db = ns.db
  local left, bottom, width, height = UIParent:GetRect()
  if not left then return end
  local ppu = Lines.PixelsPerUnit()
  targets = Lines.Compute(db.guides, left, bottom, width, height, ppu)
  local thickness = (db.thickness or 1) / ppu
  for i, t in ipairs(targets) do
    local line = acquire(i)
    local c = t.color
    line:SetColorTexture(c.r, c.g, c.b, c.a)
    line:SetThickness(thickness)
    -- The container fills UIParent, so offsets from its corner are UIParent
    -- coordinates less UIParent's own origin (normally 0, 0).
    if t.orientation == "vertical" then
      line:SetStartPoint("BOTTOMLEFT", container, t.coord - left, 0)
      line:SetEndPoint("TOPLEFT", container, t.coord - left, 0)
    else
      line:SetStartPoint("BOTTOMLEFT", container, 0, t.coord - bottom)
      line:SetEndPoint("BOTTOMRIGHT", container, 0, t.coord - bottom)
    end
    line:Show()
  end
  for i = #targets + 1, #pool do pool[i]:Hide() end
  container:SetFrameStrata(db.aboveFrames and "HIGH" or "BACKGROUND")
  Lines.UpdateVisibility()
  if ns.Snap then ns.Snap.Apply() end
  if ns.Unlock then ns.Unlock.Apply() end
end

function Lines.SetEditModeShown(shown)
  editModeShown = shown and true or false
  if editModeShown then Lines.Refresh() else Lines.UpdateVisibility() end
end

function Lines.IsEditModeShown() return editModeShown end

function Lines.SetUnlockShown(shown)
  unlockShown = shown and true or false
  if unlockShown then Lines.Refresh() else Lines.UpdateVisibility() end
end

function Lines.IsUnlockShown() return unlockShown end

function Lines.SetInCombat(v)
  inCombat = v and true or false
  Lines.UpdateVisibility()
end

function Lines.Init()
  if container then return end
  container = CreateFrame("Frame", "EditModeGuideLinesFrame", UIParent)
  container:SetAllPoints(UIParent)
  container:SetFrameStrata("BACKGROUND")
  container:Hide()
  Lines.frame = container
  Lines.pool = pool

  local manager = _G.EditModeManagerFrame
  if manager then
    -- Visible exactly when the Edit Mode window is, like Blizzard's own grid
    -- (which also hides while Edit Mode is parked behind a menu).
    manager:HookScript("OnShow", function() Lines.SetEditModeShown(true) end)
    manager:HookScript("OnHide", function() Lines.SetEditModeShown(false) end)
    editModeShown = manager:IsShown() and true or false
  end
  -- Blizzard's grid redraws on this too: UIParent can be resized (debug menus).
  if type(_G.UpdateUIParentPosition) == "function" then
    hooksecurefunc("UpdateUIParentPosition", function() Lines.Refresh() end)
  end
  Lines.Refresh()
end
