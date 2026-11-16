// Reminders.qml — calendar reminders: storage, repeats, due-time notifications
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    // [{ id, title, note, date:"YYYY-MM-DD", time:"HH:MM"|"", repeat:"none|daily|weekly|monthly|yearly",
    //    lead:minutes, doneDates:["YYYY-MM-DD"], fired:["YYYY-MM-DD"] }]
    property var items: []
    property int rev: 0                          // bumps on every change so views re-evaluate
    property string lastSaved: ""

    readonly property string path: Quickshell.env("HOME") + "/.config/quickshell/state/reminders.json"

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function ymd(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    function parse(s) { var p = s.split("-"); return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2])) }
    function dayDiff(a, b) { return Math.round((parse(b) - parse(a)) / 86400000) }

    function save() {
        var t = JSON.stringify(items, null, 1)
        lastSaved = t
        file.setText(t)
        rev++
    }
    function uid() { return Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36) }

    function add(title, date, time, repeat, lead, note) {
        title = (title || "").trim()
        if (title === "") return false
        var a = items.slice()
        a.push({ id: uid(), title: title, note: note || "", date: date, time: time || "", repeat: repeat || "none",
                 lead: lead || 0, doneDates: [], fired: [] })
        items = a; save(); return true
    }
    function remove(id) { items = items.filter(function (i) { return i.id !== id }); save() }
    function toggleDone(id, day) {
        items = items.map(function (i) {
            if (i.id !== id) return i
            var d = i.doneDates.slice(), k = d.indexOf(day)
            if (k >= 0) d.splice(k, 1); else d.push(day)
            i.doneDates = d; return i
        })
        save()
    }
    function snooze(id, minutes) {            // one-off copy for later today
        var it = items.find(function (i) { return i.id === id }); if (!it) return
        var n = new Date(Date.now() + minutes * 60000)
        add(it.title, ymd(n), pad(n.getHours()) + ":" + pad(n.getMinutes()), "none", 0, it.note)
    }

    function occursOn(it, day) {                // day = "YYYY-MM-DD"
        if (day < it.date) return false
        var d = parse(day), b = parse(it.date)
        switch (it.repeat) {
        case "daily":   return true
        case "weekly":  return d.getDay() === b.getDay()
        case "monthly": return d.getDate() === b.getDate()
        case "yearly":  return d.getDate() === b.getDate() && d.getMonth() === b.getMonth()
        default:        return day === it.date
        }
    }
    // reminders on a day, sorted (all-day first, then by time)
    function forDay(day) {
        rev; var out = []
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (occursOn(it, day)) out.push({ id: it.id, title: it.title, note: it.note, time: it.time, repeat: it.repeat,
                                              lead: it.lead, day: day, done: it.doneDates.indexOf(day) >= 0 })
        }
        out.sort(function (x, y) { return x.time < y.time ? -1 : x.time > y.time ? 1 : 0 })
        return out
    }
    // summary used for the calendar dots: {n, open}
    function summary(day) {
        var l = forDay(day), open = 0
        for (var i = 0; i < l.length; i++) if (!l[i].done) open++
        return { n: l.length, open: open }
    }
    function upcoming(limit) {
        rev; var out = [], seen = {}, today = new Date(); today.setHours(0, 0, 0, 0)
        for (var k = 0; k < 60 && out.length < limit; k++) {
            var d = new Date(today.getFullYear(), today.getMonth(), today.getDate() + k), day = ymd(d)
            var l = forDay(day)
            for (var i = 0; i < l.length && out.length < limit; i++)
                if (!l[i].done && !seen[l[i].id]) { seen[l[i].id] = true; out.push(l[i]) }   // next occurrence only
        }
        return out
    }
    function isOverdue(r) {
        if (r.done) return false
        var now = new Date(), today = ymd(now)
        if (r.day < today) return true
        if (r.day > today || r.time === "") return false
        return r.time < pad(now.getHours()) + ":" + pad(now.getMinutes())
    }

    // ---- due-time notifications ----
    function check() {
        var now = new Date(), today = ymd(now), changed = false
        for (var i = 0; i < items.length; i++) {
            var it = items[i]
            if (!occursOn(it, today) || it.doneDates.indexOf(today) >= 0 || it.fired.indexOf(today) >= 0) continue
            var hm = it.time !== "" ? it.time : "09:00"
            var p = hm.split(":")
            var due = new Date(now.getFullYear(), now.getMonth(), now.getDate(), parseInt(p[0]), parseInt(p[1]))
            var when = due.getTime() - (it.lead || 0) * 60000
            if (now.getTime() >= when && now.getTime() - when < 12 * 3600000) {
                it.fired = it.fired.concat([today]); changed = true
                var lead = it.lead ? "in " + (it.lead >= 1440 ? "1 day" : it.lead >= 60 ? (it.lead / 60) + " h" : it.lead + " min") : "now"
                Quickshell.execDetached(["notify-send", "-a", "Reminder", "-u", "normal", "-i", "appointment-soon",
                    "  " + it.title, (it.time !== "" ? it.time + " · " : "") + lead + (it.note ? "\n" + it.note : "")])
            }
        }
        if (changed) save()
    }
    property Timer ticker: Timer { interval: 15000; running: true; repeat: true; onTriggered: root.check() }

    property FileView file: FileView {
        path: root.path
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) { root.items = []; root.rev++ } }
        onLoaded: {
            var t = text()
            if (t === root.lastSaved) return
            try { root.items = JSON.parse(t); root.lastSaved = t; root.rev++ } catch (e) { console.warn("Reminders: bad json " + e) }
            root.check()
        }
    }
}
