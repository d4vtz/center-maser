"use strict";

/*
 * Center Master v0.1
 * KWin / Plasma 6
 *
 * Design:
 *   1 window : master uses all work area minus outerGap
 *   2 windows: master 67%, secondary 33%
 *   3+       : left / master / right = 30 / 40 / 30 by default
 *
 * State is authoritative. Geometry is only a projection of state.
 */

const Config = {
    outerGap: Number(readConfig("outerGap", 8)),
    innerGap: Number(readConfig("innerGap", 8)),
    smartGaps: Boolean(readConfig("smartGaps", false)),
    dualMasterRatio: Number(readConfig("dualMasterRatio", 0.67)),
    centerMasterRatio: Number(readConfig("centerMasterRatio", 0.40)),
    minMasterRatio: Number(readConfig("minMasterRatio", 0.30)),
    maxMasterRatio: Number(readConfig("maxMasterRatio", 0.70)),
    ratioStep: Number(readConfig("ratioStep", 0.05)),
    debug: Boolean(readConfig("debug", true))
};

function log() {
    if (!Config.debug) return;
    const args = Array.prototype.slice.call(arguments);
    print("[CenterMaster] " + args.join(" "));
}

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

function idOf(window) {
    if (!window) return "<null>";
    try {
        return String(window.internalId);
    } catch (_) {
        return String(window.resourceClass || window.caption || "<window>");
    }
}

function outputId(output) {
    if (!output) return "<no-output>";
    return String(output.name || output.model || "<output>");
}

function desktopId(desktop) {
    if (!desktop) return "<no-desktop>";
    return String(desktop.id || desktop.x11DesktopNumber || "<desktop>");
}

function removeFromArray(array, item) {
    const i = array.indexOf(item);
    if (i >= 0) array.splice(i, 1);
    return i;
}

function contains(array, item) {
    return array.indexOf(item) >= 0;
}

function makeRect(x, y, width, height) {
    return {
        x: Math.round(x),
        y: Math.round(y),
        width: Math.max(1, Math.round(width)),
        height: Math.max(1, Math.round(height))
    };
}

class WorkspaceState {
    constructor(output, desktop) {
        this.output = output;
        this.desktop = desktop;

        this.master = null;
        this.left = [];
        this.right = [];

        this.focused = null;
        this.focusHistory = [];
        this.nextSide = "right";

        this.dualMasterRatio = Config.dualMasterRatio;
        this.centerMasterRatio = Config.centerMasterRatio;
    }

    tiledCount() {
        return (this.master ? 1 : 0) + this.left.length + this.right.length;
    }

    zoneOf(window) {
        if (this.master === window) return { zone: "master", index: 0 };
        let i = this.left.indexOf(window);
        if (i >= 0) return { zone: "left", index: i };
        i = this.right.indexOf(window);
        if (i >= 0) return { zone: "right", index: i };
        return null;
    }

    add(window, preferredSlot) {
        if (!window) return;

        if (this.zoneOf(window)) return;

        if (!this.master) {
            this.master = window;
            return;
        }

        if (preferredSlot && preferredSlot.zone === "left") {
            const idx = clamp(preferredSlot.index, 0, this.left.length);
            this.left.splice(idx, 0, window);
            return;
        }

        if (preferredSlot && preferredSlot.zone === "right") {
            const idx = clamp(preferredSlot.index, 0, this.right.length);
            this.right.splice(idx, 0, window);
            return;
        }

        let side;
        if (this.left.length < this.right.length) {
            side = "left";
        } else if (this.right.length < this.left.length) {
            side = "right";
        } else {
            side = this.nextSide;
        }

        if (side === "left") {
            this.left.push(window);
            this.nextSide = "right";
        } else {
            this.right.push(window);
            this.nextSide = "left";
        }
    }

    focus(window) {
        if (!window) return;
        this.focused = window;
        removeFromArray(this.focusHistory, window);
        this.focusHistory.push(window);
        this.focusHistory = this.focusHistory.filter(w => this.zoneOf(w));
    }

    chooseReplacementMaster() {
        for (let i = this.focusHistory.length - 1; i >= 0; --i) {
            const w = this.focusHistory[i];
            const z = this.zoneOf(w);
            if (z && z.zone !== "master") return w;
        }

        if (this.right.length) return this.right[0];
        if (this.left.length) return this.left[0];
        return null;
    }

