// ShellPopup.qml — base window for the shell's popups.
//
// Unmapping a Quickshell window destroys it (new surface, GL context, render thread and
// glyph upload on every open), which made pop-ins stutter. A ShellPopup is created once and
// stays mapped: while `surfaceOpen` it covers the screen (so the popup's own click-outside catcher
// keeps working), and while closed it collapses to an invisible, click-through 1x1 surface,
// which costs the compositor next to nothing.
//
// Content is laid out on a screen-sized stage, NOT on the window: on open the window is still
// 1x1 for a frame or two, and anything positioned from the window size would start at the left
// edge and jump into place. Use `sw` / `sh` (screen size) instead of `width` / `height`.
//
// Use it like PanelWindow and bind `surfaceOpen` (e.g. `surfaceOpen: showing || prog > 0.01`).
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: sp
    property bool surfaceOpen: false
    readonly property real sw: screen ? screen.width : 1920
    readonly property real sh: screen ? screen.height : 1080
    default property alias content: stage.data

    anchors { top: true; left: true; right: sp.surfaceOpen; bottom: sp.surfaceOpen }
    implicitWidth: 1
    implicitHeight: 1
    visible: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay

    Item { id: stage; width: sp.sw; height: sp.sh }
}
