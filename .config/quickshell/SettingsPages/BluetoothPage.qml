// BluetoothPage.qml — power, your devices, and pairing new ones.
// Same look as the other pages. Discovery (scanning) only runs while this page is
// open AND Settings is showing; it is stopped as soon as either closes.
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import "../"

Item {
    id: page
    readonly property int rightMargin: 46
    readonly property string mono: "JetBrainsMono Nerd Font"
    // set by SettingsWindow: true only while Settings is open
    property bool live: true

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter ? adapter.enabled : false
    readonly property bool scanning: adapter ? adapter.discovering : false
    readonly property var devices: adapter && powered ? BluetoothState.deviceList() : []
    readonly property var mine: devices.filter(d => d.paired && !BluetoothState.removingDevices[d.address])
                                       .sort((a, b) => (b.connected - a.connected) || name(a).localeCompare(name(b)))
    // nearby, unpaired, and with a real name (skip the anonymous MAC-only beacons)
    readonly property var nearby: devices.filter(d => !d.paired && d.name && d.name.replace(/[-:]/g, "") !== d.address.replace(/:/g, ""))

    function name(d) { return d ? (d.name || d.address || "device") : "" }
    function icon(d) {
        const i = (d && d.icon) || ""
        if (/headset|headphone|audio-card/.test(i)) return "󰋋"
        if (/speaker/.test(i)) return "󰓃"
        if (/mouse/.test(i)) return "󰍽"
        if (/keyboard/.test(i)) return "󰌌"
        if (/phone/.test(i)) return "󰄜"
        if (/gaming|joystick/.test(i)) return "󰊴"
        if (/computer/.test(i)) return "󰌢"
        return "󰂯"
    }
    function stateText(d) {
        if (d.pairing) return "pairing…"
        switch (d.state) {
        case BluetoothDeviceState.Connected: return "connected"
        case BluetoothDeviceState.Connecting: return "connecting…"
        case BluetoothDeviceState.Disconnecting: return "disconnecting…"
        default: return ""
        }
    }

    // ---------- discovery: only while visible ----------
    readonly property bool wantScan: live && visible && powered
    function syncScan() {
        if (!adapter || !powered) return
        adapter.discovering = wantScan
        adapter.pairable = wantScan
    }
    onWantScanChanged: syncScan()
    // starting/stopping discovery is async: if a scan comes up after we stopped wanting
    // it, stop it; if BlueZ drops it while we still want it, ask again a bit later
    onScanningChanged: {
        if (scanning && !wantScan) adapter.discovering = false
        else if (!scanning && wantScan && !scanResume.running) scanRetry.restart()
    }
    // watchdog: start/stop requests can race inside Quickshell/BlueZ; while we don't want a
    // scan, make sure none is left running
    Timer { running: !page.wantScan && page.powered; interval: 2000; repeat: true
            onTriggered: if (page.adapter && page.adapter.discovering) page.adapter.discovering = false }
    Timer { id: scanRetry; interval: 3000; onTriggered: if (page.wantScan && !page.scanning) page.syncScan() }
    Component.onCompleted: syncScan()
    Component.onDestruction: if (adapter && adapter.discovering) adapter.discovering = false

    // ---------- actions ----------
    function togglePower() {
        if (!adapter) return
        if (adapter.enabled) {
            BluetoothState.reconnectPaused = true
            if (adapter.discovering) adapter.discovering = false
            for (const d of BluetoothState.deviceList())
                if (d.state === BluetoothDeviceState.Connected || d.state === BluetoothDeviceState.Connecting) d.disconnect()
            powerOff.restart()
        } else {
            BluetoothState.reconnectPaused = false
            adapter.enabled = true
        }
    }
    Timer { id: powerOff; interval: 800; onTriggered: if (page.adapter) page.adapter.enabled = false }

    function connectDev(d) {
        if (scanning) adapter.discovering = false      // discovery slows connecting down
        d.trusted = true
        d.connect()
        scanResume.restart()
    }
    function disconnectDev(d) {
        BluetoothState.forget(d.address)                // you disconnected it: don't auto-reconnect
        d.disconnect()
    }
    function removeDev(d) {
        BluetoothState.markRemoved(d)
        if (d.state !== BluetoothDeviceState.Disconnected) d.disconnect()
        d.forget()
    }
    // resume scanning a little after a connect attempt
    Timer { id: scanResume; interval: 8000; onTriggered: page.syncScan() }

    // ---------- pieces ----------
    component Act: Text {
        id: act
        property bool lit: false
        signal clicked()
        color: lit ? Theme.accent : am.containsMouse ? Theme.text : Theme.textFaint
        font.family: page.mono; font.pixelSize: 11; font.underline: am.containsMouse
        MouseArea { id: am; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
    }

    // one device line:  󰋋 AirPods Max   82%  connected            disconnect   forget
    component DevLine: Item {
        id: dl
        property var dev: null
        property bool isNew: false               // unpaired, from discovery
        property bool wantConnect: false
        readonly property bool conn: dev && dev.state === BluetoothDeviceState.Connected
        readonly property bool busy: dev && (dev.pairing || dev.state === BluetoothDeviceState.Connecting || dev.state === BluetoothDeviceState.Disconnecting)
        width: parent.width; height: 28

        // after pairing a new device, connect to it
        Connections {
            target: dl.dev
            function onPairedChanged() { if (dl.dev.paired && dl.wantConnect) { dl.wantConnect = false; page.connectDev(dl.dev) } }
        }

        Rectangle {
            anchors.fill: parent; anchors.leftMargin: -8; anchors.rightMargin: -8
            radius: 6
            color: Theme.alpha(Theme.text, rowMa.containsMouse && !dl.conn && !dl.busy ? 0.04 : 0)
        }
        MouseArea {
            id: rowMa
            anchors.fill: parent; hoverEnabled: true
            cursorShape: dl.conn || dl.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: {
                if (dl.conn || dl.busy) return
                if (dl.isNew) { dl.wantConnect = true; dl.dev.pair() }
                else page.connectDev(dl.dev)
            }
        }
        Text {
            id: ic
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            text: page.icon(dl.dev)
            color: dl.conn ? Theme.accent : Theme.textDim
            font.family: page.mono; font.pixelSize: 14
        }
        Text {
            id: nm
            anchors { left: ic.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            width: Math.min(implicitWidth, parent.width - 320)
            elide: Text.ElideRight
            text: page.name(dl.dev)
            color: dl.conn ? Theme.accent : Theme.text
            font.family: page.mono; font.pixelSize: 12
        }
        Text {
            anchors { left: nm.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
            text: [dl.dev && dl.dev.batteryAvailable ? "󰁹 " + Math.round(dl.dev.battery * 100) + "%" : "",
                   dl.dev ? page.stateText(dl.dev) : ""].filter(s => s).join("   ")
            color: dl.busy ? Theme.textDim : Theme.textFaint
            font.family: page.mono; font.pixelSize: 10
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 16
            Act { visible: dl.isNew && !dl.busy; text: "pair"; onClicked: { dl.wantConnect = true; dl.dev.pair() } }
            Act { visible: dl.isNew && dl.dev && dl.dev.pairing; text: "cancel"; onClicked: dl.dev.cancelPair() }
            Act { visible: !dl.isNew && dl.conn; text: "disconnect"; onClicked: page.disconnectDev(dl.dev) }
            Act { visible: !dl.isNew && !dl.conn && !dl.busy; text: "connect"; onClicked: page.connectDev(dl.dev) }
            Act { visible: !dl.isNew && !dl.busy; text: "forget"; onClicked: page.removeDev(dl.dev) }
        }
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

            Text { text: "Bluetooth"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19 }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Item {
                width: parent.width; height: 18
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { width: 84; text: "bluetooth"; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
                    Text {
                        text: !page.adapter ? "no adapter" : page.powered ? "on" + (page.adapter.name ? "  ·  " + page.adapter.name : "") : "off"
                        color: page.powered ? Theme.text : Theme.textFaint; font.family: page.mono; font.pixelSize: 12
                    }
                }
                Act {
                    visible: !!page.adapter
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: page.powered ? "turn off" : "turn on"
                    onClicked: page.togglePower()
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6; visible: page.powered }

            // your devices
            Text { visible: page.powered; text: "my devices"; color: Theme.textDim; font.family: page.mono; font.pixelSize: 12 }
            Column {
                visible: page.powered
                width: parent.width; spacing: 2
                Repeater { model: page.mine; DevLine { required property var modelData; dev: modelData } }
                Text { visible: page.mine.length === 0; text: "no paired devices yet"; color: Theme.textFaint; font.family: page.mono; font.pixelSize: 12 }
            }

            // nearby
            Item { visible: page.powered; width: 1; height: 4 }
            Item {
                visible: page.powered
                width: parent.width; height: 16
                Text { text: "nearby"; color: Theme.textDim; font.family: page.mono; font.pixelSize: 12 }
                Text {
                    anchors.right: parent.right
                    text: page.scanning ? "scanning…" : ""
                    color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11
                }
            }
            Column {
                visible: page.powered
                width: parent.width; spacing: 2
                Repeater { model: page.nearby; DevLine { required property var modelData; dev: modelData; isNew: true } }
                Text {
                    visible: page.nearby.length === 0
                    text: "put a device in pairing mode and it will show up here"
                    color: Theme.textFaint; font.family: page.mono; font.pixelSize: 12
                }
            }

            Text {
                visible: page.adapter && !page.powered
                text: "bluetooth is off"
                color: Theme.textFaint; font.family: page.mono; font.pixelSize: 12
            }
        }
    }
}
