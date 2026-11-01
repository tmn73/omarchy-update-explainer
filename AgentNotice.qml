import QtQuick
import QtQuick.Shapes
import qs.Commons as Commons
import qs.Commons

// Shown above the buttons when no default agent is set: a dashed box with a
// bold title and one line of help.
Item {
  id: root

  property string fontFamily: Style.font.family

  implicitHeight: textColumn.implicitHeight + Style.space(32)

  Shape {
    anchors.fill: parent

    ShapePath {
      strokeWidth: 1
      strokeColor: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.3)
      strokeStyle: ShapePath.DashLine
      dashPattern: [4, 3]
      fillColor: "transparent"
      startX: 0.5
      startY: 0.5
      PathLine { x: root.width - 0.5; y: 0.5 }
      PathLine { x: root.width - 0.5; y: root.height - 0.5 }
      PathLine { x: 0.5; y: root.height - 0.5 }
      PathLine { x: 0.5; y: 0.5 }
    }
  }

  Column {
    id: textColumn

    anchors.fill: parent
    anchors.margins: Style.space(16)
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: qsTr("No default agent yet")
      color: Commons.Color.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    Text {
      textFormat: Text.PlainText
      width: parent.width
      wrapMode: Text.WordWrap
      text: qsTr("Omarchy picks none for you. Choose one and the explanation runs in it.")
      color: Commons.Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
