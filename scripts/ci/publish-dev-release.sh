#!/usr/bin/env bash
# Replace the rolling pre-release android-dev-latest (ADR 0005 section 6) with the debug APK that
# the android-debug-apk job of THIS run built. Only the release jobs of ci.yml call it (push to main):
# android-dev-release as above, and android-perf-release with the profile perf, which replaces the rolling
# pre-release android-perf-release with the release-template perf APK of the android-perf-apk job (P51r,
# Michael's answer 3 in the Phase 2 plan), by the same rules.
# It deletes and recreates the release, so the caller must serialize runs: ci.yml does with a concurrency
# group. Running it again after a failure is safe, it starts from scratch.
# Usage: bash scripts/ci/publish-dev-release.sh DIR [dev|perf]
#   DIR  the downloaded CI artifact: rts-mobile-debug.apk (perf: rts-mobile-perf-release.apk) and
#        THIRD_PARTY_LICENSES.txt
#   dev|perf  the profile, dev by default. perf is always signed with a key generated for the run (no store key).
# Env (required): GH_TOKEN (contents: write), GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_SERVER_URL and
#   GITHUB_RUN_ID (the runner sets the last four).
# Env (optional): KEY_KIND stable|generated|unknown (default unknown; goes into the notes; perf ignores it),
#   GITHUB_STEP_SUMMARY.
# If the live release is already on a newer commit than GITHUB_SHA (an old run re-run after a newer
# one published), it keeps that release and exits 0, so the stable URL never goes back in time.
# After creating the release it checks: published pre-release, both assets present with the local
# APK size, the tag on GITHUB_SHA, and the stable download URL serving a file with the local SHA-256.
# Exit: 0 ok or kept a newer release; 1 failed (a file, a gh call or a check); 2 bad usage or env.
set -euo pipefail

NOTICE_NAME="THIRD_PARTY_LICENSES.txt"

die() {
  local code="$1"
  shift
  echo "publish-dev-release: $*" >&2
  exit "$code"
}

[ $# -ge 1 ] && [ $# -le 2 ] && [ -n "$1" ] || die 2 "usage: bash scripts/ci/publish-dev-release.sh DIR [dev|perf]"
dir="${1%/}"
profile="${2:-dev}"
case "$profile" in
  dev)
    TAG="android-dev-latest"
    APK_NAME="rts-mobile-debug.apk"
    TITLE="Android dev build (latest main)"
    intro="Rolling debug build of \`main\`. Every push to \`main\` replaces this pre-release (ADR 0005)."
    build="debug build"
    ;;
  perf)
    TAG="android-perf-release"
    APK_NAME="rts-mobile-perf-release.apk"
    TITLE="Android perf build (release template, latest main)"
    intro="Rolling release-template build of \`main\` for the perf gate (ADR 0012 section 4), with the dev menu. Every push to \`main\` replaces this pre-release. It is no store build: no real ad ID and no store key."
    build="release template with the dev menu"
    ;;
  *) die 2 "the profile must be dev or perf, not '$profile'" ;;
esac
for v in GH_TOKEN GITHUB_REPOSITORY GITHUB_SHA GITHUB_SERVER_URL GITHUB_RUN_ID; do
  [ -n "${!v:-}" ] || die 2 "$v is not set"
done
[[ "$GITHUB_SHA" =~ ^[0-9a-f]{40}$ ]] || die 2 "GITHUB_SHA is not a full commit SHA"
key_kind="${KEY_KIND:-unknown}"
[ "$profile" = dev ] || key_kind=generated
case "$key_kind" in
  stable | generated | unknown) ;;
  *) die 2 "KEY_KIND must be stable, generated or unknown, not '$key_kind'" ;;
esac

apk="$dir/$APK_NAME"
notice="$dir/$NOTICE_NAME"
[ -s "$apk" ] || die 1 "$apk is missing or empty"
[ -s "$notice" ] || die 1 "$notice is missing or empty"
size="$(stat -c %s "$apk")"
sha256="$(sha256sum "$apk" | cut -d' ' -f1)"
repo_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY"
download_url="$repo_url/releases/download/$TAG/$APK_NAME"

