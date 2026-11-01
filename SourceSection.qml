import QtQuick
import qs.Commons as Commons
import qs.Commons

// One update source: a small capitalised label, then one row for each item
// (name on the left, "old to new" on the right), then "and more" when the
// list was cut. The data comes from Model.sections, so this file draws and
// decides nothing. No number is ever shown.
Column {
  id: root

  property string label: ""
  property var rows: []
  property bool more: false
  property string fontFamily: Style.font.family

  spacing: Style.space(4)

  Text {
    textFormat: Text.PlainText
    text: root.label
    color: Commons.Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.letterSpacing: Style.font.bodySmall * 0.06
  }

  Repeater {
    model: root.rows

    delegate: Item {
      id: row

      required property var modelData

      width: root.width
      height: Math.max(Style.space(36), 36)

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: version.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: row.modelData.name
        color: Commons.Color.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        id: version

        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, row.width * 0.6)
        elide: Text.ElideMiddle
        horizontalAlignment: Text.AlignRight
        text: row.modelData.version
        color: Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)
      }
    }
  }

  Text {
    textFormat: Text.PlainText
    visible: root.more
    height: visible ? Math.max(Style.space(36), 36) : 0
    verticalAlignment: Text.AlignVCenter
    text: qsTr("and more")
    color: Commons.Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }
}
