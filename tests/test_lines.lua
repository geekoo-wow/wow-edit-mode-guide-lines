-- tests/test_lines.lua — the drawn lines: positions, pixel alignment,
-- colors, thickness and when they're visible.

local T = ...
local test, eq, truthy, near = T.test, T.eq, T.truthy, T.near
local mock = T.mock

-- The lines drawn right now, as { orientation, coord } sorted by coord.
local function drawn(ns)
  local out = {}
  for _, t in ipairs(ns.Lines.Targets()) do out[#out + 1] = { t.orientation, t.coord } end
  table.sort(out, function(a, b) return a[2] < b[2] end)
  return out
end

test("a vertical 50% guide on a 1000 px screen draws lines at x = 250 and 750", function()
  local ns = T.load()
  ns.Config.Add("v", 50, "green")
  eq(drawn(ns), { { "vertical", 250 }, { "vertical", 750 } })
  -- The default 1 px line sits on the pixel just outside the band: the quad
  -- is centered half a pixel off the position (1 unit = 1 px here).
  local a, b = ns.Lines.pool[1], ns.Lines.pool[2]
  eq({ a.startPoint.point, a.startPoint.x, a.startPoint.y }, { "BOTTOMLEFT", 249.5, 0 })
  eq({ a.endPoint.point, a.endPoint.x, a.endPoint.y }, { "TOPLEFT", 249.5, 0 })
  eq(b.startPoint.x, 750.5)
  eq(a.startPoint.rel, ns.Lines.frame)
  eq(a.color, { r = 0.25, g = 1, b = 0.25, a = 1 })
  truthy(a.shown and b.shown)
end)

test("a horizontal guide uses the screen height, measured from the bottom", function()
  local ns = T.load()
  ns.Config.Add("h", 50, "red")
  eq(drawn(ns), { { "horizontal", 192 }, { "horizontal", 576 } })
  local a, b = ns.Lines.pool[1], ns.Lines.pool[2]
  eq({ a.startPoint.point, a.startPoint.x, a.startPoint.y }, { "BOTTOMLEFT", 0, 191.5 })
  eq({ a.endPoint.point, a.endPoint.x, a.endPoint.y }, { "BOTTOMRIGHT", 0, 191.5 })
  eq(b.startPoint.y, 576.5)
end)

test("a 0% guide is one line, disabled guides draw nothing, removed lines are hidden", function()
  local ns = T.load()
  ns.Config.Add("v", 0)
  ns.Config.Add("h", 20)
  eq(drawn(ns), { { "horizontal", 307 }, { "horizontal", 461 }, { "vertical", 500 } })
  ns.Config.SetEnabled(2, false)
  eq(drawn(ns), { { "vertical", 500 } })
  eq(#ns.Lines.pool, 3, "line textures are pooled")
  truthy(ns.Lines.pool[1].shown)
  truthy(not ns.Lines.pool[2].shown and not ns.Lines.pool[3].shown)
end)

test("positions land on whole screen pixels at any UI scale", function()
  local ns = T.load()
  mock.resize(1920, 1080, 768 / 1080) -- the "pixel perfect" scale: 1 unit = 1 px
  ns.Config.Add("v", 33.33)
  eq(drawn(ns), { { "vertical", 640 }, { "vertical", 1280 } })
  mock.resize(1920, 1080, 0.5)
  near(mock.ppu(), 0.703125)
  for _, t in ipairs(ns.Lines.Targets()) do
    local px = t.coord * mock.ppu()
    near(px, math.floor(px + 0.5), "whole pixel", 1e-6)
  end
  near(ns.Lines.Targets()[1].coord * mock.ppu(), 640)
  near(ns.Lines.Targets()[2].coord * mock.ppu(), 1280)
  near(ns.Lines.pool[1].thickness * mock.ppu(), 1, "one pixel thick")
  near(ns.Lines.pool[1].startPoint.x * mock.ppu(), 639.5, "drawn on pixel 639")
  near(ns.Lines.pool[2].startPoint.x * mock.ppu(), 1280.5, "drawn on pixel 1280")
  ns.Config.SetThickness(3)
  near(ns.Lines.pool[1].thickness * mock.ppu(), 3)
  near(ns.Lines.pool[1].startPoint.x * mock.ppu(), 639.5, "pixels 638, 639, 640")
end)

-- The pixel columns (rows) a drawn line covers: the quad's edges must land
-- on whole pixels, or the GPU paints a 1 px line in one of two columns, both
-- or neither depending on rounding noise (the bug: 1 px guides missing at
-- some percentages and scales).
local function covered(line, px, ppu)
  local center = line.startPoint.x ~= 0 and line.startPoint.x or line.startPoint.y
  local lo, hi = (center - line.thickness / 2) * ppu, (center + line.thickness / 2) * ppu
  near(lo, math.floor(lo + 0.5), "edge on a whole pixel", 1e-6)
  near(hi, math.floor(hi + 0.5), "edge on a whole pixel", 1e-6)
  near(hi - lo, px, "thickness in pixels", 1e-6)
  return math.floor(lo + 0.5), math.floor(hi + 0.5)
end

test("a line covers whole pixels at every thickness; an odd one leans outward from the band", function()
  local ns = T.load()
  ns.Config.Add("v", 50)   -- positions 250 and 750 on the 1000 px screen
  ns.Config.Add("v", 0)    -- the single center line, position 500
  local lo, hi, mid = ns.Lines.pool[1], ns.Lines.pool[2], ns.Lines.pool[3]
  for _, uiScale in ipairs({ 1, 0.5, 768 / 1080, 0.71111111 }) do
    mock.resize(2560, 1440, uiScale)
    for px = 1, 8 do
      ns.Config.SetThickness(px)
      local ppu = mock.ppu()
      local a, b = covered(lo, px, ppu)
      local c, d = covered(hi, px, ppu)
      local e, f = covered(mid, px, ppu)
      local half = math.floor(px / 2)
      -- 1 px: lo covers pixel 639 (band-side edge at 640), hi pixel 1920,
      -- mid pixel 1280; 2 px: 639-640, 1919-1920, 1279-1280; 3 px: 638-640,
      -- 1919-1921, 1279-1281.
      eq({ a, b }, { 640 - half - px % 2, 640 + half }, "lower line at " .. px .. " px")
      eq({ c, d }, { 1920 - half, 1920 + half + px % 2 }, "upper line at " .. px .. " px")
      eq({ e, f }, { 1280 - half, 1280 + half + px % 2 }, "center line at " .. px .. " px")
      -- The registered position is unchanged: the band-side edge.
      eq(drawn(ns), { { "vertical", 640 / ppu }, { "vertical", 1280 / ppu }, { "vertical", 1920 / ppu } })
    end
  end
  -- The engine's texel snapping is off, so the quad stays on those pixels.
  for i = 1, 3 do
    eq(ns.Lines.pool[i].snapToPixelGrid, false)
    eq(ns.Lines.pool[i].texelSnappingBias, 0)
  end
end)

test("Compute is pure and skips disabled guides", function()
  local ns = T.load()
  local green = ns.Guides.ParseColor("green")
  local out = ns.Lines.Compute({
    { orientation = "vertical", percent = 50, color = green, enabled = true },
    { orientation = "horizontal", percent = 50, color = green, enabled = false },
  }, 10, 20, 1000, 600, 1, 1)
  eq(out, {
    { orientation = "vertical", coord = 260, center = 259.5, color = green, guide = 1 },
    { orientation = "vertical", coord = 760, center = 760.5, color = green, guide = 1 },
  })
  local two = ns.Lines.Compute({ { orientation = "horizontal", percent = 0, color = green, enabled = true } },
    0, 0, 1000, 600, 2, 2)
  eq(two, { { orientation = "horizontal", coord = 300, center = 300, color = green, guide = 1 } })
end)

test("the lines show with the Edit Mode window and hide with it", function()
  local ns = T.load()
  ns.Config.Add("v", 50)
  local frame = ns.Lines.frame
  truthy(not frame.shown, "hidden before Edit Mode")
  mock.enterEditMode()
  truthy(frame.shown, "shown in Edit Mode")
  mock.exitEditMode()
  truthy(not frame.shown, "hidden again")
  ns.Config.SetSetting("showOutsideEditMode", true)
  truthy(frame.shown, "shown outside Edit Mode when asked")
  ns.Config.SetSetting("enabled", false)
  truthy(not frame.shown, "never shown while disabled")
  ns.Config.SetSetting("enabled", true)
  ns.Config.Clear()
  truthy(not frame.shown, "nothing to show")
end)

test("edit mode already open at login, and the strata option", function()
  mock.reset()
  local ns = T.load({ guides = { { orientation = "v", percent = 50 } } }, { noLogin = true })
  mock.enterEditMode()
  ns.frame:Fire("PLAYER_LOGIN")
  truthy(ns.Lines.frame.shown)
  eq(ns.Lines.frame.strata, "BACKGROUND")
  ns.Config.SetSetting("aboveFrames", true)
  eq(ns.Lines.frame.strata, "HIGH")
end)

test("screen and UI scale changes redraw the lines", function()
  local ns = T.load()
  ns.Config.Add("v", 50)
  mock.screen.width = 2000
  ns.frame:Fire("DISPLAY_SIZE_CHANGED")
  eq(drawn(ns), { { "vertical", 500 }, { "vertical", 1500 } })
  mock.uiScale = 0.5
  ns.frame:Fire("UI_SCALE_CHANGED")
  eq(drawn(ns), { { "vertical", 1000 }, { "vertical", 3000 } })
  mock.resize(1000, 768, 1) -- through Blizzard's UpdateUIParentPosition hook
  eq(drawn(ns), { { "vertical", 250 }, { "vertical", 750 } })
end)

test("without Edit Mode on the client the lines still work, just never auto-shown", function()
  local ns = T.load(nil, { noEditMode = true })
  ns.Config.Add("v", 50)
  eq(drawn(ns), { { "vertical", 250 }, { "vertical", 750 } })
  truthy(not ns.Lines.frame.shown)
  ns.Config.SetSetting("showOutsideEditMode", true)
  truthy(ns.Lines.frame.shown)
end)
