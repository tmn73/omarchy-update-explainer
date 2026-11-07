import QtQuick
import qs.Commons as Commons
import qs.Commons

// One row of the report that opens and closes: a header line (an optional app
// tag, the title, an optional count and a chevron), then the content, which
// slides open. The content is whatever the caller puts inside the row.
// `tone` "calm" draws the row with no fill, for the things to do at the end.
Rectangle {
  id: root

  property string tag: ""
  property string title: ""
  property string trailing: ""
  property bool open: false
  property string tone: "normal"
  property string fontFamily: Style.font.family
  // Milliseconds before the row fades and slides in, so a list of rows
  // arrives one by one. Negative means no entrance.
  property int revealDelay: -1
  default property alias content: body.data

  readonly property color line: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, root.tone === "calm" ? 0.28 : 0.14)

  radius: Style.space(10)
  color: root.tone === "calm" ? "transparent"
    : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.04)
  border.width: 1
  border.color: line
  implicitHeight: header.height + drawer.height
  clip: true

  transform: Translate { id: shift }

  Component.onCompleted: if (revealDelay >= 0 && Style.duration(1) > 0) entrance.start()

  SequentialAnimation {
    id: entrance

    PropertyAction { target: root; property: "opacity"; value: 0 }
    PropertyAction { target: shift; property: "y"; value: Style.space(8) }
    PauseAnimation { duration: root.revealDelay }
    ParallelAnimation {
      NumberAnimation { target: root; property: "opacity"; to: 1; duration: Style.duration(220); easing.type: Easing.OutCubic }
      NumberAnimation { target: shift; property: "y"; to: 0; duration: Style.duration(220); easing.type: Easing.OutCubic }
    }
  }

  Item {
    id: header

    width: parent.width
    height: Math.max(titleText.implicitHeight, Style.space(18)) + Style.space(20)

    Accessible.role: Accessible.Button
    Accessible.name: root.title
    Accessible.onPressAction: root.open = !root.open

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.open = !root.open }

    Rectangle {
      id: tagPill

      visible: root.tag !== ""
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? tagText.implicitWidth + Style.space(12) : 0
      height: tagText.implicitHeight + Style.space(4)
      radius: Style.space(5)
      color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.10)

      Text {
        id: tagText

        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.tag
        color: Commons.Color.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Text {
      id: titleText

      textFormat: Text.PlainText
      anchors.left: tagPill.visible ? tagPill.right : parent.left
      anchors.leftMargin: Style.space(tagPill.visible ? 8 : 12)
      anchors.right: trailingText.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.WordWrap
      maximumLineCount: 2
      elide: Text.ElideRight
      text: root.title
      color: root.open ? Commons.Color.accent : Commons.Color.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true

      Behavior on color { ColorAnimation { duration: Style.duration(150) } }
    }

    Text {
      id: trailingText

      textFormat: Text.PlainText
      anchors.right: chevron.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.trailing
      color: Commons.Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      id: chevron

      textFormat: Text.PlainText
      anchors.right: parent.right
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: qsTr("›")
      color: Commons.Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      rotation: root.open ? 90 : 0

      Behavior on rotation { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
    }
  }

  // The content slides: the drawer animates its height and fades in.
  Item {
    id: drawer

    anchors.top: header.bottom
    width: parent.width
    height: root.open ? body.implicitHeight + Style.space(12) : 0
    opacity: root.open ? 1 : 0
    clip: true

    Behavior on height { NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }

    Column {
      id: body

      x: Style.space(12)
      width: parent.width - Style.space(24)
      spacing: Style.space(8)
    }
  }
}
