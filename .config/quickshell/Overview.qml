pragma ComponentBehavior: Bound
// Workspace overview with live window thumbnails.  qs ipc call overview toggle | show | hide
// Tap a workspace to go there, tap a window to focus it. Bound to Super+G and the 4-finger swipe-up on the touchscreen.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

ShellPopup {
    id: root

    property bool showing: false
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: root.showing ? 320 : 160; easing.type: root.showing ? Easing.OutQuint : Easing.InQuad } }

    function show() { Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); showing = true }
    function hide() { showing = false }
    function go(ws) { hide(); Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ workspace = " + ws + " })"]) }
    function focusWin(addr, ws) {
        hide()
        Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = \"address:" + addr + "\" })"])
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.showing ? root.hide() : root.show() }
        function open(): void { root.show() }
        function hide(): void { root.hide() }
    }

    surfaceOpen: showing || prog > 0.003
    WlrLayershell.namespace: "overview"
    WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    readonly property var mon: Hyprland.focusedMonitor
    readonly property real monW: mon && mon.width > 0 ? mon.width : 1920
    readonly property real monH: mon && mon.height > 0 ? mon.height : 1080
    readonly property int wsCount: 4
    readonly property int activeWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    readonly property real k: Touch.k
    readonly property int cols: width > height ? 2 : 1
    readonly property real cardW: Math.min((width - 120 - 28 * (cols - 1)) / cols, 760)
    readonly property real cardH: cardW * monH / monW
    readonly property real scaleF: cardW / monW

    // no blur layer rule for "overview", so a real dim is fine here
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.62 * root.prog)
        MouseArea { anchors.fill: parent; onPressed: root.hide() }
    }

    Item { anchors.fill: parent; focus: root.showing; Keys.onEscapePressed: root.hide() }

    Grid {
        id: grid
        anchors.centerIn: parent
        columns: root.cols
        columnSpacing: 28
        rowSpacing: 28
        opacity: root.prog
        scale: 0.94 + 0.06 * root.prog
        transformOrigin: Item.Center

        Repeater {
            model: root.wsCount
            delegate: Item {
                id: wsCard
                required property int index
                readonly property int wsId: index + 1
                readonly property bool active: root.activeWs === wsId
                width: root.cardW + 4
                height: root.cardH + 4 + 26 * root.k

                Text {
                    id: label
                    text: "Workspace " + wsCard.wsId
                    color: wsCard.active ? Theme.accent : Theme.textDim
                    font.pixelSize: 13 * root.k
                    font.family: Theme.iconFont
                    font.weight: wsCard.active ? Font.DemiBold : Font.Normal
                }

                Rectangle {
                    id: frame
                    anchors { top: label.bottom; topMargin: 6; left: parent.left }
                    width: root.cardW; height: root.cardH
                    radius: 14
                    color: Qt.rgba(0.04, 0.04, 0.05, 0.96)
                    border.width: wsCard.active ? 2 : 1
                    border.color: wsCard.active ? Theme.accent : Theme.borderAccent
                    clip: true
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    // tap empty space -> go to the workspace
                    TapHandler { onTapped: root.go(wsCard.wsId) }

                    Repeater {
                        model: Hyprland.toplevels
                        delegate: Item {
                            id: tl
                            required property var modelData
                            readonly property var ipc: modelData.lastIpcObject
                            readonly property bool here: !!(ipc && ipc.workspace && ipc.workspace.id === wsCard.wsId)
                            visible: here && !!ipc && ipc.mapped !== false
                            x: here ? (ipc.at[0] - (root.mon ? root.mon.x : 0)) * root.scaleF : 0
                            y: here ? (ipc.at[1] - (root.mon ? root.mon.y : 0)) * root.scaleF : 0
                            width: here ? ipc.size[0] * root.scaleF : 0
                            height: here ? ipc.size[1] * root.scaleF : 0

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: Theme.bgCard
                                border.width: 1
                                border.color: tlTap.pressed ? Theme.accent : Theme.borderAccent
                                clip: true
                                ScreencopyView {
                                    anchors.fill: parent
                                    captureSource: tl.visible && root.showing && tl.modelData.wayland ? tl.modelData.wayland : null
                                    live: root.showing
                                }
                            }
                            TapHandler { id: tlTap; onTapped: root.focusWin(tl.modelData.address, wsCard.wsId) }
                        }
                    }
                }
            }
        }
    }
}
