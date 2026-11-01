import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Update data service. The helper owns every system query; this item schedules
// it, reads the default agent, and exposes one stable model to the panel.
//
// The rule that shapes this file: a failed refresh never discards a good
// summary. `summary` is replaced only when a run comes back ok. Every other
// outcome updates runState and message and leaves the data alone.
//
// Nothing here builds a shell string. Every process gets an argv array, and
// the only text that reaches an argument list is the fixed prompt and a path.
Item {
  id: root

  property var summary: null
  property string runState: "loading"
  property string message: ""
  property string fetchedAt: ""
  property string agent: ""
  property bool busy: false

  readonly property string status: Model.statusOf(summary, runState)
  readonly property string tooltip: Model.tooltip(summary, status)

  readonly property string reportDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/update-explainer"
  readonly property string reportPath: reportDir + "/report.txt"

  function helperPath() {
    return Qt.resolvedUrl("omarchy-update-explainer-collect").toString().replace(/^file:\/\//, "")
  }

  function refresh() {
    if (!summaryProcess.running) {
      runState = "loading"
      summaryProcess.command = [helperPath(), "--summary"]
      summaryProcess.running = true
    }
    if (!agentProcess.running) {
      agentProcess.command = ["omarchy-default-agent"]
      agentProcess.running = true
    }
  }

  function apply(raw) {
    var parsed = Model.parseSummary(String(raw || ""))
    if (parsed.ok) {
      summary = parsed.summary
      fetchedAt = String(parsed.summary.generatedAt || "")
      message = String(parsed.summary.message || "")
      runState = parsed.summary.state === "error" ? "error" : "ok"
      if (parsed.summary.total === 0)
        removeReport()
    } else {
      runState = "error"
      message = parsed.message
    }
  }

  function removeReport() {
    if (!cleanupProcess.running) {
      cleanupProcess.command = ["rm", "-f", reportPath]
      cleanupProcess.running = true
    }
  }

  // The helper writes into the directory but does not create it, so each
  // report run starts by making it private to this user.
  function explain() {
    if (busy) return
    busy = true
    mkdirProcess.command = ["mkdir", "-p", "-m", "700", reportDir]
    mkdirProcess.running = true
  }

  function finishReport(raw) {
    var data = null
    try {
      data = JSON.parse(String(raw || ""))
    } catch (error) {
      data = null
    }
    if (data && data.state === "ok" && typeof data.path === "string" && data.path !== "") {
      Quickshell.execDetached(["omarchy-agent-prompt", Model.buildPrompt(data.path)])
    } else {
      message = data && data.message ? String(data.message) : qsTr("The update report could not be written.")
    }
    busy = false
  }

  function updateNow() {
    if (updateProcess.running) return
    updateProcess.command = ["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]
    updateProcess.running = true
  }

  function chooseAgent() {
    Quickshell.execDetached(["omarchy-menu", "summon", "setup.default.agent"])
  }

  visible: false

  Component.onDestruction: removeReport()

  Timer {
    interval: 6 * 60 * 60 * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: summaryProcess

    running: false
    command: []
    onExited: function (exitCode) {
      var output = String(summaryCollector.text || "")
      if (output.trim() !== "") {
        root.apply(output)
      } else {
        root.runState = "error"
        root.message = qsTr("The update check produced no output.")
      }
    }

    stdout: StdioCollector {
      id: summaryCollector

      waitForEnd: true
    }
  }

  Process {
    id: agentProcess

    running: false
    command: []
    onExited: function (exitCode) {
      root.agent = String(agentCollector.text || "").trim()
    }

    stdout: StdioCollector {
      id: agentCollector

      waitForEnd: true
    }
  }

  Process {
    id: mkdirProcess

    running: false
    command: []
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.message = qsTr("The report folder could not be created.")
        root.busy = false
        return
      }
      reportProcess.command = [root.helperPath(), "--report", root.reportPath]
      reportProcess.running = true
    }
  }

  Process {
    id: reportProcess

    running: false
    command: []
    onExited: function (exitCode) {
      root.finishReport(String(reportCollector.text || ""))
    }

    stdout: StdioCollector {
      id: reportCollector

      waitForEnd: true
    }
  }

  // If the launcher returns at once instead of waiting for the update, the
  // next timer tick refreshes.
  Process {
    id: updateProcess

    running: false
    command: []
    onExited: function (exitCode) {
      root.refresh()
    }
  }

  Process {
    id: cleanupProcess

    running: false
    command: []
  }
}
