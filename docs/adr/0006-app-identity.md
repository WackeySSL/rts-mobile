# ADR 0006: App identity (store title and application ids)

Status: accepted, 2026-10-10 (Michael)

## Context
Google Play locks the applicationId at the first upload of an app, including an upload to
internal testing. That upload happens in Phase 6, before the Phase 7 naming step in the
roadmap. The store title, on the other hand, can be changed at any time. ADR 0005 needs a
package id for the Phase 1 debug APK now.

## Decision
- Store title: **"Treadline: Offline RTS"** (22 of the 30 characters Play allows). "RTS" and
  "Offline" are search terms the title carries for free. The game is playable offline; ads
  simply do not show without a network.
- Release applicationId: **`dk.appcode.rts`**. It is neutral, so a later rename of the game
  never conflicts with the locked id.
- Dev builds (the Phase 1 debug APK, ADR 0005): **`dk.appcode.rts.dev`**, launcher label
  "Treadline dev", so the dev build and the Play build can be installed side by side.
- The codename `rts-mobile` stays for the repository, scripts and file names.

## Consequences
- Phase 6 uses `dk.appcode.rts` for the first Play upload; from then on it cannot change.
- The trademark search for "Treadline" stays in Phase 7, before the public launch. If it
  finds a conflict, only the title and the logo change, not the applicationId.
- `assets/`, menus and store texts may use the name "Treadline" from now on. Nothing in the
  name, logo or store texts may borrow from an existing game (CLAUDE.md, Legal).
