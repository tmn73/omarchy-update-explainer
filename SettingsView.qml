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

  // Where the report goes: false for the panel, true for a terminal.
  property bool reportInTerminal: false
  // The two signals of a panel report: the bar icon and the notification.
  property bool reportOnIcon: true
  property bool reportNotify: true

  // `key` is the setting name: showOmarchy, showSystem, showTools, showPlugins,
  // reportOnIcon, reportNotify or reportInTerminal. `fallback` is its value when shell.json has none.
  signal toggled(string key, bool fallback)

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
    onActivated: root.toggled("showOmarchy", true)
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("System packages")
    hint: qsTr("Includes the reboot icon.")
    checked: root.types.system !== false
    onActivated: root.toggled("showSystem", true)
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("AUR and dev tools")
    checked: root.types.tools !== false
    onActivated: root.toggled("showTools", true)
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("Plugins")
    hint: qsTr("Shell plugins that are behind their repository.")
    checked: root.types.plugins !== false
    onActivated: root.toggled("showPlugins", true)
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

  // A gap between the two sections.
  Item {
    width: 1
    height: Style.space(10)
  }

  Text {
    width: parent.width
    textFormat: Text.PlainText
    text: qsTr("The update report")
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
    label: qsTr("Show the report on the bar icon")
    hint: qsTr("The icon pulses while the report is written, then changes until you open this popup.")
    checked: root.reportOnIcon
    onActivated: root.toggled("reportOnIcon", true)
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("Notify when the report is ready")
    hint: qsTr("Sends one notification when the report ends.")
    checked: root.reportNotify
    onActivated: root.toggled("reportNotify", true)
  }

  ToggleRow {
    foreground: root.foreground
    fontFamily: root.fontFamily
    label: qsTr("Open in a terminal")
    hint: qsTr("Shows the report here by default. Some assistants still open a terminal to write it.")
    checked: root.reportInTerminal
    onActivated: root.toggled("reportInTerminal", false)
  }
}
