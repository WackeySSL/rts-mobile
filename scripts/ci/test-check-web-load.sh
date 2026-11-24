#!/usr/bin/env bash
# Offline test of scripts/ci/check-web-load.sh (P451b): the usage errors, and the verdict for a console
# with and without a script error, against a stub `playwright` module (no browser, no Godot).
# Needs: bash, python3, node. ci.yml runs it in the verify job.
# Usage: bash scripts/ci/test-check-web-load.sh      Exit: 0 all cases pass, 1 a case failed, 3 a tool is missing.
set -euo pipefail
for tool in python3 node; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "test-check-web-load: $tool is missing" >&2
    exit 3
  }
done
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
mkdir -p "$root/site" "$root/mods/playwright"
echo '<html></html>' >"$root/site/index.html"
# The stub replays the lines of FAKE_CONSOLE (one per line) as console messages when the page loads.
cat >"$root/mods/playwright/index.js" <<'JS'
module.exports = {
  devices: { 'Pixel 7': {} },
  chromium: {
    launch: async () => ({
      close: async () => {},
      newContext: async () => ({
        newPage: async () => {
          const handlers = [];
          return {
            on: (ev, fn) => { if (ev === 'console') handlers.push(fn); },
            goto: async () => {
              for (const text of (process.env.FAKE_CONSOLE || '').split('\n').filter(Boolean)) {
                handlers.forEach((fn) => fn({ text: () => text }));
              }
            },
            waitForTimeout: async () => {},
          };
        },
      }),
    }),
  },
};
JS
failures=0
expect() { # name, expected exit, command...
  local name="$1" want="$2" rc=0
  shift 2
  "$@" >"$root/out" 2>&1 || rc=$?
  if [ "$rc" -ne "$want" ]; then
    echo "FAIL $name: exit $rc, wanted $want"
    sed 's/^/    /' "$root/out"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}
check="$repo/scripts/ci/check-web-load.sh"
export NODE_PATH="$root/mods"
expect "no directory" 2 bash "$check"
expect "missing directory" 2 bash "$check" "$root/nowhere"
expect "bad port" 2 bash "$check" --port x "$root/site"
expect "unknown flag" 2 bash "$check" --nope "$root/site"
FAKE_CONSOLE=$'Godot Engine v4.7.2\nGL Driver Message' expect "clean console" 0 bash "$check" --port 8893 --seconds 1 "$root/site"
FAKE_CONSOLE=$'Godot Engine\nSCRIPT ERROR: Parse Error: Cannot find member "new" in base "X".' expect "parse error" 1 bash "$check" --port 8893 --seconds 1 "$root/site"
grep -q 'Parse Error' "$root/out" || {
  echo "FAIL the failing run did not print the matching line"
  failures=$((failures + 1))
}
FAKE_CONSOLE='ERROR: Failed to load script "res://a.gd" with error "Compilation failed".' expect "failed to load script" 1 bash "$check" --port 8893 --seconds 1 "$root/site"
if [ "$failures" -ne 0 ]; then
  echo "test-check-web-load: $failures case(s) failed" >&2
  exit 1
fi
echo "test-check-web-load: all cases pass"
