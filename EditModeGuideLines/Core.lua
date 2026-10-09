-- Core.lua — namespace, defaults, SavedVariables, events and output.

local ADDON, ns = ...
ns = ns or {}
ns.name = ADDON or "EditModeGuideLines"

-- Default configuration. Kept in code (not only in SavedVariables) because the
-- Forever beta currently fails to load SavedVariables at startup; with these
-- defaults the addon still works after every restart, just without guides.
ns.DEFAULTS = {
  version = 1,
  enabled = true,              -- draw the guides and let frames snap to them
  showOutsideEditMode = false, -- guides are visible only while Edit Mode is open
  aboveFrames = false,         -- draw the guides over the UI instead of behind it
  thickness = 1,               -- line thickness, in screen pixels
  showPanel = true,            -- open the guide panel together with Edit Mode
  guides = {},                 -- the guides; Guides.lua describes the shape
}

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end
ns.DeepCopy = deepCopy

-- Fill in missing keys from the defaults without clobbering user settings; a
-- table setting that isn't a table (hand-edited SavedVariables) counts as
-- missing. The guide list is the user's: once it is a list, it is left alone.
local function mergeDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil or (type(v) == "table" and type(db[k]) ~= "table") then
      db[k] = deepCopy(v)
    elseif type(v) == "table" and k ~= "guides" then
      mergeDefaults(db[k], v)
    end
  end
end

-- SavedVariables can be edited by hand, so nothing read from them may raise.
-- A setting of the wrong type counts as missing; a guide that can't be made
-- sense of is dropped (Guides.Normalize), the rest keep their order.
local function normalize(db)
  for k, v in pairs(ns.DEFAULTS) do
    if type(v) == "boolean" and type(db[k]) ~= "boolean" then db[k] = nil end
  end
  db.thickness = ns.Guides.ParseThickness(db.thickness)
  if type(db.guides) == "table" then
    local indexes = {}
    for k in pairs(db.guides) do
      if type(k) == "number" then indexes[#indexes + 1] = k end
    end
    table.sort(indexes)
    local list = {}
    for _, k in ipairs(indexes) do
      local guide = ns.Guides.Normalize(db.guides[k])
      if guide then list[#list + 1] = guide end
    end
    db.guides = list
  else
    db.guides = nil
  end
end

local function migrate(db)
  -- Nothing to migrate yet; the version is recorded for later changes.
  db.version = ns.DEFAULTS.version
end

function ns.InitDB()
  if type(_G.EditModeGuideLinesDB) ~= "table" then _G.EditModeGuideLinesDB = {} end
  local db = _G.EditModeGuideLinesDB
  normalize(db)
  migrate(db)
  mergeDefaults(db, ns.DEFAULTS)
  ns.db = db
  return db
end

-- Called after any change to the saved config: redraws the lines (which
-- re-registers the snap targets) and tells the UI to redraw what's showing.
function ns.ConfigChanged()
  if ns.Lines then ns.Lines.Refresh() end
  if ns.OnConfigChanged then ns.OnConfigChanged() end
end

function ns.Print(msg)
  local frame = _G.DEFAULT_CHAT_FRAME
  local line = "|cff33ccffGuideLines|r: " .. tostring(msg)
  if frame then frame:AddMessage(line) else print(line) end
end

-- ---- events ---------------------------------------------------------------

local frame = CreateFrame("Frame")
ns.frame = frame
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("UI_SCALE_CHANGED")
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")

-- Everything that needs Blizzard's Edit Mode frames waits for login, when
-- all of the default UI has loaded.
local function onLogin()
  if ns.loggedIn then return end
  ns.loggedIn = true
  ns.Lines.Init()
  ns.Snap.Init()
  ns.UI.Init()
end

frame:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" then
    if arg ~= ns.name then return end
    frame:UnregisterEvent("ADDON_LOADED")
    ns.InitDB()
    if _G.IsLoggedIn and _G.IsLoggedIn() then onLogin() end
  elseif event == "PLAYER_LOGIN" then
    if ns.db then onLogin() end
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    if ns.Lines then ns.Lines.Refresh() end
  end
end)
