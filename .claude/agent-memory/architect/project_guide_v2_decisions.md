---
name: project-guide-v2-decisions
description: ADR 0048 (accepted 2026-11-24, "Ja til alle"): tutorial guide v2, docked card + n/N tab, blink, lead-in chains, gesture hints; plan rows P582-P596
metadata:
  type: project
---
# Tutorial guide v2 (ADR 0048, ACCEPTED 2026-11-24)

- Michael's phone test of Basics (upright) asked 6 things: fixed card at the top that folds and reopens each step, a step counter in a corner, blinking frame, highlight that follows multi-tap steps, all lessons, animated gesture hints. ADR 0048 + plan `docs/plans/2026-11-24-guide-v2.md` on `claude/p58x-guide-v2-plan` (base 53fabb24, commit eae8e33e), rows P582-P596; P580/P581 were taken elsewhere.
- Dock = pure `GuideDock.place` from `HudCorners.place` rects: top = 64 dp landscape / 120 dp upright (toast slot reserved), left = group column end + 8, landscape right = reserved full-map rect - 8 (card never moves when the map opens), upright map open -> dock drops under the map. Cap 45 % of safe height, wide (>= 440 dp, tab + Next in a right column) and narrow (head row) forms.
- P543g's free-place search retired with no fallback; overlaps left (tile, world-follow controls like PlaceConfirm, modal buttons) -> card stays, see-through, body passes touches, ring + hand drawn above (Q3 A rec).
- Counter n/N, step = beat (lead-ins don't count), tab = one 48 dp button at the scope-side corner, folded state per beat only, reopens on stall. Skip only on first card + pause menu "Leave tutorial" (Q4 rec).
- Chains: `TutorialBeatDef.lead_in: Array[TutorialLeadInDef]` (UI-state kinds only, new Kind 18 STRIKE_AIMING); active = furthest reached step wins (scan from the end, never latched) so placement closing the drawer keeps the ring on PlaceConfirm. Four tab-only beats merge (Basics 26, Strikes 10, Air 11, Support 12). Keep enemy trigger_beat ids groups/home/sell-last.
- Blink: opacity 25-100 % at 800 ms (1.25 Hz < WCAG 3 Hz), data in `data/tutorial/guide_settings.tres`, colours in theme `GuideTokens`; reduced = steady, no Tween. Hint: `GestureHint.pose()` pure, long-press timing from input_settings + extra, hides on any touch + 2 s, reduced = static key pose (Q5 rec; the brief said "dropped", ADR 0027 §8 keeps informative visuals).
- Critical path is lane T1 (five rows on CoachMark.gd in series: P585, P588, P589, P591, P592).
- Pitfall: the brief said the strike button is top right; it is 8 dp above BUILD (ADR 0025 §10). Only the scope is top right. Check HudCorners before trusting a brief's layout.
- Pitfall: a director accessor that returns a Dictionary per frame allocates; return a Resource wrapped once per beat.
- ACCEPTED 2026-11-24 (Michael "Ja til alle": 1 top, 2 "3/26", 3 A see-through, 4 Skip on first card only + pause-menu Leave tutorial (already on main, PauseMenu `_exit_button`), 5 still hand with arrows). P583 done on the same branch (PR #634): ADR 0048 status + answers, dated note in ADR 0044 §2, plan P583 done, P589 notes the Skip tests that move to beat 1 or Leave tutorial.
- Pitfall: awk length() counts bytes, so lines with arrows (→) or § read as too long; measure characters with Python before rewrapping.
