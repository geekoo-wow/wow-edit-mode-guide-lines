-- tests/test_unlock.lua — EllesmereUI's Unlock Mode: the lines show with the
-- session, every line is registered as a position-locked, hair-thin element
-- its movers snap to, the panel docks under the banner, and nothing breaks
-- without EllesmereUI.

local T = ...
local test, eq, truthy, near = T.test, T.eq, T.truthy, T.near
local mock = T.mock

local SCREEN_W, SCREEN_H = 1000, 768   -- the mock's screen, UIParent units at scale 1

-- The registered movers that are live (not hidden), keyed by element key.
local function liveMovers()
  local out = {}
  for key, m in pairs(mock.unlockMovers()) do
    if not m.hidden then out[key] = m end
  end
  return out
end

local function keys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

test("without EllesmereUI the integration stays off and the addon still works", function()
  local ns = T.load()
  truthy(not ns.Unlock.Available())
  truthy(not ns.Unlock.CanSnap())
  truthy(not ns.Unlock.IsActive())
  truthy(not ns.Unlock.initialized)
  ns.Config.Add("v", 50)
  eq(next(ns.Unlock.Strips()), nil, "no strips")
  ns.Commands.Run("unlock")
  truthy(T.lastPrinted():match("EllesmereUI isn't loaded"), T.lastPrinted())
  eq(rawget(ns.UI.settings, "openUnlockButton"), nil, "no Unlock Mode button in the settings")
end)

test("the lines show while an Unlock Mode session is open and hide when it closes", function()
  local ns = T.load(nil, { ellesmere = true })
  truthy(ns.Unlock.Available() and ns.Unlock.CanSnap() and ns.Unlock.initialized)
  ns.Config.Add("v", 50)
  truthy(not ns.Lines.frame.shown, "hidden outside both editors")
  mock.enterUnlock()
  truthy(ns.Unlock.IsActive() and ns.Unlock.active)
  truthy(ns.Lines.frame.shown)
  mock.exitUnlock("save")
  truthy(not ns.Unlock.active)
  truthy(not ns.Lines.frame.shown)
  ns.Config.SetSetting("showOutsideEditMode", true)
  truthy(ns.Lines.frame.shown)
end)

test("a session already open when the addon logs in shows the lines", function()
  local ns = T.load(nil, { ellesmere = true, noLogin = true })
  ns.Config.Add("v", 50)
  mock.enterUnlock()
  ns.frame:Fire("PLAYER_LOGIN")
  truthy(ns.Unlock.active)
  truthy(ns.Lines.frame.shown)
end)

test("each line is an element whose mover is a hair-thin strip on the line, off screen along it", function()
  local ns = T.load(nil, { ellesmere = true })
  ns.Config.Add("v", 50, "green")
  local live = liveMovers()
  eq(keys(live), { "EMG_V_250", "EMG_V_750" })
  for _, m in pairs(live) do
    truthy(m.right - m.left <= 0.001, "hair thin")
    truthy(m.top >= SCREEN_H and m.bottom <= 0, "spans the whole screen height")
    local cy = (m.top + m.bottom) / 2
    truthy(cy < 0 or cy > SCREEN_H, "its own center is off screen")
  end
  near(live.EMG_V_250.left, 250)
  near(live.EMG_V_750.left, 750)
  eq(live.EMG_V_250.label, "Vertical guide at 25%")
  eq(live.EMG_V_750.label, "Vertical guide at 75%")
  eq(live.EMG_V_250.group, "Guide Lines")
  truthy(live.EMG_V_250.order < live.EMG_V_750.order)

  ns.Config.Add("h", 50)
  live = liveMovers()
  eq(keys(live), { "EMG_H_192", "EMG_H_576", "EMG_V_250", "EMG_V_750" })
  local h = live.EMG_H_192
  near(h.bottom, 192)
  truthy(h.top - h.bottom <= 0.001)
  truthy(h.left <= 0 and h.right >= SCREEN_W, "spans the whole screen width")
  local cx = (h.left + h.right) / 2
  truthy(cx < 0 or cx > SCREEN_W)
  eq(h.label, "Horizontal guide at 25%")
  eq(live.EMG_H_576.label, "Horizontal guide at 75%")
end)

