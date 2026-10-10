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

**Why:** each of these cost a spike or a false GREEN during Phase 0.
**How to apply:** check this list first when a test is flaky or a script reports success without evidence. Never relax the scan; add a narrow allowlist regex with a comment only for a message proven benign.
