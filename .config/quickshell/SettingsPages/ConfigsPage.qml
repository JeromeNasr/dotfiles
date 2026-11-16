// .config/quickshell/SettingsPages/ConfigsPage.qml
import QtQuick
import QtQuick.Controls
import Quickshell
import "../"

Item {
    id: page
    property real marginLeft: 0
    property real marginRight: 55
    property real marginTop: 0
    property real marginBottom: 0
    property real sliderMarginRight: 10
    property real sectionSpacing: 6

    function editConfig(path) {
        Quickshell.execDetached([
            "xed",
            path.replace(/^~/, Quickshell.env("HOME"))
        ])
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
                text: "Configs"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 19
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            Text {
                text: "Hyprland"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }

            Column {
                width: parent.width
                spacing: page.sectionSpacing
                ConfigButton {
                    label: "Programs - autostart - input"
                    path: "~/.config/hypr/hyprland.lua"
                }
                ConfigButton {
                    label: "Monitors - workspaces"
                    path: "~/.config/hypr/monitors.lua"
                }
                ConfigButton {
                    label: "Look and feel"
                    path: "~/.config/hypr/look.lua"
                }
                ConfigButton {
                    label: "Keybinds"
                    path: "~/.config/hypr/keybinds.lua"
                }
                ConfigButton {
                    label: "Rules"
                    path: "~/.config/hypr/rules.lua"
                }
                ConfigButton {
                    label: "Lock screen"
                    path: "~/.config/hypr/hyprlock.conf"
                }
            }
            Text {
                text: "Rofi"
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: 16
            }
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.border
            }
            Column {
                width: parent.width
                spacing: page.sectionSpacing
                ConfigButton {
                    label: "Config"
                    path: "~/.config/rofi/config.rasi"
                }
            }
        }
    }
}