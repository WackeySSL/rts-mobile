#!/usr/bin/env bash
# C++ format check of native/sim_kernels (ADR 0013 sections 8 and 12), a step of scripts/verify.sh.
# The pinned clang-format version comes first, as build-native.sh checks SCons: a missing tool or
# another version is exit 3, never a skip. Then clang-format --dry-run --Werror runs over every
# C++ file below native/sim_kernels, with that folder's .clang-format.
# Why 20.1.8: the last patch of clang-format 20, the series godot-cpp's pre-commit hook pins at our
# godot-cpp commit; PyPI wheels exist for Linux x86_64 and arm64 and for macOS.
# Usage: bash scripts/ci/check-cpp-format.sh      Env: CLANG_FORMAT=<binary> (default: clang-format)
# Exit:  0 formatted, 1 a file needs formatting, 3 clang-format missing or not the pinned version
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

CLANG_FORMAT_VERSION="20.1.8"
CLANG_FORMAT="${CLANG_FORMAT:-clang-format}"

command -v "$CLANG_FORMAT" >/dev/null 2>&1 || { echo "clang-format is missing: pipx install clang-format==${CLANG_FORMAT_VERSION}" >&2; exit 3; }
have="$("$CLANG_FORMAT" --version 2>/dev/null | sed -n 's/^.*clang-format version \([0-9][0-9.]*\).*$/\1/p' | head -n 1 || true)"
[ "$have" = "$CLANG_FORMAT_VERSION" ] || { echo "needs clang-format ${CLANG_FORMAT_VERSION}, '$CLANG_FORMAT' reports '${have:-nothing}': pipx install clang-format==${CLANG_FORMAT_VERSION}" >&2; exit 3; }
files=()
while IFS= read -r file; do files+=("$file"); done < <(find native/sim_kernels -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.hpp' \) | LC_ALL=C sort)
[ ${#files[@]} -gt 0 ] || { echo "check-cpp-format: no C++ files below native/sim_kernels" >&2; exit 1; }
"$CLANG_FORMAT" --dry-run --Werror "${files[@]}"
echo "check-cpp-format: ${#files[@]} files formatted (clang-format ${have})"
