# Plan: the Dusk Array's overload and vision cut

Date: 2026-11-23. Base: `main` at 56694ad1. Author: architect (branch
`claude/p57x-dusk-overload-plan`). Decision: `docs/adr/0047-dusk-array-overload-and-vision-cut.md`
(**proposed**; Michael decided the two changes on 2026-11-23, and questions 1-4 are open).
ROADMAP: Phase 4b balance ("The balance run (seeds 1-100) passes the ADR 0031 gate thresholds with
the new units"). This changes balance before launch and adds no checkbox. No code row starts before
P570 (acceptance) merges.

## Goal
The Dusk Array should match the Deep Bore better and stay different:
1. **Overload:** a one-time 200 hit from data on every enemy building in the ring, at the
   blackout's moment.
2. **Vision cut:** blacked-out buildings give no sight for the blackout's length, and the victim's
   radar scope goes dark when their only working radar is caught.

The same sight is lost for an AI victim and a human victim (GDD pillar 4). The cost is measured in
one Hard-vs-Hard balance run before and one after.

Scope guard. Not in this plan: a strike warning for the Dusk Array, unit effects, new art beyond
reusing the offline glyph, an AI that aims for overload kills, or any change to the Deep Bore,
ranges, lengths or prices. These go to the lead's follow-up list if P577 asks for them.

## Affected modules
| Area | Files (main ones) | Rows |
|---|---|---|
| Data | `data/weapons/renew_overload.tres` (new), `data/units/renew_strike.tres`, `data/rules.tres`, `data/units/fossil_radar.tres`, `data/units/renew_radar.tres`; `data/dev/arena/**` stays frozen | P572-P574 |
| Defs | `game/sim/defs/RulesDef.gd` (+`blackout_sight_cut`), `game/sim/defs/BuildingDef.gd` (+`radar`) | P573, P574 |
| Sim | `Strike.gd` (overload, `hit_damage`), `FogUpdate.gd`, `WorldLoad.gd` (`stamp_fog`, `type_radar` copy), `WorldShape.gd` (RULE_SCALARS, TYPE_ARRAYS), `Radar.gd` (new) | P572-P574 |
| Native | `native/sim_kernels/src/core/fog.cpp`, `fog.h`, `src/bind/kernel_fog.cpp`, `world_access.h`; sanitizer case | P573 |
| Core | `game/core/MatchSnapshot.gd` (`radar_dark`, `radar_dark_until`, `type_radar`) | P574 |
| View/UI | `game/ui/RadarScope.gd`, `RadarMap.gd`, `Minimap.gd`, `game/view/HitFx.gd`/`AirFx.gd`, `game/ui/AttackCues.gd` (question 3) | P575, P575b |
| AI | `game/ai/AiStrikes.gd` | P576 |
| Harness | `tests/smoke/smoke_count.gd`, `smoke_run.gd`, `balance_summary.gd` | P571 |
| Docs | ADR 0047, status notes in ADRs 0010, 0013, 0023, 0025; `docs/GDD.md`; `docs/HOW_TO_PLAY.md`; `data/help/how_to_play.tres`; `docs/balance/` | P570, each feature row, P577, P578 |

## Command and data changes
- **Commands:** none. SUPERWEAPON 15 is unchanged. `STATE_FORMAT` stays 7.
- **Data:**
  - `renew_overload.tres`: `damage` 200, `vs_armour` (0, 0, 0, 100), `targets` 1.
  - `renew_strike.tres`: `strike_weapon` = the new weapon.
  - `rules.tres`: `blackout_sight_cut = 1`, with `RulesDef` default 0.
  - `fossil_radar.tres`, `renew_radar.tres`: `radar = true`, with `BuildingDef` default false.
  - The frozen arena gets none of these.
- **Hashed values that move:** `hp` and `fog_cell`, only when a shipped Dusk Array fires.
  `defs_hash` moves in P572, P573 and P574.

## GDD diff (§Superweapons, applied by P570)
Replace the Dusk Array bullet with:

> - **Dusk Array** (Lumen Accord): at once and with no warning, every enemy building within 4
>   tiles takes an overload hit (200 damage, enough to finish off a badly damaged building) and
>   goes dark for 30 seconds: no power, defences silent, production paused, and no sight, so the
>   fog closes in wherever only those buildings saw. If it catches the victim's radar building and
>   they have no other working one, their radar goes dark for that time too. Units are not
>   affected: they keep moving, shooting and seeing with their own eyes.

The next line stays exactly: "No freeze weapons. The Phase 3 dummy opponent never builds or fires
one; Phase 4's AI does." The Deep Bore bullet is unchanged. If question 1 is answered B, P570 drops
the radar sentence. If question 2 is B, "enough to finish off a badly damaged building" becomes "it
never destroys a building on its own".

## Test plan (what is proven headless)
- **Sim (gdUnit4, both implementations where a kernel phase is involved):**
  - overload: values, armour, upgrades, a kill at the last hp and its same-tick loss and defeat,
    own buildings, units, neutral rows, the radius edge, sold-this-tick, two strikes in one tick,
    no weapon means no damage;
  - vision cut: on and off on the owner's fog turn, exact ticks, death while cut, `stamp_fog`, rule
    0 bit-identical, unit sight untouched;
  - radar rule: dark and light in every case of ADR 0047 §3;
  - replay hash equal; the frozen arena's goldens unchanged.
- **Native:** FOG lockstep crafted cases with blackouts (cut, return, death while cut, cut plus
  sweep), the random lockstep with a blackout injected, and the sanitizer harness case.
- **Fairness:** the victim's `PlayerView` visibility equals its fog block with and without the cut,
  and an AI victim's `AiIntel` lists drop an enemy seen only by a cut building (P573, P576).
- **UI (headless, the six sizes of ADR 0015 §6):** the dark scope face, the tap nudge, the full map
  folding, the return, no forbidden words in any label, and the overload sparks only on shown
  buildings.
- **Measurement:** the counters' unit tests on crafted worlds (P571). The run itself only on GitHub
  Actions (P577).

## Rows
Each row is one small PR (under about 400 production lines; tests do not count) with its tests and,
when player-facing, its `docs/HOW_TO_PLAY.md` rows. Code PRs get 2 review lenses, docs PRs 1.
Mutation testing (at most about 10 chosen mutants) for P572, P573 and P574.

| Row | Owner | Depends | What | Acceptance (tests) | Prod. lines |
|---|---|---|---|---|---|
| P570 | architect | Michael's answers | **Acceptance docs.** ADR 0047 status: accepted with the answers. Apply the GDD paragraph above. Dated status notes, no accepted text changed: ADR 0023 §10 (blackout writes hp; the "holds none" note superseded), ADR 0025 §7 and question 5 (narrowed) and §8 (question 3), ADR 0010 §1 (cut rows), ADR 0013 §5 (FOG reads `offline_until` and one rule). Adjust rows P575, P575b and P576 to the answers | docs lens; `tests/project` doc tests pass | 0 |
| P571 | ai-dev | none (may merge before P570) | **Strike counters in the smoke harness** (ADR 0047 §12): the eleven per-player keys, schema 2 unchanged; `balance_summary.gd` sums them per faction and level and gives per-fire means. Uses no `Strike.hit_damage` yet: until P572 it counts the rupture through the formula in the harness, then P572 switches it to the shared static. After merge, the lead dispatches the **"before" run** (P577's settings) on `main` | crafted-world tests for every key (a rupture kill, a blackout's building-ticks, a cut's cells, radar-dark ticks once P574 lands, 0 for a match with no strike); an old report without the keys still summarises | 0 (tests/) |
| P572 | gameplay-dev | P570; P571's "before" run dispatched | **Overload, data and sim** (ADR 0047 §1). `renew_overload.tres`; `renew_strike.tres` `strike_weapon`; `Strike.hit_damage` shared by `_land` and `_black_out`; the overload in the blackout pass (skip hp <= 0); header docs. Update `test_defs_strike_data.gd` (the blackout now holds a weapon; still no unit or building has it as `weapon`). HOW_TO_PLAY `superweapon-blackout`. Re-pin the shipped-data goldens that fire a Dusk Array, each named in the PR with the reason (ADR 0047 §6), and the `defs_hash` pins | 200 vs BUILDING armour; `Upgrades.taken` applied; at least 1; a row at 200 hp dies at that tick's REMOVE with DIED flag 0, `stat_lost_buildings` +1 and `Outcome` on the same tick; a row at 201 lives at 1; own, unit and air rows untouched; neutral hit; a row exactly on the radius hit; a SELL before it is skipped and a SELL after it pays on the lower hp; two arrays in one tick stack; no weapon (-1) means today's behaviour, bit for bit; frozen arena goldens unchanged; replay hash equal; the tutorial strike drill suites pass | ~60 |
| P573 | gameplay-dev | P570 | **Vision cut, sim plus FOG kernel twin** (ADR 0047 §2). `RulesDef.blackout_sight_cut` (RULE_SCALARS), `rules.tres` 1; `FogUpdate.run` wanted cell -1 while cut; the same in `core/fog.cpp`/`fog.h`/`kernel_fog.cpp` (+`offline_until`, +rule); `WorldLoad.stamp_fog` skips cut rows; header docs of FogUpdate, fog.h and FogGrid's invariant. HOW_TO_PLAY `superweapon-switched-off`. Re-pin the shipped-data goldens it moves and the `defs_hash` pins | the cut lands on the owner's first fog turn at or after the strike, and the return on the first turn at or after `offline_until`, exact ticks with `fog_period_ticks` 3 and players 1 and 2; dirty lists hold the flipped cells; a death while cut takes nothing away twice (counts never below 0); FogGrid rebuilt from the hashed rows equals the live one; rule 0 gives an identical hash to today on a match with a blackout; a unit standing in the ring keeps its disc; an enemy seen only by a cut building is not targetable (TARGETING, both implementations) and is absent from the victim's `PlayerView`; `LastSeen` keeps the record; a sweep that is on still shows the whole map; FOG lockstep crafted and random cases; sanitizer case; `check-native-tests.sh` | ~50 GDScript + ~40 C++ |
| P574 | gameplay-dev | P570 | **Radar rule, sim and snapshot** (ADR 0047 §3). `BuildingDef.radar` to `type_radar` (TYPE_ARRAYS); both radar `.tres` set it; `game/sim/Radar.gd` (`dark`, `dark_until`); `MatchSnapshot` copies `type_radar` and fills `radar_dark`/`radar_dark_until` per player once per capture (preallocated). Re-pin the `defs_hash` pins | dark only with a complete radar offline and none complete online; no radar means never dark; low power means not dark; a site does not count either way; a second online radar or one finished during the blackout clears it; selling or losing the dark radar clears it; `dark_until` is the lowest `offline_until` of the dark radars; the snapshot flag flips on the firing step's snapshot and clears on the snapshot where `offline_until <= snap.tick`, the same snapshot as the offline glyph; the frozen arena's radar is never dark; no allocation in capture (the snapshot's alloc test) | ~80 |
| P575 | touch-ux-dev | P574 | **The dark radar scope and full map** (ADR 0047 §8). `RadarScope` dark face (panel disc, `glyph_offline`, amber drain ring to `radar_dark_until`); the tap nudges and opens nothing; an open `RADAR` closes and hold-to-send is cancelled; `MinimapImage` keeps patching; the crop returns on the next paint. HOW_TO_PLAY: new `superweapon-blackout-radar` with its `data/help/how_to_play.tres` entry, and a clause in `camera-radar` | headless UI tests at the six sizes, upright and sideways: face shown and hidden by the snapshot flag; ring fraction from the ticks; tap gives a nudge with no state change; open map closes; no label contains OFFLINE, ONLINE, SIGNAL or DOWN; the scope's draw count at rest is unchanged; HOW_TO_PLAY id and coverage tests pass | ~150 |
| P575b | touch-ux-dev | P572 | **Overload sparks** (+ the attack cue if question 3 is yes). For a STRIKE record of kind 2, one `HitFx` flash plus chips on every shown non-firer building in the radius (snapshot positions, squared distance), the lowest ids first while the ring has slots, and none on a building with a DIED record that tick. If question 3 is yes, `AttackCues` raises one cue per such record when an own building lies in the radius and the point is out of view, and HOW_TO_PLAY `combat-under-attack` gets its clause | view tests on crafted snapshots: sparks only on shown buildings; no sparks for the firer's own; reduced effects drop the chips; ring overflow takes the lowest ids; a kill shows the collapse, not a flash; cue raised once per strike out of view, none in view, none for the firer (if question 3 is yes) | ~100 |
| P576 | ai-dev | P573, P574 | **AI awareness** (ADR 0047 §9). `AiStrikes` Dusk Array tie-break: between candidates of equal value, the ring that covers a seen or remembered enemy radar (`type_radar` from the view's types) wins. HOW_TO_PLAY `superweapon-computer` (Hard only, and the tie-break). If question 4 is B, this row grows by the AI handicap (re-plan first) | tie-break picks the radar's cluster and a non-tie ignores it; counted tests within `target_tests_max`; no pass over rows (`passes` 0); fairness: in a headless AI-vs-AI blackout, the victim AI's `AiIntel` lists lose the enemy that only a cut building saw, and the AI never reads a cell its fog does not show | ~50 |
| P577 | ai-dev | P571 to P576 merged | **Measurement, GitHub Actions only.** `balance.yml` `workflow_dispatch`, suite `custom`, levels `hard,hard`, scenarios `cross`, matches 100, map `kestrel`, seed_start 1. "Before" on the commit after P571 (dispatched there), "after" on the commit after P576. Report `docs/balance/2026-11-xx-dusk-overload.md`: per strike and fire, damage (enemy and own), kills (buildings, units, own), blackout building-seconds, sight cells lost, sight-cut building-seconds and radar-dark seconds; win rate and median match length by faction; before against after. A recommendation to Michael if the Array now outweighs the Bore. No local balance runs | the two artifacts and the report; the numbers come from the summaries only | 0 |
| P578 | architect | P577 | **Docs close-out.** ADR 0047 implementation note (rows and PRs as merged), the measured result and any data change P577 proposes (as a question to Michael, not applied), and the `rts-sim-conventions` line for the FOG cut rule | docs lens | 0 |

### Lanes and merge order
- **Wave 1:** P570 and P571 in parallel. P571 may merge first, and its "before" run is dispatched
  as soon as it merges.
- **Wave 2:** P572, P573 and P574 in parallel, after P570 merges and the "before" run has started.
  They touch different lines of `WorldShape.gd` and `WorldLoad.gd`, and each re-pins `defs_hash`
  pins. Verify their combined tree once before the second and third merge. Expect each later one to
  re-pin the same `defs_hash` pins again on rebase. No interaction review is needed: they touch
  different systems.
- **Wave 3:** P575 (after P574), P575b (after P572) and P576 (after P573 and P574) in parallel.
  P575 and P575b both edit HOW_TO_PLAY, in different rows.
- **Wave 4:** P577, then P578.
- **Critical path:** P570 → P573 → P576 → P577 → P578.

## Risks
1. **Legal and precedent (question 1).** A radar that goes dark is close to Command & Conquer's
   radar-offline look (ADR 0023 §13, ADR 0025 question 5). Mitigation: the dark state never depends
   on the player's own state, and it has its own look with no noise, no words and no announcer.
   Option B drops it.
2. **Indirect unit effect.** Units lose targets that only a blacked-out building saw (TARGETING
   reads the fog). Artillery's sight (9000-10000) covers its range (9000), so the effect is small.
   The GDD wording says "with their own eyes" so the claim stays true.
3. **FOG kernel drift.** This is the one native edit. Lockstep crafted and random cases plus the
   sanitizer case. The GDScript twin stays the reference (web path).
4. **Asymmetry against humans (question 4).** The dark scope costs a human attention and costs the
   AI nothing. The AI-vs-AI run cannot measure that part, so Michael's phone check of a Hard match
   as Derrick League is the only gauge.
5. **Dead rows still targeted in their last tick** (an overload kill in COMMANDS). This is the SELL
   precedent: a few wasted shots, no state error. The harness's rupture kill count is an upper
   bound.
6. **Balance swing.** The Lumen Accord may now win too often in Hard-vs-Hard. Three data levers:
   damage, the rule switch, and the radar flags. Mend pays the overload back, which softens it.
   P577 decides, and any tuning is a later row with Michael's yes.
7. **Re-pin churn.** Three parallel rows move the same `defs_hash` pins. Each re-pins on rebase,
   names the pins and gives the reason. The frozen arena's state goldens must stay unchanged, and a
   test guards that.
8. **Tutorial strike drill.** `tutorial_strikes.tres` loads the shipped Dusk Array, so the overload
   may kill a building a later beat needs. P572 runs the tutorial suites, and a failure goes back to
   the tutorial owner, not into a data tweak.
9. **The HitFx ring** (16 slots) overflows on a large strike. It is capped, with the lowest ids
   first, and no allocation.
10. **Saves and replays from older builds** are refused through `defs_hash` (ADR 0042). This is
    expected, and the restore note says so.
