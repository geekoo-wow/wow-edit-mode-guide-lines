-- tests/run.lua — tiny test runner. Usage (from the repo root):
--   lua5.1 tests/run.lua
-- Each test gets a fresh mock WoW API and a freshly loaded addon, read in
-- the order listed in the .toc so the file list can't drift.

package.path = "./tests/?.lua;" .. package.path
local mock = require("mock_wow")

local ADDON_DIR = "EditModeGuideLines/"

-- The single TOC; the packager splits it per client at release time.
local TOC = "EditModeGuideLines.toc"

local function tocLines(toc)
  local files, directives = {}, {}
  for line in io.lines(ADDON_DIR .. toc) do
    local key, value = line:match("^##%s*([%w%-_]+):%s*(.-)%s*$")
    if key then
      directives[key] = value
    elseif line:match("%.lua%s*$") and not line:match("^#") then
      files[#files + 1] = line:match("^%s*(.-)%s*$")
    end
  end
  return files, directives
end

local function tocFiles() return (tocLines(TOC)) end

-- Loads the addon like the client does: each file gets (addonName, ns), then
-- ADDON_LOADED (SavedVariables init) and PLAYER_LOGIN (Edit Mode wiring).
-- opts.noEditMode loads without Blizzard's Edit Mode objects, opts.noLogin
-- stops before PLAYER_LOGIN. Returns ns.
local function loadAddon(savedVars, opts)
  opts = opts or {}
  mock.reset()
  if opts.noEditMode then mock.removeEditMode() end
  _G.EditModeGuideLinesDB = savedVars
  local ns = {}
  for _, f in ipairs(tocFiles()) do
    local chunk = assert(loadfile(ADDON_DIR .. f))
    chunk("EditModeGuideLines", ns)
  end
  ns.frame:Fire("ADDON_LOADED", "EditModeGuideLines")
  if not opts.noLogin then ns.frame:Fire("PLAYER_LOGIN") end
  return ns
end

-- ---- assertions -----------------------------------------------------------

local T = { mock = mock, load = loadAddon, TOC = TOC, tocLines = tocLines, ADDON_DIR = ADDON_DIR }

local function fmt(v, depth)
  depth = (depth or 0) + 1
  if type(v) ~= "table" then return tostring(v) end
  if depth > 4 then return tostring(v) end
  local parts = {}
  local n = 0
  for i = 1, #v do parts[i] = fmt(v[i], depth); n = i end
  local keys = {}
  for k in pairs(v) do
    if type(k) ~= "number" or k > n or k < 1 or k ~= math.floor(k) then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. fmt(v[k], depth) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function deepEq(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not deepEq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

function T.eq(actual, expected, msg)
  if not deepEq(actual, expected) then
    error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
  end
end

function T.near(actual, expected, msg, tolerance)
  tolerance = tolerance or 1e-9
  if type(actual) ~= "number" or math.abs(actual - expected) > tolerance then
    error(string.format("%sexpected %s, got %s", msg and (msg .. ": ") or "", tostring(expected), tostring(actual)), 2)
  end
end

function T.truthy(v, msg) if not v then error(msg or "expected truthy value", 2) end end

-- The last chat line the addon printed, without color codes.
function T.lastPrinted()
  local line = mock.printed[#mock.printed]
  return line and line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") or nil
end

-- ---- run ------------------------------------------------------------------

local tests = {}
function T.test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

for _, f in ipairs({
  "tests/test_toc.lua", "tests/test_guides.lua", "tests/test_config.lua", "tests/test_lines.lua",
  "tests/test_snap.lua", "tests/test_ui.lua", "tests/test_commands.lua",
}) do
  assert(loadfile(f))(T)
end

local failed = 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    print("  ok    " .. t.name)
  else
    failed = failed + 1
    print("  FAIL  " .. t.name .. "\n        " .. tostring(err))
  end
end
print(string.format("\n%d tests, %d failed", #tests, failed))
os.exit(failed == 0 and 0 or 1)
