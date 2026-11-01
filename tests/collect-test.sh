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
  for tool in bash cat rm mv mktemp jq date grep head awk tr sed cut sort wc env dirname basename stat chmod ls mkdir sleep flock rmdir timeout kill; do
    path=$(command -v "$tool" 2>/dev/null) && ln -sf "$path" "$sandbox/bin/$tool"
  done
  for tool in checkupdates fakeroot pacman expac yay mise gh lscpu lspci uname; do
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
    STUB_CHECK_LOCKDIR STUB_CHECK_DBLOG STUB_FAKEROOT_LOG \
    UPDATE_EXPLAINER_LOCK_WAIT UPDATE_EXPLAINER_NET_TIMEOUT UPDATE_EXPLAINER_CHECK_TIMEOUT UPDATE_EXPLAINER_HOOKS_DIR \
    STUB_YAY_HANG STUB_MISE_HANG STUB_CHECK_HANG STUB_FAKEROOT_HANG STUB_QKK_HANG STUB_QKK STUB_PIDFILE STUB_MISE_LOG STUB_PACMAN_LOG STUB_CPU STUB_KERNEL_RELEASE STUB_OMARCHY_Q UPDATE_EXPLAINER_DMI_DIR XDG_SESSION_TYPE
  export XDG_RUNTIME_DIR="$sandbox/run"
  export TMPDIR="$sandbox/tmp"
  rm -rf "$sandbox/tmp"; mkdir -p "$sandbox/tmp"
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

