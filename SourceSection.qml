import QtQuick
import qs.Commons as Commons
import qs.Commons
import qs.Ui

// One update source as a card: a header that opens and closes the rows, then
// one row for each item, then "and N more" when the list was cut. The data
// comes from Model.sections, so this file draws and decides nothing. A section
// can carry one action button, for the plugins section: Update plugins.
Rectangle {
  id: root

  property string label: ""
  property string badge: ""
  property var rows: []
  property bool more: false
  property string moreText: ""
  property bool open: false
  property bool hasAction: false
  property string fontFamily: Style.font.family
  property bool expanded: open

  signal actionRequested()

  radius: Style.space(10)
  color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.04)
  border.width: 1
  border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.14)
  implicitHeight: column.implicitHeight

  Column {
    id: column

    width: parent.width

    SectionHeader {
      width: parent.width
      label: root.label
      badge: root.badge
      expanded: root.expanded
      fontFamily: root.fontFamily
      onClicked: root.expanded = !root.expanded
    }

    Repeater {
      model: root.expanded ? root.rows : []

      delegate: SectionRow {
        required property var modelData

        width: column.width
        name: modelData.name
        version: modelData.version
        fontFamily: root.fontFamily
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.expanded && root.more
      width: parent.width
      height: visible ? Math.max(Style.space(34), 34) : 0
      leftPadding: Style.space(14)
      verticalAlignment: Text.AlignVCenter
      text: root.moreText !== "" ? root.moreText : qsTr("and more")
      color: Commons.Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Item {
      visible: root.expanded && root.hasAction
      width: parent.width
      height: visible ? Math.max(Style.space(34), 34) + Style.space(12) : 0

      Button {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        height: Math.max(Style.space(34), 34)
        text: qsTr("Update plugins")
        focusable: true
        bordered: true
        fontFamily: root.fontFamily
        fontSize: Style.font.body
        horizontalPadding: Style.space(16)
        radius: Style.space(8)

        Accessible.role: Accessible.Button
        Accessible.name: text

        onClicked: root.actionRequested()
      }
    }
  }
}
