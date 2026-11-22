// NetworkPage.qml — Wi-Fi on/off, current connection, traffic, and the network list.
// Same look as System / Audio / Display: mono labels, plain lines, no boxes.
// Everything polls only while Settings is open.
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page
    readonly property int rightMargin: 46
    readonly property string mono: "JetBrainsMono Nerd Font"
    // set by SettingsWindow: true only while Settings is open
    property bool live: true

    // ---------- state ----------
    property bool wifiOn: true
    property string wifiDev: ""
    property string wifiConn: ""          // active connection name on the wifi device
    property var ethernet: null            // { device, state, connection } or null if no port
    property var addrs: ({})               // iface -> "192.168.1.5/24"
    property var saved: ({})               // saved wifi connection names
    property var networks: []              // [{ ssid, signal, secured, connected }]
    property bool scanning: false
    property real down: 0
    property real up: 0
    property var prev: null

    // per-network UI state
    property string askFor: ""             // ssid whose password box is open
    property string busy: ""               // ssid with an action in flight
    property string busyLabel: ""
    property var errors: ({})              // ssid -> message

    function fmtSpeed(b) {
        if (b < 1024) return Math.round(b) + " B/s"
        if (b < 1048576) return (b / 1024).toFixed(1) + " KB/s"
        return (b / 1048576).toFixed(2) + " MB/s"
    }
    function strength(s) { return s >= 75 ? "󰤨" : s >= 50 ? "󰤥" : s >= 25 ? "󰤢" : "󰤟" }
    function setError(ssid, msg) { const e = Object.assign({}, errors); if (msg) e[ssid] = msg; else delete e[ssid]; errors = e }
    function friendly(err) {
        const s = err.toLowerCase()
        if (s.includes("secrets were required") || s.includes("802-1x") || s.includes("password")) return "wrong password"
        if (s.includes("no network with ssid")) return "network not found — try rescan"
        if (s.includes("timeout") || s.includes("timed out")) return "timed out"
        return err.replace(/^Error:\s*/, "").split("\n")[0].slice(0, 80) || "failed to connect"
    }

    // nmcli -t output: split on unescaped ':' (SSIDs can contain ':')
    function splitTerse(line, n) {
        const f = []; let cur = "", esc = false
        for (const ch of line) {
            if (esc) { cur += ch; esc = false }
            else if (ch === "\\") esc = true
            else if (ch === ":" && f.length < n - 1) { f.push(cur); cur = "" }
            else cur += ch
        }
        f.push(cur)
        return f
    }

    // ---------- traffic (1 s) ----------
    Process {
        id: pNet
        command: ["cat", "/proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rx = 0, tx = 0
                for (const line of text.split("\n").slice(2)) {
                    const i = line.indexOf(":"); if (i < 0) continue
                    const name = line.slice(0, i).trim()
                    if (name === "lo" || /^(veth|docker|br-|virbr|tun|wg)/.test(name)) continue
                    const p = line.slice(i + 1).trim().split(/\s+/)
                    rx += Number(p[0]) || 0; tx += Number(p[8]) || 0
                }
                const now = Date.now()
                if (page.prev) {
                    const dt = (now - page.prev.t) / 1000
                    if (dt > 0) { page.down = Math.max(0, (rx - page.prev.rx) / dt); page.up = Math.max(0, (tx - page.prev.tx) / dt) }
                }
                page.prev = { rx: rx, tx: tx, t: now }
            }
        }
    }
    Timer { interval: 1000; repeat: true; triggeredOnStart: true; running: page.live; onTriggered: if (!pNet.running) pNet.running = true }

    // ---------- devices / radio / saved / addresses (3 s) ----------
    Process {
        id: pState
        command: ["sh", "-c",
            "nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device; echo '#'; " +
            "nmcli -t -f NAME,TYPE connection show; echo '#'; " +
            "nmcli radio wifi; echo '#'; " +
            "ip -4 -o addr show scope global | awk '{print $2, $4}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [devs, conns, radio, ips] = text.split("\n#\n")
                let wdev = "", wconn = "", eth = null
                for (const l of (devs || "").split("\n")) {
                    const f = page.splitTerse(l.trim(), 4); if (f.length < 4) continue
                    if (f[1] === "wifi" && !wdev) { wdev = f[0]; wconn = f[2] === "connected" ? f[3] : "" }
                    else if (f[1] === "ethernet" && !eth) eth = { device: f[0], state: f[2], connection: f[3] }
                }
                const sv = {}
                for (const l of (conns || "").split("\n")) {
                    const f = page.splitTerse(l.trim(), 2)
                    if (f[1] === "802-11-wireless") sv[f[0]] = true
                }
                const ad = {}
                for (const l of (ips || "").split("\n")) { const p = l.trim().split(" "); if (p.length === 2) ad[p[0]] = p[1] }
                page.wifiDev = wdev; page.wifiConn = wconn; page.ethernet = eth
                page.saved = sv; page.addrs = ad
                page.wifiOn = (radio || "").trim() === "enabled"
            }
        }
    }
    Timer { interval: 3000; repeat: true; triggeredOnStart: true; running: page.live; onTriggered: if (!pState.running) pState.running = true }

    // ---------- wifi list: cached results every 10 s (instant); a real scan on open / "rescan" ----------
    Process {
        id: pList
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const by = {}
                for (const l of text.split("\n")) {
                    const f = page.splitTerse(l.trim(), 4)
                    if (f.length < 4 || !f[1]) continue
                    const n = { ssid: f[1], signal: parseInt(f[2]) || 0, secured: f[3] !== "" && f[3] !== "--", connected: f[0] === "*" }
                    const o = by[n.ssid]   // one row per SSID (several access points / bands)
                    if (!o) by[n.ssid] = n
                    else { o.connected = o.connected || n.connected; o.signal = Math.max(o.signal, n.signal) }
                }
                page.networks = Object.values(by).sort((a, b) => (b.connected - a.connected) || (b.signal - a.signal))
                page.scanning = false
            }
        }
    }
    Timer { interval: 10000; repeat: true; triggeredOnStart: true; running: page.live && page.wifiOn; onTriggered: if (!pList.running) pList.running = true }
    Process { id: pRescan; command: ["nmcli", "device", "wifi", "rescan"]; onExited: listSoon.restart() }
    Timer { id: listSoon; interval: 2500; onTriggered: pList.running = true }
    function rescan() { if (pRescan.running) return; scanning = true; pRescan.running = true }

    // ---------- actions ----------
    function refreshAll() { pState.running = true; listSoon.interval = 600; listSoon.restart() }

    Process {
        id: pRadio
        onExited: { pState.running = true; if (page.wifiOn) page.rescan() }
    }
    function setWifi(on) { wifiOn = on; if (!on) networks = []; pRadio.command = ["nmcli", "radio", "wifi", on ? "on" : "off"]; pRadio.running = true }

    Process {
        id: pConnect
        property string ssid: ""
        stderr: StdioCollector { id: connErr }
        onExited: code => {
            if (code !== 0) page.setError(pConnect.ssid, page.friendly(connErr.text || ""))
            else { page.setError(pConnect.ssid, ""); page.askFor = "" }
            page.busy = ""
            page.refreshAll()
        }
    }
    function run(ssid, cmd, label) {
        if (pConnect.running) return
        setError(ssid, ""); busy = ssid; busyLabel = label
        pConnect.ssid = ssid; pConnect.command = cmd; pConnect.running = true
    }
    function activate(n) {
        if (n.connected) return
        if (saved[n.ssid]) run(n.ssid, ["nmcli", "connection", "up", "id", n.ssid], "connecting…")
        else if (n.secured) askFor = askFor === n.ssid ? "" : n.ssid
        else run(n.ssid, ["nmcli", "device", "wifi", "connect", n.ssid], "connecting…")
    }
    function connectWith(ssid, pw) { if (pw !== "") run(ssid, ["nmcli", "device", "wifi", "connect", ssid, "password", pw], "connecting…") }
    function disconnect() { if (wifiDev) run(wifiConn, ["nmcli", "device", "disconnect", wifiDev], "disconnecting…") }
    function forget(ssid) { run(ssid, ["nmcli", "connection", "delete", "id", ssid], "forgetting…") }

    onLiveChanged: if (live) { pNet.running = true; pState.running = true; pList.running = true; rescan() }
    // timers bound to `live` don't fire triggeredOnStart at creation, so load once right away
    Component.onCompleted: { pNet.running = true; pState.running = true; pList.running = true; rescan() }

    // ---------- pieces ----------
    component Act: Text {
        id: act
        property bool lit: false
        property bool warn: false
        signal clicked()
        color: warn ? Theme.danger : lit ? Theme.accent : am.containsMouse ? Theme.text : Theme.textFaint
        font.family: page.mono; font.pixelSize: 11; font.underline: am.containsMouse
        MouseArea { id: am; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
    }
    component Fact: Row {
        property string k: ""
        property string v: ""
        property color vc: Theme.text
        Text { width: 84; text: parent.k; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
        Text { text: parent.v; color: parent.vc; font.family: page.mono; font.pixelSize: 12 }
    }

    // ---------- layout ----------
    Flickable {
        id: flick
        anchors { fill: parent; rightMargin: page.rightMargin }
        contentWidth: width
        contentHeight: content.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: flick.width
            spacing: 14

            Text { text: "Network"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19 }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Column {
                width: parent.width
                spacing: 6
                topPadding: 2

                Item {
                    width: parent.width; height: wifiRow.height
                    Fact { id: wifiRow; k: "wi-fi"; v: page.wifiOn ? (page.wifiConn ? "connected" : "on") : "off"; vc: page.wifiOn ? Theme.text : Theme.textFaint }
                    Act { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                          text: page.wifiOn ? "turn off" : "turn on"; onClicked: page.setWifi(!page.wifiOn) }
                }
                Item {
                    visible: page.wifiConn !== ""
                    width: parent.width; height: netRow.height
                    Fact { id: netRow; k: "network"; v: page.wifiConn }
                    Act { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                          text: "disconnect"; onClicked: page.disconnect() }
                }
                Fact { visible: !!page.addrs[page.wifiDev]; k: "address"; v: page.addrs[page.wifiDev] || "" }
                Fact {
                    visible: page.ethernet !== null
                    k: "ethernet"
                    v: page.ethernet ? (page.ethernet.state === "connected" ? (page.ethernet.connection + (page.addrs[page.ethernet.device] ? "  " + page.addrs[page.ethernet.device] : "")) : "unplugged") : ""
                    vc: page.ethernet && page.ethernet.state === "connected" ? Theme.text : Theme.textFaint
                }
                Fact { k: "traffic"; v: "↓ " + page.fmtSpeed(page.down) + "    ↑ " + page.fmtSpeed(page.up) }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            Item {
                width: parent.width; height: 16
                Text { text: "networks"; color: Theme.textDim; font.family: page.mono; font.pixelSize: 12 }
                Act { visible: page.wifiOn; anchors.right: parent.right; text: page.scanning ? "scanning…" : "rescan"; onClicked: page.rescan() }
            }

            Text {
                visible: !page.wifiOn
                text: "wi-fi is off"
                color: Theme.textFaint; font.family: page.mono; font.pixelSize: 12
            }
            Text {
                visible: page.wifiOn && page.networks.length === 0
                text: "looking for networks…"
                color: Theme.textFaint; font.family: page.mono; font.pixelSize: 12
            }

            Column {
                visible: page.wifiOn
                width: parent.width
                spacing: 2

                Repeater {
                    model: page.networks
                    Column {
                        id: net
                        required property var modelData
                        readonly property bool isSaved: !!page.saved[modelData.ssid]
                        readonly property string err: page.errors[modelData.ssid] || ""
                        readonly property bool open: page.askFor === modelData.ssid
                        width: parent.width

                        Item {
                            width: parent.width; height: 28
                            Rectangle {
                                anchors.fill: parent; anchors.leftMargin: -8; anchors.rightMargin: -8
                                radius: 6
                                color: Theme.alpha(Theme.text, rowMa.containsMouse && !net.modelData.connected ? 0.04 : 0)
                            }
                            MouseArea {
                                id: rowMa
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: net.modelData.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: page.activate(net.modelData)
                            }
                            Text {
                                id: bars
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                text: page.strength(net.modelData.signal)
                                color: net.modelData.connected ? Theme.accent : Theme.textDim
                                font.family: page.mono; font.pixelSize: 14
                            }
                            Text {
                                id: name
                                anchors { left: bars.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                width: Math.min(implicitWidth, parent.width - 300)
                                elide: Text.ElideRight
                                text: net.modelData.ssid
                                color: net.modelData.connected ? Theme.accent : Theme.text
                                font.family: page.mono; font.pixelSize: 12
                            }
                            Text {
                                anchors { left: name.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                text: [net.modelData.secured ? "󰌾" : "", net.modelData.signal + "%",
                                       net.modelData.connected ? "connected" : net.isSaved ? "saved" : ""].filter(s => s).join("  ")
                                color: Theme.textFaint; font.family: page.mono; font.pixelSize: 10
                            }
                            Row {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 16
                                Text {
                                    visible: page.busy === net.modelData.ssid
                                    text: page.busyLabel; color: Theme.textDim; font.family: page.mono; font.pixelSize: 11
                                }
                                Act {
                                    visible: net.isSaved && page.busy !== net.modelData.ssid
                                    text: "forget"
                                    onClicked: page.forget(net.modelData.ssid)
                                }
                            }
                        }

                        // password box for a new secured network
                        Item {
                            visible: net.open
                            width: parent.width; height: visible ? 34 : 0
                            Text { id: pwl; x: 30; anchors.verticalCenter: parent.verticalCenter; text: "password"; color: Theme.textDim; font.family: page.mono; font.pixelSize: 11 }
                            Item {
                                id: pwBox
                                anchors { left: pwl.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                width: 240; height: 22
                                TextInput {
                                    id: pw
                                    anchors.fill: parent
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Theme.text; selectionColor: Theme.alpha(Theme.accent, 0.4)
                                    font.family: page.mono; font.pixelSize: 12
                                    echoMode: showPw.lit ? TextInput.Normal : TextInput.Password
                                    focus: net.open
                                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                                    Keys.onReturnPressed: page.connectWith(net.modelData.ssid, text)
                                    Keys.onEscapePressed: page.askFor = ""
                                }
                                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: pw.activeFocus ? Theme.accent : Theme.border }
                            }
                            Row {
                                anchors { left: pwBox.right; leftMargin: 16; verticalCenter: parent.verticalCenter }
                                spacing: 16
                                Act { id: showPw; text: lit ? "hide" : "show"; onClicked: lit = !lit }
                                Act { text: "connect"; lit: pw.text !== ""; onClicked: page.connectWith(net.modelData.ssid, pw.text) }
                            }
                        }

                        Text {
                            visible: net.err !== ""
                            x: 30; bottomPadding: 4
                            text: net.err
                            color: Theme.danger; font.family: page.mono; font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
