#!/usr/bin/env bash
# Tests for omarchy-update-explainer-notes. A local web server stands in for the
# Arch GitLab, the AUR and the GitHub API, so no test uses the real network.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/omarchy-update-explainer-notes"

failures=0
fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
has() { grep -qF -- "$2" "$1" || fail "$3 (missing: $2)"; }
hasnt() { ! grep -qF -- "$2" "$1" || fail "$3 (found: $2)"; }

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq is missing"; exit 0; }

sandbox=$(mktemp -d)
web="$sandbox/web"
mkdir -p "$web"
port=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$web" >/dev/null 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null; rm -rf "$sandbox"' EXIT
for _ in $(seq 1 50); do curl -s "http://127.0.0.1:$port/" >/dev/null 2>&1 && break; sleep 0.1; done

base="http://127.0.0.1:$port"
export UPDATE_EXPLAINER_ARCH_RAW="$base/arch"
export UPDATE_EXPLAINER_AUR_BASE="$base/aur"
export UPDATE_EXPLAINER_GITHUB_API="$base/gh"
export UPDATE_EXPLAINER_NOTES_CACHE="$sandbox/cache"
export UPDATE_EXPLAINER_FETCH_TIMEOUT=5

# Official package "foo": site url, GitHub only in source.
mkdir -p "$web/arch/foo/-/raw/main" "$web/arch/bar/-/raw/main" "$web/gh/repos/acme/foo" "$web/aur/plain"
printf 'url="https://foo.example"\nsource=("https://github.com/acme/foo/releases/download/v${pkgver}/foo.tar.gz")\n' >"$web/arch/foo/-/raw/main/PKGBUILD"
printf 'url="https://bar.example"\nsource=("https://bar.example/bar.tar.gz")\n' >"$web/arch/bar/-/raw/main/PKGBUILD"
printf 'url=x\nsource=("git+https://github.com/GloriousEggroll/proton-ge-custom.git")\n' >"$web/aur/plain/PKGBUILD"
printf '[{"tag_name":"v1.0.0","body":"old"},{"tag_name":"v1.1.0","body":"You can now do a thing.\\u0007\\nSecond line."}]' >"$web/gh/repos/acme/foo/releases"
mkdir -p "$web/arch/big/-/raw/main" "$web/gh/repos/acme/big"
printf 'url=x\nsource=("https://github.com/acme/big/archive/v${pkgver}.tar.gz")\n' >"$web/arch/big/-/raw/main/PKGBUILD"
{ printf '[{"tag_name":"v1.1","body":"'; head -c 2000000 /dev/zero | tr '\0' 'x'; printf '"}]'; } >"$web/gh/repos/acme/big/releases"
mkdir -p "$web/gh/repos/GloriousEggroll/proton-ge-custom"
printf '[{"tag_name":"GE-Proton11-12","body":"# GE-Proton11-12\\nWine got newer."}]' >"$web/gh/repos/GloriousEggroll/proton-ge-custom/releases"

report="$sandbox/report.txt"
cat >"$report" <<'R'
## This machine
model: test

## Pacman packages
foo 1:1.0.0-1 -> 1:1.1.0-2 [extra] 1 MiB | foo
bar 2.0-1 -> 2.1-1 [extra] 1 MiB | bar has no GitHub source
rebuilt 3.0-1 -> 3.0-2 [extra] 1 MiB | same upstream version
omarchy-dev 1-1 -> 1-2 [omarchy] 1 MiB | not on the Arch GitLab
big 1.0-1 -> 1.1-1 [extra] 1 MiB | answer larger than the cap
.. 1-1 -> 2-1 [extra] 1 MiB | a name that is a path
TOTAL download: 4 MiB

## AUR
proton-ge-custom-bin 1:GE_Proton11_11-1 -> 1:GE_Proton11_12-1 [3h]

## Reboot hints
(none)
R

out=$("$HELPER" --append-report "$report" 2>"$sandbox/stderr")
[[ $out == '{"state":"ok"}' ]] || fail "unexpected output: $out"
has "$report" '## Release notes' "the section is added"
has "$report" '### foo 1:1.0.0-1 -> 1:1.1.0-2' "foo is listed"
has "$report" 'You can now do a thing.' "the notes of the new version are used, not the old ones"
hasnt "$report" 'old' "the notes of the old version are left out"
has "$report" 'project: acme/foo' "the GitHub project is named"
has "$report" '### bar 2.0-1 -> 2.1-1' "a package without GitHub is still listed"
has "$report" '(no release notes found)' "a missing note says so"
hasnt "$report" '### rebuilt' "a rebuild is skipped"
hasnt "$report" '### omarchy-dev' "a package from the omarchy repository is skipped"
has "$report" '### big 1.0-1 -> 1.1-1' "an oversized answer is still listed"
hasnt "$report" 'xxxxxxxxxx' "an oversized answer is cut, not read"
hasnt "$report" '### ..' "a package name that is a path is skipped"
has "$report" 'Wine got newer.' "an AUR package matches a tag with other punctuation"
hasnt "$report" $'\a' "control characters are removed"
[[ -s "$sandbox/cache/foo-1_1.1.0-2" ]] || fail "the notes are cached"

# The cache answers when the server is gone.
cp "$report" "$sandbox/report.first"
kill "$server" 2>/dev/null; wait "$server" 2>/dev/null
cat >"$report" <<'R'
## Pacman packages
foo 1:1.0.0-1 -> 1:1.1.0-2 [extra] 1 MiB | foo
R
"$HELPER" --append-report "$report" >/dev/null 2>&1
has "$report" 'You can now do a thing.' "a cached package needs no network"

# A report with nothing to explain stays as it is.
printf '## Pacman packages\n(none)\n' >"$report"
before=$(<"$report")
"$HELPER" --append-report "$report" >/dev/null 2>&1
[[ $(<"$report") == "$before" ]] || fail "an empty list changes the report"

# Bad calls.
"$HELPER" >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "no argument is a usage error"
out=$("$HELPER" --append-report "$sandbox/missing" 2>/dev/null)
[[ $out == *'"state":"error"'* ]] || fail "a missing report is an error: $out"
ln -s "$report" "$sandbox/link"
out=$("$HELPER" --append-report "$sandbox/link" 2>/dev/null)
[[ $out == *'"state":"error"'* ]] || fail "a symlink report is refused: $out"

(( failures == 0 )) && echo "notes-test: ok" || exit 1
