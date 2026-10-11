#!/bin/bash
# Setup script for the Claude Code cloud environment "rts-godot".
# Paste this file into claude.ai/code -> environment -> Setup script, and set the environment
# variable GODOT_MIRROR_REPO=<github-owner>/rts-mobile.
# Godot is downloaded from this repository's own release (created by the "Mirror Godot toolchain"
# workflow), because cloud sessions may only fetch release files from attached repositories.
# Must exit 0 and finish within about 5 minutes so the environment can be cached.
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
REPO="${GODOT_MIRROR_REPO:-}"
ZIP="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
BIN="Godot_v${GODOT_VERSION}-stable_linux.x86_64"
DEST="/opt/godot"

if ! mkdir -p "$DEST" 2>/dev/null; then
  DEST="$HOME/.local/opt/godot"
  mkdir -p "$DEST"
fi

if [ -z "$REPO" ]; then
  echo "GODOT_MIRROR_REPO is not set; skipping the Godot download."
elif [ ! -x "$DEST/$BIN" ]; then
  URL="https://github.com/${REPO}/releases/download/toolchain-godot-${GODOT_VERSION}/${ZIP}"
  if curl -fsSL --retry 3 -o "/tmp/${ZIP}" "$URL"; then
    # unzip is not guaranteed on the cloud image; Python's zipfile module is.
    if command -v unzip >/dev/null 2>&1; then
      unzip -o -q "/tmp/${ZIP}" -d "$DEST"
    else
      python3 -m zipfile -e "/tmp/${ZIP}" "$DEST"
    fi
    chmod +x "$DEST/$BIN" 2>/dev/null || echo "Could not extract ${ZIP} into ${DEST}."
    rm -f "/tmp/${ZIP}"
  else
    echo "Could not download ${URL}. Run the 'Mirror Godot toolchain' workflow first."
  fi
fi

if [ -x "$DEST/$BIN" ]; then
  if [ -w /usr/local/bin ]; then
    ln -sf "$DEST/$BIN" /usr/local/bin/godot
  else
    mkdir -p "$HOME/.local/bin"
    ln -sf "$DEST/$BIN" "$HOME/.local/bin/godot"
  fi
fi

if ! command -v gdlint >/dev/null 2>&1; then
  pip install --quiet "gdtoolkit==4.5.0" 2>/dev/null ||
    pip install --quiet --break-system-packages "gdtoolkit==4.5.0" 2>/dev/null ||
    uv tool install "gdtoolkit==4.5.0" 2>/dev/null ||
    echo "Could not install gdtoolkit."
fi
exit 0
