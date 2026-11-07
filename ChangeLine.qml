import QtQuick
import qs.Commons as Commons
import qs.Commons

// One line of the list of all changes: the project in bold, then what changed.
// A change for other hardware or another setup is dimmed and says so, so the
// list stays complete without looking like news for this machine.
Column {
  id: root

  property string name: ""
  property string summary: ""
  // "here", "other" or "unknown" (Model.parseWhatsNew).
  property string fit: "unknown"
  property string fontFamily: Style.font.family

  readonly property real fade: fit === "other" ? 0.45 : 1

  width: parent ? parent.width : 0
  spacing: Style.space(1)

  Text {
    textFormat: Text.PlainText
    width: parent.width
    elide: Text.ElideRight
    text: root.fit === "other" ? qsTr("%1 · not for this machine").arg(root.name) : root.name
    color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, root.fade)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    width: parent.width
    visible: root.summary !== ""
    wrapMode: Text.WordWrap
    text: root.summary
    color: Qt.rgba(Commons.Color.muted.r, Commons.Color.muted.g, Commons.Color.muted.b, root.fade)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
