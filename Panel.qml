import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Bar entry point for the update explainer.
//
// This file owns the bar button and the popup layout. Update data, the report
// and process control belong to Service.qml, what the popup shows to
// UpdatesBody.qml, the buttons to ActionBar.qml, the wording to Model.js.
Panel {
  id: root

  moduleName: "tmn73.update-explainer"
  ipcTarget: "tmn73.update-explainer"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool hasSummary: updates.shown !== null
  // Held data stays valid after a failed refresh, so it keeps showing.
  readonly property bool hasUpdates: Model.hasUpdates(updates.shown)

  // Nerd Font glyphs. A pending check shows one per update type (Model.kindOf).
  readonly property var glyphs: ({
    current: "\uf021", pending: "\uf021", checking: "\uf021", error: "\uf071",
    reboot: "\uf01e", omarchy: "\uf0aa", system: "\uf1b2", tools: "\uf121", plugins: "\uf12e", settings: "\uf013", report: "\uf15c"
  })

  // True while the popup shows the settings screen.
  property bool settingsOpen: false
  // Empty slot when up to date. Stays visible while the popup is open.
  visible: root.opened || Model.barVisible(updates.barStatus, root.hasSummary, updates.lastFailed, updates.reportMark)

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
    panelOpen: root.opened
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { updates.refresh(); return "ok" }
    function status(): string { return updates.status }
  }

  BarButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    text: root.glyphs[Model.iconKey(updates.shown, updates.barStatus, updates.barTypes, updates.reportMark)] || root.glyphs.current
    status: updates.status
    mark: updates.reportMark
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
    contentHeight: panel.fittedContentHeight(content.implicitHeight + (footer.visible ? footer.height + Style.space(12) : 0), Style.space(640))

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

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.visible ? footer.top : parent.bottom
        anchors.bottomMargin: footer.visible ? Style.space(12) : 0
        spacing: Style.space(18)

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
          types: updates.barTypes
          reportInTerminal: updates.reportInTerminal
          reportOnIcon: updates.reportOnIcon
          reportNotify: updates.reportNotify
          onToggled: function (key, fallback) { store.toggle(key, fallback) }
        }

        UpdatesBody {
          width: parent.width
          visible: !root.settingsOpen
          summary: updates.shown
          status: updates.status
          message: updates.message
          fontFamily: root.fontFamily
          report: updates.whatsNew
          reportPhase: updates.whatsNewState
          reportError: updates.whatsNewError
          hasReport: updates.hasReport
          reportStep: updates.reportStep
          reportStartedAt: updates.reportStartedAt
          onPluginsRequested: updates.updatePlugins()
        }
      }

      // The buttons stay at the bottom while the list above scrolls.
      Column {
        id: footer

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: !root.settingsOpen
        spacing: Style.space(12)

        Rectangle {
          width: parent.width
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
        }

        ActionBar {
          id: actions

          width: parent.width
          agent: updates.agent
          busy: updates.busy
          pending: root.hasUpdates
          systemPending: updates.systemPending
          explainError: updates.explainError
          fontFamily: root.fontFamily
          mode: updates.reportMode
          onExplainRequested: { updates.explain(); root.refocus() }
          onAskRequested: { updates.ask(); root.refocus() }
          onChooseRequested: { updates.chooseAgent(); root.refocus() }
          onUpdateRequested: { root.close(); updates.updateNow() }
          onRefreshRequested: { updates.refresh(true); root.refocus() }
        }
      }
    }
  }
}
