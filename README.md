# rts-mobile (working title)

An original real-time strategy game for phones: build a base, harvest ore and command tank
battles in 8-10 minute matches against the computer. Built with Godot 4.7 and developed with
Claude Code.

Status: pre-alpha. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Build and test
- Godot 4.7.2 with the Compatibility renderer.
- `bash scripts/verify.sh` runs format, lint, import, tests and a headless AI-vs-AI smoke run.
- `bash scripts/run-tests.sh` runs the gdUnit4 tests only.
- `bash scripts/run-sim-smoke.sh --matches N` runs headless AI-vs-AI matches with fixed seeds
  (a stub until the simulation exists).
- `bash scripts/export-web.sh` builds the web preview into `build/web`. It needs the Godot 4.7.2
  web export templates.

## Licence
- Code: MIT, see [LICENSE](LICENSE).
- Assets: SVG drawn in this repository is MIT like the code; everything else is listed with its
  licence in [assets/CREDITS.md](assets/CREDITS.md).
- Engine: the game runs on the Godot Engine (MIT), which bundles third-party components under
  their own licences. Godot's `LICENSE.txt` and `COPYRIGHT.txt` for 4.7.2-stable are in
  [docs/licenses/godot-4.7.2/](docs/licenses/godot-4.7.2/), and every web build ships them as
  `THIRD_PARTY_LICENSES.txt` next to `index.html`.
- C++ runtime: the Godot export templates use LLVM libc++ (Apache-2.0 WITH LLVM-exception), which
  every Android build ships as `libc++_shared.so`. Its licence text (LLVM `llvmorg-21.1.0`) is in
  [docs/licenses/llvm-libc++/](docs/licenses/llvm-libc++/), and the `THIRD_PARTY_LICENSES.txt` of
  every Android and web build includes it.
- The game's name and logo are not covered by the MIT licence and remain the property of
  AppCode ApS.

## Contributing
Issues and pull requests are welcome. By contributing you agree that your contribution is
licensed under the MIT licence. The rules in [CLAUDE.md](CLAUDE.md) apply to humans too.
