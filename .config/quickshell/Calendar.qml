// Calendar.qml — click the clock (or SUPER+A) : month view, reminders, clock format.
// Keys: ←/→ day · ↑/↓ week · PgUp/PgDn month · T today · N new reminder · Esc close
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    property alias ipc: ipcH

    property bool showing: false
    // The surface stays mapped all the time (it's only card-sized, fully transparent and
    // click-through while hidden). Unmapping on close made Quickshell destroy the window and
    // rebuild it, with a fresh GL context, render thread and glyph upload, on every open,
    // and that rebuild was the stutter at the start of the pop-in.
    visible: true
    property real prog: showing ? 1 : 0
    // snappy: 200 ms in, 120 ms out
    Behavior on prog { NumberAnimation { duration: root.showing ? 200 : 120; easing.type: root.showing ? Easing.OutCubic : Easing.InQuad } }
    property bool addOpen: false
    readonly property int selIdx: { for (let i = 0; i < 42; i++) if (cells[i].s === sel) return i; return -1 }
    readonly property real tk: Touch.k

    // ---- state ----
    property string sel: Reminders.ymd(new Date())
    property int viewY: new Date().getFullYear()
    property int viewM: new Date().getMonth()
    property int slideDir: 0
    property bool fmtOpen: false

    // new-reminder form
    property bool allDay: true
    property int  nHour: 9
    property int  nMin: 0
    property string nRepeat: "none"
    property int  nLead: 0

    readonly property string todayStr: Reminders.ymd(clk.date)
    readonly property int firstDow: Prefs.weekStartMon ? 1 : 0

    // The surface is only as big as the card (+ room for the slide-in). A full-screen layer
    // made Hyprland blur/composite the whole 1920x1080 screen on every animation frame,
    // which is what made the pop-in stutter. Outside clicks close it via a focus grab.
    readonly property int pad: 14
    readonly property real gap: barCfg.thickness + barCfg.margin + 8 + (Touch.mode ? 14 : 0)
    anchors {
        top: barCfg.position === "top"
        bottom: barCfg.position === "bottom"
        left: barCfg.position === "left"
        right: barCfg.position === "right"
    }
    margins {
        top: Math.max(0, root.gap - root.pad); bottom: Math.max(0, root.gap - root.pad)
        left: Math.max(0, root.gap - root.pad); right: Math.max(0, root.gap - root.pad)
    }
    implicitWidth: card.width + 2 * pad
    // grow at once; while the card animates smaller, keep room until it has shrunk
    implicitHeight: Math.ceil(Math.max(card.height, card.targetH)) + 2 * pad
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "calendar"
    WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    mask: Region { item: root.showing ? card : null }

    // click anywhere outside the card -> close
    property double grabClosedAt: 0
    // armed a couple of frames after opening: grabbing in the same instant the (already
    // mapped) surface takes keyboard focus makes Hyprland clear the grab right away
    property bool grabArmed: false
    onShowingChanged: { grabArmed = false; if (showing) grabTimer.restart() }
    Timer { id: grabTimer; interval: 40; onTriggered: root.grabArmed = root.showing }
    HyprlandFocusGrab {
        windows: [root]
        active: root.showing && root.grabArmed
        onCleared: { if (root.showing) { root.grabClosedAt = Date.now(); root.close() } }
    }

    SystemClock { id: clk; precision: Prefs.seconds && root.showing ? SystemClock.Seconds : SystemClock.Minutes }

    // bar placement (so the card opens next to the clock wherever the bar lives)
    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/state/bar-state.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        adapter: JsonAdapter { id: barCfg
            property string position: "top"
            property int thickness: 20
            property int margin: 4
        }
    }

    function open() {
        const n = new Date()
        sel = Reminders.ymd(n); viewY = n.getFullYear(); viewM = n.getMonth()
        fmtOpen = false; addOpen = false; resetForm()
        showing = true
        Qt.callLater(function () { menuRoot.forceActiveFocus() })
    }
    function close() { showing = false }
    // a click on the bar clock while open first clears the grab (closing it); don't reopen on that same click
    function toggle() { showing ? close() : (Date.now() - grabClosedAt < 350 ? null : open()) }


    IpcHandler {
        id: ipcH
        enabled: false   // the always-loaded stub in shell.qml forwards here (lazy loading)
        target: "calendar"
        function toggle(): void { root.toggle() }
        function show(): void { root.open() }
        function hide(): void { root.close() }
    }

    function resetForm() {
        allDay = true; nRepeat = "none"; nLead = 0
        const n = new Date(); nHour = Math.min(23, n.getHours() + 1); nMin = 0
    }
    function selectDay(y, m, d) {
        const s = Reminders.ymd(new Date(y, m, d))
        if (y !== viewY || m !== viewM) goMonth(new Date(y, m, 1))
        sel = s
    }
    function goMonth(dt) {
        const old = viewY * 12 + viewM, nw = dt.getFullYear() * 12 + dt.getMonth()
        slideDir = nw > old ? 1 : nw < old ? -1 : 0
        viewY = dt.getFullYear(); viewM = dt.getMonth()
        gridAnim.restart()
    }
    function shiftSel(days) {
        const p = Reminders.parse(sel), n = new Date(p.getFullYear(), p.getMonth(), p.getDate() + days)
        selectDay(n.getFullYear(), n.getMonth(), n.getDate())
    }
    function gotoToday() { const n = new Date(); selectDay(n.getFullYear(), n.getMonth(), n.getDate()) }
    function submit() {
        const hm = allDay ? "" : Reminders.pad(nHour) + ":" + Reminders.pad(nMin)
        if (Reminders.add(titleInput.text, sel, hm, nRepeat, nLead, "")) {
            titleInput.text = ""
        }
    }
    function isoWeek(d) {
        const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()))
        const dn = t.getUTCDay() || 7
        t.setUTCDate(t.getUTCDate() + 4 - dn)
        const y0 = new Date(Date.UTC(t.getUTCFullYear(), 0, 1))
        return Math.ceil(((t - y0) / 86400000 + 1) / 7)
    }
    readonly property var cells: {
        Reminders.rev
        const first = (new Date(viewY, viewM, 1).getDay() - firstDow + 7) % 7
        const out = []
        for (let i = 0; i < 42; i++) {
            const d = new Date(viewY, viewM, i - first + 1)
            const s = Reminders.ymd(d), sm = Reminders.summary(s)
            out.push({ y: d.getFullYear(), m: d.getMonth(), d: d.getDate(), s: s, inMonth: d.getMonth() === viewM,
                       weekend: d.getDay() === 0 || d.getDay() === 6, n: sm.n, open: sm.open,
                       wk: i % 7 === 0 ? isoWeek(new Date(d.getFullYear(), d.getMonth(), d.getDate() + 3)) : -1 })
        }
        return out
    }
    readonly property var dayItems: { Reminders.rev; return Reminders.forDay(sel) }
    readonly property var upcoming: { Reminders.rev; return Reminders.upcoming(4) }

    function relLabel(s) {
        const k = Reminders.dayDiff(todayStr, s)
        return k === 0 ? "Today" : k === 1 ? "Tomorrow" : k === -1 ? "Yesterday"
             : k > 1 ? "In " + k + " days" : Math.abs(k) + " days ago"
    }

        // ---------- small pieces ----------
        component IconBtn: Item {                     // icon button with a finger-sized hit area
            id: ib
            property string icon: ""
            property bool lit: false
            signal clicked()
            implicitWidth: Math.round(36 * Touch.k); implicitHeight: implicitWidth
            Text { anchors.centerIn: parent; text: ib.icon; font.family: Theme.iconFont; font.pixelSize: 15
                   color: ib.lit || ima.pressed ? Theme.accent : Theme.textDim
                   scale: ima.pressed ? 0.86 : 1
                   Behavior on scale { NumberAnimation { duration: 90 } } }
            MouseArea { id: ima; anchors.fill: parent; onClicked: ib.clicked() }
        }
        component TextBtn: Item {                     // quiet text button, no box
            id: tg
            property string label: ""
            property bool lit: false
            signal clicked()
            implicitWidth: tl.implicitWidth + 16; implicitHeight: Math.round(30 * Touch.k)
            Text { id: tl; anchors.centerIn: parent; text: tg.label; font.family: Theme.fontFamily; font.pixelSize: 11
                   color: tg.lit ? Theme.accent : tma.pressed ? Theme.text : Theme.textDim }
            Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 3; anchors.horizontalCenter: parent.horizontalCenter
                        height: 1; width: tg.lit ? tl.implicitWidth : 0; color: Theme.accent
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } } }
            MouseArea { id: tma; anchors.fill: parent; onClicked: tg.clicked() }
        }


    // ================= UI =================
    readonly property int cw: Math.round(48 * tk)      // cell width
    readonly property int ch: Math.round(42 * tk)      // cell height

    Item {
        id: menuRoot
        anchors.fill: parent
        focus: true

        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_Escape) { if (root.addOpen) { root.addOpen = false; titleInput.text = "" } else root.close() }
            else if (e.key === Qt.Key_Left)  root.shiftSel(-1)
            else if (e.key === Qt.Key_Right) root.shiftSel(1)
            else if (e.key === Qt.Key_Up)    root.shiftSel(-7)
            else if (e.key === Qt.Key_Down)  root.shiftSel(7)
            else if (e.key === Qt.Key_PageUp)   root.goMonth(new Date(root.viewY, root.viewM - 1, 1))
            else if (e.key === Qt.Key_PageDown) root.goMonth(new Date(root.viewY, root.viewM + 1, 1))
            else if (e.key === Qt.Key_T || e.key === Qt.Key_Home) root.gotoToday()
            else if (e.key === Qt.Key_N || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.addOpen = true; titleInput.forceActiveFocus() }
            else return
            e.accepted = true
        }

        // ---------- the card ----------
        Rectangle {
            id: card
            readonly property real targetH: col.implicitHeight + 36
            width: 40 + 7 * root.cw
            height: targetH
            // only animate resizes while fully open, so reopening never plays a leftover resize
            Behavior on height { enabled: root.prog > 0.999; NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
            radius: 14
            color: Theme.alpha(Theme.bgPanel, 0.88)
            border.width: 1
            border.color: Theme.alpha(Theme.text, 0.10)

            x: root.pad
            y: barCfg.position === "bottom" ? root.height - height - root.pad : root.pad

            visible: root.prog > 0.003
            opacity: Math.min(1, root.prog * 2.5)
            scale: 0.965 + 0.035 * root.prog
            transformOrigin: barCfg.position === "bottom" ? Item.Bottom : Item.Top
            transform: Translate { y: (1 - root.prog) * (barCfg.position === "bottom" ? 10 : -10) }
            layer.enabled: root.prog > 0.003 && root.prog < 0.999      // one cheap composite only while animating
            layer.smooth: true
            MouseArea { anchors.fill: parent }     // swallow taps so they don't close the card

            Column {
                id: col
                x: 20; y: 18; width: parent.width - 40
                spacing: 0

                // ---- header: date as typography, time on the right ----
                Item {
                    width: parent.width; height: Math.round(62 * root.tk)
                    Column {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: Qt.formatDate(Reminders.parse(root.sel), "dddd").toUpperCase()
                            color: root.sel === root.todayStr ? Theme.accent : Theme.textDim
                            font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 3
                        }
                        Text {
                            text: Qt.formatDate(Reminders.parse(root.sel), "d MMMM")
                            color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 26; font.weight: Font.DemiBold
                        }
                    }
                    Column {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                            anchors.right: parent.right
                            text: Prefs.timeText(clk.date)
                            color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 17
                            MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: Prefs.clock12 = !Prefs.clock12 }
                        }
                        Text {
                            anchors.right: parent.right
                            text: root.relLabel(root.sel)
                            color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                    }
                }

                // ---- month bar ----
                Item {
                    width: parent.width; height: Math.round(38 * root.tk)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDate(new Date(root.viewY, root.viewM, 1), "MMMM yyyy")
                        color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 12
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        TextBtn { label: "today"; visible: root.sel !== root.todayStr || root.viewM !== new Date().getMonth(); onClicked: root.gotoToday() }
                        IconBtn { icon: "󰅁"; onClicked: root.goMonth(new Date(root.viewY, root.viewM - 1, 1)) }
                        IconBtn { icon: "󰅂"; onClicked: root.goMonth(new Date(root.viewY, root.viewM + 1, 1)) }
                        IconBtn { icon: "󰒓"; lit: root.fmtOpen; onClicked: root.fmtOpen = !root.fmtOpen }
                    }
                }

                // ---- clock options (collapsed) ----
                Item {
                    width: parent.width; height: root.fmtOpen ? Math.round(34 * root.tk) : 0
                    clip: true; opacity: root.fmtOpen ? 1 : 0
                    Behavior on height { NumberAnimation { duration: 280; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        TextBtn { label: "24h"; lit: !Prefs.clock12; onClicked: Prefs.clock12 = false }
                        TextBtn { label: "12h"; lit: Prefs.clock12; onClicked: Prefs.clock12 = true }
                        TextBtn { label: "am/pm"; lit: Prefs.ampm; onClicked: Prefs.ampm = !Prefs.ampm }
                        TextBtn { label: "seconds"; lit: Prefs.seconds; onClicked: Prefs.seconds = !Prefs.seconds }
                        TextBtn { label: "date in bar"; lit: Prefs.dateInBar; onClicked: Prefs.dateInBar = !Prefs.dateInBar }
                        TextBtn { label: Prefs.weekStartMon ? "mon first" : "sun first"; onClicked: Prefs.weekStartMon = !Prefs.weekStartMon }
                    }
                }

                // ---- weekday labels ----
                Row {
                    height: 22
                    Repeater {
                        model: 7
                        delegate: Text {
                            required property int index
                            width: root.cw; height: 22
                            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                            text: Qt.locale().dayName((index + root.firstDow) % 7, Locale.NarrowFormat)
                            color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 10
                        }
                    }
                }

                // ---- month grid ----
                Item {
                    id: gridHost
                    width: parent.width; height: 6 * root.ch
                    clip: true

                    Item {
                        id: gridWrap
                        width: parent.width; height: parent.height
                        ParallelAnimation {
                            id: gridAnim
                            NumberAnimation { target: gridWrap; property: "x"; from: root.slideDir * 30; to: 0; duration: 380; easing.type: Easing.OutQuint }
                            NumberAnimation { target: gridWrap; property: "opacity"; from: 0.0; to: 1.0; duration: 240; easing.type: Easing.OutQuad }
                        }
                        WheelHandler { onWheel: e => root.goMonth(new Date(root.viewY, root.viewM + (e.angleDelta.y > 0 ? -1 : 1), 1)) }

                        // selection: ONE ring that glides between days
                        Rectangle {
                            id: ring
                            readonly property int d: Math.min(root.cw, root.ch) - 6
                            width: d; height: d; radius: d / 2
                            color: "transparent"; border.width: 1.5; border.color: Theme.accent
                            readonly property int i: root.selIdx
                            x: (i < 0 ? 0 : (i % 7) * root.cw + (root.cw - d) / 2)
                            y: (i < 0 ? 0 : Math.floor(i / 7) * root.ch + (root.ch - d) / 2)
                            opacity: i < 0 ? 0 : 1
                            Behavior on x { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutQuint } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        Repeater {
                            model: 42
                            delegate: Item {
                                id: cell
                                required property int index
                                readonly property var c: root.cells[index]
                                readonly property bool isSel: c.s === root.sel
                                readonly property bool isToday: c.s === root.todayStr
                                x: (index % 7) * root.cw; y: Math.floor(index / 7) * root.ch
                                width: root.cw; height: root.ch

                                Rectangle {                       // today = solid disc
                                    anchors.centerIn: parent
                                    width: ring.d - 6; height: width; radius: width / 2
                                    color: Theme.accent
                                    opacity: cell.isToday ? 1 : 0
                                    scale: cMa.pressed ? 0.9 : 1
                                    Behavior on scale { NumberAnimation { duration: 100 } }
                                }
                                Rectangle {                       // press feedback
                                    anchors.centerIn: parent
                                    width: ring.d; height: width; radius: width / 2
                                    color: Theme.alpha(Theme.text, 0.09)
                                    opacity: cMa.pressed ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                }
                                Text {
                                    anchors.centerIn: parent
                                    anchors.verticalCenterOffset: cell.c.n > 0 ? -2 : 0
                                    text: cell.c.d
                                    color: cell.isToday ? Theme.bgPanel : cell.c.inMonth ? (cell.c.weekend ? Theme.textDim : Theme.text) : Theme.textFaint
                                    opacity: cell.c.inMonth || cell.isToday ? 1 : 0.5
                                    font.family: Theme.fontFamily; font.pixelSize: 13
                                    font.weight: cell.isToday || cell.isSel ? Font.Bold : Font.Normal
                                }
                                Rectangle {                       // reminder tick
                                    visible: cell.c.n > 0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: parent.height / 2 + 9
                                    width: cell.c.n > 1 ? 8 : 3; height: 3; radius: 1.5
                                    color: cell.isToday ? Theme.bgPanel : (cell.c.open > 0 ? Theme.accent : Theme.textFaint)
                                }
                                MouseArea {
                                    id: cMa; anchors.fill: parent
                                    onClicked: root.selectDay(cell.c.y, cell.c.m, cell.c.d)
                                    onDoubleClicked: { root.addOpen = true; titleInput.forceActiveFocus() }
                                }
                            }
                        }
                    }
                    DragHandler {                                  // swipe the month with a finger
                        target: null; yAxis.enabled: false
                        onActiveChanged: if (!active) {
                            if (translation.x < -50) root.goMonth(new Date(root.viewY, root.viewM + 1, 1))
                            else if (translation.x > 50) root.goMonth(new Date(root.viewY, root.viewM - 1, 1))
                        }
                    }
                }

                Item { width: 1; height: 8 }
                Rectangle { width: parent.width; height: 1; color: Theme.alpha(Theme.text, 0.08) }
                Item { width: 1; height: 6 }

                // ---- agenda: plain rows, hairlines, no cards ----
                Item {
                    id: agenda
                    width: parent.width
                    height: root.dayItems.length === 0 ? Math.round(34 * root.tk) : Math.min(root.dayItems.length, 4) * Math.round(44 * root.tk)
                    Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                    clip: true
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: root.dayItems.length === 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        text: "Nothing planned"
                        color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 12
                    }
                    ListView {
                        id: agendaList
                        anchors.fill: parent
                        model: root.dayItems
                        boundsBehavior: Flickable.StopAtBounds
                        add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240 } NumberAnimation { property: "x"; from: 14; to: 0; duration: 320; easing.type: Easing.OutQuint } }
                        remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 140 } }
                        displaced: Transition { NumberAnimation { properties: "y"; duration: 280; easing.type: Easing.OutQuint } }
                        delegate: Item {
                            id: row
                            required property var modelData
                            width: agendaList.width; height: Math.round(44 * root.tk)
                            readonly property bool overdue: Reminders.isOverdue(modelData)
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.alpha(Theme.text, 0.06) }

                            Item {
                                id: tick
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.round(36 * root.tk); height: width
                                Rectangle {
                                    anchors.centerIn: parent; width: 18; height: 18; radius: 9
                                    color: row.modelData.done ? Theme.accent : "transparent"
                                    border.width: 1.5; border.color: row.overdue ? Theme.danger : row.modelData.done ? Theme.accent : Theme.alpha(Theme.text, 0.35)
                                    Behavior on color { ColorAnimation { duration: 160 } }
                                    Text { anchors.centerIn: parent; text: ""; color: Theme.bgPanel; font.family: Theme.iconFont; font.pixelSize: 9
                                           opacity: row.modelData.done ? 1 : 0; scale: row.modelData.done ? 1 : 0.4
                                           Behavior on opacity { NumberAnimation { duration: 140 } }
                                           Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } } }
                                }
                                MouseArea { anchors.fill: parent; onClicked: Reminders.toggleDone(row.modelData.id, row.modelData.day) }
                            }
                            Column {
                                anchors.left: tick.right; anchors.right: del.left; anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: row.modelData.title
                                    color: row.modelData.done ? Theme.textFaint : Theme.text
                                    font.family: Theme.fontFamily; font.pixelSize: 13; font.strikeout: row.modelData.done
                                }
                                Text {
                                    text: (row.modelData.time !== "" ? Prefs.showHM(row.modelData.time) : "all day")
                                          + (row.modelData.repeat !== "none" ? "  ·  " + row.modelData.repeat : "")
                                          + (row.modelData.lead ? "  ·  " + (row.modelData.lead >= 1440 ? "1d" : row.modelData.lead >= 60 ? (row.modelData.lead / 60) + "h" : row.modelData.lead + "m") + " early" : "")
                                          + (row.overdue ? "  ·  overdue" : "")
                                    color: row.overdue ? Theme.danger : Theme.textFaint
                                    font.family: Theme.fontFamily; font.pixelSize: 10
                                }
                            }
                            IconBtn {
                                id: del
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                icon: ""; onClicked: Reminders.remove(row.modelData.id)
                                opacity: 0.55
                            }
                        }
                    }
                }

                // ---- add reminder: one quiet line that opens up ----
                Item {
                    width: parent.width; height: Math.round(42 * root.tk)
                    Text {
                        id: plus
                        anchors.verticalCenter: parent.verticalCenter; x: 9
                        text: "+"; color: root.addOpen ? Theme.accent : Theme.textDim
                        font.family: Theme.fontFamily; font.pixelSize: 18
                        rotation: root.addOpen ? 90 : 0
                        Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter; x: Math.round(36 * root.tk)
                        visible: titleInput.text === ""
                        text: "Add a reminder"
                        color: Theme.textFaint; font.family: Theme.fontFamily; font.pixelSize: 13
                    }
                    TextInput {
                        id: titleInput
                        x: Math.round(36 * root.tk); width: parent.width - x - 8; height: parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13
                        selectionColor: Theme.accent; clip: true
                        onAccepted: root.submit()
                        onActiveFocusChanged: if (activeFocus) {
                            root.addOpen = true
                            if (Touch.mode) Quickshell.execDetached({ command: ["qs", "ipc", "call", "keyboard", "open"] })
                        }
                        Keys.onEscapePressed: { text = ""; root.addOpen = false; menuRoot.forceActiveFocus() }
                    }
                    MouseArea {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; width: Math.round(36 * root.tk)
                        onClicked: { root.addOpen = !root.addOpen; if (root.addOpen) titleInput.forceActiveFocus(); else menuRoot.forceActiveFocus() }
                    }
                    MouseArea {
                        anchors.fill: parent; anchors.leftMargin: Math.round(36 * root.tk); enabled: !titleInput.activeFocus
                        onClicked: { root.addOpen = true; titleInput.forceActiveFocus() }
                    }
                    Rectangle {                                    // submit
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        width: 52; height: 26; radius: 13
                        opacity: titleInput.text.trim() !== "" ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        color: Theme.accent
                        Text { anchors.centerIn: parent; text: "add"; color: Theme.bgPanel; font.family: Theme.fontFamily; font.pixelSize: 11; font.bold: true }
                        MouseArea { anchors.fill: parent; enabled: parent.opacity > 0.5; onClicked: root.submit() }
                    }
                }

                // ---- options appear only while adding: time · repeat · early-warning ----
                Item {
                    id: opts
                    width: parent.width
                    height: root.addOpen ? Math.round(40 * root.tk) : 0
                    opacity: root.addOpen ? 1 : 0
                    clip: true
                    Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    readonly property var reps: ["none", "daily", "weekly", "monthly", "yearly"]
                    readonly property var leads: [0, 5, 15, 60, 1440]
                    readonly property var leadNames: ["on time", "5m early", "15m early", "1h early", "1d early"]
                    function nudge(m) { const t = (root.nHour * 60 + root.nMin + m + 1440) % 1440; root.nHour = Math.floor(t / 60); root.nMin = t % 60 }

                    Row {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        TextBtn { label: root.allDay ? "all day" : "timed"; lit: !root.allDay; onClicked: root.allDay = !root.allDay }
                        Row {
                            visible: !root.allDay; spacing: 0
                            IconBtn { icon: ""; onClicked: opts.nudge(-15) }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Prefs.showHM(Reminders.pad(root.nHour) + ":" + Reminders.pad(root.nMin)); width: 66; horizontalAlignment: Text.AlignHCenter
                                color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 13
                                WheelHandler { onWheel: e => opts.nudge(e.angleDelta.y > 0 ? 15 : -15) }
                            }
                            IconBtn { icon: ""; onClicked: opts.nudge(15) }
                        }
                        TextBtn { label: opts.reps[Math.max(0, opts.reps.indexOf(root.nRepeat))] === "none" ? "once" : root.nRepeat; lit: root.nRepeat !== "none"
                              onClicked: root.nRepeat = opts.reps[(opts.reps.indexOf(root.nRepeat) + 1) % opts.reps.length] }
                        TextBtn { label: opts.leadNames[Math.max(0, opts.leads.indexOf(root.nLead))]; lit: root.nLead !== 0
                              onClicked: root.nLead = opts.leads[(opts.leads.indexOf(root.nLead) + 1) % opts.leads.length] }
                    }
                }
            }
        }
    }
}
