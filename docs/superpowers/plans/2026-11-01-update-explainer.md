# Update Explainer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Omarchy bar widget that shows pending updates and opens the user's default agent with the update data, so the agent explains the update in plain language.

**Architecture:** A bundled bash helper collects update data (summary JSON for the widget, text report for the agent). Pure logic lives in `Model.js` (node-testable). `Service.qml` schedules the helper and launches the agent and the update. `Panel.qml` plus small components draw the widget. This follows the layout of `~/dev/omarchy-jira`.

**Tech Stack:** bash and jq (helper), QML with Quickshell (widget), node's built-in test runner (logic), shell tests with stubbed commands (helper), `qmllint`.

**Spec:** `docs/superpowers/specs/2026-11-01-update-explainer-design.md`. Mockups: kept outside the repository.

## Global Constraints

- Plugin id `tmn73.update-explainer`, kind `bar-widget`, entry point `Panel.qml`.
- Every line of text that leaves the session is English. No em dashes, no en dashes. No ticket numbers or ticket names in identifiers or comments.
- The collector makes no call to GitHub. `checkupdates`, `yay -Qua` and `mise outdated` may use the network, as `omarchy update` does.
- The collector and the widget never run `omarchy-update` and never change the system. Only the "Update now" click starts it.
- Update data and user text never appear in a process argument list. The only argv text is the fixed prompt instructions and the data file path.
- The data file lives in `$XDG_RUNTIME_DIR`, mode 600, written to a temp name then renamed.
- The prompt names no agent and no agent-specific tool or skill.
- No headless LLM call, no API key, no provider setting.
- Helper contract: exactly one JSON document on stdout, exit code 0 for every failure the user can meet. A non-zero exit means the helper itself broke.
- Every `Text` in QML is `Text.PlainText`. Every theme color is `Commons.Color.*`, never bare `Color.`.
- QML files stay small, one responsibility each. Pure logic stays in `Model.js` with `.pragma library` and a `module.exports` guard, as in `omarchy-jira/Model.js`.
- Git identity for this repo is `tmn73 <tommymartin1234@gmail.com>`, already set locally.

## Review Focus

1. Tool missing (`yay`, `mise` or `expac` not installed): that source shows 0 and a note, the widget does not go to `error`. Test in Task 1.
2. `checkupdates` exit codes: 2 means nothing pending (quiet, total 0), 1 means a real failure (state `error`). Test in Task 1.
3. Offline refresh: `Service.qml` keeps the last good summary and its timestamp, and shows the error state beside it. Test in Task 4.
4. Hostile text in package names or descriptions (quotes, newlines, `<img src=x>`): written verbatim to the data file, shown as plain text, never in argv. Tests in Tasks 2 and 5.
5. Double click on "Explain": the data file is replaced atomically, one agent launch per click, and the button stays disabled while the report is written. Test in Tasks 2 and 4.

---

## File structure

| File | Responsibility |
| --- | --- |
| `manifest.json` | Plugin metadata, copied in shape from `omarchy-jira/manifest.json` |
| `omarchy-update-explainer-collect` | Bash helper, modes `--summary` and `--report <file>` |
| `Model.js` | Pure logic: counts, verdict text, tooltip, state, prompt |
| `Service.qml` | Timer, helper `Process`, agent launch, update launch |
| `Panel.qml` | Bar entry: icon, dot, count, opens the panel |
| `SourceList.qml` | One row per source |
| `ActionBar.qml` | "Explain" and "Update now" buttons, plus the no-agent variant |
| `tests/` | `collect-test.sh`, `model.test.js`, `qml-source-test.sh`, `fixtures/`, `run-all.sh` |
| `README.md`, `LICENSE`, `.gitignore` | Docs and housekeeping |

---

### Task 1: Collector, summary mode

**Files:**
- Create: `omarchy-update-explainer-collect`, `manifest.json`, `LICENSE`, `.gitignore`, `tests/collect-test.sh`, `tests/run-all.sh`, `tests/fixtures/stubs/` (stub scripts for `checkupdates`, `fakeroot`, `pacman`, `expac`, `yay`, `mise`)

