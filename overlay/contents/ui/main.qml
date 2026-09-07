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

    function startDrag(window) {
        if (!enabled || !window || !window.move) return
        refreshWorkArea()
        dragWindow = window
        dragging = true
        activeZone = zoneAt(Workspace.cursorPos)
        visible = true
        pollTimer.start()
    }

    function finishDrag(window) {
        if (dragWindow !== window) return
        pollTimer.stop()
        dragging = false
        activeZone = ""
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
        activeZone = zoneAt(Workspace.cursorPos)
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
            if (overlay.dragging) overlay.refreshWorkArea()
        }
    }

    Item {
        implicitWidth: overlay.workArea.width
        implicitHeight: overlay.workArea.height
        width: overlay.width
        height: overlay.height

        Rectangle {
            id: leftZone
            x: overlay.zoneGap
            y: overlay.zoneGap
            width: Math.max(1, overlay.width * overlay.dropZoneRatio - overlay.zoneGap * 1.5)
            height: Math.max(1, overlay.height - overlay.zoneGap * 2)
            radius: overlay.cornerRadius
            color: Kirigami.Theme.highlightColor
            opacity: overlay.activeZone === "left" ? overlay.activeOpacity : overlay.inactiveOpacity
            border.color: Kirigami.Theme.highlightColor
            border.width: overlay.activeZone === "left" ? 3 : 1

            Text {
                anchors.centerIn: parent
                text: "LEFT"
                color: Kirigami.Theme.highlightedTextColor
                font.bold: true
                font.pixelSize: 18
                opacity: overlay.activeZone === "left" ? 1.0 : 0.65
            }
        }

        Rectangle {
            id: masterZone
            x: overlay.width * overlay.dropZoneRatio + overlay.zoneGap / 2
            y: overlay.zoneGap
            width: Math.max(1, overlay.width * (1.0 - overlay.dropZoneRatio * 2.0) - overlay.zoneGap)
            height: Math.max(1, overlay.height - overlay.zoneGap * 2)
            radius: overlay.cornerRadius
            color: Kirigami.Theme.highlightColor
            opacity: overlay.activeZone === "master" ? overlay.activeOpacity : overlay.inactiveOpacity
            border.color: Kirigami.Theme.highlightColor
            border.width: overlay.activeZone === "master" ? 3 : 1

            Text {
                anchors.centerIn: parent
                text: "MASTER"
                color: Kirigami.Theme.highlightedTextColor
                font.bold: true
                font.pixelSize: 18
                opacity: overlay.activeZone === "master" ? 1.0 : 0.65
            }
        }

        Rectangle {
            id: rightZone
            x: overlay.width * (1.0 - overlay.dropZoneRatio) + overlay.zoneGap / 2
            y: overlay.zoneGap
            width: Math.max(1, overlay.width * overlay.dropZoneRatio - overlay.zoneGap * 1.5)
            height: Math.max(1, overlay.height - overlay.zoneGap * 2)
            radius: overlay.cornerRadius
            color: Kirigami.Theme.highlightColor
            opacity: overlay.activeZone === "right" ? overlay.activeOpacity : overlay.inactiveOpacity
            border.color: Kirigami.Theme.highlightColor
            border.width: overlay.activeZone === "right" ? 3 : 1

            Text {
                anchors.centerIn: parent
                text: "RIGHT"
                color: Kirigami.Theme.highlightedTextColor
                font.bold: true
                font.pixelSize: 18
                opacity: overlay.activeZone === "right" ? 1.0 : 0.65
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
