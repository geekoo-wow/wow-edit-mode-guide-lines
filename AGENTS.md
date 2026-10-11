# EditModeGuideLines — agent instructions

Follow the commit message and release conventions in [CONTRIBUTING.md](CONTRIBUTING.md). In particular: release notes are generated from `Changelog:` commit trailers — never create or edit `RELEASE_NOTES.md`.

WoW retail (Midnight 12.x) and WoW: Forever addon (Mainline-era API, Lua 5.1).
Guide lines for Edit Mode (and EllesmereUI's Unlock Mode): centered vertical
or horizontal pairs at a percentage of the screen that frames snap to. See
README.md for behaviour.

## Commands

- Test: `lua5.1 tests/run.lua` (must pass before committing)
- Lint: `luacheck .`

## Architecture rules

- `EditModeGuideLines/Guides.lua` must stay free of WoW API calls so it runs
  offline: it is the model (parsing, validation, where a guide's lines go).
- `Config.lua` is the only code that writes `ns.db`. `UI.lua` only draws
  widgets and `Commands.lua` only parses chat; both call `Config`, which ends
  every change with `ns.ConfigChanged()` (redraw lines, re-register snap
  targets, refresh the UI through `ns.OnConfigChanged`).
- `Lines.lua` is the only place that draws. `Lines.Compute` is pure: it turns
  guides plus a screen rect into pixel-aligned line coordinates in UIParent
  units; `Lines.Refresh` draws them and calls `Snap.Apply` and `Unlock.Apply`.
- `Snap.lua` is the only place that touches `EditModeMagnetismManager`. The
  mechanism, and why it is the right one, is in its header comment: guides go
  into Blizzard's `magneticGridLines` table (keyed by tables tagged
  `isGuideLine`), so frames snap their edges and centers to them and the
  saved layout anchors to UIParent. Never register the addon's own frames as
  magnetic frames (`RegisterFrame`): layouts would then be anchored to them.
- Contract between them: the coordinate Snap registers (and the strip Unlock
  places) is exactly the coordinate Lines drew (all come from
  `Lines.Targets()`), so a snapped frame lands on the drawn pixel. Keep
  positions rounded to whole screen pixels.
- `Unlock.lua` is the only place that touches `EllesmereUI`, and only through
  its public API: `RegisterUnlockModeListener`, `IsUnlockModeActive`,
  `GetUnlockModeTopBarAnchor`, `OpenUnlockMode`, `RegisterUnlockElements` and
  `MakeUnlockElement`. Never read its `_` fields or hook its functions (its
  PLUGINS_API.md forbids both, and it keeps its internals unreachable).
  Snapping works by registering each drawn line as a position-locked,
  hair-thin, screen-long element whose mover's left/bottom edge is on the
  line and whose other edges and center are off screen; the header comment
  explains the geometry EllesmereUI's `Sync` gives a tiny element. The mock
  in `tests/mock_wow.lua` mirrors the registration API and that geometry;
  keep both in step with `EUI_UnlockMode.lua` and
  `EUI_UnlockMode_Movers.lua` if those change. The addon must still load,
  and behave as before, without EllesmereUI.
- Blizzard's grid owns `magneticGridLines` while shown; the hooks on
  `RegisterGrid`/`UnregisterGrid` put the guides back. With nothing to
  register and the grid hidden, the table must be left `nil` again.
- Everything that needs Blizzard's Edit Mode frames waits for `PLAYER_LOGIN`
  (`Core.lua`), and every use of `EditModeManagerFrame`,
  `EditModeMagnetismManager` and `ColorPickerFrame` is guarded: the addon must
  still load (settings category, slash command, lines) when they're missing.
- SavedVariables are hand-editable, so nothing read from them may raise:
  `Core.lua` normalizes the shape at load (`Guides.Normalize` per guide),
  bad settings fall back to the defaults. Removing or renaming a field needs
  a migration there plus a version bump.
- New WoW globals the addon uses go in `.luacheckrc` `read_globals` and get a
  mock in `tests/mock_wow.lua`. The mock's `hooksecurefunc` really wraps, and
  its Edit Mode objects mirror Blizzard's table shapes; keep them in step
  with `Blizzard_EditMode/Shared/EditModeUtil.lua` if those change.
- `EditModeGuideLines/EditModeGuideLines.toc` is the only TOC and is
  authoritative for the file list; the test runner loads files in its order.
  Supported clients are the `## Interface-Retail:` and `## Interface-Forever:`
  lines; the packager splits them into per-client TOCs at release time
  (`enable-toc-creation`). The base `## Interface:` must list every per-client
  version (tests/test_toc.lua).
- Releases: pushing a `v*` tag runs `.github/workflows/release.yml`. Never tag
  or push tags unless asked.
