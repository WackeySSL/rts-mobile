#!/usr/bin/env bash
# Installs the official Godot Linux editor and ONLY the web (no-threads) export templates.
# Shared by .github/workflows/ci.yml and preview.yml. Idempotent: on an actions/cache hit it only
# re-verifies the templates and re-links the editor. The 1.28 GB template archive is never
# downloaded in full: the three members are read with HTTP Range requests
# (scripts/ci/remote_zip.py) and checked against pinned SHA-256s.
# Changing the Godot version is a stack change: new ADR, then update the pins below.
# Env (all optional): GODOT_VERSION (must be 4.7.2), GODOT_HOME, GODOT_BIN_DIR, TEMPLATES_DIR.
# Exit: 0 ok; 1 download, hash or version mismatch; 2 unsupported GODOT_VERSION.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
PINNED_VERSION="4.7.2"
# SHA-512 of Godot_v4.7.2-stable_linux.x86_64.zip: the line in the official godot-builds
# 4.7.2-stable SHA512-SUMS.txt. The live file is compared with it below as well.
EDITOR_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
# SHA-256 of the members as stored in Godot_v4.7.2-stable_export_templates.tpz.
TEMPLATE_SUMS="38885c88f75abbc797a1db7559719800279a00cfb9fa8b2e2868a7f6f84bad2e  version.txt
d3ee2f08cef0cf3cf6678a6355a92a8db48ccdd35cbd2e8bfd5f0e8a0b4032a0  web_nothreads_release.zip
08962aefef811b603541d7951ac67ef00413aad2d978855183c28adee98f626a  web_nothreads_debug.zip"

if [ "$GODOT_VERSION" != "$PINNED_VERSION" ]; then
  echo "install-godot.sh pins Godot $PINNED_VERSION; update the hashes for $GODOT_VERSION first." >&2
  exit 2
fi

BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable"
ZIP="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
BIN_NAME="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
GODOT_HOME="${GODOT_HOME:-$HOME/.local/opt/godot-${GODOT_VERSION}}"
GODOT_BIN_DIR="${GODOT_BIN_DIR:-$HOME/.local/bin}"
TEMPLATES_DIR="${TEMPLATES_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.stable}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sha512() { if command -v sha512sum >/dev/null; then sha512sum "$@"; else shasum -a 512 "$@"; fi; }
sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

tmp=""
trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT

# 1. Editor binary
if [ ! -x "$GODOT_HOME/$BIN_NAME" ]; then
  tmp="$(mktemp -d)"
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/$ZIP" "$BASE/$ZIP"
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/SHA512-SUMS.txt" "$BASE/SHA512-SUMS.txt"
  official="$(awk -v f="$ZIP" '$2 == f { print $1 }' "$tmp/SHA512-SUMS.txt")"
  actual="$(sha512 "$tmp/$ZIP" | awk '{ print $1 }')"
  if [ "$official" != "$EDITOR_SHA512" ] || [ "$actual" != "$EDITOR_SHA512" ]; then
    echo "SHA-512 mismatch for $ZIP" >&2
    echo "  pinned:   $EDITOR_SHA512" >&2
    echo "  official: $official" >&2
    echo "  actual:   $actual" >&2
    exit 1
  fi
  mkdir -p "$GODOT_HOME"
  unzip -q -o "$tmp/$ZIP" "$BIN_NAME" -d "$GODOT_HOME"
  chmod +x "$GODOT_HOME/$BIN_NAME"
  rm -rf "$tmp"
  tmp=""
fi
mkdir -p "$GODOT_BIN_DIR"
ln -sf "$GODOT_HOME/$BIN_NAME" "$GODOT_BIN_DIR/godot"
# Later steps of the same job find `godot` (and pipx tools in the same dir) on PATH.
if [ -n "${GITHUB_PATH:-}" ]; then echo "$GODOT_BIN_DIR" >> "$GITHUB_PATH"; fi

# 2. Web export templates (no-threads only), fetched by range from the .tpz
templates_ok() {
  [ -d "$TEMPLATES_DIR" ] || return 1
  (cd "$TEMPLATES_DIR" && echo "$TEMPLATE_SUMS" | sha256 -c --quiet - >/dev/null 2>&1)
}
if ! templates_ok; then
  mkdir -p "$TEMPLATES_DIR"
  python3 -I "$HERE/remote_zip.py" extract "$BASE/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
    "$TEMPLATES_DIR" templates/version.txt templates/web_nothreads_release.zip templates/web_nothreads_debug.zip
  (cd "$TEMPLATES_DIR" && echo "$TEMPLATE_SUMS" | sha256 -c -)
fi
if [ "$(cat "$TEMPLATES_DIR/version.txt")" != "${GODOT_VERSION}.stable" ]; then
  echo "unexpected template version.txt" >&2
  exit 1
fi

# 3. The editor only runs on Linux; elsewhere (local tests of this script) it is just unpacked.
if [ "$(uname -s)" = "Linux" ]; then
  reported="$("$GODOT_BIN_DIR/godot" --headless --version)"
  reported="$(printf '%s\n' "${reported%%$'\n'*}" | cut -d. -f1-4)"
  if [ "$reported" != "${GODOT_VERSION}.stable" ]; then
    echo "unexpected editor version: $reported" >&2
    exit 1
  fi
fi
echo "Godot $GODOT_VERSION ready: $GODOT_BIN_DIR/godot, templates in $TEMPLATES_DIR"
