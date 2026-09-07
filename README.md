# Center Master v0.2

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
- `Meta+M`: toggle monocle for the current output + desktop
- `Meta+R`: reflow the current layout
- `Meta+-` / `Meta+=`: shrink / grow master
- `Meta+0`: reset master ratios

## Monocle

`Meta+M` toggles monocle without destroying the logical Center Master layout. All tiled windows keep their logical master/left/right positions and receive the same work-area geometry. Leaving monocle restores the previous layout.

## Drag and drop

When enabled, dragging a tiled window and releasing it reassigns it according to the horizontal drop zone:

- left edge -> LEFT stack
- center -> MASTER
- right edge -> RIGHT stack

The vertical release position chooses the insertion point inside a secondary stack. Dragging the master to a side promotes another tiled window so the workspace never loses its master.

## Application rules

The graphical configuration page exposes three rule lists:

- Always floating
- Ignored
- Force tiled

Rules are matched against `resourceClass`, `resourceName`, and `desktopFileName`. Separate entries with commas, semicolons, or line breaks. A wildcard `*` can be used at the beginning and/or end.

Structural KWin windows such as panels, desktop windows, popups, and other special windows remain ignored.

## Configuration

System Settings -> Window Management -> KWin Scripts -> Center Master -> Configure exposes:

- outer and inner gaps
- smart gaps
- dual-master and centered-master ratios
- ratio resize step
- drag/drop reassignment and edge-zone width
- per-application rules
- debug logging

KWin stores these values in `kwinrc`. Reload Center Master after changing settings so the running script reads the new values.

## Install / update

```bash
git pull
./install.sh
```

The installer replaces the local copy under `~/.local/share/kwin/scripts/org.d4vtz.centermaster`, enables the script, and asks KWin to reconfigure.

## Logs

```bash
journalctl --user -f | grep -i CenterMaster
```

Debug logging is disabled by default and can be enabled from the configuration page.

## Current scope

Implemented:

- state per output + virtual desktop
- stable master
- balanced left/right insertion
- keyboard navigation and movement
- master promotion
- floating toggle with previous-slot restoration
- minimized-window exclusion while preserving logical position
- fullscreen bypass
- output/desktop re-homing
- configurable gaps and ratios
- monocle
- explicit reflow
- drag/drop zone reassignment
- per-application floating/ignored/tiled rules
- graphical configuration UI
- WorkArea-aware geometry

Still intentionally deferred:

- weighted vertical resize of secondary windows
- alternate layouts such as dwindle or traditional master-stack
