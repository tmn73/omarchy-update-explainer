import QtQuick
import qs.Commons
import qs.Commons as Commons

// The popup title row: the title, how old the check is, and the gear that
// switches between the updates and the settings screen.
Item {
  id: root

  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family
  property string title: ""
  property string fetchedAt: ""
  property string gearGlyph: ""
  property bool settingsOpen: false

  signal gearClicked()

  height: Math.max(Style.space(28), 28)

  function ageText() {
    if (fetchedAt === "") return ""
    var then = Date.parse(fetchedAt)
    if (isNaN(then)) return ""
    var minutes = Math.max(0, Math.round((Date.now() - then) / 60000))
    return minutes < 1 ? qsTr("checked just now") : qsTr("checked %1 min ago").arg(minutes)
  }

  Text {
    textFormat: Text.PlainText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.title
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.title
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    anchors.right: gear.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    visible: !root.settingsOpen
    text: root.ageText()
    color: Commons.Color.muted
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Item {
    id: gear

    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: parent.height
    height: parent.height

    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Settings")
    Accessible.onPressAction: root.gearClicked()

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: root.gearClicked() }

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.gearGlyph
      color: root.settingsOpen ? root.foreground : Commons.Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
  }
}
