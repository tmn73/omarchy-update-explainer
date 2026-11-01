#!/usr/bin/env bash
# Tests for omarchy-update-explainer-collect.
#
# Contract: exactly one JSON document on stdout, exit code zero for every
# failure the user can meet. Every external tool is a stub on a sandbox PATH,
# so no test touches the real system or the network.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/omarchy-update-explainer-collect"
STUBS="$ROOT/tests/fixtures/stubs"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

assert_jq() {
  jq -e "$1" >/dev/null 2>&1 <<<"$2" || fail "$3 (filter: $1)"
}

MODE_ARGS=(--summary)
sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# Fresh sandbox PATH per case: system basics plus the stubs that the case keeps.
make_sandbox() {
  rm -rf "$sandbox/bin"
  mkdir -p "$sandbox/bin"
  local tool path
  for tool in bash cat rm mv mktemp jq date grep head awk tr sed cut sort wc env dirname basename stat chmod ls mkdir sleep flock rmdir; do
    path=$(command -v "$tool" 2>/dev/null) && ln -sf "$path" "$sandbox/bin/$tool"
  done
  for tool in checkupdates fakeroot pacman expac yay mise gh; do
    [[ " ${SKIP:-} " == *" $tool "* ]] || ln -sf "$STUBS/$tool" "$sandbox/bin/$tool"
  done
}

# run_case: sets $out and $code. Env vars set by the caller reach the stubs.
run_case() {
  make_sandbox
  out=$(PATH="$sandbox/bin" "$HELPER" "${MODE_ARGS[@]}" 2>"$sandbox/stderr")
  code=$?
  if grep -q "command not found" "$sandbox/stderr"; then
    fail "helper stderr has 'command not found': $(head -c 300 "$sandbox/stderr")"
  fi
}

reset_env() {
  unset SKIP STUB_CHECK_EXIT STUB_CHECK_ERR STUB_TRANSACTION STUB_KERNEL_PKG \
    STUB_OLD_VERSIONS STUB_DESC STUB_CHECK_OUT STUB_FAKEROOT_EXIT STUB_AUR STUB_MISE STUB_GH_LOG \
    STUB_CHECK_LOCKDIR STUB_CHECK_DBLOG STUB_FAKEROOT_LOG
  export XDG_RUNTIME_DIR="$sandbox/run"
  rm -rf "$sandbox/run"
  MODE_ARGS=(--summary)
}

summary_ok() {
  reset_env
  export STUB_TRANSACTION=$'omarchy 4.2-1 core 10485760\nfoo 2.0-1 extra 2097152'
  export STUB_OLD_VERSIONS="omarchy=4.1-1 foo=1.0-1"
  export STUB_AUR="bar 1.0 -> 1.1"
  export STUB_MISE="node 20 20.1 22"
  run_case
  [[ $code -eq 0 ]] || fail "summary_ok exit $code"
  assert_jq '.state=="ok"' "$out" "summary_ok state"
  assert_jq '.sources=={pacman:2,aur:1,mise:1}' "$out" "summary_ok sources"
  assert_jq '.total==4' "$out" "summary_ok total"
  assert_jq '.omarchy.pending==true and .omarchy.package=="omarchy"' "$out" "summary_ok omarchy"
  assert_jq '.omarchy.from=="4.1-1" and .omarchy.to=="4.2-1"' "$out" "summary_ok versions"
  assert_jq '.downloadPartial==true' "$out" "summary_ok partial"
  assert_jq '.downloadMiB==12' "$out" "summary_ok download"
  assert_jq '.reboot==false' "$out" "summary_ok reboot"
  assert_jq '.generatedAt|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "$out" "summary_ok generatedAt"
}

summary_nothing_pending() {
  reset_env
  export STUB_CHECK_EXIT=2
  run_case
  [[ $code -eq 0 ]] || fail "summary_nothing_pending exit $code"
  assert_jq '.state=="ok"' "$out" "nothing_pending state"
  assert_jq '.total==0' "$out" "nothing_pending total"
  assert_jq '.downloadMiB==null' "$out" "nothing_pending download"
  assert_jq '.omarchy.pending==false' "$out" "nothing_pending omarchy"
}

