pragma ComponentBehavior: Bound
// Radial quick-actions wheel (SUPER+S).
// Keys: ←/→/Tab move · Enter/Space run · 1-9 jump · Esc close · mouse: aim + click
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: root
    property string iconFont: Theme.iconFont
    property int ringRadius: 134
    property int ringThickness: 50
    property int gapAngle: 4
    property int deadZone: 44

    property bool showing: false
    // Only keep the surface mapped while the menu is open (or closing): an idle full-screen layer still costs the compositor every frame.
    property bool mapped: false
    onShowingChanged: { if (showing) { unmapTimer.stop(); mapped = true } else unmapTimer.restart() }
    Timer { id: unmapTimer; interval: 700; onTriggered: root.mapped = false }
    visible: mapped
    property int selected: -1

    readonly property int outerZone: ringRadius + ringThickness
    readonly property real step: 360 / items.length
    readonly property var items: [
        { icon: "\udb81\udc93", name: "Settings",  cmd: ["qs", "ipc", "call", "settings", "toggle"] },
        { icon: "\udb80\udd00", name: "Capture",   cmd: ["sh", "-c", "sleep 0.25; f=$HOME/Pictures/$(date +%s).png; grim \"$f\"; wl-copy < \"$f\"; qs ipc call screenshot notify \"$f\""] },
        { icon: "\uf125",       name: "Area",      cmd: ["sh", "-c", "sleep 0.15; f=$HOME/Pictures/$(date +%s).png; grim -g \"$(slurp)\" \"$f\"; wl-copy < \"$f\"; qs ipc call screenshot notify \"$f\""] },
        { icon: "\uf073",       name: "Calendar",  cmd: ["qs", "ipc", "call", "calendar", "toggle"] },
        { icon: "\uf108",       name: "Displays",  cmd: ["qs", "ipc", "call", "project", "toggle"] },
        { icon: "\uf03e",       name: "Wallpaper", cmd: ["sh", "-c", "$HOME/.local/bin/wallpaper-toggle"] },
        { icon: "\uf0ea",       name: "Clipboard", cmd: ["sh", "-c", "sleep 0.15; $HOME/.config/hypr/scripts/clipboard.sh"] },
        { icon: "\uf1fb",       name: "Colour",    cmd: ["sh", "-c", "sleep 0.2; c=$(hyprpicker -a -n) && notify-send -t 2500 'Colour copied' \"$c\""] },
        { icon: "\uf0f3",       name: "Notifs",    cmd: ["qs", "ipc", "call", "notifications", "toggle"] },
        { icon: "\uf0ae",       name: "To-do",     cmd: ["qs", "ipc", "call", "todo", "toggle"] },
        { icon: "\uf023",       name: "Lock",      cmd: ["sh", "-c", "$HOME/.local/bin/power-action lock"] },
        { icon: "\uf011",       name: "Power",     cmd: ["qs", "ipc", "call", "powermenu", "toggle"] },
        { icon: "\uf11c",       name: "Keyboard",  cmd: ["qs", "ipc", "call", "keyboard", "toggle"] },
        { icon: "\udb80\udf4c", name: "Touch",     cmd: ["qs", "ipc", "call", "touch", "toggle"] },
        { icon: "\udb81\udf4a", name: "Rotate",    cmd: ["rotate-screen", "next"] },
        { icon: "\udb80\udcdf", name: "Boost",     cmd: ["boost", "toggle"] },
        { icon: "\udb80\udd68", name: "Opacity",   cmd: ["sh", "-c", "$HOME/.config/hypr/scripts/opacity.sh"] }
    ]

                component Ring: Shape {
                    id: ringShape
                    anchors.fill: parent
    required property var s
                    preferredRendererType: Shape.CurveRenderer
                    property color fill: "transparent"
                    property color line: "transparent"
                    property real lw: 1.2
                    ShapePath {
                        fillColor: ringShape.fill
                        strokeColor: ringShape.line
                        strokeWidth: ringShape.lw
                        joinStyle: ShapePath.RoundJoin
                        startX: s.cx + Math.cos(s.a0 * Math.PI / 180) * s.rIn
                        startY: s.cy + Math.sin(s.a0 * Math.PI / 180) * s.rIn
                        PathLine {
                            x: s.cx + Math.cos(s.a0 * Math.PI / 180) * s.rOut
                            y: s.cy + Math.sin(s.a0 * Math.PI / 180) * s.rOut
                        }
                        PathAngleArc {
                            moveToStart: false
                            centerX: s.cx; centerY: s.cy
                            radiusX: s.rOut; radiusY: s.rOut
                            startAngle: s.a0; sweepAngle: s.sweep
                        }
                        PathLine {
                            x: s.cx + Math.cos((s.a0 + s.sweep) * Math.PI / 180) * s.rIn
                            y: s.cy + Math.sin((s.a0 + s.sweep) * Math.PI / 180) * s.rIn
                        }
                        PathAngleArc {
                            moveToStart: false
                            centerX: s.cx; centerY: s.cy
                            radiusX: s.rIn; radiusY: s.rIn
                            startAngle: s.a0 + s.sweep; sweepAngle: -s.sweep
                        }
                    }
                }


    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "wheel"
    WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    mask: Region { item: root.showing ? menuRoot : null }

    function run(i) {
        if (i < 0 || i >= root.items.length) return
        var a = root.items[i]
        root.closeMenu()
        Quickshell.execDetached({ command: a.cmd })
    }

    function openMenu() {
        var mon = Hyprland.focusedMonitor
        if (mon) {
            var scr = Quickshell.screens.find(function (s) { return s.name === mon.name })
            if (scr) root.screen = scr
        }
        root.selected = -1
        root.atPointer = false
        if (mon && !Touch.mode) cursorProc.running = true      // centre the wheel on the pointer: no travel to aim
        root.showing = true
        Qt.callLater(function () { if (root.showing) menuRoot.forceActiveFocus() })
    }

    // wheel centre (window coords); falls back to the middle of the screen
    property bool atPointer: false
    property real px: 0
    property real py: 0
    readonly property real half: outerZone + 20
    readonly property real cxw: atPointer ? Math.max(half + 8, Math.min(menuRoot.width - half - 8, px)) : menuRoot.width / 2
    readonly property real cyw: atPointer ? Math.max(half + 8, Math.min(menuRoot.height - half - 8, py)) : menuRoot.height / 2
    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos", "-j"]
        stdout: StdioCollector { onStreamFinished: {
            try { const c = JSON.parse(text), mon = Hyprland.focusedMonitor
                  if (!mon || wheel.p > 0.35) return                      // too late: don't jump mid-animation
                  root.px = c.x - mon.x; root.py = c.y - mon.y; root.atPointer = true } catch (e) {} } }
    }

    function closeMenu() { root.showing = false }
    function toggleMenu() { root.showing ? root.closeMenu() : root.openMenu() }

    function pointAt(x, y) {
        var dx = x - root.cxw
        var dy = y - root.cyw
        var d = Math.sqrt(dx * dx + dy * dy)
        if (d < root.deadZone) { root.selected = -1; return }
        var n = root.items.length
        var a = Math.atan2(dy, dx) * 180 / Math.PI + 90
        if (a < 0) a += 360
        root.selected = Math.round(a / root.step) % n
    }

    IpcHandler {
        target: "wheel"
        function toggle(): void { root.toggleMenu() }
        function show(): void { root.openMenu() }
        function hide(): void { root.closeMenu() }
        function confirm(): void {
            if (!root.showing) return
            if (root.selected >= 0) root.run(root.selected)
            else root.closeMenu()
        }
    }

    Item {
        id: menuRoot
        anchors.fill: parent
        focus: true

        Keys.onPressed: function (event) {
            if (!root.showing) return
            var n = root.items.length
            if (event.key === Qt.Key_Escape) {
                root.closeMenu()
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                root.selected = (root.selected + 1) % n
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                root.selected = root.selected < 0 ? n - 1 : (root.selected - 1 + n) % n
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                if (root.selected >= 0) root.run(root.selected)
                else root.closeMenu()
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                root.run(event.key - Qt.Key_1)
            }
            event.accepted = true
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: function (mouse) { root.pointAt(mouse.x, mouse.y) }
            onPressed: function (mouse) { root.pointAt(mouse.x, mouse.y) }   // touch: select on finger-down
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function (mouse) {
                if (mouse.button === Qt.RightButton) { root.closeMenu(); return }
                var dx = mouse.x - root.cxw
                var dy = mouse.y - root.cyw
                var d = Math.sqrt(dx * dx + dy * dy)
                if (d >= root.deadZone && root.selected >= 0) root.run(root.selected)   // anywhere along the aimed direction counts
                else root.closeMenu()
            }
            onWheel: function (w) {                                                    // scroll steps round the ring
                var n = root.items.length, dir = w.angleDelta.y > 0 ? -1 : 1
                root.selected = root.selected < 0 ? (dir > 0 ? 0 : n - 1) : (root.selected + dir + n) % n
            }
        }

        // soft dim behind the wheel (alpha stays below the layer-rule blur threshold -> no screen blur)
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.16 * wheel.p
            visible: opacity > 0.003
        }

        Item {
            id: wheel
            width: 2 * (root.ringRadius + root.ringThickness) + 40
            height: width
            x: root.cxw - width / 2
            y: root.cyw - height / 2
            transformOrigin: Item.Center

            // ONE animated value drives the whole entrance; everything below is derived from it
            // (no per-segment Behaviors / timers -> no stutter, one clock for all pieces).
            property real p: 0
            NumberAnimation on p {
                id: pAnim
                running: false
                to: root.showing ? 1 : 0
                duration: root.showing ? 260 : 130
                easing.type: root.showing ? Easing.OutQuint : Easing.InQuad
            }
            Connections {
                target: root
                function onShowingChanged() { pAnim.stop(); pAnim.to = root.showing ? 1 : 0; pAnim.duration = root.showing ? 260 : 130
                                              pAnim.easing.type = root.showing ? Easing.OutQuint : Easing.InQuad; pAnim.start() }
            }
            visible: root.showing || p > 0.002
            // one offscreen layer for the whole wheel: a single cheap alpha instead of 13 group-opacities
            layer.enabled: p < 0.999
            layer.smooth: true
            opacity: Math.min(1, p * 2.2)
            scale: 0.9 + 0.1 * p

            // ---- centre hub ----
            Rectangle {
                id: hubCircle
                width: 2 * (root.deadZone + 16)
                height: width
                radius: width / 2
                anchors.centerIn: parent
                scale: 0.7 + 0.3 * wheel.p
                color: Theme.alpha(Theme.bgPanel, 0.62)
                border.width: 1.5
                border.color: root.selected >= 0 ? Theme.accent : Theme.alpha(Theme.text, 0.35)
                Behavior on border.color { ColorAnimation { duration: 140 } }

                Column {
                    anchors.centerIn: parent
                    spacing: 2
                    Text {
                        id: nameText
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.selected >= 0 ? root.items[root.selected].name : "Quick"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                        color: root.selected >= 0 ? Theme.accent : Theme.text
                        Behavior on color { ColorAnimation { duration: 140 } }
                        onTextChanged: pop.restart()
                        NumberAnimation { id: pop; target: nameText; property: "scale"; from: 0.9; to: 1; duration: 180; easing.type: Easing.OutCubic }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.selected >= 0 && root.selected < 9 ? "or press " + (root.selected + 1) : (root.selected >= 0 ? "click to run" : "aim, then click")
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        color: Theme.textFaint
                    }
                }
            }

            // ---- segments (geometry is static; only transforms/opacity animate) ----
            Repeater {
                model: root.items

                delegate: Item {
                    id: seg
                    required property var modelData
                    required property int index
                    readonly property bool focused: index === root.selected
                    readonly property real midAngle: (index * root.step - 90) * Math.PI / 180
                    readonly property real a0: index * root.step - 90 - root.step / 2 + root.gapAngle / 2
                    readonly property real sweep: root.step - root.gapAngle
                    readonly property real rad: root.ringRadius
                    readonly property real rIn: rad - root.ringThickness / 2
                    readonly property real rOut: rad + root.ringThickness / 2
                    readonly property real cx: wheel.width / 2
                    readonly property real cy: wheel.height / 2

                    // stagger derived from the single clock; none while closing
                    readonly property real lp: Math.max(0, Math.min(1, (wheel.p * (root.showing ? 1.45 : 1) - (root.showing ? index / root.items.length * 0.45 : 0))))
                    // hover/focus amount, one short ease
                    property real fo: focused ? 1 : 0
                    Behavior on fo { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    anchors.fill: parent
                    transformOrigin: Item.Center
                    scale: (0.84 + 0.16 * lp) * (1 + 0.05 * fo)
                    rotation: (1 - lp) * -9

                    Ring { s: seg; fill: Theme.alpha(Theme.bgPanel, 0.58); line: Theme.alpha(Theme.text, 0.32) }
                    Ring {                                  // accent overlay, cross-faded by opacity only
                        s: seg; fill: Theme.alpha(Theme.accent, 0.26); line: Theme.accent; lw: 2
                        opacity: seg.fo
                        visible: opacity > 0.01
                    }

                    Text {
                        x: seg.cx + Math.cos(seg.midAngle) * seg.rad - width / 2
                        y: seg.cy + Math.sin(seg.midAngle) * seg.rad - height / 2
                        text: seg.modelData.icon
                        font.family: root.iconFont
                        font.pixelSize: 21
                        color: Qt.tint(Theme.textDim, Theme.alpha(Theme.accent, seg.fo))
                        scale: 1 + 0.22 * seg.fo
                    }
                }
            }
        }
    }
}
