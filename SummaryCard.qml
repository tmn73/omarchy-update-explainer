import QtQuick
import qs.Commons as Commons
import qs.Commons

// The card at the top of the popup while updates wait: one bold headline, a
// reboot flag, one chip for each source that has items, and the download size.
// Everything comes from Model.stats, so this file only draws.
Rectangle {
  id: root

  property string headline: ""
  property bool reboot: false
  property var chips: []
  property string download: ""
  property string fontFamily: Style.font.family

  radius: Style.space(10)
  color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.06)
  border.width: 1
  border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.14)
  implicitHeight: body.implicitHeight + Style.space(28)

  Column {
    id: body

    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(14)
    spacing: Style.space(10)

    Item {
      width: parent.width
      height: Math.max(headlineText.implicitHeight, badge.height)

      Text {
        id: headlineText

        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: badge.visible ? badge.left : parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        wrapMode: Text.WordWrap
        text: root.headline
        color: Commons.Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Rectangle {
        id: badge

        visible: root.reboot
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: badgeText.implicitWidth + Style.space(16)
        height: badgeText.implicitHeight + Style.space(8)
        radius: Style.space(6)
        color: Qt.rgba(Commons.Color.urgent.r, Commons.Color.urgent.g, Commons.Color.urgent.b, 0.18)

        Text {
          id: badgeText

          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: qsTr("Reboot needed")
          color: Commons.Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }
      }
    }

    Flow {
      width: parent.width
      spacing: Style.space(8)

      Repeater {
        model: root.chips

        delegate: Rectangle {
          id: chip

          required property var modelData

          width: chipRow.implicitWidth + Style.space(20)
          height: chipRow.implicitHeight + Style.space(10)
          radius: height / 2
          color: "transparent"
          border.width: 1
          border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.2)

          Row {
            id: chipRow

            anchors.centerIn: parent
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: chip.modelData.count
              color: Commons.Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: chip.modelData.label
              color: Commons.Color.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.download !== ""
      width: parent.width
      text: root.download
      color: Commons.Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
