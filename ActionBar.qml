import QtQuick
import qs.Commons as Commons
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The actions at the bottom of the panel.
//
// While updates wait: a soft tinted primary button ("Tell me what changes", or
// "Choose an assistant" when no default agent is set) above a solid
// "Update now". In every other state: one outlined "Check again". Nothing here
// starts anything on its own: the user clicks. The agent is never named.
Column {
  id: root

  property string agent: ""
  property bool busy: false
  property bool pending: false
  property string explainError: ""
  property string fontFamily: Style.font.family
  // Keyboard cursor: -1 none, 0 the first button, 1 the second.
  property int cursor: -1
  readonly property int buttonCount: pending ? 2 : 1

  signal explainRequested()
  signal chooseRequested()
  signal updateRequested()
  signal refreshRequested()

  spacing: Style.space(10)

  function firstAction() {
    if (!pending) refreshRequested()
    else if (busy) return
    else if (agent === "") chooseRequested()
    else explainRequested()
  }

  // Tab and Shift+Tab move the cursor between the buttons.
  function moveFocus(direction) {
    var n = buttonCount
    cursor = cursor < 0 ? (direction > 0 ? 0 : n - 1) : (cursor + direction + n) % n
  }

  // Enter and Space act on the cursor, or on the first button when none is set.
  function activateFocused() {
    if (pending && cursor === 1) updateRequested()
    else firstAction()
  }

  AgentNotice {
    width: parent.width
    visible: root.pending && root.agent === ""
    fontFamily: root.fontFamily
  }

  TintButton {
    width: parent.width
    visible: root.pending
    text: Model.explainLabel(root.agent, root.busy)
    hasCursor: root.cursor === 0
    enabled: !root.busy
    opacity: enabled ? 1 : 0.5
    fontFamily: root.fontFamily
    onClicked: root.firstAction()
  }

  Button {
    width: parent.width
    height: Math.max(Style.space(44), 44)
    visible: root.pending
    text: qsTr("Update now")
    focusable: true
    hasCursor: root.cursor === 1
    background: Commons.Color.foreground
    foreground: Commons.Color.background
    fontFamily: root.fontFamily
    fontSize: Style.font.body
    radius: Style.space(12)

    Accessible.role: Accessible.Button
    Accessible.name: text

    onClicked: root.updateRequested()
  }

  Button {
    width: parent.width
    height: Math.max(Style.space(44), 44)
    visible: !root.pending
    text: qsTr("Check again")
    focusable: true
    hasCursor: root.cursor === 0
    bordered: true
    fontFamily: root.fontFamily
    fontSize: Style.font.body
    radius: Style.space(12)

    Accessible.role: Accessible.Button
    Accessible.name: text

    onClicked: root.refreshRequested()
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
