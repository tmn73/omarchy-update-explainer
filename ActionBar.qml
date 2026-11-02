import QtQuick
import qs.Commons as Commons
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Actions at the bottom of the panel. While updates wait: a tinted "Tell me
// what changes" (or "Choose an assistant" with no default agent) and, for system
// updates only, a solid "Update now". Otherwise an outlined "Check again".
// Nothing starts on its own, and the agent is never named.
Column {
  id: root

  property string agent: ""
  property bool busy: false
  property bool pending: false
  property bool systemPending: true
  property string explainError: ""
  property string fontFamily: Style.font.family
  // Keyboard cursor: -1 none, then 0 or 1.
  property int cursor: -1
  readonly property int buttonCount: pending && systemPending ? 2 : 1
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

  function moveFocus(direction) {
    var n = buttonCount
    cursor = cursor < 0 ? (direction > 0 ? 0 : n - 1) : (cursor + direction + n) % n
  }

  function activateFocused() {
    if (pending && systemPending && cursor === 1) updateRequested()
    else firstAction()
  }

  AgentNotice {
    width: parent.width
    visible: root.pending && root.agent === ""
    fontFamily: root.fontFamily
  }

  // Compact buttons sized to their text; the row wraps when too narrow.
  Flow {
    width: parent.width
    spacing: Style.space(10)

    TintButton {
      visible: root.pending
      text: Model.explainLabel(root.agent, root.busy)
      hasCursor: root.cursor === 0
      enabled: !root.busy
      opacity: enabled ? 1 : 0.5
      fontFamily: root.fontFamily
      onClicked: root.firstAction()
    }

    Button {
      height: Math.max(Style.space(34), 34)
      visible: root.pending && root.systemPending
      text: qsTr("Update now")
      focusable: true
      hasCursor: root.cursor === 1
      background: Commons.Color.foreground
      foreground: Commons.Color.background
      fontFamily: root.fontFamily
      fontSize: Style.font.body
      horizontalPadding: Style.space(16)
      radius: Style.space(8)

      Accessible.role: Accessible.Button
      Accessible.name: text

      onClicked: root.updateRequested()
    }

    Button {
      height: Math.max(Style.space(34), 34)
      visible: !root.pending
      text: qsTr("Check again")
      focusable: true
      hasCursor: root.cursor === 0
      bordered: true
      fontFamily: root.fontFamily
      fontSize: Style.font.body
      horizontalPadding: Style.space(16)
      radius: Style.space(8)

      Accessible.role: Accessible.Button
      Accessible.name: text

      onClicked: root.refreshRequested()
    }
  }

  NoteText {
    width: parent.width
    visible: root.pending && root.agent !== "" && !root.busy
    text: Model.agentNotice()
    fontFamily: root.fontFamily
  }

  NoteText {
    width: parent.width
    visible: root.explainError !== ""
    text: root.explainError
    color: Commons.Color.urgent
    fontFamily: root.fontFamily
  }
}