summary_checkupdates_fails() {
  reset_env
  export STUB_CHECK_EXIT=1
  export STUB_CHECK_ERR="error: failed to synchronize all databases"
  run_case
  [[ $code -eq 0 ]] || fail "checkupdates_fails exit $code"
  assert_jq '.state=="error"' "$out" "checkupdates_fails state"
  assert_jq '.message|length>0' "$out" "checkupdates_fails message"
}

summary_tool_missing() {
  reset_env
  export SKIP="yay"
  export STUB_CHECK_EXIT=2
  run_case
  [[ $code -eq 0 ]] || fail "tool_missing exit $code"
  assert_jq '.state=="ok" and .sources.aur==0' "$out" "tool_missing state"
  assert_jq '.notes|map(select(contains("yay")))|length>0' "$out" "tool_missing notes"
}

summary_reboot_kernel() {
  reset_env
  export STUB_TRANSACTION="linux 6.2-1 core 1048576"
  export STUB_KERNEL_PKG=linux
  run_case
  assert_jq '.reboot==true' "$out" "reboot_kernel reboot"
}

summary_hostile_names() {
  reset_env
  local hostile='bad "quote" <img src=x> $(id) `id`'
  export STUB_CHECK_EXIT=1
  export STUB_CHECK_ERR="$hostile"
  run_case
  [[ $code -eq 0 ]] || fail "hostile exit $code"
  jq -e . >/dev/null 2>&1 <<<"$out" || fail "hostile: output is not valid JSON"
  jq -e --arg h "$hostile" '.message|contains($h)' >/dev/null 2>&1 <<<"$out" \
    || fail "hostile: message lost the text"
  reset_env
  export STUB_TRANSACTION='weird"name 1.0-1 core 1048576'
  export STUB_DESC="$hostile"
  run_case
  jq -e . >/dev/null 2>&1 <<<"$out" || fail "hostile package: output is not valid JSON"
  assert_jq '.total==1' "$out" "hostile package total"
}

summary_malformed_line() {
  reset_env
  export STUB_TRANSACTION=$'foo 2.0-1 extra 2097152\nbad line'
  run_case
  assert_jq '.sources.pacman==1 and .total==1' "$out" "malformed_line count"
}

summary_transaction_fails() {
  reset_env
  export STUB_CHECK_OUT=$'foo 1.0-1 -> 2.0-1\nbar 3-1 -> 4-1'
  export STUB_FAKEROOT_EXIT=1
  run_case
  [[ $code -eq 0 ]] || fail "transaction_fails exit $code"
  assert_jq '.state=="ok" and .sources.pacman==2 and .total==2' "$out" "transaction_fails count"
  assert_jq '.downloadMiB==null' "$out" "transaction_fails download"
  assert_jq '.notes|map(select(contains("transaction")))|length>0' "$out" "transaction_fails note"
}

report_env() {
  reset_env
  export STUB_TRANSACTION=$'omarchy 4.2-1 core 10485760\nfoo 2.0-1 extra 2097152'
  export STUB_OLD_VERSIONS="omarchy=4.1-1 foo=1.0-1"
  export STUB_GH_LOG="$sandbox/gh-called"
  rm -f "$STUB_GH_LOG"
  MODE_ARGS=(--report "$sandbox/report.txt")
  rm -f "$sandbox/report.txt"
}

HEADINGS=("## Pacman packages" "## Omarchy" "## Local edits the upgrade overwrites" \
  "## Pending migrations" "## Orphans" "## Mise" "## AUR" "## Reboot hints")

report_sections() {
  report_env
  run_case
  [[ $code -eq 0 ]] || fail "report_sections exit $code"
  jq -e --arg p "$sandbox/report.txt" '.state=="ok" and .path==$p' >/dev/null 2>&1 <<<"$out" \
    || fail "report_sections json: $out"
  local last=0 h line
  for h in "${HEADINGS[@]}"; do
    line=$(grep -n -x -F "$h" "$sandbox/report.txt" | head -1 | cut -d: -f1)
    if [[ -z $line ]] || (( line <= last )); then fail "report_sections heading out of order or missing: $h"; fi
    last=${line:-$last}
  done
  grep -q -x -F "compare basecamp/omarchy v4.1...v4.2" "$sandbox/report.txt" \
    || fail "report_sections compare line"
  grep -q -F "foo 1.0-1 -> 2.0-1 [extra] 2 MiB | A package" "$sandbox/report.txt" \
    || fail "report_sections package line"
  grep -q -F "TOTAL download: 12 MiB" "$sandbox/report.txt" || fail "report_sections total"
}

