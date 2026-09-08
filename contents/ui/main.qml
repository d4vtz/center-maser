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
    property real insertionY: -1
    property var previewData: null
    property var leftRects: []
    property var rightRects: []
    property bool allowLeft: true
    property bool allowMaster: true
    property bool allowRight: true
    property var previewRect: null
    property var resultRects: []

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

    function refreshPreview() {
        if (!dragWindow) {
            previewData = null
            activeZone = ""
            activeSlot = -1
            insertionY = -1
            leftWindowCount = 0
            rightWindowCount = 0
            leftRects = []
            rightRects = []
            allowLeft = true
            allowMaster = true
            allowRight = true
            previewRect = null
            resultRects = []
            return
        }

        var preview = Logic.dragPreview(dragWindow)
        previewData = preview

        if (!preview) {
            activeZone = ""
            activeSlot = -1
            insertionY = -1
            leftWindowCount = 0
            rightWindowCount = 0
            leftRects = []
            rightRects = []
            allowLeft = true
            allowMaster = true
            allowRight = true
            previewRect = null
            resultRects = []
            return
        }

        activeZone = preview.zone
        activeSlot = preview.index
        insertionY = preview.insertionY
        leftWindowCount = preview.leftCount
        rightWindowCount = preview.rightCount
        leftRects = preview.leftRects || []
        rightRects = preview.rightRects || []
        allowLeft = !preview.allowed || preview.allowed.left
        allowMaster = !preview.allowed || preview.allowed.master
        allowRight = !preview.allowed || preview.allowed.right
        previewRect = preview.previewRect || null
        resultRects = preview.resultRects || []

        if (preview.workArea) {
            workArea = Qt.rect(
                preview.workArea.x,
                preview.workArea.y,
                preview.workArea.width,
                preview.workArea.height
            )
        }
    }

    function connectOverlayWindow(window) {
        if (!window || !window.normalWindow) return

        window.interactiveMoveResizeStarted.connect(function() {
            if (!window.move || !root.overlayEnabled) return

            root.refreshWorkArea()
            root.dragWindow = window
            root.dragging = true
            root.refreshPreview()
            overlay.visible = true
            pollTimer.start()
        })

        window.interactiveMoveResizeFinished.connect(function() {
            if (root.dragWindow !== window) return

            pollTimer.stop()
            root.dragging = false
            root.activeZone = ""
            root.activeSlot = -1
            root.insertionY = -1
            root.previewData = null
            root.leftRects = []
            root.rightRects = []
            root.allowLeft = true
            root.allowMaster = true
            root.allowRight = true
            root.previewRect = null
            root.resultRects = []
            root.dragWindow = null
            overlay.visible = false
        })
    }

    function updateOverlayPointer() {
        if (!dragging || !dragWindow) return

        refreshPreview()
    }

    function zoneMessage() {
        if (activeZone === "left") return "Soltar en columna izquierda"
        if (activeZone === "right") return "Soltar en columna derecha"
        if (activeZone === "master") return "Soltar como ventana principal"
        if (!allowLeft && allowMaster && !allowRight) return "Mueve al centro para intercambiar con la principal"
        return "Destino no disponible"
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
                color: root.alphaColor(Kirigami.Theme.backgroundColor, 0.02)
            }

            Rectangle {
                id: leftZone
                visible: root.allowLeft
                x: root.zoneGap
                y: root.zoneGap
                width: Math.max(1, parent.width * root.dropZoneRatio - root.zoneGap * 1.5)
                height: Math.max(1, parent.height - root.zoneGap * 2)
                radius: root.cornerRadius
                color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "left" ? 0.065 : 0.018)
                border.color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "left" ? 0.72 : 0.16)
                border.width: root.activeZone === "left" ? 2 : 1

                Behavior on color { ColorAnimation { duration: 110 } }

                Rectangle {
                    visible: root.activeZone === "left" &&
                             root.activeSlot >= 0 &&
                             root.leftWindowCount > 0 &&
                             root.insertionY >= root.workArea.y
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    y: Math.max(6, Math.min(
                        parent.height - height - 6,
                        root.insertionY - root.workArea.y - height / 2))
                    height: 4
                    radius: 2
                    color: Kirigami.Theme.highlightColor
                    border.color: root.alphaColor(Kirigami.Theme.highlightedTextColor, 0.55)
                    border.width: 1
                }
            }

            Rectangle {
                id: masterZone
                visible: root.allowMaster
                x: parent.width * root.dropZoneRatio + root.zoneGap / 2
                y: root.zoneGap
                width: Math.max(1, parent.width * (1.0 - root.dropZoneRatio * 2.0) - root.zoneGap)
                height: Math.max(1, parent.height - root.zoneGap * 2)
                radius: root.cornerRadius
                color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "master" ? 0.065 : 0.018)
                border.color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "master" ? 0.72 : 0.16)
                border.width: root.activeZone === "master" ? 2 : 1

                Behavior on color { ColorAnimation { duration: 110 } }
            }

            Rectangle {
                id: rightZone
                visible: root.allowRight
                x: parent.width * (1.0 - root.dropZoneRatio) + root.zoneGap / 2
                y: root.zoneGap
                width: Math.max(1, parent.width * root.dropZoneRatio - root.zoneGap * 1.5)
                height: Math.max(1, parent.height - root.zoneGap * 2)
                radius: root.cornerRadius
                color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "right" ? 0.065 : 0.018)
                border.color: root.alphaColor(
                    Kirigami.Theme.highlightColor,
                    root.activeZone === "right" ? 0.72 : 0.16)
                border.width: root.activeZone === "right" ? 2 : 1

                Behavior on color { ColorAnimation { duration: 110 } }

                Rectangle {
                    visible: root.activeZone === "right" &&
                             root.activeSlot >= 0 &&
                             root.rightWindowCount > 0 &&
                             root.insertionY >= root.workArea.y
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    y: Math.max(6, Math.min(
                        parent.height - height - 6,
                        root.insertionY - root.workArea.y - height / 2))
                    height: 4
                    radius: 2
                    color: Kirigami.Theme.highlightColor
                    border.color: root.alphaColor(Kirigami.Theme.highlightedTextColor, 0.55)
                    border.width: 1
                }
            }

            Rectangle {
                id: exactDropPreview
                visible: root.previewRect !== null && root.activeZone !== "invalid"
                x: visible ? root.previewRect.x - root.workArea.x : 0
                y: visible ? root.previewRect.y - root.workArea.y : 0
                width: visible ? Math.max(1, root.previewRect.width) : 1
                height: visible ? Math.max(1, root.previewRect.height) : 1
                radius: Math.max(6, root.cornerRadius - 2)
                color: root.alphaColor(Kirigami.Theme.highlightColor, 0.13)
                border.color: Kirigami.Theme.highlightColor
                border.width: 3

                Behavior on x { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                id: hintCard
                width: Math.min(310, parent.width * 0.31)
                height: 142
                anchors.centerIn: parent
                radius: 14
                color: root.alphaColor(Kirigami.Theme.backgroundColor, 0.92)
                border.color: root.alphaColor(Kirigami.Theme.highlightColor, 0.78)
                border.width: 2

                Column {
                    anchors.centerIn: parent
                    spacing: 10

                    Item {
                        width: 162
                        height: 76
                        anchors.horizontalCenter: parent.horizontalCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: root.alphaColor(Kirigami.Theme.backgroundColor, 0.30)
                            border.color: root.alphaColor(Kirigami.Theme.textColor, 0.22)
                            border.width: 1
                        }

                        Repeater {
                            model: root.resultRects

                            Rectangle {
                                required property int index
                                readonly property var rectData: root.resultRects[index]

                                x: 4 + rectData.x * (parent.width - 8)
                                y: 4 + rectData.y * (parent.height - 8)
                                width: Math.max(3, rectData.width * (parent.width - 8))
                                height: Math.max(3, rectData.height * (parent.height - 8))
                                radius: 4
                                color: rectData.dragged
                                    ? root.alphaColor(Kirigami.Theme.highlightColor, 0.68)
                                    : root.alphaColor(Kirigami.Theme.textColor, 0.14)
                                border.color: rectData.dragged
                                    ? Kirigami.Theme.highlightColor
                                    : root.alphaColor(Kirigami.Theme.textColor, 0.26)
                                border.width: rectData.dragged ? 2 : 1
                            }
                        }

                        Text {
                            visible: root.resultRects.length === 0
                            anchors.centerIn: parent
                            text: "—"
                            color: root.alphaColor(Kirigami.Theme.textColor, 0.55)
                            font.pixelSize: 18
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.zoneMessage()
                        color: Kirigami.Theme.textColor
                        font.pixelSize: 14
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
