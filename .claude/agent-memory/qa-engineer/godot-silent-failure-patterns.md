---
name: godot-silent-failure-patterns
description: Recurring ways Godot 4.7.2 / gdUnit4 / shell scripts fail silently or flakily in rts-mobile, with the guard that catches each
metadata:
  type: project
---

One or two lines each. Found during Phase 0 (2026-10-10).

- Godot exits 0 on parse errors and when gdUnit4 finds no tests. `run-tests.sh` therefore checks `results.xml` for tests>0, and `verify.sh`/`export-web.sh` scan the log for `SCRIPT ERROR|^ERROR:|Parse Error`.
- `load()` of a broken script only prints a Parse Error; `test_scripts_compile` calls `can_instantiate()` on every `.gd` to turn that into a real failure.
- Headless window is 64x64: GUI hit-tests silently miss. Set `get_window().size = Vector2i(1280, 720)` first and restore it in `after()`.
- An expected `push_error` still prints `ERROR:` and fails the verify scan, even under `assert_error`. Do not test error paths without a narrow allowlist entry.
- `grep -q` at the end of a pipeline under `pipefail` can fail from SIGPIPE: read the output into a variable and use a here-string.
- `git branch -d` refuses after cherry-picks (new SHAs). Prove equivalence with `git patch-id --stable` per commit, then `-D`.
- `strings pack | grep dev_menu` matches file paths; the real check is `grep -A1 -x _custom_features | grep -qx dev_menu`.
- The interactive shell is zsh: unquoted `$var` is not word-split and `PIPESTATUS` is `pipestatus`. Run arg-matrix loops under `bash -c`.
- gdUnit4 and worktrees share `user://` (same project name): never run gdUnit4 in two worktrees at once.
- `grep -v -E -f allowlist || true` exits 2 on an invalid ERE and hides every error. verify.sh and export-web.sh now compile it first with `grep -E -f allowlist /dev/null` (exit > 1 = fail). Proof harness pattern: scratch git repo + fake `godot` on PATH.
- A test that skips a scene/file "while it does not exist" goes vacuous once the file moves. Require it by `DevRoutes.*` constants. Prove such fixes by moving the file and running old vs new tests.
- In-memory `GDScript.new()` fixtures must be valid code: a parse error prints `SCRIPT ERROR` (fails the verify scan) and `get_instance_base_type()` returns "".
- zsh traps in the Bash tool: `grep` is a ugrep function (use /usr/bin/grep for BSD behaviour), and an unmatched glob (`rm -f x_*.uid`) aborts the whole command.
- The allowlist must never fail open: verify.sh and export-web.sh reject invalid ERE syntax (grep exit 2) and entries that match an empty line (`a*`, `x?`, `.*`, GNU `foo|`). An over-broad but valid entry (e.g. `ERROR`) is still possible, so review every new entry.
- Integrating fix branches: commit a dirty memory file before `git cherry-pick`, prove equivalence with a per-commit `git patch-id --stable` match, then `git worktree remove` (no --force needed when only ignored `.godot/build/reports` remain) and `git branch -D`.
- Purity guard limit: name patterns cannot tell `Array.shuffle()`/`pick_random()` from a `DetRandom.shuffle()`, so those are not banned. `floor/ceil/round/lerp` on ints return ints, so they are not banned either (only `*f` variants).
- Purity guard (P27q): `length(` also trips on `String.length()`; use `len(s)` in game/sim (the report now says so). Multi-line scan fixtures live as `.txt` under `tests/project/fixtures/` so gdformat, gdlint and the compile test never see them; pin flagged line numbers and append new cases at the end.
- Text scanners that track brackets must count depth relative to the construct they track (a loop header inside a multi-line lambda call, or after a docstring with a stray `(`, was skipped silently with an absolute count). Pin every operator and keyword of a detection regex with its own one-line snippet, then delete one token at a time to prove each pin fails.
- Word-list scanners (P56, `test_native_purity`): build each regex from the same word list the test probes, one generated fixture per word. Hand-written alternations left 134 of 213 alternative-deletion mutants alive; a scratch SceneTree script that deletes one alternative at a time finds them. A legal look-alike per rule also catches over-broad words (`exp\w*` matched `std::experimental`).
- A scratch `-s` SceneTree script that errors in `_init()` never reaches `quit()` and hangs headless Godot (a renamed constant did it): run it under `timeout`. GDScript `String` has no `partition()`; use `find()` and `substr()`.

**Why:** each of these cost a spike or a false GREEN during Phase 0.
**How to apply:** check this list first when a test is flaky or a script reports success without evidence. Never relax the scan; add a narrow allowlist regex with a comment only for a message proven benign.
