import QtQuick
import qs.Commons as Commons
import qs.Commons

// One update inside a source card: the name on the left, "old to new" on the
// right, and a thin line above it.
Item {
  id: row

  property string name: ""
  property string version: ""
  property string fontFamily: Style.font.family

  height: Math.max(Style.space(36), 36)

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 1
    color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)
  }

  Text {
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.leftMargin: Style.space(14)
    anchors.right: versionText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: row.name
    color: Commons.Color.foreground
    font.family: row.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    id: versionText

    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    width: Math.min(implicitWidth, row.width * 0.6)
    elide: Text.ElideMiddle
    horizontalAlignment: Text.AlignRight
    text: row.version
    color: Commons.Color.muted
    font.family: row.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}
