import QtQuick
import org.kde.kwin
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

PlasmaCore.Dialog {
    id: overlay

    visible: false
    type: PlasmaCore.Dialog.OnScreenDisplay
    location: PlasmaCore.Types.Desktop
    backgroundHints: PlasmaCore.Types.NoBackground
    flags: Qt.BypassWindowManagerHint | Qt.FramelessWindowHint | Qt.Popup
    hideOnWindowDeactivate: false
    outputOnly: true

    property rect workArea: Qt.rect(0, 0, 1920, 1080)
    property var dragWindow: null
    property bool dragging: false
    property string activeZone: ""
    property int leftWindowCount: 0
    property int rightWindowCount: 0
    property int activeSlot: -1

    readonly property bool enabled: KWin.readConfig("enabled", true)
    readonly property real dropZoneRatio: Math.min(Math.max(KWin.readConfig("dropZoneRatio", 0.30), 0.15), 0.45)
    readonly property real activeOpacity: Math.min(Math.max(KWin.readConfig("activeOpacity", 0.30), 0.05), 0.70)
    readonly property real inactiveOpacity: Math.min(Math.max(KWin.readConfig("inactiveOpacity", 0.10), 0.02), 0.35)
    readonly property int cornerRadius: Math.min(Math.max(KWin.readConfig("cornerRadius", 12), 0), 32)
    readonly property int zoneGap: Math.min(Math.max(KWin.readConfig("zoneGap", 8), 0), 32)

    x: workArea.x
    y: workArea.y
    width: workArea.width
    height: workArea.height

    function alphaColor(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha)
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

        var area = Workspace.clientArea(KWin.WorkArea, screen, Workspace.currentDesktop)
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

    function startDrag(window) {
        if (!enabled || !window || !window.move) return
        refreshWorkArea()
        dragWindow = window
        refreshStackCounts()
        dragging = true
        activeZone = zoneAt(Workspace.cursorPos)
        activeSlot = slotForCursor(activeZone)
        visible = true
        pollTimer.start()
    }

    function finishDrag(window) {
        if (dragWindow !== window) return
        pollTimer.stop()
        dragging = false
        activeZone = ""
        activeSlot = -1
        dragWindow = null
        visible = false
    }

    function connectWindow(window) {
        if (!window || !window.normalWindow) return

        window.interactiveMoveResizeStarted.connect(function() {
            if (window.move) startDrag(window)
        })

        window.interactiveMoveResizeFinished.connect(function() {
            finishDrag(window)
        })
    }

    function updatePointer() {
        if (!dragging || !dragWindow) return
        refreshWorkArea()
        refreshStackCounts()
        activeZone = zoneAt(Workspace.cursorPos)
        activeSlot = slotForCursor(activeZone)
    }

    Component.onCompleted: {
        var windows = Workspace.stackingOrder
        for (var i = 0; i < windows.length; ++i) connectWindow(windows[i])
    }

    Connections {
        target: Workspace

        function onWindowAdded(window) {
            overlay.connectWindow(window)
        }

        function onWindowRemoved(window) {
            if (overlay.dragWindow === window) overlay.finishDrag(window)
        }

        function onScreensChanged() {
            if (overlay.dragging) {
                overlay.refreshWorkArea()
                overlay.refreshStackCounts()
            }
        }
    }

    Item {
        implicitWidth: overlay.workArea.width
        implicitHeight: overlay.workArea.height
        width: overlay.width
        height: overlay.height

        Rectangle {
            anchors.fill: parent
            color: overlay.alphaColor(Kirigami.Theme.backgroundColor, 0.10)
        }

        Rectangle {
            id: leftZone
            x: overlay.zoneGap
            y: overlay.zoneGap
            width: Math.max(1, overlay.width * overlay.dropZoneRatio - overlay.zoneGap * 1.5)
            height: Math.max(1, overlay.height - overlay.zoneGap * 2)
            radius: overlay.cornerRadius
            color: overlay.activeZone === "left"
                ? overlay.alphaColor(Kirigami.Theme.highlightColor, overlay.activeOpacity)
                : overlay.alphaColor(Kirigami.Theme.backgroundColor, 0.72)
            border.color: overlay.activeZone === "left"
                ? Kirigami.Theme.highlightColor
                : overlay.alphaColor(Kirigami.Theme.textColor, 0.28)
            border.width: overlay.activeZone === "left" ? 3 : 1

            Behavior on color { ColorAnimation { duration: 110 } }
            Behavior on border.color { ColorAnimation { duration: 110 } }

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Text {
                    width: parent.width
                    text: "LEFT"
                    horizontalAlignment: Text.AlignHCenter
                    color: overlay.activeZone === "left"
                        ? Kirigami.Theme.highlightedTextColor
                        : Kirigami.Theme.textColor
                    font.bold: true
                    font.pixelSize: 15
                    opacity: overlay.activeZone === "left" ? 1.0 : 0.72
                }

                Item {
                    width: parent.width
                    height: Math.max(1, parent.height - 26)

                    Repeater {
                        model: Math.max(1, overlay.leftWindowCount + 1)

                        Rectangle {
                            required property int index
                            readonly property int count: Math.max(1, overlay.leftWindowCount + 1)

                            x: 0
                            y: index * (parent.height / count) + 2
                            width: parent.width
                            height: Math.max(1, parent.height / count - 4)
                            radius: Math.max(4, overlay.cornerRadius - 4)
                            color: overlay.activeZone === "left" && overlay.activeSlot === index
                                ? overlay.alphaColor(Kirigami.Theme.highlightColor, 0.48)
                                : overlay.alphaColor(Kirigami.Theme.alternateBackgroundColor, 0.52)
                            border.color: overlay.activeZone === "left" && overlay.activeSlot === index
                                ? Kirigami.Theme.highlightColor
                                : overlay.alphaColor(Kirigami.Theme.textColor, 0.18)
                            border.width: overlay.activeZone === "left" && overlay.activeSlot === index ? 2 : 1
                        }
                    }
                }
            }
        }

        Rectangle {
            id: masterZone
            x: overlay.width * overlay.dropZoneRatio + overlay.zoneGap / 2
            y: overlay.zoneGap
            width: Math.max(1, overlay.width * (1.0 - overlay.dropZoneRatio * 2.0) - overlay.zoneGap)
            height: Math.max(1, overlay.height - overlay.zoneGap * 2)
            radius: overlay.cornerRadius
            color: overlay.activeZone === "master"
                ? overlay.alphaColor(Kirigami.Theme.highlightColor, overlay.activeOpacity)
                : overlay.alphaColor(Kirigami.Theme.backgroundColor, 0.72)
            border.color: overlay.activeZone === "master"
                ? Kirigami.Theme.highlightColor
                : overlay.alphaColor(Kirigami.Theme.textColor, 0.28)
            border.width: overlay.activeZone === "master" ? 3 : 1

            Behavior on color { ColorAnimation { duration: 110 } }
            Behavior on border.color { ColorAnimation { duration: 110 } }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 8
                radius: Math.max(4, overlay.cornerRadius - 4)
                color: overlay.activeZone === "master"
                    ? overlay.alphaColor(Kirigami.Theme.highlightColor, 0.16)
                    : overlay.alphaColor(Kirigami.Theme.alternateBackgroundColor, 0.34)
                border.color: overlay.alphaColor(
                    overlay.activeZone === "master"
                        ? Kirigami.Theme.highlightColor
                        : Kirigami.Theme.textColor,
                    overlay.activeZone === "master" ? 0.72 : 0.16)
                border.width: overlay.activeZone === "master" ? 2 : 1

                Text {
                    anchors.centerIn: parent
                    text: "MASTER"
                    color: overlay.activeZone === "master"
                        ? Kirigami.Theme.highlightedTextColor
                        : Kirigami.Theme.textColor
                    font.bold: true
                    font.pixelSize: 18
                    opacity: overlay.activeZone === "master" ? 1.0 : 0.72
                }
            }
        }

        Rectangle {
            id: rightZone
            x: overlay.width * (1.0 - overlay.dropZoneRatio) + overlay.zoneGap / 2
            y: overlay.zoneGap
            width: Math.max(1, overlay.width * overlay.dropZoneRatio - overlay.zoneGap * 1.5)
            height: Math.max(1, overlay.height - overlay.zoneGap * 2)
            radius: overlay.cornerRadius
            color: overlay.activeZone === "right"
                ? overlay.alphaColor(Kirigami.Theme.highlightColor, overlay.activeOpacity)
                : overlay.alphaColor(Kirigami.Theme.backgroundColor, 0.72)
            border.color: overlay.activeZone === "right"
                ? Kirigami.Theme.highlightColor
                : overlay.alphaColor(Kirigami.Theme.textColor, 0.28)
            border.width: overlay.activeZone === "right" ? 3 : 1

            Behavior on color { ColorAnimation { duration: 110 } }
            Behavior on border.color { ColorAnimation { duration: 110 } }

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Text {
                    width: parent.width
                    text: "RIGHT"
                    horizontalAlignment: Text.AlignHCenter
                    color: overlay.activeZone === "right"
                        ? Kirigami.Theme.highlightedTextColor
                        : Kirigami.Theme.textColor
                    font.bold: true
                    font.pixelSize: 15
                    opacity: overlay.activeZone === "right" ? 1.0 : 0.72
                }

                Item {
                    width: parent.width
                    height: Math.max(1, parent.height - 26)

                    Repeater {
                        model: Math.max(1, overlay.rightWindowCount + 1)

                        Rectangle {
                            required property int index
                            readonly property int count: Math.max(1, overlay.rightWindowCount + 1)

                            x: 0
                            y: index * (parent.height / count) + 2
                            width: parent.width
                            height: Math.max(1, parent.height / count - 4)
                            radius: Math.max(4, overlay.cornerRadius - 4)
                            color: overlay.activeZone === "right" && overlay.activeSlot === index
                                ? overlay.alphaColor(Kirigami.Theme.highlightColor, 0.48)
                                : overlay.alphaColor(Kirigami.Theme.alternateBackgroundColor, 0.52)
                            border.color: overlay.activeZone === "right" && overlay.activeSlot === index
                                ? Kirigami.Theme.highlightColor
                                : overlay.alphaColor(Kirigami.Theme.textColor, 0.18)
                            border.width: overlay.activeZone === "right" && overlay.activeSlot === index ? 2 : 1
                        }
                    }
                }
            }
        }

        Timer {
            id: pollTimer
            interval: 16
            repeat: true
            onTriggered: overlay.updatePointer()
        }
    }
}
