#!/usr/bin/env bash
# Offline test of publish-dev-release.sh. It runs the real script against a stub gh, curl and sleep
# on PATH, so no token, network or release is touched. ci.yml runs it in android-debug-apk, before
# the release job can run on main. State of the fake repo lives in files under $STUB_STATE.
# The perf profile (P51r, android-perf-release) runs the same cases against its own tag, APK and notes.
# Usage: bash scripts/ci/test-publish-dev-release.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/publish-dev-release.sh"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
mkdir "$root/bin" "$root/apk" "$root/state" "$root/empty"
printf 'apk-bytes' >"$root/apk/rts-mobile-debug.apk"
printf 'perf-apk!' >"$root/apk/rts-mobile-perf-release.apk"
printf 'licences' >"$root/apk/THIRD_PARTY_LICENSES.txt"

cat >"$root/bin/gh" <<'STUB'
#!/usr/bin/env bash
S="$STUB_STATE"
echo "gh $*" >>"$S/log"
if [ "$1" = release ] && [ "$2" = delete ]; then rm -f "$S/release" "$S/tag" "$S/pre"; exit 0; fi
if [ "$1" = release ] && [ "$2" = create ]; then
  [ ! -f "$S/create-fails" ] || exit 1
  while [ $# -gt 0 ]; do
    [ "$1" = --target ] && echo "$2" >"$S/tag"
    [ "$1" = --notes-file ] && cp "$2" "$S/notes"
    [ "$1" = --prerelease ] && : >"$S/pre"
    shift
  done
  [ ! -f "$S/wrong-tag" ] || cp "$S/wrong-tag" "$S/tag"
  : >"$S/release"; exit 0
fi
[ "$1" = api ] || exit 9
shift
if [ "$1" = -X ]; then rm -f "$S/tag"; exit 0; fi
path="$1"; shift
pre=false; [ ! -f "$S/pre" ] || pre=true
size=9; [ ! -f "$S/size" ] || size="$(cat "$S/size")"
case "$path" in
  */releases/tags/*) [ -f "$S/release" ] || exit 1
    json="{\"prerelease\":$pre,\"draft\":false,\"assets\":[{\"name\":\"$(cat "$S/apk-name")\",\"size\":$size,\"state\":\"uploaded\"},{\"name\":\"THIRD_PARTY_LICENSES.txt\",\"size\":8,\"state\":\"uploaded\"}]}" ;;
  */git/ref/tags/*) [ -f "$S/tag" ] || exit 1; json='{}' ;;
  */commits/*) [ -f "$S/tag" ] || exit 1; json="{\"sha\":\"$(cat "$S/tag")\"}" ;;
  */compare/*) json="{\"status\":\"$(cat "$S/compare")\"}" ;;
  *) exit 9 ;;
esac
if [ "${1:-}" = --jq ]; then jq -r "$2" <<<"$json"; else echo "$json"; fi
STUB
cat >"$root/bin/curl" <<'STUB'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = -o ] && out="$2"; shift; done
cat "$STUB_STATE/served" >"$out"
STUB
printf '#!/usr/bin/env bash\nexit 0\n' >"$root/bin/sleep"
chmod +x "$root/bin/gh" "$root/bin/curl" "$root/bin/sleep"

run_sha="$(printf 'b%.0s' {1..40})" # the commit of the run under test
other="$(printf 'a%.0s' {1..40})"   # the commit a live tag is on
failures=0
profile="" # the second argument of the script: empty for dev, perf for the perf profile
apk_name="rts-mobile-debug.apk"
# run_case NAME WANT_RC LOG_REGEX DIR [VAR=value ...]  (the state files are set by the caller)
run_case() {
  local name="$1" want="$2" regex="$3" dir="$4" rc=0
  shift 4
  : >"$root/state/log"
  env -i PATH="$root/bin:$PATH" STUB_STATE="$root/state" GH_TOKEN=x GITHUB_REPOSITORY=o/r \
    GITHUB_SHA="$run_sha" GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=1 "$@" \
    bash "$script" "$dir" $profile >"$root/state/out" 2>&1 || rc=$?
  if [ "$rc" = "$want" ] && grep -Eq "$regex" "$root/state/log" "$root/state/out"; then
    echo "ok: $name (exit $rc)"
  else
    echo "FAIL: $name: exit $rc, wanted $want, log or output must match /$regex/"
    cat "$root/state/out" "$root/state/log"
    failures=$((failures + 1))
  fi
}
not_in_log() { # not_in_log REGEX WHY
  if grep -Eq "$1" "$root/state/log"; then echo "FAIL: $2"; failures=$((failures + 1)); fi
}
reset() { # reset [release] [TAG_SHA]: a fake repo with this release and a tag on this commit
  rm -f "$root/state"/{release,tag,pre,size,wrong-tag,create-fails,notes}
  echo "$apk_name" >"$root/state/apk-name"
  cp "$root/apk/$apk_name" "$root/state/served"
  echo behind >"$root/state/compare"
  for a in "$@"; do if [ "$a" = release ]; then : >"$root/state/release"; else echo "$a" >"$root/state/tag"; fi; done
}

reset
run_case "empty argument" 2 'usage' ""
run_case "GH_TOKEN unset" 2 'GH_TOKEN is not set' "$root/apk" GH_TOKEN=
run_case "GITHUB_SHA not a SHA" 2 'full commit SHA' "$root/apk" GITHUB_SHA=main
run_case "KEY_KIND unknown value" 2 'KEY_KIND must be' "$root/apk" KEY_KIND=other
run_case "empty directory" 1 'missing or empty' "$root/empty"

reset
run_case "first publish" 0 'release create' "$root/apk"
not_in_log 'release delete' "first publish deleted something"
reset release "$other"
run_case "replace an older release" 0 'release delete.*cleanup-tag' "$root/apk"
reset "$other"
run_case "delete a stale tag without release" 0 'api -X DELETE .*refs/tags/android-dev-latest' "$root/apk"
reset release "$run_sha"
echo ahead >"$root/state/compare" # never consulted for the commit of this very run
run_case "re-run of the same commit republishes" 0 'release delete' "$root/apk"
reset release "$other"
echo ahead >"$root/state/compare"
run_case "live tag on a newer commit is kept" 0 'keeping it' "$root/apk"
not_in_log 'release (delete|create)' "the newer release was touched"
reset release "$other"
echo diverged >"$root/state/compare"
run_case "live tag on a diverged commit is replaced" 0 'release delete' "$root/apk"

reset
touch "$root/state/create-fails"
run_case "failing create exits 1" 1 'release create' "$root/apk"
reset
echo 3 >"$root/state/size"
run_case "uploaded asset with the wrong size exits 1" 1 'not a published pre-release' "$root/apk"
reset
echo "$other" >"$root/state/wrong-tag"
run_case "tag not on the run commit exits 1" 1 'not on' "$root/apk"
reset
printf 'other' >"$root/state/served"
run_case "stable URL serving other bytes exits 1" 1 'serves' "$root/apk"

# P51r: the perf profile publishes android-perf-release, with its own APK name, title and notes.
profile=perf
apk_name="rts-mobile-perf-release.apk"
reset
run_case "perf: first publish" 0 'release create android-perf-release .*rts-mobile-perf-release\.apk .*--title Android perf build \(release template, latest main\)' "$root/apk"
grep -Fq 'release template with the dev menu' "$root/state/notes" || { echo "FAIL: perf: the notes do not name the build"; failures=$((failures + 1)); }
grep -Fq 'key generated for this run: uninstall the previous rts-mobile build' "$root/state/notes" ||
  { echo "FAIL: perf: the notes do not say that the key is generated"; failures=$((failures + 1)); }
grep -Fq 'no store key' "$root/state/notes" || { echo "FAIL: perf: the notes do not say that it is no store build"; failures=$((failures + 1)); }
not_in_log 'android-dev-latest' "perf: the dev tag was touched"
reset release "$other"
run_case "perf: replace an older release" 0 'release delete android-perf-release --repo o/r --yes --cleanup-tag' "$root/apk"
reset "$other"
run_case "perf: delete a stale tag without release" 0 'api -X DELETE .*refs/tags/android-perf-release' "$root/apk"
reset release "$other"
echo ahead >"$root/state/compare"
run_case "perf: live tag on a newer commit is kept" 0 'android-perf-release is on newer commit' "$root/apk"
not_in_log 'release (delete|create)' "perf: the newer release was touched"
reset
run_case "perf: KEY_KIND is ignored, the key is generated" 0 'release create' "$root/apk" KEY_KIND=stable
grep -Fq 'key generated for this run' "$root/state/notes" || { echo "FAIL: perf: KEY_KIND=stable reached the notes"; failures=$((failures + 1)); }
reset
printf 'other' >"$root/state/served"
run_case "perf: stable URL serving other bytes exits 1" 1 'serves' "$root/apk"
mkdir "$root/debug-only"
cp "$root/apk/rts-mobile-debug.apk" "$root/apk/THIRD_PARTY_LICENSES.txt" "$root/debug-only/"
run_case "perf: a folder with only the debug APK" 1 'rts-mobile-perf-release\.apk is missing or empty' "$root/debug-only"
profile=other
run_case "unknown profile" 2 'profile must be dev or perf' "$root/apk"

[ "$failures" = 0 ] || { echo "test-publish-dev-release: $failures case(s) failed" >&2; exit 1; }
echo "test-publish-dev-release: OK"