    remove(window) {
        const slot = this.zoneOf(window);
        if (!slot) return null;

        removeFromArray(this.focusHistory, window);
        if (this.focused === window) this.focused = null;

        if (slot.zone === "left") {
            this.left.splice(slot.index, 1);
            return slot;
        }

        if (slot.zone === "right") {
            this.right.splice(slot.index, 1);
            return slot;
        }

        // Removing master.
        const replacement = this.chooseReplacementMaster();
        this.master = null;

        if (replacement) {
            const rslot = this.zoneOf(replacement);
            if (rslot.zone === "left") this.left.splice(rslot.index, 1);
            if (rslot.zone === "right") this.right.splice(rslot.index, 1);
            this.master = replacement;
        }

        return slot;
    }

    promote(window) {
        const slot = this.zoneOf(window);
        if (!slot || slot.zone === "master") return false;

        const oldMaster = this.master;
        this.master = window;

        if (slot.zone === "left") this.left[slot.index] = oldMaster;
        if (slot.zone === "right") this.right[slot.index] = oldMaster;
        return true;
    }

    moveUp(window) {
        const slot = this.zoneOf(window);
        if (!slot || slot.zone === "master" || slot.index <= 0) return false;
        const stack = slot.zone === "left" ? this.left : this.right;
        [stack[slot.index - 1], stack[slot.index]] = [stack[slot.index], stack[slot.index - 1]];
        return true;
    }

    moveDown(window) {
        const slot = this.zoneOf(window);
        if (!slot || slot.zone === "master") return false;
        const stack = slot.zone === "left" ? this.left : this.right;
        if (slot.index >= stack.length - 1) return false;
        [stack[slot.index + 1], stack[slot.index]] = [stack[slot.index], stack[slot.index + 1]];
        return true;
    }

    moveLeft(window) {
        const slot = this.zoneOf(window);
        if (!slot) return false;

        if (slot.zone === "right") return this.promote(window);
        if (slot.zone === "master") {
            if (!this.left.length) return false;
            const target = this.left[0];
            return this.promote(target);
        }
        return false;
    }

    moveRight(window) {
        const slot = this.zoneOf(window);
        if (!slot) return false;

        if (slot.zone === "left") return this.promote(window);
        if (slot.zone === "master") {
            if (!this.right.length) return false;
            const target = this.right[0];
            return this.promote(target);
        }
        return false;
    }

    resizeMaster(delta) {
        if (this.tiledCount() < 2) return false;

        if (this.left.length && this.right.length) {
            this.centerMasterRatio = clamp(
                this.centerMasterRatio + delta,
                Config.minMasterRatio,
                Config.maxMasterRatio
            );
        } else {
            this.dualMasterRatio = clamp(
                this.dualMasterRatio + delta,
                Config.minMasterRatio,
                Config.maxMasterRatio
            );
        }
        return true;
    }

    resetRatios() {
        this.dualMasterRatio = Config.dualMasterRatio;
        this.centerMasterRatio = Config.centerMasterRatio;
    }

    validate() {
        const seen = [];

        const push = (w, where) => {
            if (!w) throw new Error("Null window in " + where);
            if (contains(seen, w)) throw new Error("Duplicate window in " + where);
            seen.push(w);
        };

        if (this.master) push(this.master, "master");
        for (const w of this.left) push(w, "left");
        for (const w of this.right) push(w, "right");

        if ((this.left.length || this.right.length) && !this.master) {
            throw new Error("Secondary windows exist without master");
        }

        return true;
    }
}

class ManagedWindow {
    constructor(window) {
        this.window = window;
        this.mode = "tiled";
        this.previousSlot = null;
        this.workspaceKey = null;
        this.userMoving = false;
        this.userResizing = false;
        this.lastAppliedGeometry = null;
    }
}

