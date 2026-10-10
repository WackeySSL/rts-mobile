# Bootstrap prompt (Phase 0)

Run Claude Code locally in the unpacked kit folder and paste everything below the line.

---

You are setting up rts-mobile. Before doing anything, read CLAUDE.md, docs/GDD.md,
docs/ROADMAP.md (Phase 0) and docs/adr/0001-engine-and-architecture.md.

Work through these steps in order. If a step fails, stop and tell me exactly what failed.

1. Check the tools: `godot --version` (expect 4.7.x), `gdformat --version`, `gdlint --version`,
   `gh auth status` and `jq --version`. Report anything missing and stop.
2. Run `git init` if needed, commit the kit unchanged as "chore: starter kit", create a PUBLIC
   GitHub repository named rts-mobile under my account with `gh repo create`, make `main` the
   default branch and push.
3. Build every Phase 0 item from docs/ROADMAP.md on a branch `phase-0` as a few small commits.
   Use the subagents: release-engineer for the workflows, art-director for the style guide,
   sample unit and gallery, qa-engineer for gdUnit4 and the scripts. Pin gdUnit4 to an exact
   release and every third-party GitHub Action to a commit SHA.
4. Run `bash scripts/verify.sh` until it prints `RESULT: GREEN`.
5. Open a PR, follow CI and the preview workflow with `gh run watch`, and fix until both are
   green and the preview link loads. If GitHub Pages is not enabled yet, try to enable it from
   the gh-pages branch with `gh api`; if that fails, tell me the exact setting to change.
6. Squash-merge only after I write "merge".
7. Finish with a short checklist, in Danish, of what I must do by hand: run
   /install-github-app, run the "Mirror Godot toolchain" workflow with 4.7.2, create the cloud
   environment rts-godot with GODOT_MIRROR_REPO and scripts/cloud/setup.sh, create the Project
   with docs/PROJECT_INSTRUCTIONS.md, and protect main (require CI, block force pushes).
