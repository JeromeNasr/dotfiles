// ShellPopup.qml — base window for the shell's popups.
//
// Unmapping a Quickshell window destroys it (new surface, GL context, render thread and
// glyph upload on every open), which made pop-ins stutter. A ShellPopup is created once and
// stays mapped: while `surfaceOpen` it covers the screen (so the popup's own click-outside catcher
// keeps working), and while closed it collapses to an invisible, click-through 1x1 surface,
// which costs the compositor next to nothing.
//
// Use it like PanelWindow and bind `surfaceOpen` (e.g. `surfaceOpen: showing || prog > 0.01`).
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: sp
    property bool surfaceOpen: false

    anchors { top: true; left: true; right: sp.surfaceOpen; bottom: sp.surfaceOpen }
    implicitWidth: 1
    implicitHeight: 1
    visible: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
}
