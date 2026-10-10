# Third-party addons

## gdUnit4

| Field | Value |
| --- | --- |
| Name | gdUnit4 (unit test framework for Godot) |
| Version | 6.2.2 |
| Tag | `v6.2.2` |
| Tag commit | `0127a55f4543dfc24746f6e5c7ba6f94105d51f2` |
| Source | https://github.com/godot-gdunit-labs/gdUnit4 |
| Licence | MIT, Copyright (c) 2023 Mike Schulze (`addons/gdUnit4/LICENSE`) |
| Location | `addons/gdUnit4/` |
| Used for | `tests/` (run headless by `scripts/run-tests.sh`) |

The editor plugin is not enabled in `project.godot`. The command line runner does not need it.
The Web export preset excludes `addons/gdUnit4/*` and `tests/*`.

### How it was vendored

This is the upstream AssetLib export (`addons/gdUnit4` without `test/` and without the agent
files `AGENTS.md` and `CLAUDE.md`), 272 files. Do not `cp -R` a clone: that would bring in
`test/` and a `CLAUDE.md`.

```bash
git clone --depth 1 --branch v6.2.2 https://github.com/godot-gdunit-labs/gdUnit4.git <scratch>
git -C <scratch> rev-parse HEAD   # must print 0127a55f4543dfc24746f6e5c7ba6f94105d51f2
git -C <scratch> archive --format=tar HEAD addons/gdUnit4 | tar -x -C <repo>
```

Upstream ignores `*.gd.uid`, so it ships none. One `godot --headless --path . --import` generated
the 236 `*.gd.uid` and 8 `*.png.import` files that are committed next to the sources. They keep
`git status` clean after a fresh clone is imported.

### Notes

- Upstream states Godot 4.5 to 4.7.1. It is verified on 4.7.2 on macOS (Phase 0); Ubuntu is
  first exercised by CI. If a Godot bump breaks it, re-run the spike before changing the pin
  (ADR 0002).
- `addons/gdUnit4` does not pass `gdformat` or `gdlint`, so `scripts/verify.sh` checks only
  `game`, `tests` and `scenes`.
- Upgrade only through a new ADR.
