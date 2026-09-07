# Center Master v0.1

KWin/Plasma 6 automatic tiling script implementing a centered-master layout.

## Geometry

- 1 tiled window: master occupies the work area minus `outerGap`.
- 2 windows: master 67%, secondary 33%.
- 3+ windows with both sides occupied: left/master/right = 30/40/30.
- If only one side is occupied, no empty column is reserved; the layout stays 67/33.
- Secondary windows stack vertically.
- `smartGaps` defaults to `false`, so outer gaps remain visible with a single window.

## Shortcuts

- Meta+Arrow: focus
- Meta+Shift+Arrow: reorder / cross zones
- Meta+Return: promote focused window to master
- Meta+F: toggle floating
- Meta+Ctrl+Left/Right: shrink/grow master
- Meta+Ctrl+0: reset ratios

## Current v0.1 behavior

Implemented:

- state per output + virtual desktop
- stable master
- left/right secondary stacks
- balanced insertion
- promotion
- directional focus
- directional reordering
- floating toggle
- minimized-window exclusion while preserving logical position
- fullscreen bypass
- output/desktop re-homing
- user-configurable gaps and ratios
- WorkArea-aware geometry

Deliberately deferred:

- drag-and-drop zone reassignment
- graphical configuration UI
- per-app user rules
- vertical weighted resize for secondary stacks
- monocle
- master-stack/dwindle alternate layouts

Interactive mouse move/resize currently snaps the tiled window back to the computed layout when the operation finishes.

## Install

```bash
kpackagetool6 --type=KWin/Script -i ./center-master-kwin-v0.1
kwriteconfig6 --file kwinrc --group Plugins --key org.d4vtz.centermasterEnabled true
qdbus org.kde.KWin /KWin reconfigure
```

If reinstalling after edits:

```bash
kpackagetool6 --type=KWin/Script -u org.d4vtz.centermaster
kpackagetool6 --type=KWin/Script -i ./center-master-kwin-v0.1
qdbus org.kde.KWin /KWin reconfigure
```

## Logs

```bash
journalctl --user -f | grep -i CenterMaster
```

KWin's scripting debug category may need to be enabled for script output to appear.

## Important

This is intentionally a first implementation, not yet a polished release. Test it in a disposable Plasma session/configuration before relying on it for daily work.
