#!/usr/bin/env bash
# PR web preview on the gh-pages branch (Pages "deploy from a branch", path /).
#   publish  copy build/web/ to gh-pages:pr-<n>/ (never forced; retried when another push won)
#   comment  create or update ONE sticky PR comment and wait until the build is live;
#            exits 1 when pr-<n>/build.txt does not return HEAD_SHA in time (default 8 min)
#   remove   delete gh-pages:pr-<n>/ and update the comment
# Env: PR, HEAD_SHA (publish and comment), GH_TOKEN, GITHUB_REPOSITORY. Untrusted event data must
# reach this script only through env, never through ${{ }} inside run:.
# Optional env: BUILD_DIR (build/web), MARKER, PAGES_URL, REMOTE_URL, LIVE_TIMEOUT (480 s),
#   POLL_INTERVAL (15 s), BUILD_REQUEST_AFTER (90 s), PUSH_ATTEMPTS (6), PUSH_RETRY_SLEEP (5 s).
# Exit: 0 ok; 1 failed (push, build dir or preview not live); 2 bad usage or env.
set -euo pipefail

cmd="${1:?usage: pages-publish.sh publish|comment|remove}"
[[ "${PR:-}" =~ ^[0-9]+$ ]] || { echo "PR must be a number" >&2; exit 2; }
REPO="${GITHUB_REPOSITORY:?}"
OWNER_LC="$(printf '%s' "${REPO%%/*}" | tr '[:upper:]' '[:lower:]')"
PAGES_URL="${PAGES_URL:-https://${OWNER_LC}.github.io/${REPO#*/}/pr-${PR}/}"
REMOTE_URL="${REMOTE_URL:-https://github.com/${REPO}.git}"
SITE="${RUNNER_TEMP:-/tmp}/gh-pages-site"
BUILD_DIR="${BUILD_DIR:-build/web}"
MARKER="${MARKER:-<!-- rts-mobile-web-preview -->}"
DIR="pr-${PR}"
LIVE_TIMEOUT="${LIVE_TIMEOUT:-480}"
POLL_INTERVAL="${POLL_INTERVAL:-15}"
BUILD_REQUEST_AFTER="${BUILD_REQUEST_AFTER:-90}"
PUSH_ATTEMPTS="${PUSH_ATTEMPTS:-6}"
PUSH_RETRY_SLEEP="${PUSH_RETRY_SLEEP:-5}"
for n in LIVE_TIMEOUT POLL_INTERVAL BUILD_REQUEST_AFTER PUSH_ATTEMPTS PUSH_RETRY_SLEEP; do
  [[ "${!n}" =~ ^[0-9]+$ ]] || { echo "$n must be a non-negative integer" >&2; exit 2; }
done

PUSHED=0
# The site clone holds the token in its git config while it exists; always remove it.
trap 'rm -rf "${SITE:?}"' EXIT

site_git() { git -C "$SITE" "$@"; }

# Retries a command up to 3 times (the GitHub API fails now and then).
retry() {
  local n=0
  until "$@"; do
    n=$((n + 1))
    if [ "$n" -ge 3 ]; then return 1; fi
    sleep $((n * 2))
  done
}

prepare_site() {
  rm -rf "${SITE:?}"
  git init -q -b scratch "$SITE"
  site_git config user.name "github-actions[bot]"
  site_git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  site_git config commit.gpgsign false
  if [ -n "${GH_TOKEN:-}" ]; then
    local b64
    b64="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
    echo "::add-mask::$b64"
    site_git config http.https://github.com/.extraheader "AUTHORIZATION: basic $b64"
  fi
  site_git remote add origin "$REMOTE_URL"
}

put_build() {
  rm -rf "${SITE:?}/$DIR"
  mkdir -p "$SITE/$DIR"
  cp -R "$BUILD_DIR/." "$SITE/$DIR/"
}

drop_build() { rm -rf "${SITE:?}/$DIR"; }

# Re-reads origin/gh-pages, applies "$1", commits and pushes. Never forces: a failed ls-remote or
# fetch (network) and a rejected push (another PR pushed first) are retried on top of the current
# gh-pages, up to PUSH_ATTEMPTS times.
# "$3" = create: also create gh-pages (with .nojekyll) when the branch does not exist yet.
# Sets PUSHED=1 when a commit reached the remote.
update_branch() {
  local change="$1" msg="$2" mode="$3" attempt=0 rc
  PUSHED=0
  while [ "$attempt" -lt "$PUSH_ATTEMPTS" ]; do
    attempt=$((attempt + 1))
    rc=0
    site_git ls-remote --exit-code --heads origin gh-pages >/dev/null || rc=$?
    if [ "$rc" -eq 0 ]; then
      # The depth-1 fetch moves the whole gh-pages tip (tens of MB), so it is the call most likely
      # to hit a transient network error. Retry it like ls-remote; checkout and clean are local.
      if ! site_git fetch -q --depth 1 origin gh-pages; then
        echo "fetch of gh-pages failed (attempt $attempt of $PUSH_ATTEMPTS)" >&2
        if [ "$attempt" -lt "$PUSH_ATTEMPTS" ]; then sleep $((attempt * PUSH_RETRY_SLEEP)); fi
        continue
      fi
      site_git checkout -q -B gh-pages FETCH_HEAD
      site_git clean -q -f -d -x
    elif [ "$rc" -eq 2 ]; then
      if [ "$mode" != "create" ]; then
        echo "gh-pages does not exist; nothing to do"
        return 0
      fi
      echo "gh-pages does not exist yet; creating it"
      site_git symbolic-ref HEAD "refs/heads/init-$attempt"
      site_git read-tree --empty
      site_git clean -q -f -d -x
    else
      echo "cannot reach origin (ls-remote exit $rc, attempt $attempt of $PUSH_ATTEMPTS)" >&2
      if [ "$attempt" -lt "$PUSH_ATTEMPTS" ]; then sleep $((attempt * PUSH_RETRY_SLEEP)); fi
      continue
    fi
    "$change"
    touch "$SITE/.nojekyll"
    site_git add -A
    if site_git diff --cached --quiet; then
      echo "gh-pages already up to date"
      return 0
    fi
    site_git commit -q -m "$msg"
    if site_git push -q origin HEAD:refs/heads/gh-pages; then
      PUSHED=1
      return 0
    fi
    echo "push rejected (attempt $attempt of $PUSH_ATTEMPTS); retrying on top of the new gh-pages"
    if [ "$attempt" -lt "$PUSH_ATTEMPTS" ]; then sleep $((attempt * PUSH_RETRY_SLEEP)); fi
  done
  echo "::error::could not update gh-pages after $PUSH_ATTEMPTS attempts" >&2
  return 1
}

