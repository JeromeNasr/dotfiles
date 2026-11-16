// Touch.qml — touch-mode state shared by the whole shell (persisted to state/touch-state.json).
//   qs ipc call touch toggle | on | off | auto
// "auto" follows the laptop's tablet-mode switch (the gesture daemon calls on/off for it).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property alias mode: a.mode                 // bigger bar + OSK auto-prompt + roomier overlays
    property alias autoMode: a.autoMode         // follow tablet-mode switch
    // multiplier overlays use for hit targets / type
    readonly property real k: mode ? 1.18 : 1.0

    function setMode(v) { a.mode = v }
    function toggle() { a.mode = !a.mode }

    property IpcHandler ipc: IpcHandler {
        target: "touch"
        function toggle(): void { root.toggle() }
        function on(): void { root.setMode(true) }
        function off(): void { root.setMode(false) }
        function tablet(v: bool): void { if (a.autoMode) root.setMode(v) }   // from the gesture daemon
        function status(): string { return a.mode ? "on" : "off" }
    }

    // squeekboard gives auto-show on text-field focus in every app; only worth having in touch mode
    property Process squeek: Process {
        command: ["squeekboard"]
        running: a.mode
    }

    property FileView file: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/state/touch-state.json"
        printErrors: false
        onAdapterUpdated: saveTimer.restart()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) root.file.writeAdapter() }
        adapter: JsonAdapter {
            id: a
            property bool mode: false
            property bool autoMode: true
        }
    }
    property Timer saveTimer: Timer { interval: 300; onTriggered: root.file.writeAdapter() }
}
