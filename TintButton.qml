import QtQuick
import qs.Commons as Commons
import qs.Commons
import qs.Ui

// The primary button: a soft tint of the accent color with a thin accent
// border and accent text. No icon.
Button {
  id: root

  focusable: true
  height: Math.max(Style.space(48), 48)
  background: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)
  foreground: Commons.Color.accent
  fontSize: Style.font.body
  radius: Style.space(12)

  Accessible.role: Accessible.Button
  Accessible.name: text

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: "transparent"
    border.width: 1
    border.color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
  }
}
