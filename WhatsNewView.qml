import QtQuick
import qs.Commons as Commons
import qs.Commons

// The report in the panel, as an accordion. Folded, it reads at a glance: the
// headline and one line for each new feature. Open a row for the detail. The
// smaller changes, the list of all changes and the things to do come last,
// folded. While the agent works, or when it failed, one VerdictBlock says so.
// The data comes from Model.parseWhatsNew.
Column {
  id: root

  property var report: null
  // "running", "ready" or "error" (Service.whatsNewState).
  property string phase: ""
  property string error: ""
  property string step: ""
  property real startedAt: 0
  property string fontFamily: Style.font.family

  readonly property bool ready: phase === "ready" && report !== null

  spacing: Style.space(8)

  LoadingView {
    width: parent.width
    visible: root.phase === "running"
    step: root.step
    startedAt: root.startedAt
    fontFamily: root.fontFamily
  }

  VerdictBlock {
    width: parent.width
    visible: root.phase === "error"
    tone: "error"
    title: root.error
    fontFamily: root.fontFamily
  }

  VerdictBlock {
    width: parent.width
    visible: root.ready
    tone: "pending"
    title: root.ready ? root.report.headline : ""
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.ready ? root.report.features : []

    delegate: AccordionRow {
      required property var modelData
      required property int index

      width: root.width
      tag: modelData.app
      title: modelData.title
      open: index === 0
      revealDelay: 80 + index * 70
      fontFamily: root.fontFamily

      FeatureDetail {
        app: modelData.app
        detail: modelData.detail
        tryIt: modelData.tryIt
        source: modelData.source
        fontFamily: root.fontFamily
      }
    }
  }

  AccordionRow {
    width: parent.width
    visible: root.ready && root.report.smaller.length > 0
    title: qsTr("Smaller changes")
    revealDelay: root.ready ? 80 + root.report.features.length * 70 + 0 : 0
    trailing: root.ready ? String(root.report.smaller.length) : ""
    fontFamily: root.fontFamily

    Repeater {
      model: root.ready ? root.report.smaller : []

      delegate: Text {
        required property var modelData

        textFormat: Text.PlainText
        width: parent ? parent.width : 0
        wrapMode: Text.WordWrap
        text: qsTr("• %1").arg(modelData)
        color: Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  AccordionRow {
    width: parent.width
    visible: root.ready && root.report.changes.length > 0
    title: qsTr("All changes")
    revealDelay: root.ready ? 80 + root.report.features.length * 70 + 70 : 0
    trailing: root.ready ? String(root.report.changes.length) : ""
    fontFamily: root.fontFamily

    Repeater {
      model: root.ready ? root.report.changes : []

      delegate: ChangeLine {
        required property var modelData

        name: modelData.name
        summary: modelData.summary
        fit: modelData.fit
        fontFamily: root.fontFamily
      }
    }
  }

  AccordionRow {
    width: parent.width
    visible: root.ready && root.report.risks.length > 0
    tone: "calm"
    revealDelay: root.ready ? 80 + root.report.features.length * 70 + 140 : 0
    title: root.ready && root.report.risks.length === 1 ? qsTr("1 thing to do") : qsTr("%1 things to do").arg(root.ready ? root.report.risks.length : 0)
    fontFamily: root.fontFamily

    Repeater {
      model: root.ready ? root.report.risks : []

      delegate: RiskDetail {
        required property var modelData

        title: modelData.title
        detail: modelData.detail
        command: modelData.command
        fontFamily: root.fontFamily
      }
    }
  }
}
