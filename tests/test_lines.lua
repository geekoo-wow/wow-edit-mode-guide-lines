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
  local a, b = ns.Lines.pool[1], ns.Lines.pool[2]
  eq({ a.startPoint.point, a.startPoint.x, a.startPoint.y }, { "BOTTOMLEFT", 250, 0 })
  eq({ a.endPoint.point, a.endPoint.x, a.endPoint.y }, { "TOPLEFT", 250, 0 })
  eq(b.startPoint.x, 750)
  eq(a.startPoint.rel, ns.Lines.frame)
  eq(a.color, { r = 0.25, g = 1, b = 0.25, a = 1 })
  truthy(a.shown and b.shown)
end)

test("a horizontal guide uses the screen height, measured from the bottom", function()
  local ns = T.load()
  ns.Config.Add("h", 50, "red")
  eq(drawn(ns), { { "horizontal", 192 }, { "horizontal", 576 } })
  local a = ns.Lines.pool[1]
  eq({ a.startPoint.point, a.startPoint.x, a.startPoint.y }, { "BOTTOMLEFT", 0, 192 })
  eq({ a.endPoint.point, a.endPoint.x, a.endPoint.y }, { "BOTTOMRIGHT", 0, 192 })
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
  ns.Config.SetThickness(3)
  near(ns.Lines.pool[1].thickness * mock.ppu(), 3)
end)

test("Compute is pure and skips disabled guides", function()
  local ns = T.load()
  local green = ns.Guides.ParseColor("green")
  local out = ns.Lines.Compute({
    { orientation = "vertical", percent = 50, color = green, enabled = true },
    { orientation = "horizontal", percent = 50, color = green, enabled = false },
  }, 10, 20, 1000, 600, 1)
  eq(out, {
    { orientation = "vertical", coord = 260, color = green, guide = 1 },
    { orientation = "vertical", coord = 760, color = green, guide = 1 },
  })
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
