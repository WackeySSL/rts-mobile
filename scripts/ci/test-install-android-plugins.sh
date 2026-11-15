#!/usr/bin/env bash
# Offline test of scripts/ci/install-android-plugins.sh (P410). No network: the download is a file:// URL
# (ANDROID_PLUGINS_BASE_URL) to a small fixture zip built here. The pinned SHA-256 belongs to the real asset, so the
# positive cases run a copy of the script whose ZIP_SHA256 line holds the fixture's hash; the cases with the real
# script prove that the pin refuses anything else. Cases: a wrong archive is refused and extracts nothing (exit 1), a
# good one installs package.gd, the ads libraries and the iOS marker, the second run downloads nothing, --check
# exits 0 or 1, an archive without the libraries fails, a usage error is exit 2, and the pins name the tag, the
# commit, Godot 4.7.2 and a 64-digit SHA-256. ci.yml runs it in the verify job.
# Usage: bash scripts/ci/test-install-android-plugins.sh      Exit: 0 all cases pass, 1 a case failed.
set -euo pipefail
for tool in zip unzip curl sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "test-install-android-plugins: $tool is missing (needed by this test)" >&2
    exit 3
  }
done
repo="$(cd "$(dirname "$0")/../.." && pwd -P)"
root="$(mktemp -d)"
trap 'rm -rf "${root:?}"' EXIT
failures=0
real="$repo/scripts/ci/install-android-plugins.sh"

check() { # name, wanted exit code, wanted text in the output (may be empty); uses rc and out
  if [ "$rc" = "$2" ] && { [ -z "$3" ] || grep -Fq -- "$3" <<<"$out"; }; then
    echo "ok: $1"
  else
    echo "FAIL: $1 (wanted exit $2 and '$3', got exit $rc: $(tail -n 1 <<<"$out"))" >&2
    failures=$((failures + 1))
  fi
}
assert() { if "${@:2}"; then echo "ok: $1"; else echo "FAIL: $1" >&2; failures=$((failures + 1)); fi; }
run() { # script, args...; runs inside a scratch tree, sets rc and out
  local script="$1"
  shift
  set +e
  out="$(cd "$tree" && ANDROID_PLUGINS_BASE_URL="file://$root/serve" bash "$script" "$@" 2>&1)"
  rc=$?
  set -e
}

# A tree that holds a copy of the script at scripts/ci/ (the script works from the repository root two levels up).
new_tree() { # name, sha256 the copy pins
  tree="$root/$1"
  mkdir -p "$tree/scripts/ci"
  sed "s/^ZIP_SHA256=.*/ZIP_SHA256=\"$2\"/" "$real" >"$tree/scripts/ci/install-android-plugins.sh"
}

godot_version="$(sed -n 's/^GODOT_VERSION="\(.*\)"$/\1/p' "$real")"
# shellcheck disable=SC2016 # the ${GODOT_VERSION} to replace is literal text in the script
zip_name="$(sed -n 's/^ZIP="\(.*\)"$/\1/p' "$real" | sed "s/\${GODOT_VERSION}/$godot_version/")"
version="$(sed -n 's/^PLUGIN_VERSION="\(.*\)"$/\1/p' "$real")"
mkdir -p "$root/serve" "$root/fixture/ads/libs" "$root/fixture/pubmatic"
printf '# generated\nconst VERSION := "%s"\n' "$version" >"$root/fixture/package.gd"
printf 'extends EditorExportPlugin\n' >"$root/fixture/ads/poing_godot_admob_ads.gd"
for f in ads-debug ads-release core-debug core-release; do printf 'aar %s\n' "$f" >"$root/fixture/ads/libs/poing-godot-admob-$f.aar"; done
printf 'unused mediation adapter\n' >"$root/fixture/pubmatic/x.gd"
(cd "$root/fixture" && zip -q -r "$root/serve/$zip_name" package.gd ads pubmatic)
cp "$root/serve/$zip_name" "$root/served.zip"
good_sha="$(sha256sum <"$root/serve/$zip_name" | cut -d' ' -f1)"

# 1. The real script's pin refuses the fixture, and extracts nothing.
tree="$root/real"
mkdir -p "$tree"
mkdir -p "$tree/scripts/ci" && cp "$real" "$tree/scripts/ci/"
run scripts/ci/install-android-plugins.sh
check "the pin refuses an archive with another SHA-256" 1 "SHA-256 mismatch"
assert "a refused archive extracts nothing" test ! -e "$tree/addons/admob/android"

