#!/usr/bin/env bash
# Prints the font section of THIRD_PARTY_LICENSES.txt (plan row P118b, ADR 0025 section 13; the SIL Open Font
# License asks for the copyright notice and the licence text with every copy of the font software). For every
# folder under assets/art/fonts/ that holds a font file (.ttf, .otf, .woff or .woff2) it prints a titled block that
# names the family (the folder name, in words) and the font files of that folder, then the folder's OFL.txt
# unchanged. There is no list of families: a new font folder is picked up by this rule, and a font folder
# without a non-empty OFL.txt stops the export. export-web.sh and export-android.sh append this output to their
# notices, so the two stay identical, as they do for the libc++ and godot-cpp sections.
# Usage: bash scripts/ci/font-notice.sh [--list]
#   --list  print only the project path of each family's OFL.txt (assets/art/fonts/<family>/OFL.txt), one per
#           line, after the same checks: the export scripts look for exactly these files in the pack or APK.
# Exit:  0 ok
#        1 a font folder has no OFL.txt or an empty one, or the project holds no font file at all
#        2 usage error
# Bash 3.2 compatible (export-web.sh runs on macOS runners too).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

FONT_DIR="assets/art/fonts"
OFL_NAME="OFL.txt"

die() {
  local code="$1"
  shift
  echo "font-notice: $*" >&2
  exit "$code"
}

list_only=0
case "${1:-}" in
  "") ;;
  --list) list_only=1 ;;
  *) die 2 "usage: bash scripts/ci/font-notice.sh [--list]" ;;
esac
[ $# -le 1 ] || die 2 "usage: bash scripts/ci/font-notice.sh [--list]"

# The font files of a folder (one level, no .import files), sorted by name, or of the whole tree.
font_files() { # DIR [MAXDEPTH]
  find "$1" ${2:+-maxdepth "$2"} -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff' -o -iname '*.woff2' \)
}

families="$(font_files "$FONT_DIR" 2>/dev/null | sed 's,/[^/]*$,,' | LC_ALL=C sort -u || true)"
[ -n "$families" ] || die 1 "no font file under $FONT_DIR (the theme loads its fonts from there)"

# Every font folder needs its licence text: a missing or empty file stops the export before a notice is written.
while IFS= read -r dir; do
  [ -s "$dir/$OFL_NAME" ] || die 1 "licence notice source $dir/$OFL_NAME is missing or empty (a font folder ships its $OFL_NAME with every build, OFL section 2)"
done <<<"$families"

if [ "$list_only" = 1 ]; then
  while IFS= read -r dir; do
    printf '%s/%s\n' "$dir" "$OFL_NAME"
  done <<<"$families"
  exit 0
fi

rule="--------------------------------------------------------------------------------"
while IFS= read -r dir; do
  ofl="$dir/$OFL_NAME"
  family="$(basename "$dir" | tr '_-' '  ' | awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2)} 1')"
  files=""
  while IFS= read -r font; do
    files="${files:+$files, }$(basename "$font")"
  done <<<"$(font_files "$dir" 1 | LC_ALL=C sort)"
  # Title, rule, the files line, the note, a blank line, then the text: the offline test finds the text five lines
  # below the title.
  printf '\n%s\nFont family %s: %s\n%s\n' "$rule" "$family" "$ofl" "$rule"
  printf 'Font files of this family in the build: %s\n' "$files"
  printf '%s\n\n' "The family's $OFL_NAME (SIL Open Font License) follows unchanged."
  cat "$ofl"
  # A text without a final newline must not run into the next block.
  [ -z "$(tail -c 1 "$ofl")" ] || printf '\n'
done <<<"$families"
