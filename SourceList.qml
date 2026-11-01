import QtQuick
import qs.Commons as Commons
import qs.Commons

// One row per update source: a label on the left, the count or version jump on
// the right. The rows come from Model.sourceRows, so this file draws and
// decides nothing.
Column {
  id: root

  property var rows: []
  property string fontFamily: Style.font.family

  Repeater {
    model: root.rows

    delegate: Item {
      id: row

      required property var modelData
      required property int index

      width: root.width
      height: Math.max(Style.space(44), 44)

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.label
        color: Commons.Color.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        textFormat: Text.PlainText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: row.modelData.value
        color: Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        visible: row.index < root.rows.length - 1
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.12)
      }
    }
  }
}
