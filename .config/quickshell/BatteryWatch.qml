// BatteryWatch.qml — battery notifications, driven by UPower events (no polling).
//  · 20 %  low       (once per discharge)
//  · 10 %  critical  (once per discharge, urgent)
//  · full while plugged in (once per charge) — a good moment to unplug
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Scope {
    id: w
    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev && dev.isLaptopBattery
    readonly property int pct: present ? Math.round(dev.percentage * 100) : -1     // UPower percentage is 0..1
    readonly property bool discharging: present && dev.state === UPowerDeviceState.Discharging
    readonly property bool full: present && (dev.state === UPowerDeviceState.FullyCharged || (pct >= 100 && !discharging))

    property bool warnedLow: false
    property bool warnedCrit: false
    property bool warnedFull: true          // don't announce "full" for the state we booted into

    function notify(urgency, title, body) {
        Quickshell.execDetached(["notify-send", "-a", "Battery", "-u", urgency, "-i", "battery", title, body])
    }
    function check() {
        if (!present || pct < 0) return
        if (discharging) {
            warnedFull = false
            if (pct <= 10 && !warnedCrit) { warnedCrit = true; warnedLow = true
                notify("critical", "Battery critical: " + pct + "%", "Plug in now — the laptop will suspend soon.") }
            else if (pct <= 20 && !warnedLow) { warnedLow = true
                notify("normal", "Battery low: " + pct + "%", "Plug in when you can.") }
        } else {
            warnedLow = false; warnedCrit = false          // plugged in: re-arm for the next discharge
            if (full && !warnedFull) { warnedFull = true
                notify("low", "Battery fully charged", "You can unplug the charger.") }
        }
    }
    onPctChanged: check()
    onDischargingChanged: check()
    onFullChanged: check()
}
