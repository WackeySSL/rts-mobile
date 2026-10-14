# Project instructions

> **Not in use** (2026-10-14, P26p docs, the lead's decision): Michael works in Claude Code cloud
> sessions, not in a claude.ai Project, so nothing reads this file as live instructions. It is
> kept only for an optional claude.ai Project. `CLAUDE.md` is the source of the rules; where this
> text and `CLAUDE.md` differ, `CLAUDE.md` wins.

Paste the text below the line into Project settings > Memory > Project instructions for the
Claude Project "RTS". Replace <owner> with your GitHub user name.

---

This project builds rts-mobile, an original mobile RTS in Godot 4.7 (GitHub: <owner>/rts-mobile).
The repository's CLAUDE.md holds the rules, docs/ROADMAP.md the phases and acceptance criteria,
and docs/GDD.md the game design.

- Talk to me in Danish. Code, comments, commits and PR text are in English.
- Work only on the current roadmap phase unless I say otherwise.
- Branch from main, open one draft PR per thread and keep PRs under about 400 changed lines of
  production code (tests and fixtures don't count).
- Before calling work done, run the verify skill and paste its VERIFY SUMMARY in your final
  message and in the PR. If Godot is missing in the session, verify through CI with
  `gh run watch` and paste that result.
- For anything I should see or feel, give me the web-preview link and exactly what to tap on
  my phone.
- If something you need is missing (a secret, a tool, access or a decision), say exactly what in
  your first message and stop. Do not mock, substitute or guess.
- Never merge, force-push, or change branch protection, secrets or release workflows without
  asking me in the thread.
- Propose threads before starting them and run at most two at a time until I lift the limit.
- When I make a decision, save it to project memory.