report_mode_600() {
  report_env
  run_case
  [[ $(stat -c %a "$sandbox/report.txt" 2>/dev/null) == 600 ]] || fail "report_mode_600"
}

report_atomic() {
  report_env
  make_sandbox
  local i
  for i in 1 2; do
    PATH="$sandbox/bin" "$HELPER" --report "$sandbox/report.txt" >/dev/null 2>&1 &
  done
  wait
  local h
  for h in "${HEADINGS[@]}"; do
    grep -q -x -F "$h" "$sandbox/report.txt" 2>/dev/null || fail "report_atomic missing heading: $h"
  done
  compgen -G "$sandbox/*.tmp" >/dev/null && fail "report_atomic left a tmp file"
  compgen -G "$sandbox/.*.tmp" >/dev/null && fail "report_atomic left a hidden tmp file"
}

report_no_github() {
  report_env
  run_case
  [[ -e $sandbox/gh-called ]] && fail "report_no_github: gh was called"
  grep -q -x -F "compare basecamp/omarchy v4.1...v4.2" "$sandbox/report.txt" || fail "report_no_github compare line"
}

report_hostile_text() {
  report_env
  local hostile=$'say "hi" \'quoted\'\nsecond line <img src=x> $(id) `id`'
  export STUB_DESC="$hostile"
  run_case
  [[ $code -eq 0 ]] || fail "report_hostile exit $code"
  grep -q -F -- "say \"hi\" 'quoted'" "$sandbox/report.txt" || fail "report_hostile first line"
  grep -q -F -- 'second line <img src=x> $(id) `id`' "$sandbox/report.txt" || fail "report_hostile second line"
}

report_bad_path() {
  report_env
  MODE_ARGS=(--report "$sandbox/missing-dir/report.txt")
  run_case
  [[ $code -eq 0 ]] || fail "report_bad_path exit $code"
  assert_jq '.state=="error" and (.message|length>0)' "$out" "report_bad_path state"
}

report_fallback_note() {
  report_env
  export STUB_CHECK_OUT=$'foo 1.0-1 -> 2.0-1'
  export STUB_FAKEROOT_EXIT=1
  run_case
  [[ $code -eq 0 ]] || fail "report_fallback exit $code"
  grep -q -F "foo 1.0-1 -> 2.0-1 [unknown]" "$sandbox/report.txt" || fail "report_fallback line"
  grep -q -i "transaction could not be read" "$sandbox/report.txt" || fail "report_fallback note"
}

report_dev_version_refs() {
  report_env
  export STUB_TRANSACTION=$'omarchy-dev 4.0.0.r7534.g7eedd17-1 core 10485760'
  export STUB_OLD_VERSIONS="omarchy-dev=4.0.0.r7500.gabcdef123-1"
  run_case
  [[ $code -eq 0 ]] || fail "report_dev_version exit $code"
  grep -q -x -F "compare basecamp/omarchy abcdef123...7eedd17" "$sandbox/report.txt" \
    || fail "report_dev_version compare line: $(grep compare "$sandbox/report.txt")"
}

report_dir_target() {
  report_env
  mkdir -p "$sandbox/existing-dir"
  MODE_ARGS=(--report "$sandbox/existing-dir")
  run_case
  [[ $code -eq 0 ]] || fail "report_dir_target exit $code"
  assert_jq '.state=="error" and (.message|length>0)' "$out" "report_dir_target state"
  compgen -G "$sandbox/existing-dir/*" >/dev/null && fail "report_dir_target moved a file into the directory"
}

