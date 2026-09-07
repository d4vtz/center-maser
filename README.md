# Center Master v0.5.0

KWin/Plasma 6 automatic tiling script with a stable centered master and two secondary stacks.

## Layout

- 1 tiled window: master fills the work area while respecting `outerGap`.
- 2 windows: master defaults to 67%, secondary to 33%.
- 3+ windows with both sides occupied: left/master/right defaults to 30/40/30.
- If only one secondary side is occupied, no empty column is reserved.
- Secondary windows stack vertically.
- `smartGaps` defaults to `false`, so a single window keeps its outer gap.

## Keyboard

- `Meta+H/J/K/L`: navigate
- `Meta+Shift+H/J/K/L`: move between stacks / reorder vertically
- `Meta+Return`: promote focused window to master
- `Meta+Space`: toggle floating
- `Meta+M`: toggle monocle
- `Meta+R`: reflow the current layout
- `Meta+-` / `Meta+=`: shrink / grow master
- `Meta+0`: reset master ratios
- `Meta+Ctrl+K`: increase the focused secondary window weight
- `Meta+Ctrl+J`: decrease the focused secondary window weight
- `Meta+Ctrl+Backspace`: reset the focused secondary stack to equal weights

## Weighted secondary stacks

Secondary windows no longer have to use equal heights.

For example:

```text
RIGHT

A  weight 1.0
B  weight 2.0
C  weight 1.0
```

produces approximately:

```text
┌────────┐
│   A    │ 25%
├────────┤
│        │
│   B    │ 50%
│        │
├────────┤
│   C    │ 25%
└────────┘
```

Resizing transfers weight between the focused window and its nearest vertical neighbor, so the total stack height remains constant. `minStackWeight` prevents a window from collapsing to an unusable size.

## Focus wrap

`focusWrap` is disabled by default.

When enabled:

- Up from the first item of a secondary stack focuses the last item.
- Down from the last item focuses the first item.
- Left from LEFT wraps toward RIGHT (or MASTER if RIGHT is empty).
- Right from RIGHT wraps toward LEFT (or MASTER if LEFT is empty).

This affects focus only. Window movement does not wrap.

## Insertion policies

`insertionPolicy` controls where newly tiled windows are inserted:

- `balanced`: default; fills the shorter stack and alternates on ties.
- `right`: always inserts new secondary windows in RIGHT.
- `left`: always inserts new secondary windows in LEFT.
- `focused-stack`: uses the stack of the previously focused secondary window when possible, otherwise falls back to balanced.

The first tiled window on an empty output + desktop always becomes MASTER.

## Monocle

`Meta+M` toggles monocle without destroying the logical Center Master layout. All tiled windows keep their logical master/left/right positions and receive the same work-area geometry. Leaving monocle restores the previous layout.

## Drag and drop

When enabled, dragging a tiled window now uses two complementary visual layers:

- a KZones-style full-screen overlay that shows LEFT / MASTER / RIGHT simultaneously and highlights the zone under the cursor;
- KWin's native outline, retained as the precise insertion preview inside the selected secondary stack.

The overlay is a separate declarative KWin companion script so the existing JavaScript tiling engine remains the single authority for layout state and drop behavior.

The target is resolved according to the horizontal drop zone:

- left edge -> LEFT stack
- center -> MASTER
- right edge -> RIGHT stack

The vertical release position chooses the insertion point inside a secondary stack.

## Application rules

The graphical configuration page exposes three rule lists:

- Always floating
- Ignored
- Force tiled

Rules are matched against `resourceClass`, `resourceName`, and `desktopFileName`. Separate entries with commas, semicolons, or line breaks. A wildcard `*` can be used at the beginning and/or end.

## Configuration

System Settings -> Window Management -> KWin Scripts -> Center Master -> Configure exposes:

- outer and inner gaps
- smart gaps
- master ratios
- master resize step
- weighted secondary resize step and minimum weight
- optional focus wrap
- insertion policy
- drag/drop reassignment and edge-zone width
- KZones-style overlay enablement, opacity, corner radius and visual gap
- per-application rules
- debug logging

Reload Center Master after changing settings so the running script reads the new values.

## Install / update

```bash
git pull
./install.sh
```

## Tests

The repository now contains a pure layout-core test suite for the v0.3 invariants:

```bash
node --test tests/*.test.mjs
```

GitHub Actions runs the same tests on pushes and pull requests.

The suite currently covers:

- balanced and explicit insertion policies
- focused-stack insertion
- weighted-height normalization
- vertical weight transfer and minimum weight
- optional focus wrapping

## Logs

```bash
journalctl --user -f | grep -i CenterMaster
```

Debug logging is disabled by default.

