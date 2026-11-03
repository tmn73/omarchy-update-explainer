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
  // The system summary as the helper last reported it, and the plugins that are
  // behind their remote. `shown` is the two together (Model.withPlugins).
  property var summary: null
  property var pluginList: []
  readonly property var shown: Model.withPlugins(summary, pluginList)
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
  readonly property bool checkMise: boolSetting("checkMise", true)
  readonly property bool checkPlugins: boolSetting("checkPlugins", true)
  // Which update types may show the bar icon. The popup lists all of them.
  readonly property var barTypes: ({
    omarchy: boolSetting("showOmarchy", true),
    system: boolSetting("showSystem", true),
    tools: boolSetting("showTools", true),
    plugins: boolSetting("showPlugins", true)
  })
  // When the last check ended (ms since the epoch). Manual refreshes wait 30 s.
  property real lastRunEndedAt: 0
  property bool summaryTimedOut: false
  property bool reportTimedOut: false
  property bool pluginsTimedOut: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    return value === false || value === "false" ? false : (value === true || value === "true" ? true : fallback)
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value))
      value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  readonly property bool systemPending: Model.hasUpdates(summary)
  readonly property string status: Model.statusOf(shown, runState)
  readonly property string barStatus: Model.barStatus(shown, status, barTypes)
  readonly property string tooltip: Model.tooltip(shown, status, message)

  // Empty when the session has no runtime directory. Nothing is written then:
  // a fixed path in a shared folder would invite symlink and squatting tricks.
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string reportDir: runtimeDir + "/update-explainer"
  readonly property string reportPath: reportDir + "/report.txt"

  function helperPath() {
    return Qt.resolvedUrl("omarchy-update-explainer-collect").toString().replace(/^file:\/\//, "")
  }

  function notesHelperPath() {
    return Qt.resolvedUrl("omarchy-update-explainer-notes").toString().replace(/^file:\/\//, "")
  }

  function pluginsHelperPath() {
    return Qt.resolvedUrl("omarchy-update-explainer-plugins").toString().replace(/^file:\/\//, "")
  }

  // `forced` is for the timer and the Check again button. Every other caller
  // (panel open, R key, clicks, IPC) is ignored within 30 s of the last run.
  function refresh(forced) {
    if (Model.refreshAllowed(Date.now(), lastRunEndedAt, forced === true) && !summaryProcess.running) {
      runState = "loading"
      summaryProcess.command = [helperPath()].concat(Model.helperArgs("summary", "", checkMise))
      summaryProcess.running = true
      summaryDeadline.restart()
    }
    if (checkPlugins && !pluginsProcess.running && Model.refreshAllowed(Date.now(), lastRunEndedAt, forced === true)) {
      pluginsProcess.command = [pluginsHelperPath()]
      pluginsProcess.running = true
      pluginsDeadline.restart()
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
  }

  // The report is never removed here: an agent session may still read it. The
  // next Explain overwrites it, and logout clears the runtime directory.

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
    reportDeadline.restart()
  }

  function finishReport(raw) {
    if (reportTimedOut) {
      reportDeadline.stop()
      reportTimedOut = false
      return
    }
    var data = null
    try {
      data = JSON.parse(String(raw || ""))
    } catch (error) {
      data = null
    }
    if (data && data.state === "ok" && typeof data.path === "string" && data.path !== "") {
      // The release notes of the new package versions come first, then the
      // commit subjects of outdated plugins. Each step is optional.
      notesProcess.command = ["timeout", "--kill-after=5", "90", notesHelperPath(), "--append-report", data.path]
      notesProcess.reportPath = data.path
      notesProcess.running = true
      return
    } else {
      reportDeadline.stop()
      explainError = data && data.message ? String(data.message) : qsTr("The update report could not be written.")
    }
    busy = false
  }

  function finishNotes(path) {
    if (checkPlugins && pluginList.length > 0) {
      appendProcess.command = ["timeout", "--kill-after=5", "120", pluginsHelperPath(), "--append-report", path]
      appendProcess.reportPath = path
      appendProcess.running = true
      return
    }
    reportDeadline.stop()
    Quickshell.execDetached(["omarchy-agent-prompt", Model.buildPrompt(path)])
    busy = false
  }

  function updateNow() {
    if (updateProcess.running) return
    updateProcess.command = ["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]
    updateProcess.running = true
  }

  function updatePlugins() {
    if (pluginUpdateProcess.running) return
    pluginUpdateProcess.command = ["omarchy-launch-floating-terminal-with-presentation", "omarchy plugin update --yes"]
    pluginUpdateProcess.running = true
  }

  onCheckPluginsChanged: if (!checkPlugins) pluginList = []

  function chooseAgent() {
    Quickshell.execDetached(["omarchy-menu", "summon", "setup.default.agent"])
  }

  visible: false

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh(true)
  }

  // Total deadlines: a hung run never wedges the widget for the session.
  Timer {
    id: summaryDeadline

    interval: Model.SUMMARY_DEADLINE_MS
    onTriggered: {
      if (!summaryProcess.running) return
      root.summaryTimedOut = true
      root.runState = "error"
      root.lastFailed = true
      root.message = qsTr("The update check took too long and was stopped.")
      summaryProcess.running = false
    }
  }

  Timer {
    id: pluginsDeadline

    interval: Model.PLUGINS_DEADLINE_MS
    onTriggered: {
      if (!pluginsProcess.running) return
      root.pluginsTimedOut = true
      pluginsProcess.running = false
    }
  }

  Timer {
    id: reportDeadline

    interval: Model.REPORT_DEADLINE_MS
    onTriggered: {
      if (!reportProcess.running && !mkdirProcess.running && !notesProcess.running && !appendProcess.running) return
      root.reportTimedOut = reportProcess.running || notesProcess.running || appendProcess.running
      mkdirProcess.running = false
      reportProcess.running = false
      notesProcess.running = false
      appendProcess.running = false
      root.explainError = qsTr("The report took too long and was stopped.")
      root.busy = false
    }
  }

  Process {
    id: summaryProcess

    running: false
    command: []
    onExited: function (exitCode) {
      summaryDeadline.stop()
      root.lastRunEndedAt = Date.now()
      var output = String(summaryCollector.text || "")
      if (root.summaryTimedOut) {
        root.summaryTimedOut = false
      } else if (output.trim() !== "") {
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

  // A failed or late plugin check keeps the list the widget already has.
  Process {
    id: pluginsProcess

    running: false
    command: []
    onExited: function (exitCode) {
      pluginsDeadline.stop()
      var items = root.pluginsTimedOut ? null : Model.parsePlugins(String(pluginsCollector.text || ""))
      root.pluginsTimedOut = false
      if (items !== null) root.pluginList = items
    }

    stdout: StdioCollector {
      id: pluginsCollector

      waitForEnd: true
    }
  }

  // Adds the release notes of the new package versions to the report. Without
  // them the agent still gets the report that was written.
  Process {
    id: notesProcess

    property string reportPath: ""

    running: false
    command: []
    onExited: function (exitCode) {
      if (root.reportTimedOut) {
        root.reportTimedOut = false
        return
      }
      root.finishNotes(reportPath)
    }
  }

  // Adds the plugin section to the report. Without it the agent still gets
  // the report that was written.
  Process {
    id: appendProcess

    property string reportPath: ""

    running: false
    command: []
    onExited: function (exitCode) {
      reportDeadline.stop()
      if (root.reportTimedOut) {
        root.reportTimedOut = false
        return
      }
      Quickshell.execDetached(["omarchy-agent-prompt", Model.buildPrompt(reportPath)])
      root.busy = false
    }
  }

  Process {
    id: pluginUpdateProcess

    running: false
    command: []
    onExited: function (exitCode) {
      root.refresh(true)
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
      reportProcess.command = [root.helperPath()].concat(Model.helperArgs("report", root.reportPath, root.checkMise))
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
