-- Guides.lua — the guide model: what a guide is, how user input is parsed and
-- validated, and where a guide's lines go. No WoW API, so it runs offline.
--
-- A guide is { orientation = "vertical" | "horizontal", percent = 0..100,
-- color = { r, g, b, a }, enabled = boolean }. It stands for a band of the
-- screen `percent` wide (or tall) centered on the screen, drawn as the two
-- lines that bound it: a vertical 50% guide on a 1000 px wide screen draws
-- lines at 250 px and 750 px. 0% is a single line through the middle, 100%
-- the screen edges.

local _, ns = ...
ns = ns or {}

local Guides = {}
ns.Guides = Guides

Guides.ORIENTATIONS = { "vertical", "horizontal" }
Guides.LABELS = { vertical = "Vertical", horizontal = "Horizontal" }

local ORIENTATION_ALIASES = {
  v = "vertical", vert = "vertical", vertical = "vertical",
  h = "horizontal", horiz = "horizontal", horizontal = "horizontal",
}

-- Named colors, accepted by the slash command and shown in the help.
Guides.COLORS = {
  red     = { r = 1,    g = 0.25, b = 0.25 },
  green   = { r = 0.25, g = 1,    b = 0.25 },
  blue    = { r = 0.35, g = 0.55, b = 1 },
  yellow  = { r = 1,    g = 0.9,  b = 0.2 },
  cyan    = { r = 0.2,  g = 1,    b = 1 },
  magenta = { r = 1,    g = 0.3,  b = 1 },
  orange  = { r = 1,    g = 0.6,  b = 0.1 },
  white   = { r = 1,    g = 1,    b = 1 },
}
Guides.COLOR_NAMES = { "red", "green", "blue", "yellow", "cyan", "magenta", "orange", "white" }
Guides.DEFAULT_COLOR = "green"

Guides.MIN_THICKNESS, Guides.MAX_THICKNESS = 1, 8

local function trim(s) return (s:match("^%s*(.-)%s*$")) end

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

local function round(v) return math.floor(v + 0.5) end

-- "v", "vert", "vertical", "h", "horiz", "horizontal" (any case) -> the
-- orientation, or nil.
function Guides.ParseOrientation(value)
  if type(value) ~= "string" then return nil end
  return ORIENTATION_ALIASES[trim(value:lower())]
end

function Guides.Other(orientation)
  return orientation == "vertical" and "horizontal" or "vertical"
end

-- A percentage from 0 to 100, kept to two decimals. Returns the number, or
-- nil and a message.
function Guides.ParsePercent(value)
  local n = tonumber(value)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then
    return nil, "the percentage must be a number"
  end
  if n < 0 or n > 100 then return nil, "the percentage must be between 0 and 100" end
  return round(n * 100) / 100
end

-- A whole number of pixels from MIN_THICKNESS to MAX_THICKNESS, or nil.
function Guides.ParseThickness(value)
  local n = tonumber(value)
  if n == nil or n ~= n or n == math.huge or n == -math.huge then return nil end
  n = round(n)
  if n < Guides.MIN_THICKNESS or n > Guides.MAX_THICKNESS then return nil end
  return n
end

-- A color { r, g, b, a } with components in 0..1, or nil. Accepts a color
-- name, hex ("#ff8800", "ff8800", "#ff880080" with alpha) or a table with
-- r, g, b (and optionally a) fields; components are clamped.
function Guides.ParseColor(value)
  if type(value) == "table" then
    local r, g, b, a = tonumber(value.r), tonumber(value.g), tonumber(value.b), tonumber(value.a)
    if not (r and g and b) then return nil end
    return { r = clamp01(r), g = clamp01(g), b = clamp01(b), a = a and clamp01(a) or 1 }
  end
  if type(value) ~= "string" then return nil end
  local s = trim(value:lower())
  local named = Guides.COLORS[s]
  if named then return { r = named.r, g = named.g, b = named.b, a = 1 } end
  local hex = s:match("^#?(%x+)$")
  if not hex or (#hex ~= 6 and #hex ~= 8) then return nil end
  local function channel(i) return tonumber(hex:sub(i, i + 1), 16) / 255 end
  return { r = channel(1), g = channel(3), b = channel(5), a = #hex == 8 and channel(7) or 1 }
end

-- "ff8800" (no alpha).
function Guides.ColorToHex(color)
  return string.format("%02x%02x%02x", round(color.r * 255), round(color.g * 255), round(color.b * 255))
end

-- The chat escape that colors the text after it.
function Guides.ColorCode(color)
  return "|cff" .. Guides.ColorToHex(color)
end

-- The preset's name when the color is one, otherwise "#rrggbb".
function Guides.ColorName(color)
  local hex = Guides.ColorToHex(color)
  for _, name in ipairs(Guides.COLOR_NAMES) do
    if Guides.ColorToHex(Guides.COLORS[name]) == hex then return name end
  end
  return "#" .. hex
end

-- A clean guide from anything (hand-edited SavedVariables included), or nil
-- when it can't be one. A missing or bad color becomes the default; anything
-- but `enabled = false` counts as enabled.
function Guides.Normalize(g)
  if type(g) ~= "table" then return nil end
  local orientation = Guides.ParseOrientation(g.orientation)
  local percent = Guides.ParsePercent(g.percent)
  if not orientation or not percent then return nil end
  return {
    orientation = orientation,
    percent = percent,
    color = Guides.ParseColor(g.color) or Guides.ParseColor(Guides.DEFAULT_COLOR),
    enabled = g.enabled ~= false,
  }
end

-- A new guide from user input. Returns the guide, or nil and a message.
function Guides.New(orientation, percent, color)
  local o = Guides.ParseOrientation(orientation)
  if not o then return nil, "the orientation must be vertical (v) or horizontal (h)" end
  local p, err = Guides.ParsePercent(percent)
  if not p then return nil, err end
  if color == nil then color = Guides.DEFAULT_COLOR end
  local c = Guides.ParseColor(color)
  if not c then
    return nil, "unknown color; use a name (" .. table.concat(Guides.COLOR_NAMES, ", ") .. ") or hex like #ff8800"
  end
  return { orientation = o, percent = p, color = c, enabled = true }
end

-- Same orientation and percentage: the same lines, whatever the color.
function Guides.Same(a, b)
  return a.orientation == b.orientation and a.percent == b.percent
end

-- The band's edges as fractions of the screen: 50 -> 0.25, 0.75.
function Guides.Fractions(percent)
  local half = percent / 200
  return 0.5 - half, 0.5 + half
end

-- Where the lines go along the guide's axis on a screen `size` long:
-- 50% of 1000 -> { 250, 750 }. A 0% guide is one line through the middle.
function Guides.LinePositions(percent, size)
  local lo, hi = Guides.Fractions(percent)
  if lo == hi then return { lo * size } end
  return { lo * size, hi * size }
end

-- "50", "33.3", "0": no trailing zeros.
function Guides.FormatPercent(p)
  local s = string.format("%.2f", p)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

-- "Vertical 50% (lines at 25% and 75%)"
function Guides.Describe(guide)
  local lo, hi = Guides.Fractions(guide.percent)
  local where
  if lo == hi then
    where = "one line at 50%"
  else
    where = string.format("lines at %s%% and %s%%", Guides.FormatPercent(lo * 100), Guides.FormatPercent(hi * 100))
  end
  return string.format("%s %s%% (%s)", Guides.LABELS[guide.orientation], Guides.FormatPercent(guide.percent), where)
end
