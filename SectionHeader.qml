import QtQuick
import qs.Commons as Commons
import qs.Commons

// The header of a source card: a dot, the capitalised label, a badge and a
// chevron. The whole header is one button that reports a click.
Item {
  id: root

  property string label: ""
  property string badge: ""
  property bool expanded: false
  property string fontFamily: Style.font.family

  signal clicked()

  height: Math.max(Style.space(42), 42)

  Accessible.role: Accessible.Button
  Accessible.name: root.label
  Accessible.onPressAction: root.clicked()

  Rectangle {
    id: dot

    anchors.left: parent.left
    anchors.leftMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(8)
    height: width
    radius: width / 2
    color: Commons.Color.accent
  }

  Text {
    textFormat: Text.PlainText
    anchors.left: dot.right
    anchors.leftMargin: Style.space(10)
    anchors.right: badgeText.left
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: root.label
    color: Commons.Color.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    font.letterSpacing: Style.font.bodySmall * 0.06
  }

  Text {
    id: badgeText

    textFormat: Text.PlainText
    anchors.right: chevron.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: root.badge
    color: Commons.Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Text {
    id: chevron

    textFormat: Text.PlainText
    anchors.right: parent.right
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    text: root.expanded ? "" : ""
    color: Commons.Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