function calculateStackRects(windows, area, gap) {
    const result = [];
    const n = windows.length;
    if (!n) return result;

    const totalGap = gap * Math.max(0, n - 1);
    const available = Math.max(1, area.height - totalGap);
    const unit = available / n;

    let y = area.y;
    for (let i = 0; i < n; ++i) {
        const nextY = (i === n - 1)
            ? area.y + area.height
            : area.y + (i + 1) * unit + i * gap;

        const height = (i === n - 1)
            ? area.y + area.height - y
            : unit;

        result.push({
            window: windows[i],
            rect: makeRect(area.x, y, area.width, height)
        });

        y = nextY + (i === n - 1 ? 0 : gap);
    }

    return result;
}

function calculateLayout(state, workArea) {
    const count = state.tiledCount();
    if (!count || !state.master) return [];

    const outer = (Config.smartGaps && count === 1) ? 0 : Config.outerGap;
    const inner = Config.innerGap;

    const area = {
        x: workArea.x + outer,
        y: workArea.y + outer,
        width: Math.max(1, workArea.width - outer * 2),
        height: Math.max(1, workArea.height - outer * 2)
    };

    if (count === 1) {
        return [{ window: state.master, rect: makeRect(area.x, area.y, area.width, area.height) }];
    }

    const hasLeft = state.left.length > 0;
    const hasRight = state.right.length > 0;

    // Only one secondary side is occupied. Use the dual ratio, regardless
    // of how many windows happen to be stacked on that side.
    if (!(hasLeft && hasRight)) {
        const sideWindows = hasLeft ? state.left : state.right;
        const masterRatio = state.dualMasterRatio;
        const sideRatio = 1 - masterRatio;
        const contentWidth = area.width - inner;

        const masterWidth = contentWidth * masterRatio;
        const sideWidth = contentWidth * sideRatio;

        let masterArea, sideArea;
        if (hasLeft) {
            sideArea = { x: area.x, y: area.y, width: sideWidth, height: area.height };
            masterArea = {
                x: area.x + sideWidth + inner,
                y: area.y,
                width: masterWidth,
                height: area.height
            };
        } else {
            masterArea = { x: area.x, y: area.y, width: masterWidth, height: area.height };
            sideArea = {
                x: area.x + masterWidth + inner,
                y: area.y,
                width: sideWidth,
                height: area.height
            };
        }

        return [
            { window: state.master, rect: makeRect(masterArea.x, masterArea.y, masterArea.width, masterArea.height) },
            ...calculateStackRects(sideWindows, sideArea, inner)
        ];
    }

    // Both sides occupied: centered master.
    const masterRatio = state.centerMasterRatio;
    const sideRatio = (1 - masterRatio) / 2;
    const contentWidth = area.width - inner * 2;

    const leftWidth = contentWidth * sideRatio;
    const masterWidth = contentWidth * masterRatio;
    const rightWidth = contentWidth - leftWidth - masterWidth;

    const leftArea = {
        x: area.x,
        y: area.y,
        width: leftWidth,
        height: area.height
    };

    const masterArea = {
        x: area.x + leftWidth + inner,
        y: area.y,
        width: masterWidth,
        height: area.height
    };

    const rightArea = {
        x: masterArea.x + masterWidth + inner,
        y: area.y,
        width: rightWidth,
        height: area.height
    };

    return [
        ...calculateStackRects(state.left, leftArea, inner),
        { window: state.master, rect: makeRect(masterArea.x, masterArea.y, masterArea.width, masterArea.height) },
        ...calculateStackRects(state.right, rightArea, inner)
    ];
}

class Controller {
    constructor() {
        this.states = new Map();
        this.managed = new Map();
        this.applyingLayout = false;
    }

    windowKey(window) {
        return idOf(window);
    }

    stateKey(output, desktop) {
        return outputId(output) + "::" + desktopId(desktop);
    }

    currentDesktopFor(window) {
        if (window.desktops && window.desktops.length > 0) return window.desktops[0];
        // All-desktop windows are not tiled in v0.1.
        return null;
    }

    stateFor(window, create) {
        const output = window.output;
        const desktop = this.currentDesktopFor(window);
        if (!output || !desktop) return null;

        const key = this.stateKey(output, desktop);
        if (!this.states.has(key) && create) {
            this.states.set(key, new WorkspaceState(output, desktop));
        }
        return this.states.get(key) || null;
    }

