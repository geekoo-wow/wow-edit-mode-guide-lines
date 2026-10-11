std = "lua51"
max_line_length = 140
codes = true
self = false -- unused self in methods and script handlers is normal WoW style

-- WoW API used by the addon.
read_globals = {
  "CreateFrame", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME",
  "hooksecurefunc", "wipe", "GetPhysicalScreenSize", "IsLoggedIn", "InCombatLockdown", "ShowUIPanel",
  "EditModeManagerFrame", "EditModeMagnetismManager", "ColorPickerFrame", "Settings",
  "EllesmereUI",
}

globals = { "EditModeGuideLinesDB", "SlashCmdList", "SLASH_EDITMODEGUIDELINES1", "SLASH_EDITMODEGUIDELINES2" }

files["tests/"] = {
  -- The mock defines the WoW API.
  globals = { "_G" },
  allow_defined_top = true,
  ignore = { "111", "112", "121", "122" },
}
