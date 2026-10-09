-- Config.lua — the operations the panel and the slash command perform on the
-- saved guides and settings. The only code that writes ns.db; free of widget
-- code so it can be tested offline. Every change ends in ns.ConfigChanged(),
-- which redraws the lines, re-registers the snap targets and refreshes the UI.
--
-- The Set* functions return nil on success and a message on failure, without
-- changing anything.

local _, ns = ...
ns = ns or {}

local Config = {}
ns.Config = Config

local Guides = ns.Guides

local function list() return ns.db.guides end

-- ---- guides -----------------------------------------------------------------

function Config.List() return list() end
function Config.Count() return #list() end
function Config.Get(i) return list()[i] end

local function duplicateOf(orientation, percent, except)
  for i, g in ipairs(list()) do
    if i ~= except and g.orientation == orientation and g.percent == percent then
      return string.format("there is already a %s guide at %s%%", g.orientation, Guides.FormatPercent(g.percent))
    end
  end
end

-- Returns the new guide's number, or nil and a message. The color is
-- optional (Guides.DEFAULT_COLOR); it can be a name, hex or a color table.
function Config.Add(orientation, percent, color)
  local guide, err = Guides.New(orientation, percent, color)
  if not guide then return nil, err end
  err = duplicateOf(guide.orientation, guide.percent)
  if err then return nil, err end
  local l = list()
  l[#l + 1] = guide
  ns.ConfigChanged()
  return #l
end

function Config.Remove(i)
  if not list()[i] then return false end
  table.remove(list(), i)
  ns.ConfigChanged()
  return true
end

-- Removes every guide; returns how many there were.
function Config.Clear()
  local l = list()
  local n = #l
  if n == 0 then return 0 end
  for k = n, 1, -1 do l[k] = nil end
  ns.ConfigChanged()
  return n
end

function Config.SetPercent(i, value)
  local g = list()[i]
  if not g then return "no such guide" end
  local p, err = Guides.ParsePercent(value)
  if not p then return err end
  err = duplicateOf(g.orientation, p, i)
  if err then return err end
  g.percent = p
  ns.ConfigChanged()
end

function Config.SetOrientation(i, value)
  local g = list()[i]
  if not g then return "no such guide" end
  local o = Guides.ParseOrientation(value)
  if not o then return "the orientation must be vertical (v) or horizontal (h)" end
  local err = duplicateOf(o, g.percent, i)
  if err then return err end
  g.orientation = o
  ns.ConfigChanged()
end

function Config.Flip(i)
  local g = list()[i]
  if not g then return "no such guide" end
  return Config.SetOrientation(i, Guides.Other(g.orientation))
end

function Config.SetColor(i, value)
  local g = list()[i]
  if not g then return "no such guide" end
  local c = Guides.ParseColor(value)
  if not c then
    return "unknown color; use a name (" .. table.concat(Guides.COLOR_NAMES, ", ") .. ") or hex like #ff8800"
  end
  g.color = c
  ns.ConfigChanged()
end

function Config.SetEnabled(i, enabled)
  local g = list()[i]
  if not g then return "no such guide" end
  g.enabled = enabled and true or false
  ns.ConfigChanged()
end

function Config.Toggle(i)
  local g = list()[i]
  if not g then return "no such guide" end
  return Config.SetEnabled(i, not g.enabled)
end

-- ---- settings ---------------------------------------------------------------

-- The on/off settings: every boolean in ns.DEFAULTS (enabled,
-- showOutsideEditMode, aboveFrames, showPanel), plus thickness (read only
-- here; Config.SetThickness validates it).
function Config.GetSetting(key) return ns.db[key] end

function Config.SetSetting(key, value)
  if type(ns.DEFAULTS[key]) ~= "boolean" then return "no such setting" end
  ns.db[key] = value and true or false
  ns.ConfigChanged()
end

function Config.SetThickness(value)
  local n = Guides.ParseThickness(value)
  if not n then
    return string.format("the thickness must be %d to %d pixels", Guides.MIN_THICKNESS, Guides.MAX_THICKNESS)
  end
  ns.db.thickness = n
  ns.ConfigChanged()
end
