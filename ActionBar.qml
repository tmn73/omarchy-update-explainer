import QtQuick
import qs.Commons as Commons
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The two actions at the bottom of the panel. The primary button explains the
// updates with the default agent, or asks the user to choose one when none is
// set. It never starts anything on its own: the user clicks.
Column {
  id: root

  property string agent: ""
  property bool busy: false
  property var summary: null
  property string explainError: ""
  // Keyboard cursor: -1 none, 0 the primary button, 1 Update now.
  property int cursor: -1
  property string fontFamily: Style.font.family

  signal explainRequested()
  signal chooseRequested()
  signal updateRequested()

  spacing: Style.space(12)

  function primaryAction() {
    if (!primary.enabled) return
    if (agent === "") chooseRequested()
    else explainRequested()
  }

  // Tab and Shift+Tab move the cursor between the two buttons.
  function moveFocus(direction) {
    cursor = cursor < 0 ? (direction > 0 ? 0 : 1) : (cursor + direction + 2) % 2
  }

  // Enter and Space act on the cursor, or on the primary button when none is set.
  function activateFocused() {
    if (cursor === 1) updateRequested()
    else primaryAction()
  }

  AgentNotice {
    width: parent.width
    visible: root.agent === ""
    fontFamily: root.fontFamily
  }

  Button {
    id: primary

    width: parent.width
    height: Math.max(Style.space(48), 48)
    text: Model.explainLabel(root.agent, root.busy)
    focusable: true
    hasCursor: root.cursor === 0
    enabled: Model.explainEnabled(root.summary, root.agent, root.busy)
    opacity: enabled ? 1 : 0.5
    background: Commons.Color.accent
    foreground: Commons.Color.background
    fontFamily: root.fontFamily
    fontSize: Style.font.body
    radius: Style.space(10)

    Accessible.role: Accessible.Button
    Accessible.name: text

    onClicked: root.primaryAction()
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: root.agent !== ""
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: qsTr("Opens your default agent in a terminal. You start it, nothing runs in the background.")
    color: Commons.Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Button {
    width: parent.width
    height: Math.max(Style.space(44), 44)
    text: qsTr("Update now")
    focusable: true
    hasCursor: root.cursor === 1
    bordered: true
    fontFamily: root.fontFamily
    fontSize: Style.font.body
    radius: Style.space(10)

    Accessible.role: Accessible.Button
    Accessible.name: text

    onClicked: root.updateRequested()
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: root.explainError !== ""
    wrapMode: Text.WordWrap
    text: root.explainError
    color: Commons.Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
