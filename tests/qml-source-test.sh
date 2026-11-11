#!/usr/bin/env bash
# Source-level checks on the QML.
#
# A running shell cannot be driven headlessly, so these assert the properties
# that would otherwise only be noticed when the widget misbehaves.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

has() {
  local file="$1" pattern="$2" label="$3"
  grep -qE "$pattern" "$ROOT/$file" || fail "$label"
}

hasnt() {
  local file="$1" pattern="$2" label="$3"
  grep -qE "$pattern" "$ROOT/$file" && fail "$label" || true
}

# ---- Every QML file lints clean (the output decides, not the exit code)

for file in "$ROOT"/*.qml; do
  output=$(qmllint "$file" 2>&1 || true)
  if [[ -n $output ]]; then
    fail "$(basename "$file"): $output"
  fi
done

# ---- The palette is always qualified (Qt 6.12 shadows a bare Color)

for file in "$ROOT"/*.qml; do
  name=$(basename "$file")
  hasnt "$name" "(^|[^.[:alnum:]_])Color\." "$name uses a bare Color, use Commons.Color"
done

# ---- Service.qml

[[ -f $ROOT/Service.qml ]] || fail "Service.qml is missing"
if [[ -f $ROOT/Service.qml ]]; then
  S=Service.qml

  # Polling
  has $S "Timer \{" "no Timer"
  has $S "triggeredOnStart: true" "the Timer does not fire on start"

  # The interface Panel.qml binds to
  for property in summary status runState agent message explainError fetchedAt busy tooltip; do
    has $S "property .* $property\b" "Service.qml no longer exposes $property"
  done
  for method in refresh explain updateNow chooseAgent; do
    has $S "function $method\(" "Service.qml no longer has $method()"
  done

  # A failed refresh keeps the last good summary: Model.nextState (unit tested
  # in model.test.js) decides, and the Service only applies what it returns.
  assigns=$(grep -cE '^[[:space:]]*(root\.)?summary = ' "$ROOT/$S" || true)
  ((assigns == 1)) || fail "summary is assigned $assigns times, expected exactly once"
  has $S 'summary = next\.summary' "summary is not taken from the reducer result"
  has $S 'Model\.nextState\(' "apply() does not use Model.nextState"
  hasnt $S 'removeReport' "Service.qml removes the report (an agent session may still read it)"
  hasnt $S '"rm"' "Service.qml runs rm"
  hasnt $S 'onDestruction' "Service.qml acts on destruction"
  hasnt $S 'Model\.parseSummary' "Service.qml parses the summary outside the reducer"

  # Explain failures reach the user, and explain() waits for a refresh.
  has $S 'property string explainError' "Service.qml has no explainError"
  has $S 'explainQueued' "explain() does not queue behind a running refresh"
  has $S 'Model\.explainAfterRefresh\(' "a queued report starts without checking the refresh outcome"
  has $S 'property bool lastFailed' "Service.qml has no lastFailed"
  has $S 'if \(summaryProcess\.running\)' "explain() does not check the running refresh"

  # Argv arrays only: no shell string for the agent or the update
  has $S 'execDetached\(\["omarchy-agent-prompt", Model\.buildPrompt\(' \
    "the agent is not launched with an argv array"
  hasnt $S '"(sh|bash)"|sh -c|bash -c' "Service.qml builds a shell string"
  has $S '"omarchy-launch-floating-terminal-with-presentation"' "updateNow misses the launcher token"
  has $S '"omarchy-update"' "updateNow misses the update token"
  hasnt $S 'omarchy-launch-floating-terminal-with-presentation omarchy-update' \
    "the update is launched as one joined string"
  has $S '"omarchy-menu", "summon", "setup\.default\.agent"' "chooseAgent has no argv array"
  has $S '"omarchy-default-agent"' "the agent is not read from omarchy-default-agent"

  # Report file handling
  has $S 'XDG_RUNTIME_DIR' "the report dir is not under XDG_RUNTIME_DIR"
  has $S '"mkdir", "-p", "-m", "700"' "the report dir is not created with mode 700"
  hasnt $S 'cleanupProcess' "the report is removed through a child Process that dies with the item"
  has $S 'Model\.helperArgs\("report"' "explain does not ask for a report"
  has $S 'Model\.helperArgs\("summary"' "refresh does not ask for a summary"
  has $S 'boolSetting\("checkMise", true\)' "the checkMise setting is not read"
  has $S 'Model\.refreshAllowed\(' "refresh is not throttled"
  has $S 'forced === true' "refresh has no forced path"
  has $S 'onTriggered: root\.refresh\(true\)' "the timer does not force the refresh"
  # Deadlines: a hung run is stopped and never wedges the widget.
  has $S 'id: summaryDeadline' "no summary deadline timer"
  has $S 'id: reportDeadline' "no report deadline timer"
  has $S 'interval: Model\.SUMMARY_DEADLINE_MS' "the summary deadline is not from Model"
  has $S 'interval: Model\.REPORT_DEADLINE_MS' "the report deadline is not from Model"
  has $S 'summaryProcess\.running = false' "the deadline does not stop the summary run"
  has $S 'reportProcess\.running = false' "the deadline does not stop the report run"
  has $S 'root\.failReport\(qsTr\("The report took too long' "the deadline does not clear busy"
  has $S 'function failReport' "Service.qml has no failReport"
  grep -A4 'function failReport' "$ROOT/$S" | grep -q 'busy = false' || fail "failReport does not clear busy"
  has $S 'if \(busy\) return|if \(root\.busy\) return' "a second explain() while busy is not ignored"

  # The panel report: bounded reads, no silent plugin update, no lost report.
  has $S '"head", "-c", String\(Model\.ANSWER_MAX_BYTES\)' "the answer file is not read through a byte cap"
  hasnt $S 'FileView' "the answer file is read whole by a FileView"
  has $S 'Component\.onCompleted: loadSavedReport\(\)' "a shell reload does not restore the saved report"
  has $S '"head", "-c", String\(Model\.SAVED_REPORT_MAX_BYTES\)' "the saved report is not read through a byte cap"
  has $S 'saveReport\(text\)' "a finished report is not saved"
  has $S '\[cappedPath\(\), String\(Model\.AGENT_OUTPUT_MAX_BYTES\)\]\.concat\(argv\)' "the agent output has no byte cap"
  hasnt $S 'plugin update --yes' "Update plugins skips the diff and the confirmation"
  has $S '"omarchy plugin update"\]' "Update plugins does not run omarchy plugin update"
  has $S '!pluginsProcess\.running && !appendProcess\.running' "the timer fetches plugins while a report fetches them"
  grep -A3 'function startReport' "$ROOT/$S" | grep -qF 'whatsNewKey = Model.updatesKey(shown)' || fail "a queued report keeps the key of the old updates"

  # No agent name in the service
  hasnt $S 'claude|codex' "Service.qml names an agent"

  # No predictable shared directory: without XDG_RUNTIME_DIR nothing is written
  hasnt $S '/tmp' "Service.qml contains a /tmp literal"
  has $S 'runtimeDir === ""' "explain does not refuse when the runtime dir is missing"

  # No absolute plugin paths
  has $S "Qt\.resolvedUrl" "the helper is not resolved relatively"
  hasnt $S "/home/|/usr/local/" "Service.qml contains an absolute path"
fi

# ---- Every Text block is plain text and wraps its literals in qsTr (package data is hostile)

# Prints one line per broken Text block. Works per block by tracking brace depth.
text_block_problems() {
  awk '
    function flush() {
      if (!plain) print FILENAME ":" start ": Text block without textFormat: Text.PlainText"
      if (literal) print FILENAME ":" start ": Text block with a literal text outside qsTr"
      inblock = 0
    }
    {
      line = $0
      if (!inblock && line ~ /(^|[^A-Za-z0-9_.])Text[ \t]*\{/) {
        inblock = 1; depth = 0; plain = 0; literal = 0; start = FNR
      }
      if (inblock) {
        if (line ~ /textFormat:[ \t]*Text\.PlainText/) plain = 1
        if (line ~ /(^|[ \t{;])text:[ \t]*"[^"]/) literal = 1
        n = gsub(/\{/, "{", line); m = gsub(/\}/, "}", line)
        depth += n - m
        if (depth <= 0) flush()
      }
    }
  ' "$1"
}

# The checker must reject a deliberately broken sample.
sample=$(mktemp --suffix=.qml)
cat >"$sample" <<'QML'
Item {
  Text {
    textFormat: Text.PlainText
    textFormat: Text.PlainText
    text: "raw literal"
  }
  Text{
    anchors.centerIn: parent
    text: qsTr("no plain format")
  }
}
QML
problems=$(text_block_problems "$sample" | wc -l)
rm -f "$sample"
((problems == 2)) || fail "the Text block check found $problems problems in the broken sample, expected 2"

for file in "$ROOT"/*.qml; do
  while IFS= read -r problem; do
    [[ -n $problem ]] && fail "$problem"
  done < <(text_block_problems "$file")
done

# ---- Panel and its components

for name in Panel SourceSection VerdictBlock TintButton NoteText ActionBar; do
  [[ -f $ROOT/$name.qml ]] || fail "$name.qml is missing"
done
limit() {
  local file="$1" max="$2"
  [[ -f $ROOT/$file ]] || return 0
  local lines
  lines=$(wc -l <"$ROOT/$file")
  ((lines < max)) || fail "$file has $lines lines, the limit is under $max"
}
limit Panel.qml 210
limit SourceSection.qml 120
limit VerdictBlock.qml 120
limit TintButton.qml 120
limit NoteText.qml 120
limit ActionBar.qml 120

if [[ -f $ROOT/Panel.qml ]]; then
  has Panel.qml 'moduleName: "tmn73\.update-explainer"' "Panel.qml has the wrong moduleName"
  has Panel.qml 'ipcTarget: "tmn73\.update-explainer"' "Panel.qml has the wrong ipcTarget"
  has Panel.qml 'Service \{' "Panel.qml does not instantiate the Service"
  has Panel.qml 'Accessible\.name' "the bar button has no Accessible.name"
  has Panel.qml 'UpdatesBody \{' "Panel.qml does not use UpdatesBody"
  has UpdatesBody.qml 'Model\.panelVerdict' "UpdatesBody.qml does not take the verdict from Model.panelVerdict"
  has UpdatesBody.qml 'Model\.sections\(' "UpdatesBody.qml does not draw Model.sections"
  has UpdatesBody.qml 'Model\.stats\(' "UpdatesBody.qml does not take the summary card from Model.stats"
  has UpdatesBody.qml 'VerdictBlock \{' "UpdatesBody.qml does not use VerdictBlock"
  has UpdatesBody.qml 'SourceSection \{' "UpdatesBody.qml does not use SourceSection"
  has Panel.qml 'onRefreshRequested: \{ updates\.refresh\(true\); root\.refocus\(\) \}' "Check again does not refresh and restore focus"
  # Every button path hands focus back to the key catcher.
  for handler in onExplainRequested onChooseRequested onRefreshRequested; do
    grep -E "$handler:" "$ROOT/Panel.qml" | grep -q 'root\.refocus()' || fail "$handler does not restore focus"
  done
  has Panel.qml 'onUpdateRequested: \{ root\.close\(\); updates\.updateNow\(\) \}' "Update now does not close the panel"
  has Panel.qml 'function refocus\(\)' "Panel.qml has no refocus"
  has Panel.qml 'keyCatcher\.forceActiveFocus' "refocus does not target the key catcher"
  # Held data keeps showing after a failed refresh.
  has Panel.qml 'readonly property bool hasUpdates: Model\.hasUpdates\(updates\.shown\)' "Panel.qml has no hasUpdates"
  has UpdatesBody.qml 'Model\.hasUpdates\(summary\)' "the sections hide when the last refresh failed"
  has Panel.qml 'pending: root\.hasUpdates' "the buttons follow the status, not the held data"
  hasnt Panel.qml 'status === "pending"' "Panel.qml gates the panel on the pending status"
  has Panel.qml 'updates\.lastFailed' "the bar does not keep the error icon during a retry"
  hasnt Panel.qml 'Model\.verdictLine|Model\.sourceRows|SourceList' "Panel.qml uses removed names"
  has Panel.qml 'settings: root\.settings' "Panel.qml does not pass settings to the Service"
  hasnt Panel.qml 'omarchy\.system-update' "Panel.qml touches the stock update widget"
  # Bar item: hidden when up to date, never a count, the stock glyph, no dot.
  has Panel.qml 'visible: root\.opened \|\| Model\.barVisible\(' "the bar item is not hidden by Model.barVisible"
  hasnt Panel.qml 'labelText' "the bar item shows a count or label"
  hasnt Panel.qml 'summary\.total' "Panel.qml reads the total for the bar"
  has Panel.qml 'pending: "\\uf021"' "the pending glyph is not the stock one"
  has Panel.qml 'checking: "\\uf021"' "the checking glyph is not the stock one"
  # The bar shows the icon alone: no dot element and no accent color on it.
  hasnt Panel.qml 'radius: width / 2' "the bar item draws a round dot"
  hasnt Panel.qml 'Commons\.Color\.accent' "Panel.qml uses the accent color for a dot"
  hasnt Panel.qml 'visualIconSize' "Panel.qml positions something on the icon"
fi
if [[ -f $ROOT/SourceSection.qml ]]; then
  has SourceSection.qml 'Repeater' "SourceSection.qml draws no rows"
  has SectionRow.qml 'elide: Text\.ElideMiddle' "the version text does not elide in the middle"
  has SectionRow.qml 'row\.width \* 0\.6' "the version text has no width cap"
  has SourceSection.qml 'qsTr\("and more"\)' "SourceSection.qml has no 'and more' row"
  hasnt SourceSection.qml 'length|count' "SourceSection.qml computes or shows a count"
fi
if [[ -f $ROOT/VerdictBlock.qml ]]; then
  has VerdictBlock.qml 'property string tone' "VerdictBlock.qml has no tone"
fi
if [[ -f $ROOT/TintButton.qml ]]; then
  has TintButton.qml 'Button \{' "TintButton.qml is not a stock Button"
  has TintButton.qml 'Math\.max\(Style\.space\(34\), 34\)' "TintButton is not 34 px high"
  has TintButton.qml 'radius: Style\.space\(8\)' "TintButton has no radius of 8"
  has TintButton.qml 'horizontalPadding: Style\.space\(16\)' "TintButton has no 16 px padding"
  hasnt TintButton.qml 'Style\.space\((44|48)\)|width: parent' "TintButton is large or full width"
  hasnt TintButton.qml 'iconText' "TintButton has an icon"
fi
[[ -f $ROOT/SolidButton.qml ]] || fail "SolidButton.qml is missing"
if [[ -f $ROOT/SolidButton.qml ]]; then
  has SolidButton.qml 'root\.hot' "SolidButton.qml has no hover color of its own"
  has SolidButton.qml 'foreground: Commons\.Color\.background' "SolidButton.qml label is not the background color"
fi
if [[ -f $ROOT/ActionBar.qml ]]; then
  has ActionBar.qml 'enabled: !root\.busy' "the primary button is not disabled while busy"
  has ActionBar.qml 'TintButton \{' "the primary button is not a TintButton"
  has ActionBar.qml 'qsTr\("Check again"\)' "ActionBar.qml has no Check again button"
  has ActionBar.qml 'signal refreshRequested' "ActionBar.qml has no refresh signal"
  hasnt ActionBar.qml 'iconText|caption' "ActionBar.qml has an icon or a caption"
  has ActionBar.qml 'Model\.explainLabel\(root\.agent, root\.busy, root\.mode\)' "the busy label does not reach the button"
  has ActionBar.qml 'Model\.agentNotice\(\)' "ActionBar.qml has no agent notice"
  has ActionBar.qml 'visible: root\.pending && root\.agent !== "" && !root\.busy' "the notice is not limited to an agent set and not busy"
  has ActionBar.qml 'property string explainError' "ActionBar.qml cannot show an explain error"
  has ActionBar.qml 'text: root\.explainError' "ActionBar.qml does not show the explain error"
  # Keyboard path: the catcher takes Tab, Enter and Space first, so Panel must
  # forward them, and the buttons must be focusable stock Buttons.
  has Panel.qml 'onTabRequested: function \(direction\) \{ actions\.moveFocus\(direction\) \}' "Tab does not move between the buttons"
  has Panel.qml 'onActivateRequested: actions\.activateFocused\(\)' "Enter and Space do not activate a button"
  has ActionBar.qml 'function moveFocus\(' "ActionBar.qml has no moveFocus"
  has ActionBar.qml 'function activateFocused\(' "ActionBar.qml has no activateFocused"
  buttons=$(grep -cE '^    Button \{' "$ROOT/ActionBar.qml" || true)
  ((buttons == 1)) || fail "ActionBar.qml has $buttons plain Buttons, expected 1 (Check again)"
  has ActionBar.qml 'SolidButton \{' "Update now is not a SolidButton"
  focusables=$(grep -cE 'focusable: true' "$ROOT/ActionBar.qml" || true)
  ((focusables == 1)) || fail "ActionBar.qml has $focusables focusable plain buttons, expected 1"
  hasnt ActionBar.qml 'TapHandler' "ActionBar.qml still uses a TapHandler"
  # Compact on purpose: a desktop mouse and keyboard panel, so the 44 px touch
  # target rule does not apply. Buttons are about 34 px, sized to their text.
  has ActionBar.qml 'buttons\.cell' "the buttons do not share the row"
  grep -c 'Math\.max(Style\.space(34), 34)' "$ROOT/ActionBar.qml" | grep -qx 1 || fail "the Check again button is not 34 px"
  hasnt ActionBar.qml 'Style\.space\((44|48)\)' "ActionBar.qml keeps a 44 or 48 px button"
  grep -c 'Accessible\.name' "$ROOT/ActionBar.qml" | grep -qx 1 || fail "the plain button needs an Accessible.name"
  has ActionBar.qml 'Model\.explainLabel' "the primary label does not come from Model.explainLabel"
  has ActionBar.qml 'chooseRequested' "ActionBar.qml has no choose signal"
  has ActionBar.qml 'explainRequested' "ActionBar.qml has no explain signal"
  has ActionBar.qml 'updateRequested' "ActionBar.qml has no update signal"
  has ActionBar.qml 'Update now' "ActionBar.qml has no Update now button"
  hasnt ActionBar.qml 'claude|codex' "ActionBar.qml names an agent"
fi
# No em or en dash in any tracked file. The pattern uses escapes, so this
# file does not hold the characters itself.
dash_sample=$(printf 'a \xe2\x80\x94 b \xe2\x80\x93 c')
grep -qP '[\x{2013}\x{2014}]' <<<"$dash_sample" || fail "the dash check misses a sample with an em and an en dash"
while IFS= read -r tracked; do
  [[ -f $ROOT/$tracked ]] || continue
  if grep -qP '[\x{2013}\x{2014}]' "$ROOT/$tracked"; then
    fail "$tracked has an em or en dash"
  fi
done < <(git -C "$ROOT" ls-files)

# ---- The refresh setting is wired

has Service.qml 'refreshIntervalSec' "Service.qml does not read refreshIntervalSec"
has Service.qml 'interval: root\.refreshIntervalSec' "the Timer interval does not follow refreshIntervalSec"
[[ -f $ROOT/AgentNotice.qml ]] || fail "AgentNotice.qml is missing"
has ActionBar.qml 'AgentNotice' "ActionBar.qml does not use AgentNotice"
has AgentNotice.qml 'No default agent yet' "AgentNotice.qml has no title"
has AgentNotice.qml 'LineDash|Qt\.DashLine|dash' "AgentNotice.qml has no dashed border"

# ---- The manifest declares the mise switch

jq -e '.barWidget.schema | map(select(.key == "checkMise" and .type == "boolean" and .defaultValue == true)) | length == 1' \
  "$ROOT/manifest.json" >/dev/null || fail "manifest.json has no boolean checkMise setting that defaults to true"
jq -e '.barWidget.defaults.checkMise == true' "$ROOT/manifest.json" >/dev/null || fail "manifest.json defaults lack checkMise"

# ---- Report mark and notification

has Service.qml 'boolSetting\("reportOnIcon", true\)' "reportOnIcon does not default to true"
has Service.qml 'boolSetting\("reportNotify", true\)' "reportNotify does not default to true"
has Service.qml 'Model\.reportMark\(whatsNewState, whatsNewCurrent, reportUnread, reportOnIcon\)' "the report mark is not derived in Model"
has Service.qml 'onPanelOpenChanged' "opening the popup does not clear the unread report"
has Service.qml 'omarchy-notification-send' "the report notification does not use the Omarchy notifier"
has Service.qml '"notify-send"' "the report notification has no notify-send fallback"
has Service.qml '"omarchy-shell", "-q", "tmn73.update-explainer", "open"' "a click on the notification does not open the popup"
hasnt Service.qml 'notif.*whatsNew\.(headline|summary|title)' "report text goes into the notification argv"

has Panel.qml 'report: "\\uf15c"' "the report glyph is missing"
has Panel.qml 'panelOpen: root\.opened' "the service does not know when the popup is open"
has Panel.qml 'Model\.iconKey\(updates\.shown, updates\.barStatus, updates\.barTypes, updates\.reportMark\)' "the bar glyph ignores the report mark"
has Panel.qml 'Model\.barVisible\(updates\.barStatus, root\.hasSummary, updates\.lastFailed, updates\.reportMark\)' "the bar item can hide while a report is marked"
has Panel.qml 'mark: updates\.reportMark' "the bar button does not get the report mark"
has BarButton.qml 'running: root\.mark === "writing"' "the icon does not pulse while the report is written"
has BarButton.qml 'root\.mark === "ready" \? Commons\.Color\.accent' "the ready report does not use the accent color"
hasnt BarButton.qml 'radius: width / 2' "the bar button draws a round dot"

has SettingsView.qml 'toggled\("reportOnIcon", true\)' "the icon setting has no toggle"
has SettingsView.qml 'toggled\("reportNotify", true\)' "the notification setting has no toggle"
has Panel.qml 'reportOnIcon: updates\.reportOnIcon' "the settings screen does not get reportOnIcon"
has Panel.qml 'reportNotify: updates\.reportNotify' "the settings screen does not get reportNotify"
has manifest.json '"version": "0\.4\.0"' "the version is not 0.4.0"
has manifest.json '"reportOnIcon": true' "the manifest has no reportOnIcon default"
has manifest.json '"reportNotify": true' "the manifest has no reportNotify default"

# ---- Result

if ((failures > 0)); then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "qml-source-test: all checks passed"
