#!/usr/bin/env bash
# Loads a web export in headless Chromium and fails when the console shows a script error (P451b).
# export-web.sh only scans the export log; a script that exports fine but does not compile in the
# running build (a class_name used before the global class cache knows it, for instance) shows only
# in the browser console. This is the guard for that.
# Usage: bash scripts/ci/check-web-load.sh [--port N] [--seconds N] DIR
#   DIR        the web export (holds index.html), e.g. build/web
#   --port     localhost port of the throwaway static server (default 8811)
#   --seconds  how long the console is watched after the page loaded (default 15)
# Env:   NODE_PATH  where `playwright` resolves from (default: the global npm root)
# Method: a fresh browser profile, no seeded save. A script that does not compile is logged at the first
#         load, before any menu shows, so no save or tap is needed to reach it (tested on 56694ad1,
#         whose menu_routes_defaults.gd errors at the first load with an empty save too). The server sends no
#         COOP/COEP headers: the build is no-threads and has to run without them, as on GitHub Pages.
# Needs: python3, node, the playwright package and a Chromium it can launch.
# Exit:  0 no script error in the console
#        1 a SCRIPT ERROR / Parse Error / Compile Error / Failed to load script line, or an uncaught
#          page error (the lines are printed)
#        2 usage error, or DIR has no index.html
#        3 a tool is missing, the server did not start, or the browser could not load the page
# Always stops the server it started. Bash 3.2 compatible.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() { echo "usage: bash scripts/ci/check-web-load.sh [--port N] [--seconds N] DIR" >&2; }

port=8811
seconds=15
dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --port | --seconds)
      if [ $# -lt 2 ] || ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -eq 0 ]; then
        usage
        echo "check-web-load: $1 needs a positive number" >&2
        exit 2
      fi
      if [ "$1" = "--port" ]; then port="$2"; else seconds="$2"; fi
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
if [ "$up" != 1 ]; then
  echo "check-web-load: the static server did not start on port $port (port in use?)" >&2
  exit 3
fi

rc=0
node "$here/web-load-check.js" "http://127.0.0.1:$port/index.html" "$seconds" || rc=$?
exit "$rc"
