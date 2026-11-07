import QtQuick
import qs.Commons as Commons
import qs.Commons
import qs.Ui

// Two tabs under the summary card: "What's new" (the report) and "Packages"
// (the update lists). `current` is "whatsnew" or "packages".
Row {
  id: root

  property string current: "whatsnew"
  property string fontFamily: Style.font.family

  signal picked(string tab)

  readonly property real cell: (width - spacing) / 2

  spacing: Style.space(8)

  Repeater {
    model: [
      { id: "whatsnew", label: qsTr("What's new") },
      { id: "packages", label: qsTr("Packages") }
    ]

    delegate: Button {
      required property var modelData

      readonly property bool selected: root.current === modelData.id

      width: root.cell
      height: Math.max(Style.space(30), 30)
      text: modelData.label
      bordered: !selected
      background: selected ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.16) : "transparent"
      foreground: selected ? Commons.Color.accent : Commons.Color.muted
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      radius: Style.space(8)

      Accessible.role: Accessible.PageTab
      Accessible.name: text

      onClicked: root.picked(modelData.id)
    }
  }
}
