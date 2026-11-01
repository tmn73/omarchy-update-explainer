import QtQuick
import qs.Commons as Commons
import qs.Commons

// The words at the top of the panel: a bold title, then one muted line. The
// tone picks the title color: "error" is the urgent color, "checking" is
// muted, anything else uses the accent (the theme has no separate success or
// attention color).
Column {
  id: root

  property string title: ""
  property string detail: ""
  property string tone: "pending"
  property string fontFamily: Style.font.family

  spacing: Style.space(2)

  Text {
    textFormat: Text.PlainText
    width: parent.width
    wrapMode: Text.WordWrap
    text: root.title
    color: root.tone === "error" ? Commons.Color.urgent
      : root.tone === "checking" ? Commons.Color.muted : Commons.Color.accent
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
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
    font.pixelSize: Style.font.body
  }
}
