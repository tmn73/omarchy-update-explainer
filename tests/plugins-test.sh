#!/usr/bin/env bash
# Tests for omarchy-update-explainer-plugins. Remotes are local folders, so no
# test makes a network call.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/omarchy-update-explainer-plugins"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
assert_jq() { jq -e "$1" >/dev/null 2>&1 <<<"$2" || fail "$3 (filter: $1)"; }

sandbox=$(mktemp -d)
trap 'rm -rf "$sandbox"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

plugins="$sandbox/plugins"
mkdir -p "$plugins" "$sandbox/remotes"

# make_plugin <id>: a remote with one commit and a checkout of it.
make_plugin() {
  git init -q --initial-branch=main "$sandbox/remotes/$1"
  git -C "$sandbox/remotes/$1" commit -q --allow-empty -m one
  git clone -q "$sandbox/remotes/$1" "$plugins/$1"
}
remote_commit() { git -C "$sandbox/remotes/$1" commit -q --allow-empty -m "$2"; }

run() { out=$(UPDATE_EXPLAINER_PLUGINS_DIR="$plugins" "$HELPER" 2>"$sandbox/stderr"); code=$?; }

# No plugin folder at all.
out=$(UPDATE_EXPLAINER_PLUGINS_DIR="$sandbox/none" "$HELPER" 2>/dev/null)
assert_jq '.state == "ok" and .items == []' "$out" "a missing folder is an empty list"

make_plugin current
make_plugin behind
make_plugin ahead
make_plugin broken
mkdir "$plugins/not-git"
remote_commit behind two
git -C "$plugins/ahead" commit -q --allow-empty -m local
rm -rf "$sandbox/remotes/broken"
# diverged: a local commit and a remote commit. dirty-clash: an edited file that
# the remote changes. dirty-clear: an edited file the remote leaves alone.
make_plugin diverged
make_plugin dirty-clash
make_plugin dirty-clear
for id in diverged dirty-clash dirty-clear; do
  echo base >"$sandbox/remotes/$id/a.txt"; echo base >"$sandbox/remotes/$id/b.txt"
  git -C "$sandbox/remotes/$id" add . && git -C "$sandbox/remotes/$id" commit -q -m files
  git -C "$plugins/$id" pull -q
done
git -C "$plugins/diverged" commit -q --allow-empty -m local
echo mine >"$plugins/dirty-clash/a.txt"
echo mine >"$plugins/dirty-clear/b.txt"
for id in diverged dirty-clash dirty-clear; do
  echo remote >"$sandbox/remotes/$id/a.txt"; git -C "$sandbox/remotes/$id" commit -q -am remote
done

run
[[ $code -eq 0 ]] || fail "exit code is $code"
assert_jq '.state == "ok"' "$out" "state is ok"
assert_jq '.items | map(.name) | sort == ["behind", "dirty-clear"]' "$out" "only plugins that can be fast-forwarded are listed"
assert_jq '(.items | map(select(.name == "behind"))[0] | .from != .to and (.from | length) == 7)' "$out" "short hashes differ"
assert_jq '(.items | map(.name) | index("diverged")) == null' "$out" "a checkout with local commits is not listed"
assert_jq '(.items | map(.name) | index("dirty-clash")) == null' "$out" "an edit in the way of the update is not listed"
assert_jq '(.items | map(.name) | index("ahead")) == null' "$out" "a checkout ahead of its remote is not listed"
assert_jq '(.items | map(.name) | index("broken")) == null' "$out" "a failed fetch is not listed"

# A plugin whose remote has nothing new is not fetched: the check only asks the
# remote for its latest commit, so git writes no FETCH_HEAD there.
[[ -e "$plugins/current/.git/FETCH_HEAD" ]] && fail "a current plugin was fetched"
[[ -e "$plugins/behind/.git/FETCH_HEAD" ]] || fail "a plugin with a new commit was not fetched"

# The folder keeps its files: the helper never merges.
[[ $(git -C "$plugins/behind" rev-parse --short=7 HEAD) == "$(jq -r '.items[] | select(.name == "behind") | .from' <<<"$out")" ]] || fail "the checkout moved"

# --append-report adds the new commit subjects to an existing report file.
report="$sandbox/report.txt"
echo "## Machine" >"$report"
out=$(UPDATE_EXPLAINER_PLUGINS_DIR="$plugins" "$HELPER" --append-report "$report" 2>/dev/null)
assert_jq '.state == "ok"' "$out" "append reports ok"
grep -q '^## Plugins$' "$report" || fail "the report has no Plugins section"
grep -q '^behind: ' "$report" || fail "the report does not name the plugin behind"
grep -q '^  - two$' "$report" || fail "the report does not list the new commit subject"
grep -q '^## Machine$' "$report" || fail "the report lost its earlier content"
out=$(UPDATE_EXPLAINER_PLUGINS_DIR="$plugins" "$HELPER" --append-report "$sandbox/nope.txt" 2>/dev/null)
assert_jq '.state == "error"' "$out" "append refuses a file that does not exist"
"$HELPER" --bogus >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "an unknown argument is not a usage error"

# A folder name with odd characters is skipped.
make_plugin "ok.plugin"
mv "$plugins/ok.plugin" "$plugins/bad name"
run
assert_jq '(.items | map(.name) | index("bad name")) == null' "$out" "an id with a space is skipped"

(( failures == 0 )) && echo "plugins: all checks passed"
exit $(( failures > 0 ))