**Interfaces:**
- Produces: `omarchy-update-explainer-collect --summary` prints one JSON document:
  `{"state":"ok"|"error","message":string,"generatedAt":ISO8601,"omarchy":{"pending":bool,"package":string,"from":string,"to":string},"sources":{"pacman":int,"aur":int,"mise":int},"total":int,"downloadMiB":int|null,"downloadPartial":bool,"reboot":bool,"notes":[string]}`
- `total` counts the Omarchy package once inside `pacman`, so `total = pacman + aur + mise`. `omarchy.pending` is true when the Omarchy package is in the pacman transaction.
- `downloadMiB` comes from `pacman -Sup --print-format '%n %v %r %s'` (repo packages only). `downloadPartial` is true when `aur + mise > 0`. `downloadMiB` is null when pacman has nothing pending.
- `reboot` follows the `collect.sh` rules (kernel file `/vmlinuz`, `hyprland`, `nvidia*`).

- [ ] **Step 1: Write the failing tests in `tests/collect-test.sh`** with PATH set to a sandbox of stub commands, as `omarchy-jira/tests/helper-test.sh` does. Named cases and assertions with `jq -e`:
  - `summary_ok`: stubs report 2 pacman packages including `omarchy 4.1-1 -> 4.2-1`, 1 AUR, 1 mise. Expect `state=="ok"`, `sources=={pacman:2,aur:1,mise:1}`, `total==4`, `omarchy.pending==true`, `omarchy.from=="4.1-1"`, `omarchy.to=="4.2-1"`, `downloadPartial==true`.
  - `summary_nothing_pending`: `checkupdates` exits 2 with no output. Expect `state=="ok"`, `total==0`, `downloadMiB==null`.
  - `summary_checkupdates_fails`: `checkupdates` exits 1 with an error text. Expect `state=="error"`, a non-empty `message`, exit code 0.
  - `summary_tool_missing`: no `yay` in the sandbox. Expect `state=="ok"`, `sources.aur==0`, and a `notes` entry that names `yay`.
  - `summary_reboot_kernel`: a pending package whose file list holds `/vmlinuz` (stub `pacman -Qlq`). Expect `reboot==true`.
  - `summary_hostile_names`: a package description with quotes and `<img src=x>`. Expect valid JSON and the text intact where the JSON carries it.

- [ ] **Step 2: Run `bash tests/collect-test.sh` and confirm every case fails** with "helper not found".

- [ ] **Step 3: Implement `omarchy-update-explainer-collect --summary`.** Reuse the phases of `~/.claude/skills/omarchy-next-update/collect.sh` (pacman transaction through `fakeroot pacman -Sup`, background `yay -Qua` and `mise outdated`, the reboot rules). Build the JSON with `jq -n --arg/--argjson`, never string concatenation. Exit 0 on every user-reachable failure. Add `.gitignore`, `LICENSE` (MIT, as in the other tmn73 plugins) and `manifest.json` (`id`, `name`, `version 0.1.0`, `kinds ["bar-widget"]`, `activation "on-demand"`, schema with `refreshIntervalSec` default 1800, min 300, max 21600).

- [ ] **Step 4: Run `bash tests/collect-test.sh`, expect all cases PASS.** Write `tests/run-all.sh` to run every test file and exit non-zero on a failure.

- [ ] **Step 5: Commit** `feat: add the update summary helper`.

---

### Task 2: Collector, report mode

**Files:**
- Modify: `omarchy-update-explainer-collect`, `tests/collect-test.sh`

**Interfaces:**
- Consumes: the pacman transaction logic from Task 1 (extract it into a shell function used by both modes).
- Produces: `omarchy-update-explainer-collect --report <file>` writes the plain-text report to `<file>` (temp name, then `mv`, mode 600) and prints `{"state":"ok","path":"<file>"}` or `{"state":"error","message":string}`.
- Report sections, in this order, each with a `## ` heading: pacman packages (`name old -> new [repo] MiB | description`, then total), omarchy (package, versions, and the line `compare basecamp/omarchy OLD...NEW` using the `ref_of` rule from `collect.sh`), local edits the upgrade overwrites, pending migrations, orphans, mise, AUR, reboot hints.

