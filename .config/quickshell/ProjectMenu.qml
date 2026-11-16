// ProjectMenu.qml — Displays: connect/mirror/extend, per-screen control, sound, share & record.
// Open with SUPER+P, the bar monitor icon, or when an HDMI/DP screen is plugged in.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root

    property bool showing: false
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: root.showing ? 260 : 150; easing.type: root.showing ? Easing.OutQuint : Easing.InCubic } }

    readonly property string bin: Quickshell.env("HOME") + "/.local/bin/"

    // ---- live data ----
    property var st: ({ monitors: [], mode: "internal", externalConnected: false, sinks: [] })
    property var sh: ({ casting: [], recording: { active: false }, ask: true })
    property string selName: ""
    property bool busy: false
    property bool dragActive: false        // a screen in the layout map is being dragged
    property real recStart: 0
    property int recSecs: 0
    readonly property bool autoAudio: pref.autoAudio

    readonly property var mons: st.monitors || []
    readonly property var sel: mons.find(m => m.name === selName) || mons.find(m => m.enabled) || mons[0] || null
    readonly property int enabledCount: mons.filter(m => m.enabled).length
    readonly property var others: mons.filter(m => m.enabled && sel && m.name !== sel.name)

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "project-menu"
    WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: root.showing ? menuRoot : null }

    // ---------- control ----------
    function open() { showing = true; refresh(); Qt.callLater(function () { menuRoot.forceActiveFocus() }) }
    function close() { showing = false }
    function toggle() { showing ? close() : open() }
    function refresh() {
        if (!pStatus.running) pStatus.running = true
        if (!pShare.running) pShare.running = true
    }
    function run(args) {                       // fire a backend command, then refresh the view
        busy = true
        Quickshell.execDetached({ command: args })
        settle.restart()
    }
    function setMode(m) {
        run([bin + "rice-display", "mode", m])
        if (pref.autoAudio && m !== "internal") audioSoon.restart()
    }
    function setProp(out, ...rest) { run([bin + "rice-display", "set", out].concat(rest)) }
    function lsize(m) {
        let w = m.w / m.scale, h = m.h / m.scale
        if (m.transform === 1 || m.transform === 3 || m.transform === 5 || m.transform === 7) { const t = w; w = h; h = t }
        return { w: w, h: h }
    }
    function hdmiSink() { return (st.sinks || []).find(s => s.hdmi) }
    function fmtTime(s) { return Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60) }

    Timer { id: settle; interval: 900; onTriggered: { root.busy = false; root.refresh() } }
    Timer { id: poll; interval: 2000; running: root.showing && !root.dragActive; repeat: true; onTriggered: root.refresh() }
    Timer { id: clockTick; interval: 1000; running: root.showing && root.sh.recording && root.sh.recording.active; repeat: true
            onTriggered: root.recSecs = Math.max(0, Math.round((Date.now() - root.recStart) / 1000)) }
    Timer { id: audioSoon; interval: 1800; onTriggered: { const h = root.hdmiSink(); if (h && !h.default) root.run([root.bin + "rice-display", "audio", h.name]) } }

    Process { id: pStatus; command: [root.bin + "rice-display", "status"]
        stdout: StdioCollector { onStreamFinished: { try { root.st = JSON.parse(text) } catch (e) {} } } }
    Process { id: pShare; command: [root.bin + "rice-share", "status"]
        stdout: StdioCollector { onStreamFinished: {
            try { const d = JSON.parse(text); root.sh = d
                  if (d.recording && d.recording.active) { root.recStart = Date.now() - d.recording.seconds * 1000; root.recSecs = d.recording.seconds } } catch (e) {} } } }

    // persisted preferences
    FileView {
        id: prefFile
        path: Quickshell.env("HOME") + "/.config/quickshell/state/project-state.json"
        printErrors: false
        onAdapterUpdated: prefSave.restart()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) writeAdapter() }
        adapter: JsonAdapter { id: pref
            property bool autoOpen: true
            property bool autoAudio: true }
    }
    Timer { id: prefSave; interval: 300; onTriggered: prefFile.writeAdapter() }

    IpcHandler {
        target: "project"
        function toggle(): void { root.toggle() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
        function mode(name: string): void { root.setMode(name) }
    }

    // hot-plug: pop the menu up when a screen is connected, and never strand the user on a dead output
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "monitoradded" || ev.name === "monitoraddedv2") {
                root.refresh()
                if (pref.autoOpen) { delayedOpen.restart() }
            } else if (ev.name === "monitorremoved" || ev.name === "monitorremovedv2") {
                rescue.restart()
            }
        }
    }
    Timer { id: delayedOpen; interval: 900; onTriggered: { root.refresh(); if (!root.showing && root.st.externalConnected) root.open() } }
    Timer { id: rescue; interval: 900; onTriggered: { Quickshell.execDetached([root.bin + "rice-display", "rescue"]); root.refresh() } }

    // ================= UI =================
    Item {
        id: menuRoot
        anchors.fill: parent
        focus: true
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_Escape) root.close()
            else if (e.key === Qt.Key_1) root.setMode("internal")
            else if (e.key === Qt.Key_2) root.setMode("mirror")
            else if (e.key === Qt.Key_3) root.setMode("extend")
            else if (e.key === Qt.Key_4) root.setMode("external")
            else return
            e.accepted = true
        }
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.30 * root.prog }
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        component Chip: Rectangle {
            id: chip
            property string label: ""
            property bool on: false
            property bool dim: false
            property bool danger: false
            signal clicked()
            implicitWidth: lab.implicitWidth + 18
            implicitHeight: 26
            radius: 13
            color: on ? Theme.alpha(danger ? Theme.danger : Theme.accent, 0.28) : (ma.containsMouse ? Theme.alpha(Theme.text, 0.10) : Theme.alpha(Theme.text, 0.05))
            border.width: 1
            border.color: on ? (danger ? Theme.danger : Theme.accent) : Theme.alpha(Theme.text, 0.14)
            opacity: dim ? 0.4 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Text { id: lab; anchors.centerIn: parent; text: chip.label; font.family: Theme.fontFamily; font.pixelSize: 11
                   color: chip.on ? (chip.danger ? Theme.danger : Theme.accent) : Theme.textDim }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: !chip.dim; onClicked: chip.clicked() }
        }
        component Section: Text {
            color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 2
        }

        Rectangle {
            id: card
            width: 680
            height: Math.min(root.height - 60, 760)
            anchors.centerIn: parent
            radius: 18
            color: Theme.alpha(Theme.bgPanel, 0.88)
            border.width: 1
            border.color: Theme.alpha(Theme.text, 0.14)
            visible: root.prog > 0.01
            opacity: Math.min(1, root.prog)
            scale: 0.95 + 0.05 * root.prog
            MouseArea { anchors.fill: parent }

            // header
            Item {
                id: header
                x: 24; y: 18; width: parent.width - 48; height: 40
                Text { id: ttl; text: "Displays"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 22; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    anchors.left: ttl.right; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter
                    height: 22; width: pill.implicitWidth + 20; radius: 11
                    color: root.st.externalConnected ? Theme.alpha(Theme.ok, 0.22) : Theme.alpha(Theme.text, 0.08)
                    Text { id: pill; anchors.centerIn: parent; font.family: Theme.fontFamily; font.pixelSize: 11
                           text: root.st.externalConnected ? "  external connected" : "no external screen"
                           color: root.st.externalConnected ? Theme.ok : Theme.textDim }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Chip { label: "  Detect"; onClicked: { root.run(["hyprctl", "reload"]) } }
                    Chip { label: ""; onClicked: root.close() }
                }
            }

            Flickable {
                id: flick
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; topMargin: 8; bottomMargin: 14 }
                contentWidth: width; contentHeight: body.implicitHeight + 8
                clip: true; boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: body
                    x: 24; width: flick.width - 48
                    spacing: 16

                    // ---------------- MODE ----------------
                    Section { text: "PROJECT   ·   1 2 3 4" }
                    Item {
                        id: tiles
                        width: parent.width; height: 78
                        readonly property var defs: [
                            { id: "internal", icon: "", label: "Laptop only", sub: "this screen" },
                            { id: "mirror",   icon: "", label: "Mirror",      sub: "same on both" },
                            { id: "extend",   icon: "", label: "Extend",      sub: "one big desktop" },
                            { id: "external", icon: "", label: "External only", sub: "turn laptop off" } ]
                        readonly property int curIdx: Math.max(0, defs.findIndex(d => d.id === root.st.mode))
                        readonly property real tw: (width - 3 * 8) / 4
                        Rectangle {          // sliding highlight
                            x: tiles.curIdx * (tiles.tw + 8); width: tiles.tw; height: parent.height; radius: 12
                            color: Theme.alpha(Theme.accent, 0.20); border.width: 1.5; border.color: Theme.accent
                            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.1 } }
                        }
                        Repeater {
                            model: tiles.defs
                            delegate: Item {
                                id: tile
                                required property var modelData
                                required property int index
                                readonly property bool usable: modelData.id === "internal" || root.st.externalConnected
                                x: index * (tiles.tw + 8); width: tiles.tw; height: tiles.height
                                opacity: usable ? 1 : 0.35
                                Rectangle { anchors.fill: parent; radius: 12; color: Theme.alpha(Theme.text, tMa.containsMouse && tile.usable ? 0.08 : 0.03); Behavior on color { ColorAnimation { duration: 120 } } }
                                Column {
                                    anchors.centerIn: parent; spacing: 3
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.icon; color: root.st.mode === tile.modelData.id ? Theme.accent : Theme.text
                                           font.family: Theme.iconFont; font.pixelSize: 22; scale: tMa.pressed ? 0.9 : 1; Behavior on scale { NumberAnimation { duration: 90 } } }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.label; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 12; font.bold: true }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.modelData.sub; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 9 }
                                }
                                MouseArea { id: tMa; anchors.fill: parent; hoverEnabled: true; enabled: tile.usable; onClicked: root.setMode(tile.modelData.id) }
                            }
                        }
                    }
                    Text {
                        visible: !root.st.externalConnected
                        width: parent.width; wrapMode: Text.WordWrap
                        text: "Plug in an HDMI / DisplayPort screen or projector and it will show up here automatically."
                        color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11
                    }

                    // ---------------- LAYOUT MAP ----------------
                    Section { text: "LAYOUT   ·   drag a screen to place it, click to configure" }
                    Rectangle {
                        id: map
                        width: parent.width; height: 240; radius: 12
                        color: Theme.alpha(Theme.text, 0.035)
                        clip: true
                        readonly property var act: root.mons.filter(m => m.enabled)
                        readonly property var bb: {
                            if (act.length === 0) return { x: 0, y: 0, w: 1920, h: 1080 }
                            let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
                            for (const m of act) { const s = root.lsize(m); x0 = Math.min(x0, m.x); y0 = Math.min(y0, m.y); x1 = Math.max(x1, m.x + s.w); y1 = Math.max(y1, m.y + s.h) }
                            // leave empty room around the screens so one can be dragged to any side
            let mw = 0, mh = 0
            for (const m of act) { const s = root.lsize(m); mw = Math.max(mw, s.w); mh = Math.max(mh, s.h) }
            const pw = mw * 0.5, ph = mh * 0.45
            return { x: x0 - pw, y: y0 - ph, w: Math.max(1, x1 - x0 + 2 * pw), h: Math.max(1, y1 - y0 + 2 * ph) }
                        }
                        readonly property real k: Math.min((width - 60) / bb.w, (height - 36) / bb.h)
                        readonly property real ox: (width - bb.w * k) / 2
                        readonly property real oy: (height - bb.h * k) / 2
                        Repeater {
                            model: map.act
                            delegate: Rectangle {
                                id: mr
                                required property var modelData
                                required property int index
                                readonly property var s: root.lsize(modelData)
                                readonly property bool mirrored: modelData.mirrorOf && modelData.mirrorOf !== "none"
                                property real dx: 0
                                property real dy: 0
                                readonly property bool dragging: ma.pressed && ma.moved
                                z: dragging ? 10 : 0
                                x: map.ox + (modelData.x - map.bb.x) * map.k + (mirrored ? 10 : 0) + dx
                                y: map.oy + (modelData.y - map.bb.y) * map.k + (mirrored ? 10 : 0) + dy
                                // drop: snap to the other screens' edges, keep clear of overlaps, then apply + remember
                                function drop() {
                                    let nx = Math.round(modelData.x + dx / map.k), ny = Math.round(modelData.y + dy / map.k)
                                    const others = map.act.filter(o => o.name !== modelData.name)
                                    const snap = Math.max(60, 30 / map.k)        // ~30 px on the map
                                    let bx = nx, by = ny, bdx = snap, bdy = snap
                                    for (const o of others) {
                                        const os = root.lsize(o)
                                        for (const c of [o.x + os.w, o.x - s.w, o.x, o.x + os.w - s.w]) if (Math.abs(c - nx) < bdx) { bdx = Math.abs(c - nx); bx = c }
                                        for (const c of [o.y + os.h, o.y - s.h, o.y, o.y + os.h - s.h]) if (Math.abs(c - ny) < bdy) { bdy = Math.abs(c - ny); by = c }
                                    }
                                    for (const o of others) {                       // resolve any overlap along the shallower axis
                                        const os = root.lsize(o)
                                        const ox = Math.min(bx + s.w, o.x + os.w) - Math.max(bx, o.x)
                                        const oy = Math.min(by + s.h, o.y + os.h) - Math.max(by, o.y)
                                        if (ox > 0 && oy > 0) {
                                            if (ox < oy) bx = (bx + s.w / 2 < o.x + os.w / 2) ? o.x - s.w : o.x + os.w
                                            else         by = (by + s.h / 2 < o.y + os.h / 2) ? o.y - s.h : o.y + os.h
                                        }
                                    }
                                    root.setProp(modelData.name, "pos", bx + "x" + by)
                                }
                                width: s.w * map.k; height: s.h * map.k
                                radius: 6
                                color: Theme.alpha(modelData.internal ? Theme.accent2 : Theme.accent, root.sel && root.sel.name === modelData.name ? 0.35 : 0.16)
                                border.width: root.sel && root.sel.name === modelData.name ? 2 : 1
                                border.color: root.sel && root.sel.name === modelData.name ? Theme.accent : Theme.alpha(Theme.text, 0.3)
                                Behavior on x { enabled: !mr.dragging; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on y { enabled: !mr.dragging; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                                Column {
                                    anchors.centerIn: parent; spacing: 1
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: (mr.modelData.internal ? " " : " ") + mr.modelData.name
                                           color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; text: mr.modelData.w + "×" + mr.modelData.h + (mr.mirrored ? "  · mirror" : "")
                                           color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 9 }
                                }
                                MouseArea {
                                    id: ma
                                    anchors.fill: parent
                                    property real px: 0
                                    property real py: 0
                                    property bool moved: false
                                    onPressed: m => { const p = mapToItem(map, m.x, m.y); px = p.x; py = p.y; moved = false
                                                      root.selName = mr.modelData.name; root.dragActive = true }
                                    onPositionChanged: m => { if (!pressed) return
                                        const p = mapToItem(map, m.x, m.y)
                                        mr.dx = p.x - px; mr.dy = p.y - py
                                        if (Math.abs(mr.dx) + Math.abs(mr.dy) > 6) moved = true }
                                    onReleased: { root.dragActive = false
                                        if (moved && (Math.abs(mr.dx) + Math.abs(mr.dy) > 6)) mr.drop()
                                        mr.dx = 0; mr.dy = 0; moved = false }
                                    onCanceled: { root.dragActive = false; mr.dx = 0; mr.dy = 0; moved = false }
                                }
                            }
                        }
                    }
                    Row {
                        visible: root.mons.some(m => !m.enabled)
                        spacing: 6
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Off:"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11 }
                        Repeater {
                            model: root.mons.filter(m => !m.enabled)
                            delegate: Chip { required property var modelData; label: "  Turn on " + modelData.name; onClicked: root.setProp(modelData.name, "on") }
                        }
                    }

                    // ---------------- SELECTED DISPLAY ----------------
                    Rectangle {
                        id: detail
                        visible: root.sel !== null
                        width: parent.width; height: dcol.implicitHeight + 28; radius: 12
                        color: Theme.alpha(Theme.text, 0.04)
                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        clip: true
                        Column {
                            id: dcol
                            x: 14; y: 14; width: parent.width - 28; spacing: 10
                            Row {
                                spacing: 10
                                Text { text: root.sel ? root.sel.name : ""; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 15; font.bold: true }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: root.sel ? root.sel.label + "  ·  " + root.sel.w + "×" + root.sel.h + " @ " + root.sel.hz + " Hz" : ""
                                       color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11 }
                            }
                            Section { text: "RESOLUTION" }
                            Flow {
                                width: parent.width; spacing: 5
                                Repeater {
                                    model: root.sel ? root.sel.modes.slice(0, 10) : []
                                    delegate: Chip {
                                        required property var modelData
                                        label: modelData.res
                                        on: root.sel && (root.sel.w + "x" + root.sel.h) === modelData.res
                                        onClicked: root.setProp(root.sel.name, "mode", modelData.res + "@" + modelData.hz[0].toFixed(2))
                                    }
                                }
                            }
                            Section { text: "REFRESH RATE"; visible: refreshFlow.count > 1 }
                            Flow {
                                id: refreshFlow
                                readonly property var hzs: { if (!root.sel) return []; const m = root.sel.modes.find(x => x.res === root.sel.w + "x" + root.sel.h); return m ? m.hz : [] }
                                readonly property int count: hzs.length
                                visible: count > 1
                                width: parent.width; spacing: 5
                                Repeater {
                                    model: refreshFlow.hzs
                                    delegate: Chip { required property var modelData; label: modelData.toFixed(modelData % 1 === 0 ? 0 : 2) + " Hz"
                                        on: root.sel && Math.abs(root.sel.hz - modelData) < 0.05
                                        onClicked: root.setProp(root.sel.name, "mode", root.sel.w + "x" + root.sel.h + "@" + modelData.toFixed(2)) }
                                }
                            }
                            Row {
                                spacing: 24
                                Column {
                                    spacing: 6
                                    Section { text: "SCALE" }
                                    Row { spacing: 5
                                        Repeater { model: [1, 1.25, 1.5, 1.75, 2]
                                            delegate: Chip { required property var modelData; label: (modelData * 100) + "%"; on: root.sel && Math.abs(root.sel.scale - modelData) < 0.02
                                                onClicked: root.setProp(root.sel.name, "scale", String(modelData)) } } }
                                }
                                Column {
                                    spacing: 6
                                    Section { text: "ROTATION" }
                                    Row { spacing: 5
                                        Repeater { model: [0, 90, 180, 270]
                                            delegate: Chip { required property var modelData; label: modelData + "°"
                                                on: root.sel && root.sel.transform % 4 === modelData / 90
                                                onClicked: root.setProp(root.sel.name, "rotate", String(modelData)) } } }
                                }
                            }
                            Column {
                                spacing: 6
                                visible: root.others.length > 0 && root.st.mode === "extend"
                                Section { text: "POSITION  (relative to " + (root.others[0] ? root.others[0].name : "") + ")" }
                                Row { spacing: 5
                                    Repeater { model: [ { l: "  Left of", v: "left" }, { l: "  Right of", v: "right" }, { l: "  Above", v: "above" }, { l: "  Below", v: "below" } ]
                                        delegate: Chip { required property var modelData; label: modelData.l
                                            onClicked: root.setProp(root.sel.name, "pos", modelData.v, root.others[0].name) } } }
                            }
                            Row {
                                spacing: 6
                                Chip { label: root.sel && root.sel.enabled ? "  Turn this screen off" : "  Turn on"; dim: root.enabledCount <= 1 && root.sel && root.sel.enabled
                                       onClicked: root.setProp(root.sel.name, root.sel.enabled ? "off" : "on") }
                            }
                        }
                    }

                    // ---------------- SOUND ----------------
                    Section { text: "SOUND OUTPUT" }
                    Column {
                        width: parent.width; spacing: 4
                        Repeater {
                            model: root.st.sinks || []
                            delegate: Rectangle {
                                id: sk
                                required property var modelData
                                width: parent.width; height: 34; radius: 9
                                color: skMa.containsMouse ? Theme.alpha(Theme.text, 0.09) : Theme.alpha(Theme.text, 0.04)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Rectangle { x: 12; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7
                                    color: "transparent"; border.width: 1.5; border.color: sk.modelData.default ? Theme.accent : Theme.alpha(Theme.text, 0.4)
                                    Rectangle { anchors.centerIn: parent; width: sk.modelData.default ? 8 : 0; height: width; radius: width / 2; color: Theme.accent
                                                Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutBack } } } }
                                Text { x: 36; width: parent.width - 120; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                       text: sk.modelData.desc.replace(/^.*?High Definition Audio \(HD Audio\)\s*/, "")
                                       color: sk.modelData.default ? Theme.text : Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12 }
                                Text { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                                       visible: sk.modelData.hdmi; text: "HDMI / DP"; color: Theme.accent; font.family: Theme.fontFamily; font.pixelSize: 10 }
                                MouseArea { id: skMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.run([root.bin + "rice-display", "audio", sk.modelData.name]) }
                            }
                        }
                    }

                    // ---------------- SHARE & RECORD ----------------
                    Section { text: "SHARE & RECORD" }
                    Rectangle {
                        width: parent.width; height: shareCol.implicitHeight + 28; radius: 12
                        color: Theme.alpha(Theme.text, 0.04)
                        Column {
                            id: shareCol
                            x: 14; y: 14; width: parent.width - 28; spacing: 10

                            // live sharing status
                            Row {
                                spacing: 10
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5
                                    color: root.sh.casting && root.sh.casting.length ? Theme.danger : Theme.textFaint
                                    SequentialAnimation on opacity { running: root.sh.casting && root.sh.casting.length > 0; loops: Animation.Infinite
                                        NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 } } }
                                Text { anchors.verticalCenter: parent.verticalCenter
                                       text: root.sh.casting && root.sh.casting.length ? "Sharing your screen (" + root.sh.casting.length + " stream" + (root.sh.casting.length > 1 ? "s" : "") + ")" : "Not sharing your screen"
                                       color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13 }
                                Chip { visible: root.sh.casting && root.sh.casting.length > 0; danger: true; on: true; label: "  Stop sharing"
                                       onClicked: { for (const c of root.sh.casting) root.run([root.bin + "rice-share", "stop-cast", String(c.id)]) } }
                            }
                            Text {
                                width: parent.width; wrapMode: Text.WordWrap
                                text: "To share in Meet, Zoom, Discord, Teams or OBS: choose “Share screen” in the app, then pick the display in Hyprland's picker."
                                color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11
                            }
                            Row {
                                spacing: 6
                                Chip { label: root.sh.ask ? "  Always ask which screen" : "Remember my choice"; on: root.sh.ask
                                       onClicked: root.run([root.bin + "rice-share", "ask", root.sh.ask ? "off" : "on"]) }
                            }

                            Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.text, 0.08) }

                            // recording
                            Row {
                                spacing: 8
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "Record:"; color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12 }
                                Repeater {
                                    model: root.mons.filter(m => m.enabled)
                                    delegate: Chip { required property var modelData; label: "  " + modelData.name
                                        dim: root.sh.recording && root.sh.recording.active
                                        onClicked: root.run([root.bin + "rice-share", "record", "start", modelData.name]) }
                                }
                                Chip { label: "  Region"; dim: root.sh.recording && root.sh.recording.active
                                       onClicked: { root.close(); root.run([root.bin + "rice-share", "record", "start", "region"]) } }
                            }
                            Row {
                                visible: root.sh.recording && root.sh.recording.active
                                spacing: 10
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: Theme.danger
                                    SequentialAnimation on opacity { running: root.sh.recording && root.sh.recording.active; loops: Animation.Infinite
                                        NumberAnimation { to: 0.25; duration: 600 } NumberAnimation { to: 1; duration: 600 } } }
                                Text { anchors.verticalCenter: parent.verticalCenter; text: "Recording  " + root.fmtTime(root.recSecs); color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13; font.bold: true }
                                Chip { danger: true; on: true; label: "  Stop & save"; onClicked: root.run([root.bin + "rice-share", "record", "stop"]) }
                            }
                            Row {
                                spacing: 6
                                Chip { label: "  Open recordings"; onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p ~/Videos/Recordings; xdg-open ~/Videos/Recordings"]) }
                            }
                        }
                    }

                    // ---------------- PREFERENCES ----------------
                    Section { text: "PREFERENCES" }
                    Row {
                        spacing: 6
                        Chip { label: "Open menu when a screen is plugged in"; on: pref.autoOpen; onClicked: pref.autoOpen = !pref.autoOpen }
                        Chip { label: "Switch sound to HDMI"; on: pref.autoAudio; onClicked: pref.autoAudio = !pref.autoAudio }
                    }
                    Item { width: 1; height: 4 }
                }
            }
        }
    }
}
