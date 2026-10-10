# rts-mobile (working title)

An original real-time strategy game for phones: build a base, harvest ore and command tank
battles in 8-10 minute matches against the computer. Built with Godot 4.7 and developed with
Claude Code.

Status: pre-alpha. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Build and test
- Godot 4.7.2 with the Compatibility renderer.
- `bash scripts/verify.sh` runs format, lint, import, tests and a headless AI-vs-AI smoke run.
- Web build: `bash scripts/export-web.sh` (available after Phase 0).

## Licence
- Code: MIT, see [LICENSE](LICENSE).
- Assets: SVG drawn in this repository is MIT like the code; everything else is listed with its
  licence in [assets/CREDITS.md](assets/CREDITS.md).
- The game's name and logo are not covered by the MIT licence and remain the property of
  AppCode ApS.

## Contributing
Issues and pull requests are welcome. By contributing you agree that your contribution is
licensed under the MIT licence. The rules in [CLAUDE.md](CLAUDE.md) apply to humans too.
