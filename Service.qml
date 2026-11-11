import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model
import "Headless.js" as Headless

// Update data service. The helper owns every system query; this item schedules
// it, reads the default agent, and exposes one stable model to the panel.
//
// The rule that shapes this file: a failed refresh never discards a good
// summary. Model.nextState decides, and it replaces `summary` only when a run
// comes back ok. Every other outcome updates runState and message and leaves
// the data and the report alone.
//
// Every process gets an argv array, and the only text that reaches an argument
// list is the fixed prompt and a path. The one command line is the resume line
// for the terminal launcher, built by Headless.resumeLine from a checked
// session id and a quoted path.
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

  // The report in the panel. whatsNewState is "", "running", "ready" or
  // "error". The report belongs to the updates it was written for
  // (whatsNewKey), so it stops showing when they change.
  readonly property bool reportInTerminal: boolSetting("reportInTerminal", false)
  // The two signals of a panel report: the mark on the bar icon and the
  // notification when it ends.
  readonly property bool reportOnIcon: boolSetting("reportOnIcon", true)
  readonly property bool reportNotify: boolSetting("reportNotify", true)
  // Set by the panel. A report that ends while the popup is open needs no signal.
  property bool panelOpen: false
  // True from the end of a report until the user opens the popup. A report
  // restored after a shell reload never sets it.
  property bool reportUnread: false
  onPanelOpenChanged: if (panelOpen) reportUnread = false
  property var whatsNew: null
  property string whatsNewState: ""
  property string whatsNewError: ""
  property string whatsNewKey: ""
  property string whatsNewPath: ""
  property string sessionId: ""
  property bool agentExited: false
  // The step of a panel report: "collect", "notes" or "agent", and when it
  // started (ms since the epoch). The loading view shows both.
  property string reportStep: ""
  // A report path that waits for the plugin check to end before its plugin
  // section is added (finishNotes).
  property string appendWaiting: ""
  property real reportStartedAt: 0
  readonly property bool whatsNewCurrent: whatsNewKey !== "" && whatsNewKey === Model.updatesKey(shown)
  readonly property bool canAsk: sessionId !== "" && Headless.supports(agent)
  readonly property bool hasReport: whatsNewCurrent && whatsNewState !== ""
  readonly property string reportMark: Model.reportMark(whatsNewState, whatsNewCurrent, reportUnread, reportOnIcon)
  readonly property string reportMode: Model.reportMode(reportInTerminal, whatsNewCurrent && whatsNewState === "ready", canAsk)

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
  readonly property string tooltip: Model.tooltip(shown, status, message, reportMark)

  // Empty when the session has no runtime directory. Nothing is written then:
  // a fixed path in a shared folder would invite symlink and squatting tricks.
  readonly property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "")
  readonly property string reportDir: runtimeDir + "/update-explainer"
  readonly property string reportPath: reportDir + "/report.txt"
  // The last finished panel report (saveReport, restoreReport).
  readonly property string savedReportPath: runtimeDir === "" ? "" : reportDir + "/last-report.json"
  // The language of the report (Model.languageOf).
  readonly property string locale: String(Quickshell.env("LC_MESSAGES") || Quickshell.env("LANG") || "")

  function helperPath() {
    return Qt.resolvedUrl("omarchy-update-explainer-collect").toString().replace(/^file:\/\//, "")
  }

  function notesHelperPath() {
    return Qt.resolvedUrl("omarchy-update-explainer-notes").toString().replace(/^file:\/\//, "")
  }

  function cappedPath() {
    return Qt.resolvedUrl("omarchy-update-explainer-capped").toString().replace(/^file:\/\//, "")
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
    // A report that adds the plugin section fetches the same repositories:
    // the timer waits for it, so two fetches never share one FETCH_HEAD.
    if (checkPlugins && !pluginsProcess.running && !appendProcess.running && Model.refreshAllowed(Date.now(), lastRunEndedAt, forced === true)) {
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
    if (!reportInTerminal) beginWhatsNew()
    if (summaryProcess.running) {
      explainQueued = true
      return
    }
    startReport()
  }

  // A panel report shows its loading view from the click on.
  function beginWhatsNew() {
    whatsNewKey = Model.updatesKey(shown)
    whatsNew = null
    whatsNewError = ""
    sessionId = ""
    agentExited = false
    reportUnread = false
    whatsNewState = "running"
    reportStep = "collect"
    reportStartedAt = Date.now()
  }

  // Every failure before the agent starts: the message shows under the
  // buttons, and in the report view when a panel report was running.
  function failReport(message) {
    explainError = message
    if (whatsNewState === "running") finishWhatsNew(null, message)
    busy = false
  }

  function startReport() {
    // A report that waited for a refresh belongs to the updates that refresh found.
    if (whatsNewState === "running") whatsNewKey = Model.updatesKey(shown)
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
      reportStep = "notes"
      // The release notes of the new package versions come first, then the
      // commit subjects of outdated plugins. Each step is optional.
      notesProcess.command = ["timeout", "--kill-after=5", "90", notesHelperPath(), "--append-report", data.path]
      notesProcess.reportPath = data.path
      notesProcess.running = true
      return
    } else {
      reportDeadline.stop()
      failReport(data && data.message ? String(data.message) : qsTr("The update report could not be written."))
    }
    busy = false
  }

  function finishNotes(path) {
    if (checkPlugins && pluginList.length > 0 && pluginsProcess.running) {
      appendWaiting = path
      return
    }
    if (checkPlugins && pluginList.length > 0) {
      appendProcess.command = ["timeout", "--kill-after=5", "120", pluginsHelperPath(), "--append-report", path]
      appendProcess.reportPath = path
      appendProcess.running = true
      return
    }
    launchAgent(path)
  }

  // The terminal mode opens the agent with the Markdown prompt, as before. The
  // panel mode asks for a JSON file: an agent from the Headless table writes
  // it with no terminal, any other agent opens in a terminal and writes it
  // there. The panel looks for the file until it parses or the deadline ends.
  function launchAgent(path) {
    reportDeadline.stop()
    if (reportInTerminal) {
      Quickshell.execDetached(["omarchy-agent-prompt", Model.buildPrompt(path, locale)])
      // The setting changed while a panel report collected its data. The
      // report goes to the terminal, so the panel report ends here.
      if (whatsNewState === "running") whatsNewState = ""
      busy = false
      return
    }
    whatsNewPath = reportDir + "/whats-new-" + Date.now() + ".json"
    if (whatsNewState !== "running") beginWhatsNew()
    reportStep = "agent"
    var prompt = Model.buildPanelPrompt(path, whatsNewPath, locale)
    var argv = Headless.runCommand(agent, prompt)
    // An agent without a terminal is read once it exits, so the cards and the
    // session id arrive together. A terminal agent stays open for questions,
    // so the panel looks for its file instead.
    if (argv.length > 0) {
      headlessProcess.command = [cappedPath(), String(Model.AGENT_OUTPUT_MAX_BYTES)].concat(argv)
      headlessProcess.running = true
    } else {
      Quickshell.execDetached(["omarchy-agent-prompt", prompt])
      whatsNewPoll.start()
    }
    agentDeadline.restart()
  }

  // Called with the text of the answer file. A file still being written does
  // not parse yet, so the panel keeps looking until the agent has exited.
  function readWhatsNew(text) {
    if (whatsNewState !== "running") return
    var report = Model.parseWhatsNew(text)
    if (report) {
      finishWhatsNew(report, "")
      saveReport(text)
    } else if (agentExited) {
      finishWhatsNew(null, qsTr("The assistant did not write the report."))
    }
  }

  // Keeps the finished report on disk, so a shell reload shows it again. The
  // text goes through stdin, never through the argument list.
  function saveReport(answer) {
    if (savedReportPath === "" || reportSaver.running) return
    reportSaver.payload = Model.savedReportText(whatsNewKey, sessionId, answer)
    reportSaver.command = ["dd", "of=" + savedReportPath, "status=none"]
    reportSaver.stdinEnabled = true
    reportSaver.running = true
  }

  function loadSavedReport() {
    if (savedReportPath === "" || savedReportReader.running) return
    savedReportReader.command = ["head", "-c", String(Model.SAVED_REPORT_MAX_BYTES), savedReportPath]
    savedReportReader.running = true
  }

  Component.onCompleted: loadSavedReport()

  // Shows the saved report after a shell reload. A report started since the
  // reload wins. whatsNewCurrent still hides it when the updates changed.
  function restoreReport(text) {
    if (whatsNewState !== "") return
    var saved = Model.parseSavedReport(text)
    if (!saved) return
    whatsNewKey = saved.key
    whatsNew = saved.report
    sessionId = saved.sessionId
    whatsNewError = ""
    whatsNewState = "ready"
  }

  function finishWhatsNew(report, error) {
    whatsNewPoll.stop()
    agentDeadline.stop()
    whatsNew = report
    whatsNewError = error
    whatsNewState = report ? "ready" : "error"
    busy = false
    var signals = Model.reportSignals(panelOpen, whatsNewCurrent, reportNotify)
    reportUnread = signals.unread
    if (signals.notify) notifyReport(report !== null)
  }

  readonly property string notifier: Quickshell.env("OMARCHY_PATH")
    ? Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-notification-send"
    : "omarchy-notification-send"

  // One notification for a report that ended. A click opens the popup. The
  // text is fixed (Model.reportNotice), and `--exec` with its argv is last.
  function notifyReport(ok) {
    var notice = Model.reportNotice(ok)
    var primary = [notifier, "-g", "\uf15c", "-u", "normal", notice.title, notice.body,
      "--exec", "omarchy-shell", "-q", "tmn73.update-explainer", "open"]
    var fallback = ["notify-send", "--app-name=Update Explainer", "-u", "normal", "--", notice.title, notice.plainBody]
    senderComponent.createObject(root, { command: primary, fallback: fallback, running: true })
  }

  Component {
    id: senderComponent

    // One process per notification, gone once it exits. A command that cannot
    // start at all (no omarchy-notification-send here) reports running=false
    // without ever having started, and the fallback runs then.
    Process {
      property var fallback: null
      property bool began: false

      onStarted: began = true
      onRunningChanged: {
        if (running) return
        if (!began && fallback) senderComponent.createObject(root, { command: fallback, running: true })
        destroy()
      }
    }
  }

  // Reopens the session that wrote the report, in a terminal, for questions.
  function ask() {
    var line = Headless.resumeLine(agent, sessionId, reportDir)
    if (line === "") return
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", line])
  }

  function updateNow() {
    if (updateProcess.running) return
    updateProcess.command = ["omarchy-launch-floating-terminal-with-presentation", "omarchy-update"]
    updateProcess.running = true
  }

  function updatePlugins() {
    if (pluginUpdateProcess.running) return
    pluginUpdateProcess.command = ["omarchy-launch-floating-terminal-with-presentation", "omarchy plugin update"]
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
      root.failReport(qsTr("The report took too long and was stopped."))
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
          root.failReport(outcome.error)
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
      if (root.appendWaiting !== "") {
        var path = root.appendWaiting
        root.appendWaiting = ""
        root.finishNotes(path)
      }
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
      root.launchAgent(reportPath)
    }
  }

  Timer {
    id: whatsNewPoll

    interval: Model.WHATS_NEW_POLL_MS
    repeat: true
    onTriggered: root.readAnswerFile()
  }

  Timer {
    id: agentDeadline

    interval: Model.AGENT_DEADLINE_MS
    onTriggered: {
      headlessProcess.running = false
      root.finishWhatsNew(null, qsTr("The assistant took too long and was stopped."))
    }
  }

  // The answer file, read through head so the shell never holds more than
  // Model.ANSWER_MAX_BYTES. A larger file is cut, does not parse, and counts as
  // no report. The file does not exist until the agent writes it, so a missing
  // file only matters once the agent has exited.
  function readAnswerFile() {
    if (answerReader.running || whatsNewPath === "") return
    answerReader.command = ["head", "-c", String(Model.ANSWER_MAX_BYTES), whatsNewPath]
    answerReader.running = true
  }

  // Writes the saved report (saveReport). Closing stdin ends dd.
  Process {
    id: reportSaver

    property string payload: ""

    running: false
    command: []
    stdinEnabled: false
    onStarted: {
      write(payload)
      stdinEnabled = false
    }
  }

  // Reads the saved report once, when the service starts. A missing file
  // gives no output and restores nothing.
  Process {
    id: savedReportReader

    running: false
    command: []
    onExited: function (exitCode) {
      root.restoreReport(String(savedReportCollector.text || ""))
    }

    stdout: StdioCollector {
      id: savedReportCollector

      waitForEnd: true
    }
    stderr: StdioCollector {}
  }

  Process {
    id: answerReader

    running: false
    command: []
    onExited: function (exitCode) {
      root.readWhatsNew(String(answerCollector.text || ""))
    }

    stdout: StdioCollector {
      id: answerCollector

      waitForEnd: true
    }
  }

  // One turn of an agent from the Headless table. It runs in the report
  // folder, so its session reopens from there (Headless.resumeLine).
  Process {
    id: headlessProcess

    running: false
    command: []
    workingDirectory: root.reportDir
    onExited: function (exitCode) {
      root.sessionId = Headless.sessionOf(root.agent, String(headlessCollector.text || ""))
      root.agentExited = true
      root.readAnswerFile()
    }

    stdout: StdioCollector {
      id: headlessCollector

      waitForEnd: true
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
        root.failReport(qsTr("The report folder could not be created."))
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
