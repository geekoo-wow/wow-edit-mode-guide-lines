# EditModeGuideLines

Guide lines for Edit Mode, on **retail WoW** and **WoW: Forever**. Create as
many vertical or horizontal guides as you like, in any color, and the game's
own snapping pulls frames onto them, the same way it snaps to the grid.

A guide is **centered**: it marks a band of the screen a given percentage
wide (or tall) and draws the two lines that bound it. A vertical 50% guide
on a 1000 px wide screen draws lines at 250 px and 750 px; a 0% guide is one
line through the middle, 100% the screen edges. That makes it easy to build
multi-area layouts on ultrawide screens: one guide marks the band the HUD
lives in, another the side areas, and every frame snaps to their edges.

> Prototype. Built against the Forever beta, which uses the Mainline
> (12.1-era) addon API, not the Classic one; retail uses the same API. The
> Edit Mode internals it relies on are identical on both clients.

## Supported clients

| Client | Interface |
|---|---|
| Retail (Midnight 12.x) | 120000, 120001, 120005, 120007, 120100 |
| WoW: Forever | 16001 |

The repo has one `EditModeGuideLines.toc` with `## Interface-Retail:` and
`## Interface-Forever:` lines; the release packager splits it into
`EditModeGuideLines_Mainline.toc` and `EditModeGuideLines_Camelot.toc`, which
each client picks by name. Classic flavors have no Edit Mode and aren't
supported. After a client patch, get the new number with
`/dump select(4, GetBuildInfo())` and add it to that client's line and to the
base `## Interface:` line.

## Install

1. Install it from CurseForge (project 1734653) with your addon manager, or
   download `EditModeGuideLines-<version>.zip` from the GitHub releases page
   and unzip it into the client's `Interface/AddOns/` (you should end up with
   `Interface/AddOns/EditModeGuideLines/`).
2. Open Edit Mode (Game Menu > Edit Mode). The **Guide lines** panel opens
   next to the Edit Mode window.
3. Make sure **Snap to Frames** is ticked in the Edit Mode window: that is
   the game's own switch for snapping, and the guides use it.

## Using it

In the panel, pick **Vertical** or **Horizontal**, type the width of the
band in percent, pick a color (click the swatch for the game's color picker,
with opacity) and press **Add**. Each guide in the list can be recolored,
flipped between vertical and horizontal, given a new percentage (type and
press Enter), hidden with its tick box, or deleted.

Then drag any frame as usual: when one of its edges or its center comes
within a few pixels of a guide, the red preview line appears and the frame
snaps to it on release, exactly like the grid. Both vertical and horizontal
guides can snap at once. Snapping anchors the frame to the screen, not to
the guide, so layouts don't depend on this addon being loaded, and deleting
a guide leaves every frame where it is.

Settings (in the panel and in Options > AddOns > EditModeGuideLines):

- **Enabled**: draw the guides and let frames snap to them.
- **Show outside Edit Mode**: keep the guides on screen all the time. By
  default they appear with the Edit Mode window and go away with it.
- **Draw above frames**: draw the guides over the UI instead of behind it.
- **Thickness**: line thickness in screen pixels (1 to 8).
- **Show the guide panel in Edit Mode** (settings only): whether the panel
  opens with Edit Mode. `/emg` or `/emg panel` opens it on demand.

Guides are saved per account (`EditModeGuideLinesDB`) and apply to every
Edit Mode layout.

## Slash commands

`/emg` (or `/guidelines`) opens the panel in Edit Mode, the settings
otherwise. Everything the panel does is also a command:

```
/emg add v 50 green        add a vertical guide: lines at 25% and 75%
/emg add h 33.3 #ff8800    add a horizontal guide, hex color
/emg list                  list the guides with their numbers
/emg del 2                 remove guide 2; /emg clear removes all
/emg percent 1 60          change guide 1's percentage
/emg flip 1                vertical <-> horizontal
/emg color 1 cyan          recolor guide 1
/emg toggle 1              hide or show guide 1
/emg on | off              enable or disable the addon
/emg show | hide           show the guides outside Edit Mode, or not
/emg above                 toggle drawing above the frames
/emg thickness 2           line thickness in pixels
/emg panel | editmode      open the panel, open Edit Mode
```