work="$(mktemp -d)"
trap 'rm -rf "${work:?}"' EXIT

if [ "$key_kind" = stable ]; then
  key_note="stable debug key: installs over an earlier android-dev-latest build signed with the same key; uninstall a PR or generated-key build first."
else
  key_note="key generated for this run: uninstall the previous rts-mobile build before installing."
fi
cat >"$work/notes.md" <<EOF
$intro

- Commit: [\`$GITHUB_SHA\`]($repo_url/commit/$GITHUB_SHA)
- Run: $repo_url/actions/runs/$GITHUB_RUN_ID
- Package \`dk.appcode.rts.dev\`, arm64, $build. SHA-256 of $APK_NAME: \`$sha256\`
- Signing: $key_note
- $NOTICE_NAME lists the licences of the bundled engine and must stay with the APK.
- Download: $download_url
EOF

# Start from scratch: the old release and its tag, or a tag left behind by a failed run.
release_api="repos/$GITHUB_REPOSITORY/releases/tags/$TAG"
if gh api "$release_api" >/dev/null 2>&1; then
  # Concurrency orders runs that overlap, not an old run that is re-run later. Keep a newer release.
  live="$(gh api "repos/$GITHUB_REPOSITORY/commits/$TAG" --jq .sha 2>/dev/null || true)"
  if [ -n "$live" ] && [ "$live" != "$GITHUB_SHA" ]; then
    rel="$(gh api "repos/$GITHUB_REPOSITORY/compare/$GITHUB_SHA...$live" --jq .status 2>/dev/null || true)"
    if [ "$rel" = ahead ]; then
      echo "- Pre-release \`$TAG\` is on newer commit \`$live\`; kept it, nothing published for \`$GITHUB_SHA\`." >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
      echo "publish-dev-release: $TAG is on newer commit $live, keeping it (this run is $GITHUB_SHA)"
      exit 0
    fi
  fi
  gh release delete "$TAG" --repo "$GITHUB_REPOSITORY" --yes --cleanup-tag
fi
if gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$TAG" >/dev/null 2>&1; then
  gh api -X DELETE "repos/$GITHUB_REPOSITORY/git/refs/tags/$TAG"
fi
gh release create "$TAG" "$apk" "$notice" \
  --repo "$GITHUB_REPOSITORY" \
  --target "$GITHUB_SHA" \
  --title "$TITLE" \
  --notes-file "$work/notes.md" \
  --prerelease

info="$(gh api "$release_api" --jq '{prerelease, draft, assets: [.assets[] | {name, size, state}]}')" ||
  die 1 "release $TAG not found after creating it"
jq -e --arg apk "$APK_NAME" --argjson size "$size" --arg notice "$NOTICE_NAME" '
  .prerelease and (.draft | not)
  and ([.assets[] | select(.name == $apk and .size == $size and .state == "uploaded")] | length == 1)
  and ([.assets[] | select(.name == $notice and .state == "uploaded")] | length == 1)' <<<"$info" >/dev/null ||
  die 1 "the release is not a published pre-release with both assets uploaded: $info"
tag_sha="$(gh api "repos/$GITHUB_REPOSITORY/commits/$TAG" --jq .sha)"
[ "$tag_sha" = "$GITHUB_SHA" ] || die 1 "tag $TAG is on $tag_sha, not on $GITHUB_SHA"

# The contract is the stable URL: download it the way the phone does and compare. Assets can lag
# behind the API for a moment, so try a few times.
served=""
for attempt in 1 2 3 4; do
  if curl -fsSL --retry 2 --retry-delay 3 -o "$work/served.apk" "$download_url" 2>/dev/null; then
    served="$(sha256sum "$work/served.apk" | cut -d' ' -f1)"
    [ "$served" = "$sha256" ] && break
  fi
  if [ "$attempt" -lt 4 ]; then sleep 5; fi
done
[ "$served" = "$sha256" ] || die 1 "$download_url serves '${served:-nothing}', expected $sha256"

echo "- Pre-release [\`$TAG\`]($repo_url/releases/tag/$TAG): $download_url ($size bytes, SHA-256 \`$sha256\`)" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "publish-dev-release: OK $download_url"
