import QtQuick
import QtQuick.Controls as QQC
import qs.Commons

// A column that scrolls when it is taller than the popup. The scrollbar shows
// only when needed, and the column leaves room for it.
Flickable {
  id: root

  default property alias body: column.data
  property alias spacing: column.spacing
  readonly property bool scrolls: contentHeight > height

  implicitHeight: column.implicitHeight
  contentWidth: width
  contentHeight: column.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds
  interactive: scrolls

  QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

  Column {
    id: column

    width: root.width - (root.scrolls ? Style.space(10) : 0)
  }
}