- [ ] **Step 1: Add failing tests:**
  - `report_sections`: the file holds the seven headings above in order, and the `compare basecamp/omarchy` line carries the refs derived from the stub versions.
  - `report_mode_600`: `stat -c %a` of the file is `600`.
  - `report_atomic`: two runs started together leave a complete file (every heading present) and no `*.tmp` file behind.
  - `report_no_github`: the stub `gh` records any call; the file `gh-called` must not exist after the run.
  - `report_hostile_text`: quotes, newlines and `<img src=x>` from a stub description appear verbatim in the file.
  - `report_bad_path`: a path in a missing directory gives `state=="error"` and exit code 0.

- [ ] **Step 2: Run the tests, confirm the new cases fail.**

- [ ] **Step 3: Implement `--report <file>`** from the same collection functions. No call to `gh` or `curl`. Write with `mktemp` in the target directory, `chmod 600`, then `mv`.

- [ ] **Step 4: Run `bash tests/run-all.sh`, expect PASS.**

- [ ] **Step 5: Commit** `feat: add the update report helper`.

---

### Task 3: Model.js

**Files:**
- Create: `Model.js`, `tests/model.test.js`

**Interfaces:**
- Produces, all pure:
  - `parseSummary(raw: string): {ok: boolean, summary: object|null, message: string}` (JSON parse, shape check on `state`, `sources`, `total`)
  - `statusOf(summary: object|null, agent: string): "pending"|"current"|"error"|"checking"`
  - `tooltip(summary, status): string`
  - `verdictLine(summary): string` (items pending, `about N MiB` or `at least N MiB` when `downloadPartial`, no size when `downloadMiB` is null, reboot yes or no)
  - `sourceRows(summary): [{id, label, value}]` (rows: Omarchy shows `from to to` when pending, else `0`; System packages; AUR; Dev tools)
  - `explainLabel(agent: string): string` (`"Explain with <name>"`, or `"Choose default agent"` when `agent === ""`). Agent display names for the known ids from `omarchy-default-agent` (claude to "Claude Code", codex to "Codex", and so on); an unknown id shows as given.
  - `buildPrompt(dataPath: string): string`

- [ ] **Step 1: Write failing tests** in `tests/model.test.js` with the node test runner:
  - `parseSummary rejects text that is not JSON` and `rejects JSON without sources`.
  - `statusOf returns pending when total > 0`, `current when total is 0`, `error when state is error`.
  - `verdictLine says "at least 210 MiB" when downloadPartial`, `says "about 210 MiB" when not`, `omits size when downloadMiB is null`, `says "No reboot needed." / "Reboot needed."`.
  - `sourceRows shows "4.1-1 to 4.2-1" for the Omarchy row when pending`.
  - `explainLabel gives "Explain with Claude Code" for claude and "Choose default agent" for empty`.
  - `buildPrompt contains the data path`, `tells the agent to stop if the file cannot be read` (contains `cannot read`), `forbids running the update` (contains `Never run`), `requires a final line starting "Sources:"`, `asks for the user's language`, `names no agent` (no match for `claude|codex|opencode|skill`, case-insensitive), `holds no em dash or en dash`.

- [ ] **Step 2: Run `node --test tests/model.test.js`, confirm FAIL.**

- [ ] **Step 3: Implement the functions** in `Model.js`. The prompt asks for: a verdict line (safe or not, reboot, size), at most 5 bullets for Omarchy changes in user terms, at most 5 for apps and tools, a heads-up only when action is needed, reading the pull requests behind the Omarchy commits from the `compare` line, and the closing `Sources:` line. It ends with the unreadable-file rule and the never-run rule.

- [ ] **Step 4: Run the tests, expect PASS.**

- [ ] **Step 5: Commit** `feat: add the update explainer logic`.

---

### Task 4: Service.qml

**Files:**
- Create: `Service.qml`
- Modify: `tests/qml-source-test.sh` (create, then extend in Task 5)

**Interfaces:**
- Consumes: Task 1 and 2 helper modes, Task 3 `Model.*`.
- Produces on `Service` (an `Item`): properties `summary`, `status`, `agent`, `message`, `fetchedAt`, `busy` (report being written), `tooltip`; functions `refresh()`, `explain()`, `updateNow()`, `chooseAgent()`.