## Current scope

Implemented:

- state per output + virtual desktop
- stable master
- configurable insertion policy
- keyboard navigation and movement
- optional focus wrap
- master promotion
- weighted vertical secondary stacks
- floating toggle with previous-slot restoration
- minimized-window exclusion while preserving logical position
- fullscreen bypass
- output/desktop re-homing
- configurable gaps and ratios
- monocle
- explicit reflow
- drag/drop zone reassignment
- per-application floating/ignored/tiled rules
- native precise drag/drop insertion highlighting
- KZones-style LEFT / MASTER / RIGHT drag overlay
- graphical configuration UI
- WorkArea-aware geometry
- automated layout-core tests and CI

Still intentionally deferred:

- persistent per-desktop layout state across KWin restarts
- alternate layouts such as dwindle or traditional master-stack


## Center Master Accent decoration

v0.4 adds a companion Aurorae window decoration named `CenterMasterAccent`.

The active window border follows KDE's accent color through the Plasma SVG role `ColorScheme-Highlight`. Inactive borders use the current text/foreground color at reduced opacity, and the decoration background follows `ColorScheme-Background`. The button glyphs also use color-scheme roles, so the decoration follows light/dark and accent changes instead of hardcoding a palette.

Defaults:

- active border: 4 px by default, configurable from 1 to 12 px
- inactive border: 2 px by default, configurable from 0 to 12 px
- inactive border opacity: 0.42 by default, configurable from 0 to 1
- title area: inherited unchanged from the original Aurorae theme
- title/buttons: current KDE foreground
- no custom shadow; gaps remain responsible for visual separation

`install.sh` installs the decoration under:

```text
~/.local/share/aurorae/themes/CenterMasterAccent
```

and applies it through KWin's `org.kde.kdecoration2` configuration. Before changing the decoration for the first time, the installer stores the previous decoration plugin and theme in:

```text
~/.config/center-master/decoration-backup.conf
```

To restore the previous window decoration:

```bash
bash restore-decoration.sh
```

The SVG border colors follow KDE's current color scheme automatically. Aurorae stores title text colors in its rc file rather than as an SVG color role, so `install.sh` synchronizes those title colors from `kdeglobals` when the decoration is installed.


### v0.4.1 decoration correction

The first v0.4 implementation shipped a standalone Aurorae decoration. That changed the user's titlebar and button artwork, which was not the intended behavior.

v0.4.1 no longer ships its own decoration assets. Instead, `install.sh`:

1. recovers the decoration that was active before Center Master Accent;
2. if it is an Aurorae SVG theme, clones that exact theme into `CenterMasterAccent`;
3. keeps the original titlebar, buttons, shadows and geometry;
4. adds only Aurorae `innerborder` and `innerborder-inactive` FrameSvg elements;
5. uses `ColorScheme-Highlight` for the active border and a subdued `ColorScheme-Text` for inactive borders.

For an existing v0.4.0 install, the saved file `~/.config/center-master/decoration-backup.conf` is used as the source of truth, so rerunning `./install.sh` rebuilds the accent decoration from the original theme rather than from the temporary Center Master decoration.

If the original decoration is not an Aurorae SVG theme, Center Master now leaves it untouched instead of replacing it.


### v0.4.2 configurable border appearance

The cloned Aurorae border can now be adjusted from Center Master's configuration page:

- `activeBorderWidth`: default 4 px, range 1-12 px
- `inactiveBorderWidth`: default 2 px, range 0-12 px
- `inactiveBorderOpacity`: default 0.42, range 0-1

The active border continues to use `ColorScheme-Highlight`, so changing the KDE accent color does not require changing Center Master.

Because Aurorae border thickness is baked into the generated SVG, after changing these three settings rerun:

```bash
./install.sh
```

The installer reads the values from KWin's `Script-org.d4vtz.centermaster` configuration group, reclones the original Aurorae decoration, reapplies only the inner border, and reloads KWin.


### v0.5.0 KZones-style drag overlay

Center Master keeps the existing linear `master + left[] + right[]` state model. No binary tree was introduced.

The visual drag system is split deliberately:

1. `org.d4vtz.centermaster` continues to own state, reassignment and exact stack insertion.
2. `org.d4vtz.centermaster.overlay` is a declarative KWin script that only renders the three drop regions.

This prevents the visual layer from becoming a second tiling engine. The overlay follows the KDE highlight/accent color through Kirigami and is click-through (`outputOnly`), so it never steals the interactive move.

The companion overlay reads mirrored settings. Because it is a separate KWin package, rerun:

```bash
./install.sh
```

after changing overlay-specific appearance settings so the installer synchronizes them to the companion script.
