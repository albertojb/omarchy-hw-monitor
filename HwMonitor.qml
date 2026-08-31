import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons

Item {
  id: root

  property int cpu: 0
  property int mem: 0
  property string memText: ""
  property var storage: []

  // Widget position, in pixels from the top-left of each screen. -1 means
  // "not placed yet"; it then sits in the bottom-right corner.
  property int posX: -1
  property int posY: -1

  readonly property int cardWidth: 260
  readonly property int edgeMargin: Style.spacing.huge
  readonly property int minY: Style.bar.sizeHorizontal + Style.spacing.sm
  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")
  readonly property string positionFile: Quickshell.env("HOME") + "/.local/state/omarchy/albertojb-hwmonitor-position"

  readonly property var rows: [
    { name: "CPU", pct: root.cpu, value: root.cpu + "%", path: "" },
    { name: "MEMORY", pct: root.mem, value: root.memText, path: "" }
  ].concat((root.storage || []).map(function (entry) {
    return { name: entry.name, pct: entry.pct, value: entry.text, path: entry.path }
  }))

  // Where a storage row should open. Bound into `opener` below.
  property string openPath: ""

  function savePosition() {
    if (!writer.running) writer.running = true
  }

  Process {
    id: probe
    command: ["sh", root.pluginDir + "stats.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          root.cpu = d.cpu
          root.mem = d.mem
          root.memText = d.memText
          root.storage = d.storage || []
        } catch (e) {}
      }
    }
  }

  Process {
    id: writer
    command: ["sh", root.pluginDir + "position.sh", "write",
              root.positionFile, String(root.posX), String(root.posY)]
  }

  Process {
    id: opener
    command: ["setsid", "uwsm-app", "--", "nautilus", "--new-window", root.openPath]
  }

  Process {
    id: reader
    running: true
    command: ["sh", root.pluginDir + "position.sh", "read", root.positionFile]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = String(text).trim().split(/\s+/)
        if (parts.length === 2) {
          var x = parseInt(parts[0], 10)
          var y = parseInt(parts[1], 10)
          if (isFinite(x) && isFinite(y)) {
            root.posX = x
            root.posY = y
          }
        }
      }
    }
  }


  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!probe.running) probe.running = true
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      // The surface spans the whole output and never moves, so pointer
      // coordinates during a drag stay in one stable frame of reference.
      // Only the card itself takes input; `mask` lets the rest through.
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      mask: Region { item: card }

      WlrLayershell.namespace: "albertojb-hwmonitor"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Rectangle {
        id: card
        width: root.cardWidth
        height: implicitHeight
        x: root.posX >= 0 ? Math.max(0, Math.min(root.posX, panel.width - width))
                          : panel.width - width - root.edgeMargin
        y: root.posY >= 0 ? Math.max(root.minY, Math.min(root.posY, panel.height - height))
                          : panel.height - height - root.edgeMargin
        radius: Style.spacing.lg
        color: Color.popups.background
        border.width: Style.spacing.hairline
        border.color: Color.popups.border
        implicitHeight: grip.height + column.implicitHeight + Style.spacing.xxl

        // Drag handle. Moves the card inside the fixed full-screen surface.
        MouseArea {
          id: grip
          width: Style.spacing.huge + Style.spacing.xl
          height: Style.spacing.huge
          anchors.top: parent.top
          anchors.right: parent.right
          cursorShape: Qt.SizeAllCursor
          hoverEnabled: true

          property real grabX: 0
          property real grabY: 0

          onPressed: function (mouse) {
            var p = mapToItem(card.parent, mouse.x, mouse.y)
            grabX = p.x - card.x
            grabY = p.y - card.y
            root.posX = card.x
            root.posY = card.y
          }
          onPositionChanged: function (mouse) {
            if (!pressed) return
            var p = mapToItem(card.parent, mouse.x, mouse.y)
            root.posX = Math.max(0, Math.min(p.x - grabX, panel.width - card.width))
            root.posY = Math.max(root.minY, Math.min(p.y - grabY, panel.height - card.height))
          }
          onReleased: root.savePosition()

          Grid {
            anchors.centerIn: parent
            columns: 2
            rowSpacing: Style.spacing.xs
            columnSpacing: Style.spacing.xs
            opacity: grip.containsMouse || grip.pressed ? 0.9 : 0.35
            Behavior on opacity { NumberAnimation { duration: 150 } }

            Repeater {
              model: 6
              Rectangle {
                width: Style.spacing.xxs
                height: width
                radius: width / 2
                color: Color.popups.text
              }
            }
          }
        }

        Column {
          id: column
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: grip.bottom
          anchors.leftMargin: Style.spacing.xxl
          anchors.rightMargin: Style.spacing.xxl
          spacing: Style.spacing.lg

          Repeater {
            model: root.rows

            Column {
              id: row
              required property var modelData
              width: column.width
              spacing: Style.spacing.xs

              Item {
                width: parent.width
                height: label.implicitHeight

                Text {
                  id: valueText
                  anchors.right: parent.right
                  text: row.modelData.value
                  color: Color.popups.text
                  font.family: Style.font.resolvedFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  id: label
                  anchors.left: parent.left
                  anchors.right: valueText.left
                  anchors.rightMargin: Style.spacing.md
                  text: row.modelData.name
                  color: Color.popups.text
                  opacity: 0.7
                  font.family: Style.font.resolvedFamily
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                  elide: Text.ElideRight
                }
              }

              Rectangle {
                id: track
                width: parent.width
                height: Style.spacing.sm
                radius: height / 2
                color: Qt.rgba(Color.popups.text.r, Color.popups.text.g, Color.popups.text.b, 0.15)

                Rectangle {
                  width: parent.width * Math.max(0, Math.min(100, row.modelData.pct)) / 100
                  height: parent.height
                  radius: parent.radius
                  color: Color.popups.border
                  Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }

                // Storage rows open their mount point in Files.
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -Style.spacing.sm
                  enabled: row.modelData.path !== ""
                  hoverEnabled: enabled
                  cursorShape: Qt.PointingHandCursor
                  onEntered: track.opacity = 0.7
                  onExited: track.opacity = 1
                  onClicked: {
                    root.openPath = row.modelData.path
                    opener.running = true
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
