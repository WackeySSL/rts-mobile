---
name: project-dusk-overload-decisions
description: ADR 0047 (accepted 2026-11-23): Dusk Array overload 200 from data + vision cut + radar dark; plan rows P570-P578
metadata:
  type: project
---
# Dusk Array overload and vision cut (ADR 0047, PROPOSED 2026-11-23)

- Michael decided (2026-11-23) overload ~200 + vision cut. ADR 0047 on `claude/p57x-dusk-overload-plan` (base 56694ad1), plan `docs/plans/2026-11-23-dusk-overload.md`, rows P570 (acceptance docs), P571 (smoke counters, merges first for the "before" run), P572 overload, P573 FOG cut + kernel twin, P574 Radar.gd + snapshot, P575 dark scope, P575b sparks/cue, P576 AI tie-break, P577 Hard-vs-Hard custom run, P578 close-out. Questions: 1 radar dark vs ADR 0025 Q5 (legal), 2 lethal (rec. A), 3 strike cue (rec. yes), 4 AI mirror (rec. none).
- Overload = `renew_overload.tres` (200, vs_armour 0,0,0,100) as renew_strike's `strike_weapon`, in the blackout pass in COMMANDS (SELL precedent: hp 0 in COMMANDS, removed at REMOVE same tick); shared `Strike.hit_damage`; skip hp <= 0; neutral hit like the blackout; no new event.
- Vision cut = FogUpdate wanted cell -1 while `offline_until > tick+1` and rule `blackout_sight_cut` (RulesDef default 0, rules.tres 1); reuses fog_cell's -1 meaning so Removal/no-double-unstamp hold; stamp_fog skips `offline_until > tick`; FOG kernel reads offline_until + rule. No STATE_FORMAT bump.
- Radar dark = derived: owns complete radar offline and no complete radar online (`BuildingDef.radar` -> `type_radar`); no radar never dark (ADR 0023 §13 kept); in snapshot per capture. AI loses the same sight via fog; dark scope is a human-only attention cost.
- Pitfall: gate every new sim rule by data defaults that the frozen `data/dev/arena/` lacks (rule int 0, flag false, weapon -1) so arena state goldens never move; new TYPE/RULE entries still move every defs_hash pin.
- Pitfall: a GDScript-only fog unstamp that keeps fog_cell breaks Removal's dying-row unstamp (double -1) and stamp_fog; change the wanted cell inside FOG instead (twin edit).
- Pitfall: HOW_TO_PLAY says Normal builds strikes, but only Hard's strong build orders do (P192b); P576 fixes `superweapon-computer`. Parallel rows must edit different HOW_TO_PLAY rows.
- ACCEPTED 2026-11-23 (Michael "ja ja ja nej": 1 yes dark radar with own look, 2 A lethal, 3 yes one cue per strike out of view (no rim wedge while dark), 4 A no AI handicap). P570 done on `claude/p57x-dusk-overload-plan` on top of the lead's 0d34f78c: GDD §Superweapons applied, dated notes in ADR 0023 §10, 0025 §7 + Q5 + §8, 0010 §1, 0013 §5; P575b now includes the AttackCues cue and `combat-under-attack`.
