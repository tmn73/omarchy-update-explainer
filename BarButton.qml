import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The icon in the bar. Panel.qml picks the glyph. This file owns how the icon
// reacts to the update check and to the panel report.
//
// `status` is the update check: "checking" dims the icon, "error" paints it in
// the urgent color. `mark` is the panel report (Model.reportMark): "writing"
// makes the icon spin in the accent color, "ready" paints it in the accent
// color, "failed" in the urgent color.
BarIconButton {
  id: root

  property string status: ""
  property string mark: ""

  // The shell paints an active button in its urgent color. A report that is
  // being written or is ready is not an alert, so it takes the accent color.
  active: root.status === "error" || root.mark !== ""
  activeColor: root.mark === "ready" || root.mark === "writing" ? Commons.Color.accent : (root.bar ? root.bar.urgent : Commons.Color.urgent)
  opacity: root.status === "checking" ? 0.5 : 1

  // A spinning glyph reads at a glance, where a dimmed one went unnoticed.
  // The glyph turns back to rest when the report ends or motion is reduced.
  RotationAnimation on textRotation {
    from: 0
    to: 360
    duration: Style.duration(1100)
    loops: Animation.Infinite
    running: root.mark === "writing" && !Style.reduceMotion
    // A stopped animation keeps its angle, so the next glyph would sit tilted.
    onRunningChanged: if (!running) root.textRotation = 0
  }
}
