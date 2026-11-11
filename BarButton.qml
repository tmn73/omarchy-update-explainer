import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The icon in the bar. Panel.qml picks the glyph. This file owns how the icon
// reacts to the update check and to the panel report.
//
// `status` is the update check: "checking" dims the icon, "error" paints it in
// the urgent color. `mark` is the panel report (Model.reportMark): "writing"
// makes the icon pulse, "ready" paints it in the accent color, "failed" in the
// urgent color.
BarIconButton {
  id: root

  property string status: ""
  property string mark: ""
  // The opacity while a report is written. It is a property of its own, so the
  // opacity binding below survives the animation.
  property real pulse: 1

  // The shell paints an active button in its urgent color. A report that is
  // ready is good news, so it takes the accent color.
  active: root.status === "error" || root.mark === "ready" || root.mark === "failed"
  activeColor: root.mark === "ready" ? Commons.Color.accent : (root.bar ? root.bar.urgent : Commons.Color.urgent)
  opacity: root.mark === "writing" ? root.pulse : (root.status === "checking" ? 0.5 : 1)

  SequentialAnimation on pulse {
    running: root.mark === "writing"
    loops: Animation.Infinite
    onStopped: root.pulse = 1

    NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutSine }
    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
  }
}
