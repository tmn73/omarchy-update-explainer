// Pure logic for the update explainer widget: parsing the helper summary,
// deriving the status, and building the text the UI and the agent receive.
//
// Everything here is Qt-free so it can be unit tested under node
// (tests/model.test.js). The QML side owns rendering and process control.

var AGENT_NAMES = {
  pi: "Pi",
  omp: "Oh My Pi",
  opencode: "OpenCode",
  ori: "Ori",
  claude: "Claude Code",
  codex: "Codex",
  crush: "Crush",
  grok: "Grok",
  openclaw: "OpenClaw",
  agy: "Antigravity",
  hermes: "Hermes",
  copilot: "GitHub Copilot",
  muse: "Muse Code",
  "cursor-agent": "Cursor CLI",
  kimi: "Kimi",
  qwen: "Qwen Code",
  dsh: "DeepSeek Harness",
  mcode: "MiniMax Code",
  "kiro-cli": "Kiro CLI",
  freebuff: "Freebuff",
  kilo: "Kilo",
  devin: "Devin CLI",
  amp: "Amp",
  commandcode: "Command Code"
}

function parseSummary(raw) {
  var data
  try {
    data = JSON.parse(raw)
  } catch (e) {
    return { ok: false, summary: null, message: "The update check returned text that is not JSON." }
  }
  if (!data || typeof data !== "object" || Array.isArray(data)
      || typeof data.state !== "string"
      || !data.sources || typeof data.sources !== "object"
      || typeof data.total !== "number") {
    return { ok: false, summary: null, message: "The update check returned an unexpected shape." }
  }
  return { ok: true, summary: data, message: "" }
}

// runState is the outcome of the last refresh: "ok", "error" or "loading".
// A failed refresh wins even when an older summary is still held.
function statusOf(summary, runState) {
  if (runState === "error") return "error"
  if (!summary) return runState === "loading" ? "checking" : "current"
  if (summary.state === "error") return "error"
  return summary.total > 0 ? "pending" : "current"
}

function plural(n, word) {
  return n + " " + word + (n === 1 ? "" : "s")
}

function tooltip(summary, status) {
  if (status === "checking") return "Checking for updates"
  if (status === "error") {
    return summary && summary.message ? summary.message : "The update check failed"
  }
  if (status === "pending" && summary) return plural(summary.total, "update") + " pending"
  return "System is up to date"
}

function verdictLine(summary) {
  var parts = [plural(summary.total, "item") + " pending"]
  if (summary.downloadMiB !== null && summary.downloadMiB !== undefined) {
    parts.push((summary.downloadPartial ? "at least " : "about ") + summary.downloadMiB + " MiB")
  }
  var line = parts.join(", ") + "."
  return line + " " + (summary.reboot ? "Reboot needed." : "No reboot needed.")
}

function sourceRows(summary) {
  var o = summary.omarchy || {}
  var s = summary.sources || {}
  return [
    { id: "omarchy", label: "Omarchy", value: o.pending ? o.from + " to " + o.to : "0" },
    { id: "pacman", label: "System packages", value: String(s.pacman || 0) },
    { id: "aur", label: "AUR", value: String(s.aur || 0) },
    { id: "mise", label: "Dev tools", value: String(s.mise || 0) }
  ]
}

function explainLabel(agent) {
  if (!agent) return "Choose default agent"
  return "Explain with " + (AGENT_NAMES[agent] || agent)
}

function buildPrompt(dataPath) {
  return [
    "Read the file " + dataPath + ". It lists the pending updates for this Linux system (Omarchy, system packages, AUR packages and dev tools).",
    "Explain the updates to the user in their own language, as a short briefing.",
    "Write in this order:",
    "1. One verdict line: is it safe to update now, is a reboot needed, and how much will be downloaded.",
    "2. At most 5 bullets on what changes in Omarchy, in terms of what the user will notice. If the file has a compare line for Omarchy, read the pull requests behind those commits to understand the changes.",
    "3. At most 5 bullets on the apps and tools that change.",
    "4. A heads-up only when the user must act, for example a config file to merge or a service to restart. Leave this part out when nothing needs action.",
    "5. A final line that starts with \"Sources:\" and lists the places you read.",
    "If you cannot read the file, say that you cannot read it and stop. Do not guess its content.",
    "Never run the update or any command that changes the system. Only explain."
  ].join("\n")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseSummary: parseSummary,
    statusOf: statusOf,
    tooltip: tooltip,
    verdictLine: verdictLine,
    sourceRows: sourceRows,
    explainLabel: explainLabel,
    buildPrompt: buildPrompt
  }
}
