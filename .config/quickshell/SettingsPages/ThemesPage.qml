// ThemesPage.qml — colour source, light/dark, presets and font.
// Same look as the other pages. Hover a preset or font to preview it live, click to apply.
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

    // ---------- theme state (43pr/bin/theme.py writes it) ----------
    property bool colorGen: true
    property bool darkMode: true
    property string preset: ""
    property string source: ""         // "wallpaper" | "preset" | …
    FileView {
        id: stateView
        path: (Quickshell.env("XDG_STATE_HOME") || (page.home + "/.local/state")) + "/43pr/state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const s = JSON.parse(text())
                page.colorGen = s.colorgen !== false
                page.darkMode = s.mode_appearance !== "light"
                page.preset = s.preset || ""
                page.source = s.mode || ""
            } catch (e) {}
        }
    }
    Timer { id: reloadTimer; interval: 700; onTriggered: stateView.reload() }

    function runTheme(args) {
        Quickshell.execDetached(["python3", page.home + "/.config/43pr/bin/theme.py"].concat(args))
        reloadTimer.restart()
    }
    function setColorGen(on) { colorGen = on; runTheme(["colorgen", on ? "on" : "off"]) }
    function setDark(on) { if (on !== darkMode) { darkMode = on; runTheme(["toggle"]) } }
    function applyPreset(key) { previewTheme(""); preset = key; runTheme(key === "default" ? ["default"] : ["preset", key]) }
    // which preset is "current": only meaningful when colours aren't coming from the wallpaper
    readonly property bool fromWallpaper: colorGen && source === "wallpaper"

    // ---------- live previews (built by ~/.local/bin/rice-theme-previews) ----------
    property var previews: ({})
    readonly property var presetKeys: Object.keys(previews).filter(k => k[0] !== "_").sort((a, b) => a === "default" ? -1 : b === "default" ? 1 : a.localeCompare(b))
    FileView {
        path: page.home + "/.cache/43pr/theme-previews.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { page.previews = JSON.parse(text()) } catch (e) {} }
    }
    Component.onCompleted: Quickshell.execDetached(["sh", "-c", "\"$HOME/.local/bin/rice-theme-previews\""])
    Component.onDestruction: { Theme.previewPalette = null; Theme.fontPreview = "" }

    Timer {
        id: previewTimer
        interval: 90                      // debounce so sweeping the mouse doesn't thrash
        property var pending: null
        onTriggered: Theme.previewPalette = pending
    }
    function previewTheme(key) { previewTimer.pending = key && previews[key] ? previews[key] : null; previewTimer.restart() }
    function pretty(key) { return key.replace(/-/g, " ") }

    // ---------- fonts ----------
    readonly property var fonts: [
        { t: "JetBrains Mono", f: "JetBrainsMono Nerd Font" },
        { t: "Fira Code",      f: "FiraCode Nerd Font" },
        { t: "Cascadia",       f: "CaskaydiaCove Nerd Font" },
        { t: "Geist Mono",     f: "GeistMono Nerd Font" },
        { t: "Victor Mono",    f: "VictorMono Nerd Font" },
        { t: "Monaspace Neon", f: "MonaspiceNe Nerd Font" },
        { t: "Iosevka",        f: "Iosevka Nerd Font" },
        { t: "Hack",           f: "Hack" }
    ]
    function setFont(family) {
        Theme.fontPreview = ""
        Quickshell.execDetached(["sh", "-c", "\"$HOME/.local/bin/rice-font\" set \"$1\"", "sh", family])
    }

    // editor: same choice as the Configs page
    FileView { id: editorFile; path: page.home + "/.config/quickshell/state/editor"; printErrors: false; blockLoading: true }
    function editThemeFile() {
        const ed = (editorFile.text() || "").trim() || "xed"
        const f = page.home + "/.config/quickshell/Theme.qml"
        Quickshell.execDetached(ed === "nvim" ? ["kitty", "-e", "nvim", f] : [ed, f])
    }

    // ---------- pieces ----------
    component Act: Text {
        id: act
        property bool lit: false
        signal clicked()
        color: lit ? Theme.accent : am.containsMouse ? Theme.text : Theme.textFaint
        font.family: page.mono; font.pixelSize: 11; font.underline: am.containsMouse
        MouseArea { id: am; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
    }
    // "label   ● a   b"
    component Pick: Item {
        id: pk
        property string label: ""
        property var options: []           // [{ t, on }]
        signal picked(int i)
        width: parent.width; height: 18
        Text { id: pl; width: 84; anchors.verticalCenter: parent.verticalCenter; text: pk.label; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
        Row {
            anchors { left: pl.right; verticalCenter: parent.verticalCenter }
            spacing: 22
            Repeater {
                model: pk.options
                Text {
                    id: o
                    required property var modelData
                    required property int index
                    text: (modelData.on ? "● " : "") + modelData.t
                    color: modelData.on ? Theme.accent : om.containsMouse ? Theme.text : Theme.textFaint
                    font.family: page.mono; font.pixelSize: 12
                    MouseArea { id: om; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pk.picked(o.index) }
                }
            }
        }
    }

    // ---------- layout ----------
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

            Text { text: "Themes"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19 }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Pick {
                label: "colours"
                options: [{ t: "from wallpaper", on: page.colorGen }, { t: "preset", on: !page.colorGen }]
                onPicked: i => page.setColorGen(i === 0)
            }
            Pick {
                label: "mode"
                options: [{ t: "dark", on: page.darkMode }, { t: "light", on: !page.darkMode }]
                onPicked: i => page.setDark(i === 0)
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            Item {
                width: parent.width; height: 16
                Text { text: "presets"; color: Theme.textDim; font.family: page.mono; font.pixelSize: 12 }
                Text { anchors.right: parent.right; text: "hover to preview, click to apply"; color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11 }
            }

            Grid {
                id: grid
                width: parent.width
                columns: 3
                columnSpacing: 18
                rowSpacing: 2
                Repeater {
                    model: page.presetKeys
                    Item {
                        id: pr
                        required property string modelData
                        readonly property bool cur: !page.fromWallpaper && page.preset === modelData
                        readonly property var sw: (page.previews[modelData] && page.previews[modelData]._swatch) || []
                        width: (grid.width - 2 * grid.columnSpacing) / 3; height: 28
                        Rectangle {
                            anchors.fill: parent; anchors.leftMargin: -6; anchors.rightMargin: -6
                            radius: 6; color: Theme.alpha(Theme.text, prm.containsMouse ? 0.05 : 0)
                        }
                        Row {
                            id: swr
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: pr.sw
                                Rectangle { required property var modelData; width: 9; height: 14; color: modelData }
                            }
                        }
                        Text {
                            anchors { left: swr.right; leftMargin: 10; right: parent.right; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: (pr.cur ? "● " : "") + page.pretty(pr.modelData)
                            color: pr.cur ? Theme.accent : prm.containsMouse ? Theme.text : Theme.textDim
                            font.family: page.mono; font.pixelSize: 12
                        }
                        MouseArea {
                            id: prm
                            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: page.previewTheme(containsMouse ? pr.modelData : "")
                            onClicked: page.applyPreset(pr.modelData)
                        }
                    }
                }
            }
            Text {
                visible: page.presetKeys.length === 0
                text: "building previews…"; color: Theme.textFaint; font.family: page.mono; font.pixelSize: 12
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            // fonts, each shown in itself
            Item {
                width: parent.width; height: fontFlow.height
                Text { id: fl; width: 84; text: "font"; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
                Flow {
                    id: fontFlow
                    anchors { left: fl.right; right: parent.right }
                    spacing: 22
                    Repeater {
                        model: page.fonts
                        Text {
                            id: fo
                            required property var modelData
                            readonly property bool cur: Theme.fontFamily === modelData.f
                            text: (cur ? "● " : "") + modelData.t
                            color: cur ? Theme.accent : fm.containsMouse ? Theme.text : Theme.textFaint
                            font.family: modelData.f; font.pixelSize: 13
                            MouseArea {
                                id: fm
                                anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onContainsMouseChanged: Theme.fontPreview = containsMouse ? fo.modelData.f : ""
                                onClicked: page.setFont(fo.modelData.f)
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }
            Act { text: "edit Theme.qml"; onClicked: page.editThemeFile() }
        }
    }
}
