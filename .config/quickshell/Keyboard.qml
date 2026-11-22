pragma ComponentBehavior: Bound
// Touch keyboard.  qs ipc call osk toggle|open|hide     (also: edge-swipe up from the bottom)
// Never takes keyboard focus, so the app you are typing into keeps it. Keys are sent with ydotool.
// Shift: tap = next key, double-tap = lock.  Ctrl/Alt/Super: tap = next key.  Hold ⌫ and arrows to repeat.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root

    property bool showing: false
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: root.showing ? 340 : 200; easing.type: root.showing ? Easing.OutQuint : Easing.InQuad } }

    // modifier state: shift 0 off / 1 next key / 2 locked
    property int shift: 0
    property bool ctrl: false
    property bool alt: false
    property bool sup: false
    property bool fnLayer: false

    readonly property real kh: Math.round(54 * Touch.k)            // key height
    readonly property real gap: 6
    readonly property real boardW: Math.min(width - 24, 1500)

    // [label, shiftLabel, evdev code, weight, kind]   kind: "" normal | mod-* | act-*
    readonly property var rows: [
        [["`","~",41,1],["1","!",2,1],["2","@",3,1],["3","#",4,1],["4","$",5,1],["5","%",6,1],["6","^",7,1],["7","&",8,1],["8","*",9,1],["9","(",10,1],["0",")",11,1],["-","_",12,1],["=","+",13,1],["⌫","⌫",14,1.7,"rep"]],
        [["Tab","Tab",15,1.5,"fn"],["q","Q",16,1],["w","W",17,1],["e","E",18,1],["r","R",19,1],["t","T",20,1],["y","Y",21,1],["u","U",22,1],["i","I",23,1],["o","O",24,1],["p","P",25,1],["[","{",26,1],["]","}",27,1],["\\","|",43,1.2]],
        [["Esc","Esc",1,1.8,"fn"],["a","A",30,1],["s","S",31,1],["d","D",32,1],["f","F",33,1],["g","G",34,1],["h","H",35,1],["j","J",36,1],["k","K",37,1],["l","L",38,1],[";",":",39,1],["'","\"",40,1],["Enter","Enter",28,2.1,"fn"]],
        [["Shift","Shift",42,2.3,"shift"],["z","Z",44,1],["x","X",45,1],["c","C",46,1],["v","V",47,1],["b","B",48,1],["n","N",49,1],["m","M",50,1],[",","<",51,1],[".",">",52,1],["/","?",53,1],["↑","↑",103,1.2,"rep"],["⌄","⌄",0,1.2,"hide"]],
        [["Ctrl","Ctrl",29,1.4,"ctrl"],["Super","Super",125,1.4,"sup"],["Alt","Alt",56,1.4,"alt"],["ع / EN","",0,1.5,"lang"],["Hints","",0,1.3,"hints"],["Space","Space",57,3.6,"fn"],["Fn","Fn",0,1.2,"fnkey"],["←","←",105,1.2,"rep"],["↓","↓",108,1.2,"rep"],["→","→",106,1.2,"rep"]]
    ]

    // Arabic mode: switches the system xkb layout (us,latam,ara -> index 2) so the same evdev codes type Arabic.
    // Keys are relabelled with the standard Arabic 101 layout; "hints" shows the physical (Latin) key in the corner.
    property bool arabic: false
    property bool hints: true
    function setArabic(on) {
        arabic = on
        Quickshell.execDetached({ command: ["hyprctl", "switchxkblayout", "all", on ? "2" : "0"] })
    }
    // evdev code -> [arabic, arabic with shift]   (◌ = combining mark)
    readonly property var ar: ({
        41:["ذ","◌ّ"], 16:["ض","◌َ"], 17:["ص","◌ً"], 18:["ث","◌ُ"], 19:["ق","◌ٌ"], 20:["ف","ﻹ"], 21:["غ","إ"],
        22:["ع","`"], 23:["ه","÷"], 24:["خ","×"], 25:["ح","؛"], 26:["ج","<"], 27:["د",">"],
        30:["ش","◌ِ"], 31:["س","◌ٍ"], 32:["ي","]"], 33:["ب","["], 34:["ل","ﻷ"], 35:["ا","أ"], 36:["ت","ـ"],
        37:["ن","،"], 38:["م","/"], 39:["ك",":"], 40:["ط","\""],
        44:["ئ","~"], 45:["ء","◌ْ"], 46:["ؤ","}"], 47:["ر","{"], 48:["ﻻ","ﻵ"], 49:["ى","آ"], 50:["ة","'"],
        51:["و",","], 52:["ز","."], 53:["ظ","؟"]
    })

    // RK68-style Fn layer: Fn+1..= -> screen/home/mail/calc/music/rec/prev/stop/next/mute/vol-/vol+, Fn+⌫ -> Del, Fn+arrows -> Home/PgUp/PgDn/End   (evdev code -> [label, code])
    readonly property var fnm: ({
        2:["Screen",227], 3:["Home",172], 4:["Mail",155], 5:["Calc",140], 6:["Music",226], 7:["Rec",167],
        8:["⏮",165], 9:["⏹",166], 10:["⏭",163], 11:["Mute",113], 12:["Vol−",114], 13:["Vol+",115], 14:["Del",111],
        105:["Home",102], 103:["PgUp",104], 108:["PgDn",109], 106:["End",107]
    })

    function show() { showing = true }
    function hide() { showing = false; fnLayer = false; shift = 0; ctrl = false; alt = false; sup = false }
    function toggle() { showing ? hide() : show() }

    function send(code) {
        var down = [], up = []
        if (shift > 0) { down.push("42:1"); up.unshift("42:0") }
        if (ctrl) { down.push("29:1"); up.unshift("29:0") }
        if (alt)  { down.push("56:1"); up.unshift("56:0") }
        if (sup)  { down.push("125:1"); up.unshift("125:0") }
        var cmd = ["ydotool", "key"].concat(down, [code + ":1", code + ":0"], up)
        Quickshell.execDetached({ command: cmd })
        if (shift === 1) shift = 0
        ctrl = false; alt = false; sup = false
    }

    IpcHandler {
        target: "osk"
        // In touch mode squeekboard owns the keyboard (it also auto-shows on text fields);
        // outside touch mode this themed keyboard is used for manual toggling.
        function toggle(): void { if (Touch.mode) root.sq("toggle"); else root.toggle() }
        function open(): void { if (Touch.mode) root.sq("true"); else root.show() }
        function hide(): void { if (Touch.mode) root.sq("false"); else root.hide() }
    }

    function sq(v) {
        sqProc.command = ["sh", "-c",
            "B='busctl --user'; D='sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0'; v=" + v + "; " +
            "if [ \"$v\" = toggle ]; then c=$($B get-property $D Visible | cut -d' ' -f2); [ \"$c\" = true ] && v=false || v=true; fi; " +
            "$B call $D SetVisible b $v"]
        sqProc.running = true
    }
    Process { id: sqProc }

    anchors { bottom: true; left: true; right: true }
    implicitHeight: 5 * kh + 6 * gap + 44
    color: "transparent"
    visible: showing || prog > 0.003
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: showing ? implicitHeight - 10 : 0
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "keyboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: panel }

    component KeyCap: Item {
        id: cap
        required property var spec          // [label, shiftLabel, code, weight, kind]
        required property real unitW
        property bool pressed: tap.pressed
        readonly property string kind: spec.length > 4 ? spec[4] : ""
        readonly property bool isMod: kind === "shift" || kind === "ctrl" || kind === "alt" || kind === "sup"
        readonly property bool lit: (kind === "shift" && root.shift > 0) || (kind === "ctrl" && root.ctrl)
                                    || (kind === "alt" && root.alt) || (kind === "sup" && root.sup)
                                    || (kind === "fnkey" && root.fnLayer) || (kind === "lang" && root.arabic) || (kind === "hints" && root.arabic && root.hints)
        readonly property var fnSpec: root.fnLayer ? root.fnm[spec[2]] : undefined
        readonly property var arSpec: (root.arabic && !fnSpec) ? root.ar[spec[2]] : undefined
        readonly property string shown: fnSpec ? fnSpec[0] : arSpec ? arSpec[root.shift > 0 ? 1 : 0]
                                      : (root.shift > 0 && kind !== "shift" && spec[1] !== "") ? spec[1] : spec[0]
        readonly property bool wide: fnSpec !== undefined || (spec[0].length > 1 && kind !== "rep")
        width: unitW * spec[3]
        height: root.kh

        function fire() {
            if (kind === "shift")      root.shift = root.shift === 0 ? 1 : (root.shift === 1 ? 2 : 0)
            else if (kind === "ctrl")  root.ctrl = !root.ctrl
            else if (kind === "alt")   root.alt = !root.alt
            else if (kind === "sup")   root.sup = !root.sup
            else if (kind === "hide")  root.hide()
            else if (kind === "fnkey") root.fnLayer = !root.fnLayer
            else if (kind === "lang")  root.setArabic(!root.arabic)
            else if (kind === "hints") root.hints = !root.hints
            else root.send(fnSpec ? fnSpec[1] : spec[2])
        }

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: 10
            color: cap.lit ? Theme.alpha(Theme.accent, 0.30)
                 : cap.pressed ? Theme.alpha(Theme.text, 0.26)
                 : (cap.wide || cap.isMod) ? Theme.alpha(Theme.text, 0.07) : Theme.alpha(Theme.text, 0.12)
            border.width: 1
            border.color: cap.lit ? Theme.accent : Theme.alpha(Theme.text, cap.pressed ? 0.35 : 0.10)
            scale: cap.pressed ? 0.94 : 1
            Behavior on color { ColorAnimation { duration: 90 } }
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Text {
                anchors.centerIn: parent
                text: cap.shown
                color: cap.lit ? Theme.accent : Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: cap.wide ? 13 : (cap.arSpec ? 22 : 19)
                font.weight: cap.wide ? Font.Normal : Font.Medium
            }
            Text {                 // physical-key hint: which key on the real keyboard types this Arabic letter
                visible: cap.arSpec !== undefined && root.hints
                text: (root.shift > 0 ? cap.spec[1] : cap.spec[0]).toUpperCase()
                anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 5
                color: Theme.accent
                opacity: 0.85
                font.family: Theme.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
            }
            Rectangle {            // shift-lock dot
                visible: cap.kind === "shift" && root.shift === 2
                width: 5; height: 5; radius: 2.5; color: Theme.accent
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 7
            }
        }

        // fires on finger-down (no tap-delay); every key has its own handler so several fingers work at once
        TapHandler {
            id: tap
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onPressedChanged: if (pressed) {
                cap.fire()
                if (cap.kind === "rep") rep.restart()
            } else { rep.stop(); if (cap.kind !== "fnkey" && root.fnLayer) root.fnLayer = false }
        }
        Timer { id: rep; interval: 380; onTriggered: { cap.fire(); rep.interval = 55; rep.repeat = true } 
                onRunningChanged: if (!running) { interval = 380; repeat = false } }
    }

    Item {
        id: panel
        width: root.boardW + 20
        height: parent.height
        anchors.horizontalCenter: parent.horizontalCenter
        y: (1 - root.prog) * (height + 10)

        Rectangle {
            anchors.fill: parent; anchors.topMargin: 10
            radius: 18
            color: Theme.alpha(Theme.bgPanel, 0.93)
            border.width: 1; border.color: Theme.alpha(Theme.text, 0.10)

            // grab handle: drag it down to dismiss
            Item {
                id: handle
                width: parent.width; height: 30
                Rectangle { anchors.centerIn: parent; width: 44; height: 4; radius: 2; color: Theme.alpha(Theme.text, 0.25) }
                DragHandler {
                    target: null; xAxis.enabled: false
                    onActiveChanged: if (!active && translation.y > 40) root.hide()
                }
            }

            Column {
                x: 10; y: 30
                spacing: root.gap
                Repeater {
                    model: root.rows
                    delegate: Row {
                        id: rowItem
                        required property var modelData
                        spacing: root.gap
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property real total: {
                            var t = 0
                            for (var i = 0; i < modelData.length; i++) t += modelData[i][3]
                            return t
                        }
                        readonly property real unitW: (root.boardW - (modelData.length - 1) * root.gap) / total
                        Repeater {
                            model: rowItem.modelData
                            delegate: KeyCap {
                                required property var modelData
                                spec: modelData
                                unitW: rowItem.unitW
                            }
                        }
                    }
                }
            }
        }
    }
}
