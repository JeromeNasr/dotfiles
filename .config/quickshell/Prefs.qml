// Prefs.qml — shared clock preferences (persisted to state/clock-state.json)
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // Bar clock -> Calendar, in-process (no `sh` + `qs ipc` round trip on every click)
    signal toggleCalendar()

    property alias clock12: a.clock12          // 12-hour clock
    property alias ampm: a.ampm                // show AM/PM suffix (12-hour only)
    property alias seconds: a.seconds          // show seconds
    property alias dateInBar: a.dateInBar      // "Sun 15 Nov  16:06" in the bar
    property alias weekStartMon: a.weekStartMon

    function pad(n) { return (n < 10 ? "0" : "") + n }

    // time only, honouring every preference
    function timeText(d) {
        var f = a.clock12 ? "h:mm" : "HH:mm"
        if (a.seconds) f += ":ss"
        if (a.clock12 && a.ampm) f += " AP"
        return Qt.formatDateTime(d, f)
    }
    function barText(d) {
        return (a.dateInBar ? Qt.formatDateTime(d, "ddd d MMM") + "  " : "") + timeText(d)
    }
    // "09:30" (24h storage format) -> display string
    function showHM(hm) {
        if (!hm) return ""
        var p = hm.split(":"); var h = parseInt(p[0]), m = p[1]
        if (!a.clock12) return pad(h) + ":" + m
        var suf = h >= 12 ? "PM" : "AM"; var h12 = h % 12 === 0 ? 12 : h % 12
        return h12 + ":" + m + (a.ampm ? " " + suf : "")
    }

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/state/clock-state.json"
        printErrors: false
        onAdapterUpdated: saveTimer.restart()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) root.file.writeAdapter() }
        adapter: JsonAdapter {
            id: a
            property bool clock12: false
            property bool ampm: true
            property bool seconds: false
            property bool dateInBar: false
            property bool weekStartMon: true
        }
    }
    property Timer saveTimer: Timer { interval: 300; onTriggered: root.file.writeAdapter() }
}
