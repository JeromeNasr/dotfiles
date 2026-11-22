// AudioPage.qml — output / input device + volume, and per-app volume.
// Same look as the System page: mono labels, block-segment bars, no boxes.
// Bars: click or drag to set, scroll for ±5%.
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../"

Item {
    id: page
    readonly property int rightMargin: 46
    readonly property string mono: "JetBrainsMono Nerd Font"
    // set by SettingsWindow; port availability is only re-checked while Settings is open
    property bool live: true

    PwObjectTracker { objects: Pipewire.nodes.values }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var nodes: Pipewire.nodes.values
    readonly property var outputs: nodes.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var inputs: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
    // apps playing sound (Quickshell reports playback streams with isSink == true)
    readonly property var appStreams: nodes.filter(n => n.audio && n.isStream && n.isSink)

    // node names whose active port is "not available" (HDMI with nothing plugged in, …)
    property var unplugged: ({})
    property bool showUnplugged: false

    function shortName(n) { return n ? (n.nickname || n.description || n.name || "unknown") : "unknown" }
    function appName(n) { const p = n.properties || {}; return p["application.name"] || n.description || n.name || "unknown" }
    function appDetail(n) { const m = (n.properties || {})["media.name"] || ""; return m !== appName(n) ? m : "" }
    function setVol(n, v) { if (n?.audio) { n.audio.muted = false; n.audio.volume = Math.max(0, Math.min(1, v)) } }
    function toggleMute(n) { if (n?.audio) n.audio.muted = !n.audio.muted }

    Process {
        id: portCheck
        command: ["sh", "-c", "pactl -f json list sinks 2>/dev/null; echo; pactl -f json list sources 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {}
                for (const chunk of text.split("\n")) {
                    if (!chunk.trim().startsWith("[")) continue
                    try {
                        for (const d of JSON.parse(chunk)) {
                            const port = (d.ports || []).find(p => p.name === d.active_port)
                            if (port && port.availability === "not available") out[d.name] = true
                        }
                    } catch (e) {}
                }
                page.unplugged = out
            }
        }
    }
    // re-check when devices come and go (HDMI, headphones, bluetooth)
    onNodesChanged: if (live) recheck.restart()
    onLiveChanged: if (live) recheck.restart()
    Timer { id: recheck; interval: 300; onTriggered: portCheck.running = true }
    Component.onCompleted: portCheck.running = true

    // ---------- pieces ----------
    // block-segment volume bar; hovering previews where a click would land
    component Blocks: Item {
        id: bk
        property real value: 0
        property bool dim: false
        signal picked(real v)
        readonly property int segs: Math.max(8, Math.floor((width + 2) / 8))
        readonly property int lit: Math.round(Math.min(1, value) * segs)
        readonly property int hoverAt: ma.containsMouse ? Math.ceil(ma.mouseX / width * segs) : -1
        height: 18

        function at(x) { return Math.max(0, Math.min(1, Math.ceil(x / width * segs) / segs)) }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: bk.segs
                Rectangle {
                    required property int index
                    width: 6; height: 12
                    antialiasing: false
                    color: index < bk.lit ? (bk.dim ? Theme.alpha(Theme.textFaint, 0.55) : Theme.accent)
                         : index < bk.hoverAt ? Theme.alpha(Theme.accent, 0.35)
                         : Theme.alpha(Theme.textFaint, 0.18)
                }
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: m => bk.picked(bk.at(m.x))
            onPositionChanged: m => { if (pressed) bk.picked(bk.at(m.x)) }
        }
        WheelHandler { onWheel: e => bk.picked(Math.max(0, Math.min(1, bk.value + (e.angleDelta.y > 0 ? 0.05 : -0.05)))) }
    }

    // label · bar · % · mute
    component VolLine: Item {
        id: vl
        property var node: null
        property string label: ""
        property string sub: ""
        property int labelWidth: 84
        readonly property bool muted: node?.audio?.muted ?? false
        readonly property real vol: node?.audio?.volume ?? 0
        width: parent.width
        height: sub !== "" ? 32 : 20

        Column {
            id: lab
            anchors.verticalCenter: parent.verticalCenter
            width: vl.labelWidth
            Text { width: parent.width - 8; text: vl.label; elide: Text.ElideRight; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
            Text { width: parent.width - 8; visible: vl.sub !== ""; text: vl.sub; elide: Text.ElideRight; color: Theme.textFaint; font.family: page.mono; font.pixelSize: 10 }
        }
        Blocks {
            anchors { left: lab.right; right: pctText.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            value: vl.vol
            dim: vl.muted
            enabled: !!vl.node?.audio
            onPicked: v => page.setVol(vl.node, v)
        }
        Text {
            id: pctText
            anchors { right: muteText.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
            width: 40; horizontalAlignment: Text.AlignRight
            text: vl.node ? Math.round(vl.vol * 100) + "%" : "—"
            color: vl.muted ? Theme.textFaint : Theme.text; font.family: page.mono; font.pixelSize: 12
        }
        Text {
            id: muteText
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: 44; horizontalAlignment: Text.AlignRight
            text: vl.muted ? "muted" : "mute"
            color: vl.muted ? Theme.danger : mma.containsMouse ? Theme.text : Theme.textFaint
            font.family: page.mono; font.pixelSize: 11; font.underline: mma.containsMouse
            MouseArea { id: mma; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.toggleMute(vl.node) }
        }
    }

    // device picker:  ● Headphones / ○ Digital Microphone / + 3 unplugged
    component Devices: Column {
        id: dv
        property var devices: []
        property var current: null
        property bool isOutput: true
        readonly property var hidden: devices.filter(d => page.unplugged[d.name] && d.id !== current?.id)
        readonly property var shown: devices.filter(d => !page.unplugged[d.name] || d.id === current?.id)
                                            .concat(page.showUnplugged ? hidden : [])
        x: 84
        width: parent.width - 84
        spacing: 3

        Repeater {
            model: dv.shown
            Text {
                id: row
                required property var modelData
                readonly property bool active: dv.current?.id === modelData.id
                readonly property bool gone: !!page.unplugged[modelData.name]
                text: (active ? "● " : "○ ") + page.shortName(modelData) + (gone ? "  (unplugged)" : "")
                color: active ? Theme.text : hov.containsMouse ? Theme.textDim : Theme.textFaint
                font.family: page.mono; font.pixelSize: 12
                MouseArea {
                    id: hov
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: row.active ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: if (!row.active) {
                        if (dv.isOutput) Pipewire.preferredDefaultAudioSink = row.modelData
                        else Pipewire.preferredDefaultAudioSource = row.modelData
                    }
                }
            }
        }
        Text {
            visible: dv.devices.length === 0
            text: dv.isOutput ? "no outputs" : "no inputs"
            color: Theme.textFaint; font.family: page.mono; font.pixelSize: 12
        }
        Text {
            visible: dv.hidden.length > 0
            text: (page.showUnplugged ? "- hide " : "+ ") + dv.hidden.length + " unplugged"
            color: fma.containsMouse ? Theme.textDim : Theme.textFaint
            font.family: page.mono; font.pixelSize: 11; topPadding: 2
            MouseArea { id: fma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: page.showUnplugged = !page.showUnplugged }
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

            Text { text: "Audio"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19 }
            Rectangle { width: parent.width; height: 1; color: Theme.border }

            Item { width: 1; height: 2 }
            VolLine { node: page.sink; label: "output" }
            Devices { devices: page.outputs; current: page.sink; isOutput: true }

            Item { width: 1; height: 6 }
            VolLine { node: page.source; label: "input" }
            Devices { devices: page.inputs; current: page.source; isOutput: false }

            Item { width: 1; height: 4 }
            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            Text {
                text: "apps" + (page.appStreams.length ? "  " + page.appStreams.length : "")
                color: Theme.textDim; font.family: page.mono; font.pixelSize: 12
            }
            Column {
                width: parent.width
                spacing: 12
                Repeater {
                    model: page.appStreams
                    VolLine {
                        required property var modelData
                        node: modelData
                        label: page.appName(modelData)
                        sub: page.appDetail(modelData)
                        labelWidth: 150
                    }
                }
                Text {
                    visible: page.appStreams.length === 0
                    text: "nothing playing"
                    color: Theme.textFaint; font.family: page.mono; font.pixelSize: 12
                }
            }
        }
    }
}
