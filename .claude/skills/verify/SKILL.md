---
name: verify
description: Full verification of rts-mobile - format, lint, Godot import, gdUnit4 tests and a headless AI-vs-AI smoke run - ending in a VERIFY SUMMARY. Use before every commit, after any code change, and whenever someone asks whether something works, compiles, passes or is ready for review.
allowed-tools:
  - Bash(bash scripts/verify.sh)
  - Bash(bash scripts/verify.sh *)
---

# Verify

Run from the repository root:

```bash
bash scripts/verify.sh
```

Read the `===== VERIFY SUMMARY =====` block at the end of the output.

| Result | What to do |
| --- | --- |
| `RESULT: GREEN` | Done. Paste the summary block into your final message and the PR description. |
| `FAILED: <step>` | Read the printed log path, fix the cause, run again. |
| Exit code 3, `GODOT MISSING` | This session has no Godot. Commit, push the branch, run `gh run watch` on the PR's CI run and report that result instead. |

Rules:
- Never skip, disable or weaken a test or a check to get green. Fix the cause.
- Godot can exit 0 after runtime errors, so verify.sh also fails on `SCRIPT ERROR`, `ERROR:` and
  `Parse Error` lines. Only a message proven benign may be added to
  `scripts/verify-allowlist.txt`, as a narrow regex with a comment explaining why.
- Keep slow steps; correctness first. Mention it if a step takes more than 5 minutes.
