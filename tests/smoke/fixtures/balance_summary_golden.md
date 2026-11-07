## Balance summary

Commit `abc123`, impl `native`, levels `normal,normal`, scenarios `cross`, at most 13500 ticks a match, seeds 1001-1004.

| Matches | Victories | Draws | Timeouts | Dropped | Flow full (total, most) |
| --- | --- | --- | --- | --- | --- |
| 4 | 4 | 0 | 0 | 0 | 1, 1 |

### Win shares (per-mille; a draw or a timeout counts half to each side)

| Group | Value | Share |
| --- | --- | --- |
| faction | fossil | 500 |
| faction | renew | 500 |
| seat | bottom | 500 |
| seat | top | 500 |

### Match length

Median 8.9 min, 90th percentile 8.9 min, longest 8.9 min (8000, 8000 and 8000 ticks).

### Unit types

| Faction | Type | Produced | Share | Kills per 1 000 credits | Survival | Built in |
| --- | --- | --- | --- | --- | --- | --- |
| fossil | artillery | 4 | 167 | 0.00 | 1000 | 4 |
| fossil | harvester | 4 | 167 | 0.00 | 1000 | 4 |
| fossil | heavy_tank | 4 | 167 | 0.00 | 1000 | 4 |
| fossil | light_tank | 4 | 167 | 0.00 | 1000 | 4 |
| fossil | rifle_squad | 4 | 167 | 0.00 | 1000 | 4 |
| fossil | rocket_squad | 4 | 167 | 0.00 | 1000 | 4 |
| renew | renew_artillery | 4 | 167 | 0.00 | 1000 | 4 |
| renew | renew_rifle | 4 | 167 | 0.00 | 1000 | 4 |
| renew | renew_rocket | 4 | 167 | 0.00 | 1000 | 4 |
| renew | renew_scout | 4 | 167 | 0.00 | 1000 | 4 |
| renew | renew_tank | 4 | 167 | 0.00 | 1000 | 4 |
| renew | renew_tanker | 4 | 167 | 0.00 | 1000 | 4 |

Share and survival are per-mille, rounded half up; a type that never occurred shows 0.
Kills are an estimate, credited in this order: a shot at the row in the tick it died; else an enemy rupture landing in that tick within its radius (to the strike building's type); else the row's last shooter; else nobody. Kills by structures (turrets, strike buildings) are not in the unit rows; a cancelled site is neither a loss nor a kill. Kills by free rows (the scenario's units, a refinery's tanker) count, while the credits spent count produced rows only.

### Flags

- the flow cache was full in 1 ticks

Distinct final hashes: 4.

### Gate: FAIL

| Check | What | Value | Limit | Verdict | Detail |
| --- | --- | --- | --- | --- | --- |
| set | a gate set | 0 | 1-1 | fail | 4 matches are not seeds 1001-1100 or 1001-1200 |
| 1 | faction win share | 500 | 400-600 | pass | fossil 500, renew 500 |
| 2 | top seat win share | 500 | 400-600 | pass | top 500 |
| 3a | timeouts | 0 | 0-0 | pass |  |
| 3b | longest match (ticks) | 8000 | 0-13500 | pass |  |
| 4 | least built unit type (matches) | 4 | 2-4 | pass | artillery in 4 of 4 |
| 5 | dropped commands (all matches) | 0 | 0-0 | pass |  |
| 6 | distinct final hashes | 4 | 4-4 | pass |  |
| 7 | impl is native | 1 | 1-1 | pass | impl native |
