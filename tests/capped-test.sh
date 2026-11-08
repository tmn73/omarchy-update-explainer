#!/usr/bin/env bash
# Tests for omarchy-update-explainer-capped.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CAPPED="$ROOT/omarchy-update-explainer-capped"
failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }

out=$("$CAPPED" 10 printf 'abcdefghijklmnopqrstuvwxyz')
[[ $out == abcdefghij ]] || fail "the output is not cut at the cap: $out"

out=$("$CAPPED" 100 printf 'short')
[[ $out == short ]] || fail "a short output is changed: $out"

"$CAPPED" 100 false; [[ $? -ne 0 ]] || fail "a failed command reports success"
"$CAPPED" >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "no argument is not a usage error"
"$CAPPED" 0 true >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "a zero cap is accepted"
"$CAPPED" 10x true >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "a cap that is not a number is accepted"

# A stop signal stops the command too, not only the helper.
marker="capped-test-$$-$RANDOM"
"$CAPPED" 100 bash -c "exec -a $marker sleep 60" &
helper=$!
sleep 0.5
pgrep -f "$marker" >/dev/null || fail "the command did not start"
kill -TERM "$helper"
wait "$helper" 2>/dev/null
sleep 0.5
pgrep -f "$marker" >/dev/null && { fail "the command survives the stop signal"; pkill -f "$marker"; }

(( failures == 0 )) && echo "capped-test: ok" || exit 1
