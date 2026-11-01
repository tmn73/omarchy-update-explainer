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

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT

# Fresh sandbox PATH per case: system basics plus the stubs that the case keeps.
make_sandbox() {
  rm -rf "$sandbox/bin"
  mkdir -p "$sandbox/bin"
  local tool path
  for tool in bash cat rm mv mktemp jq date grep head awk tr sed cut sort wc env dirname; do
    path=$(command -v "$tool" 2>/dev/null) && ln -sf "$path" "$sandbox/bin/$tool"
  done
  for tool in checkupdates fakeroot pacman expac yay mise; do
    [[ " ${SKIP:-} " == *" $tool "* ]] || ln -sf "$STUBS/$tool" "$sandbox/bin/$tool"
  done
}

# run_case: sets $out and $code. Env vars set by the caller reach the stubs.
run_case() {
  make_sandbox
  out=$(PATH="$sandbox/bin" "$HELPER" --summary 2>"$sandbox/stderr")
  code=$?
  if grep -q "command not found" "$sandbox/stderr"; then
    fail "helper stderr has 'command not found': $(head -c 300 "$sandbox/stderr")"
  fi
}

reset_env() {
  unset SKIP STUB_CHECK_EXIT STUB_CHECK_ERR STUB_TRANSACTION STUB_KERNEL_PKG \
    STUB_OLD_VERSIONS STUB_DESC STUB_CHECK_OUT STUB_FAKEROOT_EXIT STUB_AUR STUB_MISE
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

for case_name in summary_ok summary_nothing_pending summary_checkupdates_fails \
  summary_tool_missing summary_reboot_kernel summary_hostile_names summary_malformed_line summary_transaction_fails; do
  before=$failures
  "$case_name"
  (( failures == before )) && echo "ok   $case_name" || echo "FAIL $case_name"
done

if (( failures > 0 )); then
  echo "$failures assertion(s) failed" >&2
  exit 1
fi
echo "all passed"
