// PowerPage.qml — battery, power profile and CPU power limit.
// Same look as the other pages. Polls only while Settings is open.
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

    // ---------- battery ----------
    property var bat: null      // { pct, status, now, full, design, rate (W), cycles }
    Process {
        id: pBat
        command: ["sh", "-c",
            "b=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1); [ -n \"$b\" ] || exit 0; cd $b;" +
            "r() { cat $1 2>/dev/null || echo 0; };" +
            "echo $(r capacity) $(r status) $(r energy_now) $(r energy_full) $(r energy_full_design) $(r power_now)" +
            " $(r charge_now) $(r charge_full) $(r charge_full_design) $(r current_now) $(r voltage_now) $(r cycle_count)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                if (p.length < 12) { page.bat = null; return }
                const n = p.map(Number)
                // energy_* is µWh / power_now µW; charge_* is µAh / current µA (× voltage µV)
                const v = n[10] / 1e6
                const useE = n[3] > 0
                const now = useE ? n[2] / 1e6 : n[6] / 1e6 * v
                const full = useE ? n[3] / 1e6 : n[7] / 1e6 * v
                const design = useE ? n[4] / 1e6 : n[8] / 1e6 * v
                const rate = Math.abs(useE ? n[5] / 1e6 : n[9] / 1e6 * v)
                page.bat = { pct: n[0], status: p[1], now: now, full: full, design: design, rate: rate, cycles: n[11] }
            }
        }
    }
    Timer { interval: 5000; repeat: true; running: page.live; onTriggered: if (!pBat.running) pBat.running = true }

    function hm(h) {
        if (!isFinite(h) || h <= 0 || h > 48) return ""
        const m = Math.round(h * 60)
        return (m >= 60 ? Math.floor(m / 60) + "h " : "") + (m % 60) + "m"
    }
    readonly property string batLine: {
        if (!bat) return ""
        const s = bat.status.toLowerCase()
        let t = s === "discharging" && bat.rate > 0.3 ? hm(bat.now / bat.rate) + " left"
              : s === "charging" && bat.rate > 0.3 ? hm((bat.full - bat.now) / bat.rate) + " to full"
              : s === "not charging" ? "plugged in, not charging" : s
        if (bat.rate > 0.3) t += "  ·  " + bat.rate.toFixed(1) + " W"
        return t
    }

    // ---------- profile + power limit (via ~/.local/bin/power-limit) ----------
    property string profile: ""
    property var profiles: []
    property int limit: 100          // applied slider value 0..100
    property real dragLimit: -1      // while dragging
    property int capPct: 100
    property bool turboOff: false
    property bool canWrite: true

    Process {
        id: pStatus
        command: ["sh", "-c", "power-limit status; echo '#'; powerprofilesctl list 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [st, list] = text.split("\n#\n")
                const p = (st || "").trim().split(/\s+/)
                if (p.length >= 5) {
                    page.limit = parseInt(p[0]); page.capPct = parseInt(p[1])
                    page.turboOff = p[2] === "1"; page.canWrite = p[3] === "1"; page.profile = p[4]
                }
                const found = []; const re = /^\s*\*?\s*([a-z-]+):\s*$/gm; let m
                while ((m = re.exec(list || "")) !== null) found.push(m[1])
                if (found.length) page.profiles = found
            }
        }
    }
    Process { id: pSet; onExited: pStatus.running = true }
    function setLimit(v) {
        v = Math.max(0, Math.min(100, Math.round(v)))
        limit = v; dragLimit = -1
        pSet.command = ["power-limit", String(v)]; pSet.running = true
    }
    // a profile maps to a preset limit (power-limit also sets the profile from the limit)
    function setProfile(id) { setLimit(id === "power-saver" ? 30 : id === "balanced" ? 65 : 100) }
    function limitText(v) { return v === 0 ? "minimum" : (15 + Math.floor(v * 85 / 100)) + "% cpu" + (v < 70 ? " · no turbo" : "") }

    Process {
        id: pSetup
        command: ["pkexec", "sh", "-c",
            "install -m644 " + Quickshell.env("HOME") + "/dotfiles/dotfiles/.config/hypr/tmpfiles/power-limit.conf /etc/tmpfiles.d/power-limit.conf" +
            " && systemd-tmpfiles --create /etc/tmpfiles.d/power-limit.conf"]
        onExited: { pStatus.running = true; Quickshell.execDetached(["power-limit", "restore"]) }
    }

    function refresh() { pBat.running = true; pStatus.running = true }
    onLiveChanged: if (live) refresh()
    Component.onCompleted: refresh()

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
    component Label: Text { width: 84; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
    component Faint: Text { color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11 }

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

            Text { text: "Power"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19 }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            // battery
            Column {
                visible: page.bat !== null
                width: parent.width
                spacing: 8
                Item {
                    width: parent.width; height: 20
                    Label { id: bl; anchors.verticalCenter: parent.verticalCenter; text: "battery" }
                    Rectangle {
                        anchors { left: bl.right; right: bp.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        height: 4; radius: 2; color: Theme.alpha(Theme.textFaint, 0.18)
                        Rectangle {
                            width: parent.width * Math.min(1, (page.bat ? page.bat.pct : 0) / 100); height: parent.height; radius: 2
                            color: page.bat && page.bat.pct <= 15 && page.bat.status === "Discharging" ? Theme.danger : Theme.accent
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                        }
                    }
                    Text { id: bp; anchors { right: bs.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                           width: 40; horizontalAlignment: Text.AlignRight
                           text: page.bat ? page.bat.pct + "%" : ""; color: Theme.text; font.family: page.mono; font.pixelSize: 12 }
                    Faint { id: bs; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 190; horizontalAlignment: Text.AlignRight; elide: Text.ElideLeft; text: page.batLine }
                }
                Row {
                    x: 84
                    spacing: 22
                    Faint { text: page.bat ? "health " + Math.round(Math.min(100, page.bat.full / Math.max(1e-6, page.bat.design) * 100)) + "%" : "" }
                    Faint { text: page.bat ? page.bat.full.toFixed(1) + " of " + page.bat.design.toFixed(1) + " Wh" : "" }
                    Faint { visible: page.bat && page.bat.cycles > 0; text: page.bat ? page.bat.cycles + " cycles" : "" }
                }
            }

            Rectangle { visible: page.bat !== null; width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            // profile
            Item {
                width: parent.width; height: 20
                Label { id: pl; anchors.verticalCenter: parent.verticalCenter; text: "profile" }
                Row {
                    anchors { left: pl.right; verticalCenter: parent.verticalCenter }
                    spacing: 22
                    Repeater {
                        model: [{ id: "power-saver", t: "power saver" }, { id: "balanced", t: "balanced" }, { id: "performance", t: "performance" }]
                        Text {
                            id: po
                            required property var modelData
                            readonly property bool cur: page.profile === modelData.id
                            readonly property bool ok: page.profiles.length === 0 || page.profiles.indexOf(modelData.id) >= 0
                            text: (cur ? "● " : "") + modelData.t
                            opacity: ok ? 1 : 0.35
                            color: cur ? Theme.accent : pm.containsMouse ? Theme.text : Theme.textFaint
                            font.family: page.mono; font.pixelSize: 12
                            MouseArea { id: pm; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; enabled: po.ok && !po.cur
                                        cursorShape: Qt.PointingHandCursor; onClicked: page.setProfile(po.modelData.id) }
                        }
                    }
                }
            }

            // cpu limit
            Item {
                width: parent.width; height: 20
                Label { id: ll; anchors.verticalCenter: parent.verticalCenter; text: "cpu limit" }
                Item {
                    id: lbar
                    anchors { left: ll.right; right: lt.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    height: 18
                    readonly property real v: (page.dragLimit >= 0 ? page.dragLimit : page.limit) / 100
                    readonly property bool hot: lma.containsMouse || lma.pressed
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: lbar.hot ? 6 : 4; radius: height / 2
                        color: Theme.alpha(Theme.textFaint, 0.18)
                        Behavior on height { NumberAnimation { duration: 120 } }
                        Rectangle {
                            width: Math.max(height, parent.width * lbar.v); height: parent.height; radius: parent.radius
                            color: page.limit === 0 && page.dragLimit < 0 ? Theme.danger : Theme.accent
                        }
                    }
                    Rectangle {
                        width: 12; height: 12; radius: 6; anchors.verticalCenter: parent.verticalCenter
                        x: Math.round(lbar.width * lbar.v - 6); color: Theme.text
                        opacity: lbar.hot ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: lma
                        anchors.fill: parent; anchors.topMargin: -4; anchors.bottomMargin: -4
                        hoverEnabled: true; preventStealing: true; cursorShape: Qt.PointingHandCursor
                        function at(x) { return Math.max(0, Math.min(100, x / lbar.width * 100)) }
                        onPressed: m => page.dragLimit = at(m.x)
                        onPositionChanged: m => { if (pressed) page.dragLimit = at(m.x) }
                        // applying runs powerprofilesctl + sysfs writes, so only on release
                        onReleased: page.setLimit(page.dragLimit)
                    }
                }
                Text { id: lt; anchors { right: lmin.left; rightMargin: 16; verticalCenter: parent.verticalCenter }
                       width: 150; horizontalAlignment: Text.AlignRight
                       text: page.limitText(Math.round(page.dragLimit >= 0 ? page.dragLimit : page.limit))
                       color: page.limit === 0 && page.dragLimit < 0 ? Theme.danger : Theme.text; font.family: page.mono; font.pixelSize: 12 }
                Act { id: lmin; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                      text: page.limit === 0 ? "back to full" : "minimum"; warn: page.limit === 0
                      onClicked: page.setLimit(page.limit === 0 ? 100 : 0) }
            }
            Row {
                x: 84
                spacing: 16
                Faint {
                    text: page.canWrite
                        ? "cpu capped at " + page.capPct + "%" + (page.turboOff ? "  ·  turbo off" : "  ·  turbo on")
                        : "cpu cap not set up yet, only the profile changes"
                }
                Act { visible: !page.canWrite; text: pSetup.running ? "setting up…" : "set up"; lit: true
                      onClicked: if (!pSetup.running) pSetup.running = true }
            }
        }
    }
}
