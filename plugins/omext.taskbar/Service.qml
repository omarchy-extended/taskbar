import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons

// A small taskbar at the bottom edge of every screen (omext taskbar, from
// omarchy-extended). It hides below the edge and comes up when the pointer
// reaches it. Left to right: the windows on the workspaces in front of you
// (every screen's), a button per other workspace with its windows in a list,
// the minimized windows, and a button per omext dock with its apps' windows.
// This file keeps the windows; TaskbarWindow.qml draws one screen's bar.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var appLibrary: shell ? shell.appLibrary : null
  readonly property string dockTool: Quickshell.env("HOME") + "/.local/bin/omext-dock"

  property var clients: []
  property var monitors: []
  property string activeAddress: ""
  property var docks: []   // `omext-dock list`'s docks, when omext docks is here

  // omext start at the left end, when it's here, on, and set to be (its
  // Settings › Bar button › On the taskbar: startOnTaskbar, which omext core keeps).
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
  readonly property bool startHere: !!coreAddons.item && coreAddons.item.on("start") && shared.startOnTaskbar === true
  // Start's menu, opened over this screen's taskbar: its left end, and how far
  // up from the bottom edge the taskbar reaches.
  function openStart(screenName, left, reach, wide) {
    Quickshell.execDetached(["omarchy-shell", "-q", "omext.start", "taskbar", screenName + " " + Math.round(left) + " " + Math.round(reach) + " " + Math.round(wide)])
  }
  // A click on the taskbar while Start's menu is open over it: the menu goes.
  function startAside() {
    if (root.heldScreen) Quickshell.execDetached(["omarchy-shell", "-q", "omext.start", "close"])
  }
  property string heldScreen: ""   // where Start's menu is open over the taskbar: it stays up

  // address -> {dock, app, icon, edge}: the windows in an omext dock.
  readonly property var docked: {
    var out = {}
    for (var d of root.docks)
      for (var a of (d.apps || []))
        if (a.address) out[a.address] = { dock: d.id, app: a.id, icon: a.icon || "", name: a.name || "", edge: d.edge }
    return out
  }

  // workspace id -> the monitor showing it.
  readonly property var shownWorkspaces: {
    var out = {}
    for (var m of root.monitors) if (m.activeWorkspace && m.activeWorkspace.id > 0) out[m.activeWorkspace.id] = m
    return out
  }
  readonly property bool manyScreens: root.monitors.length > 1

  function windowOk(c) { return c && c.address && c.mapped !== false }
  function byPlace(a, b) { return (a.at[0] - b.at[0]) || (a.at[1] - b.at[1]) }

  // The windows in front of you: by screen, left to right, then by place.
  readonly property var current: {
    var list = root.clients.filter(c => root.windowOk(c) && c.workspace && root.shownWorkspaces[c.workspace.id] && !root.docked[c.address])
    list.sort(function(a, b) {
      var ma = root.shownWorkspaces[a.workspace.id], mb = root.shownWorkspaces[b.workspace.id]
      return (ma.x - mb.x) || (ma.y - mb.y) || root.byPlace(a, b)
    })
    return list
  }

  // [{key, label, title, windows}]: each other workspace with windows, in order.
  readonly property var others: {
    var by = {}, out = []
    for (var c of root.clients) {
      if (!root.windowOk(c) || !c.workspace || !(c.workspace.id > 0) || root.shownWorkspaces[c.workspace.id] || root.docked[c.address]) continue
      var id = c.workspace.id
      if (!by[id]) {
        by[id] = { key: "ws:" + id, id: id, label: String(c.workspace.name || id), title: "Workspace " + (c.workspace.name || id), windows: [] }
        out.push(by[id])
      }
      by[id].windows.push(c)
    }
    out.sort((a, b) => a.id - b.id)
    for (var g of out) g.windows.sort(root.byPlace)
    return out
  }

  readonly property var minimized: root.clients.filter(c => root.windowOk(c) && c.workspace && c.workspace.name === "special:minimized")

  // [{key, edge, title, windows}]: each omext dock with an app running.
  readonly property var dockGroups: {
    var out = []
    for (var d of root.docks) {
      var windows = root.clients.filter(c => root.windowOk(c) && root.docked[c.address] && root.docked[c.address].dock === d.id)
      if (windows.length === 0) continue
      var side = d.edge === "left" ? "Left" : d.edge === "right" ? "Right" : String(d.edge || "")
      out.push({ key: "dock:" + d.id, edge: d.edge, title: side + " dock" + (root.manyScreens && d.screen ? " · " + d.screen : ""), windows: windows })
    }
    return out
  }

  // --- what a window looks like -----------------------------------------------

  function iconSource(name) {
    return root.appLibrary ? root.appLibrary.iconSource(name) : (Quickshell.iconPath(name, true) || Quickshell.iconPath("application-x-executable", true))
  }
  // Its desktop entry: by its class, or the class's last part without an
  // "_app" ("org.localsend.localsend_app": localsend).
  // omext core: what the omext addons share (which app a window is, going to
  // a window). Its files, by their path.
  readonly property string coreDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/plugins/omext.core"
  Loader { id: coreApps; source: "file://" + root.coreDir + "/Apps.qml" }
  Loader { id: coreWindows; source: "file://" + root.coreDir + "/Windows.qml" }
  Loader { id: coreAddons; source: "file://" + root.coreDir + "/Addons.qml" }
  Loader { id: coreShared; Component.onCompleted: setSource("file://" + root.coreDir + "/Settings.qml", { name: "omext" }) }
  // The taskbar's own settings (~/.config/omext/taskbar.json; omext core's
  // Settings reads, watches and writes it): gatherOnUnplug brings an unplugged
  // screen's windows onto the workspace in front of you.
  Loader { id: coreOwn; Component.onCompleted: setSource("file://" + root.coreDir + "/Settings.qml", { name: "taskbar" }) }
  readonly property var config: coreOwn.item ? coreOwn.item.values : ({})
  // The choices that cross addons (~/.config/omext/omext.json, omext core's).
  readonly property var shared: coreShared.item ? coreShared.item.values : ({})
  // (omext core's rule: a web app is itself, not its browser; an app run in a
  // terminal is the entry that starts it so.)
  function entryOf(c) {
    if (coreApps.item) return coreApps.item.ofWindow(c)
    return DesktopEntries.heuristicLookup(c.class) || DesktopEntries.heuristicLookup(c.initialClass)
  }
  function iconOf(c) {
    var d = root.docked[c.address]
    if (d && d.icon) return root.iconSource(d.icon)
    // A browser profile's own icon (omext core), so its windows tell apart.
    var p = coreApps.item && coreApps.item.profileIconOf ? coreApps.item.profileIconOf(c) : ""
    if (p) return root.iconSource(p)
    var e = root.entryOf(c)
    return root.iconSource(e && e.icon ? e.icon : String(c.class || "").toLowerCase())
  }
  // The app's name ("Files"), whatever its window's title says ("YouTube",
  // the folder it's in): the dock's name for it, else its desktop entry's.
  function appName(c) {
    var d = root.docked[c.address]
    if (d && d.name) return d.name
    var e = root.entryOf(c)
    return e ? e.name : String(c.class || "")
  }
  function titleOf(c) {
    return String(c.title || "") || root.appName(c)
  }
  // The title, when it says more than the app's name.
  function detailOf(c) {
    var t = String(c.title || "").trim(), n = root.appName(c)
    return t && t.toLowerCase() !== n.toLowerCase() ? t : ""
  }
  function labelOf(c) {
    var t = root.detailOf(c)
    return root.appName(c) + (t ? "  ·  " + t : "")
  }

  // --- what a click does ----------------------------------------------------------

  // Into the dock it's in, as Start does it: the dock's plugin opens it (it
  // slides out under a cover, then shows the app), then the pointer goes onto it.
  // A click: the window, focused and on top (its workspace comes with it). The
  // focused one goes down to the minimized instead, as on a taskbar. A
  // minimized one comes back onto the workspace in front of you first.
  // --- pinned apps ---------------------------------------------------------------
  // Apps that keep an icon on the taskbar, running or not ("pins" in
  // ~/.config/omext/taskbar.json: desktop entry ids, in their order). A right
  // click on a window's icon pins or unpins its app.
  readonly property var pins: Array.isArray(config.pins) ? config.pins : []
  function pinKeyOf(c) {
    var e = c ? root.entryOf(c) : null
    return e && e.id ? String(e.id) : String(c && c.class || "")
  }
  function isPinnedKey(k) { return root.pins.indexOf(k) >= 0 }
  function togglePinKey(k) {
    if (!k || !coreOwn.item) return
    var p = root.pins.slice(), i = p.indexOf(k)
    if (i >= 0) p.splice(i, 1); else p.push(k)
    coreOwn.item.set({ pins: p })
  }
  function togglePin(address) {
    var a = String(address).indexOf("0x") === 0 ? String(address) : "0x" + address
    var c = root.clients.find(x => x.address === a)
    if (c) root.togglePinKey(root.pinKeyOf(c))
  }
  // [{key, entry, name, icon, windows}]: each pin, with its app's windows
  // wherever they are (another workspace, minimized, in a dock).
  readonly property var pinned: root.pins.map(function(k) {
    var e = DesktopEntries.byId(k) || DesktopEntries.heuristicLookup(k)
    return { key: k, entry: e || null, name: e ? e.name : k, icon: e && e.icon ? e.icon : String(k).toLowerCase(),
             windows: root.clients.filter(c => root.windowOk(c) && root.pinKeyOf(c) === k) }
  })
  // A pin clicked: to its window if it has one (the first), else the app starts.
  function openPin(pin, screenMonitor) {
    if (pin.windows.length) { root.activate(pin.windows[0], screenMonitor); return }
    var e = pin.entry
    if (!e) return
    if (e.runInTerminal) Quickshell.execDetached(["omarchy-launch-tui"].concat((e.command || []).filter(w => !/^%[a-zA-Z]$/.test(String(w)))))
    else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", String(e.id) + ".desktop"])
    refreshSoon.restart()
  }

  function activate(c, screenMonitor) {
    var w = coreWindows.item
    if (!w) return
    var d = root.docked[c.address]
    if (!d && c.address === root.activeAddress && c.workspace && c.workspace.id > 0 && root.shownWorkspaces[c.workspace.id]) w.minimize(c)
    else w.goTo(c, d || null, screenMonitor || null)
    refreshSoon.restart()
  }

  // Brings windows from the workspaces out of sight onto the one a screen shows
  // (the focused screen's by default), where they stay put behind the focus.
  // `which`: addresses, or every window in `others` when left out.
  function gather(screenMonitor, which) {
    var m = screenMonitor || Hyprland.focusedMonitor
    var ws = m && m.activeWorkspace ? m.activeWorkspace.id : -1
    if (!(ws >= 1)) return 0
    var moved = 0
    for (var g of root.others) for (var c of g.windows) {
      if (which && which.indexOf(c.address) === -1) continue
      if (coreWindows.item) coreWindows.item.moveTo(c, ws)
      moved++
    }
    if (moved > 0) refreshSoon.restart()
    return moved
  }

  // A screen unplugged: its workspaces carry on, out of sight, on another
  // screen. Its windows come onto the workspace in front of you instead.
  property var orphans: []
  Timer {
    id: gatherOrphans
    interval: 1500
    onTriggered: { var a = root.orphans; root.orphans = []; root.gather(null, a) }
  }
  function screenGone(data) {
    if (root.config.gatherOnUnplug !== true) return
    var id = parseInt(String(data).split(",")[0])
    var mine = root.clients.filter(c => root.windowOk(c) && c.monitor === id && c.workspace && c.workspace.id > 0 && !root.docked[c.address])
    if (mine.length === 0) return
    root.orphans = root.orphans.concat(mine.map(c => c.address))
    gatherOrphans.restart()
  }

  // A right click: omext arrange's small map of the window's screen's zones, at
  // the pointer, as its button on a window's titlebar opens (a click there
  // puts the window in that zone, or in a dock). A minimized one comes back
  // onto the workspace in front of you first. Nothing without omext arrange.
  // `on`: the taskbar's screen; (x, y): the point there the map stands on (the
  // middle of the icon's top edge, in layout pixels).
  property string zoneScreen: ""   // the screen whose taskbar the zone map was opened from ("": none open)
  Timer { id: zoneGone; interval: 2500; onTriggered: root.zoneScreen = "" }   // (the map never opened)
  function zoneMenu(c, on, x, y) {
    if (!c || !coreAddons.item || !coreAddons.item.on("zones") || root.docked[c.address]) return false
    var minimized = c.workspace && c.workspace.name === "special:minimized"
    var mon = root.monitors.find(m => m.id === c.monitor)
    var screen = minimized || !mon ? on : mon.name   // (a minimized one comes back onto this screen)
    if (minimized && coreWindows.item) coreWindows.item.goTo(c, null, null)
    // (With what the map's Pin line would do for this window's app.)
    Quickshell.execDetached(["bash", "-c", (minimized ? "sleep 0.25; " : "") + 'omarchy-shell -q omext.zones quickPin "$0" "$1" "$2" "$3" "$4" "$5"',
                             c.address, screen, on, String(Math.round(x)), String(Math.round(y)), root.isPinnedKey(root.pinKeyOf(c)) ? "unpin" : "pin"])
    root.zoneScreen = on
    zoneGone.restart()
    refreshSoon.restart()
    return true
  }

  function closeWindow(c) {
    if (coreWindows.item) coreWindows.item.close(c)
    refreshSoon.restart()
  }

  // --- keeping up ------------------------------------------------------------------

  function refresh() {
    if (!clientsProc.running) clientsProc.running = true
    else clientsAgain = true
  }
  property bool clientsAgain: false
  function refreshDocks() {
    if (!dockProc.running) dockProc.running = true
  }

  Process {
    id: clientsProc
    command: ["bash", "-c", "printf '{\"clients\":%s,\"monitors\":%s,\"active\":%s}' \"$(hyprctl clients -j)\" \"$(hyprctl monitors -j)\" \"$(hyprctl activewindow -j)\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var all = JSON.parse(text)
          root.clients = all.clients || []
          root.monitors = all.monitors || []
          root.activeAddress = all.active && all.active.address || ""
        } catch (e) {}
      }
    }
    onExited: if (root.clientsAgain) { root.clientsAgain = false; Qt.callLater(root.refresh) }
  }

  Process {
    id: dockProc
    command: ["bash", "-c", '[ -x "$0" ] && "$0" list 2>/dev/null || echo "{}"', root.dockTool]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.docks = JSON.parse(text).docks || [] } catch (e) { root.docks = [] }
      }
    }
  }

  Timer { id: refreshSoon; interval: 60; onTriggered: root.refresh() }
  Timer { id: docksSoon; interval: 400; onTriggered: root.refreshDocks() }
  // Nothing is missed for long, whatever an event leaves out.
  Timer { interval: 5000; running: true; repeat: true; onTriggered: { root.refresh(); } }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event.name)
      // omext arrange's zone map, opened from a right click here: the taskbar
      // stays up on that screen until the map has gone.
      if (name === "openlayer" && String(event.data) === "omext-zones-quick") zoneGone.stop()
      if (name === "closelayer" && String(event.data) === "omext-zones-quick") root.zoneScreen = ""
      if (name === "monitorremovedv2") root.screenGone(event.data)
      if (/^(openwindow|closewindow|movewindow|windowtitle|activewindow|workspace|focusedmon|monitoradded|monitorremoved|fullscreen|changefloatingmode|minimized|activespecial)/.test(name))
        refreshSoon.restart()
      if (/^(openwindow|closewindow|movewindow|monitoradded|monitorremoved|configreloaded)/.test(name))
        docksSoon.restart()
    }
  }

  // (In place of Omarchy's dock, which would collide with it at the bottom
  // edge: omext core has that off while the taskbar is on.)
  Component.onCompleted: {
    refresh(); refreshDocks()
  }

  // Escape (omext core's bind): the lists close and the taskbar goes down.
  GlobalShortcut {
    appid: "omext"; name: "escape-taskbar"; description: "Close the taskbar and its lists"
    onPressed: { for (var w of bars.instances) w.done() }
  }

  // The taskbar's key (hypr/taskbar.lua binds it when one is set): up, with the
  // keyboard on it, on the screen in front.
  function byKeyboard() {
    for (var w of bars.instances) if (w.monitor && w.monitor.focused) { if (w.kbOn) w.done(); else w.kbStart() }
  }
  GlobalShortcut { appid: "omext"; name: "taskbar-keys"; description: "The taskbar, by keyboard"; onPressed: root.byKeyboard() }

  ShellIpc {
    target: "omext.taskbar"
    function refresh(): void { root.refresh(); root.refreshDocks() }
    // Every window on a workspace out of sight, onto the focused screen's.
    function gather(): void { root.gather(null) }
    function keys(): void { root.byKeyboard() }
    function pin(address: string): void { root.togglePin(address) }   // a window's app, pinned or unpinned (the zone map's line)
    // Start's menu is open over this screen's taskbar ("" : closed).
    function hold(screen: string): void { root.heldScreen = screen }
    // Up on the screen with the focus, until the pointer has been and gone.
    function show(): void {
      for (var w of bars.instances) if (w.monitor && w.monitor.focused) w.reveal()
    }
    // A group's list: "3" (workspace 3), or "dock:<id>" (an omext dock).
    function list(group: string): void {
      var key = /^[0-9]+$/.test(group) ? "ws:" + group : group
      for (var w of bars.instances) if (w.monitor && w.monitor.focused) w.openByKey(key)
    }
  }

  Variants {
    id: bars
    model: Quickshell.screens
    delegate: Component {
      TaskbarWindow {
        required property var modelData
        screen: modelData
        taskbar: root
      }
    }
  }
}
