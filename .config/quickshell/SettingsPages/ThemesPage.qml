import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell
import "../"

Item {
    id: page
    property real marginLeft: 0
    property real marginRight: 55
    property real marginTop: 0
    property real marginBottom: 0
    property real sectionSpacing: 6

    function editConfig(path) {
        Quickshell.execDetached([
            "xed",
            path.replace(/^~/, Quickshell.env("HOME"))
        ])
    }

    function runTheme(themeCommand) {
        console.log("Running theme:", themeCommand)

        Quickshell.execDetached([
            "/bin/sh",
            "-c",
            "python3 \"$HOME/.config/43pr/bin/theme.py\" " + themeCommand
        ])

        // Re-read state.json shortly after, so the buttons reflect the new
        // colorgen / appearance (presets can change the appearance too).
        reloadTimer.restart()
    }

    property bool colorGen: true
    property bool darkMode: true

    FileView {
        id: stateView
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
              + "/43pr/state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            page.colorGen = stateAdapter.colorgen
            page.darkMode = stateAdapter.mode_appearance !== "light"
        }
        adapter: JsonAdapter {
            id: stateAdapter
            property bool colorgen: true
            property string mode_appearance: "dark"
        }
    }

    // ---- live preview data (built by ~/.local/bin/rice-theme-previews) ----
    property var previews: ({})
    FileView {
        path: Quickshell.env("HOME") + "/.cache/43pr/theme-previews.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { page.previews = JSON.parse(text()) } catch (e) {} }
    }
    Component.onCompleted: Quickshell.execDetached(["/bin/sh", "-c", "\"$HOME/.local/bin/rice-theme-previews\""])
    Component.onDestruction: { Theme.previewPalette = null; Theme.fontPreview = "" }

    Timer {
        id: previewTimer
        interval: 90                       // debounce so sweeping the mouse doesn't thrash
        property var pending: null
        onTriggered: Theme.previewPalette = pending
    }
    function previewTheme(key) {
        previewTimer.pending = key && page.previews[key] ? page.previews[key] : null
        previewTimer.restart()
    }

    function setFont(family) {
        Theme.fontPreview = ""
        Quickshell.execDetached(["/bin/sh", "-c", "\"$HOME/.local/bin/rice-font\" set \"$1\"", "sh", family])
    }

    component FontButton: Rectangle {
        required property string family
        required property string label
        width: (parent.width - (parent.columns - 1) * parent.spacing) / parent.columns
        height: 42
        radius: Theme.radius
        color: "#00000000"
        border.width: 1
        border.color: Theme.fontFamily === family ? Theme.accent : Theme.border
        Behavior on border.color { ColorAnimation { duration: 120 } }

        Text {
            anchors.fill: parent
            anchors.margins: 6
            text: label + "  Aa 0O"
            color: Theme.fontFamily === family ? Theme.accent : Theme.textDim
            font.family: family
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: { parent.color = Theme.alpha(Theme.accent, 0.08); Theme.fontPreview = family }
            onExited:  { parent.color = "#00000000"; Theme.fontPreview = "" }
            onClicked: page.setFont(family)
        }
    }

    Timer {
        id: reloadTimer
        interval: 700
        onTriggered: stateView.reload()
    }

    function setColorGen(on) {
        page.colorGen = on
        runTheme("colorgen " + (on ? "on" : "off"))
    }

    function toggleMode() {
        page.darkMode = !page.darkMode      // optimistic; state.json reload corrects it
        runTheme("toggle")
    }

    component ToggleButton: Rectangle {
        required property string label
        required property bool checked
        property string valueText: checked ? "On" : "Off"
        signal toggled()

        width: parent.width
        height: 42
        radius: Theme.radius
        color: "#00000000"
        border.width: 1
        border.color: checked ? Theme.accent : Theme.border

        Text {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            text: label + ": " + valueText
            color: checked ? Theme.accent : Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
                parent.color = Theme.alpha(Theme.accent, 0.08)
                parent.border.color = Theme.accent
            }

            onExited: {
                parent.color = "#00000000"
                parent.border.color = parent.checked ? Theme.accent : Theme.border
            }

            onClicked: parent.toggled()
        }
    }

    component ConfigButton: Rectangle {
        required property string label
        required property string path

        width: parent.width
        height: 42
        radius: Theme.radius
        color: "#00000000"
        border.width: 1
        border.color: Theme.border

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: label
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 13
            font.bold: true
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Text {
                text: "\uf120"
                color: Theme.textDim
                font.family: Theme.iconFont
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "Edit " + path.split("/").pop()
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
                parent.color = Theme.alpha(Theme.accent, 0.08)
                parent.border.color = Theme.accent
            }

            onExited: {
                parent.color = "#00000000"
                parent.border.color = Theme.border
            }

            onClicked: page.editConfig(path)
        }
    }

    component ThemeButton: Rectangle {
        required property string label
        required property string command
        readonly property string key: command === "default" ? "default" : command.replace("preset ", "")
        readonly property var sw: (page.previews[key] && page.previews[key]._swatch) ? page.previews[key]._swatch : []

        width: (parent.width - (parent.columns - 1) * parent.spacing) / parent.columns
        height: 58
        radius: Theme.radius
        color: "#00000000"
        border.width: 1
        border.color: Theme.border
        Behavior on border.color { ColorAnimation { duration: 120 } }

        Text {
            anchors.top: parent.top
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            text: label
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }

        Row {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            Repeater {
                model: sw
                Rectangle {
                    width: 14; height: 14; radius: 7
                    color: modelData
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.18)
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true

            onEntered: {
                parent.color = Theme.alpha(Theme.accent, 0.08)
                parent.border.color = Theme.accent
                page.previewTheme(parent.key)
            }

            onExited: {
                parent.color = "#00000000"
                parent.border.color = Theme.border
                page.previewTheme("")
            }

            onClicked: { page.previewTheme(""); page.runTheme(command) }
        }
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: page.marginLeft
        anchors.rightMargin: page.marginRight
        anchors.topMargin: page.marginTop
        anchors.bottomMargin: page.marginBottom
        contentWidth: width
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            id: scrollBar

            background: Rectangle {
                color: Theme.alpha(Theme.border, 0.3)
                radius: width / 2
            }

            contentItem: Rectangle {
                color: Theme.accent
                radius: width / 2
            }
        }

        Column {
            id: content
            width: flick.width
            spacing: 14

            Text {
                text: "Themes"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 19
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            Column {
                width: parent.width
                spacing: page.sectionSpacing

                Row {
                    width: parent.width
                    spacing: page.sectionSpacing

                    ToggleButton {
                        width: (parent.width - parent.spacing) / 2
                        label: "Color generation"
                        checked: page.colorGen
                        onToggled: page.setColorGen(!page.colorGen)
                    }

                    ToggleButton {
                        width: (parent.width - parent.spacing) / 2
                        label: "Mode"
                        checked: true
                        valueText: page.darkMode ? "Dark" : "Light"
                        onToggled: page.toggleMode()
                    }
                }

                Grid {
                    width: parent.width
                    columns: 3
                    spacing: page.sectionSpacing

                    ThemeButton {
                        label: "Default"
                        command: "default"
                    }
                    ThemeButton {
                        label: "White"
                        command: "preset white"
                    }
                    ThemeButton {
                        label: "Metal"
                        command: "preset metal"
                    }
                    ThemeButton {
                        label: "Slate"
                        command: "preset slate"
                    }
                    ThemeButton {
                        label: "Light Gray"
                        command: "preset light-gray"
                    }
                    ThemeButton {
                        label: "Beige"
                        command: "preset beige"
                    }
                    ThemeButton {
                        label: "Silver"
                        command: "preset silver"
                    }
                    ThemeButton {
                        label: "Gold"
                        command: "preset gold"
                    }
                    ThemeButton {
                        label: "Nord"
                        command: "preset nord"
                    }
                    ThemeButton {
                        label: "Tokyo Night"
                        command: "preset tokyo-night"
                    }
                    ThemeButton {
                        label: "Catppuccin Mocha"
                        command: "preset catppuccin-mocha"
                    }
                    ThemeButton {
                        label: "Everforest Dark"
                        command: "preset everforest-dark"
                    }
                    ThemeButton {
                        label: "Dracula"
                        command: "preset dracula"
                    }
                    ThemeButton {
                        label: "One Dark"
                        command: "preset one-dark"
                    }
                    ThemeButton {
                        label: "Kanagawa"
                        command: "preset kanagawa"
                    }
                    ThemeButton {
                        label: "Rose Pine"
                        command: "preset rose-pine"
                    }
                    ThemeButton {
                        label: "Red"
                        command: "preset red"
                    }
                    ThemeButton {
                        label: "Matrix"
                        command: "preset matrix"
                    }
                }
            }

            Text {
                text: "FONT  (hover to preview, click to apply)"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: 12
            }

            Grid {
                width: parent.width
                columns: 2
                spacing: page.sectionSpacing

                FontButton { label: "JetBrains Mono"; family: "JetBrainsMono Nerd Font" }
                FontButton { label: "Fira Code";       family: "FiraCode Nerd Font" }
                FontButton { label: "Cascadia";        family: "CaskaydiaCove Nerd Font" }
                FontButton { label: "Geist Mono";      family: "GeistMono Nerd Font" }
                FontButton { label: "Victor Mono";     family: "VictorMono Nerd Font" }
                FontButton { label: "Monaspace Neon";  family: "MonaspiceNe Nerd Font" }
                FontButton { label: "Iosevka";         family: "Iosevka Nerd Font" }
                FontButton { label: "Hack";            family: "Hack" }
            }

            Column {
                width: parent.width
                spacing: page.sectionSpacing

                ConfigButton {
                    label: "Theme"
                    path: "~/.config/quickshell/Theme.qml"
                }
            }
        }
    }
}