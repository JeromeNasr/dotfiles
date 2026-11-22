// ClipboardMenu.qml — clipboard history picker (cliphist).  Super+V / `qs ipc call clipboard toggle`
// Type to filter · ↑/↓ to move · Enter copies (then paste with Ctrl+V) · Shift+Del removes · Esc closes.
// Images get a preview (decoded once into ~/.cache/quickshell/clip/).
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
    Behavior on prog { NumberAnimation { duration: root.showing ? 180 : 110; easing.type: Easing.OutCubic } }
    surfaceOpen: showing || prog > 0.01
    WlrLayershell.namespace: "clipboard"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: root.showing ? catcher : null }

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/quickshell/clip"
    property var entries: []            // [{ id, text, image }]
    property string query: ""
    readonly property var shown: {
        const q = query.toLowerCase()
        return q === "" ? entries : entries.filter(e => !e.image && e.text.toLowerCase().includes(q))
    }
    property int sel: 0
    readonly property var cur: shown.length ? shown[Math.min(sel, shown.length - 1)] : null

    function open() { query = ""; sel = 0; pList.running = true; showing = true; Qt.callLater(() => search.forceActiveFocus()) }
    function close() { showing = false }

    IpcHandler {
        id: ipcH
        enabled: false   // the always-loaded stub in shell.qml forwards here (lazy loading)
        target: "clipboard"
        function toggle(): void { root.showing ? root.close() : root.open() }
        function open(): void { root.open() }
        function hide(): void { root.close() }
    }

    Process {
        id: pList
        command: ["sh", "-c", "cliphist list 2>/dev/null | head -n 300"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t"); if (tab < 0) continue
                    const id = line.slice(0, tab), t = line.slice(tab + 1)
                    const img = t.match(/^\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/)
                    out.push(img ? { id: id, image: true, text: img[2] + "  " + img[3] + "  ·  " + img[1], ext: img[2] }
                                 : { id: id, image: false, text: t })
                }
                root.entries = out
            }
        }
    }
    Process { id: pRun; onExited: pList.running = root.showing }
    function copy(e) {
        if (!e) return
        pRun.command = ["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist decode | wl-copy", "sh", e.id]
        pRun.running = true
        close()
    }
    function remove(e) {
        if (!e) return
        pRun.command = ["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete", "sh", e.id]
        pRun.running = true
        entries = entries.filter(x => x.id !== e.id)
    }

    // image preview for the selected entry
    property string preview: ""
    Process {
        id: pPrev
        property string want: ""
        stdout: StdioCollector { onStreamFinished: if (pPrev.want !== "") root.preview = "file://" + pPrev.want }
    }
    onCurChanged: {
        preview = ""
        if (!cur || !cur.image) return
        const f = cacheDir + "/" + cur.id + "." + cur.ext
        pPrev.want = f
        pPrev.command = ["sh", "-c", "mkdir -p \"$2\"; [ -s \"$3\" ] || printf '%s\\t\\n' \"$1\" | cliphist decode > \"$3\"; echo ok", "sh", cur.id, cacheDir, f]
        pPrev.running = true
    }

    Item {
        id: catcher
        anchors.fill: parent
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            id: card
            width: 640
            height: Math.min(parent.height - 160, 520)
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.16 + (1 - root.prog) * -10
            opacity: root.prog
            radius: 14
            color: Theme.alpha(Theme.bgPanel, 0.97)
            border.width: 1; border.color: Theme.alpha(Theme.text, 0.10)
            MouseArea { anchors.fill: parent }

            // search
            Item {
                id: top
                x: 18; y: 14; width: parent.width - 36; height: 30
                Text { id: icon; anchors.verticalCenter: parent.verticalCenter; text: "󰅌"; color: Theme.accent; font.family: root.mono; font.pixelSize: 16 }
                TextInput {
                    id: search
                    anchors { left: icon.right; leftMargin: 12; right: count.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    color: Theme.text; font.family: root.mono; font.pixelSize: 14
                    selectionColor: Theme.alpha(Theme.accent, 0.4)
                    onTextChanged: { root.query = text; root.sel = 0 }
                    Keys.onEscapePressed: root.close()
                    Keys.onUpPressed: root.sel = Math.max(0, root.sel - 1)
                    Keys.onDownPressed: root.sel = Math.min(root.shown.length - 1, root.sel + 1)
                    Keys.onReturnPressed: root.copy(root.cur)
                    Keys.onEnterPressed: root.copy(root.cur)
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier)) { root.remove(root.cur); e.accepted = true }
                        else if (e.key === Qt.Key_PageDown) { root.sel = Math.min(root.shown.length - 1, root.sel + 8); e.accepted = true }
                        else if (e.key === Qt.Key_PageUp) { root.sel = Math.max(0, root.sel - 8); e.accepted = true }
                    }
                    Text { visible: search.text === ""; text: "search clipboard history"; color: Theme.textFaint; font: search.font }
                }
                Text { id: count; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                       text: root.shown.length + (root.query ? " / " + root.entries.length : ""); color: Theme.textFaint; font.family: root.mono; font.pixelSize: 11 }
            }
            Rectangle { id: sep; x: 0; y: top.y + top.height + 10; width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            // list (left) + image preview (right, only for images)
            ListView {
                id: list
                anchors { left: parent.left; right: prevBox.visible ? prevBox.left : parent.right; top: sep.bottom; bottom: hint.top
                          leftMargin: 10; rightMargin: 10; topMargin: 8; bottomMargin: 6 }
                clip: true
                model: root.shown
                currentIndex: root.sel
                highlightMoveDuration: 0
                boundsBehavior: Flickable.StopAtBounds
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    width: list.width; height: 30
                    Rectangle { anchors.fill: parent; radius: 7
                                color: row.index === root.sel ? Theme.alpha(Theme.accent, 0.14) : Theme.alpha(Theme.text, rma.containsMouse ? 0.04 : 0) }
                    Text {
                        anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: (row.modelData.image ? "󰋩  " : "") + row.modelData.text.replace(/\s+/g, " ")
                        elide: Text.ElideRight
                        color: row.index === root.sel ? Theme.text : row.modelData.image ? Theme.textDim : Theme.textDim
                        font.family: root.mono; font.pixelSize: 12
                    }
                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true
                                onEntered: root.sel = row.index
                                onClicked: root.copy(row.modelData) }
                }
            }
            Text {
                visible: root.shown.length === 0
                anchors.centerIn: list
                text: root.entries.length ? "no matches" : "clipboard history is empty"
                color: Theme.textFaint; font.family: root.mono; font.pixelSize: 12
            }
            Item {
                id: prevBox
                visible: root.cur !== null && root.cur.image
                anchors { right: parent.right; top: sep.bottom; bottom: hint.top; margins: 14 }
                width: 240
                Image {
                    anchors.fill: parent
                    source: root.preview
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize.width: 480
                    smooth: true
                }
            }
            Text {
                id: hint
                anchors { left: parent.left; leftMargin: 20; bottom: parent.bottom; bottomMargin: 12 }
                text: "enter copy   ·   shift+del remove   ·   esc close"
                color: Theme.textFaint; font.family: root.mono; font.pixelSize: 10
            }
        }
    }
}
