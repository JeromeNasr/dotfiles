// Wallpaper picker — centered carousel, fast & light.
// Keys: ←/→ (h/l)  move · Enter/Space apply · Esc/W/Q close · mouse: click a card, wheel scrolls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import Qt.labs.folderlistmodel

PanelWindow {
    id: main
    readonly property real ui: Screen.height / 1080

    // ---- look ----
    readonly property real cardW: 400 * ui
    readonly property real cardH: 225 * ui
    readonly property real gap: 26 * ui
    readonly property real step: cardW + gap
    readonly property real cardRadius: 16 * ui
    readonly property int  moveMs: 300          // carousel glide
    readonly property int  fadeMs: 180          // open / close

    // ---- theme colours (live from the 43pr palette) ----
    property color accent: "#ffffff"
    property color textCol: "#ffffff"
    property color dimCol: "#b0b0b0"
    property color cardCol: "#1a1a1a"

    property string wallpaperPath: configs.wallpaper_path.replace("$HOME", Quickshell.env("HOME"))
    property string cachePath: configs.cache_path.replace("$HOME", Quickshell.env("HOME"))
    property string currentWallpaper: ""
    property bool closing: false

    implicitHeight: Screen.height
    implicitWidth: Screen.width
    color: "transparent"
    aboveWindows: true
    exclusionMode: "Ignore"
    exclusiveZone: 1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "wallpaper-picker"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Component.onCompleted: Quickshell.execDetached(["bash", Quickshell.shellPath("cache.sh"), Quickshell.shellDir])

    function close() {
        if (closing) return
        closing = true
        root.opacity = 0
        quitTimer.start()
    }
    Timer { id: quitTimer; interval: main.fadeMs; onTriggered: Qt.quit() }

    // ---------- data ----------
    FileView {
        path: Quickshell.shellPath("config.json")
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter {
            id: configs
            property string wallpaper_path
            property string cache_path
        }
    }

    FileView {   // accent colours follow the active theme
        path: Quickshell.env("HOME") + "/.cache/43pr/quickshell-theme.json"
        printErrors: false
        onLoaded: {
            try {
                const p = JSON.parse(text())
                main.accent = p.accent || main.accent
                main.textCol = p.text || main.textCol
                main.dimCol = p.textDim || main.dimCol
                main.cardCol = p.bgCard || main.cardCol
            } catch (e) {}
        }
    }

    FileView {   // which wallpaper is active now -> start the carousel on it
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/43pr/state.json"
        printErrors: false
        onLoaded: {
            try { main.currentWallpaper = JSON.parse(text()).wallpaper || "" } catch (e) {}
            list.centerOnStart()
        }
    }

    FolderListModel {
        id: folderModel
        folder: "file://" + main.wallpaperPath
        showDirs: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        sortField: FolderListModel.Time      // newest first: freshly added wallpapers show up first
        sortReversed: true
    }

    // ---------- UI ----------
    Item {
        id: root
        anchors.fill: parent
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: main.fadeMs; easing.type: Easing.OutCubic } }
        Component.onCompleted: opacity = 1

        // dim backdrop (Hyprland blurs it via the "wallpaper-picker" layer rule)
        Rectangle { anchors.fill: parent; color: "#000000"; opacity: 0.5 }
        MouseArea { anchors.fill: parent; onClicked: main.close() }

        // header
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 - main.cardH * 1.15 - 70 * main.ui
            text: "WALLPAPERS"
            color: main.textCol
            opacity: 0.9
            font.pixelSize: 15 * main.ui
            font.letterSpacing: 6
            font.weight: Font.Medium
        }

        ListView {
            id: list
            width: parent.width
            height: main.cardH * 1.5
            anchors.centerIn: parent
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
            property bool ready: false
            readonly property real centerX: width / 2

            function clampIndex(i) { return Math.max(0, Math.min(i, count - 1)) }

            function centerOnStart() {
                if (ready || count <= 0) return
                let idx = 0
                if (main.currentWallpaper !== "") {
                    for (let i = 0; i < count; i++)
                        if (folderModel.get(i, "filePath") === main.currentWallpaper) { idx = i; break }
                }
                selectedIndex = idx
                contentX = idx * main.step - leftMargin
                ready = true
            }
            onCountChanged: centerOnStart()

            function go(i) { selectedIndex = clampIndex(i) }
            onSelectedIndexChanged: if (ready) contentX = selectedIndex * main.step - leftMargin

            Behavior on contentX {
                enabled: list.ready
                NumberAnimation { duration: main.moveMs; easing.type: Easing.OutQuint }
            }

            function apply() {
                if (count <= 0) return
                Quickshell.execDetached(["bash", Quickshell.shellPath("commands.sh"), folderModel.get(selectedIndex, "filePath")])
                main.close()
            }

            Keys.onPressed: function(e) {
                switch (e.key) {
                case Qt.Key_Left: case Qt.Key_H: case Qt.Key_Up:    go(selectedIndex - (e.modifiers & Qt.ShiftModifier ? 5 : 1)); break
                case Qt.Key_Right: case Qt.Key_L: case Qt.Key_Down: go(selectedIndex + (e.modifiers & Qt.ShiftModifier ? 5 : 1)); break
                case Qt.Key_Home: go(0); break
                case Qt.Key_End:  go(count - 1); break
                case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: apply(); break
                case Qt.Key_Escape: case Qt.Key_Q: main.close(); break
                default: return
                }
                e.accepted = true
            }

            delegate: Item {
                id: d
                width: main.cardW
                height: list.height

                // distance of this card from the centre, in "cards" (continuous while gliding)
                readonly property real dist: Math.abs((x - list.contentX + width / 2) - list.centerX) / main.step
                readonly property real near: Math.max(0, 1 - dist)
                readonly property real eased: near * near * (3 - 2 * near)      // smoothstep
                readonly property bool active: index === list.selectedIndex

                z: eased
                scale: 0.78 + 0.42 * eased
                opacity: Math.max(0, 0.38 + 0.62 * eased - Math.max(0, dist - 3) * 0.4)
                visible: opacity > 0.02

                ClippingRectangle {
                    id: card
                    anchors.centerIn: parent
                    width: main.cardW
                    height: main.cardH
                    radius: main.cardRadius
                    color: main.cardCol
                    border.width: d.active ? Math.max(2, 3 * main.ui) : 0
                    border.color: main.accent
                    Behavior on border.width { NumberAnimation { duration: 140 } }

                    Image {
                        id: img
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        smooth: true
                        mipmap: false
                        sourceSize.width: main.cardW * 1.6
                        sourceSize.height: main.cardH * 1.6
                        source: "file://" + main.cachePath + fileName
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }

                        property int tries: 0
                        Timer {
                            id: retry
                            interval: 700
                            onTriggered: { if (img.tries++ < 25) { const s = img.source; img.source = ""; img.source = s } }
                        }
                        onStatusChanged: if (status === Image.Error) retry.start()
                    }
                }

                MouseArea {
                    anchors.fill: card
                    onClicked: d.active ? list.apply() : list.go(index)
                    onWheel: function(w) { list.go(list.selectedIndex + (w.angleDelta.y > 0 ? -1 : 1)); w.accepted = true }
                }
            }
        }

        // caption
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height / 2 + main.cardH * 0.6 + 56 * main.ui
            spacing: 8 * main.ui
            readonly property string fname: list.count > 0 ? String(folderModel.get(list.selectedIndex, "fileName")) : ""

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: parent.fname.replace(/\.[^.]+$/, "").replace(/[-_]+/g, " ")
                color: main.textCol
                font.pixelSize: 20 * main.ui
                font.weight: Font.Medium
                elide: Text.ElideMiddle
                width: Math.min(implicitWidth, root.width * 0.6)
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: list.count > 0 ? (list.selectedIndex + 1) + " / " + list.count : ""
                color: main.accent
                font.pixelSize: 13 * main.ui
                font.letterSpacing: 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "←  →  browse     ⏎  apply     esc  close"
                color: main.dimCol
                opacity: 0.7
                font.pixelSize: 12 * main.ui
                topPadding: 10 * main.ui
            }
        }

        Text {
            anchors.centerIn: parent
            visible: list.count === 0 && folderModel.status === FolderListModel.Ready
            text: "No wallpapers in " + main.wallpaperPath
            color: main.dimCol
            font.pixelSize: 16 * main.ui
        }
    }
}
