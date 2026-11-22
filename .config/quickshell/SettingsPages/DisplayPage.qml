// DisplayPage.qml — brightness, night light, and per-monitor scale / resolution / refresh.
// Same look as System and Audio: mono labels, thin bars, plain-text options.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../"

Item {
    id: page
    readonly property int rightMargin: 46
    readonly property string mono: "JetBrainsMono Nerd Font"
    // set by SettingsWindow: true only while Settings is open
    property bool live: true

    property var monitors: []
    property var savedState: ({})
    readonly property string stateDir: Quickshell.env("HOME") + "/.config/quickshell/state"
    readonly property var activeMonitors: monitors.filter(m => !m.disabled)

    // ---------- brightness ----------
    property real brightness: 0
    property bool brightDragging: false
    Process {
        id: brightnessGet
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",")
                const pct = parseInt(parts[3])
                if (!isNaN(pct) && !page.brightDragging) page.brightness = pct / 100
            }
        }
    }
    // follow brightness keys while the page is open
    Timer { interval: 1500; repeat: true; running: page.live && !page.brightDragging; onTriggered: brightnessGet.running = true }
    // apply while dragging, at most ~25x/s
    property real brightPending: -1
    Timer {
        id: brightApply; interval: 40
        onTriggered: if (page.brightPending >= 0) {
            Quickshell.execDetached(["brightnessctl", "-q", "set", Math.max(1, Math.round(page.brightPending * 100)) + "%"])
            page.brightPending = -1
        }
    }
    function setBrightness(v) {
        brightness = v
        brightPending = v
        if (!brightApply.running) brightApply.start()
    }

    // ---------- night light (shared with the bar's moon: NightState -> hypr/bin/night) ----------
    readonly property bool nightOn: NightState.on
    readonly property real nightValue: Math.max(0, Math.min(1, (NightState.temp - 1500) / 5000))
    property real nightPending: -1
    Timer {
        id: nightApply; interval: 60
        onTriggered: if (page.nightPending >= 0) {
            NightState.set(Math.round((1500 + page.nightPending * 5000) / 50) * 50)
            page.nightPending = -1
        }
    }
    function setNight(v) {
        nightPending = v
        if (!nightApply.running) nightApply.start()
    }

    Process {
        id: stateDirProcess
        command: ["mkdir", "-p", page.stateDir]
    }

    FileView {
        id: displayFile
        path: page.stateDir + "/display.json"
        blockLoading: true
    }

    FileView {
        id: displayLua
        path: page.stateDir + "/display.lua"
    }

    function loadState() {
        try {
            const saved = JSON.parse(displayFile.text())
            if (saved && typeof saved.monitors === "object" && saved.monitors !== null) {
                savedState = saved.monitors
            }
        } catch (error) {}
    }

    function luaFileText() {
        const lines = []
        const names = Object.keys(savedState)
        for (let i = 0; i < names.length; i++) {
            const entry = savedState[names[i]]
            if (!entry) continue
            if (entry.disabled === true) {
                lines.push(monitorLua({ name: names[i] }, { disabled: true }))
                continue
            }
            if (typeof entry.mode !== "string") continue
            lines.push(monitorLua({ name: names[i] }, {
                mode: entry.mode,
                position: typeof entry.position === "string" ? entry.position : "auto",
                scale: typeof entry.scale === "number" ? entry.scale : 1
            }))
        }
        return lines.join("\n") + "\n"
    }

    Timer {
        id: stateSaveTimer
        interval: 300
        onTriggered: {
            try {
                displayFile.setText(JSON.stringify({ monitors: page.savedState }, null, 2))
                displayLua.setText(page.luaFileText())
            } catch (error) {}
        }
    }

    function monitorPosition(mon) {
        return page.activeMonitors.length <= 1 ? "auto" : mon.x + "x" + mon.y
    }

    function rememberMonitor(mon, fields) {
        if (!mon || !mon.name) return
        const next = Object.assign({}, savedState)
        next[mon.name] = Object.assign({}, next[mon.name] || {}, fields)
        savedState = next
        stateSaveTimer.restart()
    }

    Process {
        id: pReset
        onExited: exitCode => {
            refreshTimer.restart()
        }
    }

    function resetToConfig() {
        stateSaveTimer.stop()
        savedState = ({})
        pReset.command = [
            "sh", "-c",
            "rm -f '" + page.stateDir + "/display.json' '" + page.stateDir + "/display.lua'; hyprctl reload"
        ]
        pReset.running = true
    }

    function monitorMode(mon) { return mon.width + "x" + mon.height + "@" + mon.refreshRate.toFixed(2) }

    function luaString(value) { return String(value).replace(/\\/g, "\\\\").replace(/"/g, "\\\"") }

    function monitorLua(mon, options = {}) {
        const values = ["output = \"" + luaString(mon.name) + "\""]
        if (options.mode !== undefined) values.push("mode = \"" + luaString(options.mode) + "\"")
        if (options.position !== undefined) values.push("position = \"" + luaString(options.position) + "\"")
        if (options.scale !== undefined) values.push("scale = " + options.scale)
        if (options.disabled !== undefined) values.push("disabled = " + options.disabled)
        if (options.mirrorOf !== undefined) values.push("mirrorOf = \"" + luaString(options.mirrorOf) + "\"")
        return "hl.monitor({" + values.join(",") + "})"
    }

    function isMain(mon) {
        return !mon.disabled && page.activeMonitors.length > 0 && mon.x === 0 && mon.y === 0
    }

    Process {
        id: pShell
        onExited: exitCode => {
            refreshTimer.restart()
        }
    }

    function layoutCommands(ordered) {
        const cmds = []
        let x = 0
        for (let i = 0; i < ordered.length; i++) {
            const m = ordered[i]
            const mode = monitorMode(m)
            const pos = x + "x0"
            rememberMonitor(m, { mode: mode, scale: m.scale, position: pos, disabled: false })
            cmds.push("hyprctl eval '" + monitorLua(m, { mode: mode, position: pos, scale: m.scale }) + "'")
            x += Math.round(m.width / m.scale)
        }
        if (ordered.length > 0) cmds.push("hyprctl dispatch focusmonitor '" + ordered[0].name + "'")
        return cmds
    }

    function setMainMonitor(main) {
        if (!main || !main.name || main.disabled) return
        const others = page.activeMonitors.filter(m => m.name !== main.name).sort((a, b) => a.x - b.x)
        const cmds = layoutCommands([main].concat(others))
        pShell.command = ["sh", "-c", cmds.join("; ")]
        pShell.running = true
    }

    function setMonitorEnabled(mon, enabled) {
        if (!mon || !mon.name) return
        let cmds = []
        if (enabled) {
            const entry = savedState[mon.name] || {}
            const mode = typeof entry.mode === "string" ? entry.mode : "preferred"
            const scale = typeof entry.scale === "number" ? entry.scale : 1
            rememberMonitor(mon, { mode: mode, scale: scale, position: "auto", disabled: false })
            cmds.push("hyprctl eval '" + monitorLua(mon, { mode: mode, position: "auto", scale: scale }) + "'")
        } else {
            if (page.activeMonitors.length <= 1) return
            const wasMain = isMain(mon)
            rememberMonitor(mon, { mode: monitorMode(mon), scale: mon.scale, disabled: true })
            cmds.push("hyprctl eval '" + monitorLua(mon, { disabled: true }) + "'")
            if (wasMain) {
                const rest = page.activeMonitors.filter(m => m.name !== mon.name).sort((a, b) => a.x - b.x)
                cmds = cmds.concat(layoutCommands(rest))
            }
        }
        pShell.command = ["sh", "-c", cmds.join("; ")]
        pShell.running = true
    }

    Process {
        id: pList
        command: ["hyprctl", "monitors", "all", "-j"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.monitors = JSON.parse(text)
                } catch (error) {
                    page.monitors = []
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
    }

    function refresh() {
        pList.running = true
    }

    Process {
        id: pApply
        property var pendingMon: null

        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                if (out.length === 0) return

                const match = out.match(/using suggested scale:\s*([\d.]+)/i)
                if (match && pApply.pendingMon) {
                    const suggested = parseFloat(match[1])
                    page.setScale(pApply.pendingMon, suggested, true)
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
        onExited: exitCode => {
            refreshTimer.restart()
        }
    }

    function gcd(a, b) { while (b) { [a, b] = [b, a % b] }; return a }

    function validScale(mon, requested) {
        const width = mon.width
        const height = mon.height
        let best = requested
        let bestDistance = Infinity

        for (let i = 84; i <= 1560; i++) {
            const scale = i / 120
            if (scale < 0.7 || scale > 1.3) continue

            const logicalWidth = width / scale
            const logicalHeight = height / scale

            if (Math.abs(logicalWidth - Math.round(logicalWidth)) < 0.0001 &&
                Math.abs(logicalHeight - Math.round(logicalHeight)) < 0.0001) {
                const distance = Math.abs(scale - requested)
                if (distance < bestDistance) {
                    best = scale
                    bestDistance = distance
                }
            }
        }

        return best
    }

    function setScale(mon, scale, isRetry = false) {
        const requested = scale
        const applied = isRetry ? scale : validScale(mon, requested)

        const idx = page.monitors.findIndex(m => m.name === mon.name)
        if (idx !== -1) {
            const updated = page.monitors.slice()
            updated[idx] = Object.assign({}, updated[idx], { scale: applied })
            page.monitors = updated
        }

        rememberMonitor(mon, { mode: monitorMode(mon), scale: applied, position: monitorPosition(mon) })

        pApply.pendingMon = mon
        pApply.command = [
            "hyprctl", "eval",
            monitorLua(mon, { mode: monitorMode(mon), position: mon.x + "x" + mon.y, scale: applied })
        ]
        pApply.running = true
    }

    Process {
        id: pResolution
        stdout: StdioCollector {
            onStreamFinished: {}
        }
        stderr: StdioCollector {
            onStreamFinished: {}
        }
        onExited: exitCode => {
            refreshTimer.restart()
        }
    }

    function resolutionList(mon) {
        if (!mon || !mon.availableModes) return []
        const seen = {}
        const items = []
        for (let i = 0; i < mon.availableModes.length; i++) {
            const match = String(mon.availableModes[i]).match(/^(\d+)x(\d+)@/)
            if (!match) continue
            const key = match[1] + "x" + match[2]
            if (seen[key]) continue
            seen[key] = true
            items.push({ key: key, width: parseInt(match[1]), height: parseInt(match[2]) })
        }
        items.sort((a, b) => (b.width * b.height - a.width * a.height) || (b.width - a.width))
        return items.slice(0, 6).map(item => item.key)
    }

    function bestMode(mon, resolution) {
        if (!mon || !mon.availableModes) return null
        const prefix = resolution + "@"
        let bestRate = null
        let bestDistance = Infinity
        for (let i = 0; i < mon.availableModes.length; i++) {
            const mode = String(mon.availableModes[i])
            if (mode.indexOf(prefix) !== 0) continue
            const rate = parseFloat(mode.substring(prefix.length))
            if (isNaN(rate)) continue
            const distance = Math.abs(rate - mon.refreshRate)
            if (distance < bestDistance || (distance === bestDistance && rate > bestRate)) {
                bestRate = rate
                bestDistance = distance
            }
        }
        return bestRate === null ? null : prefix + bestRate.toFixed(2)
    }

    function setResolution(mon, resolution) {
        if (!mon || !mon.name || !resolution) {
            return
        }
        const scale = mon.scale !== undefined ? mon.scale : 1
        rememberMonitor(mon, { mode: resolution, scale: scale, position: monitorPosition(mon) })
        const lua = monitorLua(mon, {
            mode: resolution,
            position: mon.x + "x" + mon.y,
            scale: scale
        })
        try {
            pResolution.command = ["hyprctl", "eval", lua]
            pResolution.running = true
        } catch (error) {}
    }

    function refreshRates(mon) {
        if (!mon || !mon.availableModes) return []
        const prefix = mon.width + "x" + mon.height + "@"
        const seen = {}
        const rates = []
        for (let i = 0; i < mon.availableModes.length; i++) {
            const mode = String(mon.availableModes[i])
            if (mode.indexOf(prefix) !== 0) continue
            const match = mode.match(/@([\d.]+)/)
            if (!match) continue
            const rate = parseFloat(match[1])
            if (isNaN(rate)) continue
            const key = rate.toFixed(2)
            if (seen[key]) continue
            seen[key] = true
            rates.push(rate)
        }
        rates.sort((a, b) => b - a)
        return rates
    }

    function setRefreshRate(mon, rate) {
        if (!mon || !mon.name || rate === undefined) {
            return
        }
        const mode = mon.width + "x" + mon.height + "@" + rate.toFixed(2)
        const scale = mon.scale !== undefined ? mon.scale : 1
        rememberMonitor(mon, { mode: mode, scale: scale, position: monitorPosition(mon) })
        const lua = monitorLua(mon, {
            mode: mode,
            position: mon.x + "x" + mon.y,
            scale: scale
        })
        try {
            pResolution.command = ["hyprctl", "eval", lua]
            pResolution.running = true
        } catch (error) {}
    }


    function monLabel(m) {
        if (/^(eDP|LVDS|DSI)/.test(m.name)) return "built-in"
        const model = /^0x[0-9a-f]+$/i.test(m.model || "") ? "" : (m.model || "")
        return ((m.make || "") + " " + model).trim()
    }

    // scales that give a whole-pixel logical size (what Hyprland accepts), in a sane range
    function scaleOptions(mon) {
        const out = []
        for (let i = 84; i <= 240; i++) {
            const s = i / 120, lw = mon.width / s, lh = mon.height / s
            if (Math.abs(lw - Math.round(lw)) > 1e-4 || Math.abs(lh - Math.round(lh)) > 1e-4) continue
            if (lw < 1000 && s !== 1) continue
            const two = Math.round(s * 100) / 100
            if (Math.abs(s - two) > 1e-6 && [4/3, 5/3].every(k => Math.abs(s - k) > 1e-6)) continue
            out.push(s)
        }
        if (!out.some(s => Math.abs(s - mon.scale) < 0.004)) out.push(mon.scale)
        return out.sort((a, b) => a - b)
    }

    Timer { id: refreshTimer; interval: 250; onTriggered: page.refresh() }
    // pick up monitors being plugged in / out
    Connections {
        target: Hyprland
        function onRawEvent(ev) { if (ev.name.indexOf("monitor") === 0) refreshTimer.restart() }
    }
    onLiveChanged: if (live) { refreshTimer.restart(); brightnessGet.running = true; NightState.refresh() }

    Process { id: pEditConfig; command: ["sh", "-c", "xdg-open ~/.config/hypr/monitors.lua || xed ~/.config/hypr/monitors.lua"] }

    // ---------- pieces ----------
    // thin bar: click / drag to set, scroll ±5%; knob on hover
    component Bar: Item {
        id: bk
        property real value: 0
        property bool dim: false
        signal picked(real v)
        signal released()
        readonly property bool hot: ma.containsMouse || ma.pressed
        readonly property alias pressed: ma.pressed
        height: 18
        function at(x) { return Math.max(0, Math.min(1, x / width)) }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: bk.hot ? 6 : 4; radius: height / 2
            color: Theme.alpha(Theme.textFaint, 0.18)
            Behavior on height { NumberAnimation { duration: 120 } }
            Rectangle {
                width: Math.max(height, parent.width * Math.min(1, bk.value)); height: parent.height; radius: parent.radius
                color: bk.dim ? Theme.alpha(Theme.textFaint, 0.55) : Theme.accent
                Behavior on width { enabled: !ma.pressed; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
        Rectangle {
            width: 12; height: 12; radius: 6
            anchors.verticalCenter: parent.verticalCenter
            x: Math.round(bk.width * Math.min(1, bk.value) - width / 2)
            color: bk.dim ? Theme.textFaint : Theme.text
            opacity: bk.hot ? 1 : 0
            scale: ma.pressed ? 1.15 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 100 } }
        }
        MouseArea {
            id: ma
            anchors.fill: parent; anchors.topMargin: -4; anchors.bottomMargin: -4
            hoverEnabled: true; preventStealing: true
            cursorShape: Qt.PointingHandCursor
            onPressed: m => bk.picked(bk.at(m.x))
            onPositionChanged: m => { if (pressed) bk.picked(bk.at(m.x)) }
            onReleased: bk.released()
        }
        WheelHandler { onWheel: e => bk.picked(Math.max(0, Math.min(1, bk.value + (e.angleDelta.y > 0 ? 0.05 : -0.05)))) }
    }

    // small text action:  mute / set main / disable …
    component Act: Text {
        id: act
        property bool lit: false
        signal clicked()
        color: lit ? Theme.accent : am.containsMouse ? Theme.text : Theme.textFaint
        font.family: page.mono; font.pixelSize: 11; font.underline: am.containsMouse
        MouseArea { id: am; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.clicked() }
    }

    // a row of plain-text choices; the current one is accent + dot
    component Choices: Item {
        id: ch
        property string label: ""
        property var options: []          // [{ text, key, current }]
        signal chosen(var key)
        width: parent.width
        height: flow.implicitHeight
        Text { id: cl; width: 84; text: ch.label; color: Theme.textDim; font.family: page.mono; font.pixelSize: 12 }
        Flow {
            id: flow
            anchors { left: cl.right; right: parent.right }
            spacing: 18
            Repeater {
                model: ch.options
                Text {
                    id: opt
                    required property var modelData
                    text: (modelData.current ? "● " : "") + modelData.text
                    color: modelData.current ? Theme.accent : om.containsMouse ? Theme.text : Theme.textFaint
                    font.family: page.mono; font.pixelSize: 12
                    MouseArea { id: om; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true
                                cursorShape: opt.modelData.current ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: if (!opt.modelData.current) ch.chosen(opt.modelData.key) }
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

            Text { text: "Display"; color: Theme.text; font.family: Theme.fontFamily; font.pixelSize: 19 }
            Rectangle { width: parent.width; height: 1; color: Theme.border }
            Item { width: 1; height: 2 }

            // brightness
            Item {
                width: parent.width; height: 20
                Text { id: bl; width: 84; anchors.verticalCenter: parent.verticalCenter; text: "brightness"; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
                Bar {
                    id: brBar
                    anchors { left: bl.right; right: bp.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    value: page.brightness
                    onPicked: v => { page.brightDragging = brBar.pressed; page.setBrightness(Math.max(0.01, v)) }
                    onReleased: page.brightDragging = false
                }
                Text { id: bp; anchors { right: parent.right; rightMargin: 58; verticalCenter: parent.verticalCenter }
                       width: 40; horizontalAlignment: Text.AlignRight
                       text: Math.round(page.brightness * 100) + "%"; color: Theme.text; font.family: page.mono; font.pixelSize: 12 }
            }

            // night light: slider = colour temperature (left = warmer)
            Item {
                width: parent.width; height: 20
                Text { id: nl; width: 84; anchors.verticalCenter: parent.verticalCenter; text: "night light"; color: Theme.accent; font.family: page.mono; font.pixelSize: 12 }
                Bar {
                    anchors { left: nl.right; right: np.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    value: page.nightValue
                    dim: !page.nightOn
                    onPicked: v => page.setNight(v)
                }
                Text { id: np; anchors { right: ntog.left; rightMargin: 14; verticalCenter: parent.verticalCenter }
                       width: 44; horizontalAlignment: Text.AlignRight
                       text: NightState.temp + "K"; color: page.nightOn ? Theme.text : Theme.textFaint; font.family: page.mono; font.pixelSize: 12 }
                Act { id: ntog; anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                      width: 44; horizontalAlignment: Text.AlignRight
                      text: page.nightOn ? "on" : "off"
                      lit: page.nightOn
                      onClicked: NightState.setOn(!page.nightOn) }
            }

            Item { width: 1; height: 4 }
            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }

            // monitors
            Repeater {
                model: page.monitors
                Column {
                    id: mon
                    required property var modelData
                    readonly property bool off: modelData.disabled === true
                    readonly property bool main: page.isMain(modelData)
                    width: content.width
                    spacing: 10
                    bottomPadding: 8

                    Item {
                        width: parent.width; height: 20
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12
                            Text { text: mon.modelData.name; color: mon.off ? Theme.textFaint : Theme.text; font.family: page.mono; font.pixelSize: 13; font.bold: true }
                            Text { visible: !mon.off; text: page.monLabel(mon.modelData); color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11; anchors.baseline: parent.children[0].baseline }
                            Text { visible: mon.off; text: "disabled"; color: Theme.textFaint; font.family: page.mono; font.pixelSize: 11; anchors.baseline: parent.children[0].baseline }
                            Text { visible: mon.main && page.activeMonitors.length > 1; text: "main"; color: Theme.accent; font.family: page.mono; font.pixelSize: 11; anchors.baseline: parent.children[0].baseline }
                        }
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 16
                            Act { visible: !mon.off && !mon.main && page.activeMonitors.length > 1; text: "set main"; onClicked: page.setMainMonitor(mon.modelData) }
                            Act { visible: mon.off || page.activeMonitors.length > 1; text: mon.off ? "enable" : "disable"; onClicked: page.setMonitorEnabled(mon.modelData, mon.off) }
                        }
                    }

                    Choices {
                        visible: !mon.off
                        label: "resolution"
                        options: page.resolutionList(mon.modelData).map(r => ({ text: r.replace("x", "×"), key: r, current: r === mon.modelData.width + "x" + mon.modelData.height }))
                        onChosen: key => { const m = page.bestMode(mon.modelData, key); if (m) page.setResolution(mon.modelData, m) }
                    }
                    Choices {
                        visible: !mon.off
                        label: "refresh"
                        options: page.refreshRates(mon.modelData).map(r => ({ text: (Math.abs(r - Math.round(r)) < 0.05 ? Math.round(r) : r.toFixed(2)) + " Hz", key: r, current: Math.abs(r - mon.modelData.refreshRate) < 0.05 }))
                        onChosen: key => page.setRefreshRate(mon.modelData, key)
                    }
                    Choices {
                        visible: !mon.off
                        label: "scale"
                        options: page.scaleOptions(mon.modelData).map(s => ({ text: s.toFixed(2), key: s, current: Math.abs(s - mon.modelData.scale) < 0.004 }))
                        onChosen: key => page.setScale(mon.modelData, key, true)
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.border; opacity: 0.6 }
            Row {
                spacing: 22
                Act { text: "reset to config"; onClicked: page.resetToConfig() }
                Act { text: "edit monitors.lua"; onClicked: if (!pEditConfig.running) pEditConfig.running = true }
            }
        }
    }

    Component.onCompleted: {
        stateDirProcess.running = true
        loadState()
        brightnessGet.running = true
        NightState.refresh()
    }
}
