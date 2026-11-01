import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Update data service. The helper owns every system query; this item schedules
// it, reads the default agent, and exposes one stable model to the panel.
//
// The rule that shapes this file: a failed refresh never discards a good
// summary. Model.nextState decides, and it replaces `summary` only when a run
// comes back ok. Every other outcome updates runState and message and leaves
// the data and the report alone.
//
// Nothing here builds a shell string. Every process gets an argv array, and
// the only text that reaches an argument list is the fixed prompt and a path.
Item {
  id: root

  property var settings: ({})
  property var summary: null
  property string runState: "loading"
  property string message: ""
  // Why the last Explain click failed. Cleared by the next click. Kept apart
  // from `message`, which describes the update check.
  property string explainError: ""
  property bool explainQueued: false
  // True after a failed check until the next one succeeds. The bar keeps the
  // error icon on screen during a retry.
  property bool lastFailed: false
  property string fetchedAt: ""
  property string agent: ""
  property bool busy: false

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 1800, 300, 21600)

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value))
      value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  readonly property string status: Model.statusOf(summary, runState)
  readonly property string tooltip: Model.tooltip(summary, status, message)

  // Empty when the session has no runtime directory. Nothing is written then:
  // a fixed path in a shared folder would invite symlink and squatting tricks.
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string reportDir: runtimeDir + "/update-explainer"
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
    var next = Model.nextState({ summary: summary, fetchedAt: fetchedAt }, raw)
    summary = next.summary
    fetchedAt = next.fetchedAt
    runState = next.runState
    message = next.message
    lastFailed = next.runState === "error"
    if (next.removeReport)
      removeReport()
  }

  function removeReport() {
    if (runtimeDir === "") return
    // Detached so it still runs when this item is being destroyed.
    Quickshell.execDetached(["rm", "-f", reportPath])
  }

  // Explain waits for a refresh in flight: two checkupdates runs would fight
  // over one database lock. The helper writes into the directory but does not
  // create it, so each report run starts by making it private to this user.
  function explain() {
    explainError = ""
    if (busy) return
    if (runtimeDir === "") {
      explainError = qsTr("The runtime directory is not available, so the update report cannot be written.")
      return
    }
    busy = true
    if (summaryProcess.running) {
      explainQueued = true
      return
    }
    startReport()
  }

  function startReport() {
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
      explainError = data && data.message ? String(data.message) : qsTr("The update report could not be written.")
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
    interval: root.refreshIntervalSec * 1000
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
        root.lastFailed = true
      }
      if (root.explainQueued) {
        root.explainQueued = false
        var outcome = Model.explainAfterRefresh(root.status)
        if (outcome.start) {
          root.startReport()
        } else {
          root.explainError = outcome.error
          root.busy = false
        }
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
        root.explainError = qsTr("The report folder could not be created.")
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
}
