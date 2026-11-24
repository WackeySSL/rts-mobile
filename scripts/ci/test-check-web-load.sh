#!/usr/bin/env bash
# Offline test of scripts/ci/check-web-load.sh (P451b): the usage errors, and the verdict for each console and
# menu behaviour, against a stub `playwright` module (no browser, no Godot).
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
# The stub plays the part of the browser. On every load of index.html it replays the lines of FAKE_CONSOLE (one per
# line) as console messages, and throws FAKE_PAGEERROR as an uncaught page error. The screen is static until a
# tap, then changes; FAKE_MENU=dead keeps it static after the tap, FAKE_MENU=animated changes it all the time.
# FAKE_LATE_ERROR is a console line the tap produces. FAKE_SEED_FAIL makes the evaluate that writes the save throw.
# FAKE_SAVE_READ is what the save reads back as (default: a save with xp=500).
cat >"$root/mods/playwright/index.js" <<'JS'
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, Math.min(ms, 20)));
module.exports = {
  devices: { 'Pixel 7': {} },
  chromium: {
    launch: async () => ({
      close: async () => {},
      newContext: async () => ({
        newPage: async () => {
          const handlers = [];
          const errHandlers = [];
          let shots = 0;
          let tapped = false;
          return {
            on: (ev, fn) => { (ev === 'console' ? handlers : errHandlers).push(fn); },
            close: async () => {},
            viewportSize: () => ({ width: 412, height: 839 }),
            touchscreen: {
              tap: async () => {
                tapped = true;
                if (process.env.FAKE_LATE_ERROR) handlers.forEach((fn) => fn({ text: () => process.env.FAKE_LATE_ERROR }));
              },
            },
            screenshot: async () => {
              if (process.env.FAKE_MENU === 'animated') return Buffer.from('frame' + shots++);
              return Buffer.from(tapped && process.env.FAKE_MENU !== 'dead' ? 'next screen' : 'main menu');
            },
            evaluate: async (fn, arg) => {
              if (arg && arg.dir) {
                if (process.env.FAKE_SEED_FAIL) throw new Error('VersionError');
                return undefined;
              }
              if (typeof arg === 'string') return process.env.FAKE_SAVE_READ === undefined ? 'xp=500\n' : process.env.FAKE_SAVE_READ;
              return String(fn).includes('status-notice') ? 'stub page text' : 0;
            },
            goto: async (url) => {
              if (!/index\.html$/.test(url)) return;
              if (process.env.FAKE_PAGEERROR) errHandlers.forEach((fn) => fn(new Error(process.env.FAKE_PAGEERROR)));
              for (const text of (process.env.FAKE_CONSOLE || '').split('\n').filter(Boolean)) {
                handlers.forEach((fn) => fn({ text: () => text }));
              }
            },
            waitForTimeout: sleep,
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
printed() { # what the last run must have printed
  grep -q -- "$1" "$root/out" || {
    echo "FAIL the last run did not print '$1'"
    sed 's/^/    /' "$root/out"
    failures=$((failures + 1))
  }
}
check="$repo/scripts/ci/check-web-load.sh"
export NODE_PATH="$root/mods"
expect "no directory" 2 bash "$check"
expect "missing directory" 2 bash "$check" "$root/nowhere"
expect "bad port" 2 bash "$check" --port x "$root/site"
expect "port above 65535" 2 bash "$check" --port 65536 "$root/site"
expect "bad boot timeout" 2 bash "$check" --boot-timeout 0 "$root/site"
expect "unknown flag" 2 bash "$check" --nope "$root/site"
run="bash $check --port 8893 --seconds 1 --boot-timeout 1 $root/site"
# shellcheck disable=SC2086 # $run is a word list on purpose
FAKE_CONSOLE=$'Godot Engine v4.7.2\nGL Driver Message\nboot_ms=5123' expect "marker then clean" 0 $run
printed 'boot_ms=5123'
# shellcheck disable=SC2086
FAKE_CONSOLE=$'Godot Engine v4.7.2\nGL Driver Message' expect "no marker" 3 $run
printed 'GL Driver Message'
printed 'stub page text'
# shellcheck disable=SC2086
FAKE_CONSOLE=$'Godot Engine\nSCRIPT ERROR: Parse Error: Cannot find member "new" in base "X".\n   at: GDScript::reload (res://a.gd:12)' expect "parse error before marker" 1 $run
printed 'a.gd:12'
# shellcheck disable=SC2086
FAKE_CONSOLE=$'boot_ms=5000\nERROR: Failed to load script "res://a.gd" with error "Compilation failed".' expect "failed to load script after marker" 1 $run
# shellcheck disable=SC2086
FAKE_CONSOLE=$'boot_error: res://menu.tscn did not load' expect "boot_error" 1 $run
# shellcheck disable=SC2086
FAKE_PAGEERROR='RuntimeError: abort' expect "page error" 1 $run
# An "at:" line that does not follow a hit is not collected.
# shellcheck disable=SC2086
FAKE_CONSOLE=$'boot_ms=5000\n   at: stray (res://b.gd:1)' expect "stray at: line" 0 $run
# Phase 2: the menu does not answer the tap, a screen that never stops changing, an error after the tap, and the
# save that cannot be written or is not there after the boot.
# shellcheck disable=SC2086
FAKE_MENU=dead FAKE_CONSOLE='boot_ms=5000' expect "dead menu" 4 $run
printed 'did not answer'
# shellcheck disable=SC2086
FAKE_MENU=animated FAKE_CONSOLE='boot_ms=5000' expect "animated screen, no main menu" 4 $run
printed 'kept changing'
# shellcheck disable=SC2086
FAKE_LATE_ERROR='SCRIPT ERROR: Invalid call. Nonexistent function.' FAKE_CONSOLE='boot_ms=5000' expect "error after the tap" 1 $run
printed 'after the tap on SKIRMISH'
# shellcheck disable=SC2086
FAKE_SAVE_READ='' FAKE_CONSOLE='boot_ms=5000' expect "save not read back" 3 $run
printed 'not in IndexedDB'
# shellcheck disable=SC2086
FAKE_SEED_FAIL=1 FAKE_CONSOLE='boot_ms=5000' expect "save not written" 3 $run
printed 'could not write the save'
if [ "$failures" -ne 0 ]; then
  echo "test-check-web-load: $failures case(s) failed" >&2
  exit 1
fi
echo "test-check-web-load: all cases pass"