test("the elements are position-locked, unlinkable and save nothing", function()
  local ns = T.load(nil, { ellesmere = true })
  ns.Config.Add("v", 0)
  local m = liveMovers().EMG_V_500
  truthy(m, "a 0% guide is one line through the middle")
  local e = m.elem
  truthy(e.keepMoverWhenAnchored and e.isAnchored() == true, "position-locked")
  truthy(e.noResize and e.noAnchorTo and e.noAnchorTarget and e.noSizeMatchTarget)
  eq(type(e.savePosition), "function")
  eq(e.savePosition("EMG_V_500", "TOPLEFT", "TOPLEFT", 1, 2), nil)
  eq(e.loadPosition, nil)
  eq(e.folder, "EditModeGuideLines")
  eq(e.getFrame(), ns.Unlock.Strips().EMG_V_500.frame)
end)

test("an EllesmereUI without the element factory gets the same elements", function()
  local ns = T.load(nil, { ellesmere = { noFactory = true } })
  ns.Config.Add("v", 50)
  local m = liveMovers().EMG_V_250
  truthy(m)
  eq(type(m.elem.savePosition), "function")
  eq(m.elem.savePos, nil)
  truthy(m.elem.keepMoverWhenAnchored)
end)

test("lines that go away stay registered but hidden; nothing is ever unregistered", function()
  local ns = T.load(nil, { ellesmere = true })
  ns.Config.Add("v", 50)
  ns.Config.Add("v", 20)
  eq(keys(liveMovers()), { "EMG_V_250", "EMG_V_400", "EMG_V_600", "EMG_V_750" })
  ns.Config.Remove(2)
  eq(keys(liveMovers()), { "EMG_V_250", "EMG_V_750" })
  eq(keys(mock.unlockMovers()), { "EMG_V_250", "EMG_V_400", "EMG_V_600", "EMG_V_750" }, "still registered")
  ns.Config.SetEnabled(1, false)
  eq(keys(liveMovers()), {})
  ns.Config.SetEnabled(1, true)
  ns.Config.SetSetting("enabled", false)
  eq(keys(liveMovers()), {}, "the addon off: nothing to snap to")
  ns.Config.SetSetting("enabled", true)
  eq(keys(liveMovers()), { "EMG_V_250", "EMG_V_750" })
  ns.Config.Add("v", 20)
  eq(keys(liveMovers()), { "EMG_V_250", "EMG_V_400", "EMG_V_600", "EMG_V_750" }, "the old elements come back")
end)

test("registration happens only when the set of lines changes", function()
  local ns = T.load(nil, { ellesmere = true })
  eq(mock.unlockRegistrations, 0, "nothing to register yet")
  ns.Config.Add("v", 50)
  eq(mock.unlockRegistrations, 1)
  ns.Lines.Refresh()
  ns.Config.SetColor(1, "red")
  ns.Config.SetThickness(3)
  eq(mock.unlockRegistrations, 1, "same lines: no churn")
  ns.Config.SetPercent(1, 60)
  eq(mock.unlockRegistrations, 2)
  eq(keys(liveMovers()), { "EMG_V_200", "EMG_V_800" })
end)

test("during a session a change hides every strip and shows the live ones again, so they re-sync", function()
  local ns = T.load(nil, { ellesmere = true })
  mock.enterUnlock()
  ns.Config.Add("v", 50)
  eq(mock.unlockRegistrations, 2, "hide, then show")
  eq(mock.unlockHiddenOnRegister.EMG_V_250, false, "live after the second call")
  eq(keys(liveMovers()), { "EMG_V_250", "EMG_V_750" })
  mock.exitUnlock()
  ns.Config.Add("h", 0)
  eq(mock.unlockRegistrations, 3, "one call outside a session")
end)

test("a resize moves the lines to new elements and hides the old", function()
  local ns = T.load(nil, { ellesmere = true })
  ns.Config.Add("v", 50)
  mock.resize(2000, 768)
  eq(keys(liveMovers()), { "EMG_V_1500", "EMG_V_500" })
  eq(keys(mock.unlockMovers()), { "EMG_V_1500", "EMG_V_250", "EMG_V_500", "EMG_V_750" })
end)

