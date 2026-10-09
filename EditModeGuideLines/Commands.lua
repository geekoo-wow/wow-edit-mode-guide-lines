-- Commands.lua — /emg (alias /guidelines). Everything the panel does, from
-- chat, plus a few quick toggles. All changes go through ns.Config.

local _, ns = ...
ns = ns or {}

local Commands = {}
ns.Commands = Commands

local Config, Guides = ns.Config, ns.Guides

local function onOff(v) return v and "|cff55ff55on|r" or "|cffff5555off|r" end

local HELP = {
  "/emg — open the guide panel (in Edit Mode) or the settings",
  "/emg add <v|h> <percent> [color] — add a guide, e.g. /emg add v 50 green",
  "/emg list — list the guides with their numbers",
  "/emg del <n> | clear — remove guide n, or all guides",
  "/emg percent <n> <percent> | flip <n> | color <n> <color> | toggle <n> — edit guide n",
  "/emg on | off — enable or disable the addon; show | hide — guides outside Edit Mode",
  "/emg above | thickness <px> | panel | editmode — drawing order, line thickness, the panel, open Edit Mode",
  "Colors: " .. table.concat(Guides.COLOR_NAMES, ", ") .. ", or hex like #ff8800",
}

-- "2. Vertical 50% (lines at 25% and 75%)", colored like the guide.
local function describe(i, g)
  return string.format("%d. %s%s|r%s", i, Guides.ColorCode(g.color), Guides.Describe(g), g.enabled and "" or " (off)")
end

-- The guide number in a command argument, or nil and a message.
local function guideIndex(arg)
  local i = tonumber(arg)
  if i and i == math.floor(i) and Config.Get(i) then return i end
  if Config.Count() == 0 then return nil, "there are no guides" end
  return nil, string.format("the guide number must be 1 to %d (see /emg list)", Config.Count())
end

-- Prints the error, or the result of done() when there is none.
local function report(err, done)
  if err then ns.Print(err) else ns.Print(done()) end
end

function Commands.Run(msg)
  local args = {}
  for word in tostring(msg or ""):gmatch("%S+") do args[#args + 1] = word end
  local cmd = (args[1] or ""):lower()

  if cmd == "" then
    if not ns.UI.Open() then ns.Print("the panel is unavailable; see /emg help") end
  elseif cmd == "help" or cmd == "?" then
    for _, line in ipairs(HELP) do ns.Print(line) end
  elseif cmd == "add" then
    local i, err = Config.Add(args[2], args[3], args[4])
    if err then
      ns.Print(err .. " — e.g. /emg add v 50 green")
    else
      ns.Print("added " .. describe(i, Config.Get(i)))
    end
  elseif cmd == "list" then
    local guides = Config.List()
    if #guides == 0 then
      ns.Print("no guides; add one with /emg add v 50 green")
    else
      for i, g in ipairs(guides) do ns.Print(describe(i, g)) end
    end
  elseif cmd == "del" or cmd == "delete" or cmd == "remove" or cmd == "rm" then
    local i, err = guideIndex(args[2])
    if err then ns.Print(err) return end
    local text = describe(i, Config.Get(i))
    Config.Remove(i)
    ns.Print("removed " .. text)
  elseif cmd == "clear" then
    local n = Config.Clear()
    ns.Print(n == 0 and "there were no guides" or string.format("removed %d guide%s", n, n == 1 and "" or "s"))
  elseif cmd == "percent" or cmd == "set" then
    local i, err = guideIndex(args[2])
    if err then ns.Print(err) return end
    report(Config.SetPercent(i, args[3]), function() return "now " .. describe(i, Config.Get(i)) end)
  elseif cmd == "flip" then
    local i, err = guideIndex(args[2])
    if err then ns.Print(err) return end
    report(Config.Flip(i), function() return "now " .. describe(i, Config.Get(i)) end)
  elseif cmd == "color" or cmd == "colour" then
    local i, err = guideIndex(args[2])
    if err then ns.Print(err) return end
    report(Config.SetColor(i, args[3]), function() return "now " .. describe(i, Config.Get(i)) end)
  elseif cmd == "toggle" then
    local i, err = guideIndex(args[2])
    if err then ns.Print(err) return end
    report(Config.Toggle(i), function() return "now " .. describe(i, Config.Get(i)) end)
  elseif cmd == "on" or cmd == "off" then
    Config.SetSetting("enabled", cmd == "on")
    ns.Print("guides " .. onOff(Config.GetSetting("enabled")))
  elseif cmd == "show" or cmd == "hide" then
    Config.SetSetting("showOutsideEditMode", cmd == "show")
    ns.Print("guides outside Edit Mode " .. onOff(Config.GetSetting("showOutsideEditMode")))
  elseif cmd == "above" then
    Config.SetSetting("aboveFrames", not Config.GetSetting("aboveFrames"))
    ns.Print("drawing above frames " .. onOff(Config.GetSetting("aboveFrames")))
  elseif cmd == "thickness" then
    report(Config.SetThickness(args[2]), function() return "thickness " .. Config.GetSetting("thickness") .. " px" end)
  elseif cmd == "panel" then
    if not ns.UI.ShowPanel() then ns.Print("the panel is unavailable on this client") end
  elseif cmd == "editmode" then
    ns.UI.OpenEditMode()
  else
    ns.Print("unknown command; see /emg help")
  end
end

function Commands.Init()
  _G.SLASH_EDITMODEGUIDELINES1 = "/emg"
  _G.SLASH_EDITMODEGUIDELINES2 = "/guidelines"
  _G.SlashCmdList = _G.SlashCmdList or {}
  _G.SlashCmdList.EDITMODEGUIDELINES = Commands.Run
end
