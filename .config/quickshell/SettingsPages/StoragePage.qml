// StoragePage.qml — disks, filesystems and one-click cleanup.
// Same look as the other pages. Sizes are measured when the page opens (and after a
// cleanup), not on a loop; disk usage refreshes every 10 s only while Settings is open.
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

    property var disks: []          // [{ name, model, size, tran, mounts: [df rows] }]
    property var info: ({})         // cleanup sizes, see pScan
    property bool scanned: false
    property string confirming: ""  // key of the item asking "sure?"
    property string running: ""     // key of the item being cleaned
    property var results: ({})      // key -> "freed 1.2 GB" / error

    function fmt(b) {
        if (!isFinite(b) || b <= 0) return "0 B"
        const u = ["B", "KB", "MB", "GB", "TB"]; let i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (i ? b.toFixed(1) : Math.round(b)) + " " + u[i]
    }
    // "3.15 GiB", "490M", "12 KB" -> bytes
    function parseSize(s) {
        const m = String(s || "").replace(/\s+/g, "").match(/^([0-9.]+)([KMGT]?)(i?B)?$/i)
        if (!m) return 0
        return parseFloat(m[1]) * Math.pow(1024, " KMGT".indexOf((m[2] || " ").toUpperCase()))
    }
    function tone(p) { return p >= 90 ? Theme.danger : Theme.accent }

    // ---------- disks + filesystems ----------
    Process {
        id: pDisks
        command: ["sh", "-c", "lsblk -J -b -d -o NAME,MODEL,SIZE,TYPE,TRAN; echo '#'; df -P -B1 -T"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [blk, dfText] = text.split("\n#\n")
                let list = []
                try {
                    list = (JSON.parse(blk).blockdevices || [])
                        .filter(d => d.type === "disk" && !/^(zram|loop|ram)/.test(d.name))
                        .map(d => ({ name: d.name, model: (d.model || "").trim(), size: Number(d.size) || 0, tran: d.tran || "", mounts: [] }))
                } catch (e) {}
                for (const line of (dfText || "").split("\n").slice(1)) {
                    const f = line.trim().split(/\s+/)
                    if (f.length < 7 || !f[0].startsWith("/dev/")) continue
                    const row = { dev: f[0], type: f[1], total: Number(f[2]), used: Number(f[3]), free: Number(f[4]), pct: parseInt(f[5]), mount: f.slice(6).join(" ") }
                    const disk = list.find(d => f[0].startsWith("/dev/" + d.name))
                    // one row per device (bind mounts / btrfs subvolumes show up several times)
                    if (disk && !disk.mounts.some(m => m.dev === row.dev)) disk.mounts.push(row)
                }
                for (const d of list) d.mounts.sort((a, b) => a.mount.length - b.mount.length)
                page.disks = list
            }
        }
    }
    Timer { interval: 10000; repeat: true; running: page.live; onTriggered: pDisks.running = true }

    // ---------- cleanup sizes (on open / after a cleanup) ----------
    Process {
        id: pScan
        command: ["sh", "-c",
            "s() { du -sb \"$1\" 2>/dev/null | cut -f1; };" +
            "echo \"trash $(s \"$HOME/.local/share/Trash\")\";" +
            "echo \"thumbs $(s \"$HOME/.cache/quickshell/thumbs\")\";" +
            "echo \"yay $(s \"$HOME/.cache/yay\")\";" +
            "echo \"clip $(cliphist list 2>/dev/null | wc -l)\";" +
            "echo \"journal $(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+ ?[KMGT]?i?B?' | head -1 | tr -d ' ')\";" +
            "echo \"pacman $(s /var/cache/pacman/pkg)\";" +
            "echo \"pacold $(paccache -dk1 2>/dev/null | grep -oE 'saved: [0-9.]+ [KMGT]?i?B' | cut -d' ' -f2- | tr -d ' ')\";" +
            "echo \"pacgone $(paccache -duk0 2>/dev/null | grep -oE 'saved: [0-9.]+ [KMGT]?i?B' | cut -d' ' -f2- | tr -d ' ')\";" +
            "command -v flatpak >/dev/null && echo \"flatpak $(flatpak list 2>/dev/null | wc -l)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {}
                for (const line of text.split("\n")) {
                    const [k, v] = line.trim().split(" ")
                    if (!k) continue
                    o[k] = (k === "clip" || k === "flatpak") ? (parseInt(v) || 0) : (/^[0-9]+$/.test(v || "") ? Number(v) : page.parseSize(v))
                }
                page.info = o
                page.scanned = true
            }
        }
    }

    function refreshAll() { pDisks.running = true; if (!pScan.running) pScan.running = true }
    onLiveChanged: if (live) refreshAll()
    Component.onCompleted: refreshAll()

    // ---------- cleanup actions ----------
    readonly property var items: [
        { key: "trash", label: "trash", note: "files you deleted",
          size: () => info.trash, verb: "empty",
          cmd: "rm -rf -- \"$HOME/.local/share/Trash/files/\"* \"$HOME/.local/share/Trash/info/\"* \"$HOME/.local/share/Trash/expunged/\"* 2>/dev/null; true" },
        { key: "clip", label: "clipboard", note: "history entries",
          text: () => (info.clip || 0) + " items", verb: "wipe", cmd: "cliphist wipe" },
        { key: "thumbs", label: "thumbnails", note: "wallpaper picker cache, rebuilt on demand",
          size: () => info.thumbs, verb: "clear", cmd: "rm -rf -- \"$HOME/.cache/quickshell/thumbs/\"*" },
        { key: "yay", label: "yay cache", note: "AUR build files",
          size: () => info.yay, verb: "clean", cmd: "rm -rf -- \"$HOME/.cache/yay/\"*" },
        { key: "pacman", label: "pacman cache", note: "keeps only the installed version of each package",
          size: () => (info.pacold || 0) + (info.pacgone || 0), approx: true, of: () => info.pacman, verb: "clean", root: true,
          cmd: "pkexec sh -c 'paccache -rk1; paccache -ruk0'" },
        { key: "journal", label: "system logs", note: "trimmed to the last 7 days",
          size: () => info.journal, verb: "trim", root: true,
          cmd: "pkexec journalctl --vacuum-time=7d" },
        { key: "flatpak", label: "flatpak", note: "unused runtimes", hide: () => !info.flatpak,
          text: () => "", verb: "clean", cmd: "flatpak uninstall --unused -y --noninteractive" }
    ]

    Process {
        id: pClean
        property string key: ""
        property real before: 0
        stderr: StdioCollector { id: cleanErr }
        onExited: code => {
            const r = Object.assign({}, page.results)
            r[pClean.key] = code === 0 ? "done" : (code === 126 || code === 127 ? "cancelled" : (cleanErr.text.trim().split("\n").pop() || "failed").slice(0, 70))
            page.results = r
            page.running = ""
            page.refreshAll()
        }
    }
    function clean(it) {
        if (pClean.running) return
        confirming = ""; running = it.key
        const r = Object.assign({}, results); delete r[it.key]; results = r
        pClean.key = it.key; pClean.command = ["sh", "-c", it.cmd]; pClean.running = true
    }

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

            Text { text: "Storage"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19 }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            // disks
            Repeater {
                model: page.disks
                Column {
                    id: disk
                    required property var modelData
                    width: content.width
                    spacing: 8

                    Item {
                        width: parent.width; height: 18
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Text { text: disk.modelData.model || disk.modelData.name; color: Theme.text; font.family: page.mono; font.pixelSize: 13; font.bold: true }
                            Text { text: [disk.modelData.tran, page.fmt(disk.modelData.size)].filter(s => s).join("  ·  "); color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11; anchors.baseline: parent.children[0].baseline }
                        }
                        Act { anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                              text: "what's using space?"; onClicked: Quickshell.execDetached(["baobab"]) }
                    }

                    Repeater {
                        model: disk.modelData.mounts
                        Item {
                            id: mrow
                            required property var modelData
                            width: disk.width; height: 20
                            Text { id: ml; width: 84; anchors.verticalCenter: parent.verticalCenter; text: mrow.modelData.mount; elide: Text.ElideRight; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
                            Rectangle {
                                anchors { left: ml.right; right: mp.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                height: 4; radius: 2
                                color: Theme.alpha(Theme.textFaint, 0.18)
                                Rectangle {
                                    width: parent.width * Math.min(1, mrow.modelData.pct / 100); height: parent.height; radius: 2
                                    color: page.tone(mrow.modelData.pct)
                                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                            Text { id: mp; anchors { right: md.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                                   width: 40; horizontalAlignment: Text.AlignRight
                                   text: mrow.modelData.pct + "%"; color: mrow.modelData.pct >= 90 ? Theme.danger : Theme.text; font.family: page.mono; font.pixelSize: 12 }
                            Text { id: md; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                   width: 190; horizontalAlignment: Text.AlignRight
                                   text: page.fmt(mrow.modelData.free) + " free of " + page.fmt(mrow.modelData.total)
                                   color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11 }
                        }
                    }
                    Item { width: 1; height: 2 }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            Item {
                width: parent.width; height: 16
                Text { text: "cleanup"; color: Theme.textDim; font.family: page.mono; font.pixelSize: 12 }
                Text { anchors.right: parent.right; text: page.scanned ? "" : "measuring…"; color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11 }
            }

            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: page.items
                    Item {
                        id: ci
                        required property var modelData
                        readonly property real bytes: modelData.size ? (modelData.size() || 0) : 0
                        readonly property string amount: !page.scanned ? "…" : modelData.text ? modelData.text() : (modelData.approx && bytes > 0 ? "~" : "") + page.fmt(bytes)
                        readonly property bool empty: page.scanned && (modelData.size ? bytes <= 0 : modelData.key === "clip" ? !page.info.clip : false)
                        readonly property string result: page.results[modelData.key] || ""
                        visible: !(modelData.hide && modelData.hide())
                        width: parent.width; height: visible ? 34 : 0

                        Text { id: cl; width: 120; y: 2; text: ci.modelData.label; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
                        Text { id: ca; anchors { left: cl.right; baseline: cl.baseline } width: 90
                               text: ci.amount; color: ci.empty ? Theme.textFaint : Theme.text; font.family: page.mono; font.pixelSize: 12 }
                        Text { anchors { left: cl.left; top: cl.bottom; topMargin: 2 }
                               text: ci.modelData.note + (ci.modelData.of && page.scanned ? "  ·  " + page.fmt(ci.modelData.of()) + " total" : "") + (ci.modelData.root ? "  ·  asks for your password" : "")
                               color: Theme.textFaint; font.family: page.mono; font.pixelSize: 10 }

                        Row {
                            anchors { right: parent.right; top: parent.top; topMargin: 2 }
                            spacing: 14
                            Text { visible: ci.result !== "" && page.running !== ci.modelData.key; text: ci.result
                                   color: ci.result === "done" ? Theme.textDim : Theme.danger; font.family: page.mono; font.pixelSize: 11 }
                            Text { visible: page.running === ci.modelData.key; text: "working…"; color: Theme.textDim; font.family: page.mono; font.pixelSize: 11 }
                            Act { visible: page.confirming === ci.modelData.key; text: "cancel"; onClicked: page.confirming = "" }
                            Act { visible: page.confirming === ci.modelData.key; text: ci.modelData.verb + " now"; warn: true; onClicked: page.clean(ci.modelData) }
                            Act { visible: page.confirming !== ci.modelData.key && page.running !== ci.modelData.key && !ci.empty && page.scanned
                                  text: ci.modelData.verb; onClicked: page.confirming = ci.modelData.key }
                        }
                    }
                }
            }
        }
    }
}
