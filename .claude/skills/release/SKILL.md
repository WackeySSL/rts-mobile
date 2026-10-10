---
name: release
description: Cut a release of rts-mobile - set the version, update CHANGELOG.md, open the release PR, then start release.yml, which tags main and ships to the stores. Only run when Michael types /release.
disable-model-invocation: true
argument-hint: "[version, e.g. 0.3.0]"
---

# Release $ARGUMENTS

1. Check that `main` is green: `gh run list --branch main --limit 3`. If not, stop and report.
2. On a new branch, set `application/config/version` in `project.godot` to `$ARGUMENTS`.
   Do not edit the Android versionCode; CI derives it from the run number.
3. Add a `## [$ARGUMENTS]` section to `CHANGELOG.md` (Keep a Changelog format), written for
   players, from the PR titles merged since the previous release.
4. Commit `release: v$ARGUMENTS`, open a PR, wait for green CI and ask Michael to merge it.
5. After the merge, start the release: `gh workflow run release.yml -f version=$ARGUMENTS`.
   Cloud sessions cannot push tags, so the workflow tags `main` itself.
6. Follow the runs with `gh run watch` and report the links and the result.

Never upload builds manually and never touch secrets.
