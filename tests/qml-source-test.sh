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
  has $S 'if \(next\.removeReport\)' "the report removal does not follow the reducer"
  hasnt $S 'Model\.parseSummary' "Service.qml parses the summary outside the reducer"

  # Explain failures reach the user, and explain() waits for a refresh.
  has $S 'property string explainError' "Service.qml has no explainError"
  has $S 'explainQueued' "explain() does not queue behind a running refresh"
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
  # Removal must survive teardown, so it is detached, not a child Process.
  has $S 'Component\.onDestruction: removeReport\(\)' "destruction does not remove the report"
  body=$(awk '/function removeReport\(\)/{f=1} f{print} f&&/^  }$/{exit}' "$ROOT/$S")
  grep -qE 'Quickshell\.execDetached\(\["rm", "-f", reportPath\]\)' <<<"$body" \
    || fail "removeReport does not use execDetached with rm -f"
  hasnt $S 'cleanupProcess' "the report is removed through a child Process that dies with the item"
  has $S '"--report"' "explain does not ask for a report"
  has $S '"--summary"' "refresh does not ask for a summary"
  has $S 'if \(busy\) return|if \(root\.busy\) return' "a second explain() while busy is not ignored"

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

# ---- Panel, SourceList and ActionBar

for name in Panel SourceList ActionBar; do
  [[ -f $ROOT/$name.qml ]] || fail "$name.qml is missing"
done
limit() {
  local file="$1" max="$2"
  [[ -f $ROOT/$file ]] || return 0
  local lines
  lines=$(wc -l <"$ROOT/$file")
  ((lines < max)) || fail "$file has $lines lines, the limit is under $max"
}
limit Panel.qml 200
limit SourceList.qml 120
limit ActionBar.qml 120

if [[ -f $ROOT/Panel.qml ]]; then
  has Panel.qml 'moduleName: "tmn73\.update-explainer"' "Panel.qml has the wrong moduleName"
  has Panel.qml 'ipcTarget: "tmn73\.update-explainer"' "Panel.qml has the wrong ipcTarget"
  has Panel.qml 'Service \{' "Panel.qml does not instantiate the Service"
  has Panel.qml 'Accessible\.name' "the bar button has no Accessible.name"
  has Panel.qml 'Model\.verdictLine' "Panel.qml does not show the verdict line"
  has Panel.qml 'settings: root\.settings' "Panel.qml does not pass settings to the Service"
  hasnt Panel.qml 'omarchy\.system-update' "Panel.qml touches the stock update widget"
  # Bar item: hidden when up to date, never a count, the stock glyph, a corner dot.
  has Panel.qml 'visible: root\.opened \|\| Model\.barVisible\(' "the bar item is not hidden by Model.barVisible"
  hasnt Panel.qml 'labelText' "the bar item shows a count or label"
  hasnt Panel.qml 'summary\.total' "Panel.qml reads the total for the bar"
  has Panel.qml 'pending: "\\uf021"' "the pending glyph is not the stock one"
  has Panel.qml 'checking: "\\uf021"' "the checking glyph is not the stock one"
  has Panel.qml 'x: button\.width / 2 \+ button\.visualIconSize / 2 - width' "the dot is not on the icon top-right corner"
  has Panel.qml 'y: button\.height / 2 - button\.visualIconSize / 2' "the dot is not on the icon top edge"
fi
if [[ -f $ROOT/SourceList.qml ]]; then
  has SourceList.qml 'rows' "SourceList.qml takes no rows"
  has SourceList.qml 'Repeater' "SourceList.qml draws no rows"
fi
if [[ -f $ROOT/ActionBar.qml ]]; then
  has ActionBar.qml 'Model\.explainEnabled\(' "the primary button is not gated by Model.explainEnabled"
  has ActionBar.qml 'Model\.explainLabel\(root\.agent, root\.busy\)' "the busy label does not reach the button"
  has ActionBar.qml 'property string explainError' "ActionBar.qml cannot show an explain error"
  has ActionBar.qml 'text: root\.explainError' "ActionBar.qml does not show the explain error"
  # Keyboard path: the catcher takes Tab, Enter and Space first, so Panel must
  # forward them, and the buttons must be focusable stock Buttons.
  has Panel.qml 'onTabRequested: function \(direction\) \{ actions\.moveFocus\(direction\) \}' "Tab does not move between the buttons"
  has Panel.qml 'onActivateRequested: actions\.activateFocused\(\)' "Enter and Space do not activate a button"
  has ActionBar.qml 'function moveFocus\(' "ActionBar.qml has no moveFocus"
  has ActionBar.qml 'function activateFocused\(' "ActionBar.qml has no activateFocused"
  buttons=$(grep -cE '^  Button \{' "$ROOT/ActionBar.qml" || true)
  ((buttons == 2)) || fail "ActionBar.qml has $buttons stock Buttons, expected 2"
  focusables=$(grep -cE 'focusable: true' "$ROOT/ActionBar.qml" || true)
  ((focusables == 2)) || fail "ActionBar.qml has $focusables focusable buttons, expected 2"
  hasnt ActionBar.qml 'TapHandler' "ActionBar.qml still uses a TapHandler"
  has ActionBar.qml 'Math\.max\(Style\.space\(48\), 48\)' "the primary button is under 48 px"
  has ActionBar.qml 'Math\.max\(Style\.space\(44\), 44\)' "Update now is under 44 px"
  grep -c 'Accessible\.name' "$ROOT/ActionBar.qml" | grep -qx 2 || fail "each button needs an Accessible.name"
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

# ---- Result

if ((failures > 0)); then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "qml-source-test: all checks passed"
