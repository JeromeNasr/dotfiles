// ConfigsPage.qml — quick access to the config files of this rice.
// Same look as the other pages. Pick an editor once (remembered); click a file to open it.
import QtQuick
import Quickshell
import Quickshell.Io
import "../"

Item {
    id: page
    readonly property int rightMargin: 46
    readonly property string mono: "JetBrainsMono Nerd Font"
    readonly property string home: Quickshell.env("HOME")
    property bool live: true

    // editor choice, remembered in state/editor
    readonly property var editors: [
        { id: "xed",  t: "xed" },
        { id: "code", t: "vs code" },
        { id: "nvim", t: "nvim" }
    ]
    property string editor: (editorFile.text() || "").trim() || "xed"
    FileView { id: editorFile; path: page.home + "/.config/quickshell/state/editor"; printErrors: false; blockLoading: true }
    function setEditor(id) { editor = id; editorFile.setText(id + "\n") }

    function expand(p) { return p.replace(/^~/, home) }
    function open(p) {
        const f = expand(p)
        if (editor === "nvim") Quickshell.execDetached(["kitty", "-e", "nvim", f])
        else Quickshell.execDetached([editor, f])
    }
    function folder(p) { const f = expand(p); Quickshell.execDetached(["xdg-open", f.substring(0, f.lastIndexOf("/"))]) }

    readonly property var groups: [
        { name: "hyprland", files: [
            { t: "main",        note: "programs, autostart, input", p: "~/.config/hypr/hyprland.lua" },
            { t: "keybinds",    note: "",                           p: "~/.config/hypr/keybinds.lua" },
            { t: "look",        note: "gaps, borders, blur, animations", p: "~/.config/hypr/look.lua" },
            { t: "rules",       note: "window and layer rules",     p: "~/.config/hypr/rules.lua" },
            { t: "monitors",    note: "displays and workspaces",    p: "~/.config/hypr/monitors.lua" },
            { t: "lock screen", note: "hyprlock",                   p: "~/.config/hypr/hyprlock.conf" },
            { t: "idle",        note: "hypridle: dim, lock, sleep", p: "~/.config/hypr/hypridle.conf" }
        ]},
        { name: "apps", files: [
            { t: "terminal",    note: "kitty",                      p: "~/.config/kitty/kitty.conf" },
            { t: "shell",       note: "zsh",                        p: "~/.zshrc" },
            { t: "launcher",    note: "rofi",                       p: "~/.config/rofi/config.rasi" },
            { t: "fetch",       note: "fastfetch",                  p: "~/.config/fastfetch/config.jsonc" }
        ]},
        { name: "desktop", files: [
            { t: "shell",       note: "quickshell: bar, menus, this window", p: "~/.config/quickshell/shell.qml" },
            { t: "themes",      note: "what the theme switcher writes to", p: "~/.config/43pr/targets.toml" }
        ]}
    ]

    Process { id: pReload; command: ["hyprctl", "reload"]; stdout: StdioCollector { onStreamFinished: page.reloadMsg = text.trim() === "ok" ? "reloaded" : text.trim().split("\n")[0] } }
    property string reloadMsg: ""
    Timer { running: page.reloadMsg !== ""; interval: 2500; onTriggered: page.reloadMsg = "" }

    component Act: Text {
        id: act
        property bool lit: false
        signal clicked()
        color: lit ? Theme.accent : am.containsMouse ? Theme.text : Theme.textFaint
        font.family: page.mono; font.pixelSize: 11; font.underline: am.containsMouse
        MouseArea { id: am; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
    }

    Flickable {
        id: flick
        anchors { fill: parent; rightMargin: page.rightMargin }
        contentWidth: width
        contentHeight: content.implicitHeight + 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: flick.width
            spacing: 14

            Text { text: "Configs"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19 }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Item {
                width: parent.width; height: 18
                Text { id: el; width: 84; anchors.verticalCenter: parent.verticalCenter; text: "open with"; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
                Row {
                    anchors { left: el.right; verticalCenter: parent.verticalCenter }
                    spacing: 22
                    Repeater {
                        model: page.editors
                        Text {
                            id: eo
                            required property var modelData
                            readonly property bool cur: page.editor === modelData.id
                            text: (cur ? "● " : "") + modelData.t
                            color: cur ? Theme.accent : em.containsMouse ? Theme.text : Theme.textFaint
                            font.family: page.mono; font.pixelSize: 12
                            MouseArea { id: em; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.setEditor(eo.modelData.id) }
                        }
                    }
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 14
                    Text { visible: page.reloadMsg !== ""; text: page.reloadMsg; color: Theme.textDim; font.family: page.mono; font.pixelSize: 11 }
                    Act { text: "reload hyprland"; onClicked: pReload.running = true }
                }
            }

            Repeater {
                model: page.groups
                Column {
                    id: grp
                    required property var modelData
                    width: content.width
                    spacing: 2

                    Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }
                    Item { width: 1; height: 8 }
                    Text { text: grp.modelData.name; color: Theme.textDim; font.family: page.mono; font.pixelSize: 12; bottomPadding: 4 }

                    Repeater {
                        model: grp.modelData.files
                        Item {
                            id: row
                            required property var modelData
                            width: grp.width; height: 26
                            Rectangle {
                                anchors.fill: parent; anchors.leftMargin: -8; anchors.rightMargin: -8
                                radius: 6; color: Theme.alpha(Theme.text, rma.containsMouse ? 0.04 : 0)
                            }
                            MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.open(row.modelData.p) }
                            Text { id: rt; width: 120; anchors.verticalCenter: parent.verticalCenter; text: row.modelData.t; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
                            Text { anchors { left: rt.right; right: acts.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                   elide: Text.ElideRight
                                   text: row.modelData.p + (row.modelData.note ? "   " + row.modelData.note : "")
                                   color: rma.containsMouse ? Theme.textDim : Theme.textFaint; font.family: page.mono; font.pixelSize: 11 }
                            Row {
                                id: acts
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 14
                                Act { text: "folder"; onClicked: page.folder(row.modelData.p) }
                                Act { text: "edit"; onClicked: page.open(row.modelData.p) }
                            }
                        }
                    }
                }
            }
        }
    }
}