Colors: `red`, `green`, `blue`, `yellow`, `cyan`, `magenta`, `orange`,
`white`, or hex like `#ff8800` (`#ff880080` with alpha).

## How the snapping works

Edit Mode's snapping lives in Blizzard's `EditModeMagnetismManager`
(`Blizzard_EditMode/Shared/EditModeUtil.lua`). While the grid is shown, each
grid line is registered there as a coordinate in UIParent space; when a frame
is dropped (and while it is dragged, for the red preview line) the manager
finds the closest registered line within 8 screen pixels of the frame's
left/right/center (or top/bottom/center), and anchors the frame to UIParent
at that position.

This addon registers its guide lines in that same table, under keys of its
own, and puts them back whenever the grid rebuilds or clears the table. The
result behaves exactly like extra grid lines at the positions you chose:
edges and centers snap, the preview line shows, and the saved layout never
references the addon. The other extension point, registering frames as
"magnetic frames", was deliberately not used: snapping to one of those
anchors the frame *to that frame*, which would tie saved layouts to the
addon's guide frames.

Positions are rounded to whole screen pixels before they are drawn and
registered, so a snapped frame sits exactly on the drawn line.

## Known limitations

- Snapping needs Edit Mode's **Snap to Frames** option on, and happens within
  the game's 8 px magnetism range; the guides are not a magnet from across
  the screen.
- The game only snaps on release and picks the single closest target: if a
  frame edge is nearer to another frame than to a guide, it snaps to the
  frame.
- Guides are per account, not per layout.
- **Forever beta SavedVariables bug**: the beta saves SavedVariables on logout
  but doesn't load them on startup, so guides won't survive a restart there
  until Blizzard fixes it (the Forever Data Protect addon works around it).
- Not yet verified in game; the WoW API is mocked in the tests, and the
  panel is only checked for wiring, not layout.

## Development

```
lua5.1 tests/run.lua   # offline tests against a mocked WoW API
luacheck .             # lint
```

Layout:

- `Guides.lua`: the guide model — parsing, validation, line positions (no WoW API)
- `Config.lua`: the operations on the saved guides and settings (testable offline)
- `Lines.lua`: draws the lines; `Lines.Compute` turns guides into pixel-aligned coordinates
- `Snap.lua`: registers the lines with `EditModeMagnetismManager` and keeps them registered
- `UI.lua`: the Edit Mode panel and the settings category; draws widgets and calls `Config`
- `Commands.lua`: `/emg`
- `Core.lua`: defaults, SavedVariables (loading, normalizing), events, output helpers
- `Init.lua`: loaded last; registers the slash command
- `EditModeGuideLines.toc`: the file list and per-client interface versions

The tests live in `tests/`: `run.lua` loads the addon in TOC order against
`mock_wow.lua` (a stand-in for the WoW API, including the pieces of Blizzard's
Edit Mode the addon hooks) once per test, so each test starts from a fresh
addon and fresh SavedVariables.

Every push to a branch runs lint and tests, then builds the addon zip without
publishing it: download it from the run's **Artifacts** to try a build in game.

## Releasing

Push an annotated `v*` tag. CI runs lint and tests, generates the release
notes from `Changelog:` commit trailers, packages the addon with the
[BigWigs packager](https://github.com/BigWigsMods/packager), publishes a
GitHub release and uploads it to CurseForge (project 1734653, from
`X-Curse-Project-ID` in the TOC). A tag with `alpha` or `beta` in its name
(`v0.1.0-alpha.1`) is published as an alpha or beta file and a GitHub
pre-release; any other tag is a release. The commit convention and steps are
in [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT; see [LICENSE](LICENSE).