test("the strips sit exactly on the drawn lines, at any resolution and scale", function()
  local ns = T.load(nil, { ellesmere = true })
  mock.resize(1920, 1080, 0.5)
  ns.Config.Add("v", 33.33)
  ns.Config.Add("h", 10)
  local live = liveMovers()
  local n = 0
  for _, t in ipairs(ns.Lines.Targets()) do
    n = n + 1
    local found
    for _, m in pairs(live) do
      if t.orientation == "vertical" and math.abs(m.left - t.coord) < 1e-6 then found = m end
      if t.orientation == "horizontal" and math.abs(m.bottom - t.coord) < 1e-6 then found = m end
    end
    truthy(found, "a strip on the line at " .. t.coord)
  end
  eq(n, 4)
  local _, _, w, h = _G.UIParent:GetRect()
  for _, m in pairs(live) do
    if m.right - m.left < 1 then
      truthy(m.top >= h and m.bottom <= 0)
    else
      truthy(m.left <= 0 and m.right >= w)
    end
  end
end)

test("the lines hide while combat suspends the session and return after", function()
  local ns = T.load(nil, { ellesmere = true })
  ns.Config.Add("v", 50)
  mock.enterUnlock()
  truthy(ns.Lines.frame.shown)
  ns.frame:Fire("PLAYER_REGEN_DISABLED")
  truthy(not ns.Lines.frame.shown)
  ns.frame:Fire("PLAYER_REGEN_ENABLED")
  truthy(ns.Lines.frame.shown)
  ns.Config.SetSetting("showOutsideEditMode", true)
  ns.frame:Fire("PLAYER_REGEN_DISABLED")
  truthy(ns.Lines.frame.shown, "always-on guides stay in combat")
  ns.frame:Fire("PLAYER_REGEN_ENABLED")
end)

test("the panel docks under the Unlock Mode banner and closes with the session", function()
  local ns = T.load(nil, { ellesmere = true })
  mock.enterUnlock()
  truthy(ns.UI.panel.shown)
  eq(ns.UI.panel.strata, "FULLSCREEN_DIALOG", "above EllesmereUI's movers")
  local p = ns.UI.panel.points[1]
  eq({ p[1], p[2], p[3], p[4] }, { "TOPRIGHT", _G.UIParent, "TOPRIGHT", -14 })
  eq(p[5], -(mock.ellesmereBannerHeight + 8), "below the banner's hover zone")
  mock.exitUnlock()
  truthy(not ns.UI.panel.shown)
  ns.Config.SetSetting("showPanel", false)
  mock.enterUnlock()
  truthy(not ns.UI.panel.shown, "stays closed when the setting is off")
  truthy(ns.UI.Open(), "/emg opens it during the session")
  truthy(ns.UI.panel.shown)
  eq(mock.opened, nil, "not the settings")
end)

test("in Edit Mode the panel keeps its place next to the Edit Mode window", function()
  local ns = T.load(nil, { ellesmere = true })
  mock.enterEditMode()
  local p = ns.UI.panel.points[1]
  eq({ p[1], p[2], p[3] }, { "TOPLEFT", mock.manager, "TOPRIGHT" })
  eq(ns.UI.panel.strata, "DIALOG")
  mock.exitEditMode()
  truthy(not ns.UI.panel.shown)
end)

test("/emg unlock and the settings button open Unlock Mode, except in combat", function()
  local ns = T.load(nil, { ellesmere = true })
  mock.inCombat = true
  ns.Commands.Run("unlock")
  truthy(T.lastPrinted():match("combat"), T.lastPrinted())
  truthy(not ns.Unlock.IsActive())
  mock.inCombat = false
  ns.Commands.Run("unlock")
  truthy(ns.Unlock.IsActive())
  mock.exitUnlock()
  truthy(ns.UI.settings.openUnlockButton, "settings button present")
  ns.UI.settings.openUnlockButton:Click()
  truthy(ns.Unlock.IsActive())
end)
