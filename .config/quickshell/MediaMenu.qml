// MediaMenu.qml — now-playing popup: blurred cover backdrop, big art, live equalizer, seek bar with
// time bubble, transport, player switch and the SYSTEM volume (slider + mute + %).
// Open: click the title in the bar, or `qs ipc call media toggle`. Esc / click outside closes.
// Keys: Space play/pause · ←/→ seek 5s · ↑/↓ volume · M mute · N/P next/previous.  Scroll = volume.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

ShellPopup {
    id: root
    property alias ipc: ipcH
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

    // ---- system output volume (PipeWire default sink) ----
    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool hasSink: sink !== null && sink.audio !== null
    readonly property real vol: hasSink ? sink.audio.volume : 0
    readonly property bool muted: hasSink && sink.audio.muted
    function setVol(v) { if (hasSink) { sink.audio.muted = false; sink.audio.volume = Math.max(0, Math.min(1, v)) } }
    function stepVol(d) { setVol(Math.round((vol + d) * 100) / 100) }
    function toggleMute() { if (hasSink) sink.audio.muted = !sink.audio.muted }
    readonly property string volGlyph: !hasSink || muted || vol <= 0 ? "󰖁" : vol < 0.34 ? "󰕿" : vol < 0.67 ? "󰖀" : "󰕾"

    IpcHandler {
        id: ipcH
        enabled: false   // the always-loaded stub in shell.qml forwards here (lazy loading)
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
        color: Qt.alpha(Theme.text, !enabledBtn ? 0 : (ma.pressed ? 0.22 : (ma.containsMouse ? 0.13 : (active ? 0.10 : 0))))
        Behavior on color { ColorAnimation { duration: 100 } }
        scale: ma.pressed ? 0.90 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        Text { anchors.centerIn: parent; text: rb.glyph; font.family: Theme.iconFont; font.pixelSize: rb.glyphSize
               color: rb.active ? Theme.accent : Theme.text; opacity: rb.enabledBtn ? 1 : 0.3
               Behavior on color { ColorAnimation { duration: 120 } } }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: rb.enabledBtn; onClicked: rb.clicked() }
    }

    // horizontal slider: fill grows on hover, knob + optional value bubble while dragging
    component Track: Item {
        id: tk
        property real frac: 0
        property bool live: false      // true while the user drags
        property bool smooth: true
        property color fillColor: Theme.accent
        property string bubbleText: ""
        signal scrub(real f)
        signal commit(real f)
        height: 22
        readonly property bool big: hov.containsMouse || tk.live
        Rectangle { id: bar; width: parent.width; height: tk.big ? 7 : 4; radius: height / 2
            anchors.verticalCenter: parent.verticalCenter; color: Qt.alpha(Theme.text, 0.16)
            Behavior on height { NumberAnimation { duration: 120 } }
            Rectangle { width: parent.width * tk.frac; height: parent.height; radius: height / 2; color: tk.fillColor
                Behavior on width { enabled: tk.smooth && !tk.live; NumberAnimation { duration: 1000; easing.type: Easing.Linear } } }
        }
        Rectangle { id: knob; width: 14; height: 14; radius: 7; color: Theme.text; anchors.verticalCenter: parent.verticalCenter
            x: (tk.width - width) * tk.frac; opacity: tk.big ? 1 : 0; scale: tk.live ? 1.2 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 100 } } }
        Rectangle { visible: tk.live && tk.bubbleText !== ""; width: bt.implicitWidth + 14; height: 20; radius: 6
            color: Theme.bgCard; border.width: 1; border.color: tk.fillColor
            y: -height - 2
            x: Math.max(0, Math.min(tk.width - width, knob.x + knob.width / 2 - width / 2))
            Text { id: bt; anchors.centerIn: parent; text: tk.bubbleText; color: Theme.text
                   font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true } }
        MouseArea { id: hov; anchors.fill: parent; hoverEnabled: true
            function f(mx) { return Math.max(0, Math.min(1, mx / width)) }
            onPressed: m => { tk.live = true; tk.scrub(f(m.x)) }
            onPositionChanged: m => { if (pressed) tk.scrub(f(m.x)) }
            onReleased: m => { tk.commit(f(m.x)); tk.live = false } }
    }

    // little equalizer: bars bounce while something plays, settle flat when paused
    component Equalizer: Row {
        id: eq
        property bool active: false
        spacing: 2
        height: 14
        Repeater {
            model: 4
            delegate: Item {
                id: eb
                required property int index
                width: 3; height: 14
                Rectangle {
                    id: bar
                    width: 3; radius: 1.5; color: Theme.accent
                    anchors.bottom: parent.bottom
                    height: 3
                    SequentialAnimation on height {
                        running: eq.active
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) bar.height = 3
                        NumberAnimation { to: 6 + ((eb.index * 5) % 9); duration: 280 + eb.index * 70; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 3 + ((eb.index * 7) % 5); duration: 300 + eb.index * 55; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 14 - ((eb.index * 3) % 6); duration: 240 + eb.index * 80; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
    }

    Item {
        id: catcher
        anchors.fill: parent
        focus: root.showing
        Keys.onEscapePressed: Marquee.menuOpen = false
        Keys.onSpacePressed: if (root.p) root.p.togglePlaying()
        Keys.onLeftPressed: if (root.p && root.p.canSeek) { root.p.position = Math.max(0, root.p.position - 5); root.p.positionChanged() }
        Keys.onRightPressed: if (root.p && root.p.canSeek) { root.p.position = Math.min(root.p.length, root.p.position + 5); root.p.positionChanged() }
        Keys.onUpPressed: root.stepVol(0.05)
        Keys.onDownPressed: root.stepVol(-0.05)
        Keys.onPressed: e => {
            if (e.key === Qt.Key_M) root.toggleMute()
            else if (e.key === Qt.Key_N && root.p && root.p.canGoNext) root.p.next()
            else if (e.key === Qt.Key_P && root.p && root.p.canGoPrevious) root.p.previous()
        }
        MouseArea { anchors.fill: parent; onClicked: Marquee.menuOpen = false }

        Rectangle {
            id: card
            width: 392
            height: col.implicitHeight + 44
            x: Math.max(12, Math.min(parent.width - width - 12, Marquee.anchorX - width / 2))
            y: 48 + (1 - root.prog) * -10
            opacity: root.prog
            scale: 0.97 + 0.03 * root.prog
            transformOrigin: Item.Top
            radius: 20
            color: Qt.alpha(Theme.bgPanel, 0.98)
            border.width: 1; border.color: Qt.alpha(Theme.text, 0.10)
            clip: true
            Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            // scroll anywhere on the card = system volume
            MouseArea {
                anchors.fill: parent
                onWheel: w => root.stepVol(w.angleDelta.y > 0 ? 0.05 : -0.05)
            }

            // blurred cover as an ambient backdrop, with a gradient so text stays readable
            Item {
                anchors.fill: parent
                visible: Marquee.art !== ""
                opacity: 0.55
                layer.enabled: visible
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64; saturation: 0.35 }
                RoundImage { anchors.fill: parent; radius: 20; source: Marquee.art }
            }
            Rectangle {
                anchors.fill: parent; radius: 20
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.alpha(Theme.bgPanel, 0.35) }
                    GradientStop { position: 0.55; color: Qt.alpha(Theme.bgPanel, 0.72) }
                    GradientStop { position: 1.0; color: Qt.alpha(Theme.bgPanel, 0.92) }
                }
            }

            Column {
                id: col
                x: 22; y: 22; width: parent.width - 44; spacing: 16

                // header: source + equalizer, then player chips when several are running
                Row {
                    width: parent.width; spacing: 8
                    Equalizer { active: Marquee.playing; anchors.verticalCenter: parent.verticalCenter }
                    Text { anchors.verticalCenter: parent.verticalCenter
                           text: !root.p ? "NOTHING PLAYING" : (Marquee.playing ? "NOW PLAYING" : "PAUSED") + (root.p.identity ? "  ·  " + root.p.identity.toUpperCase() : "")
                           color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 10; font.letterSpacing: 1.5; font.weight: Font.DemiBold
                           elide: Text.ElideRight; width: parent.width - 30 }
                }
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
                            color: Qt.alpha(sel ? Theme.accent : Theme.text, sel ? 0.28 : (cm.containsMouse ? 0.14 : 0.08))
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text { id: cl; anchors.centerIn: parent; text: (chip.modelData.isPlaying ? "▶ " : "") + (chip.modelData.identity || "player")
                                   color: chip.sel ? Theme.text : Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11 }
                            MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: Marquee.chosen = chip.modelData }
                        }
                    }
                }

                // art + track info
                Row {
                    spacing: 18
                    Item {
                        id: artBox
                        width: 132; height: 132
                        scale: Marquee.playing ? 1 : 0.94
                        Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        // soft drop shadow
                        Rectangle { anchors.fill: parent; anchors.topMargin: 8; radius: 16; color: "black"; opacity: 0.45
                                    layer.enabled: true; layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 28 } }
                        Rectangle {
                            anchors.fill: parent; radius: 16; color: Qt.alpha(Theme.text, 0.08)
                            Text { anchors.centerIn: parent; text: "󰎇"; font.family: Theme.iconFont; font.pixelSize: 48; color: Theme.textFaint }
                            RoundImage { anchors.fill: parent; radius: 16; source: Marquee.art }
                        }
                    }
                    Column {
                        width: col.width - 150; anchors.verticalCenter: parent.verticalCenter; spacing: 5
                        Text { width: parent.width; text: Marquee.trackTitle || "Nothing playing"; color: Theme.text; elide: Text.ElideRight; maximumLineCount: 3; wrapMode: Text.WordWrap
                               font.family: Theme.fontFamily; font.pixelSize: 18; font.weight: Font.Bold }
                        Text { width: parent.width; visible: text !== ""; text: Marquee.trackArtist; color: Theme.accent; elide: Text.ElideRight
                               font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { width: parent.width; visible: text !== ""; text: Marquee.trackAlbum; color: Theme.textFaint; elide: Text.ElideRight
                               font.family: Theme.fontFamily; font.pixelSize: 11 }
                    }
                }

                // seek bar
                Column {
                    width: parent.width; spacing: 0
                    visible: Marquee.len > 0
                    Track {
                        width: parent.width
                        frac: root.shownFrac
                        bubbleText: Marquee.fmt(root.shownFrac * Marquee.len)
                        onScrub: f => { root.seeking = true; root.seekFrac = f }
                        onCommit: f => { if (root.p && root.p.canSeek) { root.p.position = f * root.p.length; root.p.positionChanged() } root.seeking = false }
                    }
                    Item { width: parent.width; height: 14
                        Text { text: Marquee.fmt(root.shownFrac * Marquee.len); color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11 }
                        Text { anchors.right: parent.right; text: "-" + Marquee.fmt(Math.max(0, (1 - root.shownFrac) * Marquee.len)); color: Theme.textDim; font.family: Theme.fontFamily; font.pixelSize: 11 } }
                }

                // transport
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; spacing: 8
                    Round { glyph: "󰒝"; glyphSize: 15; active: root.p && root.p.shuffle; enabledBtn: root.p && root.p.shuffleSupported
                            onClicked: root.p.shuffle = !root.p.shuffle }
                    Round { glyph: "󰒮"; size: 42; glyphSize: 20; enabledBtn: root.p && root.p.canGoPrevious; onClicked: root.p.previous() }
                    Rectangle {
                        width: 58; height: 58; radius: 29; color: Theme.accent
                        scale: pma.pressed ? 0.93 : (pma.containsMouse ? 1.06 : 1)
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: Marquee.playing ? "󰏤" : "󰐊"; font.family: Theme.iconFont; font.pixelSize: 28; color: Theme.bgPanel }
                        MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; onClicked: if (root.p) root.p.togglePlaying() }
                    }
                    Round { glyph: "󰒭"; size: 42; glyphSize: 20; enabledBtn: root.p && root.p.canGoNext; onClicked: root.p.next() }
                    Round { glyph: root.p && root.p.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                            glyphSize: 15
                            active: root.p && root.p.loopState !== MprisLoopState.None; enabledBtn: root.p && root.p.loopSupported
                            onClicked: root.p.loopState = root.p.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                                                         : root.p.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None }
                }

                // system volume: mute button · slider · percent
                Rectangle {
                    width: parent.width; height: 46; radius: 14
                    color: Qt.alpha(Theme.text, 0.06)
                    border.width: 1; border.color: Qt.alpha(Theme.text, 0.06)
                    Row {
                        anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 14; spacing: 8
                        Round { anchors.verticalCenter: parent.verticalCenter; size: 34; glyphSize: 17
                                glyph: root.volGlyph; enabledBtn: root.hasSink; active: root.muted
                                onClicked: root.toggleMute() }
                        Track {
                            id: volTrack
                            width: parent.width - 34 - 48 - 16; anchors.verticalCenter: parent.verticalCenter
                            smooth: false
                            fillColor: root.muted ? Theme.textFaint : Theme.accent
                            frac: root.muted ? 0 : root.vol
                            bubbleText: Math.round(root.vol * 100) + "%"
                            onScrub: f => root.setVol(f)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter; width: 48; horizontalAlignment: Text.AlignRight
                            text: !root.hasSink ? "—" : root.muted ? "Muted" : Math.round(root.vol * 100) + "%"
                            color: root.muted ? Theme.textFaint : Theme.text
                            font.family: Theme.fontFamily; font.pixelSize: 13; font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
