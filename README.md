# rts-mobile (working title)

An original real-time strategy game for phones: build a base, harvest ore and command tank
battles in 8-10 minute matches against the computer. Built with Godot 4.7 and developed with
Claude Code.

Status: pre-alpha. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Build and test
- Godot 4.7.2 with the Compatibility renderer.
- For the C++ sim kernels in `native/sim_kernels/`: SCons 4.9.1 (`pipx install scons==4.9.1`), g++,
  binutils and `clang-format` 20.1.8 (`pipx install clang-format==20.1.8`). godot-cpp is fetched at
  a pinned commit, not committed.
- `bash scripts/build-native.sh` builds the Linux library and writes the git-ignored
  `native/sim_kernels.gdextension`; without it the project is plain GDScript.
  `--platform android` (arm64) needs the Android NDK that `scripts/ci/install-ndk.sh` installs
  (the pinned `NDK_VERSION`, r29); it runs in CI, or in a cloud session after `scripts/cloud/install-android.sh`.
  `--compiler clang --optimize speed` builds it as the `native-clang` CI job does.
  `--sanitize undefined` builds it with g++ under UBSan (the `sanitizers` CI job, on pull requests that touch
  `native/`, `game/sim/`, `data/`, `tests/sim/native/`, `tests/sim/support/`, `scripts/build-native.sh`,
  `scripts/ci/run-sanitizer-harness.sh` or `.github/workflows/ci.yml`); `bash scripts/ci/run-sanitizer-harness.sh <folder>`
  runs the AddressSanitizer harness over `core/` (needs g++ with libasan and libubsan).
- `bash scripts/verify.sh` runs the native build, format, lint, import, tests, the C++ format check
  and a headless AI-vs-AI smoke run.
- `bash scripts/run-tests.sh` runs the gdUnit4 tests only.
- `bash scripts/run-sim-smoke.sh --matches N` runs headless AI-vs-AI matches with fixed seeds
  (a stub until the simulation exists).
- `bash scripts/export-web.sh` builds the web preview into `build/web`. It needs the Godot 4.7.2
  web export templates.
- `bash scripts/export-android.sh` builds the debug APK into `build/android` (CI on every run). A cloud
  session first runs `bash scripts/cloud/install-android.sh` (about 1.5 GB: JDK 17, the Android SDK and NDK,
  Godot's Android template, a debug keystore; it prints the environment and the export command, and a
  second run downloads nothing). Its first run needs `--accept-android-sdk-licenses`, which accepts the
  Android SDK licences on behalf of AppCode ApS: pass it only with the owner's consent. Without the flag it
  installs nothing through sdkmanager, and stops with exit 5 when cmdline-tools, platform-tools, build-tools
  or the NDK is missing.

## Licence
- Code: MIT, see [LICENSE](LICENSE).
- Assets: SVG drawn in this repository is MIT like the code; everything else is listed with its
  licence in [assets/CREDITS.md](assets/CREDITS.md).
- Engine: the game runs on the Godot Engine (MIT), which bundles third-party components under
  their own licences. Godot's `LICENSE.txt` and `COPYRIGHT.txt` for 4.7.2-stable are in
  [docs/licenses/godot-4.7.2/](docs/licenses/godot-4.7.2/), and every web build ships them as
  `THIRD_PARTY_LICENSES.txt` next to `index.html`.
- C++ bindings: the native sim kernels are built against godot-cpp (MIT), pinned at the commit of
  tag `godot-4.5-stable` and fetched at build time. Its licence text is in
  [docs/licenses/godot-cpp-4.5-stable/](docs/licenses/godot-cpp-4.5-stable/), and the
  `THIRD_PARTY_LICENSES.txt` of every Android and web build includes it.
- C++ runtime: the Godot export templates use LLVM libc++ (Apache-2.0 WITH LLVM-exception), which
  every Android build ships as `libc++_shared.so`. Its licence text (LLVM `llvmorg-21.1.0`) is in
  [docs/licenses/llvm-libc++/](docs/licenses/llvm-libc++/), and the `THIRD_PARTY_LICENSES.txt` of
  every Android and web build includes it.
- The game's name and logo are not covered by the MIT licence and remain the property of
  AppCode ApS.

## Contributing
Issues and pull requests are welcome. By contributing you agree that your contribution is
licensed under the MIT licence. The rules in [CLAUDE.md](CLAUDE.md) apply to humans too.
