#!/usr/bin/env bash
# Proves a regeneration of the SVG frames changed colour values only (ADR 0050 section 3, P632):
# every changed or untracked-new .svg under assets/art/iso is compared with its text at REV (default
# HEAD) after each #RRGGBB is replaced by #X. Exit 0 all changes are hex only, 1 a file differs
# in more than colour (named), 2 a wrong argument.
# Usage: bash scripts/art-hex-only.sh [REV]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
rev="${1:-HEAD}"
norm() { sed -E 's/#[0-9A-Fa-f]{6}/#X/g'; }
changed=0
bad=0
while IFS= read -r file; do
  changed=$((changed + 1))
  if ! git cat-file -e "$rev:$file" 2>/dev/null; then
    echo "art-hex-only: new file $file"
    bad=$((bad + 1))
    continue
  fi
  if ! cmp -s <(git show "$rev:$file" | norm) <(norm <"$file"); then
    echo "art-hex-only: more than colour changed in $file"
    bad=$((bad + 1))
  fi
done < <(git diff --name-only "$rev" -- 'assets/art/iso/*.svg')
echo "art-hex-only: $changed changed svg files, $bad not hex only"
[ "$bad" -eq 0 ]
