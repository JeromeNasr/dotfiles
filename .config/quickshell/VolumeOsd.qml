import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

PanelWindow {
    id: root

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 150
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
        item: root.showing ? flyout : null
    }

    PwObjectTracker {
        id: audioTracker
        objects: [Pipewire.defaultAudioSink]
    }

    property var sink: Pipewire.defaultAudioSink

    property real volume: {
        if (!sink || !sink.audio)
            return 0
        return sink.audio.volume
    }

    property bool muted: {
        if (!sink || !sink.audio)
            return false
        return sink.audio.muted
    }

    property bool ready: false
    property bool showing: false

    // ---- brightness: same pill, shown when brightness changes (bar scroll, brightness keys,
    //      `qs ipc call osd brightness 5%+`). Never goes below 2 % so the screen can't go black.
    property string mode: "volume"          // what the pill is showing
    property real bright: 0
    property string pendingStep: ""
    Process {
        id: pBright
        stdout: StdioCollector {
            onStreamFinished: {
                const pct = parseInt((text.trim().split(",")[3] || "").replace("%", ""))
                if (isNaN(pct)) return
                root.bright = pct / 100
                root.mode = "brightness"
                root.showOsd()
            }
        }
        onExited: if (root.pendingStep !== "") { const s = root.pendingStep; root.pendingStep = ""; root.stepBrightness(s) }
    }
    // step: "5%+", "5%-", "40%" …  (calls while one is running are coalesced, latest wins)
    function stepBrightness(step) {
        if (pBright.running) { pendingStep = step; return }
        pBright.command = ["sh", "-c", "brightnessctl -q -n2% set \"$1\"; brightnessctl -m", "sh", step]
        pBright.running = true
    }
    function showBrightness() { pBright.command = ["brightnessctl", "-m"]; pBright.running = true }
    IpcHandler {
        target: "osd"
        function brightness(step: string): void { root.stepBrightness(step) }
        function showBrightness(): void { root.showBrightness() }
    }
    Connections {
        target: Prefs
        function onStepBrightness(step) { root.stepBrightness(step) }
    }
    property bool hovered: flyoutArea.containsMouse

    Timer {
        id: startupTimer

        interval: 2000
        repeat: false
        running: true

        onTriggered: root.ready = true
    }

    function showOsd() {
        showing = true
        hideTimer.restart()
    }

    function triggerOsd() {
        if (!ready)
            return

        showOsd()
    }

    Timer {
        id: hideTimer

        interval: 1200
        repeat: false

        onTriggered: {
            if (root.hovered) {
                hideTimer.restart()
                return
            }

            root.showing = false
        }
    }

    Connections {
        target: root.sink?.audio ?? null

        function onVolumeChanged() {
            root.mode = "volume"
            root.triggerOsd()
        }

        function onMutedChanged() {
            root.mode = "volume"
            root.triggerOsd()
        }
    }

    Rectangle {
        id: flyout
        property bool open: root.showing
        width: 320
        height: 28
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 30
        radius: 36
        color: Theme.bg
        opacity: open ? 1 : 0
        scale: open ? 1 : 0.9

        Behavior on opacity {
            NumberAnimation { duration: 150 }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutCubic
            }
        }
        MouseArea {
            id: flyoutArea

            anchors.fill: parent
            hoverEnabled: true
            enabled: flyout.open
        }
        Text {
            id: icon
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter

            text: {
                if (root.mode === "brightness")
                    return root.bright < 0.3 ? "󰃞" : root.bright < 0.7 ? "󰃟" : "󰖙"
                if (root.muted)
                    return "󰖁"
                if (root.volume <= 0)
                    return "󰕿"
                if (root.volume < 0.5)
                    return "󰖀"
                return "󰕾"
            }

            font.family: "Symbols Nerd Font"
            font.pixelSize: 20

            color: Theme.text
        }

        Text { font.family: Theme.fontFamily
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            text: root.mode === "brightness" ? Math.round(root.bright * 100) + "%"
                : root.muted
                ? "Muted"
                : Math.round(root.volume * 100) + "%"
            font.pixelSize: 12
            font.bold: true
            color: Theme.text
        }
        Rectangle {
            anchors.left: icon.right
            anchors.leftMargin: 15
            anchors.right: parent.right
            anchors.rightMargin: 68
            anchors.verticalCenter: parent.verticalCenter
            height: 5
            radius: 4
            color: "#555555"
            Rectangle {
                width: root.mode === "brightness" ? parent.width * Math.min(root.bright, 1)
                    : root.muted
                    ? 0
                    : parent.width * Math.min(root.volume, 1)
                height: parent.height
                radius: 4
                color: Theme.text
                Behavior on width {
                    NumberAnimation { duration: 100 }
                }
            }
        }
    }
}
