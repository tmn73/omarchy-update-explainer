import QtQuick
import qs.Commons
import qs.Commons as Commons

// The settings screen of the popup: which update types may show the bar icon.
// It holds no state. Panel.qml passes the current values and saves each change.
Column {
  id: root

  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property bool showOmarchy: true
  property bool showSystem: true
  property bool showTools: true

  // `key` is the setting name: showOmarchy, showSystem or showTools.
  signal toggled(string key)

  spacing: Style.space(8)

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: qsTr("Show the bar icon for")
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1
    font.bold: true
    font.capitalization: Font.AllUppercase
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("Omarchy")
    checked: root.showOmarchy
    onActivated: root.toggled("showOmarchy")
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("System packages")
    hint: qsTr("Includes the reboot icon.")
    checked: root.showSystem
    onActivated: root.toggled("showSystem")
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("AUR and dev tools")
    checked: root.showTools
    onActivated: root.toggled("showTools")
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: qsTr("This only decides when the icon shows. This popup always lists every update.")
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.50)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }
}
