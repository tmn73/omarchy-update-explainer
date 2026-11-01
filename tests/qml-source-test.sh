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
  for property in summary status runState agent message fetchedAt busy tooltip; do
    has $S "property .* $property\b" "Service.qml no longer exposes $property"
  done
  for method in refresh explain updateNow chooseAgent; do
    has $S "function $method\(" "Service.qml no longer has $method()"
  done

  # A failed refresh keeps the last good summary: summary is assigned in one
  # place only, and that place is guarded by the ok branch.
  assigns=$(grep -cE '^[[:space:]]*(root\.)?summary = ' "$ROOT/$S" || true)
  ((assigns == 1)) || fail "summary is assigned $assigns times, expected exactly once"
  grep -B3 -E '^[[:space:]]*(root\.)?summary = ' "$ROOT/$S" | grep -qE 'parsed\.ok|\.ok\)' \
    || fail "summary is assigned outside an ok guard"

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
  has $S '"rm", "-f"' "the report file is never removed"
  has $S 'Component\.onDestruction' "the report is not removed on destruction"
  has $S '"--report"' "explain does not ask for a report"
  has $S '"--summary"' "refresh does not ask for a summary"
  has $S 'if \(busy\) return|if \(root\.busy\) return' "a second explain() while busy is not ignored"

  # No agent name in the service
  hasnt $S 'claude|codex' "Service.qml names an agent"

  # No absolute plugin paths
  has $S "Qt\.resolvedUrl" "the helper is not resolved relatively"
  hasnt $S "/home/|/usr/local/" "Service.qml contains an absolute path"
fi

# ---- Result

if ((failures > 0)); then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "qml-source-test: all checks passed"
