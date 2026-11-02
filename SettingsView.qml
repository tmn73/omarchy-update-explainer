import QtQuick
import qs.Commons
import qs.Commons as Commons

// The settings screen of the popup: which update types may show the bar icon.
// It holds no state. Panel.qml passes the current values and saves each change.
Column {
  id: root

  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  // Which types show the bar icon: {omarchy, system, tools, plugins}.
  property var types: ({})

  // `key` is the setting name: showOmarchy, showSystem, showTools or showPlugins.
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
    checked: root.types.omarchy !== false
    onActivated: root.toggled("showOmarchy")
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("System packages")
    hint: qsTr("Includes the reboot icon.")
    checked: root.types.system !== false
    onActivated: root.toggled("showSystem")
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("AUR and dev tools")
    checked: root.types.tools !== false
    onActivated: root.toggled("showTools")
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("Plugins")
    hint: qsTr("Shell plugins that are behind their repository.")
    checked: root.types.plugins !== false
    onActivated: root.toggled("showPlugins")
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
