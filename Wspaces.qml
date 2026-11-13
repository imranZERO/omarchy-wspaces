pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Workspace numbers with the icons of the apps open on each. Click a number
// to switch, an icon to focus that window, scroll to step. Horizontal bars only.
BarWidget {
  id: root
  moduleName: "imranzero.wspaces"

  readonly property bool activeOnly: setting("showApps", "all") === "active"
  readonly property int iconPx: Math.min(setting("iconSize", 16), pillHeight - Style.space(4))
  readonly property int maxIcons: setting("maxIcons", 8)
  readonly property int persistent: setting("persistentWorkspaces", 5)

  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property int pillHeight: Math.max(16, barSize - Style.space(6))
  readonly property bool rounded: Style.cornerRadius > 0

  // ------------------------------------------------------------ workspaces

  readonly property var monitor: root.QsWindow.window && root.QsWindow.window.screen
    ? Hyprland.monitorFor(root.QsWindow.window.screen) : Hyprland.focusedMonitor
  readonly property string monitorName: monitor ? monitor.name : ""
  readonly property int activeId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
  readonly property string activeAddress: Hyprland.activeToplevel ? String(Hyprland.activeToplevel.address) : ""

  // Omarchy gives each monitor a block of ten workspaces (1-10, 11-20, ...)
  // and records which block in this file: "<block>\t<connector>\t<desc>".
  property var blocks: ({})

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitors/workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var next = {}
      text().split("\n").forEach(function(line) {
        var f = line.split("\t")
        if (f.length >= 3) next[f[1]] = parseInt(f[0], 10)
      })
      root.blocks = next
    }
  }

  function blockOf(id) { return Math.floor((id - 1) / 10) }
  function slotOf(id) { return (id - 1) % 10 + 1 }

  readonly property int block: blocks[monitorName] !== undefined ? blocks[monitorName]
    : activeId > 0 ? blockOf(activeId) : 0

  // The block's first N workspaces and any others of it that exist, then
  // workspaces from other blocks that are visiting this monitor.
  readonly property var workspaceIds: {
    var own = [], guests = []
    for (var p = 1; p <= persistent; p++) own.push(block * 10 + p)
    Hyprland.workspaces.values.forEach(function(ws) {
      if (ws.id <= 0) return
      if (blockOf(ws.id) === block) { if (own.indexOf(ws.id) === -1) own.push(ws.id) }
      else if (ws.monitor && ws.monitor.name === monitorName) guests.push(ws.id)
    })
    var byId = function(a, b) { return a - b }
    return own.sort(byId).concat(guests.sort(byId))
  }

  // Windows on a workspace in screen order, capped at maxIcons.
  function windowsOf(id) {
    var ws = Hyprland.workspaces.values.find(function(w) { return w.id === id })
    if (!ws) return []
    var list = ws.toplevels.values.map(function(tl) {
      var ipc = tl.lastIpcObject || {}
      return {
        address: String(tl.address),
        appId: (tl.wayland && tl.wayland.appId) || ipc["class"] || "",
        title: String(tl.title || ""),
        at: ipc.at || [1e9, 1e9]
      }
    })
    list.sort(function(l, r) { return (l.at[0] - r.at[0]) || (l.at[1] - r.at[1]) })
    return list.slice(0, maxIcons)
  }

  // ------------------------------------------------------------ icons

  // Web app windows of any Chromium browser carry the class Omarchy wrote
  // as StartupWMClass with a "chrome-" prefix, e.g. brave-x.com__-Default.
  function appInfo(appId) {
    var entry = DesktopEntries.heuristicLookup(appId.replace(/^(brave|chromium|msedge|vivaldi|helium)-/, "chrome-"))
      || DesktopEntries.heuristicLookup(appId)
    var icon = entry && entry.icon ? entry.icon : appId
    return {
      source: icon.charAt(0) === "/" ? Util.fileUrl(icon) : Quickshell.iconPath(icon, true),
      name: entry && entry.name ? entry.name : appId.split(".").pop()
    }
  }

  // ------------------------------------------------------------ actions

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  function focusWorkspace(id) {
    if (id === activeId) return
    if (blockOf(id) === block) dispatch("o.workspaces.focus(" + slotOf(id) + ", " + JSON.stringify(monitorName) + ")")
    else dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  function focusWindow(address) {
    dispatch("hl.dsp.focus({ window = \"address:0x" + address.replace(/^0x/, "") + "\" })")
  }

  property real wheelAccumulator: 0

  function scrollBy(delta) {
    var wheel = Util.wheelSteps(wheelAccumulator, delta)
    wheelAccumulator = wheel.remainder
    var index = workspaceIds.indexOf(activeId)
    if (wheel.steps === 0 || index === -1) return
    focusWorkspace(workspaceIds[Util.clamp(index - wheel.steps, 0, workspaceIds.length - 1)])
  }

  // ------------------------------------------------------------ Hyprland sync

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
      case "openwindow":
      case "closewindow":
      case "movewindowv2":
      case "changefloatingmode":
        // Window positions (lastIpcObject.at) only arrive on a refresh.
        refreshTimer.restart()
        break
      case "workspacev2":
        // Quickshell credits every switch to the focused monitor; bars share
        // the answer, so only the focused one asks Hyprland for the truth.
        if (!root.monitor || !root.monitor.focused) break
      case "moveworkspacev2":
      case "changeworkspaceid":
      case "configreloaded":
      case "monitoraddedv2":
      case "monitorremovedv2":
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
        break
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 150
    onTriggered: Hyprland.refreshToplevels()
  }

  Component.onCompleted: Hyprland.refreshToplevels()

  // ------------------------------------------------------------ view

  implicitWidth: pills.implicitWidth
  implicitHeight: root.barSize

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: function(wheel) { root.scrollBy(wheel.angleDelta.y || wheel.angleDelta.x) }
  }

  Row {
    id: pills
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    Repeater {
      model: ScriptModel { values: root.workspaceIds }

      delegate: Rectangle {
        id: pill

        required property int modelData
        readonly property var windows: root.windowsOf(modelData)
        readonly property bool active: modelData === root.activeId
        readonly property bool showIcons: windows.length > 0 && (active || !root.activeOnly)

        width: content.implicitWidth + Style.space(14)
        height: root.pillHeight
        radius: root.rounded ? Math.round(height * 0.32) : 0
        color: Util.alpha(root.fg, active ? 0.18 : pillMouse.containsMouse ? 0.12 : windows.length > 0 ? 0.06 : 0)

        // Reaches the bar edges so the whole bar height is clickable.
        MouseArea {
          id: pillMouse
          anchors.fill: parent
          anchors.topMargin: -(root.barSize - root.pillHeight) / 2
          anchors.bottomMargin: anchors.topMargin
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusWorkspace(pill.modelData)
        }

        Row {
          id: content
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.blockOf(pill.modelData) === root.block ? String(root.slotOf(pill.modelData) % 10) : String(pill.modelData)
            textFormat: Text.PlainText
            color: root.fg
            opacity: pill.active || pill.windows.length > 0 ? 1 : 0.5
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: pill.active
          }

          Repeater {
            // Keyed by address so icons survive list rebuilds.
            model: ScriptModel { values: pill.showIcons ? pill.windows : []; objectProp: "address" }

            delegate: Rectangle {
              id: appIcon

              required property var modelData
              // Bound to the id string, so lookups rerun only when it changes.
              readonly property string appId: modelData.appId
              readonly property var info: root.appInfo(appId)
              readonly property bool focused: pill.active && modelData.address === root.activeAddress
              readonly property bool tooltipHovered: iconMouse.containsMouse

              anchors.verticalCenter: parent.verticalCenter
              width: root.iconPx + Style.space(4)
              height: width
              radius: root.rounded ? Style.space(5) : 0
              color: (focused && pill.windows.length > 1) || iconMouse.containsMouse ? Util.alpha(root.fg, 0.18) : "transparent"

              Image {
                id: img
                anchors.centerIn: parent
                width: root.iconPx
                height: root.iconPx
                source: appIcon.info.source
                sourceSize: Qt.size(root.iconPx * 2, root.iconPx * 2)
                asynchronous: true
                visible: status === Image.Ready
                // Other windows on the active workspace are dimmed.
                opacity: pill.active && !appIcon.focused && !iconMouse.containsMouse ? 0.5 : 1
              }

              // Letter tile when no icon resolves.
              Rectangle {
                anchors.fill: img
                visible: !img.visible
                opacity: img.opacity
                radius: root.rounded ? width / 4 : 0
                color: Util.alpha(root.fg, 0.2)

                Text {
                  anchors.centerIn: parent
                  text: appIcon.info.name.charAt(0).toUpperCase()
                  textFormat: Text.PlainText
                  color: root.fg
                  font.pixelSize: Math.round(root.iconPx * 0.62)
                  font.bold: true
                }
              }

              MouseArea {
                id: iconMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWindow(appIcon.modelData.address)
                onContainsMouseChanged: {
                  if (!root.bar) return
                  if (containsMouse) root.bar.showTooltip(appIcon, appIcon.modelData.title || appIcon.info.name)
                  else root.bar.hideTooltip(appIcon)
                }
              }
            }
          }
        }
      }
    }
  }
}
