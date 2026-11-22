// WallpaperMenu.qml — wallpaper picker.  SUPER+W / `qs ipc call wallpaper toggle`
// The selected wallpaper fills the screen as a live preview; a filmstrip along the bottom
// glides to keep the selection centred.
// Keys: ←/→ (h/l) browse · Shift = ×5 · Home/End · R random · Enter/Space apply · Esc/Q close
// Mouse: wheel browses · click a thumbnail to select, click it again to apply · click the preview to close
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt.labs.folderlistmodel

ShellPopup {
    id: main
    property alias ipc: ipcH
    readonly property real ui: sh / 1080
    readonly property string mono: "JetBrainsMono Nerd Font"

    // ---- filmstrip geometry ----
    readonly property real thumbW: 196 * ui
    readonly property real thumbH: 110 * ui
    readonly property real thumbGap: 10 * ui

    // ---- paths ----
    readonly property string home: Quickshell.env("HOME")
    readonly property string pickerDir: home + "/.config/quickshell/hyprquickpaper/"
    property string wallpaperPath: home + "/Pictures/Wallpapers/"
    property string cachePath: home + "/.cache/quickshell/wallthumbs/"
    property string currentWallpaper: ""

    // ---- open / close ----
    property bool showing: false
    property bool loaded: false          // built on first open, then kept (unloaded by shell.qml when idle)
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: main.showing ? 240 : 150; easing.type: main.showing ? Easing.OutCubic : Easing.InCubic } }
    property bool held: false
    onShowingChanged: { if (showing) { unmapTimer.stop(); held = true } else unmapTimer.restart() }
    Timer { id: unmapTimer; interval: 180; onTriggered: main.held = false }
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
        id: ipcH
        enabled: false   // the always-loaded stub in shell.qml forwards here (lazy loading)
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
    FileView {   // which wallpaper is active -> the picker opens on it
        id: stateFile
        path: (Quickshell.env("XDG_STATE_HOME") || (main.home + "/.local/state")) + "/43pr/state.json"
        printErrors: false
        onLoaded: { try { main.currentWallpaper = JSON.parse(text()).wallpaper || "" } catch (e) {} }
    }

    // thumbnails (800x450 jpg) are made in the background; when the job ends, fallbacks swap to them
    property int thumbRev: 0
    Process { id: thumbJob; command: ["bash", main.pickerDir + "cache.sh", main.pickerDir]; onExited: main.thumbRev++ }

    // "wallhaven-1k2p8v_1920x1080.png" -> "wallhaven 1k2p8v", "clean-julian-alps.jpg" -> "julian alps"
    function pretty(f) {
        return String(f).replace(/\.[^.]+$/, "").replace(/_\d+x\d+$/, "").replace(/^clean-/, "").replace(/[-_]+/g, " ")
    }

    Loader {
        anchors.fill: parent
        active: main.loaded
        sourceComponent: Item {
            id: root

            Connections {
                target: main
                function onOpened() { strip.touched = false; strip.snapToCurrent(); strip.forceActiveFocus() }
                function onCurrentWallpaperChanged() { if (!strip.touched) strip.snapToCurrent() }
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
            readonly property int sel: strip.currentIndex
            readonly property string selPath: strip.count > 0 && sel >= 0 ? String(folderModel.get(sel, "filePath")) : ""
            readonly property string selName: strip.count > 0 && sel >= 0 ? String(folderModel.get(sel, "fileName")) : ""
            function thumb(fileName) { return "file://" + main.cachePath + fileName + ".jpg" }

            // ---------- live preview: the selected wallpaper, full screen, cross-fading ----------
            Rectangle { anchors.fill: parent; color: "black"; opacity: main.prog }
            Item {
                id: preview
                anchors.fill: parent
                opacity: main.prog
                property bool useA: true
                // short debounce so holding an arrow key doesn't decode every wallpaper on the way
                Timer {
                    id: pvDebounce; interval: 90
                    onTriggered: {
                        const src = root.selPath ? "file://" + root.selPath : ""
                        const cur = preview.useA ? pvA : pvB
                        if (src === cur.source.toString()) return
                        preview.useA = !preview.useA
                        ;(preview.useA ? pvA : pvB).source = src
                    }
                }
                Connections { target: root; function onSelPathChanged() { pvDebounce.restart() } }
                Image {
                    id: pvA
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true; smooth: true; cache: false
                    sourceSize: Qt.size(main.sw, main.sh)
                    opacity: preview.useA && status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }
                }
                Image {
                    id: pvB
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true; smooth: true; cache: false
                    sourceSize: Qt.size(main.sw, main.sh)
                    opacity: !preview.useA && status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutQuad } }
                }
            }
            // shade only the bottom, where the strip and text sit; the rest of the preview stays true to life
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: main.thumbH + 150 * main.ui
                opacity: main.prog
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.85) }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: main.close()
                onWheel: w => strip.wheel(w)
            }

            // ---------- info line ----------
            Item {
                id: info
                anchors { left: parent.left; right: parent.right; bottom: strip.top; leftMargin: 44 * main.ui; rightMargin: 44 * main.ui; bottomMargin: 18 * main.ui }
                height: 24 * main.ui
                opacity: main.prog
                transform: Translate { y: (1 - main.prog) * 16 * main.ui }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16 * main.ui
                    Text {
                        text: strip.count > 0 ? String(strip.currentIndex + 1).padStart(2, "0") + " / " + String(strip.count).padStart(2, "0") : ""
                        color: Qt.rgba(1, 1, 1, 0.5); font.family: main.mono; font.pixelSize: 12 * main.ui
                        anchors.baseline: nm.baseline
                    }
                    Text {
                        id: nm
                        text: main.pretty(root.selName)
                        color: "white"; font.family: main.mono; font.pixelSize: 17 * main.ui
                    }
                    Text {
                        visible: root.selPath !== "" && root.selPath === main.currentWallpaper
                        text: "● in use"
                        color: Theme.accent; font.family: main.mono; font.pixelSize: 12 * main.ui
                        anchors.baseline: nm.baseline
                    }
                }
                Text {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: "←→ browse    r random    enter apply    esc close"
                    color: Qt.rgba(1, 1, 1, 0.45); font.family: main.mono; font.pixelSize: 11 * main.ui
                }
            }

            // ---------- filmstrip ----------
            ListView {
                id: strip
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 34 * main.ui }
                height: main.thumbH + 14 * main.ui
                opacity: main.prog
                transform: Translate { y: (1 - main.prog) * 28 * main.ui }
                orientation: ListView.Horizontal
                model: folderModel
                spacing: main.thumbGap
                clip: false
                interactive: false
                focus: true
                cacheBuffer: main.thumbW * 8
                // keep the selected thumbnail dead centre and glide there
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: (width - main.thumbW) / 2
                preferredHighlightEnd: (width + main.thumbW) / 2
                highlightMoveDuration: 280
                highlightMoveVelocity: -1
                highlightFollowsCurrentItem: true

                property bool touched: false        // browsed since opening -> don't auto-jump

                function go(i) {
                    touched = true
                    currentIndex = Math.max(0, Math.min(i, count - 1))
                }
                function snapToCurrent() {
                    if (count <= 0) return
                    let idx = 0
                    for (let i = 0; i < count; i++)
                        if (folderModel.get(i, "filePath") === main.currentWallpaper) { idx = i; break }
                    const d = highlightMoveDuration
                    highlightMoveDuration = 0
                    currentIndex = idx
                    positionViewAtIndex(idx, ListView.Center)
                    Qt.callLater(() => { strip.highlightMoveDuration = d })
                }
                onCountChanged: if (!touched) snapToCurrent()

                // touchpads send many small deltas: one thumbnail per notch's worth
                property real wheelAcc: 0
                function wheel(w) {
                    const d = w.angleDelta.y !== 0 ? w.angleDelta.y : -w.angleDelta.x
                    wheelAcc += d
                    while (wheelAcc >= 120) { go(currentIndex - 1); wheelAcc -= 120 }
                    while (wheelAcc <= -120) { go(currentIndex + 1); wheelAcc += 120 }
                    w.accepted = true
                }
                function apply() {
                    if (count <= 0) return
                    const f = folderModel.get(currentIndex, "filePath")
                    main.currentWallpaper = f
                    Quickshell.execDetached(["bash", main.pickerDir + "commands.sh", f])
                    main.close()
                }

                Keys.onPressed: e => {
                    const big = e.modifiers & Qt.ShiftModifier ? 5 : 1
                    switch (e.key) {
                    case Qt.Key_Left: case Qt.Key_H: case Qt.Key_Up:    go(currentIndex - big); break
                    case Qt.Key_Right: case Qt.Key_L: case Qt.Key_Down: go(currentIndex + big); break
                    case Qt.Key_Home: go(0); break
                    case Qt.Key_End:  go(count - 1); break
                    case Qt.Key_R: if (count > 1) { let r; do { r = Math.floor(Math.random() * count) } while (r === currentIndex); go(r) } break
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
                    readonly property bool active: ListView.isCurrentItem
                    readonly property bool inUse: filePath === main.currentWallpaper
                    width: main.thumbW
                    height: strip.height

                    Item {
                        id: frame
                        width: main.thumbW; height: main.thumbH
                        y: d.active ? 0 : 10 * main.ui
                        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        opacity: d.active ? 1 : (ma.containsMouse ? 0.85 : 0.5)
                        Behavior on opacity { NumberAnimation { duration: 160 } }

                        Image {
                            id: img
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: true; smooth: true
                            sourceSize: Qt.size(main.thumbW * 2, main.thumbH * 2)
                            // thumbnail first; until it exists, decode the original (small)
                            property bool fallback: false
                            source: fallback ? "file://" + d.filePath : root.thumb(d.fileName)
                            onStatusChanged: if (status === Image.Error && !fallback) fallback = true
                            Connections { target: main; function onThumbRevChanged() { img.fallback = false } }
                        }
                        // thin outline on the selected one; a dot marks the wallpaper in use
                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: d.active ? 2 : 1
                            border.color: d.active ? "white" : Qt.rgba(1, 1, 1, 0.12)
                        }
                        Rectangle {
                            visible: d.inUse
                            width: 7 * main.ui; height: width; radius: width / 2
                            color: Theme.accent
                            anchors { right: parent.right; top: parent.top; margins: 7 * main.ui }
                        }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: frame
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: d.active ? strip.apply() : strip.go(d.index)
                        onWheel: w => strip.wheel(w)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: strip.count === 0 && folderModel.status === FolderListModel.Ready
                opacity: main.prog
                text: "no wallpapers in " + main.wallpaperPath
                color: "white"
                font.family: main.mono; font.pixelSize: 14 * main.ui
            }
        }
    }
}
