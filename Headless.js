// Agents that can write the panel report without a terminal.
//
// Omarchy launches agents only in a terminal (omarchy-agent), so this table
// adds the agents whose command line can run one turn and exit. An agent that
// is not here still works: it opens in a terminal and writes the same file.
// Add an agent only after you ran its command for real.
//
// Each entry gives:
// - run(prompt): the argv of one turn without a terminal.
// - session(stdout): the session id from the output of that turn, or "".
// - resume(id): the argv that reopens that session for questions.

var SESSION_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

// The tools a report needs, and nothing else. The agent reads remote text
// (release notes, pull requests), so it runs with no human watching and
// refuses every other tool ("dontAsk"). It reads only the report folder (its
// working directory) and /usr, where the files of the Local edits section
// live. It writes only the answer file: Claude Code checks every file write
// against "Edit" rules, so a "Write(...)" rule would refuse it. On GitHub it
// only reads: "gh api" is left out because the same command can also write.
// --tools removes every other built-in tool (Agent, Grep, Glob...), and
// --strict-mcp-config with no config loads no MCP server.
var CLAUDE_BUILTINS = "Read,Write,Edit,WebFetch,Bash"
var CLAUDE_TOOLS = [
  "Read(./**)",
  "Read(//usr/**)",
  "Edit(./whats-new-*.json)",
  "WebFetch",
  "Bash(gh pr view:*)",
  "Bash(gh pr diff:*)",
  "Bash(gh pr list:*)",
  "Bash(gh release view:*)"
]

var AGENTS = {
  claude: {
    run: function (prompt) {
      return ["claude", "-p", "--permission-mode", "dontAsk", "--tools", CLAUDE_BUILTINS,
              "--allowedTools", CLAUDE_TOOLS.join(","), "--strict-mcp-config", "--disable-slash-commands",
              "--output-format", "json", "--", prompt]
    },
    session: function (stdout) {
      try {
        var id = JSON.parse(String(stdout || "")).session_id
        return typeof id === "string" && SESSION_ID.test(id) ? id : ""
      } catch (e) {
        return ""
      }
    },
    resume: function (id) { return ["claude", "--resume", id] }
  }
}

function supports(agent) {
  return Object.prototype.hasOwnProperty.call(AGENTS, String(agent || ""))
}

// Empty when the agent has no entry: the caller opens a terminal instead.
function runCommand(agent, prompt) {
  return supports(agent) ? AGENTS[agent].run(prompt) : []
}

function sessionOf(agent, stdout) {
  return supports(agent) ? AGENTS[agent].session(stdout) : ""
}

function shellQuote(text) {
  return "'" + String(text).replace(/'/g, "'\\''") + "'"
}

// The command line for the terminal launcher, which runs it with bash. The
// session must reopen from the folder where it ran, so the line starts there.
// Empty when the agent has no entry or the id has an unexpected shape.
function resumeLine(agent, id, dir) {
  if (!supports(agent) || !SESSION_ID.test(String(id || "")) || !dir) return ""
  return "cd " + shellQuote(dir) + " && " + AGENTS[agent].resume(id).map(shellQuote).join(" ")
}

if (typeof module !== "undefined") {
  module.exports = {
    supports: supports,
    runCommand: runCommand,
    sessionOf: sessionOf,
    resumeLine: resumeLine
  }
}
