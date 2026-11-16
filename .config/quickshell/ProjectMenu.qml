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
    property string lastStatus: ""
    property string lastShare: ""
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
        stdout: StdioCollector { onStreamFinished: { if (text === root.lastStatus) return; root.lastStatus = text; try { root.st = JSON.parse(text) } catch (e) {} } } }
    Process { id: pShare; command: [root.bin + "rice-share", "status"]
        stdout: StdioCollector { onStreamFinished: {
            if (text === root.lastShare) return; root.lastShare = text
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
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.35 * root.prog }
        MouseArea { anchors.fill: parent; onClicked: root.close() }

        // ---- small building blocks ----
        component Chip: Rectangle {
            id: chip
            property string label: ""
            property bool on: false
            property bool dim: false
            property bool danger: false
            signal clicked()
            implicitWidth: lab.implicitWidth + 22
            implicitHeight: 28
            radius: 8
            color: on ? Theme.alpha(danger ? Theme.danger : Theme.text, danger ? 0.20 : 0.15)
                      : Theme.alpha(Theme.text, ma.pressed ? 0.14 : (ma.containsMouse ? 0.10 : 0.06))
            opacity: dim ? 0.4 : 1
            Behavior on color { ColorAnimation { duration: 100 } }
            Text { id: lab; anchors.centerIn: parent; text: chip.label; font.family: Theme.fontFamily; font.pixelSize: 12
                   font.weight: chip.on ? Font.DemiBold : Font.Normal
                   color: chip.on ? (chip.danger ? Theme.danger : Theme.text) : Theme.textDim }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: !chip.dim; onClicked: chip.clicked() }
        }
        component Heading: Text {
            color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.Medium
        }
        component Surface: Rectangle {
            radius: 12; color: Theme.alpha(Theme.text, 0.045)
        }
        component Hairline: Rectangle { height: 1; color: Theme.alpha(Theme.text, 0.07) }
        component Toggle: Item {
            id: tg
            property string label: ""
            property bool checked: false
            signal flipped()
            width: parent ? parent.width : 200; height: 42
            Text { x: 14; anchors.verticalCenter: parent.verticalCenter; text: tg.label; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13 }
            Rectangle {
                width: 38; height: 22; radius: 11
                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                color: tg.checked ? Theme.accent : Theme.alpha(Theme.text, 0.18)
                Behavior on color { ColorAnimation { duration: 140 } }
                Rectangle {
                    width: 18; height: 18; radius: 9; y: 2
                    x: tg.checked ? 18 : 2
                    color: tg.checked ? Theme.bgPanel : Theme.text
                    Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                }
            }
            MouseArea { anchors.fill: parent; onClicked: tg.flipped() }
        }

        // ---- the card ----
        Rectangle {
            id: card
            width: 640
            height: Math.min(root.height - 80, 780)
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height) / 2 + (1 - root.prog) * 14
            radius: 16
            color: Theme.alpha(Theme.bgPanel, 0.96)
            border.width: 1; border.color: Theme.alpha(Theme.text, 0.09)
            visible: root.prog > 0.01
            opacity: Math.min(1, root.prog * 1.5)
            MouseArea { anchors.fill: parent }

            Item {
                id: header
                x: 24; y: 20; width: parent.width - 48; height: 32
                Text { id: ttl; text: "Displays"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 20; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                Row {
                    anchors.left: ttl.right; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 7
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 7; height: 7; radius: 3.5
                                color: root.st.externalConnected ? Theme.ok : Theme.textFaint }
                    Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.fontFamily; font.pixelSize: 12; color: Theme.textDim
                           text: root.st.externalConnected ? "External screen connected" : "No external screen" }
                }
                Row {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 8
                    Chip { label: "Detect"; onClicked: root.run(["hyprctl", "reload"]) }
                    Chip { implicitWidth: 28; label: "×"; onClicked: root.close() }
                }
            }

            Flickable {
                id: flick
                anchors { left: parent.left; right: parent.right; top: header.bottom; bottom: parent.bottom; topMargin: 14; bottomMargin: 16 }
                contentWidth: width; contentHeight: body.implicitHeight + 4
                clip: true; boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: body
                    x: 24; width: flick.width - 48
                    spacing: 22

                    // ---------------- mode ----------------
                    Column {
                        width: parent.width; spacing: 10
                        Item {
                            id: seg
                            width: parent.width; height: 46
                            readonly property var defs: [
                                { id: "internal", icon: "", label: "Laptop" },
                                { id: "mirror",   icon: "", label: "Mirror" },
                                { id: "extend",   icon: "", label: "Extend" },
                                { id: "external", icon: "", label: "External" } ]
                            readonly property int curIdx: Math.max(0, defs.findIndex(d => d.id === root.st.mode))
                            readonly property real tw: (width - 8) / 4
                            Rectangle { anchors.fill: parent; radius: 12; color: Theme.alpha(Theme.text, 0.06) }
                            Rectangle {
                                x: 4 + seg.curIdx * seg.tw; y: 4; width: seg.tw; height: seg.height - 8; radius: 9
                                color: Theme.alpha(Theme.text, 0.15)
                                Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Repeater {
                                model: seg.defs
                                delegate: Item {
                                    id: tile
                                    required property var modelData
                                    required property int index
                                    readonly property bool usable: modelData.id === "internal" || root.st.externalConnected
                                    readonly property bool cur: root.st.mode === modelData.id
                                    x: 4 + index * seg.tw; width: seg.tw; height: seg.height
                                    opacity: usable ? 1 : 0.35
                                    Row {
                                        anchors.centerIn: parent; spacing: 8
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: tile.modelData.icon; font.family: Theme.iconFont; font.pixelSize: 15
                                               color: tile.cur ? Theme.text : Theme.textDim }
                                        Text { anchors.verticalCenter: parent.verticalCenter; text: tile.modelData.label; font.family: Theme.fontFamily; font.pixelSize: 13
                                               font.weight: tile.cur ? Font.DemiBold : Font.Normal; color: tile.cur ? Theme.text : Theme.textDim }
                                    }
                                    MouseArea { anchors.fill: parent; enabled: tile.usable; onClicked: root.setMode(tile.modelData.id) }
                                }
                            }
                        }
                        Text {
                            visible: !root.st.externalConnected
                            width: parent.width; wrapMode: Text.WordWrap
                            text: "Plug in a screen, projector or your tablet and it will appear here."
                            color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 12
                        }
                    }

                    // ---------------- arrangement ----------------
                    Column {
                        width: parent.width; spacing: 8
                        Item {
                            width: parent.width; height: 16
                            Heading { text: "Arrangement" }
                            Text { anchors.right: parent.right; text: "Drag a screen to move it"; color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 11 }
                        }
                        Surface {
                            id: map
                            width: parent.width; height: 230
                            clip: true
                            property var ghost: null           // where the screen being dragged will land
                            readonly property var act: root.mons.filter(m => m.enabled)
                            readonly property var bb: {
                                if (act.length === 0) return { x: 0, y: 0, w: 1920, h: 1080 }
                                let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, mw = 0, mh = 0
                                for (const m of act) { const s = root.lsize(m); x0 = Math.min(x0, m.x); y0 = Math.min(y0, m.y); x1 = Math.max(x1, m.x + s.w); y1 = Math.max(y1, m.y + s.h); mw = Math.max(mw, s.w); mh = Math.max(mh, s.h) }
                                const pw = mw * 0.5, ph = mh * 0.45      // empty room so a screen can be dragged to any side
                                return { x: x0 - pw, y: y0 - ph, w: Math.max(1, x1 - x0 + 2 * pw), h: Math.max(1, y1 - y0 + 2 * ph) }
                            }
                            readonly property real k: Math.min((width - 40) / bb.w, (height - 28) / bb.h)
                            readonly property real ox: (width - bb.w * k) / 2
                            readonly property real oy: (height - bb.h * k) / 2

                            Rectangle {                         // landing preview
                                visible: map.ghost !== null
                                x: map.ghost ? map.ox + (map.ghost.x - map.bb.x) * map.k : 0
                                y: map.ghost ? map.oy + (map.ghost.y - map.bb.y) * map.k : 0
                                width: map.ghost ? map.ghost.w * map.k : 0
                                height: map.ghost ? map.ghost.h * map.k : 0
                                radius: 8; color: "transparent"
                                border.width: 1.5; border.color: Theme.alpha(Theme.accent, 0.7)
                            }
                            Repeater {
                                model: map.act
                                delegate: Rectangle {
                                    id: mr
                                    required property var modelData
                                    required property int index
                                    readonly property var s: root.lsize(modelData)
                                    readonly property bool mirrored: modelData.mirrorOf && modelData.mirrorOf !== "none"
                                    readonly property bool selected: root.sel && root.sel.name === modelData.name
                                    property real dx: 0
                                    property real dy: 0
                                    readonly property bool dragging: ma.pressed && ma.moved
                                    readonly property var tgt: dragging ? snapTarget() : null
                                    onTgtChanged: map.ghost = tgt ? { x: tgt.x, y: tgt.y, w: s.w, h: s.h } : null
                                    z: dragging ? 10 : 0
                                    x: map.ox + (modelData.x - map.bb.x) * map.k + (mirrored ? 10 : 0) + dx
                                    y: map.oy + (modelData.y - map.bb.y) * map.k + (mirrored ? 10 : 0) + dy
                                    width: s.w * map.k; height: s.h * map.k
                                    radius: 8
                                    color: Theme.alpha(Theme.text, selected ? 0.16 : 0.09)
                                    border.width: selected ? 1.5 : 1
                                    border.color: selected ? Theme.accent : Theme.alpha(Theme.text, 0.16)
                                    scale: dragging ? 1.02 : 1
                                    Behavior on x { enabled: !mr.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on y { enabled: !mr.dragging; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                    Behavior on scale { NumberAnimation { duration: 120 } }

                                    // snap to the other screens' edges, then keep clear of overlaps
                                    function snapTarget() {
                                        const nx = Math.round(modelData.x + dx / map.k), ny = Math.round(modelData.y + dy / map.k)
                                        const others = map.act.filter(o => o.name !== modelData.name)
                                        const snap = Math.max(60, 30 / map.k)          // about 30 px on the map
                                        let bx = nx, by = ny, bdx = snap, bdy = snap
                                        for (const o of others) {
                                            const os = root.lsize(o)
                                            for (const c of [o.x + os.w, o.x - s.w, o.x, o.x + os.w - s.w]) if (Math.abs(c - nx) < bdx) { bdx = Math.abs(c - nx); bx = c }
                                            for (const c of [o.y + os.h, o.y - s.h, o.y, o.y + os.h - s.h]) if (Math.abs(c - ny) < bdy) { bdy = Math.abs(c - ny); by = c }
                                        }
                                        for (const o of others) {
                                            const os = root.lsize(o)
                                            const ox = Math.min(bx + s.w, o.x + os.w) - Math.max(bx, o.x)
                                            const oy = Math.min(by + s.h, o.y + os.h) - Math.max(by, o.y)
                                            if (ox > 0 && oy > 0) {
                                                if (ox < oy) bx = (bx + s.w / 2 < o.x + os.w / 2) ? o.x - s.w : o.x + os.w
                                                else         by = (by + s.h / 2 < o.y + os.h / 2) ? o.y - s.h : o.y + os.h
                                            }
                                        }
                                        return { x: bx, y: by }
                                    }
                                    function drop() {
                                        const t = snapTarget()
                                        dx = (t.x - modelData.x) * map.k; dy = (t.y - modelData.y) * map.k    // glide into place while it applies
                                        root.setProp(modelData.name, "pos", t.x + "x" + t.y)
                                    }

                                    Column {
                                        anchors.centerIn: parent; spacing: 2
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: mr.modelData.name
                                               color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
                                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: mr.modelData.w + " × " + mr.modelData.h + (mr.mirrored ? "  mirror" : "")
                                               color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 10 }
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
                                            if (moved && (Math.abs(mr.dx) + Math.abs(mr.dy) > 6)) mr.drop(); else { mr.dx = 0; mr.dy = 0 }
                                            moved = false; map.ghost = null }
                                        onCanceled: { root.dragActive = false; mr.dx = 0; mr.dy = 0; moved = false; map.ghost = null }
                                    }
                                }
                            }
                        }
                        Row {
                            visible: root.mons.some(m => !m.enabled)
                            spacing: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "Off"; color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 12 }
                            Repeater {
                                model: root.mons.filter(m => !m.enabled)
                                delegate: Chip { required property var modelData; label: "Turn on " + modelData.name; onClicked: root.setProp(modelData.name, "on") }
                            }
                        }
                    }

                    // ---------------- selected screen ----------------
                    Surface {
                        id: detail
                        visible: root.sel !== null
                        width: parent.width; height: dcol.implicitHeight + 36
                        clip: true
                        Column {
                            id: dcol
                            x: 18; y: 18; width: parent.width - 36; spacing: 18
                            Column {
                                spacing: 3
                                Text { text: root.sel ? root.sel.name : ""; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Text { text: root.sel ? [root.sel.label, root.sel.w + " × " + root.sel.h, root.sel.hz + " Hz"].filter(x => x).join("  ·  ") : ""
                                       color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12 }
                            }
                            Column {
                                width: parent.width; spacing: 8
                                Heading { text: "Resolution" }
                                Flow {
                                    width: parent.width; spacing: 6
                                    Repeater {
                                        model: root.sel ? root.sel.modes.slice(0, 10) : []
                                        delegate: Chip { required property var modelData; label: modelData.res
                                            on: root.sel && modelData.res === root.sel.w + "x" + root.sel.h
                                            onClicked: root.setProp(root.sel.name, "mode", modelData.res + "@" + modelData.hz[0].toFixed(2)) }
                                    }
                                }
                            }
                            Column {
                                width: parent.width; spacing: 8
                                Heading { text: "Refresh rate" }
                                Flow {
                                    id: refreshFlow
                                    width: parent.width; spacing: 6
                                    readonly property var hzs: {
                                        if (!root.sel) return []
                                        const m = root.sel.modes.find(x => x.res === root.sel.w + "x" + root.sel.h)
                                        return m ? m.hz.filter(h => h >= 24).slice(0, 8) : [root.sel.hz]
                                    }
                                    Repeater {
                                        model: refreshFlow.hzs
                                        delegate: Chip { required property var modelData; label: modelData.toFixed(modelData % 1 === 0 ? 0 : 2) + " Hz"
                                            on: root.sel && Math.abs(root.sel.hz - modelData) < 0.05
                                            onClicked: root.setProp(root.sel.name, "mode", root.sel.w + "x" + root.sel.h + "@" + modelData.toFixed(2)) }
                                    }
                                }
                            }
                            Row {
                                spacing: 36
                                Column {
                                    spacing: 8
                                    Heading { text: "Scale" }
                                    Row { spacing: 6
                                        Repeater { model: [1, 1.25, 1.5, 1.75, 2]
                                            delegate: Chip { required property var modelData; label: (modelData * 100) + "%"; on: root.sel && Math.abs(root.sel.scale - modelData) < 0.02
                                                onClicked: root.setProp(root.sel.name, "scale", String(modelData)) } } }
                                }
                                Column {
                                    spacing: 8
                                    Heading { text: "Rotation" }
                                    Row { spacing: 6
                                        Repeater { model: [0, 90, 180, 270]
                                            delegate: Chip { required property var modelData; label: modelData + "°"
                                                on: root.sel && root.sel.transform % 4 === modelData / 90
                                                onClicked: root.setProp(root.sel.name, "rotate", String(modelData)) } } }
                                }
                            }
                            Column {
                                spacing: 8
                                visible: root.others.length > 0 && root.st.mode === "extend"
                                Heading { text: "Place next to " + (root.others[0] ? root.others[0].name : "") }
                                Row { spacing: 6
                                    Repeater { model: [ { l: "Left", v: "left" }, { l: "Right", v: "right" }, { l: "Above", v: "above" }, { l: "Below", v: "below" } ]
                                        delegate: Chip { required property var modelData; label: modelData.l
                                            onClicked: root.setProp(root.sel.name, "pos", modelData.v, root.others[0].name) } } }
                            }
                            Chip { label: root.sel && root.sel.enabled ? "Turn this screen off" : "Turn on"; danger: root.sel && root.sel.enabled; dim: root.enabledCount <= 1 && root.sel && root.sel.enabled
                                   onClicked: root.setProp(root.sel.name, root.sel.enabled ? "off" : "on") }
                        }
                    }

                    // ---------------- sound ----------------
                    Column {
                        width: parent.width; spacing: 8
                        Heading { text: "Sound output" }
                        Surface {
                            width: parent.width; height: sndCol.implicitHeight
                            clip: true
                            Column {
                                id: sndCol
                                width: parent.width
                                Repeater {
                                    model: root.st.sinks || []
                                    delegate: Item {
                                        id: sk
                                        required property var modelData
                                        required property int index
                                        width: sndCol.width; height: 42
                                        Rectangle { anchors.fill: parent; color: Theme.alpha(Theme.text, skMa.containsMouse ? 0.05 : 0); Behavior on color { ColorAnimation { duration: 100 } } }
                                        Rectangle { visible: sk.index > 0; width: parent.width - 28; x: 14; height: 1; color: Theme.alpha(Theme.text, 0.07) }
                                        Rectangle { x: 16; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8
                                            color: "transparent"; border.width: 1.5; border.color: sk.modelData.default ? Theme.accent : Theme.alpha(Theme.text, 0.30)
                                            Rectangle { anchors.centerIn: parent; width: sk.modelData.default ? 8 : 0; height: width; radius: width / 2; color: Theme.accent
                                                        Behavior on width { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } } } }
                                        Text { x: 46; width: parent.width - 130; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                                               text: sk.modelData.desc.replace(/^.*?High Definition Audio \(HD Audio\)\s*/, "")
                                               color: sk.modelData.default ? Theme.text : Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 13 }
                                        Text { anchors.right: parent.right; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
                                               visible: sk.modelData.hdmi; text: "HDMI / DP"; color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 11 }
                                        MouseArea { id: skMa; anchors.fill: parent; hoverEnabled: true; onClicked: root.run([root.bin + "rice-display", "audio", sk.modelData.name]) }
                                    }
                                }
                            }
                        }
                    }

                    // ---------------- share & record ----------------
                    Column {
                        width: parent.width; spacing: 8
                        Heading { text: "Sharing and recording" }
                        Surface {
                            width: parent.width; height: shareCol.implicitHeight + 36
                            Column {
                                id: shareCol
                                x: 18; y: 18; width: parent.width - 36; spacing: 14

                                Row {
                                    spacing: 10
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4
                                        color: root.sh.casting && root.sh.casting.length ? Theme.danger : Theme.textFaint
                                        SequentialAnimation on opacity { running: root.sh.casting && root.sh.casting.length > 0; loops: Animation.Infinite
                                            NumberAnimation { to: 0.3; duration: 700 } NumberAnimation { to: 1; duration: 700 } } }
                                    Text { anchors.verticalCenter: parent.verticalCenter
                                           text: root.sh.casting && root.sh.casting.length ? "Sharing your screen (" + root.sh.casting.length + " stream" + (root.sh.casting.length > 1 ? "s" : "") + ")" : "Not sharing your screen"
                                           color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13 }
                                    Chip { visible: root.sh.casting && root.sh.casting.length > 0; danger: true; on: true; label: "Stop sharing"
                                           onClicked: { for (const c of root.sh.casting) root.run([root.bin + "rice-share", "stop-cast", String(c.id)]) } }
                                }
                                Text {
                                    width: parent.width; wrapMode: Text.WordWrap
                                    text: "To share in Meet, Zoom, Discord, Teams or OBS, choose Share screen in the app, then pick the display in Hyprland's picker."
                                    color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 12
                                }
                                Chip { label: root.sh.ask ? "Always ask which screen" : "Remember my choice"; on: root.sh.ask
                                       onClicked: root.run([root.bin + "rice-share", "ask", root.sh.ask ? "off" : "on"]) }

                                Hairline { width: parent.width }

                                Column {
                                    width: parent.width; spacing: 8
                                    Heading { text: "Record" }
                                    Flow {
                                        width: parent.width; spacing: 6
                                        Repeater {
                                            model: root.mons.filter(m => m.enabled)
                                            delegate: Chip { required property var modelData; label: modelData.name
                                                dim: root.sh.recording && root.sh.recording.active
                                                onClicked: root.run([root.bin + "rice-share", "record", "start", modelData.name]) }
                                        }
                                        Chip { label: "Region"; dim: root.sh.recording && root.sh.recording.active
                                               onClicked: { root.close(); root.run([root.bin + "rice-share", "record", "start", "region"]) } }
                                        Chip { label: "Open recordings"
                                               onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p ~/Videos/Recordings; xdg-open ~/Videos/Recordings"]) }
                                    }
                                }
                                Row {
                                    visible: root.sh.recording && root.sh.recording.active
                                    spacing: 10
                                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 4; color: Theme.danger
                                        SequentialAnimation on opacity { running: root.sh.recording && root.sh.recording.active; loops: Animation.Infinite
                                            NumberAnimation { to: 0.25; duration: 600 } NumberAnimation { to: 1; duration: 600 } } }
                                    Text { anchors.verticalCenter: parent.verticalCenter; text: "Recording  " + root.fmtTime(root.recSecs); color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                                    Chip { danger: true; on: true; label: "Stop and save"; onClicked: root.run([root.bin + "rice-share", "record", "stop"]) }
                                }
                            }
                        }
                    }

                    // ---------------- preferences ----------------
                    Column {
                        width: parent.width; spacing: 8
                        Heading { text: "Preferences" }
                        Surface {
                            width: parent.width; height: prefCol.implicitHeight
                            Column {
                                id: prefCol
                                width: parent.width
                                Toggle { label: "Open this menu when a screen is plugged in"; checked: pref.autoOpen; onFlipped: pref.autoOpen = !pref.autoOpen }
                                Hairline { x: 14; width: parent.width - 28 }
                                Toggle { label: "Switch sound to HDMI automatically"; checked: pref.autoAudio; onFlipped: pref.autoAudio = !pref.autoAudio }
                            }
                        }
                    }
                }
            }
        }
    }
}
