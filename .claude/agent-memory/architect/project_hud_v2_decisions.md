---
name: project-hud-v2-decisions
description: ADR 0025 (HUD v2, corner HUD) and ADR 0026 (place-first construction), proposed 2026-11-01 on base 5203ce0, plan docs/plans/2026-11-01-hud-v2.md (rows P118-P131, P26ap)
metadata:
  type: project
---

- ADR 0025 PROPOSED 2026-11-01: battle shows pill (menu, credits, power) top left, 56 dp radar scope top right, 64 dp BUILD bottom right, command bar bottom left only with a selection, group column left edge, strike button above BUILD; one unfold at a time (drawer, full map, economy card, pause), map gesture closes it and still acts (ADR 0024 §5 kept); `HudCorners.place` pure layout fn with a mirror flag.
- Drawer: landscape side panel 40 % width [312, 420] dp, portrait half-height sheet; tabs "Structures/Infantry/Vehicles" (never "Base": RA2 tab); queue row tap = CANCEL; long-press unit card = +5 (Q2 A); no pin (Q1 A: a pinned right panel = C&C sidebar); BuildSidebar keeps its class name.
- Radar: scope = 32-pt textured polygon crop of P88's MinimapImage; full map = P88's Minimap node moved; never offline (radar-gated minimap is C&C's, ADR 0023 §13); `radar_close_ms` 4000 unless pinned (P85g pin glyphs).
- Orders shown only if the sim has them: Attack (one-shot ATTACK_MOVE mode; ground tap stays MOVE, Q4 A) and Stop; Guard/Patrol/Scatter/Repair/Sell/Primary not in game.
- "Waiting for credits" cannot happen (pay at queue, ADR 0018 Q2); BUILD's grey "!" re-meant as "stalled" (no head advanced between two snapshots).
- Pause = `MatchRunner.paused` (exists; no Command, hash-neutral); Vibration is the only toggle (haptics exist); HudPrefs `[hud] haptics` replaces P85f2's pin key.
- Start page = Phase 5 main menu (Q7 A), banner Phase 6; tagline proposed "Oil and gas against wind and sun. Choose your side."
- Fonts: `assets/art/fonts/<family>/` + OFL.txt + CREDITS row (STYLE.md Reskin and theme.tres already named that folder; the lead's brief said assets/fonts/ — flagged). Accent: Lumen cyan #1FA6C8, Derrick orange picked by hue >= 15° from danger #FF5A3C and money #F2C14E.
- ADR 0026 PROPOSED: ROW column `build_left` (hundredths of a tick left, 0 = complete, -1 = cancel mark), STATE_FORMAT 5, PLACE payload [type], whole price at the check mark, one site per player, hp from `construct_start_hp_percent` rising with work, completion = charge + free tanker + stat_built, unfinished = off for power/production/requirement/fire/strike/dock/outcome; CANCEL_BUILD = 16 refunds `construct_refund_percent` (Q1 B 75); exception 19 (MatchSnapshot COPIED build_left), next free 20; re-pin under exception 10; no kernel touched.
- Transition pattern: P128 adds the new PLACE beside the old, P129 AI and P130 UI migrate, P131 removes the old path, so every merged state plays (dropping structure QUEUE in one step would break the dummy between rows).
- Pitfall: a new hashed ROW column changes every golden hash even for unit-only arenas (P109 precedent); STATE_FORMAT pins live in test_world_v1/v2/v3, test_world_split, test_fog_visible_derivation, tests/perf/support/hash_bytes.gd and the sanitizer's dump_states.gd.
- Pitfall: a row killed in COMMANDS (hp 0) stays targetable through TARGETING and FIRE until REMOVE; removing it in COMMANDS would compact before FogUpdate.begin.
- Pitfall: an interim HUD row that moves one corner part (pill to top left) collides with parts that move later (portrait SelectionPanel line, strike button vs the strip); give each interim state an explicit place in the row text.
- Pitfall: the design's fixed "enemy" colour #FF9446 equals the Derrick League's natural accent; radar markers keep team colours instead.