    classify(window) {
        if (!window) return "ignored";
        if (!window.managed || window.deleted) return "ignored";
        if (window.desktopWindow || window.dock || window.specialWindow || window.popupWindow) return "ignored";
        if (window.skipTaskbar && window.skipPager) return "ignored";
        if (window.desktops && window.desktops.length === 0) return "floating";
        if (window.transient || window.modal) return "floating";
        return "tiled";
    }

    shouldLayoutWindow(window) {
        const m = this.managed.get(this.windowKey(window));
        return m && m.mode === "tiled" && !window.minimized && !window.fullScreen;
    }

    attachSignals(window) {
        const key = this.windowKey(window);

        if (window.minimizedChanged) {
            window.minimizedChanged.connect(() => {
                const m = this.managed.get(key);
                if (!m || m.mode !== "tiled") return;
                this.relayoutForWindow(window);
            });
        }

        if (window.fullScreenChanged) {
            window.fullScreenChanged.connect(() => this.relayoutForWindow(window));
        }

        if (window.outputChanged) {
            window.outputChanged.connect(() => this.rehomeWindow(window));
        }

        if (window.desktopsChanged) {
            window.desktopsChanged.connect(() => this.rehomeWindow(window));
        }

        if (window.interactiveMoveResizeStarted) {
            window.interactiveMoveResizeStarted.connect(() => {
                const m = this.managed.get(key);
                if (!m) return;
                m.userMoving = Boolean(window.move);
                m.userResizing = Boolean(window.resize);
            });
        }

        if (window.interactiveMoveResizeFinished) {
            window.interactiveMoveResizeFinished.connect(() => {
                const m = this.managed.get(key);
                if (!m) return;

                const wasMoving = m.userMoving;
                const wasResizing = m.userResizing;
                m.userMoving = false;
                m.userResizing = false;

                // v0.1: snap back after interactive manipulation.
                // Drop-zone reassignment is intentionally deferred to v0.2.
                if (wasMoving || wasResizing) this.relayoutForWindow(window);
            });
        }
    }

    addWindow(window) {
        const key = this.windowKey(window);
        if (this.managed.has(key)) return;

        const managed = new ManagedWindow(window);
        managed.mode = this.classify(window);
        this.managed.set(key, managed);
        this.attachSignals(window);

        if (managed.mode !== "tiled") {
            log("add", key, "mode=", managed.mode);
            return;
        }

        const state = this.stateFor(window, true);
        if (!state) {
            managed.mode = "floating";
            return;
        }

        state.add(window);
        state.focus(window);
        state.validate();
        managed.workspaceKey = this.stateKey(state.output, state.desktop);

        log("add tiled", key, managed.workspaceKey);
        this.relayout(state);
    }

    removeWindow(window) {
        const key = this.windowKey(window);
        const managed = this.managed.get(key);
        if (!managed) return;

        if (managed.mode === "tiled" && managed.workspaceKey) {
            const state = this.states.get(managed.workspaceKey);
            if (state) {
                state.remove(window);
                state.validate();
                this.relayout(state);
                if (state.tiledCount() === 0) this.states.delete(managed.workspaceKey);
            }
        }

        this.managed.delete(key);
        log("removed", key);
    }

    rehomeWindow(window) {
        const key = this.windowKey(window);
        const managed = this.managed.get(key);
        if (!managed || managed.mode !== "tiled") return;

        const oldKey = managed.workspaceKey;
        const oldState = oldKey ? this.states.get(oldKey) : null;
        const newState = this.stateFor(window, true);

        if (!newState) return;
        const newKey = this.stateKey(newState.output, newState.desktop);
        if (oldKey === newKey) return;

        if (oldState) {
            oldState.remove(window);
            oldState.validate();
            this.relayout(oldState);
            if (oldState.tiledCount() === 0) this.states.delete(oldKey);
        }

        newState.add(window);
        newState.focus(window);
        newState.validate();
        managed.workspaceKey = newKey;
        this.relayout(newState);
    }

    onActivated(window) {
        if (!window) return;
        const managed = this.managed.get(this.windowKey(window));
        if (!managed || managed.mode !== "tiled") return;
        const state = managed.workspaceKey ? this.states.get(managed.workspaceKey) : null;
        if (state) state.focus(window);
    }

