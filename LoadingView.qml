import QtQuick
import qs.Commons as Commons
import qs.Commons

// What the report view shows while a report runs: the three real steps (the
// current one pulses, the done ones get a check), a clock, and skeleton rows
// with a light that sweeps across them. Everything uses Style.duration, so it
// stands still when the user turns animations off.
Column {
  id: root

  // "collect", "notes" or "agent" (Service.reportStep).
  property string step: "collect"
  property real startedAt: 0
  property string fontFamily: Style.font.family

  readonly property var steps: [
    { id: "collect", label: qsTr("Checking what changes") },
    { id: "notes", label: qsTr("Fetching the release notes") },
    { id: "agent", label: qsTr("Reading pull requests and notes") }
  ]
  readonly property int current: step === "agent" ? 2 : step === "notes" ? 1 : 0
  property int seconds: 0

  spacing: Style.space(10)

  Timer {
    interval: 1000
    repeat: true
    running: root.visible
    triggeredOnStart: true
    onTriggered: root.seconds = root.startedAt > 0 ? Math.max(0, Math.floor((Date.now() - root.startedAt) / 1000)) : 0
  }

  Repeater {
    model: root.steps

    delegate: Item {
      id: stepRow

      required property var modelData
      required property int index

      readonly property bool done: index < root.current
      readonly property bool active: index === root.current

      width: root.width
      height: label.implicitHeight + Style.space(2)

      Rectangle {
        id: dot

        anchors.left: parent.left
        anchors.leftMargin: Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(8)
        height: width
        radius: width / 2
        color: stepRow.done || stepRow.active ? Commons.Color.accent
          : Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.2)

        SequentialAnimation on opacity {
          running: stepRow.active && root.visible
          loops: Animation.Infinite
          alwaysRunToEnd: true
          NumberAnimation { from: 1; to: 0.25; duration: Style.duration(600); easing.type: Easing.InOutSine }
          NumberAnimation { from: 0.25; to: 1; duration: Style.duration(600); easing.type: Easing.InOutSine }
        }
      }

      Text {
        id: label

        textFormat: Text.PlainText
        anchors.left: dot.right
        anchors.leftMargin: Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: stepRow.done ? qsTr("%1 ✓").arg(stepRow.modelData.label)
          : stepRow.active ? qsTr("%1  %2").arg(stepRow.modelData.label).arg(Math.floor(root.seconds / 60) + ":" + String(root.seconds % 60).padStart(2, "0"))
          : stepRow.modelData.label
        color: stepRow.active ? Commons.Color.accent : stepRow.done ? Commons.Color.foreground : Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: stepRow.active
      }
    }
  }

  // Skeleton rows the size of the real ones, with one sweeping light.
  Repeater {
    model: [0.75, 0.55, 0.65]

    delegate: Rectangle {
      id: skeleton

      required property var modelData
      required property int index

      width: root.width
      height: Style.space(40)
      radius: Style.space(10)
      clip: true
      color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.04)
      border.width: 1
      border.color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.10)

      Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        width: (parent.width - Style.space(24)) * skeleton.modelData
        height: Style.space(10)
        radius: height / 2
        color: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.10)
      }

      Rectangle {
        id: sweep

        width: parent.width * 0.4
        height: parent.height
        x: -width
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: "transparent" }
          GradientStop { position: 0.5; color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.10) }
          GradientStop { position: 1; color: "transparent" }
        }

        SequentialAnimation on x {
          running: root.visible
          loops: Animation.Infinite
          PauseAnimation { duration: Style.duration(skeleton.index * 150) }
          NumberAnimation { from: -sweep.width; to: skeleton.width; duration: Style.duration(1400); easing.type: Easing.InOutQuad }
          PauseAnimation { duration: Style.duration(300) }
        }
      }
    }
  }

  NoteText {
    width: parent.width
    text: qsTr("This takes a minute or two. You can close the panel.")
    fontFamily: root.fontFamily
  }
}
