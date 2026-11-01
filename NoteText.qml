import QtQuick
import qs.Commons as Commons
import qs.Commons

// One small wrapped line of plain text under the buttons.
Text {
  property string fontFamily: Style.font.family

  textFormat: Text.PlainText
  wrapMode: Text.WordWrap
  color: Commons.Color.muted
  font.family: fontFamily
  font.pixelSize: Style.font.bodySmall
}
