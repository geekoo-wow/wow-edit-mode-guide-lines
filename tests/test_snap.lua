-- tests/test_snap.lua — registration of the guides as Edit Mode snap targets
-- in EditModeMagnetismManager.magneticGridLines, through Blizzard's grid
-- being shown, hidden and rebuilt.

local T = ...
local test, eq, truthy = T.test, T.eq, T.truthy
local mock = T.mock

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

test("a vertical 50% guide registers snap lines at x = 250 and 750", function()
  local ns = T.load()
  truthy(ns.Snap.Available())
  ns.Config.Add("v", 50)
  eq(mock.snapLines("vertical"), { 250, 750 })
  eq(mock.snapLines("horizontal"), {})
  ns.Config.Add("h", 50)
  eq(mock.snapLines("horizontal"), { 192, 576 })
end)

test("the registered coordinates are the drawn ones", function()
  local ns = T.load()
  mock.resize(1920, 1080, 0.5)
  ns.Config.Add("v", 33.33)
  ns.Config.Add("h", 10)
  local want = { vertical = {}, horizontal = {} }
  for _, t in ipairs(ns.Lines.Targets()) do table.insert(want[t.orientation], t.coord) end
  table.sort(want.vertical)
  table.sort(want.horizontal)
  eq(mock.snapLines("vertical"), want.vertical)
  eq(mock.snapLines("horizontal"), want.horizontal)
end)

test("the guides survive Blizzard's grid being shown, rebuilt and hidden", function()
  local ns = T.load()
  ns.Config.Add("v", 50)
  local MM = mock.magnetism
  mock.showGrid()
  eq(mock.snapLines("vertical"), { 250, 750 }, "after RegisterGrid reset the table")
  eq(MM.magneticGridLines.vertical[mock.gridLines[1]], 500, "Blizzard's center line is there too")
  mock.showGrid() -- grid spacing changed: rebuilt again
  eq(mock.snapLines("vertical"), { 250, 750 })
  eq(count(MM.magneticGridLines.vertical), 3, "no stale keys pile up")
  mock.hideGrid()
  truthy(MM.magneticGridLines, "recreated for the guides after UnregisterGrid")
  eq(mock.snapLines("vertical"), { 250, 750 })
  eq(MM.magneticGridLines.vertical[mock.gridLines[1]], nil, "Blizzard's lines are gone")
end)

test("with nothing to register the table is left as Blizzard expects", function()
  local ns = T.load()
  local MM = mock.magnetism
  eq(MM.magneticGridLines, nil, "no guides, grid hidden: nil")
  ns.Config.Add("v", 50)
  truthy(MM.magneticGridLines)
  ns.Config.SetSetting("enabled", false)
  eq(MM.magneticGridLines, nil, "disabled: back to nil")
  ns.Config.SetSetting("enabled", true)
  mock.showGrid()
  ns.Config.Clear()
  truthy(MM.magneticGridLines, "grid shown: Blizzard's table stays")
  eq(mock.snapLines("vertical"), {})
  eq(MM.magneticGridLines.vertical[mock.gridLines[1]], 500)
  mock.hideGrid()
  eq(MM.magneticGridLines, nil)
end)

test("edits replace the old lines and keys are reused", function()
  local ns = T.load()
  ns.Config.Add("v", 50)
  ns.Config.SetPercent(1, 20)
  eq(mock.snapLines("vertical"), { 400, 600 })
  ns.Config.Flip(1)
  eq(mock.snapLines("vertical"), {})
  eq(mock.snapLines("horizontal"), { 307, 461 })
  eq(count(ns.Snap.Registered()), 2)
  ns.Config.SetEnabled(1, false)
  eq(count(ns.Snap.Registered()), 0)
  eq(mock.snapLines("horizontal"), {})
end)

test("UIParent changes re-register at the new positions", function()
  local ns = T.load()
  ns.Config.Add("v", 50)
  mock.resize(2000, 768, 1) -- Blizzard's UpdateTopLevelParentPoints runs, hooked
  eq(mock.snapLines("vertical"), { 500, 1500 })
end)

test("without Edit Mode on the client nothing is registered and nothing raises", function()
  local ns = T.load(nil, { noEditMode = true })
  truthy(not ns.Snap.Available())
  ns.Config.Add("v", 50)
  eq(count(ns.Snap.Registered()), 0)
end)

test("the snap keys are tagged so they can be told from grid lines", function()
  local ns = T.load()
  ns.Config.Add("v", 50)
  for key in pairs(ns.Snap.Registered()) do
    eq(key.isGuideLine, true)
    eq(key.isGridLine, nil)
  end
end)
