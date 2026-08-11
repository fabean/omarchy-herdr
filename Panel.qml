import QtQuick
import QtQuick.Controls
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
  readonly property string barText: {
    if (!online) return "󰚩 ×"
    if (blocked > 0) return "󰚩 " + blocked
    if (working > 0) return "󰚩 " + working
    return "󰚩 " + total
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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

  function loadRunningColor(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*green\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) {
        runningColor = match[1]
        return
      }
    }
    runningColor = Color.accent
  }

  function agentColor(status, fallback) {
    if (status === "blocked") return urgent
    if (status === "working") return runningColor
    return fallback
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
    onLoaded: root.loadRunningColor(text())
    onFileChanged: reload()
    onLoadFailed: root.runningColor = Color.accent
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
    text: root.barText
    active: root.activeCount > 0
    activeColor: root.statusColor
    fontSize: Style.font.bodySmall
    horizontalMargin: 3.5
    tooltipText: ""

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
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
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: agentRow.agent.status === "working" || agentRow.agent.status === "blocked"
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: String(agentRow.agent.paneId || agentRow.agent.cwd || "")
          textFormat: Text.PlainText
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
        textFormat: Text.PlainText
        color: root.agentColor(String(agentRow.agent.status || "unknown"), root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: agentRow.agent.status === "blocked"
      }
    }
  }
}
