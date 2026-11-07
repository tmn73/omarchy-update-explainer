import QtQuick
import qs.Commons as Commons
import qs.Commons

// One thing to do around the update, inside the folded row at the end of the
// report: the effect in bold, what to do, then the command. No alarm color:
// the row sits after the good news. Plain text only.
Column {
  id: root

  property string title: ""
  property string detail: ""
  property string command: ""
  property string fontFamily: Style.font.family

  width: parent ? parent.width : 0
  spacing: Style.space(4)

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: root.title
    color: Commons.Color.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: root.detail !== ""
    wrapMode: Text.WordWrap
    text: root.detail
    color: Commons.Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Rectangle {
    visible: root.command !== ""
    width: parent.width
    height: commandText.implicitHeight + Style.space(12)
    radius: Style.space(6)
    color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.06)

    Text {
      id: commandText

      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.WrapAnywhere
      text: root.command
      color: Commons.Color.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
