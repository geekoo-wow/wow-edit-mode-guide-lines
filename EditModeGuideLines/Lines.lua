-- Lines.lua — draws the guides. One full-screen frame under UIParent holds a
-- pool of Line textures, one per guide line. Positions are rounded to whole
-- screen pixels, and those same rounded positions are what Snap.lua registers
-- (and Unlock.lua hands to EllesmereUI), so a frame that snaps to a guide
-- lands exactly on the drawn line. The lines are visible while Edit Mode or
-- EllesmereUI's Unlock Mode is open, or always with showOutsideEditMode.
--
-- Pixel coverage: a position is a boundary between two pixel columns (rows),
-- and a line of even thickness centered on it covers whole pixels. A line of
-- odd thickness can't: centered there, a 1 px line straddles two pixels by
-- half each, and whether the GPU paints one, the other, both or neither comes
-- down to rounding noise in the engine's transform (1 px guides vanishing at
-- some percentages and UI scales). So an odd line is drawn half a pixel off
-- its position, the extra pixel outward from the band the guide stands for:
-- the lines bound the band, and a frame snapped to both of them fills it
-- exactly and hides neither. The engine's own texel snapping is turned off on
-- the lines so the quad stays where it is put.

local _, ns = ...
ns = ns or {}

local Lines = {}
ns.Lines = Lines

local container      -- the full-screen frame; nil until Lines.Init
local pool = {}      -- Line textures, reused between refreshes
local targets = {}   -- the lines currently drawn: { orientation, coord, center, color, guide }
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
-- rounded to a whole pixel. `coord` is the line's position, the pixel
-- boundary that Snap and Unlock register. `center` is the centerline of the
-- drawn line, `thickness` pixels wide: `coord` itself for an even thickness,
-- half a pixel outward (away from the band's middle) for an odd one, so the
-- line covers whole pixels and `coord` stays its band-side edge. Pure, so the
-- tests can check the arithmetic.
function Lines.Compute(guides, left, bottom, width, height, ppu, thickness)
  local out = {}
  local overhang = ((thickness or 1) % 2) * 0.5 / ppu   -- the odd pixel's half
  for index, guide in ipairs(guides) do
    if guide.enabled then
      local vertical = guide.orientation == "vertical"
      local origin = vertical and left or bottom
      local size = vertical and width or height
      local positions = ns.Guides.LinePositions(guide.percent, size)
      for i, offset in ipairs(positions) do
        local coord = snapToPixel(origin + offset, ppu)
        -- The lower line of a pair leans left/down, the upper one (or the
        -- single line of a 0% guide) right/up.
        local outward = (i == 1 and #positions > 1) and -1 or 1
        out[#out + 1] = {
          orientation = guide.orientation,
          coord = coord,
          center = coord + outward * overhang,
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
    -- The quad is placed on whole pixels already; the engine's texel
    -- snapping would only move it by its own rounding (guarded: Line
    -- inherits both from TextureBase, but older clients may lack them).
    if line.SetSnapToPixelGrid then line:SetSnapToPixelGrid(false) end
    if line.SetTexelSnappingBias then line:SetTexelSnappingBias(0) end
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
  local thickness = db.thickness or 1   -- screen pixels
  targets = Lines.Compute(db.guides, left, bottom, width, height, ppu, thickness)
  for i, t in ipairs(targets) do
    local line = acquire(i)
    local c = t.color
    line:SetColorTexture(c.r, c.g, c.b, c.a)
    line:SetThickness(thickness / ppu)
    -- The container fills UIParent, so offsets from its corner are UIParent
    -- coordinates less UIParent's own origin (normally 0, 0). The line is
    -- drawn on `center`, which is `coord` or half a pixel off it (see Compute).
    if t.orientation == "vertical" then
      line:SetStartPoint("BOTTOMLEFT", container, t.center - left, 0)
      line:SetEndPoint("TOPLEFT", container, t.center - left, 0)
    else
      line:SetStartPoint("BOTTOMLEFT", container, 0, t.center - bottom)
      line:SetEndPoint("BOTTOMRIGHT", container, 0, t.center - bottom)
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
