import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// One screen's taskbar. The surface stays mapped across the bottom of the
// screen; only its contents move. Tucked away, its mask is a thin strip along
// the edge under the bar, which brings it up; clicks anywhere else go through.
PanelWindow {
  id: win

  property var taskbar: null

  readonly property var monitor: Hyprland.monitorFor(screen)
  readonly property var mon: {
    var name = win.monitor ? win.monitor.name : ""
    for (var m of (taskbar ? taskbar.monitors : [])) if (m.name === name) return m
    return null
  }
  readonly property int workspaceId: mon && mon.activeWorkspace ? mon.activeWorkspace.id : -1
  // A fullscreen window has the whole screen, the taskbar's edge too.
  readonly property bool fullscreen: !!taskbar && taskbar.clients.some(c => c.workspace && c.workspace.id === win.workspaceId && (c.fullscreen || 0) >= 2)

  readonly property var current: taskbar ? taskbar.current : []
  readonly property var others: taskbar ? taskbar.others : []
  readonly property var minimized: taskbar ? taskbar.minimized : []
  readonly property var dockGroups: taskbar ? taskbar.dockGroups : []
  readonly property bool startHere: !!taskbar && taskbar.startHere
  readonly property bool held: !!taskbar && !!screen && taskbar.heldScreen === screen.name
  onHeldChanged: if (!held) hideTimer.restart()
  readonly property bool anything: startHere || current.length + others.length + minimized.length + dockGroups.length > 0

  readonly property bool shown: !!taskbar && anything && !fullscreen
  property bool revealed: false
  property string openKey: ""       // the group whose list is open ("ws:3", "dock:left-laptop")
  property real openX: 0            // the middle of its button
  // (Up too while omext arrange's zone map, opened from here, is open.)
  readonly property bool zoning: !!taskbar && taskbar.zoneScreen !== "" && taskbar.zoneScreen === screen.name
  onZoningChanged: if (!zoning) hideTimer.restart()
  readonly property bool up: shown && (revealed || openKey !== "" || held || zoning)

  readonly property int iconSize: Math.round(22 * Style.fontScale)
  readonly property int slot: iconSize + Style.space(12)
  readonly property int gap: Style.space(6)
  readonly property color text: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent

  // A workspace with up to this many windows shows them on the bar, when
  // there's room for every such workspace's (counted, not measured: the bar's
  // own width would depend on the answer).
  readonly property int flatMax: 5
  readonly property bool flatOthers: {
    var s = win.slot, w = (win.current.length + win.minimized.length + (win.startHere ? 1.5 : 0)) * s + 3 * Style.space(11) + Style.space(10)
    for (var g of win.others) w += g.windows.length <= win.flatMax ? g.windows.length * s + Style.space(14) : s * 2.5
    w += win.dockGroups.length * (s + Style.space(6))
    if (win.others.length > 0) w += s  // the gather button
    return w <= win.width - Style.space(80)
  }

  readonly property var openGroup: {
    for (var g of win.others) if (g.key === win.openKey) return g
    for (var d of win.dockGroups) if (d.key === win.openKey) return d
    return null
  }
  onOpenGroupChanged: if (!openGroup) openKey = ""
  onShownChanged: if (!shown) { revealed = false; openKey = "" }

  function reveal() { win.revealed = true; shownByCall.restart() }
  function toggleGroup(key, button) {
    win.taskbar.startAside()
    if (win.openKey === key) { win.openKey = ""; return }
    win.openX = button.mapToItem(win.contentItem, button.width / 2, 0).x
    win.openKey = key
    win.tipFor = null
  }
  function openByKey(key) {
    for (var i = 0; i < row.children.length; i++) {
      var b = row.children[i]
      if (b.group && b.group.key === key) { win.revealed = true; win.toggleGroup(key, b); return }
    }
  }
  // A right click on a window: omext arrange's zone map, standing on the bar
  // above that icon (or row).
  function zoneMenuAt(c, item) {
    var p = item.mapToItem(win.contentItem, item.width / 2, 0)
    var top = Math.min(p.y, body.y)   // clear of the bar, and of an open list
    return win.taskbar.zoneMenu(c, win.screen.name, win.screen.x + p.x, win.screen.y + win.screen.height - win.height + top)
  }
  function done() { win.openKey = ""; win.revealed = false; win.tipFor = null }

  color: "transparent"
  WlrLayershell.namespace: "omext-taskbar"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0
  anchors { left: true; right: true; bottom: true }
  implicitHeight: 460

  mask: Region {
    item: win.up ? body : null
    Region { item: win.shown && !win.up ? edge : null }
    Region { item: win.shown && win.up ? hold : null }
    Region { item: list.visible ? list : null }
    Region { item: win.up && win.startHere ? startCircle : null }
  }

  HyprlandFocusGrab {
    active: win.openKey !== ""
    windows: [win]
    onCleared: win.done()
  }

  Timer {
    id: hideTimer
    interval: 350
    onTriggered: if (!bodyHover.hovered && !edgeHover.hovered && !backHover.hovered && !startHit.containsMouse && win.openKey === "" && !win.held && !win.zoning && !shownByCall.running) win.revealed = false
  }
  Timer { id: shownByCall; interval: 2500; onTriggered: hideTimer.restart() }

  // The thin strip along the bottom edge that brings it up: the whole edge,
  // from corner to corner, so it's found without aiming.
  Item {
    id: edge
    width: win.width
    height: 2
    x: 0
    y: win.height - height
    HoverHandler {
      id: edgeHover
      onHoveredChanged: if (hovered) win.revealed = true; else hideTimer.restart()
    }
  }

  // What holds the bar up: the pointer anywhere across the bottom of the
  // screen, from the edge to just over the bar (no higher: moving up off the
  // bar puts it away).
  Item {
    id: hold
    visible: win.up   // (down, it would lie over the edge strip and take its hover)
    width: win.width
    height: body.height + win.gap + Style.space(6)
    y: win.height - height
    HoverHandler {
      id: backHover
      onHoveredChanged: if (!hovered) hideTimer.restart()
    }
  }

  // Up, a shade across the whole bottom of the screen, dark at the edge and
  // fading into the desktop above the bar (only a shade: clicks go through
  // what's above the bar).
  Rectangle {
    id: backdrop
    width: win.width
    height: body.height + win.gap + Style.space(56)
    y: win.height - height
    opacity: win.up ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic } }
    gradient: Gradient {
      GradientStop { position: 0.0; color: Commons.Util.alpha(Commons.Color.popups.background, 0) }
      GradientStop { position: 0.45; color: Commons.Util.alpha(Commons.Color.popups.background, 0.35) }
      GradientStop { position: 1.0; color: Commons.Util.alpha(Commons.Color.popups.background, 0.8) }
    }
  }

  // --- the bar ---------------------------------------------------------------------

  Item {
    id: body
    width: row.implicitWidth + Style.space(10)
    height: win.slot + Style.space(8)
    x: Math.round((win.width - width) / 2)
    property real tuck: win.up ? 0 : height + win.gap + 4
    Behavior on tuck { NumberAnimation { duration: Style.duration(body.tuck > 0 ? 140 : 200); easing.type: Easing.OutCubic } }
    y: win.height - height - win.gap + tuck
    opacity: win.shown && win.up ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Style.duration(160) } }

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered) { hideTimer.restart(); win.tipFor = null }
    }

    Rectangle {
      // With Start's circle at the left end, the bar starts under its middle:
      // the circle is its end, with nothing of the bar out beyond it.
      anchors.fill: parent
      anchors.leftMargin: win.startHere ? row.x + startButton.width / 2 : 0
      radius: Style.space(14)
      color: Commons.Util.alpha(Commons.Color.popups.background, 0.88)
      border.color: Commons.Util.alpha(win.text, 0.12)
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.4
        shadowBlur: 0.6
        shadowVerticalOffset: 3
      }
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: 0

      // omext start, when it's set to be here.
      Item {
        id: startButton
        visible: win.startHere
        // A circle, larger than the rest, standing up out of the bar.
        readonly property int size: win.slot + Style.space(16)
        width: visible ? size + Style.space(4) : 0
        height: win.slot
        Rectangle {
          id: startCircle
          width: startButton.size; height: width
          radius: width / 2
          x: (startButton.width - width) / 2
          // Centred on the bar: as much out of it above as below (never past
          // the screen's bottom edge).
          y: Math.min((win.slot - height) / 2, body.height + win.gap - row.y - 1 - height)
          scale: startHit.pressed ? 0.94 : startHit.containsMouse ? 1.05 : 1
          Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
          gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(win.accent, startHit.containsMouse || win.held ? 1.25 : 1.1) }
            GradientStop { position: 1; color: Qt.darker(win.accent, 1.25) }
          }
          border.color: Commons.Util.alpha(Commons.Color.popups.background, 0.9)
          border.width: Style.space(2)
          layer.enabled: true
          layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.45; shadowBlur: 0.6; shadowVerticalOffset: 2 }
          Text {
            anchors.centerIn: parent
            text: "\u{F0570}"
            color: Commons.Color.popups.background
            font.family: Style.font.menuFamily || Style.font.family
            font.pixelSize: Math.round(win.iconSize * 1.15)
          }
          MouseArea {
            id: startHit
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // The menu a little way above the bar (and the circle over it). The
            // gap between is still Start's: the pointer crossing it keeps both.
            onClicked: win.taskbar.openStart(win.screen.name, body.x, body.height + win.gap + Style.space(12), body.width)
          }
        }
      }
      Divider { visible: win.startHere && win.current.length + win.minimized.length + win.others.length + win.dockGroups.length > 0 }

      // The workspaces in front of you: a little room between one and the next.
      Repeater {
        model: win.current
        TaskIcon {
          required property var modelData
          required property int index
          client: modelData
          leftRoom: index > 0 && win.current[index - 1].workspace.id !== modelData.workspace.id ? Style.space(8) : 0
        }
      }

      Divider { visible: win.minimized.length > 0 && win.current.length > 0 }

      Repeater {
        model: win.minimized
        TaskIcon {
          required property var modelData
          client: modelData
          minimized: true
        }
      }

      Divider { visible: win.others.length > 0 && win.current.length + win.minimized.length > 0 }

      // Every other workspace, its number small in the corner: its windows'
      // icons right on the bar, to click; with more than flatMax (or no room
      // for them all), one button whose click lists them.
      Repeater {
        model: win.others
        Item {
          id: og
          required property var modelData
          readonly property bool flat: win.flatOthers && modelData.windows.length <= win.flatMax
          readonly property var group: flat ? null : modelData   // a list to open (openByKey)
          width: flat ? flatBox.width : groupButton.width
          height: win.slot

          GroupButton {
            id: groupButton
            visible: !og.flat
            group: og.modelData
            label: og.modelData.label
            corner: true
          }

          Item {
            id: flatBox
            visible: og.flat
            width: flatRow.implicitWidth + Style.space(14)
            height: win.slot
            Rectangle {
              x: 2; y: 2; width: parent.width - 4; height: parent.height - 4
              radius: Style.space(9)
              color: Commons.Util.alpha(win.text, 0.05)
              border.color: Commons.Util.alpha(win.text, 0.08)
            }
            Row {
              id: flatRow
              anchors.centerIn: parent
              anchors.horizontalCenterOffset: -Style.space(2)
              Repeater {
                model: og.flat ? og.modelData.windows : []
                TaskIcon {
                  required property var modelData
                  client: modelData
                }
              }
            }
            Text {
              anchors { right: parent.right; bottom: parent.bottom; rightMargin: Style.space(5); bottomMargin: Style.space(3) }
              text: og.modelData.label
              color: Commons.Util.alpha(win.text, 0.45)
              font.family: Style.font.family
              font.pixelSize: Math.round(Style.font.caption * 0.85)
              font.bold: true
            }
          }
        }
      }

      // All of them here: every window out of sight onto this screen's workspace.
      Item {
        id: gatherButton
        visible: win.others.length > 0
        readonly property string tipText: "Bring them all here"
        width: win.slot
        height: win.slot
        Rectangle {
          x: 2; y: 2; width: parent.width - 4; height: parent.height - 4
          radius: Style.space(9)
          color: gatherHit.containsMouse ? Commons.Util.alpha(win.text, 0.12) : "transparent"
          Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text {
          anchors.centerIn: parent
          text: "\u{F0044}"
          color: Commons.Util.alpha(win.text, gatherHit.containsMouse ? 0.95 : 0.6)
          font.family: Style.font.menuFamily || Style.font.family
          font.pixelSize: Math.round(win.iconSize * 0.8)
        }
        MouseArea {
          id: gatherHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: if (containsMouse) win.tipFor = gatherButton; else if (win.tipFor === gatherButton) win.tipFor = null
          onClicked: { win.taskbar.startAside(); win.taskbar.gather(win.monitor); win.done() }
        }
      }

      Divider { visible: win.dockGroups.length > 0 && win.current.length + win.others.length + win.minimized.length > 0 }

      // Each omext dock with apps running in it.
      Repeater {
        model: win.dockGroups
        GroupButton {
          required property var modelData
          group: modelData
          compact: true
          label: modelData.edge === "left" ? "\u{F10AA}" : modelData.edge === "right" ? "\u{F10AB}" : "\u{F10AC}"
        }
      }
    }
  }

  // --- a window's title, over its icon ---------------------------------------------

  property Item tipFor: null
  Rectangle {
    id: tip
    visible: win.up && win.openKey === "" && win.tipFor !== null
    readonly property string what: win.tipFor ? win.tipFor.tipText : ""
    width: Math.min(Style.space(420), tipText.implicitWidth + Style.space(18))
    height: tipText.implicitHeight + Style.space(10)
    radius: Style.space(8)
    color: Commons.Util.alpha(Commons.Color.popups.background, 0.95)
    border.color: Commons.Util.alpha(win.text, 0.14)
    x: {
      if (!win.tipFor) return 0
      var c = win.tipFor.mapToItem(win.contentItem, win.tipFor.width / 2, 0).x
      return Math.max(win.gap, Math.min(win.width - width - win.gap, c - width / 2))
    }
    y: body.y - height - Style.space(6)
    Text {
      id: tipText
      anchors.centerIn: parent
      width: Math.min(implicitWidth, Style.space(400))
      text: tip.what
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: win.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }

  // --- a group's windows, over its button ---------------------------------------

  Rectangle {
    id: list
    visible: win.up && win.openGroup !== null
    readonly property int rowHeight: Math.round(30 * Style.fontScale)
    readonly property var windows: win.openGroup ? win.openGroup.windows : []
    width: Style.space(340)
    height: header.height + Math.min(windows.length * rowHeight, win.height - body.height - win.gap * 3 - header.height - Style.space(20)) + Style.space(14)
    radius: Style.space(12)
    color: Commons.Util.alpha(Commons.Color.popups.background, 0.96)
    border.color: Commons.Util.alpha(win.text, 0.14)
    x: Math.round((win.width - width) / 2)   // centred, as the taskbar is
    y: body.y - height - Style.space(8)
    layer.enabled: true
    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "#000000"; shadowOpacity: 0.35; shadowBlur: 0.6; shadowVerticalOffset: 3 }

    Text {
      id: header
      x: Style.space(12); y: Style.space(8)
      text: win.openGroup ? win.openGroup.title : ""
      color: Commons.Util.alpha(win.text, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.capitalization: Font.AllUppercase
      font.letterSpacing: 0.8
      bottomPadding: Style.space(4)
    }

    ListView {
      x: Style.space(6); y: header.y + header.height
      width: parent.width - Style.space(12)
      height: parent.height - y - Style.space(6)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: list.windows
      delegate: Rectangle {
        id: entry
        required property var modelData
        width: ListView.view.width
        height: list.rowHeight
        radius: Style.space(7)
        color: entryHit.containsMouse ? Commons.Util.alpha(win.text, 0.1) : "transparent"
        AppIcon {
          id: entryIcon
          x: Style.space(6); anchors.verticalCenter: parent.verticalCenter
          size: Math.round(18 * Style.fontScale)
          client: entry.modelData
        }
        Row {  // the app's name, then what its window shows
          anchors.verticalCenter: parent.verticalCenter
          x: entryIcon.x + entryIcon.width + Style.space(8)
          width: parent.width - x - Style.space(30)
          spacing: Style.space(8)
          Text {
            id: entryApp
            width: Math.min(implicitWidth, parent.width * 0.6)
            text: win.taskbar.appName(entry.modelData)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: win.text
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Text {
            width: parent.width - entryApp.width - parent.spacing
            text: win.taskbar.detailOf(entry.modelData)
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Commons.Util.alpha(win.text, 0.6)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
        MouseArea {
          id: entryHit
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
          // Everything taken first: closing the list takes this row away with it.
          onClicked: function(mouse) {
            var c = entry.modelData, bar = win.taskbar, m = win.monitor
            bar.startAside()
            if (mouse.button === Qt.MiddleButton) { bar.closeWindow(c); return }
            if (mouse.button === Qt.RightButton) { if (win.zoneMenuAt(c, entry)) win.done(); return }
            bar.activate(c, m)
            win.done()
          }
        }
        Rectangle {  // ✕ closes it
          anchors { right: parent.right; rightMargin: Style.space(5); verticalCenter: parent.verticalCenter }
          width: Style.space(20); height: width; radius: width / 2
          visible: entryHit.containsMouse || xHit.containsMouse
          color: xHit.containsMouse ? Commons.Util.alpha(Commons.Color.urgent, 0.4) : Commons.Util.alpha(win.text, 0.1)
          Text { anchors.centerIn: parent; text: "✕"; color: win.text; font.pixelSize: Style.space(9) }
          MouseArea { id: xHit; anchors.fill: parent; hoverEnabled: true; onClicked: win.taskbar.closeWindow(entry.modelData) }
        }
      }
    }
  }

  // --- the pieces --------------------------------------------------------------------

  // An app's icon, or its initial when it has none.
  component AppIcon: Item {
    id: ai
    property var client: null
    property int size: win.iconSize
    width: size; height: size
    Image {
      id: img
      anchors.fill: parent
      source: ai.client ? win.taskbar.iconOf(ai.client) : ""
      sourceSize: Qt.size(ai.size * 2, ai.size * 2)
      fillMode: Image.PreserveAspectFit
      smooth: true
      asynchronous: true
    }
    Rectangle {
      anchors.fill: parent
      visible: img.status !== Image.Ready
      radius: ai.size / 4
      color: Commons.Util.alpha(win.accent, 0.25)
      Text {
        anchors.centerIn: parent
        text: ai.client ? win.taskbar.appName(ai.client).charAt(0).toUpperCase() : ""
        color: win.text
        font.family: Style.font.family
        font.pixelSize: Math.round(ai.size * 0.55)
        font.bold: true
      }
    }
  }

  // A window: click to go to it (the focused one: minimize it), middle-click to close it.
  component TaskIcon: Item {
    id: ti
    property var client: null
    property bool minimized: false
    property int leftRoom: 0
    readonly property bool active: !!client && client.address === win.taskbar.activeAddress && !minimized
    readonly property string tipText: client ? win.taskbar.labelOf(client) + (minimized ? "  ·  minimized" : "") : ""
    width: win.slot + leftRoom
    height: win.slot

    Rectangle {
      x: ti.leftRoom + 2; y: 2
      width: win.slot - 4; height: win.slot - 4
      radius: Style.space(9)
      color: hit.containsMouse ? Commons.Util.alpha(win.text, 0.12) : ti.active ? Commons.Util.alpha(win.accent, 0.2) : "transparent"
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    AppIcon {
      x: ti.leftRoom + (win.slot - width) / 2
      y: (win.slot - height) / 2 - 1
      client: ti.client
      opacity: ti.minimized ? 0.45 : 1
      scale: hit.pressed ? 0.9 : hit.containsMouse ? 1.12 : 1
      Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
    Rectangle {  // focused: a wide accent line; minimized: none
      visible: !ti.minimized
      width: ti.active ? Style.space(12) : Style.space(4)
      height: 3; radius: 1.5
      x: ti.leftRoom + (win.slot - width) / 2
      y: win.slot - 4
      color: win.accent
      opacity: ti.active ? 1 : 0.45
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }
    MouseArea {
      id: hit
      x: ti.leftRoom; width: win.slot; height: win.slot
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
      onContainsMouseChanged: if (containsMouse) win.tipFor = ti; else if (win.tipFor === ti) win.tipFor = null
      onClicked: function(mouse) {
        win.taskbar.startAside()
        if (mouse.button === Qt.MiddleButton) { win.taskbar.closeWindow(ti.client); return }
        if (mouse.button === Qt.RightButton) { win.tipFor = null; win.zoneMenuAt(ti.client, ti); return }
        win.tipFor = null
        win.taskbar.activate(ti.client, win.monitor)
      }
    }
  }

  // A group (a workspace, a dock): its label and its first apps' icons, with
  // how many; a click lists them all.
  component GroupButton: Item {
    id: gb
    property var group: null
    property string label: ""
    property bool corner: false   // the label small in the corner (a workspace's number)
    property bool compact: false  // just the label, as an icon, and the count in the corner (a dock)
    readonly property bool open: !!group && win.openKey === group.key
    readonly property string tipText: group ? group.title + "  ·  " + group.windows.length + (group.windows.length === 1 ? " window" : " windows") : ""
    width: gb.compact ? win.slot + Style.space(6) : inner.implicitWidth + Style.space(gb.corner ? 18 : 14)
    height: win.slot

    Rectangle {
      x: 2; y: 2; width: parent.width - 4; height: parent.height - 4
      radius: Style.space(9)
      color: gb.open ? Commons.Util.alpha(win.accent, 0.3) : gbHit.containsMouse ? Commons.Util.alpha(win.text, 0.12) : Commons.Util.alpha(win.text, 0.05)
      border.color: Commons.Util.alpha(win.text, gb.open ? 0 : 0.08)
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    Text {  // compact: the label as an icon
      visible: gb.compact
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: -Style.space(2)
      text: gb.label
      color: win.text
      font.family: Style.font.menuFamily || Style.font.family
      font.pixelSize: Math.round(win.iconSize * 0.95)
    }
    Text {  // compact: how many
      visible: gb.compact && !!gb.group
      anchors { right: parent.right; bottom: parent.bottom; rightMargin: Style.space(5); bottomMargin: Style.space(3) }
      text: gb.group ? String(gb.group.windows.length) : ""
      color: Commons.Util.alpha(win.text, gb.open || gbHit.containsMouse ? 0.75 : 0.45)
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.caption * 0.85)
      font.bold: true
    }
    Row {
      id: inner
      visible: !gb.compact
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: gb.corner ? -Style.space(2) : 0
      spacing: Style.space(4)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !gb.corner
        text: gb.label
        color: win.text
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.bold: true
      }
      Repeater {
        model: gb.group ? gb.group.windows.slice(0, 3) : []
        AppIcon {
          required property var modelData
          anchors.verticalCenter: parent.verticalCenter
          client: modelData
          size: Math.round(15 * Style.fontScale)
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: !!gb.group && gb.group.windows.length > 3
        text: gb.group ? "+" + (gb.group.windows.length - 3) : ""
        color: Commons.Util.alpha(win.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
    Text {  // the corner label
      visible: gb.corner
      anchors { right: parent.right; bottom: parent.bottom; rightMargin: Style.space(5); bottomMargin: Style.space(3) }
      text: gb.label
      color: Commons.Util.alpha(win.text, gb.open || gbHit.containsMouse ? 0.75 : 0.45)
      font.family: Style.font.family
      font.pixelSize: Math.round(Style.font.caption * 0.85)
      font.bold: true
    }
    MouseArea {
      id: gbHit
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) win.tipFor = gb; else if (win.tipFor === gb) win.tipFor = null
      onClicked: win.toggleGroup(gb.group.key, gb)
    }
  }

  component Divider: Item {
    width: Style.space(11)
    height: win.slot
    Rectangle {
      anchors.centerIn: parent
      width: 1; height: win.slot * 0.55
      color: Commons.Util.alpha(win.text, 0.18)
    }
  }
}
