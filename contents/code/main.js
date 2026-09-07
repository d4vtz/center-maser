"use strict";

/*
 * Center Master v0.3
 * KWin / Plasma 6
 *
 * State is authoritative. Geometry is only a projection of state.
 */

function readBool(key, fallback) {
    const value = readConfig(key, fallback);
    if (typeof value === "boolean") return value;
    if (typeof value === "string") return value.toLowerCase() === "true";
    return Boolean(value);
}

function parseRuleList(value) {
    return String(value || "")
        .split(/[,;\n]/)
        .map(v => v.trim().toLowerCase())
        .filter(v => v.length > 0);
}

let Config = null;

function buildConfig(raw) {
    return {
        outerGap: Number(raw.outerGap),
        innerGap: Number(raw.innerGap),
        smartGaps: Boolean(raw.smartGaps),

        dualMasterRatio: Number(raw.dualMasterRatio),
        centerMasterRatio: Number(raw.centerMasterRatio),
        minMasterRatio: Number(raw.minMasterRatio),
        maxMasterRatio: Number(raw.maxMasterRatio),
        ratioStep: Number(raw.ratioStep),
        verticalResizeStep: Number(raw.verticalResizeStep),
        minStackWeight: Number(raw.minStackWeight),

        focusWrap: Boolean(raw.focusWrap),
        insertionPolicy: String(raw.insertionPolicy || "balanced").toLowerCase(),

        enableDragReassign: Boolean(raw.enableDragReassign),
        showDragHighlight: Boolean(raw.showDragHighlight),
        dropZoneRatio: Number(raw.dropZoneRatio),

        floatingApps: parseRuleList(raw.floatingApps || ""),
        ignoredApps: parseRuleList(raw.ignoredApps || ""),
        tiledApps: parseRuleList(raw.tiledApps || ""),

        debug: Boolean(raw.debug)
    };
}

let workspace = null;
let KWinApi = null;
let controller = null;

