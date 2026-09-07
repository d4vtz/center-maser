import QtQuick
import org.kde.kwin
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import "../code/main.js" as Logic

Item {
    id: root

    property rect workArea: Qt.rect(0, 0, 1920, 1080)
    property var dragWindow: null
    property bool dragging: false
    property string activeZone: ""
    property int leftWindowCount: 0
    property int rightWindowCount: 0
    property int activeSlot: -1

    readonly property bool overlayEnabled: boolConfig("showZoneOverlay", true)
    readonly property real dropZoneRatio: Math.min(Math.max(KWin.readConfig("dropZoneRatio", 0.30), 0.15), 0.45)
    readonly property real activeOpacity: Math.min(Math.max(KWin.readConfig("zoneOverlayActiveOpacity", 0.30), 0.05), 0.70)
    readonly property real inactiveOpacity: Math.min(Math.max(KWin.readConfig("zoneOverlayInactiveOpacity", 0.10), 0.02), 0.35)
    readonly property int cornerRadius: Math.min(Math.max(KWin.readConfig("zoneOverlayCornerRadius", 12), 0), 32)
    readonly property int zoneGap: Math.min(Math.max(KWin.readConfig("zoneOverlayGap", 8), 0), 32)

    function boolConfig(key, fallback) {
        var value = KWin.readConfig(key, fallback)
        if (typeof value === "boolean") return value
        if (typeof value === "string") return value.toLowerCase() === "true"
        return Boolean(value)
    }

    function alphaColor(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    function engineConfig() {
        return {
            outerGap: KWin.readConfig("outerGap", 8),
            innerGap: KWin.readConfig("innerGap", 8),
            smartGaps: boolConfig("smartGaps", false),

            dualMasterRatio: KWin.readConfig("dualMasterRatio", 0.67),
            centerMasterRatio: KWin.readConfig("centerMasterRatio", 0.40),
            minMasterRatio: KWin.readConfig("minMasterRatio", 0.30),
            maxMasterRatio: KWin.readConfig("maxMasterRatio", 0.70),
            ratioStep: KWin.readConfig("ratioStep", 0.05),
            verticalResizeStep: KWin.readConfig("verticalResizeStep", 0.10),
            minStackWeight: KWin.readConfig("minStackWeight", 0.20),

            focusWrap: boolConfig("focusWrap", false),
            insertionPolicy: KWin.readConfig("insertionPolicy", "balanced"),

            enableDragReassign: boolConfig("enableDragReassign", true),
            showDragHighlight: boolConfig("showDragHighlight", true),
            dropZoneRatio: KWin.readConfig("dropZoneRatio", 0.30),

            floatingApps: KWin.readConfig("floatingApps", ""),
            ignoredApps: KWin.readConfig("ignoredApps", ""),
            tiledApps: KWin.readConfig("tiledApps", ""),

            debug: boolConfig("debug", false)
        }
    }

    function screenForCursor(pos) {
        var screens = Workspace.screens
        for (var i = 0; i < screens.length; ++i) {
            var g = screens[i].geometry
            if (g && pos.x >= g.x && pos.x < g.x + g.width &&
                    pos.y >= g.y && pos.y < g.y + g.height) {
                return screens[i]
            }
        }
        return screens.length ? screens[0] : null
    }

    function refreshWorkArea() {
        var screen = screenForCursor(Workspace.cursorPos)
        if (!screen) return

        var desktop = Workspace.currentDesktopForScreen(screen)
        var area = Workspace.clientArea(KWin.WorkArea, screen, desktop)
        if (area && area.width > 0 && area.height > 0) {
            workArea = Qt.rect(area.x, area.y, area.width, area.height)
        }
    }

    function zoneAt(pos) {
        if (!workArea || workArea.width <= 0) return ""

        var relativeX = Math.max(0, Math.min(1,
            (pos.x - workArea.x) / Math.max(1, workArea.width)))

        if (relativeX < dropZoneRatio) return "left"
        if (relativeX > 1.0 - dropZoneRatio) return "right"
        return "master"
    }

    function windowBelongsToCurrentArea(window) {
        if (!window || window === dragWindow || !window.normalWindow ||
                window.minimized || window.fullScreen) return false

        var g = window.frameGeometry
        if (!g || g.width <= 0 || g.height <= 0) return false

        var cx = g.x + g.width / 2
        var cy = g.y + g.height / 2

        return cx >= workArea.x && cx <= workArea.x + workArea.width &&
               cy >= workArea.y && cy <= workArea.y + workArea.height
    }

    function refreshStackCounts() {
        var left = 0
        var right = 0
        var windows = Workspace.stackingOrder

        for (var i = 0; i < windows.length; ++i) {
            var window = windows[i]
            if (!windowBelongsToCurrentArea(window)) continue

            var g = window.frameGeometry
            var zone = zoneAt(Qt.point(g.x + g.width / 2, g.y + g.height / 2))
            if (zone === "left") ++left
            else if (zone === "right") ++right
        }

        leftWindowCount = left
        rightWindowCount = right
    }

    function slotForCursor(zone) {
        if (zone !== "left" && zone !== "right") return -1

        var existing = zone === "left" ? leftWindowCount : rightWindowCount
        var slots = Math.max(1, existing + 1)
        var relativeY = Math.max(0, Math.min(0.999999,
            (Workspace.cursorPos.y - workArea.y) / Math.max(1, workArea.height)))

        return Math.max(0, Math.min(slots - 1, Math.floor(relativeY * slots)))
    }

    function connectOverlayWindow(window) {
        if (!window || !window.normalWindow) return

        window.interactiveMoveResizeStarted.connect(function() {
            if (!window.move || !root.overlayEnabled) return

            root.refreshWorkArea()
            root.dragWindow = window
            root.refreshStackCounts()
            root.dragging = true
            root.activeZone = root.zoneAt(Workspace.cursorPos)
            root.activeSlot = root.slotForCursor(root.activeZone)
            overlay.visible = true
            pollTimer.start()
        })

        window.interactiveMoveResizeFinished.connect(function() {
            if (root.dragWindow !== window) return

            pollTimer.stop()
            root.dragging = false
            root.activeZone = ""
            root.activeSlot = -1
            root.dragWindow = null
            overlay.visible = false
        })
    }

    function updateOverlayPointer() {
        if (!dragging || !dragWindow) return

        refreshWorkArea()
        refreshStackCounts()
        activeZone = zoneAt(Workspace.cursorPos)
        activeSlot = slotForCursor(activeZone)
    }

    function zoneMessage() {
        if (activeZone === "left") return "Soltar en columna izquierda"
        if (activeZone === "right") return "Soltar en columna derecha"
        return "Soltar como ventana principal"
    }

    Component.onCompleted: {
        Logic.initialize(Workspace, KWin, engineConfig())

        var windows = Workspace.stackingOrder
        for (var i = 0; i < windows.length; ++i) {
            connectOverlayWindow(windows[i])
        }
    }

    Connections {
        target: Workspace

        function onWindowAdded(window) {
            root.connectOverlayWindow(window)
        }

        function onWindowRemoved(window) {
            if (root.dragWindow === window) {
                pollTimer.stop()
                root.dragging = false
                root.dragWindow = null
                overlay.visible = false
            }
        }

        function onScreensChanged() {
            if (root.dragging) root.refreshWorkArea()
        }
    }

    ShortcutHandler {
        name: "CenterMasterFocusLeft"
        text: "Center Master: Focus left"
        sequence: "Meta+H"
        onActivated: Logic.focusLeft()
    }
    ShortcutHandler {
        name: "CenterMasterFocusDown"
        text: "Center Master: Focus down"
        sequence: "Meta+J"
        onActivated: Logic.focusDown()
    }
    ShortcutHandler {
        name: "CenterMasterFocusUp"
        text: "Center Master: Focus up"
        sequence: "Meta+K"
        onActivated: Logic.focusUp()
    }
    ShortcutHandler {
        name: "CenterMasterFocusRight"
        text: "Center Master: Focus right"
        sequence: "Meta+L"
        onActivated: Logic.focusRight()
    }

    ShortcutHandler {
        name: "CenterMasterMoveLeft"
        text: "Center Master: Move to left stack"
        sequence: "Meta+Shift+H"
        onActivated: Logic.moveLeft()
    }
    ShortcutHandler {
        name: "CenterMasterMoveDown"
        text: "Center Master: Move down"
        sequence: "Meta+Shift+J"
        onActivated: Logic.moveDown()
    }
    ShortcutHandler {
        name: "CenterMasterMoveUp"
        text: "Center Master: Move up"
        sequence: "Meta+Shift+K"
        onActivated: Logic.moveUp()
    }
    ShortcutHandler {
        name: "CenterMasterMoveRight"
        text: "Center Master: Move to right stack"
        sequence: "Meta+Shift+L"
        onActivated: Logic.moveRight()
    }

    ShortcutHandler {
        name: "CenterMasterPromote"
        text: "Center Master: Promote to master"
        sequence: "Meta+Return"
        onActivated: Logic.promoteActive()
    }
    ShortcutHandler {
        name: "CenterMasterFloat"
        text: "Center Master: Toggle floating"
        sequence: "Meta+Space"
        onActivated: Logic.toggleFloating()
    }
    ShortcutHandler {
        name: "CenterMasterMonocle"
        text: "Center Master: Toggle monocle"
        sequence: "Meta+M"
        onActivated: Logic.toggleMonocle()
    }
    ShortcutHandler {
        name: "CenterMasterReflow"
        text: "Center Master: Reflow current layout"
        sequence: "Meta+R"
        onActivated: Logic.reflowActive()
    }

    ShortcutHandler {
        name: "CenterMasterSecondaryGrow"
        text: "Center Master: Grow secondary window"
        sequence: "Meta+Ctrl+K"
        onActivated: Logic.secondaryGrow()
    }
    ShortcutHandler {
        name: "CenterMasterSecondaryShrink"
        text: "Center Master: Shrink secondary window"
        sequence: "Meta+Ctrl+J"
        onActivated: Logic.secondaryShrink()
    }
    ShortcutHandler {
        name: "CenterMasterSecondaryReset"
        text: "Center Master: Reset secondary stack weights"
        sequence: "Meta+Ctrl+Backspace"
        onActivated: Logic.secondaryReset()
    }

    ShortcutHandler {
        name: "CenterMasterShrink"
        text: "Center Master: Shrink master"
        sequence: "Meta+-"
        onActivated: Logic.shrinkMaster()
    }
    ShortcutHandler {
        name: "CenterMasterGrow"
        text: "Center Master: Grow master"
        sequence: "Meta+="
        onActivated: Logic.growMaster()
    }
    ShortcutHandler {
        name: "CenterMasterResetRatio"
        text: "Center Master: Reset ratios"
        sequence: "Meta+0"
        onActivated: Logic.resetRatios()
    }

    PlasmaCore.Dialog {
        id: overlay

        visible: false
        type: PlasmaCore.Dialog.OnScreenDisplay
        location: PlasmaCore.Types.Desktop
        backgroundHints: PlasmaCore.Types.NoBackground
        flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
        hideOnWindowDeactivate: false
        outputOnly: true

        x: root.workArea.x
        y: root.workArea.y
        width: root.workArea.width
        height: root.workArea.height

        Item {
            implicitWidth: root.workArea.width
            implicitHeight: root.workArea.height
            width: overlay.width
            height: overlay.height

            Rectangle {
                anchors.fill: parent
                color: root.alphaColor(Kirigami.Theme.backgroundColor, 0.08)
            }

            Rectangle {
                id: leftZone
                x: root.zoneGap
                y: root.zoneGap
                width: Math.max(1, parent.width * root.dropZoneRatio - root.zoneGap * 1.5)
                height: Math.max(1, parent.height - root.zoneGap * 2)
                radius: root.cornerRadius
                color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "left" ? root.activeOpacity : root.inactiveOpacity)
                border.color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "left" ? 1.0 : 0.52)
                border.width: root.activeZone === "left" ? 3 : 1

                Behavior on color { ColorAnimation { duration: 110 } }

                Item {
                    anchors.fill: parent
                    anchors.margins: 8

                    Repeater {
                        model: Math.max(1, root.leftWindowCount + 1)

                        Rectangle {
                            required property int index
                            readonly property int count: Math.max(1, root.leftWindowCount + 1)

                            x: 0
                            y: index * (parent.height / count) + 2
                            width: parent.width
                            height: Math.max(1, parent.height / count - 4)
                            radius: Math.max(4, root.cornerRadius - 4)
                            color: root.alphaColor(
                                Kirigami.Theme.highlightColor,
                                root.activeZone === "left" && root.activeSlot === index ? 0.36 : 0.06)
                            border.color: root.alphaColor(
                                Kirigami.Theme.highlightColor,
                                root.activeZone === "left" && root.activeSlot === index ? 0.95 : 0.24)
                            border.width: root.activeZone === "left" && root.activeSlot === index ? 2 : 1
                        }
                    }
                }
            }

            Rectangle {
                id: masterZone
                x: parent.width * root.dropZoneRatio + root.zoneGap / 2
                y: root.zoneGap
                width: Math.max(1, parent.width * (1.0 - root.dropZoneRatio * 2.0) - root.zoneGap)
                height: Math.max(1, parent.height - root.zoneGap * 2)
                radius: root.cornerRadius
                color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "master" ? root.activeOpacity : root.inactiveOpacity)
                border.color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "master" ? 1.0 : 0.52)
                border.width: root.activeZone === "master" ? 3 : 1

                Behavior on color { ColorAnimation { duration: 110 } }
            }

            Rectangle {
                id: rightZone
                x: parent.width * (1.0 - root.dropZoneRatio) + root.zoneGap / 2
                y: root.zoneGap
                width: Math.max(1, parent.width * root.dropZoneRatio - root.zoneGap * 1.5)
                height: Math.max(1, parent.height - root.zoneGap * 2)
                radius: root.cornerRadius
                color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "right" ? root.activeOpacity : root.inactiveOpacity)
                border.color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "right" ? 1.0 : 0.52)
                border.width: root.activeZone === "right" ? 3 : 1

                Behavior on color { ColorAnimation { duration: 110 } }

                Item {
                    anchors.fill: parent
                    anchors.margins: 8

                    Repeater {
                        model: Math.max(1, root.rightWindowCount + 1)

                        Rectangle {
                            required property int index
                            readonly property int count: Math.max(1, root.rightWindowCount + 1)

                            x: 0
                            y: index * (parent.height / count) + 2
                            width: parent.width
                            height: Math.max(1, parent.height / count - 4)
                            radius: Math.max(4, root.cornerRadius - 4)
                            color: root.alphaColor(
                                Kirigami.Theme.highlightColor,
                                root.activeZone === "right" && root.activeSlot === index ? 0.36 : 0.06)
                            border.color: root.alphaColor(
                                Kirigami.Theme.highlightColor,
                                root.activeZone === "right" && root.activeSlot === index ? 0.95 : 0.24)
                            border.width: root.activeZone === "right" && root.activeSlot === index ? 2 : 1
                        }
                    }
                }
            }

            Rectangle {
                id: hintCard
                width: Math.min(330, parent.width * 0.32)
                height: 126
                anchors.centerIn: parent
                radius: 16
                color: root.alphaColor(Kirigami.Theme.backgroundColor, 0.92)
                border.color: Kirigami.Theme.highlightColor
                border.width: 2

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    Item {
                        width: 122
                        height: 54
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            x: 0
                            y: 0
                            width: 34
                            height: parent.height
                            radius: 5
                            color: root.alphaColor(
                                Kirigami.Theme.highlightColor,
                                root.activeZone === "left" ? 0.80 : 0.14)
                            border.color: root.alphaColor(Kirigami.Theme.highlightColor, 0.9)
                            border.width: root.activeZone === "left" ? 2 : 1
                        }

                        Rectangle {
                            x: 40
                            y: 0
                            width: 42
                            height: parent.height
                            radius: 5
                            color: root.alphaColor(
                                Kirigami.Theme.highlightColor,
                                root.activeZone === "master" ? 0.80 : 0.14)
                            border.color: root.alphaColor(Kirigami.Theme.highlightColor, 0.9)
                            border.width: root.activeZone === "master" ? 2 : 1
                        }

                        Rectangle {
                            x: 88
                            y: 0
                            width: 34
                            height: parent.height
                            radius: 5
                            color: root.alphaColor(
                                Kirigami.Theme.highlightColor,
                                root.activeZone === "right" ? 0.80 : 0.14)
                            border.color: root.alphaColor(Kirigami.Theme.highlightColor, 0.9)
                            border.width: root.activeZone === "right" ? 2 : 1
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.zoneMessage()
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 15
                        font.bold: true
                    }
                }
            }

            Timer {
                id: pollTimer
                interval: 16
                repeat: true
                onTriggered: root.updateOverlayPointer()
            }
        }
    }
}