lock_private_db() {
  reset_env
  export STUB_CHECK_DBLOG="$sandbox/dblog" STUB_FAKEROOT_LOG="$sandbox/frlog"
  rm -f "$sandbox/dblog" "$sandbox/frlog"
  export STUB_TRANSACTION='foo 2.0-1 extra 1048576'
  run_case
  local want="$sandbox/run/update-explainer/checkup-db/"
  grep -q -x -F "$want" "$sandbox/dblog" || fail "lock_private_db: checkupdates saw '$(cat "$sandbox/dblog" 2>/dev/null)'"
  grep -q -F -- "--dbpath $want" "$sandbox/frlog" || fail "lock_private_db: pacman dbpath: $(cat "$sandbox/frlog" 2>/dev/null)"
  [[ $(stat -c %a "$sandbox/run/update-explainer" 2>/dev/null) == 700 ]] || fail "lock_private_db: dir mode"
}

lock_without_runtime_dir() {
  reset_env
  unset XDG_RUNTIME_DIR
  export STUB_CHECK_DBLOG="$sandbox/dblog"
  rm -f "$sandbox/dblog"
  export STUB_TRANSACTION='foo 2.0-1 extra 1048576'
  run_case
  assert_jq '.state=="ok" and .total==1' "$out" "lock_without_runtime_dir state"
  [[ -z $(cat "$sandbox/dblog" 2>/dev/null) ]] || fail "lock_without_runtime_dir: set CHECKUPDATES_DB anyway"
}

lock_overlapping_runs() {
  reset_env
  mkdir -p "$sandbox/shared"
  export STUB_CHECK_LOCKDIR="$sandbox/shared"
  export STUB_TRANSACTION='foo 2.0-1 extra 1048576'
  make_sandbox
  PATH="$sandbox/bin" "$HELPER" --summary >"$sandbox/out1" 2>/dev/null &
  PATH="$sandbox/bin" "$HELPER" --summary >"$sandbox/out2" 2>/dev/null &
  wait
  local n
  for n in 1 2; do
    jq -e '.state=="ok" and .total==1' "$sandbox/out$n" >/dev/null 2>&1 \
      || fail "lock_overlapping_runs: run $n: $(head -c 300 "$sandbox/out$n")"
  done
}

MISE_ROWS=$'node                        20.0.0  20.0.0            22.1.0   /home/u/.config/mise/config.toml\nantigravity-cli             latest  [MISSING] (lazy)  1.4.12   /etc/mise/conf.d/omarchy-tools.toml\nnpm:@kilocode/cli           latest  [MISSING] (lazy)  7.8.18   /etc/mise/conf.d/omarchy-tools.toml\npython                      3.12    3.12.1            3.12.4   /home/u/.config/mise/config.toml\nhttp:kiro-cli               latest  [MISSING] (lazy)  2.37.0   /etc/mise/conf.d/omarchy-tools.toml'

mise_missing_summary() {
  reset_env
  export STUB_CHECK_EXIT=2 STUB_MISE="$MISE_ROWS"
  run_case
  assert_jq '.sources.mise==2 and .total==2' "$out" "mise_missing_summary count"
}

mise_missing_report() {
  report_env
  export STUB_MISE="$MISE_ROWS"
  run_case
  local section
  section=$(awk '/^## Mise$/{f=1;next} /^## /{f=0} f' "$sandbox/report.txt")
  grep -q '^node ' <<<"$section" || fail "mise_missing_report: node row lost"
  grep -q '^python ' <<<"$section" || fail "mise_missing_report: python row lost"
  grep -q 'MISSING' <<<"$section" && fail "mise_missing_report: lists a tool that is not installed"
  return 0
}

for case_name in mise_missing_summary mise_missing_report report_dev_version_refs report_dir_target lock_private_db lock_without_runtime_dir lock_overlapping_runs summary_ok summary_nothing_pending summary_checkupdates_fails \
  summary_tool_missing summary_reboot_kernel summary_hostile_names summary_malformed_line summary_transaction_fails \
  report_sections report_mode_600 report_atomic report_no_github report_hostile_text report_bad_path report_fallback_note; do
  before=$failures
  "$case_name"
  (( failures == before )) && echo "ok   $case_name" || echo "FAIL $case_name"
done

if (( failures > 0 )); then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "all passed"
