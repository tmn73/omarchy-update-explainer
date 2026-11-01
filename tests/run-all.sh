#!/usr/bin/env bash
# Run every test file. Exit non-zero when one of them fails.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
status=0
for test in ./*-test.sh; do
  echo "== $test"
  bash "$test" || status=1
done
exit "$status"
