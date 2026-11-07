import QtQuick
import qs.Commons as Commons
import qs.Commons

// The open part of a feature row: what it does, how to try it in an accent
// pill, and where it comes from. The text comes from the agent, which read
// other people's release notes, so every Text is plain.
Column {
  id: root

  property string app: ""
  property string detail: ""
  property string tryIt: ""
  property string source: ""
  property string fontFamily: Style.font.family

  width: parent ? parent.width : 0
  spacing: Style.space(8)

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
    visible: root.tryIt !== ""
    width: Math.min(parent.width, tryText.implicitWidth + Style.space(16))
    height: tryText.height + Style.space(8)
    radius: Style.space(6)
    color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
    border.width: 1
    border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)

    Text {
      id: tryText

      textFormat: Text.PlainText
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      wrapMode: Text.WordWrap
      text: qsTr("Try it: %1").arg(root.tryIt)
      color: Commons.Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    // The source says nothing when it only repeats the app.
    visible: root.source !== "" && root.source.toLowerCase() !== root.app.toLowerCase()
    elide: Text.ElideRight
    text: root.source
    color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.45)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
