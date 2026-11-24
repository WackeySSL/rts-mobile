# Dusk Array overload and vision cut, measured 2026-11-24

Plan row P577 (`docs/plans/2026-11-23-dusk-overload.md`), ADR 0047 section 12. The question: does
the Dusk Array, with the overload (200 damage to every enemy building in its ring) and the vision
cut, now weigh as much as the Deep Bore? Both runs are GitHub Actions balance runs; nothing here
was run in a session. Every number is from the two run summaries (`custom.md` and `custom.json`).

## 1. The runs

| | Commit | Run | Includes |
| --- | --- | --- | --- |
| Before | `47d3f7c5054514e9024db339f33bf796070fc6ae` | 45328608622 | P571 (the counters); no overload, no cut, no radar rule |
| After | `fb587e8eec4d21484436e21e4f8ad201de3fad3e` | 45455461192 | P572 to P576 (overload, cut, radar rule, AI tie-break) |

Same settings in both: suite `custom`, `hard,hard`, scenarios `cross`, 100 matches, map `kestrel`,
seeds 1-100, impl `native`, at most 13500 ticks a match. P580 (#636) merged after the after-run, so
it is in neither.

## 2. Strikes, per fire

Fossil fires the Deep Bore (rupture), Renew the Dusk Array (blackout). Damage and kills are the
firer's; blackout, sight and radar numbers are the victim's. Seconds are 15 ticks. A rupture's
kills are an upper bound.

| Run | Group | Fires | Damage (enemy) | Damage (own) | Kills: buildings | units | own | Blackout building-s | Sight cells lost | Sight-cut building-s | Radar-dark s |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Before | Fossil (Bore) | 91 | 1231.14 | 46.13 | 0.02 | 4.56 | 0.42 | 0.00 | 62.15 | 0.00 | 0.00 |
| Before | Renew (Array) | 97 | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 | 75.10 | 3.17 | 0.00 | 0.00 |
| After | Fossil (Bore) | 91 | 1221.32 | 45.73 | 0.03 | 4.49 | 0.40 | 0.00 | 58.64 | 0.00 | 0.00 |
| After | Renew (Array) | 97 | 501.95 | 0.00 | 0.01 | 0.00 | 0.00 | 74.73 | 14.93 | 74.40 | 0.00 |

What moved for the Array: damage 0 to 502 a fire, sight cells lost 3.17 to 14.93, sight-cut
building-seconds 0 to 74.40 (the blackout seconds themselves are unchanged, 75.10 to 74.73, so the
AI fires it at the same kind of target). Kills went from 0 to 0.01 buildings a fire (one building
in 97 fires). The Bore moved only by noise (1231 to 1221 damage), as expected: P572 to P576 do not
touch it. The Array still does no damage to units and no own damage.

## 3. Win rate and match length, by faction

| Run | Fossil | Renew | Top seat | Bottom seat | Victories | Timeouts | Median length |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Before | 505 | 495 | 505 | 495 | 1 | 99 | 15.0 min (13500 ticks) |
| After | 505 | 495 | 505 | 495 | 1 | 99 | 15.0 min (13500 ticks) |

Win shares are per-mille; a timeout counts half to each side. The one victory is seed 5, player 1
(Fossil, top seat), at tick 12527, in both runs. The 90th percentile and the longest match are also
13500 ticks in both. So the strike changes did not move who wins or how long a match lasts in
Hard vs Hard on Kestrel: 99 of 100 matches end on the clock either way, and the shares carry no
signal beyond the one victory. Flow-cache and command-drop counts differ by under 1 percent
(dropped 366 to 364, expired 306 to 303, stale 60 to 61).

## 4. Does the Array now outweigh the Bore?

No. Per fire the Array deals 502 damage against the Bore's 1221 (41 percent), kills 0.01 buildings
and no units against the Bore's 0.03 buildings and 4.49 units, and costs the victim 14.93 sight
cells against the Bore's 58.64. What the Array has that the Bore does not: it hurts nobody of its
own (the Bore's own damage is 45.7 a fire and 0.40 own kills), and it holds about 75 building-seconds
of enemy production and power off per fire, with 74 of them also sight-cut. That is a control tool,
not a damage tool, and the win shares (505/495, unchanged) show no effect on the match. In this
setup the Array's 200-damage overload is a chip: 502 damage a fire over about 2.5 buildings.

## 5. Radar-dark seconds are 0, in every match

The Array fired 97 times in the after-run and blacked out 108743 building-ticks (about 2.5 buildings
a fire for 450 ticks each), yet `radar_dark_ticks` is 0 for both players in every match. Checked
two ways:

- Counter: not a bug. `tests/smoke/smoke_count.gd` `_count_offline` calls `Radar.dark(world, player,
  world.tick)` on every counted step, the same function the snapshot uses. A crafted world with a
  real Dusk Array firing through the sim (`Strikes.step`) and the counter's `before_step` and
  `after_step`, with a complete flagged radar inside the ring, gave `radar_dark_ticks` 90 (every step of
  the rig's 90-tick blackout), and with the radar outside the ring gave 0. This one test was a
  throwaway and is not committed. The shipped `fossil_radar.tres` and `renew_radar.tres` carry `radar = true` and the smoke
  uses the shipped data, so `type_radar` is set in a real match. Each Fossil side had one
  `fossil_radar` in every match (`structures` in the per-match data), so the one-radar case applies:
  dark means that one radar is in the ring.
- Behaviour: the Array's target is the point whose 4-tile ring holds the most enemy value
  (`AiStrikes._best`, `game/ai/AiStrikes.gd`). P576's radar rule only breaks a tie of exactly equal
  value (`elif sum == best_sum`), so a radar outside the best-value ring is ignored. In 97 fires on
  100 seeds, no ring that won on value held the radar. The data does not say how often a ring could
  have covered it (the report has no positions); on 100 seeds with a 4-tile ring the radar is
  simply not near the producer cluster that has the value.

So the dark radar scope (ADR 0047 section 8) and the P576 tie-break are untested by the balance
run, and the AI as shipped almost never causes them. A human player aims at the radar on purpose;
the AI does not.

## 6. Questions for Michael (nothing applied)

1. Should the AI get a bonus for a ring that covers the radar, so the dark scope happens in
   AI-vs-AI matches (a data weight for the radar in the Dusk target value, or a larger tie
   window)? Today the tie-break is almost never reached. This is an AI change and needs a yes.
2. Is "control tool, not a damage tool" the intended weight for the Array? If it should compete
   with the Bore, the levers are data only: `data/weapons/renew_overload.tres` `damage` (200 now;
   the Bore does 1221 a fire spread over units, the Array has only buildings to hit), or
   `data/units/renew_strike.tres` `strike_radius` (4000) and `strike_ticks` (450). One variable at a
   time, same seeds, a new run each.
3. The match length is 15 minutes in 99 of 100 matches in both runs; the Phase 5 gate measures the
   8 to 10 minutes in human playtests (P556, 2026-11-23), so this report does not treat it as a
   finding.

## 7. Flags

Unchanged between the runs: the median length of 13500 ticks is outside 7200 to 9000 (P556 closed
this), and the unit-share flags (for example `fossil_bunk_wagon` and `renew_linecar` never
produced, `rifle_squad` and `renew_rifle` above 40 percent) are the same list as before. No new
flag from the strike changes.

## 8. Michael's answers (2026-11-24)

"Ja til begge":

1. Yes, the AI gets a radar bonus: a data value in `OpponentDef` that adds to the Dusk Array ring's
   value when the ring covers a seen or remembered enemy radar. Row P576b (ai-dev). Then a new
   after-run, P577b, with the same settings: radar-dark seconds above 0, and win shares and the Bore
   unchanged.
2. Yes, the Array stays a control tool. No change to `renew_overload.tres` or `renew_strike.tres`.

P578 records both answers in ADR 0047.
