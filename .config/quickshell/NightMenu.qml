// NightMenu.qml — slide-to-adjust night light popup. Open: click the moon in the bar, or `qs ipc call night toggle`.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellPopup {
    id: root
    property alias ipc: ipcH
    property bool showing: false
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: root.showing ? 200 : 120; easing.type: Easing.OutCubic } }

    surfaceOpen: showing || prog > 0.01
    WlrLayershell.namespace: "night-menu"
    mask: Region { item: root.showing ? catcher : null }

    function toggle() { showing = !showing; if (showing) NightState.refresh() }

    IpcHandler {
        id: ipcH
        enabled: false   // the always-loaded stub in shell.qml forwards here (lazy loading)
        target: "night"
        function toggle(): void { root.toggle() }
        function show(): void { root.showing = true; NightState.refresh() }
        function hide(): void { root.showing = false }
    }

    Item {
        id: catcher
        anchors.fill: parent
        focus: root.showing
        Keys.onEscapePressed: root.showing = false
        MouseArea { anchors.fill: parent; onClicked: root.showing = false }   // click outside closes

        Rectangle {
            id: card
            width: 300; height: col.implicitHeight + 36
            anchors.right: parent.right; anchors.rightMargin: 16
            y: 52 + (1 - root.prog) * -8
            opacity: root.prog
            radius: 14
            color: Qt.alpha(Theme.bgPanel, 0.96)
            border.width: 1; border.color: Qt.alpha(Theme.text, 0.09)
            MouseArea { anchors.fill: parent }

            Column {
                id: col
                x: 18; y: 18; width: parent.width - 36; spacing: 14

                Item {
                    width: parent.width; height: 24
                    Text { text: "Night light"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.DemiBold
                           anchors.verticalCenter: parent.verticalCenter }
                    Rectangle {   // on/off switch
                        width: 38; height: 22; radius: 11; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        color: NightState.on ? "#ff9a40" : Qt.alpha(Theme.text, 0.18)
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Rectangle { width: 18; height: 18; radius: 9; y: 2; x: NightState.on ? 18 : 2; color: "white"
                                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } } }
                        MouseArea { anchors.fill: parent; onClicked: NightState.setOn(!NightState.on) }
                    }
                }

                Item {
                    width: parent.width; height: 44; opacity: NightState.on ? 1 : 0.5
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Text { text: "Warmth"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12 }
                    Text { anchors.right: parent.right; text: NightState.temp + " K"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12 }
                    Item {
                        id: sl
                        y: 18; width: parent.width; height: 26
                        readonly property int from: 1500
                        readonly property int to: 6500
                        readonly property real frac: (NightState.temp - from) / (to - from)
                        Rectangle { width: parent.width; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                            gradient: Gradient { orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "#ff7a1a" } GradientStop { position: 1; color: "#dfe8ff" } } }
                        Rectangle { width: 20; height: 20; radius: 10; anchors.verticalCenter: parent.verticalCenter
                            x: sl.frac * (sl.width - width); color: "white"; border.width: 2; border.color: Qt.alpha("black", 0.35) }
                        MouseArea {
                            anchors.fill: parent
                            function upd(mx) { const f = Math.max(0, Math.min(1, (mx - 10) / (sl.width - 20)))
                                               NightState.set(Math.round((sl.from + f * (sl.to - sl.from)) / 50) * 50) }
                            onPressed: m => { NightState.dragging = true; upd(m.x) }
                            onPositionChanged: m => { if (pressed) upd(m.x) }
                            onReleased: NightState.dragging = false
                            onCanceled: NightState.dragging = false
                        }
                    }
                }

                Row {
                    spacing: 6
                    Repeater {
                        model: [["Slight", 5000], ["Medium", 3800], ["Strong", 2800], ["Max", 1900]]
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            width: lab.implicitWidth + 22; height: 28; radius: 8
                            readonly property bool sel: NightState.on && NightState.temp === modelData[1]
                            color: sel ? Qt.alpha("#ff9a40", 0.30) : Qt.alpha(Theme.text, cma.containsMouse ? 0.10 : 0.06)
                            Text { id: lab; anchors.centerIn: parent; text: chip.modelData[0]; color: chip.sel ? Theme.text : Theme.textDim
                                   font.family: Theme.fontFamily; font.pixelSize: 12 }
                            MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; onClicked: NightState.set(chip.modelData[1]) }
                        }
                    }
                }
            }
        }
    }
}
