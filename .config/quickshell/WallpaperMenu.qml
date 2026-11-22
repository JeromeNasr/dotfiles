// WallpaperMenu.qml — wallpaper picker, lives in the main shell so it opens instantly.
// Open: SUPER+W / `qs ipc call wallpaper toggle`.
// Keys: ←/→ (h/l) browse · Shift = ×5 · Home/End · R random · Enter/Space apply · Esc/Q close
// Mouse: wheel/touchpad browse · click a side card to select · click the centre card to apply
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Qt.labs.folderlistmodel

ShellPopup {
    id: main
    readonly property real ui: (screen ? screen.height : 1080) / 1080

    // ---- layout ----
    readonly property real cardW: 480 * ui
    readonly property real cardH: 270 * ui
    readonly property real gap: 30 * ui
    readonly property real step: cardW + gap
    readonly property real radius: 16 * ui

    // ---- paths ----
    readonly property string home: Quickshell.env("HOME")
    readonly property string pickerDir: home + "/.config/quickshell/hyprquickpaper/"
    property string wallpaperPath: home + "/Pictures/Wallpapers/"
    property string cachePath: home + "/.cache/quickshell/wallthumbs/"
    property string currentWallpaper: ""

    // ---- open / close ----
    property bool showing: false
    property bool loaded: false          // content is built on first open and then kept, so reopening is instant
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: main.showing ? 260 : 160; easing.type: main.showing ? Easing.OutQuart : Easing.InCubic } }
    property bool held: false
    onShowingChanged: { if (showing) { unmapTimer.stop(); held = true } else unmapTimer.restart() }
    Timer { id: unmapTimer; interval: 200; onTriggered: main.held = false }
    surfaceOpen: held

    WlrLayershell.namespace: "wallpaper-picker"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    signal opened()

    function open() {
        const mon = Hyprland.focusedMonitor
        if (mon) { const scr = Quickshell.screens.find(s => s.name === mon.name); if (scr) main.screen = scr }
        cfgFile.reload(); stateFile.reload()
        if (!thumbJob.running) thumbJob.running = true      // make any missing thumbnails
        loaded = true
        showing = true
        opened()
    }
    function close() { showing = false }
    function toggle() { showing ? close() : open() }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { main.toggle() }
        function open(): void { main.open() }
        function close(): void { main.close() }
    }

    FileView {
        id: cfgFile
        path: main.pickerDir + "config.json"
        printErrors: false
        onLoaded: { try { const c = JSON.parse(text())
                          if (c.wallpaper_path) main.wallpaperPath = c.wallpaper_path.replace("$HOME", main.home)
                          if (c.cache_path) main.cachePath = c.cache_path.replace("$HOME", main.home) } catch (e) {} }
    }
    FileView {   // which wallpaper is active -> the carousel opens on it
        id: stateFile
        path: (Quickshell.env("XDG_STATE_HOME") || (main.home + "/.local/state")) + "/43pr/state.json"
        printErrors: false
        onLoaded: { try { main.currentWallpaper = JSON.parse(text()).wallpaper || "" } catch (e) {} }
    }

    // Thumbnail generator. When it finishes, cards that were showing a fallback switch to the thumbnail.
    property int thumbRev: 0
    Process {
        id: thumbJob
        command: ["bash", main.pickerDir + "cache.sh", main.pickerDir]
        onExited: main.thumbRev++
    }

    Loader {
        anchors.fill: parent
        active: main.loaded
        sourceComponent: Item {
            id: root

            Connections {
                target: main
                function onOpened() { list.touched = false; list.snapToCurrent(); Qt.callLater(list.resnap); list.forceActiveFocus() }
                function onCurrentWallpaperChanged() { if (!list.touched) list.snapToCurrent() }
            }

            FolderListModel {
                id: folderModel
                folder: "file://" + main.wallpaperPath
                showDirs: false
                caseSensitive: false
                nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
                sortField: FolderListModel.Time      // newest first
                sortReversed: true
            }

            function thumb(fileName) { return "file://" + main.cachePath + fileName + ".jpg" }
            readonly property string selName: list.count > 0 ? String(folderModel.get(list.selectedIndex, "fileName")) : ""

            // ---------- backdrop: the selected wallpaper, blurred, cross-fading as you browse ----------
            Item {
                id: backdrop
                anchors.fill: parent
                opacity: main.prog

                Rectangle { anchors.fill: parent; color: "black" }

                property bool useA: true
                Timer {   // small delay so holding an arrow key doesn't churn the backdrop
                    id: bgDebounce; interval: 110
                    onTriggered: {
                        const src = root.selName ? root.thumb(root.selName) : ""
                        if (src === (backdrop.useA ? bgA : bgB).source.toString()) return
                        backdrop.useA = !backdrop.useA
                        ;(backdrop.useA ? bgA : bgB).source = src
                    }
                }
                Connections { target: root; function onSelNameChanged() { bgDebounce.restart() } }

                Item {
                    id: bgSrc
                    anchors.fill: parent
                    visible: false
                    Image {
                        id: bgA
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true; smooth: true
                        sourceSize: Qt.size(320, 180)          // tiny decode; the blur hides it
                        opacity: backdrop.useA && status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.InOutQuad } }
                    }
                    Image {
                        id: bgB
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true; smooth: true
                        sourceSize: Qt.size(320, 180)
                        opacity: !backdrop.useA && status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.InOutQuad } }
                    }
                }
                MultiEffect {
                    anchors.fill: parent
                    source: bgSrc
                    blurEnabled: true; blur: 1.0; blurMax: 48
                    saturation: 0.15
                    brightness: -0.38
                    autoPaddingEnabled: false
                }
                Rectangle {   // vignette so the text stays readable
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.35) }
                        GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.05) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: main.close()
                onWheel: w => list.wheel(w)
            }

            // ---------- carousel ----------
            ListView {
                id: list
                width: parent.width
                height: main.cardH * 1.6
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -30 * main.ui + (1 - main.prog) * 24 * main.ui
                opacity: main.prog
                scale: 0.96 + 0.04 * main.prog
                orientation: ListView.Horizontal
                model: folderModel
                interactive: false
                spacing: main.gap
                focus: true
                clip: false
                cacheBuffer: main.step * 6
                leftMargin: (width - main.cardW) / 2
                rightMargin: (width - main.cardW) / 2

                property int selectedIndex: 0
                property bool touched: false          // user has browsed since opening -> don't auto-jump
                readonly property real centerX: width / 2

                // where contentX must be for card i to sit dead centre (ListView's origin moves, so ask it)
                function xFor(i) {
                    const keep = contentX
                    positionViewAtIndex(i, ListView.Center)
                    const t = contentX
                    contentX = keep
                    return t
                }
                function go(i) {
                    touched = true
                    const n = Math.max(0, Math.min(i, count - 1))
                    if (n === selectedIndex) return
                    selectedIndex = n
                    scroller.stop()
                    scroller.to = xFor(n)
                    scroller.start()     // starts from wherever we are, so held keys glide
                }
                
                // jump (no animation) to the wallpaper that's in use
                function snapToCurrent() {
                    if (count <= 0) return
                    let idx = 0
                    for (let i = 0; i < count; i++)
                        if (folderModel.get(i, "filePath") === main.currentWallpaper) { idx = i; break }
                    selectedIndex = idx
                    resnap()
                    Qt.callLater(resnap)               // again once the delegates exist
                }
                // put the selected card dead centre without animating (also after any size change)
                function resnap() {
                    scroller.stop()
                    forceLayout()                      // make sure the view knows its full width before we position it
                    contentX = xFor(selectedIndex)
                }
                onCountChanged: if (!touched) snapToCurrent()
                onWidthChanged: resnap()
                onLeftMarginChanged: resnap()

                NumberAnimation { id: scroller; target: list; property: "contentX"; duration: 420; easing.type: Easing.OutExpo }

                // touchpads send many small deltas; move one card per notch's worth
                property real wheelAcc: 0
                function wheel(w) {
                    const d = w.angleDelta.y !== 0 ? w.angleDelta.y : -w.angleDelta.x
                    wheelAcc += d
                    while (wheelAcc >= 120) { go(selectedIndex - 1); wheelAcc -= 120 }
                    while (wheelAcc <= -120) { go(selectedIndex + 1); wheelAcc += 120 }
                    w.accepted = true
                }

                function apply() {
                    if (count <= 0) return
                    const f = folderModel.get(selectedIndex, "filePath")
                    main.currentWallpaper = f
                    Quickshell.execDetached(["bash", main.pickerDir + "commands.sh", f])
                    main.close()
                }

                Keys.onPressed: e => {
                    const big = e.modifiers & Qt.ShiftModifier ? 5 : 1
                    switch (e.key) {
                    case Qt.Key_Left: case Qt.Key_H: case Qt.Key_Up:    go(selectedIndex - big); break
                    case Qt.Key_Right: case Qt.Key_L: case Qt.Key_Down: go(selectedIndex + big); break
                    case Qt.Key_Home: go(0); break
                    case Qt.Key_End:  go(count - 1); break
                    case Qt.Key_R: if (count > 1) { let r; do { r = Math.floor(Math.random() * count) } while (r === selectedIndex); go(r) } break
                    case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: apply(); break
                    case Qt.Key_Escape: case Qt.Key_Q: case Qt.Key_W: main.close(); break
                    default: return
                    }
                    e.accepted = true
                }

                delegate: Item {
                    id: d
                    required property int index
                    required property string fileName
                    required property string filePath
                    width: main.cardW
                    height: list.height

                    // signed distance from the centre, in cards (continuous while gliding)
                    readonly property real off: ((x - list.contentX + width / 2) - list.centerX) / main.step
                    readonly property real dist: Math.abs(off)
                    readonly property real near: Math.max(0, 1 - dist)
                    readonly property real eased: near * near * (3 - 2 * near)
                    readonly property bool active: index === list.selectedIndex
                    readonly property bool current: filePath === main.currentWallpaper

                    z: 10 - dist
                    visible: dist < 4.2
                    opacity: Math.min(1, Math.max(0, 4 - dist)) * (0.45 + 0.55 * eased)
                    scale: 0.8 + 0.3 * eased
                    // side cards drift slightly toward the centre so the deck feels tighter
                    transform: Translate { x: -Math.sign(d.off) * Math.min(d.dist, 3) * 26 * main.ui }

                    RectangularShadow {
                        anchors.fill: card
                        radius: card.radius
                        blur: 40 * main.ui
                        spread: 2 * main.ui
                        offset.y: 14 * main.ui
                        color: Qt.rgba(0, 0, 0, 0.55)
                        opacity: d.eased
                    }

                    ClippingRectangle {
                        id: card
                        anchors.centerIn: parent
                        width: main.cardW; height: main.cardH
                        radius: main.radius
                        color: Theme.bgCard

                        Image {
                            id: img
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: true; smooth: true; mipmap: true
                            sourceSize: Qt.size(800, 450)
                            // thumbnail first; if it doesn't exist yet, decode the original until the cache job finishes
                            property bool fallback: false
                            source: fallback ? "file://" + d.filePath : root.thumb(d.fileName)
                            onStatusChanged: if (status === Image.Error && !fallback) fallback = true
                            Connections { target: main; function onThumbRevChanged() { img.fallback = false } }
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 180 } }
                        }

                        // darken side cards a touch so the centre pops
                        Rectangle { anchors.fill: parent; color: "black"; opacity: 0.35 * (1 - d.eased) }

                        Rectangle {   // "in use" badge
                            visible: d.current
                            anchors { left: parent.left; top: parent.top; margins: 12 * main.ui }
                            width: curRow.implicitWidth + 18 * main.ui; height: 24 * main.ui; radius: height / 2
                            color: Qt.rgba(0, 0, 0, 0.55)
                            Row {
                                id: curRow
                                anchors.centerIn: parent
                                spacing: 6 * main.ui
                                Rectangle { width: 6 * main.ui; height: width; radius: width / 2; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                                Text { text: "In use"; color: "white"; font.family: Theme.fontFamily; font.pixelSize: 11 * main.ui; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }

                    // selection ring, drawn outside the clip so it stays crisp
                    Rectangle {
                        readonly property real pad: 5 * main.ui
                        anchors.centerIn: card
                        width: card.width + 2 * pad; height: card.height + 2 * pad
                        radius: card.radius + pad
                        color: "transparent"
                        border.width: 2.5 * main.ui
                        border.color: Theme.accent
                        opacity: d.active ? d.eased : 0
                    }

                    MouseArea {
                        anchors.fill: card
                        cursorShape: Qt.PointingHandCursor
                        onClicked: d.active ? list.apply() : list.go(d.index)
                        onWheel: w => list.wheel(w)
                    }
                }
            }

            // ---------- caption ----------
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: list.y + list.height / 2 + main.cardH * 0.55 + 56 * main.ui + (1 - main.prog) * 12 * main.ui
                opacity: main.prog
                spacing: 6 * main.ui

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.selName.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ")
                    color: "white"
                    font.family: Theme.fontFamily; font.pixelSize: 20 * main.ui; font.weight: Font.DemiBold
                    font.capitalization: Font.Capitalize
                    elide: Text.ElideMiddle
                    width: Math.min(implicitWidth, root.width * 0.6)
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: list.count > 0 ? (list.selectedIndex + 1) + " / " + list.count : ""
                    color: Qt.rgba(1, 1, 1, 0.55)
                    font.family: Theme.fontFamily; font.pixelSize: 12 * main.ui
                }

                Item { width: 1; height: 14 * main.ui }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 18 * main.ui
                    Repeater {
                        model: [["←  →", "browse"], ["R", "random"], ["Enter", "apply"], ["Esc", "close"]]
                        delegate: Row {
                            id: hint
                            required property var modelData
                            spacing: 7 * main.ui
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: keyT.implicitWidth + 14 * main.ui; height: 22 * main.ui; radius: 6 * main.ui
                                color: Qt.rgba(1, 1, 1, 0.1)
                                border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.12)
                                Text { id: keyT; anchors.centerIn: parent; text: hint.modelData[0]; color: "white"
                                       font.family: Theme.fontFamily; font.pixelSize: 11 * main.ui }
                            }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: hint.modelData[1]
                                   color: Qt.rgba(1, 1, 1, 0.55); font.family: Theme.fontFamily; font.pixelSize: 11 * main.ui }
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0 && folderModel.status === FolderListModel.Ready
                opacity: main.prog
                text: "No wallpapers in " + main.wallpaperPath
                color: "white"
                font.family: Theme.fontFamily; font.pixelSize: 15 * main.ui
            }
        }
    }
}
