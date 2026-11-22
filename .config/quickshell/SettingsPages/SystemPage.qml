// SystemPage.qml — machine overview + live CPU / RAM / GPU.
// All live polling stops while Settings is closed (the page stays loaded in the background),
// and each tick is ONE small shell read of /proc + /sys instead of 4–5 separate programs.
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page

    // set by SettingsWindow (true only while the Settings card is open)
    property bool live: true

    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property int rightMargin: 46

    // ---- static info (read once) ----
    property string user: ""
    property string host: "…"
    property string model: ""
    property string os: "…"
    property string kernel: "…"
    property string wm: "Hyprland"
    property string shell: "…"
    property string pkgs: "…"
    property string cpu: "…"
    property string cpuCores: ""
    property string gpu: "…"
    property string tempPath: ""
    property string gpuFreqPath: ""
    property string batPath: ""

    // ---- live ----
    property string currentTime: ""
    property string uptime: "…"
    property real cpuUsage: 0
    property real memoryUsage: 0
    property real gpuUsage: 0
    property string memory: "…"
    property string cpuTemp: ""
    property string cpuFreq: ""
    property string gpuFreq: ""
    property string battery: ""
    property var cpuPrev: null

    function push(type, value) {
        value = Math.max(0, Math.min(100, Number(value)))
        if (isNaN(value)) return
        page[type + "Usage"] = value
    }
    function gib(kb) { const g = kb / 1048576; return g >= 1 ? g.toFixed(1) + " GiB" : Math.round(kb / 1024) + " MiB" }
    function fmtUptime(sec) {
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60)
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m"
    }
    function tickClock() { currentTime = Qt.formatTime(new Date(), "HH:mm:ss") }

    // ================= data =================
    Process {
        id: pStatic
        running: true
        command: ["sh", "-c",
            "echo \"user=$USER\"; echo \"host=$(cat /proc/sys/kernel/hostname)\";" +
            "echo \"model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)\";" +
            ". /etc/os-release; echo \"os=$PRETTY_NAME\";" +
            "echo \"kernel=$(uname -r)\";" +
            "echo \"shell=$(basename \"$SHELL\")\";" +
            "echo \"pkgs=$(pacman -Qq 2>/dev/null | wc -l)\";" +
            "echo \"cpu=$(awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo)\";" +
            "echo \"cores=$(grep -c ^processor /proc/cpuinfo)\";" +
            "echo \"gpu=$(lspci 2>/dev/null | grep -Ei 'VGA|3D|Display' | head -1 | sed -E 's/.*: //; s/ \\(rev.*//; s/Corporation //')\";" +
            "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name) in coretemp|k10temp|zenpower) echo \"temp=$h/temp1_input\"; break;; esac; done;" +
            "for c in /sys/class/drm/card?; do [ -r $c/gt_act_freq_mhz ] && { echo \"gfreq=$c/gt_act_freq_mhz\"; break; }; done;" +
            "for b in /sys/class/power_supply/BAT*; do [ -r $b/capacity ] && { echo \"bat=$b\"; break; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const i = line.indexOf("="); if (i < 0) continue
                    const k = line.slice(0, i), v = line.slice(i + 1).trim()
                    if (k === "user") page.user = v
                    else if (k === "host") page.host = v
                    else if (k === "model") page.model = v
                    else if (k === "os") page.os = v
                    else if (k === "kernel") page.kernel = v
                    else if (k === "shell") page.shell = v
                    else if (k === "pkgs") page.pkgs = v + " (pacman)"
                    else if (k === "cpu") page.cpu = v.replace(/\(R\)|\(TM\)|CPU /g, "").replace(/^\d+(st|nd|rd|th) Gen /, "").replace(/^(Intel|AMD) /, "").replace(/\s+/g, " ").replace(/ @.*/, "").trim()
                    else if (k === "cores") page.cpuCores = v + " threads"
                    else if (k === "gpu") { const br = v.match(/\[([^\]]+)\]/); page.gpu = (br ? br[1] : v) || "Unknown" }
                    else if (k === "temp") page.tempPath = v
                    else if (k === "gfreq") page.gpuFreqPath = v
                    else if (k === "bat") page.batPath = v
                }
                pLive.running = page.live
            }
        }
    }

    // one cheap read per second: cpu, mem, temp, freqs, battery, uptime
    Process {
        id: pLive
        command: ["sh", "-c",
            "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo;" +
            "echo \"up $(cut -d' ' -f1 /proc/uptime)\";" +
            "awk '/cpu MHz/{s+=$4;n++} END{if(n) printf \"mhz %d\\n\", s/n}' /proc/cpuinfo;" +
            (page.tempPath ? "echo \"temp $(cat " + page.tempPath + ")\";" : "") +
            (page.gpuFreqPath ? "echo \"gfreq $(cat " + page.gpuFreqPath + ")\";" : "") +
            (page.batPath ? "echo \"bat $(cat " + page.batPath + "/capacity) $(cat " + page.batPath + "/status)\";" : "")]
        stdout: StdioCollector {
            onStreamFinished: {
                let memTotal = 0, memAvail = 0
                for (const line of text.split("\n")) {
                    const p = line.trim().split(/\s+/)
                    if (p[0] === "cpu") {
                        const n = p.slice(1).map(Number)
                        const idle = n[3] + (n[4] || 0), total = n.slice(0, 8).reduce((a, b) => a + (b || 0), 0)
                        if (page.cpuPrev && total > page.cpuPrev.total)
                            page.push("cpu", 100 * (1 - (idle - page.cpuPrev.idle) / (total - page.cpuPrev.total)))
                        page.cpuPrev = { total: total, idle: idle }
                    }
                    else if (p[0] === "MemTotal:") memTotal = Number(p[1])
                    else if (p[0] === "MemAvailable:") memAvail = Number(p[1])
                    else if (p[0] === "up") page.uptime = page.fmtUptime(Number(p[1]))
                    else if (p[0] === "mhz") page.cpuFreq = (Number(p[1]) / 1000).toFixed(1) + " GHz"
                    else if (p[0] === "temp") page.cpuTemp = Math.round(Number(p[1]) / 1000) + "°C"
                    else if (p[0] === "gfreq") page.gpuFreq = Number(p[1]) > 0 ? p[1] + " MHz" : "idle"
                    else if (p[0] === "bat") page.battery = p[1] + "%" + (p[2] === "Charging" ? "  󱐋" : p[2] === "Full" ? "  full" : "")
                }
                if (memTotal > 0) {
                    page.push("memory", (memTotal - memAvail) / memTotal * 100)
                    page.memory = page.gib(memTotal - memAvail) + " of " + page.gib(memTotal)
                }
            }
        }
    }

    // GPU load needs nvtop (~0.1 s), so only every 2 s
    Process {
        id: pGpu
        command: ["sh", "-c", "nvtop -s 2>/dev/null | grep -m1 '\"gpu_util\"' | grep -oE '[0-9]+'"]
        stdout: StdioCollector { onStreamFinished: if (text.trim() !== "") page.push("gpu", text.trim()) }
    }

    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: page.live
        property int n: 0
        onTriggered: {
            page.tickClock()
            if (!pStatic.running) pLive.running = true
            if (n++ % 2 === 0) pGpu.running = true
        }
    }

    // ================= pieces =================
    // Pixel-art N, drawn as a sprite: 3-px stems, an evenly stepped 3-px diagonal,
    // top-left lighting (lit top/left edges, shaded bottom/right) and a 1-px drop shadow.
    // Pixels drop in diagonally on open; hover sends a glint across.
    component PixelN: Item {
        id: pn
        property int px: 11
        readonly property int gw: 12            // grid width
        readonly property int gh: 12            // grid height
        function on(x, y) {
            if (x < 0 || y < 0 || x >= gw || y >= gh) return false
            if (x < 3 || x >= gw - 3) return true                       // stems
            const s = 2 + Math.round(y * (gw - 6) / (gh - 1))          // diagonal start
            return x >= s && x <= s + 2
        }
        readonly property var cells: {
            const out = []
            for (let y = 0; y <= gh; y++)
                for (let x = 0; x <= gw; x++) {
                    if (on(x, y)) {
                        // 0 lit (top/left edge), 2 shade (bottom/right edge), 1 body
                        const t = !on(x, y - 1) ? 0 : !on(x, y + 1) ? 2 : !on(x - 1, y) ? 0 : !on(x + 1, y) ? 2 : 1
                        out.push({ x: x, y: y, t: t })
                    } else if (on(x - 1, y - 1)) {
                        out.push({ x: x, y: y, t: 3 })                          // drop shadow
                    }
                }
            return out
        }
        width: (gw + 1) * px
        height: (gh + 1) * px

        property real intro: -1
        property real glint: -10
        NumberAnimation on intro { from: -1; to: 26; duration: 600; easing.type: Easing.OutQuad; running: true }
        NumberAnimation { id: glintAnim; target: pn; property: "glint"; from: -3; to: 28; duration: 700; easing.type: Easing.InOutSine }
        HoverHandler { onHoveredChanged: if (hovered && !glintAnim.running) glintAnim.restart() }

        Repeater {
            model: pn.cells
            Rectangle {
                required property var modelData
                readonly property int d: modelData.x + modelData.y
                readonly property bool shine: modelData.t < 3 && Math.abs(pn.glint - d) < 1.2
                x: modelData.x * pn.px
                y: modelData.y * pn.px
                width: pn.px; height: pn.px
                antialiasing: false
                opacity: pn.intro >= d ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 80 } }
                color: shine ? Qt.lighter(Theme.accent, 1.55)
                     : modelData.t === 0 ? Qt.lighter(Theme.accent, 1.2)
                     : modelData.t === 1 ? Theme.accent
                     : modelData.t === 2 ? Qt.darker(Theme.accent, 1.3)
                     : Theme.alpha(Theme.bg, 0.9)
            }
        }
    }

    // `key   value` line, neofetch style
    component Fact: Row {
        property string k: ""
        property string v: ""
        visible: v !== ""
        Text { width: 84; text: parent.k; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
        Text { text: parent.v; color: Theme.text; font.family: page.mono; font.pixelSize: 12 }
    }

    // one live line:  cpu  ▮▮▮▮▮▯▯▯▯▯  9%  56°C · 2.2 GHz
    component Meter: Item {
        id: mt
        property string label: ""
        property real value: 0
        property string extra: ""
        readonly property int segs: 40
        readonly property color tone: value >= 85 ? Theme.danger : Theme.accent
        width: parent.width
        height: 20

        Row {
            id: lead
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text { width: 52; text: mt.label; color: Theme.textDim; font.family: page.mono; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Row {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                    model: mt.segs
                    Rectangle {
                        required property int index
                        width: 6; height: 12
                        color: index < Math.round(mt.value / 100 * mt.segs) ? mt.tone : Theme.alpha(Theme.textFaint, 0.18)
                    }
                }
            }
            Text { width: 54; text: Math.round(mt.value) + "%"; horizontalAlignment: Text.AlignRight; color: Theme.text; font.family: page.mono; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Item { width: 18; height: 1 }
            Text { width: 170; text: mt.extra; elide: Text.ElideRight; color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ================= layout =================
    Flickable {
        id: scrollArea
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds

        WheelHandler {
            onWheel: function (event) {
                scrollArea.contentY = Math.max(0, Math.min(scrollArea.contentHeight - scrollArea.height, scrollArea.contentY - event.angleDelta.y))
                event.accepted = true
            }
        }

        Column {
            id: contentColumn
            anchors { left: parent.left; right: parent.right; rightMargin: page.rightMargin }
            spacing: 14

            Item {
                width: parent.width; height: 26
                Text { text: "System"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19; anchors.verticalCenter: parent.verticalCenter }
                Text { text: page.currentTime; color: Theme.textDim; font.family: page.mono; font.pixelSize: 16; anchors { right: parent.right; verticalCenter: parent.verticalCenter } }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Row {
                spacing: 40
                topPadding: 10
                bottomPadding: 6

                PixelN { px: 11; anchors.top: parent.top; anchors.topMargin: 6 }

                Column {
                    spacing: 5
                    Row {
                        Text { text: page.user; color: Theme.accent; font.family: page.mono; font.pixelSize: 15; font.bold: true }
                        Text { text: "@"; color: Theme.textFaint; font.family: page.mono; font.pixelSize: 15; font.bold: true }
                        Text { text: page.host; color: Theme.accent; font.family: page.mono; font.pixelSize: 15; font.bold: true }
                    }
                    Text {
                        text: "-".repeat((page.user + "@" + page.host).length)
                        color: Theme.textFaint; font.family: page.mono; font.pixelSize: 15
                    }
                    Fact { k: "host";     v: page.model }
                    Fact { k: "os";       v: page.os }
                    Fact { k: "kernel";   v: page.kernel }
                    Fact { k: "wm";       v: page.wm }
                    Fact { k: "shell";    v: page.shell }
                    Fact { k: "packages"; v: page.pkgs }
                    Fact { k: "uptime";   v: page.uptime }
                    Fact { k: "cpu";      v: page.cpu + (page.cpuCores ? " (" + page.cpuCores + ")" : "") }
                    Fact { k: "gpu";      v: page.gpu }
                    Fact { k: "battery";  v: page.battery }
                    // colour blocks, like the bottom of a neofetch
                    Row {
                        topPadding: 8
                        Repeater {
                            model: [Theme.bgPanel, Theme.bgCard, Theme.border, Theme.textFaint, Theme.textDim, Theme.text, Theme.accent2, Theme.accent, Theme.ok, Theme.danger]
                            Rectangle { required property color modelData; width: 22; height: 12; color: modelData }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            Column {
                width: parent.width
                spacing: 12
                topPadding: 4
                Meter { label: "cpu"; value: page.cpuUsage;    extra: [page.cpuTemp, page.cpuFreq].filter(s => s).join(" · ") }
                Meter { label: "mem"; value: page.memoryUsage; extra: page.memory }
                Meter { label: "gpu"; value: page.gpuUsage;    extra: page.gpuFreq }
            }
        }
    }
}
