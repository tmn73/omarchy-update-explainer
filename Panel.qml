import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar entry point for the update explainer.
//
// This file owns the bar button and the popup layout. Update data and process
// control belong to Service.qml, row drawing to SourceList.qml, the buttons to
// ActionBar.qml, and the wording to Model.js.
Panel {
  id: root

  moduleName: "tmn73.update-explainer"
  ipcTarget: "tmn73.update-explainer"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool hasSummary: updates.summary !== null

  // Nerd Font glyphs: quiet check, refresh arrow, spinner, warning.
  readonly property var glyphs: ({ current: "", pending: "", checking: "", error: "" })

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function ageText() {
    if (updates.fetchedAt === "") return ""
    var then = Date.parse(updates.fetchedAt)
    if (isNaN(then)) return ""
    var minutes = Math.max(0, Math.round((Date.now() - then) / 60000))
    return minutes < 1 ? qsTr("checked just now") : qsTr("checked %1 min ago").arg(minutes)
  }

  onOpenedChanged: {
    if (opened) {
      updates.refresh()
      Qt.callLater(function () { keyCatcher.forceActiveFocus() })
    }
  }

  Service {
    id: updates

    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { updates.refresh(); return "ok" }
    function status(): string { return updates.status }
  }

  BarIconButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    text: root.glyphs[updates.status] || root.glyphs.current
    labelText: updates.status === "pending" && updates.summary ? String(updates.summary.total) : ""
    active: updates.status === "error"
    opacity: updates.status === "checking" ? 0.5 : 1
    tooltipText: updates.tooltip
    Accessible.name: updates.tooltip
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton)
        updates.refresh()
      else
        root.toggle()
    }

    Rectangle {
      visible: updates.status === "pending"
      width: Style.space(6)
      height: width
      radius: width / 2
      color: Commons.Color.accent
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(2)
    }
  }

  KeyboardPanel {
    id: panel

    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher

      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function (character) {
        if (String(character || "").toLowerCase() === "r")
          updates.refresh()
      }

      Column {
        id: content

        width: parent.width
        spacing: Style.space(20)

        Item {
          width: parent.width
          height: Math.max(Style.space(28), 28)

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: qsTr("Updates")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.ageText()
            color: Commons.Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Rectangle {
          width: parent.width
          height: verdict.implicitHeight + Style.space(32)
          radius: Style.space(10)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)

          Text {
            id: verdict

            textFormat: Text.PlainText
            anchors.fill: parent
            anchors.margins: Style.space(16)
            wrapMode: Text.WordWrap
            text: root.hasSummary && updates.status !== "error"
              ? Model.verdictLine(updates.summary)
              : (updates.message !== "" ? updates.message : updates.tooltip)
            color: updates.status === "error" ? Commons.Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        SourceList {
          width: parent.width
          visible: root.hasSummary
          rows: root.hasSummary ? Model.sourceRows(updates.summary) : []
          fontFamily: root.fontFamily
        }

        ActionBar {
          width: parent.width
          agent: updates.agent
          busy: updates.busy
          fontFamily: root.fontFamily
          onExplainRequested: updates.explain()
          onChooseRequested: updates.chooseAgent()
          onUpdateRequested: updates.updateNow()
        }
      }
    }
  }
}