# Prints the id of the sticky comment (the first github-actions[bot] comment that starts with
# MARKER), or nothing.
sticky_id() {
  gh api --paginate "repos/$REPO/issues/$PR/comments?per_page=100" |
    jq -r --arg m "$MARKER" '.[] | select(.user.login == "github-actions[bot]" and (.body | startswith($m))) | .id' |
    sed -n 1p
}

# Usage: upsert_comment BODY [update-only]
upsert_comment() {
  local body="$MARKER"$'\n'"$1" id
  id="$(retry sticky_id)" || return 1
  if [ -n "$id" ]; then
    retry gh api -X PATCH "repos/$REPO/issues/comments/$id" -f body="$body" >/dev/null
  elif [ "${2:-}" != "update-only" ]; then
    retry gh api -X POST "repos/$REPO/issues/$PR/comments" -f body="$body" >/dev/null
  fi
}

# Pushes with GITHUB_TOKEN may not start a Pages build; ask for one. Never fatal.
request_pages_build() {
  gh api -X POST "repos/$REPO/pages/builds" >/dev/null ||
    echo "::warning::Pages build request failed (is Pages enabled for gh-pages /?)"
}

is_live() {
  local got
  got="$(curl -fsS --max-time 10 "${PAGES_URL}build.txt?t=$(date +%s)" 2>/dev/null | tr -d '[:space:]')" || true
  [ "$got" = "$HEAD_SHA" ]
}

require_head_sha() {
  [[ "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo "HEAD_SHA must be a commit SHA" >&2; exit 2; }
}

case "$cmd" in
  publish)
    require_head_sha
    for f in index.html index.js index.wasm index.pck build.txt; do
      [ -s "$BUILD_DIR/$f" ] || { echo "::error::$BUILD_DIR/$f is missing or empty"; exit 1; }
    done
    if [ "$(tr -d '[:space:]' < "$BUILD_DIR/build.txt")" != "$HEAD_SHA" ]; then
      echo "::error::$BUILD_DIR/build.txt does not hold HEAD_SHA"
      exit 1
    fi
    prepare_site
    update_branch put_build "preview: PR #$PR at ${HEAD_SHA:0:7}" create
    ;;
  comment)
    require_head_sha
    short="${HEAD_SHA:0:7}"
    upsert_comment "Web preview for \`$short\` is deploying (1-3 min): $PAGES_URL" ||
      echo "::warning::could not post the deploying comment"
    waited=0
    requested=0
    while true; do
      if is_live; then
        upsert_comment "**Web preview** for \`$short\`: $PAGES_URL"$'\n\n'"Open it on the phone in landscape. Pages caches files for up to 10 min; the build id served at ${PAGES_URL}build.txt must be \`$HEAD_SHA\`."
        exit 0
      fi
      if [ "$waited" -ge "$LIVE_TIMEOUT" ]; then break; fi
      # Docs say GITHUB_TOKEN pushes do not start a Pages build; ask for one if nothing went live.
      if [ "$requested" -eq 0 ] && [ "$waited" -ge "$BUILD_REQUEST_AFTER" ]; then
        request_pages_build
        requested=1
      fi
      sleep "$POLL_INTERVAL"
      waited=$((waited + POLL_INTERVAL))
    done
    upsert_comment "Web preview for \`$short\` was pushed but is **not live (timed out)** after ${LIVE_TIMEOUT} s: $PAGES_URL (see the pages-build-deployment run in Actions)." ||
      echo "::warning::could not post the timeout comment"
    echo "::error::preview not live after ${LIVE_TIMEOUT} s: ${PAGES_URL}build.txt never returned $HEAD_SHA"
    exit 1
    ;;
  remove)
    prepare_site
    update_branch drop_build "preview: remove PR #$PR" keep
    if [ "$PUSHED" -eq 1 ]; then request_pages_build; fi
    upsert_comment "Web preview removed (PR closed)." update-only ||
      echo "::warning::could not update the preview comment"
    ;;
  *)
    echo "unknown command: $cmd" >&2
    exit 2
    ;;
esac
