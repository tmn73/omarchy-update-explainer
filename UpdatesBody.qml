import QtQuick
import qs.Commons
import "Model.js" as Model

// Everything the popup shows about the updates, under the header: the verdict
// words when nothing waits or the check failed, otherwise the summary card and
// one collapsible card for each source. Data comes from Model, so this file
// only lays things out.
Column {
  id: root

  property var summary: null
  property string status: "checking"
  property string message: ""
  property string fontFamily: Style.font.family

  readonly property bool hasSummary: summary !== null
  readonly property bool waiting: Model.hasUpdates(summary)
  readonly property var verdictParts: Model.panelVerdict(summary, status, message)
  readonly property var stats: waiting ? Model.stats(summary) : null

  signal pluginsRequested()

  spacing: Style.space(14)

  VerdictBlock {
    width: parent.width
    visible: !root.waiting || root.verdictParts.tone !== "pending"
    title: root.verdictParts.title
    detail: root.verdictParts.detail
    tone: root.verdictParts.tone
    fontFamily: root.fontFamily
  }

  SummaryCard {
    width: parent.width
    visible: root.waiting && root.verdictParts.tone === "pending"
    headline: root.stats ? root.stats.headline : ""
    reboot: root.stats ? root.stats.reboot : false
    chips: root.stats ? root.stats.chips : []
    download: root.stats ? root.stats.download : ""
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.hasSummary && root.waiting ? Model.sections(root.summary) : []

    delegate: SourceSection {
      required property var modelData

      width: root.width
      label: modelData.label
      badge: modelData.badge
      rows: modelData.rows
      more: modelData.more
      moreText: modelData.moreText
      open: modelData.open
      hasAction: modelData.id === "plugins"
      onActionRequested: root.pluginsRequested()
      fontFamily: root.fontFamily
    }
  }
}
