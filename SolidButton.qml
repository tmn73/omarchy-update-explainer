import QtQuick
import qs.Commons as Commons
import qs.Commons
import qs.Ui

// The solid button: the text color of the theme as the fill, the background
// color as the label. The stock hover fill is a mix of the label color, which
// is dark here and made the label unreadable, so hover and the keyboard cursor
// only dim the fill a little.
Button {
  id: root

  focusable: true
  height: Math.max(Style.space(34), 34)
  background: Commons.Color.foreground
  foreground: Commons.Color.background
  color: root.hot ? Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.82)
    : Commons.Color.foreground
  fontSize: Style.font.body
  horizontalPadding: Style.space(16)
  radius: Style.space(8)

  Accessible.role: Accessible.Button
  Accessible.name: text
}
