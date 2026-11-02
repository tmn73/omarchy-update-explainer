import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar entry point for the update explainer.
//
// This file owns the bar button and the popup layout. Update data and process
// control belong to Service.qml, source rows to SourceSection.qml, the verdict
// to VerdictBlock.qml, the buttons to ActionBar.qml, and the wording to
// Model.js.
Panel {
  id: root

  moduleName: "tmn73.update-explainer"
  ipcTarget: "tmn73.update-explainer"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool hasSummary: updates.summary !== null
  // Held data stays valid after a failed refresh, so it keeps showing.
  readonly property bool hasUpdates: Model.hasUpdates(updates.summary)
  readonly property var verdictParts: Model.panelVerdict(updates.summary, updates.status, updates.message)

  // Nerd Font glyphs. A pending check shows one per update type (Model.kindOf).
  readonly property var glyphs: ({
    current: "\uf021", pending: "\uf021", checking: "\uf021", error: "\uf071",
    reboot: "\uf01e", omarchy: "\uf0aa", system: "\uf1b2", tools: "\uf121", settings: "\uf013"
  })

  // True while the popup shows the settings screen.
  property bool settingsOpen: false
  // Empty slot when up to date. Stays visible while the popup is open.
  visible: root.opened || Model.barVisible(updates.barStatus, root.hasSummary, updates.lastFailed)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // Clicking a button gives it focus, and it may then hide or go disabled, so
  // Escape, R and Tab would stop working. Hand focus back to the key catcher.
  function refocus() {
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  onOpenedChanged: {
    if (opened) {
      root.settingsOpen = false
      actions.cursor = -1
      updates.refresh()
      root.refocus()
    }
  }

  SettingsStore {
    id: store

    owner: root
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
    text: root.glyphs[Model.iconKey(updates.summary, updates.barStatus, updates.barTypes)] || root.glyphs.current
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
      onCloseRequested: {
        if (root.settingsOpen) root.settingsOpen = false
        else root.close()
      }
      onTabRequested: function (direction) { actions.moveFocus(direction) }
      onActivateRequested: actions.activateFocused()
      onTextKey: function (character) {
        if (String(character || "").toLowerCase() === "r")
          updates.refresh()
      }

      ScrollBody {
        id: content

        anchors.fill: parent
        spacing: Style.space(20)

        PanelHeader {
          width: parent.width
          foreground: root.foreground
          fontFamily: root.fontFamily
          title: root.settingsOpen ? qsTr("Settings") : qsTr("Updates")
          fetchedAt: updates.fetchedAt
          gearGlyph: root.glyphs.settings
          settingsOpen: root.settingsOpen
          onGearClicked: { root.settingsOpen = !root.settingsOpen; root.refocus() }
        }

        SettingsView {
          width: parent.width
          visible: root.settingsOpen
          foreground: root.foreground
          fontFamily: root.fontFamily
          showOmarchy: updates.barTypes.omarchy
          showSystem: updates.barTypes.system
          showTools: updates.barTypes.tools
          onToggled: function (key) { store.toggle(key, true) }
        }

        VerdictBlock {
          width: parent.width
          visible: !root.settingsOpen
          title: root.verdictParts.title
          detail: root.verdictParts.detail
          tone: root.verdictParts.tone
          fontFamily: root.fontFamily
        }

        Column {
          width: parent.width
          spacing: Style.space(16)
          visible: root.hasUpdates && !root.settingsOpen

          Repeater {
            model: root.hasSummary ? Model.sections(updates.summary) : []

            delegate: SourceSection {
              required property var modelData

              width: parent.width
              label: modelData.label
              rows: modelData.rows
              more: modelData.more
              fontFamily: root.fontFamily
            }
          }
        }

        ActionBar {
          id: actions

          width: parent.width
          visible: !root.settingsOpen
          agent: updates.agent
          busy: updates.busy
          pending: root.hasUpdates
          explainError: updates.explainError
          fontFamily: root.fontFamily
          onExplainRequested: { updates.explain(); root.refocus() }
          onChooseRequested: { updates.chooseAgent(); root.refocus() }
          onUpdateRequested: { updates.updateNow(); root.refocus() }
          onRefreshRequested: { updates.refresh(true); root.refocus() }
        }
      }
    }
  }
}