    activeContext() {
        const window = workspace.activeWindow;
        if (!window) return null;
        const managed = this.managed.get(this.windowKey(window));
        if (!managed || managed.mode !== "tiled") return null;
        const state = managed.workspaceKey ? this.states.get(managed.workspaceKey) : null;
        if (!state) return null;
        return { window, managed, state };
    }

    relayoutForWindow(window) {
        const managed = this.managed.get(this.windowKey(window));
        if (!managed || !managed.workspaceKey) return;
        const state = this.states.get(managed.workspaceKey);
        if (state) this.relayout(state);
    }

    relayout(state) {
        if (!state || !state.master) return;

        const area = workspace.clientArea(KWin.WorkArea, state.output, state.desktop);
        const visibleState = new WorkspaceState(state.output, state.desktop);

        // Geometry excludes minimized windows but preserves the logical slots.
        const visible = w => {
            const m = this.managed.get(this.windowKey(w));
            return m && m.mode === "tiled" && !w.minimized && !w.fullScreen;
        };

        if (state.master && visible(state.master)) {
            visibleState.master = state.master;
        } else {
            const candidates = state.left.concat(state.right).filter(visible);
            if (candidates.length) visibleState.master = candidates[0];
        }

        if (!visibleState.master) return;

        visibleState.left = state.left.filter(w => visible(w) && w !== visibleState.master);
        visibleState.right = state.right.filter(w => visible(w) && w !== visibleState.master);
        visibleState.dualMasterRatio = state.dualMasterRatio;
        visibleState.centerMasterRatio = state.centerMasterRatio;

        const layout = calculateLayout(visibleState, area);

        this.applyingLayout = true;
        try {
            for (const item of layout) {
                const m = this.managed.get(this.windowKey(item.window));
                if (!m || m.userMoving || m.userResizing) continue;
                item.window.frameGeometry = item.rect;
                m.lastAppliedGeometry = item.rect;
            }
        } finally {
            this.applyingLayout = false;
        }
    }

    focusLeft() {
        const c = this.activeContext();
        if (!c) return;
        const z = c.state.zoneOf(c.window);

        let target = null;
        if (z.zone === "master" && c.state.left.length) target = this.closestVertical(c.window, c.state.left);
        if (z.zone === "right") target = c.state.master;
        if (target) workspace.activeWindow = target;
    }

    focusRight() {
        const c = this.activeContext();
        if (!c) return;
        const z = c.state.zoneOf(c.window);

        let target = null;
        if (z.zone === "master" && c.state.right.length) target = this.closestVertical(c.window, c.state.right);
        if (z.zone === "left") target = c.state.master;
        if (target) workspace.activeWindow = target;
    }

    focusUp() {
        const c = this.activeContext();
        if (!c) return;
        const z = c.state.zoneOf(c.window);
        if (z.zone === "master") return;
        const stack = z.zone === "left" ? c.state.left : c.state.right;
        if (z.index > 0) workspace.activeWindow = stack[z.index - 1];
    }

    focusDown() {
        const c = this.activeContext();
        if (!c) return;
        const z = c.state.zoneOf(c.window);
        if (z.zone === "master") return;
        const stack = z.zone === "left" ? c.state.left : c.state.right;
        if (z.index < stack.length - 1) workspace.activeWindow = stack[z.index + 1];
    }

    closestVertical(reference, candidates) {
        const cy = reference.frameGeometry.y + reference.frameGeometry.height / 2;
        let best = candidates[0];
        let bestDistance = Infinity;
        for (const w of candidates) {
            if (w.minimized) continue;
            const wy = w.frameGeometry.y + w.frameGeometry.height / 2;
            const d = Math.abs(wy - cy);
            if (d < bestDistance) {
                best = w;
                bestDistance = d;
            }
        }
        return best;
    }

    mutateActive(mutator) {
        const c = this.activeContext();
        if (!c) return;
        if (mutator(c.state, c.window)) {
            c.state.validate();
            this.relayout(c.state);
        }
    }

    promoteActive() {
        this.mutateActive((s, w) => s.promote(w));
    }

    moveLeft() {
        this.mutateActive((s, w) => s.moveLeft(w));
    }