- [ ] **Step 1: Write failing source tests** in `tests/qml-source-test.sh` (pattern of `omarchy-jira/tests/qml-source-test.sh`): `qmllint` prints nothing for `Service.qml`; it contains `Timer` with `triggeredOnStart`; it keeps the last good summary on failure (a comment-free check that `summary` is assigned only inside the ok branch); it launches with an argv array and does not build a shell string for the agent; it contains `omarchy-agent-prompt` and `omarchy-launch-floating-terminal-with-presentation omarchy-update`; it never contains `claude` or `codex`.

- [ ] **Step 2: Run, confirm FAIL.**

- [ ] **Step 3: Implement `Service.qml`:** `Timer` and `Process` as in `omarchy-jira/Service.qml`; `refresh()` runs `--summary` and reads `omarchy-default-agent`; `explain()` sets `busy`, runs `--report $XDG_RUNTIME_DIR/update-explainer/report.txt`, and on `state=="ok"` launches `Quickshell.execDetached(["omarchy-agent-prompt", Model.buildPrompt(path)])`, then clears `busy`; `updateNow()` uses the same launcher string the stock `SystemUpdate.qml` uses (`bar.run(...)`); `chooseAgent()` runs `omarchy-menu summon setup.default.agent`. A failed refresh never replaces a good summary. The report file is removed when a refresh finds `total == 0` and in `Component.onDestruction`. Run the update through a `Process` with an argv array so `onExited` can call `refresh()`; the spec asks for a new check when the update terminal closes. If the launcher returns at once instead of waiting, refresh on the next timer tick and say so in the README.

- [ ] **Step 4: Run the tests, expect PASS.**

- [ ] **Step 5: Commit** `feat: add the update explainer service`.

---

### Task 5: Panel and components

**Files:**
- Create: `Panel.qml`, `SourceList.qml`, `ActionBar.qml`
- Modify: `tests/qml-source-test.sh`

**Interfaces:**
- Consumes: `Service` properties and functions from Task 4, `Model.sourceRows`, `Model.verdictLine`, `Model.explainLabel`.
- Produces: the bar entry (`moduleName: "tmn73.update-explainer"`, `ipcTarget` the same) with states from the mockups: current (quiet icon), pending (icon, count, dot), checking (dashed icon), error (error icon). The panel shows the verdict box, the source rows and the action bar. Without a default agent the primary button reads `Choose default agent` and calls `chooseAgent()`.

- [ ] **Step 1: Extend the source tests:** every file passes `qmllint` with no output; no bare `Color.`; every `Text` sets `textFormat: Text.PlainText`; `Panel.qml` is under 200 lines and each component under 120; `ActionBar.qml` disables the primary button while `busy`; every icon-only control has `Accessible.name`.

- [ ] **Step 2: Run, confirm FAIL.**

- [ ] **Step 3: Implement the three files** to match the mockup boards. Touch targets at least 44 px. Strings in `qsTr`.

- [ ] **Step 4: Run `bash tests/run-all.sh`, expect PASS.**

- [ ] **Step 5: Commit** `feat: add the update explainer panel`.

---

### Task 6: Verify on the real shell, document, prepare the listing

**Files:**
- Create: `README.md`, `preview.png`

- [ ] **Step 1: Link the plugin** into `~/.config/omarchy/plugins/tmn73.update-explainer` (as the Jira plugin is) and add it to the bar. Confirm the dot and count match `omarchy-update-available` for the Omarchy part.
- [ ] **Step 2: Click through every state** in the mockups: pending, no default agent (`omarchy default agent` unset in a scratch config), offline (disconnect), explain, update now. Record any state you could not reach.
- [ ] **Step 3: Test "Explain" with Claude Code.** Confirm the agent reads the file, ends with a `Sources:` line, and does not run the update. Note that other agents are untested.
- [ ] **Step 4: Write `README.md`:** what it does, the default-agent requirement, that it coexists with the stock `omarchy.system-update` widget, the billing note (no background call), update and removal steps, and that only Claude Code was tested.
- [ ] **Step 5: Capture `preview.png`** with `omasnap` or `herdr-app shot`, as the other plugins do.
- [ ] **Step 6: Commit** `docs: add the README and preview`. Do not publish to the marketplace without the user's go-ahead.
