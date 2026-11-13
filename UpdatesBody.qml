import QtQuick
import qs.Commons
import "Model.js" as Model

// Everything the popup shows about the updates, under the header: the verdict
// words when nothing waits or the check failed, otherwise the summary card and
// one collapsible card for each source. Once a report runs in the panel, two
// tabs switch between the report and the sources. Data comes from Model, so
// this file only lays things out.
Column {
  id: root

  property var summary: null
  property string status: "checking"
  property string message: ""
  property string fontFamily: Style.font.family
  // The report in the panel (Service.whatsNew*). `hasReport` is true while it
  // runs, and when it is done for the updates on screen.
  property var report: null
  property string reportPhase: ""
  property string reportError: ""
  property bool hasReport: false
  property string reportStep: ""
  property real reportStartedAt: 0
  // { title, detail } when the updates changed since the report, else null.
  property var reportDrift: null
  property string tab: "whatsnew"

  readonly property bool hasSummary: summary !== null
  readonly property bool waiting: Model.hasUpdates(summary)
  readonly property var verdictParts: Model.panelVerdict(summary, status, message)
  readonly property var stats: waiting ? Model.stats(summary) : null
  readonly property bool showReport: waiting && hasReport && tab === "whatsnew"

  signal pluginsRequested()

  // A new run shows its report first.
  onReportPhaseChanged: if (reportPhase === "running") tab = "whatsnew"

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

  ViewTabs {
    width: parent.width
    visible: root.waiting && root.hasReport
    current: root.tab
    fontFamily: root.fontFamily
    onPicked: function (tab) { root.tab = tab }
  }

  WhatsNewView {
    width: parent.width
    visible: root.showReport
    report: root.report
    phase: root.reportPhase
    error: root.reportError
    step: root.reportStep
    startedAt: root.reportStartedAt
    drift: root.reportDrift
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.hasSummary && root.waiting && !root.showReport ? Model.sections(root.summary) : []

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
