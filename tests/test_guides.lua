-- tests/test_guides.lua — the pure guide model: parsing, validation and where
-- a guide's lines go.

local T = ...
local test, eq, truthy, near = T.test, T.eq, T.truthy, T.near

local function G() return T.load({}, { noLogin = true }).Guides end

test("a 50% guide on a 1000 px wide screen puts its lines at 250 and 750", function()
  local Guides = G()
  eq({ Guides.Fractions(50) }, { 0.25, 0.75 })
  eq(Guides.LinePositions(50, 1000), { 250, 750 })
end)

test("0% is a single line through the middle, 100% the screen edges", function()
  local Guides = G()
  eq(Guides.LinePositions(0, 1000), { 500 })
  eq(Guides.LinePositions(100, 1000), { 0, 1000 })
  eq(Guides.LinePositions(20, 600), { 240, 360 })
end)

test("percentages are numbers from 0 to 100, kept to two decimals", function()
  local Guides = G()
  eq(Guides.ParsePercent("50"), 50)
  eq(Guides.ParsePercent(33.333), 33.33)
  eq(Guides.ParsePercent(" 12.5 "), 12.5)
  eq(Guides.ParsePercent(0), 0)
  eq(Guides.ParsePercent(100), 100)
  for _, bad in ipairs({ "101", -1, "abc", "", "1e400", "nan" }) do
    local p, err = Guides.ParsePercent(bad)
    eq(p, nil, tostring(bad))
    truthy(err and err:match("percentage"), "message for " .. tostring(bad))
  end
  eq(Guides.ParsePercent(nil), nil)
end)

test("orientations accept short forms in any case", function()
  local Guides = G()
  for _, v in ipairs({ "v", "V", "vert", "Vertical", " vertical " }) do eq(Guides.ParseOrientation(v), "vertical", v) end
  for _, h in ipairs({ "h", "horiz", "HORIZONTAL" }) do eq(Guides.ParseOrientation(h), "horizontal", h) end
  eq(Guides.ParseOrientation("diagonal"), nil)
  eq(Guides.ParseOrientation(nil), nil)
  eq(Guides.ParseOrientation(1), nil)
  eq(Guides.Other("vertical"), "horizontal")
  eq(Guides.Other("horizontal"), "vertical")
end)

test("colors parse from names, hex (with or without alpha) and tables", function()
  local Guides = G()
  local green = Guides.ParseColor("green")
  eq(green, { r = 0.25, g = 1, b = 0.25, a = 1 })
  eq(Guides.ParseColor(" Green "), green)
  local c = Guides.ParseColor("#ff8800")
  near(c.r, 1); near(c.g, 136 / 255); near(c.b, 0); near(c.a, 1)
  eq(Guides.ParseColor("FF8800"), c)
  near(Guides.ParseColor("#ff880080").a, 128 / 255)
  eq(Guides.ParseColor({ r = 2, g = -1, b = "0.5" }), { r = 1, g = 0, b = 0.5, a = 1 }, "clamped")
  eq(Guides.ParseColor({ r = 1, g = 1, b = 1, a = 0.5 }).a, 0.5)
  for _, bad in ipairs({ "nope", "#12345", "#1234567", "", { r = 1 }, 7 }) do
    eq(Guides.ParseColor(bad), nil, tostring(bad))
  end
end)

test("colors round-trip through hex and are named when they're presets", function()
  local Guides = G()
  eq(Guides.ColorToHex({ r = 1, g = 136 / 255, b = 0 }), "ff8800")
  eq(Guides.ColorToHex(Guides.ParseColor("#123456")), "123456")
  eq(Guides.ColorCode({ r = 1, g = 0, b = 0 }), "|cffff0000")
  eq(Guides.ColorName(Guides.ParseColor("green")), "green")
  eq(Guides.ColorName(Guides.ParseColor("#123456")), "#123456")
end)

test("Normalize drops guides it can't make sense of and fills in the color", function()
  local Guides = G()
  eq(Guides.Normalize({ orientation = "v", percent = "50" }),
    { orientation = "vertical", percent = 50, color = Guides.ParseColor("green"), enabled = true })
  eq(Guides.Normalize({ orientation = "horizontal", percent = 10, color = "red", enabled = false }).enabled, false)
  eq(Guides.Normalize({ orientation = "horizontal", percent = 10, enabled = "yes" }).enabled, true)
  eq(Guides.Normalize({ orientation = "horizontal", percent = 10, color = "nope" }).color, Guides.ParseColor("green"))
  eq(Guides.Normalize({ orientation = "d", percent = 10 }), nil)
  eq(Guides.Normalize({ orientation = "v", percent = 110 }), nil)
  eq(Guides.Normalize({ orientation = "v" }), nil)
  eq(Guides.Normalize("v 50"), nil)
  eq(Guides.Normalize(nil), nil)
end)

test("New validates its inputs and defaults the color", function()
  local Guides = G()
  local g = Guides.New("v", "50")
  eq(g, { orientation = "vertical", percent = 50, color = Guides.ParseColor("green"), enabled = true })
  eq(Guides.New("h", 25, "#ff0000").color, { r = 1, g = 0, b = 0, a = 1 })
  local _, err = Guides.New("x", 50)
  truthy(err:match("orientation"))
  _, err = Guides.New("v", "lots")
  truthy(err:match("percentage"))
  _, err = Guides.New("v", 50, "nope")
  truthy(err:match("color"))
  truthy(Guides.Same(Guides.New("v", 50), Guides.New("v", 50, "red")))
  truthy(not Guides.Same(Guides.New("v", 50), Guides.New("h", 50)))
end)

test("thickness is a whole number of pixels within range", function()
  local Guides = G()
  eq(Guides.ParseThickness("2"), 2)
  eq(Guides.ParseThickness(2.6), 3)
  eq(Guides.ParseThickness(0), nil)
  eq(Guides.ParseThickness(9), nil)
  eq(Guides.ParseThickness("x"), nil)
  eq(Guides.ParseThickness(nil), nil)
end)

test("Describe and FormatPercent read naturally", function()
  local Guides = G()
  eq(Guides.FormatPercent(50), "50")
  eq(Guides.FormatPercent(33.3), "33.3")
  eq(Guides.FormatPercent(0), "0")
  eq(Guides.FormatPercent(100), "100")
  eq(Guides.Describe(Guides.New("v", 50)), "Vertical 50% (lines at 25% and 75%)")
  eq(Guides.Describe(Guides.New("h", 40)), "Horizontal 40% (lines at 30% and 70%)")
  eq(Guides.Describe(Guides.New("h", 0)), "Horizontal 0% (one line at 50%)")
end)