function log() {
    if (!Config.debug) return;
    const args = Array.prototype.slice.call(arguments);
    console.log("[CenterMaster] " + args.join(" "));
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

function globMatches(pattern, value) {
    if (!pattern || !value) return false;

    pattern = String(pattern).toLowerCase();
    value = String(value).toLowerCase();

    if (pattern === "*") return true;
    if (pattern.indexOf("*") < 0) return pattern === value;

    const starts = pattern.startsWith("*");
    const ends = pattern.endsWith("*");
    const core = pattern.replace(/^\*+|\*+$/g, "");

    if (starts && ends) return value.indexOf(core) >= 0;
    if (starts) return value.endsWith(core);
    if (ends) return value.startsWith(core);

    return pattern === value;
}

function windowAppIds(window) {
    return [
        window.resourceClass,
        window.resourceName,
        window.desktopFileName
    ]
        .filter(v => v !== undefined && v !== null && String(v).length > 0)
        .map(v => String(v).toLowerCase());
}

function matchesAppRule(window, patterns) {
    const ids = windowAppIds(window);

    for (const pattern of patterns) {
        for (const value of ids) {
            if (globMatches(pattern, value)) return true;
        }
    }

    return false;
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

        this.monocle = false;

        // Peso vertical por ventana secundaria. El master no usa este valor.
        this.weights = new Map();
    }

    weightOf(window) {
        return this.weights.has(window) ? this.weights.get(window) : 1.0;
    }

    setWeight(window, weight) {
        this.weights.set(window, Math.max(Config.minStackWeight, Number(weight) || 1.0));
    }

    ensureWeight(window) {
        if (!this.weights.has(window)) this.weights.set(window, 1.0);
    }

    stackForZone(zone) {
        if (zone === "left") return this.left;
        if (zone === "right") return this.right;
        return null;
    }

    tiledCount() {
        return (this.master ? 1 : 0) + this.left.length + this.right.length;
    }

    allWindows() {
        const windows = [];
        if (this.master) windows.push(this.master);
        return windows.concat(this.left, this.right);
    }

    zoneOf(window) {
        if (this.master === window) return { zone: "master", index: 0 };

        let i = this.left.indexOf(window);
        if (i >= 0) return { zone: "left", index: i };

        i = this.right.indexOf(window);
        if (i >= 0) return { zone: "right", index: i };

        return null;
    }

    add(window, preferredSlot, focusedWindow) {
        if (!window || this.zoneOf(window)) return;

        this.ensureWeight(window);

        if (!this.master) {
            this.master = window;
            return;
        }

        if (preferredSlot && preferredSlot.zone === "left") {
            this.left.splice(clamp(preferredSlot.index, 0, this.left.length), 0, window);
            return;
        }

        if (preferredSlot && preferredSlot.zone === "right") {
            this.right.splice(clamp(preferredSlot.index, 0, this.right.length), 0, window);
            return;
        }

        let side = null;
        const policy = Config.insertionPolicy;

        if (policy === "left") {
            side = "left";
        } else if (policy === "right") {
            side = "right";
        } else if (policy === "focused-stack" && focusedWindow) {
            const focusedSlot = this.zoneOf(focusedWindow);
            if (focusedSlot && (focusedSlot.zone === "left" || focusedSlot.zone === "right")) {
                side = focusedSlot.zone;
            }
        }

        if (!side) {
            if (this.left.length < this.right.length) side = "left";
            else if (this.right.length < this.left.length) side = "right";
            else side = this.nextSide;
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
        if (!window || !this.zoneOf(window)) return;

        this.focused = window;
        removeFromArray(this.focusHistory, window);
        this.focusHistory.push(window);
        this.focusHistory = this.focusHistory.filter(w => this.zoneOf(w));
    }

    chooseReplacementMaster() {
        for (let i = this.focusHistory.length - 1; i >= 0; --i) {
            const window = this.focusHistory[i];
            const slot = this.zoneOf(window);
            if (slot && slot.zone !== "master") return window;
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

        const replacement = this.chooseReplacementMaster();
        this.master = null;

        if (replacement) {
            const replacementSlot = this.zoneOf(replacement);
            if (replacementSlot.zone === "left") this.left.splice(replacementSlot.index, 1);
            if (replacementSlot.zone === "right") this.right.splice(replacementSlot.index, 1);
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
        const target = slot.index - 1;
        const other = stack[target];

        stack[target] = window;
        stack[slot.index] = other;
        return true;
    }

    moveDown(window) {
        const slot = this.zoneOf(window);
        if (!slot || slot.zone === "master") return false;

        const stack = slot.zone === "left" ? this.left : this.right;
        if (slot.index >= stack.length - 1) return false;

        const target = slot.index + 1;
        const other = stack[target];

        stack[target] = window;
        stack[slot.index] = other;
        return true;
    }

    resizeSecondary(window, delta) {
        const slot = this.zoneOf(window);
        if (!slot || slot.zone === "master") return false;

        const stack = this.stackForZone(slot.zone);
        if (!stack || stack.length < 2) return false;

        let neighborIndex = slot.index < stack.length - 1
            ? slot.index + 1
            : slot.index - 1;

        if (neighborIndex < 0) return false;

        const neighbor = stack[neighborIndex];

        this.ensureWeight(window);
        this.ensureWeight(neighbor);

        const currentWeight = this.weightOf(window);
        const neighborWeight = this.weightOf(neighbor);

        const nextCurrent = currentWeight + delta;
        const nextNeighbor = neighborWeight - delta;

        if (
            nextCurrent < Config.minStackWeight ||
            nextNeighbor < Config.minStackWeight
        ) {
            return false;
        }

        this.setWeight(window, nextCurrent);
        this.setWeight(neighbor, nextNeighbor);
        return true;
    }

    resetSecondaryWeights(zone) {
        const stack = this.stackForZone(zone);
        if (!stack) return false;
        for (const window of stack) this.setWeight(window, 1.0);
        return true;
    }

    moveLeft(window) {
        const slot = this.zoneOf(window);
        if (!slot || slot.zone !== "right") return false;

        this.right.splice(slot.index, 1);
        this.left.push(window);
        return true;
    }

    moveRight(window) {
        const slot = this.zoneOf(window);
        if (!slot || slot.zone !== "left") return false;

        this.left.splice(slot.index, 1);
        this.right.push(window);
        return true;
    }

    insertIntoStack(window, zone, index) {
        const current = this.zoneOf(window);
        if (!current || current.zone === "master") return false;

        if (current.zone === "left") this.left.splice(current.index, 1);
        if (current.zone === "right") this.right.splice(current.index, 1);

        const stack = zone === "left" ? this.left : this.right;
        stack.splice(clamp(index, 0, stack.length), 0, window);

        return true;
    }

    moveMasterToZone(zone, index) {
        if (!this.master || (zone !== "left" && zone !== "right")) return false;

        const oldMaster = this.master;
        const destination = zone === "left" ? this.left : this.right;
        const opposite = zone === "left" ? this.right : this.left;

        let replacement = null;

        if (destination.length) {
            replacement = destination[clamp(index, 0, destination.length - 1)];
        } else if (opposite.length) {
            replacement = opposite[0];
        }

        if (!replacement) return false;

        this.promote(replacement);

        const oldSlot = this.zoneOf(oldMaster);
        if (!oldSlot || oldSlot.zone === "master") return false;

        const oldStack = oldSlot.zone === "left" ? this.left : this.right;
        oldStack.splice(oldSlot.index, 1);

        const targetStack = zone === "left" ? this.left : this.right;
        targetStack.splice(clamp(index, 0, targetStack.length), 0, oldMaster);

        return true;
    }

    moveToZone(window, zone, index) {
        const slot = this.zoneOf(window);
        if (!slot) return false;

        if (zone === "master") {
            return slot.zone === "master" ? false : this.promote(window);
        }

        if (zone !== "left" && zone !== "right") return false;

        if (slot.zone === "master") {
            return this.moveMasterToZone(zone, index);
        }

        return this.insertIntoStack(window, zone, index);
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

    toggleMonocle() {
        this.monocle = !this.monocle;
        return this.monocle;
    }

    validate() {
        const seen = [];

        const push = (window, where) => {
            if (!window) throw new Error("Null window in " + where);
            if (contains(seen, window)) throw new Error("Duplicate window in " + where);
            seen.push(window);
        };

        if (this.master) push(this.master, "master");
        for (const window of this.left) push(window, "left");
        for (const window of this.right) push(window, "right");

        if ((this.left.length || this.right.length) && !this.master) {
            throw new Error("Secondary windows exist without master");
        }

        for (const window of this.left.concat(this.right)) {
            const weight = this.weightOf(window);
            if (!Number.isFinite(weight) || weight < Config.minStackWeight) {
                throw new Error("Invalid stack weight");
            }
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

function insetWorkArea(workArea, effectiveCount) {
    const outer = (Config.smartGaps && effectiveCount === 1)
        ? 0
        : Config.outerGap;

    return {
        x: workArea.x + outer,
        y: workArea.y + outer,
        width: Math.max(1, workArea.width - outer * 2),
        height: Math.max(1, workArea.height - outer * 2)
    };
}

function calculateStackRects(windows, area, gap, weightOf) {
    const result = [];
    const count = windows.length;
    if (!count) return result;

    const totalGap = gap * Math.max(0, count - 1);
    const available = Math.max(1, area.height - totalGap);

    const weights = windows.map(window => {
        const weight = weightOf ? Number(weightOf(window)) : 1.0;
        return Math.max(Config.minStackWeight, Number.isFinite(weight) ? weight : 1.0);
    });

    const totalWeight = Math.max(0.0001, weights.reduce((sum, weight) => sum + weight, 0));

    let y = area.y;
    let consumed = 0;

    for (let i = 0; i < count; ++i) {
        let height;

        if (i === count - 1) {
            height = area.y + area.height - y;
        } else {
            height = available * (weights[i] / totalWeight);
            consumed += height;
        }

        result.push({
            window: windows[i],
            rect: makeRect(area.x, y, area.width, height)
        });

        y += height + gap;
    }

    return result;
}

function calculateLayout(state, workArea) {
    const count = state.tiledCount();
    if (!count || !state.master) return [];

    const inner = Config.innerGap;
    const area = insetWorkArea(workArea, count);

    if (count === 1) {
        return [{
            window: state.master,
            rect: makeRect(area.x, area.y, area.width, area.height)
        }];
    }

    const hasLeft = state.left.length > 0;
    const hasRight = state.right.length > 0;

    if (!(hasLeft && hasRight)) {
        const sideWindows = hasLeft ? state.left : state.right;
        const contentWidth = area.width - inner;

        const masterWidth = contentWidth * state.dualMasterRatio;
        const sideWidth = contentWidth - masterWidth;

        let masterArea;
        let sideArea;

        if (hasLeft) {
            sideArea = {
                x: area.x,
                y: area.y,
                width: sideWidth,
                height: area.height
            };

            masterArea = {
                x: area.x + sideWidth + inner,
                y: area.y,
                width: masterWidth,
                height: area.height
            };
        } else {
            masterArea = {
                x: area.x,
                y: area.y,
                width: masterWidth,
                height: area.height
            };

            sideArea = {
                x: area.x + masterWidth + inner,
                y: area.y,
                width: sideWidth,
                height: area.height
            };
        }

        return [
            {
                window: state.master,
                rect: makeRect(masterArea.x, masterArea.y, masterArea.width, masterArea.height)
            },
            ...calculateStackRects(sideWindows, sideArea, inner, window => state.weightOf(window))
        ];
    }

    const contentWidth = area.width - inner * 2;
    const masterWidth = contentWidth * state.centerMasterRatio;
    const sideWidth = (contentWidth - masterWidth) / 2;

    const leftArea = {
        x: area.x,
        y: area.y,
        width: sideWidth,
        height: area.height
    };

    const masterArea = {
        x: area.x + sideWidth + inner,
        y: area.y,
        width: masterWidth,
        height: area.height
    };

    const rightArea = {
        x: masterArea.x + masterWidth + inner,
        y: area.y,
        width: sideWidth,
        height: area.height
    };

    return [
        ...calculateStackRects(state.left, leftArea, inner, window => state.weightOf(window)),
        {
            window: state.master,
            rect: makeRect(masterArea.x, masterArea.y, masterArea.width, masterArea.height)
        },
        ...calculateStackRects(state.right, rightArea, inner, window => state.weightOf(window))
    ];
}

function calculateMonocleLayout(windows, workArea) {
    if (!windows.length) return [];

    const area = insetWorkArea(workArea, 1);
    const rect = makeRect(area.x, area.y, area.width, area.height);

    return windows.map(window => ({ window, rect }));
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
        if (window.desktops && window.desktops.length > 0) {
            return window.desktops[0];
        }
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

        if (
            window.desktopWindow ||
            window.dock ||
            window.specialWindow ||
            window.popupWindow
        ) {
            return "ignored";
        }

        if (matchesAppRule(window, Config.ignoredApps)) return "ignored";
        if (matchesAppRule(window, Config.tiledApps)) return "tiled";
        if (matchesAppRule(window, Config.floatingApps)) return "floating";

        if (window.skipTaskbar && window.skipPager) return "ignored";
        if (window.desktops && window.desktops.length === 0) return "floating";
        if (window.transient || window.modal) return "floating";

        return "tiled";
    }

    attachSignals(window) {
        const key = this.windowKey(window);

        if (window.minimizedChanged) {
            window.minimizedChanged.connect(() => {
                const managed = this.managed.get(key);
                if (!managed || managed.mode !== "tiled") return;
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
                const managed = this.managed.get(key);
                if (!managed) return;

                managed.userMoving = Boolean(window.move);
                managed.userResizing = Boolean(window.resize);

                if (
                    managed.userMoving &&
                    managed.mode === "tiled" &&
                    Config.enableDragReassign &&
                    Config.showDragHighlight
                ) {
                    this.updateDragHighlight(window, window.frameGeometry);
                }
            });
        }

        if (window.interactiveMoveResizeStepped) {
            window.interactiveMoveResizeStepped.connect(geometry => {
                const managed = this.managed.get(key);

                if (
                    !managed ||
                    !managed.userMoving ||
                    managed.mode !== "tiled" ||
                    !Config.enableDragReassign ||
                    !Config.showDragHighlight
                ) {
                    return;
                }

                this.updateDragHighlight(window, geometry);
            });
        }

        if (window.interactiveMoveResizeFinished) {
            window.interactiveMoveResizeFinished.connect(() => {
                const managed = this.managed.get(key);
                if (!managed) return;

                const wasMoving = managed.userMoving;
                const wasResizing = managed.userResizing;

                managed.userMoving = false;
                managed.userResizing = false;

                if (Config.showDragHighlight) {
                    this.hideDragHighlight();
                }

                if (
                    wasMoving &&
                    Config.enableDragReassign &&
                    managed.mode === "tiled"
                ) {
                    this.handleDrop(window);
                    return;
                }

                if (wasMoving || wasResizing) {
                    this.relayoutForWindow(window);
                }
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

        const previousFocused = state.focused;
        state.add(window, null, previousFocused);
        state.focus(window);
        state.validate();

        managed.workspaceKey = this.stateKey(state.output, state.desktop);

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

                if (state.tiledCount() === 0) {
                    this.states.delete(managed.workspaceKey);
                }
            }
        }

        this.managed.delete(key);
    }

    rehomeWindow(window) {
        const managed = this.managed.get(this.windowKey(window));
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

            if (oldState.tiledCount() === 0) {
                this.states.delete(oldKey);
            }
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

        const state = managed.workspaceKey
            ? this.states.get(managed.workspaceKey)
            : null;

        if (state) state.focus(window);
    }

    activeContext() {
        const window = workspace.activeWindow;
        if (!window) return null;

        const managed = this.managed.get(this.windowKey(window));
        if (!managed || managed.mode !== "tiled") return null;

        const state = managed.workspaceKey
            ? this.states.get(managed.workspaceKey)
            : null;

        if (!state) return null;

        return { window, managed, state };
    }

    relayoutForWindow(window) {
        const managed = this.managed.get(this.windowKey(window));

        if (!managed || !managed.workspaceKey) return;

        const state = this.states.get(managed.workspaceKey);
        if (state) this.relayout(state);
    }

    visibleWindows(state) {
        return state.allWindows().filter(window => {
            const managed = this.managed.get(this.windowKey(window));

            return managed &&
                managed.mode === "tiled" &&
                !window.minimized &&
                !window.fullScreen;
        });
    }

    relayout(state) {
        if (!state || !state.master) return;

        const area = workspace.clientArea(
            KWinApi.WorkArea,
            state.output,
            state.desktop
        );

        const visible = this.visibleWindows(state);
        if (!visible.length) return;

        let layout;

        if (state.monocle) {
            layout = calculateMonocleLayout(visible, area);
        } else {
            const visibleState = new WorkspaceState(state.output, state.desktop);

            visibleState.master =
                visible.indexOf(state.master) >= 0
                    ? state.master
                    : visible[0];

            visibleState.left = state.left.filter(
                window =>
                    visible.indexOf(window) >= 0 &&
                    window !== visibleState.master
            );

            visibleState.right = state.right.filter(
                window =>
                    visible.indexOf(window) >= 0 &&
                    window !== visibleState.master
            );

            visibleState.dualMasterRatio = state.dualMasterRatio;
            visibleState.centerMasterRatio = state.centerMasterRatio;

            for (const window of visibleState.left.concat(visibleState.right)) {
                visibleState.setWeight(window, state.weightOf(window));
            }

            layout = calculateLayout(visibleState, area);
        }

        this.applyingLayout = true;

        try {
            for (const item of layout) {
                const managed = this.managed.get(
                    this.windowKey(item.window)
                );

                if (!managed || managed.userMoving || managed.userResizing) {
                    continue;
                }

                item.window.frameGeometry = item.rect;
                managed.lastAppliedGeometry = item.rect;
            }
        } finally {
            this.applyingLayout = false;
        }
    }

    closestVertical(reference, candidates) {
        const centerY =
            reference.frameGeometry.y +
            reference.frameGeometry.height / 2;

        let best = null;
        let bestDistance = Infinity;

        for (const window of candidates) {
            if (window.minimized) continue;

            const windowCenterY =
                window.frameGeometry.y +
                window.frameGeometry.height / 2;

            const distance = Math.abs(windowCenterY - centerY);

            if (distance < bestDistance) {
                best = window;
                bestDistance = distance;
            }
        }

        return best;
    }

    focusLeft() {
        const c = this.activeContext();
        if (!c) return;

        const slot = c.state.zoneOf(c.window);
        let target = null;

        if (slot.zone === "master" && c.state.left.length) {
            target = this.closestVertical(c.window, c.state.left);
        } else if (slot.zone === "right") {
            target = c.state.master;
        } else if (slot.zone === "left" && Config.focusWrap) {
            target = c.state.right.length
                ? this.closestVertical(c.window, c.state.right)
                : c.state.master;
        }

        if (target) workspace.activeWindow = target;
    }

    focusRight() {
        const c = this.activeContext();
        if (!c) return;

        const slot = c.state.zoneOf(c.window);
        let target = null;

        if (slot.zone === "master" && c.state.right.length) {
            target = this.closestVertical(c.window, c.state.right);
        } else if (slot.zone === "left") {
            target = c.state.master;
        } else if (slot.zone === "right" && Config.focusWrap) {
            target = c.state.left.length
                ? this.closestVertical(c.window, c.state.left)
                : c.state.master;
        }

        if (target) workspace.activeWindow = target;
    }

    focusUp() {
        const c = this.activeContext();
        if (!c) return;

        const slot = c.state.zoneOf(c.window);
        if (slot.zone === "master") return;

        const stack = slot.zone === "left" ? c.state.left : c.state.right;

        if (slot.index > 0) {
            workspace.activeWindow = stack[slot.index - 1];
        } else if (Config.focusWrap && stack.length > 1) {
            workspace.activeWindow = stack[stack.length - 1];
        }
    }

    focusDown() {
        const c = this.activeContext();
        if (!c) return;

        const slot = c.state.zoneOf(c.window);
        if (slot.zone === "master") return;

        const stack = slot.zone === "left" ? c.state.left : c.state.right;

        if (slot.index < stack.length - 1) {
            workspace.activeWindow = stack[slot.index + 1];
        } else if (Config.focusWrap && stack.length > 1) {
            workspace.activeWindow = stack[0];
        }
    }

    mutateActive(mutator) {
        const c = this.activeContext();
        if (!c) return;

        if (mutator(c.state, c.window)) {
            c.state.validate();
            this.relayout(c.state);

            workspace.activeWindow = c.window;
            c.state.focus(c.window);
        }
    }

    promoteActive() {
        this.mutateActive((state, window) => state.promote(window));
    }

    moveLeft() {
        this.mutateActive((state, window) => state.moveLeft(window));
    }

    moveRight() {
        this.mutateActive((state, window) => state.moveRight(window));
    }

    moveUp() {
        this.mutateActive((state, window) => state.moveUp(window));
    }

    moveDown() {
        this.mutateActive((state, window) => state.moveDown(window));
    }

    resizeMaster(delta) {
        this.mutateActive(state => state.resizeMaster(delta));
    }

    resizeSecondary(delta) {
        this.mutateActive((state, window) => state.resizeSecondary(window, delta));
    }

    resetSecondaryWeights() {
        const c = this.activeContext();
        if (!c) return;

        const slot = c.state.zoneOf(c.window);
        if (!slot || slot.zone === "master") return;

        if (c.state.resetSecondaryWeights(slot.zone)) {
            this.relayout(c.state);
            workspace.activeWindow = c.window;
            c.state.focus(c.window);
        }
    }

    resetRatios() {
        const c = this.activeContext();
        if (!c) return;

        c.state.resetRatios();
        this.relayout(c.state);

        workspace.activeWindow = c.window;
        c.state.focus(c.window);
    }

    toggleMonocle() {
        const c = this.activeContext();
        if (!c) return;

        c.state.toggleMonocle();
        this.relayout(c.state);

        workspace.activeWindow = c.window;
        c.state.focus(c.window);
    }

    reflowActive() {
        const c = this.activeContext();
        if (!c) return;

        c.state.validate();
        this.relayout(c.state);

        workspace.activeWindow = c.window;
        c.state.focus(c.window);
    }

    dropZoneForGeometry(geometry, area) {
        const centerX = geometry.x + geometry.width / 2;
        const relativeX = clamp(
            (centerX - area.x) / Math.max(1, area.width),
            0,
            1
        );

        const edge = clamp(Config.dropZoneRatio, 0.15, 0.45);

        if (relativeX < edge) return "left";
        if (relativeX > 1 - edge) return "right";
        return "master";
    }

    dragHighlightGeometry(zone, geometry, state, area) {
        const inner = Config.innerGap;
        const outer = Config.outerGap;
        const base = {
            x: area.x + outer,
            y: area.y + outer,
            width: Math.max(1, area.width - outer * 2),
            height: Math.max(1, area.height - outer * 2)
        };

        const edge = clamp(Config.dropZoneRatio, 0.15, 0.45);

        if (zone === "master") {
            const leftWidth = base.width * edge;
            const rightWidth = base.width * edge;

            return makeRect(
                base.x + leftWidth + inner,
                base.y,
                Math.max(1, base.width - leftWidth - rightWidth - inner * 2),
                base.height
            );
        }

        const stack = zone === "left" ? state.left : state.right;
        const filtered = stack.filter(w => w !== geometry.__window);
        const centerY = geometry.y + geometry.height / 2;
        const index = this.stackIndexForDrop(filtered, centerY);

        const zoneWidth = Math.max(1, base.width * edge - inner);
        const x = zone === "left"
            ? base.x
            : base.x + base.width - zoneWidth;

        if (!filtered.length) {
            return makeRect(x, base.y, zoneWidth, base.height);
        }

        const insertionY = this.insertionYForStack(filtered, index, base);
        const markerHeight = Math.max(4, Math.min(10, inner || 6));

        return makeRect(
            x,
            insertionY - markerHeight / 2,
            zoneWidth,
            markerHeight
        );
    }

    updateDragHighlight(window, geometry) {
        const managed = this.managed.get(this.windowKey(window));
        if (!managed || !managed.workspaceKey) {
            this.hideDragHighlight();
            return;
        }

        const state = this.states.get(managed.workspaceKey);
        if (!state) {
            this.hideDragHighlight();
            return;
        }

        const area = workspace.clientArea(
            KWinApi.WorkArea,
            state.output,
            state.desktop
        );

        const zone = this.dropZoneForGeometry(geometry, area);

        const geometryWithWindow = {
            x: geometry.x,
            y: geometry.y,
            width: geometry.width,
            height: geometry.height,
            __window: window
        };

        const highlight = this.dragHighlightGeometry(
            zone,
            geometryWithWindow,
            state,
            area
        );

        try {
            workspace.showOutline(highlight);
        } catch (error) {
            log("showOutline failed:", error);
        }
    }

    hideDragHighlight() {
        try {
            workspace.hideOutline();
        } catch (error) {
            log("hideOutline failed:", error);
        }
    }

    stackIndexForDrop(stack, centerY) {
        if (!stack.length) return 0;

        for (let i = 0; i < stack.length; ++i) {
            const geometry = stack[i].frameGeometry;
            const windowCenterY = geometry.y + geometry.height / 2;

            if (centerY < windowCenterY) {
                return i;
            }
        }

        return stack.length;
    }

    insertionYForStack(stack, index, area) {
        if (!stack.length) {
            return area.y + area.height / 2;
        }

        if (index <= 0) {
            return clamp(
                stack[0].frameGeometry.y,
                area.y,
                area.y + area.height
            );
        }

        if (index >= stack.length) {
            const last = stack[stack.length - 1].frameGeometry;
            return clamp(
                last.y + last.height,
                area.y,
                area.y + area.height
            );
        }

        const previous = stack[index - 1].frameGeometry;
        const next = stack[index].frameGeometry;

        return clamp(
            ((previous.y + previous.height) + next.y) / 2,
            area.y,
            area.y + area.height
        );
    }

    dragPreview(window) {
        const managed = this.managed.get(this.windowKey(window));

        if (!managed || managed.mode !== "tiled" || !managed.workspaceKey) {
            return null;
        }

        const state = this.states.get(managed.workspaceKey);
        if (!state) return null;

        const area = workspace.clientArea(
            KWinApi.WorkArea,
            state.output,
            state.desktop
        );

        const geometry = window.frameGeometry;
        const centerY = geometry.y + geometry.height / 2;
        const zone = this.dropZoneForGeometry(geometry, area);

        const left = state.left.filter(w => w !== window);
        const right = state.right.filter(w => w !== window);

        let index = -1;
        let insertionY = area.y + area.height / 2;

        if (zone === "left") {
            index = this.stackIndexForDrop(left, centerY);
            insertionY = this.insertionYForStack(left, index, area);
        } else if (zone === "right") {
            index = this.stackIndexForDrop(right, centerY);
            insertionY = this.insertionYForStack(right, index, area);
        }

        return {
            zone: zone,
            index: index,
            insertionY: insertionY,
            leftCount: left.length,
            rightCount: right.length,
            workArea: {
                x: area.x,
                y: area.y,
                width: area.width,
                height: area.height
            }
        };
    }

    handleDrop(window) {
        const managed = this.managed.get(this.windowKey(window));

        if (
            !managed ||
            managed.mode !== "tiled" ||
            !managed.workspaceKey
        ) {
            return;
        }

        const state = this.states.get(managed.workspaceKey);
        if (!state) return;

        const area = workspace.clientArea(
            KWinApi.WorkArea,
            state.output,
            state.desktop
        );

        const geometry = window.frameGeometry;

        const centerY = geometry.y + geometry.height / 2;
        const zone = this.dropZoneForGeometry(geometry, area);

        let index = 0;

        if (zone === "left") {
            index = this.stackIndexForDrop(
                state.left.filter(w => w !== window),
                centerY
            );
        } else if (zone === "right") {
            index = this.stackIndexForDrop(
                state.right.filter(w => w !== window),
                centerY
            );
        }

        if (state.moveToZone(window, zone, index)) {
            state.validate();
            state.focus(window);
        }

        this.relayout(state);
        workspace.activeWindow = window;
    }

    toggleFloating() {
        const window = workspace.activeWindow;
        if (!window) return;

        const managed = this.managed.get(this.windowKey(window));

        if (!managed || managed.mode === "ignored") return;

        if (managed.mode === "tiled") {
            const state = managed.workspaceKey
                ? this.states.get(managed.workspaceKey)
                : null;

            if (!state) return;

            managed.previousSlot = state.zoneOf(window);

            state.remove(window);
            state.validate();

            managed.mode = "floating";
            managed.workspaceKey = null;

            this.relayout(state);
            workspace.activeWindow = window;
            return;
        }

        if (managed.mode === "floating") {
            const state = this.stateFor(window, true);
            if (!state) return;

            managed.mode = "tiled";

            state.add(window, managed.previousSlot);
            state.focus(window);
            state.validate();

            managed.workspaceKey = this.stateKey(
                state.output,
                state.desktop
            );

            managed.previousSlot = null;

            this.relayout(state);
            workspace.activeWindow = window;
        }
    }
}



function bootstrap() {

    workspace.windowAdded.connect(window => controller.addWindow(window));
    workspace.windowRemoved.connect(window => controller.removeWindow(window));
    workspace.windowActivated.connect(window => controller.onActivated(window));

    if (workspace.currentDesktopChanged) {
        workspace.currentDesktopChanged.connect((_previous, current, output) => {
            const key = controller.stateKey(output, current);
            const state = controller.states.get(key);
            if (state) controller.relayout(state);
        });
    }

    if (workspace.screensChanged) {
        workspace.screensChanged.connect(() => {
            for (const state of controller.states.values()) {
                controller.relayout(state);
            }
        });
    }

    for (const window of workspace.stackingOrder) {
        controller.addWindow(window);
    }

    log(
        "started",
        "states=",
        controller.states.size,
        "windows=",
        controller.managed.size
    );
}


function initialize(workspaceObject, kwinObject, rawConfig) {
    workspace = workspaceObject;
    KWinApi = kwinObject;
    Config = buildConfig(rawConfig);

    controller = new Controller();
    bootstrap();

    log("initialized from declarative package");
}

function focusLeft() { if (controller) controller.focusLeft(); }
function focusDown() { if (controller) controller.focusDown(); }
function focusUp() { if (controller) controller.focusUp(); }
function focusRight() { if (controller) controller.focusRight(); }

function moveLeft() { if (controller) controller.moveLeft(); }
function moveDown() { if (controller) controller.moveDown(); }
function moveUp() { if (controller) controller.moveUp(); }
function moveRight() { if (controller) controller.moveRight(); }

function promoteActive() { if (controller) controller.promoteActive(); }
function toggleFloating() { if (controller) controller.toggleFloating(); }
function toggleMonocle() { if (controller) controller.toggleMonocle(); }
function reflowActive() { if (controller) controller.reflowActive(); }

function secondaryGrow() {
    if (controller && Config) controller.resizeSecondary(Config.verticalResizeStep);
}
function secondaryShrink() {
    if (controller && Config) controller.resizeSecondary(-Config.verticalResizeStep);
}
function secondaryReset() { if (controller) controller.resetSecondaryWeights(); }

function shrinkMaster() {
    if (controller && Config) controller.resizeMaster(-Config.ratioStep);
}
function growMaster() {
    if (controller && Config) controller.resizeMaster(Config.ratioStep);
}
function resetRatios() { if (controller) controller.resetRatios(); }

function dragPreview(window) {
    if (!controller || !window) return null;
    return controller.dragPreview(window);
}
