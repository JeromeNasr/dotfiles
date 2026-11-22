pragma ComponentBehavior: Bound
// Keybind cheat sheet.  qs ipc call cheatsheet toggle | show | hide | press | release
// Rows come from `keybinds-json` (parses ~/.config/hypr/keybinds.lua, using the trailing comments).
// press/release = hold-to-peek: hold the key to peek, tap it to keep the sheet open.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellPopup {
    id: root
    property alias ipc: ipcH

    property bool showing: false
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: root.showing ? 300 : 150; easing.type: root.showing ? Easing.OutQuint : Easing.InQuad } }
    property var rows: []
    property double pressedAt: 0

    function show() { if (!showing) { loader.running = true } showing = true }
    function hide() { showing = false }

    IpcHandler {
        id: ipcH
        enabled: false   // the always-loaded stub in shell.qml forwards here (lazy loading)
        target: "cheatsheet"
        function toggle(): void { root.showing ? root.hide() : root.show() }
        function open(): void { root.show() }
        function hide(): void { root.hide() }
        function press(): void {
            if (root.showing) { root.hide(); root.pressedAt = 0 }
            else { root.show(); root.pressedAt = Date.now() }
        }
        function release(): void {
            if (root.showing && root.pressedAt > 0 && Date.now() - root.pressedAt > 380) root.hide()
            root.pressedAt = 0
        }
    }

    Process {
        id: loader
        command: ["keybinds-json"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.rows = JSON.parse(text) } catch (e) { root.rows = [] } }
        }
    }

    surfaceOpen: showing || prog > 0.003
    WlrLayershell.namespace: "cheatsheet"
    WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { item: card }

    // tap outside (transparent area) closes
    MouseArea { anchors.fill: parent; enabled: root.showing; onPressed: root.hide() }

    readonly property int cols: width > 1500 ? 3 : (width > 900 ? 2 : 1)
    readonly property real k: Touch.k

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.sw - 32, 1180)
        height: Math.min(root.sh - 48, head.height + grid.implicitHeight + 56 * root.k)
        radius: 18
        color: Theme.bgPanel
        border.width: 1
        border.color: Theme.borderAccent
        opacity: root.prog
        scale: 0.97 + 0.03 * root.prog
        transformOrigin: Item.Center
        clip: true

        Text {
            id: head
            anchors { left: parent.left; top: parent.top; leftMargin: 28; topMargin: 22 }
            text: "Shortcuts"
            color: Theme.text
            font.pixelSize: 22 * root.k
            font.weight: Font.DemiBold
            font.family: Theme.iconFont
        }
        Text {
            anchors { right: parent.right; verticalCenter: head.verticalCenter; rightMargin: 28 }
            text: "tap anywhere outside to close"
            color: Theme.textFaint
            font.pixelSize: 12 * root.k
            font.family: Theme.iconFont
        }

        Flickable {
            anchors { left: parent.left; right: parent.right; top: head.bottom; bottom: parent.bottom
                      leftMargin: 28; rightMargin: 28; topMargin: 14; bottomMargin: 18 }
            contentHeight: grid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                id: grid
                width: parent.width
                columns: root.cols
                columnSpacing: 36
                rowSpacing: 2
                flow: Grid.TopToBottom
                // fill column by column so related binds stay together
                rows: Math.ceil(root.rows.length / root.cols)

                Repeater {
                    model: root.rows
                    delegate: Item {
                        required property var modelData
                        width: (grid.width - grid.columnSpacing * (root.cols - 1)) / root.cols
                        height: 34 * root.k
                        Row {
                            id: caps
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Repeater {
                                model: modelData.keys.split(" + ")
                                delegate: Rectangle {
                                    required property string modelData
                                    height: 22 * root.k
                                    width: Math.max(height, capText.implicitWidth + 14)
                                    radius: 6
                                    color: Theme.bgCard
                                    border.width: 1
                                    border.color: Theme.borderAccent
                                    Text {
                                        id: capText
                                        anchors.centerIn: parent
                                        text: modelData
                                        color: Theme.text
                                        font.pixelSize: 11.5 * root.k
                                        font.family: Theme.iconFont
                                    }
                                }
                            }
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 190 * root.k; right: parent.right; verticalCenter: parent.verticalCenter }
                            text: modelData.desc
                            elide: Text.ElideRight
                            color: Theme.textDim
                            font.pixelSize: 13 * root.k
                            font.family: Theme.iconFont
                        }
                    }
                }
            }
        }

        Keys.onEscapePressed: root.hide()
        focus: root.showing
    }
}