    moveRight() {
        this.mutateActive((s, w) => s.moveRight(w));
    }

    moveUp() {
        this.mutateActive((s, w) => s.moveUp(w));
    }

    moveDown() {
        this.mutateActive((s, w) => s.moveDown(w));
    }

    resizeMaster(delta) {
        this.mutateActive((s) => s.resizeMaster(delta));
    }

    resetRatios() {
        const c = this.activeContext();
        if (!c) return;
        c.state.resetRatios();
        this.relayout(c.state);
    }

    toggleFloating() {
        const window = workspace.activeWindow;
        if (!window) return;

        const key = this.windowKey(window);
        const managed = this.managed.get(key);
        if (!managed || managed.mode === "ignored") return;

        if (managed.mode === "tiled") {
            const state = managed.workspaceKey ? this.states.get(managed.workspaceKey) : null;
            if (!state) return;

            managed.previousSlot = state.zoneOf(window);
            state.remove(window);
            state.validate();
            managed.mode = "floating";
            managed.workspaceKey = null;
            this.relayout(state);
            return;
        }

        if (managed.mode === "floating") {
            const state = this.stateFor(window, true);
            if (!state) return;
            managed.mode = "tiled";
            state.add(window, managed.previousSlot);
            state.focus(window);
            state.validate();
            managed.workspaceKey = this.stateKey(state.output, state.desktop);
            managed.previousSlot = null;
            this.relayout(state);
        }
    }
}

const controller = new Controller();

function registerShortcuts() {
    registerShortcut("CenterMasterFocusLeft", "Center Master: Focus left", "Meta+Left",
        () => controller.focusLeft());
    registerShortcut("CenterMasterFocusRight", "Center Master: Focus right", "Meta+Right",
        () => controller.focusRight());
    registerShortcut("CenterMasterFocusUp", "Center Master: Focus up", "Meta+Up",
        () => controller.focusUp());
    registerShortcut("CenterMasterFocusDown", "Center Master: Focus down", "Meta+Down",
        () => controller.focusDown());

    registerShortcut("CenterMasterMoveLeft", "Center Master: Move left", "Meta+Shift+Left",
        () => controller.moveLeft());
    registerShortcut("CenterMasterMoveRight", "Center Master: Move right", "Meta+Shift+Right",
        () => controller.moveRight());
    registerShortcut("CenterMasterMoveUp", "Center Master: Move up", "Meta+Shift+Up",
        () => controller.moveUp());
    registerShortcut("CenterMasterMoveDown", "Center Master: Move down", "Meta+Shift+Down",
        () => controller.moveDown());

    registerShortcut("CenterMasterPromote", "Center Master: Promote to master", "Meta+Return",
        () => controller.promoteActive());

    registerShortcut("CenterMasterFloat", "Center Master: Toggle floating", "Meta+F",
        () => controller.toggleFloating());

    registerShortcut("CenterMasterGrow", "Center Master: Grow master", "Meta+Ctrl+Right",
        () => controller.resizeMaster(Config.ratioStep));
    registerShortcut("CenterMasterShrink", "Center Master: Shrink master", "Meta+Ctrl+Left",
        () => controller.resizeMaster(-Config.ratioStep));
    registerShortcut("CenterMasterResetRatio", "Center Master: Reset ratios", "Meta+Ctrl+0",
        () => controller.resetRatios());
}

function bootstrap() {
    registerShortcuts();

    workspace.windowAdded.connect(window => controller.addWindow(window));
    workspace.windowRemoved.connect(window => controller.removeWindow(window));
    workspace.windowActivated.connect(window => controller.onActivated(window));

    if (workspace.currentDesktopChanged) {
        workspace.currentDesktopChanged.connect((_previous, current, output) => {
            // Re-layout the state that just became visible.
            const key = controller.stateKey(output, current);
            const state = controller.states.get(key);
            if (state) controller.relayout(state);
        });
    }

    if (workspace.screensChanged) {
        workspace.screensChanged.connect(() => {
            for (const state of controller.states.values()) controller.relayout(state);
        });
    }

    for (const window of workspace.stackingOrder) {
        controller.addWindow(window);
    }

    log("started", "states=", controller.states.size, "windows=", controller.managed.size);
}

bootstrap();
