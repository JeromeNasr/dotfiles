// QuickMenu.qml — quick Wi-Fi + Bluetooth from the bar's network icon (left click).
// Right click the icon (or "all settings") for the full Network page.
// `qs ipc call quick toggle`.  Esc / click outside closes.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth

ShellPopup {
    id: root
    property alias ipc: ipcH

    property bool showing: false
    property real anchorX: -1           // bar icon centre (screen x); -1 = right edge
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: root.showing ? 200 : 120; easing.type: Easing.OutCubic } }
    surfaceOpen: showing || prog > 0.01
    WlrLayershell.namespace: "quick-menu"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { item: root.showing ? catcher : null }

    readonly property string mono: "JetBrainsMono Nerd Font"

    function open(x) {
        if (x !== undefined) anchorX = x
        pList.running = true; pState.running = true
        if (!pRescan.running) pRescan.running = true
        showing = true
    }
    function close() { showing = false }
    function toggle(x) { showing ? close() : open(x) }

    IpcHandler {
        id: ipcH
        enabled: false   // the always-loaded stub in shell.qml forwards here (lazy loading)
        target: "quick"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function hide(): void { root.close() }
    }

    // ---------- wi-fi ----------
    property bool wifiOn: true
    property string wifiConn: ""
    property var saved: ({})
    property var nets: []
    property string busy: ""
    property string err: ""
    function splitTerse(line, n) {
        const f = []; let cur = "", esc = false
        for (const ch of line) {
            if (esc) { cur += ch; esc = false } else if (ch === "\\") esc = true
            else if (ch === ":" && f.length < n - 1) { f.push(cur); cur = "" } else cur += ch
        }
        f.push(cur); return f
    }
    Process {
        id: pState
        command: ["sh", "-c", "nmcli radio wifi; echo '#'; nmcli -t -f TYPE,STATE,CONNECTION device; echo '#'; nmcli -t -f NAME,TYPE connection show"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [radio, devs, conns] = text.split("\n#\n")
                root.wifiOn = (radio || "").trim() === "enabled"
                let c = ""
                for (const l of (devs || "").split("\n")) { const f = root.splitTerse(l.trim(), 3); if (f[0] === "wifi" && f[1] === "connected") c = f[2] }
                root.wifiConn = c
                const sv = {}
                for (const l of (conns || "").split("\n")) { const f = root.splitTerse(l.trim(), 2); if (f[1] === "802-11-wireless") sv[f[0]] = true }
                root.saved = sv
            }
        }
    }
    Process {
        id: pList
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const by = {}
                for (const l of text.split("\n")) {
                    const f = root.splitTerse(l.trim(), 4); if (f.length < 4 || !f[1]) continue
                    const n = { ssid: f[1], signal: parseInt(f[2]) || 0, secured: f[3] !== "" && f[3] !== "--", connected: f[0] === "*" }
                    const o = by[n.ssid]; if (!o) by[n.ssid] = n; else { o.connected = o.connected || n.connected; o.signal = Math.max(o.signal, n.signal) }
                }
                root.nets = Object.values(by).sort((a, b) => (b.connected - a.connected) || (b.signal - a.signal)).slice(0, 6)
            }
        }
    }
    Process { id: pRescan; command: ["nmcli", "device", "wifi", "rescan"]; onExited: relist.restart() }
    Timer { id: relist; interval: 2500; onTriggered: pList.running = true }
    Process {
        id: pAct
        property string ssid: ""
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            root.err = code === 0 ? "" : (/secrets|password/i.test(actErr.text) ? "needs a password — use all settings" : "couldn't connect to " + pAct.ssid)
            root.busy = ""; pState.running = true; relist.interval = 600; relist.restart()
        }
    }
    function connect(n) {
        if (n.connected || pAct.running) return
        if (!saved[n.ssid] && n.secured) { openSettings(["network"]); return }   // new secured network: needs the password form
        busy = n.ssid; err = ""; pAct.ssid = n.ssid
        pAct.command = saved[n.ssid] ? ["nmcli", "connection", "up", "id", n.ssid] : ["nmcli", "device", "wifi", "connect", n.ssid]
        pAct.running = true
    }
    function setWifi(on) { wifiOn = on; Quickshell.execDetached(["nmcli", "radio", "wifi", on ? "on" : "off"]); relist.interval = 1500; relist.restart() }
    function strength(s) { return s >= 75 ? "󰤨" : s >= 50 ? "󰤥" : s >= 25 ? "󰤢" : "󰤟" }

    // ---------- bluetooth ----------
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property bool btOn: bt ? bt.enabled : false
    readonly property var btDevs: btOn ? BluetoothState.deviceList().filter(d => d.paired)
                                          .sort((a, b) => (b.connected - a.connected) || (a.name || "").localeCompare(b.name || "")) : []
    function btIcon(d) {
        const i = d.icon || ""
        return /headset|headphone|audio-card/.test(i) ? "󰋋" : /speaker/.test(i) ? "󰓃" : /mouse/.test(i) ? "󰍽"
             : /keyboard/.test(i) ? "󰌌" : /phone/.test(i) ? "󰄜" : "󰂯"
    }
    function btToggle(d) {
        if (d.state === BluetoothDeviceState.Connected) { BluetoothState.forget(d.address); d.disconnect() }
        else if (d.state === BluetoothDeviceState.Disconnected) { d.trusted = true; d.connect() }
    }

    function openSettings(args) { close(); Quickshell.execDetached(["qs", "ipc", "call", "settings"].concat(args)) }

    // ---------- pieces ----------
    component Act: Text {
        id: act
        property bool lit: false
        signal clicked()
        color: lit ? Theme.accent : am.containsMouse ? Theme.text : Theme.textFaint
        font.family: root.mono; font.pixelSize: 11; font.underline: am.containsMouse
        MouseArea { id: am; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
    }
    component Line: Item {
        id: ln
        property string icon: ""
        property string label: ""
        property string side: ""
        property bool on: false
        property bool clickable: true
        signal clicked()
        width: parent.width; height: 28
        Rectangle { anchors.fill: parent; anchors.leftMargin: -8; anchors.rightMargin: -8; radius: 6
                    color: Theme.alpha(Theme.text, lma.containsMouse && ln.clickable ? 0.05 : 0) }
        Text { id: li; anchors.verticalCenter: parent.verticalCenter; width: 22; text: ln.icon; color: ln.on ? Theme.accent : Theme.textDim; font.family: root.mono; font.pixelSize: 14 }
        Text { anchors { left: li.right; leftMargin: 6; right: ls.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
               text: ln.label; elide: Text.ElideRight; color: ln.on ? Theme.accent : Theme.text; font.family: root.mono; font.pixelSize: 12 }
        Text { id: ls; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
               text: ln.side; color: Theme.textFaint; font.family: root.mono; font.pixelSize: 10 }
        MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; enabled: ln.clickable; cursorShape: Qt.PointingHandCursor; onClicked: ln.clicked() }
    }

    Item {
        id: catcher
        anchors.fill: parent
        focus: root.showing
        Keys.onEscapePressed: root.close()
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            id: card
            width: 340
            height: col.implicitHeight + 32
            x: root.anchorX < 0 ? parent.width - width - 12 : Math.max(12, Math.min(parent.width - width - 12, root.anchorX - width / 2))
            y: 48 + (1 - root.prog) * -8
            opacity: root.prog
            radius: 14
            color: Theme.alpha(Theme.bgPanel, 0.97)
            border.width: 1; border.color: Theme.alpha(Theme.text, 0.09)
            MouseArea { anchors.fill: parent }

            Column {
                id: col
                x: 18; y: 16; width: parent.width - 36
                spacing: 4

                // wi-fi header
                Item {
                    width: parent.width; height: 22
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "wi-fi"; color: Theme.textDim; font.family: root.mono; font.pixelSize: 12 }
                    Act { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                          text: root.wifiOn ? "on" : "off"; lit: root.wifiOn; onClicked: root.setWifi(!root.wifiOn) }
                }
                Repeater {
                    model: root.wifiOn ? root.nets : []
                    Line {
                        required property var modelData
                        icon: root.strength(modelData.signal)
                        label: modelData.ssid
                        on: modelData.connected
                        side: root.busy === modelData.ssid ? "connecting…" : modelData.connected ? "connected" : root.saved[modelData.ssid] ? "saved" : modelData.secured ? "󰌾" : ""
                        clickable: !modelData.connected
                        onClicked: root.connect(modelData)
                    }
                }
                Text { visible: root.wifiOn && root.nets.length === 0; text: "looking for networks…"; color: Theme.textFaint; font.family: root.mono; font.pixelSize: 11; topPadding: 2; bottomPadding: 4 }
                Text { visible: root.err !== ""; text: root.err; color: Theme.danger; font.family: root.mono; font.pixelSize: 11 }

                Item { width: 1; height: 6 }
                Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }
                Item { width: 1; height: 6 }

                // bluetooth
                Item {
                    width: parent.width; height: 22
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "bluetooth"; color: Theme.textDim; font.family: root.mono; font.pixelSize: 12 }
                    Act { visible: !!root.bt; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                          text: root.btOn ? "on" : "off"; lit: root.btOn; onClicked: root.bt.enabled = !root.btOn }
                }
                Repeater {
                    model: root.btDevs
                    Line {
                        required property var modelData
                        icon: root.btIcon(modelData)
                        label: modelData.name || modelData.address
                        on: modelData.connected
                        side: modelData.state === BluetoothDeviceState.Connecting ? "connecting…"
                            : modelData.state === BluetoothDeviceState.Disconnecting ? "…"
                            : modelData.connected ? (modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%  " : "") + "connected" : ""
                        onClicked: root.btToggle(modelData)
                    }
                }
                Text { visible: root.btOn && root.btDevs.length === 0; text: "no paired devices"; color: Theme.textFaint; font.family: root.mono; font.pixelSize: 11 }

                Item { width: 1; height: 8 }
                Row {
                    spacing: 18
                    Act { text: "network settings"; onClicked: root.openSettings(["network"]) }
                    Act { text: "bluetooth settings"; onClicked: root.openSettings(["page", "Bluetooth"]) }
                }
            }
        }
    }
}
