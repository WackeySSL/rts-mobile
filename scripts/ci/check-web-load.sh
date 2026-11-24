#!/usr/bin/env bash
# Loads a web export in headless Chromium and fails when the console shows a script error (P451b).
# export-web.sh only scans the export log; a script that exports fine but does not compile in the
# running build (a class_name used before the global class cache knows it, for instance) shows only
# in the browser console. This is the guard for that.
# Usage: bash scripts/ci/check-web-load.sh [--port N] [--seconds N] [--boot-timeout N] DIR
#   DIR             the web export (holds index.html), e.g. build/web
#   --port          localhost port of the throwaway static server, 1-65535 (default 8811)
#   --seconds       how long the console is watched after the boot marker (default 5)
#   --boot-timeout  how long to wait for the boot marker, the console line boot_ms=<n> that the intro prints
#                   once the menu is up (default 90). The page's load event comes long before the engine
#                   has fetched its wasm and pack, so the watch window starts at the marker.
# Env:   NODE_PATH  where `playwright` resolves from (default: the global npm root)
# Method: two phases in one headless Chromium (Pixel 7), details in web-load-check.js. Phase 1 boots with a
#         fresh profile (a script that does not compile is logged here whatever the save). Phase 2 writes a
#         minimal valid save (rank XP 500) into the IndexedDB that Godot mounts as user://, boots again, so the
#         main menu (not the first-launch lesson) is what MenuRoot builds, and taps SKIRMISH: the screen must
#         change. The consent form of the web preview is tapped away (Accept) at every start. The server sends
#         no COOP/COEP headers: the build is no-threads and has to run without them, as on GitHub Pages.
# Needs: python3, node, the playwright package and a Chromium it can launch.
# Exit:  0 both phases booted, the console shows no script error and the menu answered
#        1 a SCRIPT ERROR / Parse Error / Compile Error / Failed to load script / boot_error line, or an
#          uncaught page error (the lines are printed; at once, also before the boot marker)
#        2 usage error (also a port above 65535), or DIR has no index.html
#        4 the main menu is not what showed: the screen kept changing before the tap on SKIRMISH, or did not
#          change after it
#        3 no boot marker within the boot timeout (the engine did not start; the last console lines and the
#          page text are printed), the seeded save is not in IndexedDB after the boot, a tool is missing, the
#          server did not start, or the browser could not
#          load the page
# Always stops the server it started. Bash 3.2 compatible.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() { echo "usage: bash scripts/ci/check-web-load.sh [--port N] [--seconds N] [--boot-timeout N] DIR" >&2; }

port=8811
seconds=5
boot_timeout=90
dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --port | --seconds | --boot-timeout)
      if [ $# -lt 2 ] || ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -eq 0 ]; then
        usage
        echo "check-web-load: $1 needs a positive number" >&2
        exit 2
      fi
      case "$1" in
        --port) port="$2" ;;
        --seconds) seconds="$2" ;;
        *) boot_timeout="$2" ;;
      esac
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      usage
      echo "check-web-load: unknown argument '$1'" >&2
      exit 2
      ;;
    *)
      if [ -n "$dir" ]; then
        usage
        echo "check-web-load: more than one directory" >&2
        exit 2
      fi
      dir="$1"
      shift
      ;;
  esac
done
if [ -z "$dir" ]; then
  usage
  exit 2
fi
if [ "$port" -gt 65535 ]; then
  usage
  echo "check-web-load: --port must be 65535 or below" >&2
  exit 2
fi
if [ ! -s "$dir/index.html" ]; then
  echo "check-web-load: $dir/index.html is missing or empty (run scripts/export-web.sh first)" >&2
  exit 2
fi
for tool in python3 node; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "check-web-load: $tool is missing" >&2
    exit 3
  }
done
if [ -z "${NODE_PATH:-}" ]; then
  NODE_PATH="$(npm root -g 2>/dev/null || true)"
  export NODE_PATH
fi

server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

python3 -I -m http.server "$port" --bind 127.0.0.1 --directory "$dir" >/dev/null 2>&1 &
server_pid=$!
up=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  if python3 -I -c "import socket,sys; socket.create_connection(('127.0.0.1', int(sys.argv[1])), 1).close()" "$port" 2>/dev/null; then
    up=1
    break
  fi
  sleep 0.25
done
# The probe may have reached another process that already held the port (ours would have died on bind).
if [ "$up" = 1 ]; then
  sleep 0.3 # a server that lost the bind race needs a moment to exit
  kill -0 "$server_pid" 2>/dev/null || up=0
fi
if [ "$up" != 1 ]; then
  echo "check-web-load: the static server did not start on port $port (port in use?)" >&2
  exit 3
fi

rc=0
node "$here/web-load-check.js" "http://127.0.0.1:$port" "$seconds" "$boot_timeout" || rc=$?
exit "$rc"
