---
name: project-rank-trophies-decisions
description: P673 plan (2026-11-27, rows P673a-P673j) and ADR 0054 PROPOSED: 16 data trophies, career save section, check at award time + Rank-screen refresh, result-screen line, no XP reward, no Rank banner recommended
metadata:
  type: project
---
- P673 (2026-11-27, branch claude/p673-rank-trophies-plan on 5657700e): plan docs/plans/2026-11-27-rank-trophies.md + ADR 0054 proposed; 4 questions (list, no reward, "03 RANK · TITLE" hint, no Rank banner), all recommended. Builds on P664's RankScreen `_add_section()` seam (in flight) and P670 (result look, in flight).
- Decision: TrophyDef kinds LESSONS / COUNT / WIN_GRID (state, back-fillable, re-checked by `Progression.refresh_trophies()` on Rank entry) and MATCH (per-match filters: levels, max_ticks, hq_standing, max_buildings_lost; only in award_match). Data in data/meta/trophies.tres (already !data/meta/** in balance.yml).
- Decision: new save section `career` (format 1; finished, wins, play_ticks, best_win_ticks, wins_grid, wins_faction, earned) with NO SaveService version bump; unknown keys carried through on write; written before `progress` in the same frame (one flush). Back-fill: finished = progress.next_award_id - 1, lessons from tutorial.done; wins/time not back-fillable.
- Decision: "HQ never destroyed" = a hq_type_ids row stands at the end (HQ tab -1, not sellable, no capture; data test pins it); MatchSummary gains faction (scenario().factions[seat]), stat_* of the side, standing_types. No sim change.
- Pitfall: never add keys to section `progress`: an older build's Progression._read rebuilds it from 4 keys and writes it whole, wiping them (web previews of older branches share the save). Use a new section; ADR 0042 §1 keeps unknown sections.
- Pitfall: a save key SaveService refuses (empty, `=[];"`) refuses the WHOLE set_section; never use a runtime id (map/level/faction) as a key unchecked, or a career write could cost the XP award.
- Finding (risk 1, for the lead): lessons end by beats -> TutorialHost._leave -> MenuFlow.return_to_menu (no award); no lesson has a MATCH_WON beat, so ADR 0045 lesson_xp looks unpaid; progress.lessons is not "lessons done", tutorial.done is.
- Pitfall: "units and buildings unlocked" does not exist (ADR 0045 locks maps and levels only); push back instead of inventing a count.