# 2. A copy that pins the fixture installs it: package.gd, ads/ only, the iOS marker.
new_tree good "$good_sha"
run scripts/ci/install-android-plugins.sh
check "the pinned archive installs" 0 "OK $version"
assert "package.gd is in place" test -s "$tree/addons/admob/android/bin/package.gd"
assert "the ads libraries are in place" test -s "$tree/addons/admob/android/bin/ads/libs/poing-godot-admob-ads-release.aar"
assert "the mediation adapters are not extracted" test ! -e "$tree/addons/admob/android/bin/pubmatic"
assert "the iOS marker is written" grep -q "const VERSION := \"$version\"" "$tree/addons/admob/ios/bin/package.gd"
assert "no iOS binaries are made" test -z "$(find "$tree/addons/admob/ios" -type f ! -name package.gd)"

# 3. The second run needs no download; --check agrees.
rm -rf "$root/serve"
run scripts/ci/install-android-plugins.sh
check "a second run installs nothing" 0 "already installed"
run scripts/ci/install-android-plugins.sh --check
check "--check passes when installed" 0 "already installed"

# 4. --check on an empty tree, a bad archive, usage.
new_tree empty "$good_sha"
run scripts/ci/install-android-plugins.sh --check
check "--check fails when not installed" 1 "not installed"
assert "--check installs nothing" test ! -e "$tree/addons"
mkdir -p "$root/serve"
(cd "$root/fixture" && zip -q "$root/serve/$zip_name" package.gd)
bad_sha="$(sha256sum <"$root/serve/$zip_name" | cut -d' ' -f1)"
new_tree incomplete "$bad_sha"
run scripts/ci/install-android-plugins.sh
check "an archive without the libraries fails" 1 "did not hold the expected files"
run scripts/ci/install-android-plugins.sh --nope
check "an unknown argument is exit 2" 2 "unknown argument"
run scripts/ci/install-android-plugins.sh --check extra
check "an extra argument is exit 2" 2 "too many arguments"

# 5. A download failure, a mismatch that leaves an existing install alone, and a stamp of another pin.
new_tree nodownload "$good_sha"
rm -rf "$root/serve"
run scripts/ci/install-android-plugins.sh
check "a download failure is exit 1" 1 "download of"
assert "a failed download installs nothing" test ! -e "$tree/addons/admob/android"
mkdir -p "$root/serve"
cp "$root/served.zip" "$root/serve/$zip_name"
new_tree untouched "$good_sha"
run scripts/ci/install-android-plugins.sh
check "the fixture installs for the untouched case" 0 "OK $version"
printf 'keep me\n' >"$tree/addons/admob/android/bin/ads/keep.txt"
printf 'not the pinned archive\n' >"$root/serve/$zip_name"
sed -i "s/^ZIP_SHA256=.*/ZIP_SHA256=\"$(printf '%064d' 1)\"/" "$tree/scripts/ci/install-android-plugins.sh"
run scripts/ci/install-android-plugins.sh
check "a SHA-256 mismatch on an installed tree is exit 1" 1 "SHA-256 mismatch"
assert "a mismatch leaves the existing install untouched" test -s "$tree/addons/admob/android/bin/ads/keep.txt"
assert "a mismatch leaves the stamp untouched" grep -q "^$good_sha\$" "$tree/addons/admob/android/bin/.pin"
cp "$root/served.zip" "$root/serve/$zip_name"
new_tree restamped "$good_sha"
run scripts/ci/install-android-plugins.sh
printf '%s\n' "$(printf '%064d' 2)" >"$tree/addons/admob/android/bin/.pin"
run scripts/ci/install-android-plugins.sh --check
check "a stamp of another pin is not installed" 1 "not installed"
run scripts/ci/install-android-plugins.sh
check "a stamp of another pin is reinstalled" 0 "OK $version"
assert "the reinstall rewrites the stamp" grep -q "^$good_sha\$" "$tree/addons/admob/android/bin/.pin"

# 6. The pins of the real script.
assert "the version is 5.1.0" grep -q '^PLUGIN_VERSION="5.1.0"$' "$real"
# shellcheck disable=SC2016 # the ${PLUGIN_VERSION} is literal text in the script
assert "the tag is v5.1.0" grep -q '^PLUGIN_TAG="v${PLUGIN_VERSION}"' "$real"
assert "the commit is pinned" grep -Eq '^PLUGIN_COMMIT="[0-9a-f]{40}"$' "$real"
assert "Godot 4.7.2 is pinned" test "$godot_version" = 4.7.2
assert "the SHA-256 is pinned" grep -Eq '^ZIP_SHA256="[0-9a-f]{64}"$' "$real"

[ "$failures" -eq 0 ] || {
  echo "test-install-android-plugins: $failures case(s) failed" >&2
  exit 1
}
echo "test-install-android-plugins: all cases pass"
