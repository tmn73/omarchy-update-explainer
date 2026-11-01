import QtQuick
import qs.Commons as Commons
import qs.Commons
import "Model.js" as Model

// The two actions at the bottom of the panel. The primary button explains the
// updates with the default agent, or asks the user to choose one when none is
// set. It never starts anything on its own: the user clicks.
Column {
  id: root

  property string agent: ""
  property bool busy: false
  property string fontFamily: Style.font.family

  signal explainRequested()
  signal chooseRequested()
  signal updateRequested()

  spacing: Style.space(12)

  Rectangle {
    id: primary

    width: parent.width
    height: Math.max(Style.space(48), 48)
    radius: Style.space(10)
    opacity: root.busy ? 0.5 : 1
    color: Commons.Color.accent

    Accessible.role: Accessible.Button
    Accessible.name: primaryLabel.text

    Text {
      id: primaryLabel

      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: Model.explainLabel(root.agent)
      color: Commons.Color.background
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    TapHandler {
      enabled: !root.busy
      onTapped: root.agent === "" ? root.chooseRequested() : root.explainRequested()
    }
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

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: root.agent === ""
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: qsTr("Omarchy picks none for you. Choose one and the explanation runs in it.")
    color: Commons.Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Rectangle {
    width: parent.width
    height: Math.max(Style.space(44), 44)
    radius: Style.space(10)
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.3)

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Update now")

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: qsTr("Update now")
      color: Commons.Color.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    TapHandler { onTapped: root.updateRequested() }
  }
}
