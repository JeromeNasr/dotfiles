// NightState.qml — shared night-light state (read from hypr/bin/night); the bar icon and NightMenu both use it.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: ns
    readonly property string bin: Quickshell.env("HOME") + "/dotfiles/dotfiles/.config/hypr/bin/night"
    property bool on: false
    property int temp: 3800
    property bool dragging: false

    function refresh() { if (!dragging && !p.running) p.running = true }
    function set(k) {                 // live while sliding; also switches the filter on
        temp = k; on = true
        Quickshell.execDetached({ command: [bin, "set", String(k)] })
        Quickshell.execDetached({ command: [bin, "on"] })
    }
    function setOn(v) { on = v; Quickshell.execDetached({ command: [bin, v ? "on" : "off"] }) }

    Process { id: p; command: [ns.bin, "status"]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); if (!ns.dragging) { ns.on = d.on; ns.temp = d.temp } } catch (e) {} } } }
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: ns.refresh() }
}
