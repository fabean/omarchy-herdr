import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "io.github.fabean.herdr"
  ipcTarget: "io.github.fabean.herdr"

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string stateCommand: (Quickshell.env("HOME") || "") + "/.config/omarchy/plugins/io.github.fabean.herdr/state.sh"
  readonly property string themeColorsPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme/colors.toml"
  property color runningColor: Color.accent
  property color doneColor: Color.accent

  // Panel, unlike BarWidget, does not lift these off the bar for us.
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

  property var state: ({
    online: false,
    total: 0,
    working: 0,
    blocked: 0,
    done: 0,
    idle: 0,
    unknown: 0,
    agents: []
  })
  property bool refreshing: false

  readonly property bool online: state && state.online === true
  readonly property int total: Number(state.total || 0)
  readonly property int working: Number(state.working || 0)
  readonly property int blocked: Number(state.blocked || 0)
  readonly property int activeCount: working + blocked
  readonly property var agents: state && Array.isArray(state.agents) ? state.agents : []
  readonly property color statusColor: blocked > 0 ? urgent : (working > 0 ? runningColor : foreground)

  readonly property bool showGlyph: flag("showGlyph", true)
  readonly property bool showCount: flag("showCount", true)
  readonly property bool showDots: flag("showDots", false)
  // With every block off there would be nothing left to click.
  readonly property bool glyphVisible: showGlyph || (!showCount && !showDots)

  // "Pane" holds each dot in place for the life of its pane so only its colour
  // changes; "Status" keeps state.sh's blocked-first order, which reshuffles the
  // row on every state change.
  readonly property string dotOrder: String(root.setting("dotOrder", "Pane")).toLowerCase()
  readonly property var orderedAgents: dotOrder === "status" ? agents : agents.slice().sort(comparePanes)

  readonly property int maxDots: Math.max(1, Math.round(Number(root.setting("maxDots", 8)) || 8))
  readonly property bool pulseBlocked: flag("pulseBlocked", true)
  readonly property var barDots: orderedAgents.length > maxDots ? orderedAgents.slice(0, maxDots) : orderedAgents
  readonly property int hiddenCount: Math.max(0, agents.length - barDots.length)
  readonly property real dotSize: Style.spaceReal(8)
  readonly property real dotGap: Style.space(4)
  readonly property real blockGap: Style.space(6)
  readonly property real barPadding: Style.spaceReal(6)

  readonly property string countText: {
    if (!online) return "×"
    if (blocked > 0) return String(blocked)
    if (working > 0) return String(working)
    return String(total)
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Pane ids are numbered, so "wJ:p10" has to sort after "wJ:p2": every digit
  // run is zero-padded before the ids are compared as plain strings.
  function paneSortKey(agent) {
    var id = String(agent.paneId || agent.cwd || agent.name || "")
    return id.replace(/\d+/g, function(digits) { return ("0000000000" + digits).slice(-10) })
  }

  function comparePanes(left, right) {
    var a = paneSortKey(left)
    var b = paneSortKey(right)
    return a < b ? -1 : (a > b ? 1 : 0)
  }

  // shell.json is hand-editable, so a yes/no setting can arrive as a string.
  function flag(name, fallback) {
    var value = root.setting(name, fallback)
    if (typeof value === "string") {
      var text = value.toLowerCase()
      return text === "true" || text === "yes" || text === "on" || text === "1"
    }
    return value === true
  }

  function parseState(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") state = parsed
    } catch (e) {
      console.warn("io.github.fabean.herdr: invalid state output", e)
    }
  }

  function refresh() {
    if (stateProcess.running) return
    refreshing = true
    stateProcess.running = true
  }

  function resetThemeColors() {
    runningColor = Color.accent
    doneColor = Color.accent
  }

  function loadThemeColors(raw) {
    var lines = String(raw || "").split("\n")
    var found = ({})
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) found[match[1]] = match[2]
    }
    runningColor = found["green"] || Color.accent
    doneColor = found["blue"] || found["cyan"] || Color.accent
  }

  function agentColor(status, fallback) {
    if (status === "blocked") return urgent
    if (status === "working") return runningColor
    if (status === "done") return doneColor
    return fallback
  }

  // Filled is a state that wants something from you, so the dots still read
  // apart when the colours do not.
  function dotFilled(status) {
    return status === "blocked" || status === "working" || status === "done"
  }

  function barSummary() {
    if (!online) return "Herdr is not running"
    if (total === 0) return "No agents"
    var parts = []
    if (blocked > 0) parts.push(blocked + " blocked")
    if (working > 0) parts.push(working + " working")
    if (Number(state.done || 0) > 0) parts.push(Number(state.done) + " done")
    if (Number(state.idle || 0) > 0) parts.push(Number(state.idle) + " idle")
    if (Number(state.unknown || 0) > 0) parts.push(Number(state.unknown) + " unknown")
    // Agents past the dot cap have no dot, so they are accounted for here.
    if (hiddenCount > 0) parts.push("+" + hiddenCount + " beyond the dot cap")
    return parts.join("  ·  ")
  }

  function statusGlyph(status) {
    if (status === "working") return "󰐊"
    if (status === "blocked") return ""
    if (status === "done") return ""
    if (status === "idle") return "󰒲"
    return "?"
  }

  function statusLabel(status) {
    var text = String(status || "unknown")
    return text.charAt(0).toUpperCase() + text.slice(1)
  }

  function heroDetail() {
    if (!online) return "Offline"
    if (activeCount > 0) return activeCount + " active"
    return total + " agents"
  }

  onOpenedChanged: if (opened) {
    refresh()
    if (agentFlick) agentFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Process {
    id: stateProcess
    command: [root.stateCommand]
    running: false

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseState(text)
    }

    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode !== 0) console.warn("io.github.fabean.herdr: state command exited", exitCode)
    }
  }

  FileView {
    path: root.themeColorsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeColors(text())
    onFileChanged: reload()
    onLoadFailed: root.resetThemeColors()
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    // barContent replaces the label, so the button is left with the press
    // handling, the tooltip, and the slot geometry.
    labelVisible: false
    hasVisualContent: true
    active: root.activeCount > 0
    activeColor: root.statusColor
    // A dots-only widget has no text to say it is offline.
    dimmed: !root.online
    fontSize: Style.font.bodySmall
    fixedWidth: root.vertical ? root.barSize : Math.max(12, barContent.implicitWidth + root.barPadding * 2)
    fixedHeight: root.vertical ? Math.max(12, barContent.implicitHeight + root.barPadding * 2) : root.barSize
    tooltipText: root.barSummary()

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }

    GridLayout {
      id: barContent
      anchors.centerIn: parent
      // A block that is switched off is invisible, which the layout skips.
      columns: root.vertical ? 1 : 3
      columnSpacing: root.blockGap
      rowSpacing: root.blockGap

      Text {
        visible: root.glyphVisible
        Layout.alignment: Qt.AlignCenter
        text: "󰚩"
        color: root.statusColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      Text {
        visible: root.showCount
        Layout.alignment: Qt.AlignCenter
        text: root.countText
        color: root.statusColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      GridLayout {
        visible: root.showDots
        Layout.alignment: Qt.AlignCenter
        columns: root.vertical ? 1 : root.maxDots + 1
        columnSpacing: root.dotGap
        rowSpacing: root.dotGap

        StatusDot {
          // An empty or absent herd draws no dot, and a widget with nothing in
          // it cannot be clicked, so one quiet dot holds the slot.
          visible: !root.online || root.agents.length === 0
          Layout.alignment: Qt.AlignCenter
          status: "empty"
        }

        Repeater {
          model: root.online ? root.barDots : []

          StatusDot {
            required property var modelData
            Layout.alignment: Qt.AlignCenter
            status: String(modelData.status || "unknown")
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) {
          agentFlick.contentY = Math.max(0, Math.min(
            agentFlick.contentY + dy * Style.space(58),
            Math.max(0, agentFlick.contentHeight - agentFlick.height)
          ))
        }
      }
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh() }

      Flickable {
        id: agentFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: agentFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Herdr"
            meta: root.online ? (root.activeCount > 0 ? "AGENTS IN MOTION" : "HERD AT REST") : "NOT RUNNING"
            detail: root.heroDetail()
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                text: "󰚩"
                color: root.statusColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            visible: !root.online
            width: parent.width
            text: "Herdr is not running"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            topPadding: Style.space(24)
            bottomPadding: Style.space(24)
          }

          PanelSeparator {
            visible: root.online
            foreground: root.foreground
          }

          Column {
            visible: root.online
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "OVERVIEW"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              SummaryCell { label: "Working"; value: root.working; active: root.working > 0; runningCell: true }
              SummaryCell { label: "Blocked"; value: root.blocked; active: root.blocked > 0; urgentCell: true }
              SummaryCell { label: "Done"; value: Number(root.state.done || 0) }
              SummaryCell { label: "Idle"; value: Number(root.state.idle || 0) }
            }
          }

          PanelSeparator {
            visible: root.online && root.agents.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.online && root.agents.length > 0
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              width: parent.width
              text: "AGENTS  ·  " + root.total
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.agents

              AgentRow {
                width: parent ? parent.width : 0
                agent: modelData
                rowIndex: index
              }
            }
          }
        }
      }
    }
  }

  component StatusDot: Rectangle {
    id: dot
    property string status: "unknown"

    readonly property bool filled: root.dotFilled(dot.status)
    readonly property color tint: root.agentColor(dot.status, root.dim)

    implicitWidth: root.dotSize
    implicitHeight: root.dotSize
    radius: width / 2
    antialiasing: true
    color: dot.filled ? dot.tint : "transparent"
    border.width: dot.filled ? 0 : Math.max(1, Math.round(root.dotSize / 4))
    border.color: dot.tint

    Behavior on color {
      ColorAnimation { duration: 160 }
    }

    // The animation owns opacity, so a dot that stops pulsing has to be put
    // back to full or it keeps whatever value the fade left behind.
    SequentialAnimation on opacity {
      id: pulse
      running: root.pulseBlocked && dot.status === "blocked"
      loops: Animation.Infinite
      onRunningChanged: if (!pulse.running) dot.opacity = 1
      NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
    }
  }

  component SummaryCell: Rectangle {
    id: summaryCell
    property string label: ""
    property int value: 0
    property bool active: false
    property bool urgentCell: false
    property bool runningCell: false

    width: (parent.width - parent.spacing * 3) / 4
    implicitHeight: summaryLabels.implicitHeight + Style.space(12)
    radius: Style.cornerRadius
    color: summaryCell.active
      ? Style.selectedFillFor(summaryCell.urgentCell ? root.urgent : root.foreground, Color.accent)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.035)

    Column {
      id: summaryLabels
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: summaryCell.value
        color: summaryCell.active
          ? (summaryCell.urgentCell ? root.urgent : (summaryCell.runningCell ? root.runningColor : root.foreground))
          : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: summaryCell.label.toUpperCase()
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  component AgentRow: Column {
    id: agentRow
    property var agent: ({})
    property int rowIndex: 0

    spacing: Style.space(8)

    PanelSeparator {
      visible: agentRow.rowIndex > 0
      foreground: root.foreground
      strength: 0.07
    }

    Item {
      width: agentRow.width
      implicitHeight: Math.max(agentGlyph.implicitHeight, agentLabels.implicitHeight, agentStatus.implicitHeight)

      Text {
        id: agentGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.statusGlyph(String(agentRow.agent.status || "unknown"))
        color: root.agentColor(String(agentRow.agent.status || "unknown"), root.foreground)
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
      }

      Column {
        id: agentLabels
        anchors.left: agentGlyph.right
        anchors.leftMargin: Style.space(10)
        anchors.right: agentStatus.left
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: String(agentRow.agent.name || "Agent")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: agentRow.agent.status === "working" || agentRow.agent.status === "blocked"
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: String(agentRow.agent.paneId || agentRow.agent.cwd || "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      Text {
        id: agentStatus
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.statusLabel(String(agentRow.agent.status || "unknown"))
        color: root.agentColor(String(agentRow.agent.status || "unknown"), root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: agentRow.agent.status === "blocked"
      }
    }
  }
}
