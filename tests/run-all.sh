#!/usr/bin/env bash
# Run every test file. Exit non-zero when one of them fails.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
status=0
for test in ./*-test.sh; do
  echo "== $test"
  bash "$test" || status=1
done
echo "== ./model.test.js ./headless.test.js"
node --test ./model.test.js ./headless.test.js || status=1
exit "$status"
