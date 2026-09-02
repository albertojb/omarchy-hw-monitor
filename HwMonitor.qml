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

  // Consumer-side limits for the stats sample. stats.sh enforces the same
  // caps before serializing; these are re-checked here so nothing the
  // producer emits is trusted on its own.
  readonly property int maxSampleBytes: 16384
  readonly property int maxDevices: 8
  readonly property int maxNameLength: 24
  readonly property int maxTextLength: 32
  readonly property int maxPathLength: 255

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

  // Validates one stats sample against the expected schema. Returns null
  // when anything is off, so a bad sample is dropped whole rather than
  // partially applied.
  function validateSample(d) {
    function pct(v) {
      return (typeof v === "number" && isFinite(v)) ? Math.max(0, Math.min(100, Math.round(v))) : null
    }
    function str(v, max) {
      return (typeof v === "string" && v.length <= max && !/[\x00-\x1f\x7f]/.test(v)) ? v : null
    }
    if (!d || typeof d !== "object" || Array.isArray(d)) return null
    var cpu = pct(d.cpu), mem = pct(d.mem), memText = str(d.memText, root.maxTextLength)
    if (cpu === null || mem === null || memText === null) return null
    var storage = []
    if (Array.isArray(d.storage)) {
      for (var i = 0; i < d.storage.length && storage.length < root.maxDevices; i++) {
        var e = d.storage[i]
        if (!e || typeof e !== "object" || Array.isArray(e)) continue
        var name = str(e.name, root.maxNameLength)
        var text = str(e.text, root.maxTextLength)
        var path = str(e.path, root.maxPathLength)
        var p = pct(e.pct)
        if (name === null || text === null || path === null || p === null) continue
        if (path !== "/" && !/^\/(run\/media|media|mnt)\/./.test(path)) continue
        storage.push({ name: name, pct: p, text: text, path: path })
      }
    }
    return { cpu: cpu, mem: mem, memText: memText, storage: storage }
  }

  Process {
    id: probe
    command: ["sh", root.pluginDir + "stats.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (text.length > root.maxSampleBytes) return
        var sample = null
        try { sample = root.validateSample(JSON.parse(text)) } catch (e) {}
        if (sample === null) return
        root.cpu = sample.cpu
        root.mem = sample.mem
        root.memText = sample.memText
        root.storage = sample.storage
      }
    }
  }

  Process {
    id: writer
    command: ["perl", root.pluginDir + "position.pl", "write",
              root.positionFile, String(root.posX), String(root.posY)]
  }

  Process {
    id: opener
    command: ["setsid", "uwsm-app", "--", "nautilus", "--new-window", root.openPath]
  }

  Process {
    id: reader
    running: true
    command: ["perl", root.pluginDir + "position.pl", "read", root.positionFile]
    stdout: StdioCollector {
      onStreamFinished: {
        // position.pl prints nothing unless the file held exactly two
        // non-negative integers, so this only re-checks the shape.
        var m = /^([0-9]{1,6}) ([0-9]{1,6})$/.exec(String(text).trim())
        if (m === null) return
        root.posX = parseInt(m[1], 10)
        root.posY = parseInt(m[2], 10)
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

                // Labels and values can come from device metadata, so they
                // are rendered as plain text, never as rich text.
                Text {
                  id: valueText
                  anchors.right: parent.right
                  text: row.modelData.value
                  textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
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
