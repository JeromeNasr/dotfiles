// Marquee.qml — shared MPRIS state for the bar widget and the media popup (one source of truth for all screens)
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Scope {
    id: root

    // ---- which player ----
    property var chosen: null                       // set from the popup's player chips; falls back to auto
    readonly property var players: Mpris.players.values
    readonly property var player: {
        const ps = players;
        if (chosen && ps.indexOf(chosen) >= 0) return chosen;
        return ps.find(p => p.isPlaying) ?? ps[0] ?? null;
    }
    readonly property bool playing: player !== null && player.isPlaying

    // ---- track ----
    readonly property string trackTitle: player ? (player.trackTitle || "") : ""
    readonly property string trackArtist: player ? (player.trackArtist || "") : ""
    readonly property string trackAlbum: player ? (player.trackAlbum || "") : ""
    readonly property string art: player ? (player.trackArtUrl || "") : ""
    readonly property string title: player ? ((trackArtist ? trackArtist + " - " : "") + trackTitle) : ""
    readonly property string text: title                         // kept for older callers

    // ---- progress (updated once a second while playing and something is looking) ----
    readonly property real len: player && player.lengthSupported ? player.length : 0
    readonly property real pos: player && player.positionSupported ? player.position : 0
    readonly property real frac: len > 0 ? Math.max(0, Math.min(1, pos / len)) : 0
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.playing && root.player.positionSupported
        onTriggered: root.player.positionChanged()
    }

    // ---- popup control (set by the bar widget; read by MediaMenu) ----
    property bool menuOpen: false
    property real anchorX: 0

    readonly property int maxW: 170       // visible text width in the bar
    readonly property int gap: 28         // gap between the two marquee copies
    readonly property int holdMs: 2200    // pause at the start of each loop
    readonly property int speed: 38       // px per second

    function fmt(s) {
        s = Math.max(0, Math.round(s));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x;
    }
}