HEADINGS=("## This machine" "## Pacman packages" "## Omarchy" "## Local edits the upgrade overwrites" \
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
  [[ $(grep -n '^## ' "$sandbox/report.txt" | head -1 | cut -d: -f2) == "## This machine" ]] \
    || fail "report_sections: This machine is not the first section"
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
  local hostile=$'say "hi" \'quoted\' second line <img src=x> $(id) `id`'
  export STUB_DESC="$hostile"
  run_case
  [[ $code -eq 0 ]] || fail "report_hostile exit $code"
  grep -q -F -- "say \"hi\" 'quoted'" "$sandbox/report.txt" || fail "report_hostile first line"
  grep -q -F -- 'second line <img src=x> $(id) `id`' "$sandbox/report.txt" || fail "report_hostile second part"
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
  export STUB_CHECK_DBLOG="$sandbox/dblog" STUB_FAKEROOT_LOG="$sandbox/frlog"
  rm -f "$sandbox/dblog" "$sandbox/frlog"
  export STUB_TRANSACTION='foo 2.0-1 extra 1048576'
  run_case
  assert_jq '.state=="ok" and .total==1' "$out" "lock_without_runtime_dir state"
  local db
  db=$(head -1 "$sandbox/dblog" 2>/dev/null)
  [[ $db == "$sandbox/tmp/"* ]] || fail "lock_without_runtime_dir: private db is '$db', expected under the temp dir"
  [[ $db == */checkup-db-* ]] && fail "lock_without_runtime_dir: used the stock shared path"
  grep -q -F -- "--dbpath $db" "$sandbox/frlog" || fail "lock_without_runtime_dir: pacman dbpath differs"
  [[ -e $db ]] && fail "lock_without_runtime_dir: the private db was not cleaned up"
  MODE_ARGS=(--report "$sandbox/report.txt")
  run_case
  db=$(tail -1 "$sandbox/dblog" 2>/dev/null)
  [[ $db == "$sandbox/tmp/"* && $db != */checkup-db-* ]] || fail "lock_without_runtime_dir report: db '$db'"
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

items_listed() {
  reset_env
  export STUB_CHECK_OUT=$'omarchy 4.1-1 -> 4.2-1\nfoo 1.0-1 -> 2.0-1'
  export STUB_TRANSACTION=$'omarchy 4.2-1 core 10485760\nfoo 2.0-1 extra 2097152'
  export STUB_AUR=$'bar 1.0 -> 1.1\nbaz 2 -> 3'
  export STUB_MISE=$'node  20  20.0.0  22.1.0  /x.toml\nhttp:kiro-cli latest [MISSING] (lazy) 2.37.0 /etc/y.toml\npython 3.12 3.12.1 3.12.4 /x.toml'
  run_case
  assert_jq '.items.pacman==[{name:"omarchy",from:"4.1-1",to:"4.2-1"},{name:"foo",from:"1.0-1",to:"2.0-1"}]' "$out" "items_listed pacman"
  assert_jq '.items.aur==[{name:"bar",from:"1.0",to:"1.1"},{name:"baz",from:"2",to:"3"}]' "$out" "items_listed aur"
  assert_jq '.items.mise==[{name:"node",from:"20.0.0",to:"22.1.0"},{name:"python",from:"3.12.1",to:"3.12.4"}]' "$out" "items_listed mise"
  assert_jq '.sources=={pacman:2,aur:2,mise:2} and .total==6' "$out" "items_listed counts kept"
}

items_cap() {
  reset_env
  local lines="" i
  for i in 1 2 3 4 5 6 7; do lines+="pkg$i 1.$i-1 extra 1048576"$'\n'; done
  export STUB_TRANSACTION=${lines%$'\n'}
  export STUB_OLD_VERSIONS="pkg1=0.1-1 pkg2=0.2-1 pkg3=0.3-1 pkg4=0.4-1 pkg5=0.5-1 pkg6=0.6-1 pkg7=0.7-1"
  run_case
  assert_jq '.sources.pacman==7 and (.items.pacman|length)==5' "$out" "items_cap"
  assert_jq '.items.pacman[0]=={name:"pkg1",from:"0.1-1",to:"1.1-1"}' "$out" "items_cap expac old version"
}

items_hostile() {
  reset_env
  export STUB_TRANSACTION='bad"name<img> 1.0-1 core 1048576'
  export STUB_AUR='$(id) 1 -> 2'
  run_case
  jq -e . >/dev/null 2>&1 <<<"$out" || fail "items_hostile: not JSON"
  assert_jq '.items.pacman[0].name=="bad\"name<img>"' "$out" "items_hostile pacman name"
  assert_jq '.items.aur[0].name=="$(id)"' "$out" "items_hostile aur name"
}

items_empty() {
  reset_env
  export STUB_CHECK_EXIT=2
  run_case
  assert_jq '.items=={pacman:[],aur:[],mise:[]}' "$out" "items_empty"
}

items_fallback() {
  reset_env
  export STUB_CHECK_OUT=$'foo 1.0-1 -> 2.0-1\nbar 3-1 -> 4-1'
  export STUB_FAKEROOT_EXIT=1
  run_case
  assert_jq '.items.pacman==[{name:"foo",from:"1.0-1",to:"2.0-1"},{name:"bar",from:"3-1",to:"4-1"}]' "$out" "items_fallback"
}

machine_section() {
  awk '/^## This machine$/{f=1;next} /^## /{f=0} f' "$sandbox/report.txt"
}

machine_env() {
  report_env
  mkdir -p "$sandbox/dmi"
  printf 'Test Laptop 16\n' >"$sandbox/dmi/product_name"
  printf 'TestVendor\n' >"$sandbox/dmi/sys_vendor"
  printf 'DMI-SERIAL-SENTINEL\n' >"$sandbox/dmi/product_serial"
  printf 'DMI-UUID-SENTINEL\n' >"$sandbox/dmi/product_uuid"
  printf 'BOARD-SERIAL-SENTINEL\n' >"$sandbox/dmi/board_serial"
  export UPDATE_EXPLAINER_DMI_DIR="$sandbox/dmi"
  export STUB_OMARCHY_Q="4.1-1" XDG_SESSION_TYPE=wayland
  export HOSTNAME=hostname-sentinel
}

report_machine_section() {
  machine_env
  run_case
  local sec
  sec=$(machine_section)
  local expected=("model: Test Laptop 16" "vendor: TestVendor" "cpu: Test CPU 9000" \
    "gpu: VGA compatible controller: Test Graphics Arc" "gpu: 3D controller: Test RTX Mobile" \
    "kernel: 6.9.1-test" "omarchy: omarchy 4.1-1" "session: wayland")
  local line
  for line in "${expected[@]}"; do
    grep -q -x -F "$line" <<<"$sec" || fail "report_machine_section missing line: $line (got: $sec)"
  done
  grep -q -i "Ethernet\|Host bridge" <<<"$sec" && fail "report_machine_section lists a non GPU device"
  return 0
}

report_machine_no_identifiers() {
  machine_env
  run_case
  local sentinel
  for sentinel in SERIAL-SENTINEL UUID-SENTINEL hostname-sentinel 00:11:22:33:44:55; do
    grep -q -F -- "$sentinel" "$sandbox/report.txt" && fail "report_machine_no_identifiers: report holds $sentinel"
  done
  return 0
}

report_machine_unknown() {
  machine_env
  export UPDATE_EXPLAINER_DMI_DIR="$sandbox/no-such-dir"
  unset STUB_OMARCHY_Q XDG_SESSION_TYPE
  SKIP="lscpu lspci" run_case
  local sec
  sec=$(machine_section)
  local key
  for key in model vendor cpu gpu omarchy session; do
    grep -q -x -F "$key: unknown" <<<"$sec" || fail "report_machine_unknown: $key is not unknown (got: $sec)"
  done
}

report_small_download() {
  report_env
  export STUB_TRANSACTION='tiny 1.0-1 extra 500000'
  run_case
  grep -q -x -F "TOTAL download: under 1 MiB" "$sandbox/report.txt" || fail "report_small_download: $(grep TOTAL "$sandbox/report.txt")"
  report_env
  export STUB_TRANSACTION='zero 1.0-1 extra 0'
  run_case
  grep -q -x -F "TOTAL download: 0 MiB" "$sandbox/report.txt" || fail "report_small_download zero bytes keeps 0 MiB"
}

report_mise_no_paths() {
  report_env
  export STUB_MISE="$MISE_ROWS"
  run_case
  local section
  section=$(awk '/^## Mise$/{f=1;next} /^## /{f=0} f' "$sandbox/report.txt")
  grep -q -x -F "node 20.0.0 22.1.0" <<<"$section" || fail "report_mise_no_paths: node row: $section"
  grep -q -x -F "python 3.12.1 3.12.4" <<<"$section" || fail "report_mise_no_paths: python row: $section"
  grep -q -F -e "/home/" -e ".toml" -e "/etc/" <<<"$section" && fail "report_mise_no_paths: a source path is in the report"
  return 0
}

lock_timeout() {
  reset_env
  export STUB_TRANSACTION='foo 2.0-1 extra 1048576' UPDATE_EXPLAINER_LOCK_WAIT=1
  mkdir -p -m 700 "$sandbox/run/update-explainer"
  local holder
  flock "$sandbox/run/update-explainer/collect.lock" sleep 4 &
  holder=$!
  sleep 0.5
  run_case
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  [[ $code -eq 0 ]] || fail "lock_timeout exit $code"
  assert_jq '.state=="error" and (.message|test("another update check"))' "$out" "lock_timeout summary"
  report_env
  export UPDATE_EXPLAINER_LOCK_WAIT=1
  mkdir -p -m 700 "$sandbox/run/update-explainer"
  flock "$sandbox/run/update-explainer/collect.lock" sleep 4 &
  holder=$!
  sleep 0.5
  run_case
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  [[ $code -eq 0 ]] || fail "lock_timeout report exit $code"
  assert_jq '.state=="error" and (.message|test("another update check"))' "$out" "lock_timeout report"
}

timeout_env() {
  reset_env
  export UPDATE_EXPLAINER_NET_TIMEOUT=1 UPDATE_EXPLAINER_CHECK_TIMEOUT=1
  export STUB_PIDFILE="$sandbox/pids"
  rm -f "$sandbox/pids"
}

timeout_background_tools() {
  timeout_env
  export STUB_YAY_HANG=1 STUB_MISE_HANG=1 STUB_CHECK_EXIT=2
  SECONDS=0
  run_case
  (( SECONDS < 20 )) || fail "timeout_background_tools took ${SECONDS}s"
  [[ $code -eq 0 ]] || fail "timeout_background_tools exit $code"
  assert_jq '.state=="ok" and .sources.aur==0 and .sources.mise==0' "$out" "timeout_background_tools state"
  assert_jq '.notes|map(select(contains("AUR") and contains("timed out")))|length>0' "$out" "timeout_background_tools aur note"
  assert_jq '.notes|map(select(contains("mise") and contains("timed out")))|length>0' "$out" "timeout_background_tools mise note"
}

timeout_checkupdates() {
  timeout_env
  export STUB_CHECK_HANG=1
  SECONDS=0
  run_case
  (( SECONDS < 20 )) || fail "timeout_checkupdates took ${SECONDS}s"
  [[ $code -eq 0 ]] || fail "timeout_checkupdates exit $code"
  assert_jq '.state=="error" and (.message|test("timed out"))' "$out" "timeout_checkupdates"
}

timeout_fakeroot() {
  timeout_env
  export STUB_FAKEROOT_HANG=1 STUB_CHECK_OUT=$'foo 1.0-1 -> 2.0-1'
  run_case
  assert_jq '.state=="ok" and .total==1 and .downloadMiB==null' "$out" "timeout_fakeroot falls back"
}

timeout_file_check() {
  report_env
  export UPDATE_EXPLAINER_CHECK_TIMEOUT=1 STUB_QKK_HANG=1
  SECONDS=0
  run_case
  (( SECONDS < 20 )) || fail "timeout_file_check took ${SECONDS}s"
  assert_jq '.state=="ok"' "$out" "timeout_file_check state"
  grep -q -F "(file check timed out)" "$sandbox/report.txt" || fail "timeout_file_check: no visible timeout line"
}

timeout_env_validated() {
  reset_env
  export UPDATE_EXPLAINER_NET_TIMEOUT="1; touch $sandbox/pwned" STUB_AUR=$'bar 1.0 -> 1.1' STUB_CHECK_EXIT=2
  run_case
  [[ -e $sandbox/pwned ]] && fail "timeout_env_validated: the override ran as a command"
  assert_jq '.sources.aur==1' "$out" "timeout_env_validated falls back to the default"
}

killed_helper_leaves_nothing() {
  timeout_env
  export UPDATE_EXPLAINER_NET_TIMEOUT=50 UPDATE_EXPLAINER_CHECK_TIMEOUT=50
  export STUB_YAY_HANG=1 STUB_CHECK_HANG=1
  make_sandbox
  PATH="$sandbox/bin" "$HELPER" --summary >/dev/null 2>&1 &
  local helper=$!
  sleep 1.5
  kill -TERM "$helper" 2>/dev/null
  wait "$helper" 2>/dev/null
  sleep 0.5
  local pid count=0
  while read -r pid; do
    [[ -n $pid ]] || continue
    count=$((count + 1))
    kill -0 "$pid" 2>/dev/null && { fail "killed_helper_leaves_nothing: child $pid still runs"; kill "$pid" 2>/dev/null; }
  done <"$sandbox/pids"
  (( count >= 2 )) || fail "killed_helper_leaves_nothing: expected two stub children, saw $count"
  flock -n "$sandbox/run/update-explainer/collect.lock" true || fail "killed_helper_leaves_nothing: the lock is still held"
}

no_mise_flag() {
  reset_env
  export STUB_MISE="$MISE_ROWS" STUB_MISE_LOG="$sandbox/mise-log" STUB_CHECK_EXIT=2
  rm -f "$sandbox/mise-log"
  MODE_ARGS=(--summary --no-mise)
  run_case
  assert_jq '.sources.mise==0 and .total==0 and .items.mise==[]' "$out" "no_mise_flag summary"
  assert_jq '.notes|map(select(test("mise")))|length==0' "$out" "no_mise_flag adds no note"
  [[ -e $sandbox/mise-log ]] && fail "no_mise_flag: mise was called"
  report_env
  export STUB_MISE="$MISE_ROWS" STUB_MISE_LOG="$sandbox/mise-log"
  MODE_ARGS=(--report "$sandbox/report.txt" --no-mise)
  run_case
  assert_jq '.state=="ok"' "$out" "no_mise_flag report"
  [[ -e $sandbox/mise-log ]] && fail "no_mise_flag report: mise was called"
  grep -q '^node ' "$sandbox/report.txt" && fail "no_mise_flag report: mise rows present"
  MODE_ARGS=(--summary --bogus)
  run_case
  [[ $code -eq 2 ]] || fail "no_mise_flag: an unknown flag must exit 2, got $code"
}

report_old_versions_and_descriptions_once() {
  report_env
  export STUB_TRANSACTION=$'foo 2.0-1 extra 2097152\nbar 3.0-1 extra 1048576'
  export STUB_OLD_VERSIONS="foo=1.0-1 bar=2.0-1"
  export STUB_DESC="Same description"
  local log="$sandbox/expac-log"
  rm -f "$log"
  # Wrap expac to count calls.
  mkdir -p "$sandbox/wrap"
  cat >"$sandbox/wrap/expac" <<WRAP
#!/usr/bin/env bash
echo "\$*" >>"$log"
exec "$STUBS/expac" "\$@"
WRAP
  chmod +x "$sandbox/wrap/expac"
  make_sandbox
  ln -sf "$sandbox/wrap/expac" "$sandbox/bin/expac"
  PATH="$sandbox/bin" "$HELPER" --report "$sandbox/report.txt" >/dev/null 2>&1
  grep -q -F "foo 1.0-1 -> 2.0-1 [extra] 2 MiB | Same description" "$sandbox/report.txt" || fail "report once: foo line"
  grep -q -F "bar 2.0-1 -> 3.0-1 [extra] 1 MiB | Same description" "$sandbox/report.txt" || fail "report once: bar line"
  local s_calls
  s_calls=$(grep -c -- '^-S' "$log")
  (( s_calls == 1 )) || fail "report once: expected one expac -S call, saw $s_calls"
}

report_caps() {
  report_env
  local lines="" i
  for i in $(seq 1 3000); do lines+="pkg$i 1.0-1 extra 1048576"$'\n'; done
  export STUB_TRANSACTION=${lines%$'\n'}
  export STUB_DESC=$(head -c 200 /dev/zero | tr '\0' 'd')
  run_case
  local size
  size=$(stat -c %s "$sandbox/report.txt")
  (( size <= 262144 + 200 )) || fail "report_caps: report is $size bytes"
  grep -q -F "[truncated: the report was cut at 256 KiB]" "$sandbox/report.txt" || fail "report_caps: no visible truncation line"
  report_env
  export STUB_AUR=$(printf 'name 1.0 -> 2.0 %0300d' 0)
  run_case
  local longest
  longest=$(awk '/^## AUR$/{f=1;next} /^## /{f=0} f {print length}' "$sandbox/report.txt" | sort -n | tail -1)
  (( longest <= 120 )) || fail "report_caps: an AUR line has $longest characters"
}

reboot_checks_only_candidates() {
  report_env
  export STUB_TRANSACTION=$'foo 1.0-1 core 1048576\nlinux-lts 6.2-1 core 1048576\nbar 1.0-1 core 1048576'
  export STUB_KERNEL_PKG=linux-lts STUB_PACMAN_LOG="$sandbox/pmlog"
  rm -f "$sandbox/pmlog"
  run_case
  grep -q -x -F "Qlq linux-lts" "$sandbox/pmlog" || fail "reboot_checks: the kernel package was not checked"
  grep -q -E "Qlq (foo|bar)" "$sandbox/pmlog" && fail "reboot_checks: an unrelated package was file listed"
  grep -q -F "kernel: linux-lts" "$sandbox/report.txt" || fail "reboot_checks: report lost the kernel hint"
  MODE_ARGS=(--summary)
  run_case
  assert_jq '.reboot==true' "$out" "reboot_checks summary"
  export STUB_TRANSACTION=$'foo 1.0-1 core 1048576\nhyprland 1.0-1 extra 1048576'
  unset STUB_KERNEL_PKG
  run_case
  assert_jq '.reboot==true' "$out" "reboot_checks hyprland"
  export STUB_TRANSACTION=$'nvidia-utils 1.0-1 extra 1048576'
  run_case
  assert_jq '.reboot==true' "$out" "reboot_checks nvidia"
}

hooks_show_no_exec_line() {
  report_env
  mkdir -p "$sandbox/hooks"
  printf '[Trigger]\nTarget = foo\n[Action]\nExec = /usr/bin/secret-exec-sentinel\n' >"$sandbox/hooks/patch.hook"
  export UPDATE_EXPLAINER_HOOKS_DIR="$sandbox/hooks"
  export STUB_QKK='warning: foo: /etc/foo.conf (Size mismatch)'
  run_case
  grep -q -F "patch.hook: foo" "$sandbox/report.txt" || fail "hooks: name and target missing: $(grep -A3 'Local edits' "$sandbox/report.txt")"
  grep -q -F "secret-exec-sentinel" "$sandbox/report.txt" && fail "hooks: the Exec line is in the report"
  return 0
}

for case_name in timeout_background_tools timeout_checkupdates timeout_fakeroot timeout_file_check timeout_env_validated killed_helper_leaves_nothing no_mise_flag report_old_versions_and_descriptions_once report_caps reboot_checks_only_candidates hooks_show_no_exec_line report_mise_no_paths lock_timeout report_machine_section report_machine_no_identifiers report_machine_unknown report_small_download items_listed items_cap items_hostile items_empty items_fallback mise_missing_summary mise_missing_report report_dev_version_refs report_dir_target lock_private_db lock_without_runtime_dir lock_overlapping_runs summary_ok summary_nothing_pending summary_checkupdates_fails \
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
