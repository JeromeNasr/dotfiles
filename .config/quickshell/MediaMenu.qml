// MediaMenu.qml — now-playing popup: art, seek bar, transport, player switch, volume.
// Open: click the title in the bar, or `qs ipc call media toggle`. Esc / click outside closes.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

ShellPopup {
    id: root
    readonly property bool showing: Marquee.menuOpen
    property real prog: showing ? 1 : 0
    Behavior on prog { NumberAnimation { duration: root.showing ? 260 : 150; easing.type: root.showing ? Easing.OutQuint : Easing.InCubic } }

    surfaceOpen: showing || prog > 0.01
    WlrLayershell.namespace: "media-menu"
    WlrLayershell.keyboardFocus: showing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { item: root.showing ? catcher : null }

    readonly property var p: Marquee.player
    property bool seeking: false
    property real seekFrac: 0
    readonly property real shownFrac: seeking ? seekFrac : Marquee.frac

    IpcHandler {
        target: "media"
        function toggle(): void { Marquee.menuOpen = !Marquee.menuOpen }
        function open(): void { Marquee.menuOpen = true }
        function close(): void { Marquee.menuOpen = false }
        function playpause(): void { if (Marquee.player) Marquee.player.togglePlaying() }
        function next(): void { if (Marquee.player) Marquee.player.next() }
        function previous(): void { if (Marquee.player) Marquee.player.previous() }
    }

    component Round: Rectangle {      // round icon button
        id: rb
        property string glyph: ""
        property bool active: false
        property bool enabledBtn: true
        property real size: 36
        property real glyphSize: 16
        signal clicked()
        width: size; height: size; radius: size / 2
        color: Qt.alpha(Theme.text, !enabledBtn ? 0 : (ma.pressed ? 0.20 : (ma.containsMouse ? 0.12 : (active ? 0.10 : 0))))
        Behavior on color { ColorAnimation { duration: 100 } }
        scale: ma.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: rb.glyph; font.family: Theme.iconFont; font.pixelSize: rb.glyphSize
               color: rb.active ? Theme.accent : Theme.text; opacity: rb.enabledBtn ? 1 : 0.3 }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: rb.enabledBtn; onClicked: rb.clicked() }
    }

    component Track: Item {            // horizontal slider: smooth fill, grows on hover
        id: tk
        property real frac: 0
        property bool live: false      // true while the user drags
        property bool smooth: true
        signal scrub(real f)
        signal commit(real f)
        height: 18
        Rectangle { id: bar; width: parent.width; height: hov.containsMouse || tk.live ? 6 : 4; radius: 3
            anchors.verticalCenter: parent.verticalCenter; color: Qt.alpha(Theme.text, 0.16)
            Behavior on height { NumberAnimation { duration: 120 } }
            Rectangle { width: parent.width * tk.frac; height: parent.height; radius: 3; color: Theme.accent
                Behavior on width { enabled: tk.smooth && !tk.live; NumberAnimation { duration: 1000; easing.type: Easing.Linear } } }
        }
        Rectangle { width: 12; height: 12; radius: 6; color: Theme.text; anchors.verticalCenter: parent.verticalCenter
            x: (tk.width - width) * tk.frac; opacity: hov.containsMouse || tk.live ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } } }
        MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true
            function f(mx) { return Math.max(0, Math.min(1, mx / width)) }
            onPressed: m => { tk.live = true; tk.scrub(f(m.x)) }
            onPositionChanged: m => { if (pressed) tk.scrub(f(m.x)) }
            onReleased: m => { tk.commit(f(m.x)); tk.live = false } }
    }

    Item {
        id: catcher
        anchors.fill: parent
        focus: root.showing
        Keys.onEscapePressed: Marquee.menuOpen = false
        Keys.onSpacePressed: if (root.p) root.p.togglePlaying()
        Keys.onLeftPressed: if (root.p && root.p.canSeek) { root.p.position = Math.max(0, root.p.position - 5); root.p.positionChanged() }
        Keys.onRightPressed: if (root.p && root.p.canSeek) { root.p.position = Math.min(root.p.length, root.p.position + 5); root.p.positionChanged() }
        MouseArea { anchors.fill: parent; onClicked: Marquee.menuOpen = false }

        Rectangle {
            id: card
            width: 360
            height: col.implicitHeight + 40
            x: Math.max(12, Math.min(parent.width - width - 12, Marquee.anchorX - width / 2))
            y: 48 + (1 - root.prog) * -10
            opacity: root.prog
            scale: 0.97 + 0.03 * root.prog
            transformOrigin: Item.Top
            radius: 16
            color: Qt.alpha(Theme.bgPanel, 0.97)
            border.width: 1; border.color: Qt.alpha(Theme.text, 0.09)
            clip: true
            MouseArea { anchors.fill: parent }

            // soft glow of the cover behind everything
            RoundImage { anchors.fill: parent; radius: 16; source: Marquee.art; opacity: 0.09 }

            Column {
                id: col
                x: 20; y: 20; width: parent.width - 40; spacing: 14

                // player chips (only when more than one player is running)
                Flow {
                    visible: Marquee.players.length > 1
                    width: parent.width; spacing: 6
                    Repeater {
                        model: Marquee.players
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool sel: modelData === Marquee.player
                            width: cl.implicitWidth + 20; height: 24; radius: 12
                            color: Qt.alpha(sel ? Theme.accent : Theme.text, sel ? 0.25 : (cm.containsMouse ? 0.12 : 0.07))
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { id: cl; anchors.centerIn: parent; text: (chip.modelData.isPlaying ? "▶ " : "") + (chip.modelData.identity || "player")
                                   color: chip.sel ? Theme.text : Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11 }
                            MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: Marquee.chosen = chip.modelData }
                        }
                    }
                }

                Row {
                    spacing: 16
                    Rectangle {
                        width: 108; height: 108; radius: 12; color: Qt.alpha(Theme.text, 0.08)
                        Text { anchors.centerIn: parent; text: "󰎇"; font.family: Theme.iconFont; font.pixelSize: 40; color: Theme.textFaint }
                        RoundImage { anchors.fill: parent; radius: 12; source: Marquee.art }
                    }
                    Column {
                        width: col.width - 124; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                        Text { width: parent.width; text: Marquee.trackTitle || "Nothing playing"; color: Theme.text; elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.WordWrap
                               font.family: Theme.fontFamily; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text { width: parent.width; visible: text !== ""; text: Marquee.trackArtist; color: Theme.textDim; elide: Text.ElideRight
                               font.family: Theme.fontFamily; font.pixelSize: 13 }
                        Text { width: parent.width; visible: text !== ""; text: Marquee.trackAlbum; color: Theme.textFaint; elide: Text.ElideRight
                               font.family: Theme.fontFamily; font.pixelSize: 11 }
                    }
                }

                Column {
                    width: parent.width; spacing: 2
                    visible: Marquee.len > 0
                    Track {
                        width: parent.width
                        frac: root.shownFrac
                        onScrub: f => { root.seeking = true; root.seekFrac = f }
                        onCommit: f => { if (root.p && root.p.canSeek) { root.p.position = f * root.p.length; root.p.positionChanged() } root.seeking = false }
                    }
                    Item { width: parent.width; height: 14
                        Text { text: Marquee.fmt(root.shownFrac * Marquee.len); color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11 }
                        Text { anchors.right: parent.right; text: Marquee.fmt(Marquee.len); color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11 } }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 6
                    Round { glyph: ""; glyphSize: 14; active: root.p && root.p.shuffle; enabledBtn: root.p && root.p.shuffleSupported
                            onClicked: root.p.shuffle = !root.p.shuffle }
                    Round { glyph: ""; size: 40; glyphSize: 16; enabledBtn: root.p && root.p.canGoPrevious; onClicked: root.p.previous() }
                    Rectangle {
                        width: 52; height: 52; radius: 26; color: Theme.accent
                        scale: pma.pressed ? 0.94 : (pma.containsMouse ? 1.04 : 1)
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: Marquee.playing ? "󰏤" : "󰐊"; font.family: Theme.iconFont; font.pixelSize: 24; color: Theme.bgPanel }
                        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: if (root.p) root.p.togglePlaying() }
                    }
                    Round { glyph: ""; size: 40; glyphSize: 16; enabledBtn: root.p && root.p.canGoNext; onClicked: root.p.next() }
                    Round { glyph: root.p && root.p.loopState === MprisLoopState.Track ? "" : ""
                            active: root.p && root.p.loopState !== MprisLoopState.None; enabledBtn: root.p && root.p.loopSupported
                            onClicked: root.p.loopState = root.p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                                         : root.p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None }
                }

                Row {
                    visible: root.p && root.p.volumeSupported
                    width: parent.width; spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter; text: "󰕾"; font.family: Theme.iconFont; font.pixelSize: 15; color: Theme.textDim }
                    Track { width: parent.width - 30; anchors.verticalCenter: parent.verticalCenter; smooth: false
                            frac: root.p ? root.p.volume : 0
                            onScrub: f => { if (root.p) root.p.volume = f } }
                }
            }
        }
    }
}
