// shell.qml — the shell. Popups are built the first time they are opened (LazyLoader) and then
// kept; small always-loaded IpcHandler stubs keep every `qs ipc call …` working before that.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: shellRoot

    // always loaded: things that appear on their own
    VolumeOsd {}
    ScreenshotOsd {}
    Notifications {}
    Bar {}
    Keyboard {}
    BatteryWatch {}

    function load(l) { l.active = true; return l.item }
    // each loader below is unloaded again after its popup has been closed for a while
    // (10 min; the wallpaper picker, which holds its thumbnails, after 2 min)

    LazyLoader { id: settingsL; SettingsWindow {} }
    Timer { running: settingsL.active && !!settingsL.item && !(settingsL.item.surfaceOpen ?? settingsL.item.showing); interval: 600000; onTriggered: settingsL.active = false }
    IpcHandler {
        target: "settings"
        function toggle(): void { shellRoot.load(settingsL).ipc.toggle() }
        function show(): void { shellRoot.load(settingsL).ipc.show() }
        function hide(): void { shellRoot.load(settingsL).ipc.hide() }
        function page(name: string): void { shellRoot.load(settingsL).ipc.page(name) }
        function sound(): void { shellRoot.load(settingsL).ipc.sound() }
        function display(): void { shellRoot.load(settingsL).ipc.display() }
        function network(): void { shellRoot.load(settingsL).ipc.network() }
        function snapTop(): void { shellRoot.load(settingsL).ipc.snapTop() }
        function snapCenter(): void { shellRoot.load(settingsL).ipc.snapCenter() }
        function snapBottom(): void { shellRoot.load(settingsL).ipc.snapBottom() }
        function snapLeft(): void { shellRoot.load(settingsL).ipc.snapLeft() }
        function snapRight(): void { shellRoot.load(settingsL).ipc.snapRight() }
    }

    LazyLoader { id: todoL; Todo {} }
    Timer { running: todoL.active && !!todoL.item && !(todoL.item.surfaceOpen ?? todoL.item.showing); interval: 600000; onTriggered: todoL.active = false }
    IpcHandler {
        target: "todo"
        function toggle(): void { shellRoot.load(todoL).ipc.toggle() }
        function show(): void { shellRoot.load(todoL).ipc.show() }
        function hide(): void { shellRoot.load(todoL).ipc.hide() }
    }

    LazyLoader { id: calendarL; Calendar {} }
    Timer { running: calendarL.active && !!calendarL.item && !(calendarL.item.surfaceOpen ?? calendarL.item.showing); interval: 600000; onTriggered: calendarL.active = false }
    IpcHandler {
        target: "calendar"
        function toggle(): void { shellRoot.load(calendarL).ipc.toggle() }
        function show(): void { shellRoot.load(calendarL).ipc.show() }
        function hide(): void { shellRoot.load(calendarL).ipc.hide() }
    }

    LazyLoader { id: projectL; ProjectMenu {} }
    Timer { running: projectL.active && !!projectL.item && !(projectL.item.surfaceOpen ?? projectL.item.showing); interval: 600000; onTriggered: projectL.active = false }
    IpcHandler {
        target: "project"
        function toggle(): void { shellRoot.load(projectL).ipc.toggle() }
        function show(): void { shellRoot.load(projectL).ipc.show() }
        function hide(): void { shellRoot.load(projectL).ipc.hide() }
        function mode(name: string): void { shellRoot.load(projectL).ipc.mode(name) }
    }

    LazyLoader { id: nightL; NightMenu {} }
    Timer { running: nightL.active && !!nightL.item && !(nightL.item.surfaceOpen ?? nightL.item.showing); interval: 600000; onTriggered: nightL.active = false }
    IpcHandler {
        target: "night"
        function toggle(): void { shellRoot.load(nightL).ipc.toggle() }
        function show(): void { shellRoot.load(nightL).ipc.show() }
        function hide(): void { shellRoot.load(nightL).ipc.hide() }
    }

    // the bar opens the media menu by setting Marquee.menuOpen
    property bool mediaUsed: false
    Connections { target: Marquee; function onMenuOpenChanged() { if (Marquee.menuOpen) shellRoot.mediaUsed = true } }
    LazyLoader { id: mediaL; active: shellRoot.mediaUsed || Marquee.menuOpen; MediaMenu {} }
    Timer { running: mediaL.active && !!mediaL.item && !Marquee.menuOpen; interval: 600000; onTriggered: shellRoot.mediaUsed = false }
    IpcHandler {
        target: "media"
        function toggle(): void { shellRoot.load(mediaL).ipc.toggle() }
        function open(): void { shellRoot.load(mediaL).ipc.open() }
        function close(): void { shellRoot.load(mediaL).ipc.close() }
        function playpause(): void { shellRoot.load(mediaL).ipc.playpause() }
        function next(): void { shellRoot.load(mediaL).ipc.next() }
        function previous(): void { shellRoot.load(mediaL).ipc.previous() }
    }

    LazyLoader { id: wallpaperL; WallpaperMenu {} }
    Timer { running: wallpaperL.active && !!wallpaperL.item && !(wallpaperL.item.surfaceOpen ?? wallpaperL.item.showing); interval: 120000; onTriggered: wallpaperL.active = false }
    IpcHandler {
        target: "wallpaper"
        function toggle(): void { shellRoot.load(wallpaperL).ipc.toggle() }
        function open(): void { shellRoot.load(wallpaperL).ipc.open() }
        function close(): void { shellRoot.load(wallpaperL).ipc.close() }
    }

    LazyLoader { id: wheelL; Wheel {} }
    Timer { running: wheelL.active && !!wheelL.item && !(wheelL.item.surfaceOpen ?? wheelL.item.showing); interval: 600000; onTriggered: wheelL.active = false }
    IpcHandler {
        target: "wheel"
        function toggle(): void { shellRoot.load(wheelL).ipc.toggle() }
        function show(): void { shellRoot.load(wheelL).ipc.show() }
        function hide(): void { shellRoot.load(wheelL).ipc.hide() }
        function confirm(): void { shellRoot.load(wheelL).ipc.confirm() }
    }

    LazyLoader { id: cheatsheetL; Cheatsheet {} }
    Timer { running: cheatsheetL.active && !!cheatsheetL.item && !(cheatsheetL.item.surfaceOpen ?? cheatsheetL.item.showing); interval: 600000; onTriggered: cheatsheetL.active = false }
    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { shellRoot.load(cheatsheetL).ipc.toggle() }
        function open(): void { shellRoot.load(cheatsheetL).ipc.open() }
        function hide(): void { shellRoot.load(cheatsheetL).ipc.hide() }
        function press(): void { shellRoot.load(cheatsheetL).ipc.press() }
        function release(): void { shellRoot.load(cheatsheetL).ipc.release() }
    }

    LazyLoader { id: overviewL; Overview {} }
    Timer { running: overviewL.active && !!overviewL.item && !(overviewL.item.surfaceOpen ?? overviewL.item.showing); interval: 600000; onTriggered: overviewL.active = false }
    IpcHandler {
        target: "overview"
        function toggle(): void { shellRoot.load(overviewL).ipc.toggle() }
        function open(): void { shellRoot.load(overviewL).ipc.open() }
        function hide(): void { shellRoot.load(overviewL).ipc.hide() }
    }

    LazyLoader { id: powermenuL; PowerMenu {} }
    Timer { running: powermenuL.active && !!powermenuL.item && !(powermenuL.item.surfaceOpen ?? powermenuL.item.showing); interval: 600000; onTriggered: powermenuL.active = false }
    IpcHandler {
        target: "powermenu"
        function toggle(): void { shellRoot.load(powermenuL).ipc.toggle() }
        function show(): void { shellRoot.load(powermenuL).ipc.show() }
        function hide(): void { shellRoot.load(powermenuL).ipc.hide() }
    }

    LazyLoader { id: clipboardL; ClipboardMenu {} }
    Timer { running: clipboardL.active && !!clipboardL.item && !clipboardL.item.surfaceOpen; interval: 600000; onTriggered: clipboardL.active = false }
    IpcHandler {
        target: "clipboard"
        function toggle(): void { shellRoot.load(clipboardL).ipc.toggle() }
        function open(): void { shellRoot.load(clipboardL).ipc.open() }
        function hide(): void { shellRoot.load(clipboardL).ipc.hide() }
    }

    LazyLoader { id: quickL; QuickMenu {} }
    Timer { running: quickL.active && !!quickL.item && !quickL.item.surfaceOpen; interval: 600000; onTriggered: quickL.active = false }
    IpcHandler {
        target: "quick"
        function toggle(): void { shellRoot.load(quickL).ipc.toggle() }
        function open(): void { shellRoot.load(quickL).ipc.open() }
        function hide(): void { shellRoot.load(quickL).ipc.hide() }
    }
    // the bar's network icon opens the quick menu in-process, under the icon
    Connections { target: Prefs; function onToggleQuick(x) { shellRoot.load(quickL).toggle(x) } }

    // the bar clock opens the calendar in-process
    Connections { target: Prefs; function onToggleCalendar() { shellRoot.load(calendarL).toggle() } }
}
