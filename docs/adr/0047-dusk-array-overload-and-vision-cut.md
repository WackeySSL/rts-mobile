# ADR 0047: The Dusk Array's overload and vision cut

**In short, for Michael:** when the Dusk Array fires, every enemy building in its ring also takes
one overload hit of 200 (from a weapon file in `data/`, like the Deep Bore's). A building with
200 hp or less left is destroyed by it. For the 30 s of the blackout, those buildings also give
their owner no sight: the fog closes in wherever only they saw. If the strike catches the victim's radar
building (Signal Mast or Relay Post) and they have no other working one, their round radar and full
map go dark for that time. Units are not touched: they keep moving, shooting and seeing. The
computer loses exactly the same sight as a human, because it reads the same fog.

Status: **proposed**. The two changes were decided by Michael on 2026-11-23 (overload damage of
about 200 from data; a vision cut for the length of the blackout, the exact rule left to the
architect). Four questions below need his answers before the code rows start. Written by the
architect on branch `claude/p57x-dusk-overload-plan` (base `main` at 56694ad1). Plan:
`docs/plans/2026-11-23-dusk-overload.md` (rows P570-P578).

Amends, by dated status notes that P570 writes once this ADR is accepted (no accepted text is
rewritten):
- ADR 0023 §10, "Blackout": the blackout now also takes hp (§1 below). Its status note of
  2026-10-27 ("the blackout holds none" strike weapon) is superseded: the Dusk Array holds one.
  "Units are not affected" stands.
- ADR 0025 §7, "Never offline", and its question 5: narrowed. The radar never depends on the
  player's own state (owning a radar, power); only an enemy Dusk Array on the radar building darkens
  it (§3). This needs Michael's yes (question 1), because it reverses his own answer to question 5.
- ADR 0025 §8's open question (a strike raises no attack cue): answered by question 3.
- ADR 0010 §1 (a row is re-stamped only when its cell changed): a row also loses its disc while its
  building is blacked out (§2).
- ADR 0013 §5, the FOG kernel: it reads one more row column (`offline_until`) and one more rule
  int (`blackout_sight_cut`). The twin rule holds.

## Context
The Deep Bore deals 600 damage to every ground row in 3 tiles (own rows included), after a 3 s
warning. The Dusk Array deals no damage: it switches enemy buildings in 4 tiles off for 450 ticks.
"Off" means no power made or used, defences silent, production, repair, airfields and the space
centre's sweep paused (`Strike._black_out`, read by `Power.run`, `Combat.fire`, `Production.run`,
`Repair.run`, `Air.run` and `Reveal.run`). Harvesting is not affected. Both cost 2500, use 60
power and charge for 4500 ticks. Michael finds the Dusk Array weaker and chose two changes that
keep the factions different: the Bore destroys, and the Array blinds and cripples, with a smaller
hit.

What exists that this builds on:
- The blackout runs at once in the command's apply (COMMANDS), one pass over `building_rows` in
  ascending row order, and writes only `offline_until`. Nothing is pending.
- The rupture's damage is `Combat.damage(weapon_damage, weapon_vs_armour[armour], PERCENT,
  Upgrades.taken(...))`, at least 1 when the percent is above 0, in `Strike._land` (FIRE).
- SELL and CANCEL_BUILD already set a row's hp to 0 in COMMANDS. The row stays until that tick's
  REMOVE, and TARGETING and FIRE may still pick it (`Production.apply_sell`).
- Fog: `FogUpdate.run` (GDScript twin plus the C++ FOG kernel) moves a row's disc when its cell
  differs from `fog_cell` (hashed, -1 = not stamped), on its owner's fog turn (`fog_period_ticks`
  3). Buildings never move, so after the first stamp FOG never touches them again. `Removal` takes
  away a dying row's disc only when `fog_cell >= 0`. `WorldLoad.stamp_fog` stamps every row at
  prepare(). `fog.visible` is not hashed (ADR 0016). TARGETING, `LastSeen`, `MineMemory`,
  `PlayerView` and the view read it.
- The radar scope and the full map (`RadarScope`, `RadarMap`, `Minimap`, `MinimapImage`) are an
  interface over the local player's fog and rows. The AI has no such interface: it reads
  `PlayerView`, which takes visibility from the same `fog.visible` (`Targeting.sees`).
- The perf and base arenas run on frozen defs in `data/dev/arena/` (P171). Their state goldens must
  not move.

## Decision

### 1. Overload damage
- **Data.** A new `WeaponDef` `data/weapons/renew_overload.tres`: `id` `renew_overload`, `damage`
  200, `vs_armour` (0, 0, 0, 100), `targets` 1 (ground), no range and no flight. The 0 % against
  the unit classes is a second guard; the pass reads only buildings anyway.
  `data/units/renew_strike.tres` gets `strike_weapon` = it. Nothing new in `BuildingDef` or
  `World`: `type_strike_weapon` exists (ADR 0023 §10) and is -1 for the frozen arena's Dusk Array,
  so the arena does no overload.
- **When.** In the same pass as the blackout, in the command's apply (COMMANDS, at once), row by
  row in ascending order. Each building that the blackout reaches (not the firing player's, neutral
  ones included, centre within `type_strike_radius` by squared distance) first gets its
  `offline_until` as today, then loses `Strike.hit_damage(world, row, weapon)`. That is the
  rupture's formula, moved into one shared static that `_land` also calls: armour percent,
  `Upgrades.taken`, at least 1 when the percent is above 0, and 0 when the percent is 0. A row whose
  hp is already 0 or less (sold or cancelled this tick, or killed by an earlier overload in the same
  COMMANDS) is skipped, so a death is never counted twice. Units are never in `building_rows`, so
  no unit loses hp. The firing player's own buildings are untouched.
- **Can it kill? Yes** (question 2, recommended A). A building with hp at or below the hit falls to
  0 and dies at that tick's REMOVE, exactly like a sold row. It is offline in its last tick (no
  shot, no power, no production). `Outcome.count_losses` counts it in `stat_lost_buildings`, its
  DIED record has flag 0 (a real loss, so the collapse and the crater show), and `Outcome.run` sees
  a lost last producer on the same tick. TARGETING and FIRE may still aim at it in its last tick,
  as at a sold row, so a few shots can be wasted. This is the existing SELL rule, not a new one.
- **Order with other commands.** Commands apply in `Command.compare` order. If the victim's SELL of
  the same building comes first, the overload skips the sold row. If the overload comes first, the
  sale pays on the lower hp, or is refused at 0 hp.
- **Two Dusk Arrays in one tick** (a player with two, or two players): each is its own strike, so
  each hits. `offline_until` keeps the longer one, as today.
- **Mines are not cleared** (the rupture clears them; the overload touches buildings only).
- **Damage states (ADR 0028, ADR 0029).** Stages come from hp in the view (thresholds 67 and 34),
  so the overload moves a building's stage with no new code. A 200 hit takes 10-29 % off today's
  buildings (700-2000 hp): a building at full hp stays intact, apart from the 700 hp anti-air at
  71 %. `BuildingLayer`'s write budget (20 building writes a frame) spreads a big strike over
  frames, as for a rupture. A blacked-out building's `anim` holds (ADR 0027 §6), and its damage
  smoke and fire go on (ADR 0028). An enemy building's new stage shows only where the firing player
  sees it (GDD, fog). Mend (ADR 0037 §4) goes on during a blackout, so the owner can pay the damage
  back. This is accepted and measured (P577).
- **No new event.** The STRIKE record (ADR 0027 §7) already says where and when. The view finds
  the hit buildings from it (P575b). The sim writes no IMPACT for the overload, as the rupture
  writes none.

### 2. Vision cut: blacked-out buildings give no sight
- **Rule.** While `blackout_sight_cut` is 1 (a new `RulesDef` int, default 0; `data/rules.tres` 1;
  the frozen arena's `rules.tres` leaves it at 0), a row whose `offline_until` is above the stamp
  (`world.tick + 1`, the rule `Strike`, `Power` and `Reveal` use) has no disc. In `FogUpdate.run`
  the row's wanted cell becomes -1 instead of its position's cell. The existing walk does the rest:
  a wanted cell equal to `fog_cell` is skipped; otherwise the new disc is stamped if the cell is 0
  or more, the old one is taken away if `fog_cell` is 0 or more, and `fog_cell` takes the wanted
  cell. So the disc goes on the owner's first fog turn at or after the strike's step, and comes
  back on the owner's first fog turn at or after the step in which the building is back online. The
  delay is at most `fog_period_ticks - 1` steps (2 steps, 0.13 s), the same for every run and
  every machine. Only buildings ever have an `offline_until` (`Strike._black_out` walks
  `building_rows` only, and a P573 test pins that no unit row ever gets one), so units keep their
  sight.
- **`WorldLoad.stamp_fog`** (prepare) applies the same rule, with the World's tick as the stamp: a
  row with `offline_until > world.tick` is left unstamped (`fog_cell` -1). On a fresh match nothing
  is offline, so this only matters for hand-built test Worlds. Their fog then matches what a run
  would have.
- **`Removal`** is unchanged. A row that dies while cut has `fog_cell` -1, and nothing is taken
  away twice.
- **What the victim loses.** Every cell that only blacked-out buildings saw drops to not visible in
  the victim's block of `fog.visible`, through the dirty list, so `FogLayer` fades it as usual.
  `explored` stays. The victim's own buildings are still drawn (own rows always are). The ground
  round them dims to "explored", and enemy units there vanish into the fog. Enemy buildings already
  recorded by `LastSeen` stay as dimmed records (fog memory, P77b), and no new record is made where
  nothing sees. TARGETING takes visibility from the same counts, so an own unit cannot pick an enemy
  that only a blacked-out building saw. This changes no unit's state: "Units are not affected"
  holds, and the unit's own sight works as before.
- **Hash.** `fog_cell` is a hashed row column, so it now takes -1 for a cut building. No new column
  and no layout change, so no `STATE_FORMAT` bump.
- **Kernel twin (ADR 0013 §5).** `core/fog.cpp`, `fog.h`'s `Rows` and `Rules`, and
  `kernel_fog.cpp` read `offline_until` and `blackout_sight_cut`. `world_access.h` gets the column
  id if it does not have it. The GDScript twin stays the reference. The lockstep suites get crafted
  blackout cases (P573).
- **Rejected: a GDScript pass in REMOVE that takes the disc away and leaves `fog_cell` as it is.**
  `Removal` would then take a cut row's disc away a second time, `stamp_fog` would stamp it, and
  telling them apart would need an unhashed per-row flag that `Removal` compacts, a new kind of
  column. The FOG rule uses the meaning `fog_cell` already has (-1 = no disc).

### 3. The radar goes dark
- **Which building is a radar.** A new `BuildingDef` export `radar: bool` (default false) becomes
  `type_radar` (TYPE_ARRAYS, 0 or 1, in `defs_hash`). `fossil_radar` (Signal Mast) and
  `renew_radar` (Relay Post) set it. The frozen arena's copies do not, so the arena's radar never
  goes dark.
- **Rule (derived, not stored).** Player p's radar is dark at stamp s when p owns at least one
  complete (`build_left` 0) radar building with `offline_until > s`, and no complete radar building
  with `offline_until <= s`. A player with no radar building has a working radar scope, as today:
  the minimap never needs a radar (ADR 0023 §13 stands). Low power never darkens it. A second radar
  that is online, or one finished during the blackout, keeps or brings the scope back. If the
  blacked-out radar is sold or destroyed and no other radar stands, the scope comes back too,
  because the player then owns no radar. The radar's tech gate is lost with it, so this is an
  expensive way out, and it is allowed. The dark time ends at the lowest `offline_until` among p's
  blacked-out complete radars. The view's countdown reads that.
- **Where it lives.** A new sim module `game/sim/Radar.gd` with two pure statics,
  `Radar.dark(world, player, stamp) -> bool` and `Radar.dark_until(world, player, stamp) -> int`.
  Each makes one pass over `building_rows` and allocates nothing. It is a module of its own so that
  P574 does not edit `Strike.gd` while P572 does. `MatchSnapshot` calls them once per capture
  for each player (on the worker, after the step) into two preallocated per-player arrays,
  `radar_dark` and `radar_dark_until`, with the World's new tick (`snap.tick`) as the stamp. That is the stamp `BuildingLayer`'s offline glyph uses, so the glyph
  and the dark scope start and stop on the same snapshot. The scope goes dark on the snapshot of
  the firing step, because the blackout is applied in COMMANDS.
- **Hash.** Derived from hashed columns. No hash section, no `STATE_FORMAT` change. Adding
  `type_radar` moves every `defs_hash` pin, the frozen arena's included (a new array in the
  digest), but no state golden.
- **Rejected: a hashed per-player `radar_dark_until` written by the blackout.** It means a
  `STATE_FORMAT` 8 and a re-pin of every state golden, the frozen arena's included, for state that
  follows from columns we already hash.

### 4. Fairness (GDD pillar 4) and what each side sees
- **The sight is shared state.** The vision cut changes `fog.visible`, which the human's fog layer,
  minimap and picking, TARGETING and the AI's `PlayerView` all read. An AI victim loses exactly the
  cells a human victim loses, on the same tick. Its `AiIntel` lists stop showing enemies there, and
  its `LastSeen` records stay as they were. A headless test proves it (P573: the victim's
  `PlayerView` visibility equals its fog block, with the cut and without it).
- **The radar is an interface, not information.** A dark scope removes no information the sim
  gives the player. The human can still pan the main view and see whatever their units and their
  working buildings see. What the human loses is the overview: the scope's crop, the full map with
  its camera jump and its hold-to-send, the rim wedges and the map ping. The attack toast at the
  top stays (ADR 0025 §8: it is not the radar). The AI has no overview to lose: it already reads
  its whole `PlayerView` every think. So for the radar part, the human pays an attention cost that
  the AI does not. Question 4 asks whether to mirror it. The recommendation is no: pillar 4 is about
  the same rules and no unscouted vision, and both hold. The cost of not mirroring is that an
  AI-fired Dusk Array weighs a little more on a human than a human's does on the AI (Risks, plan).
- **What the human victim sees:** the fog closing in round the blacked-out buildings, the offline
  glyph over them (today's), the overload's sparks and the damage stages (P575b). If their radar is
  caught: a dark scope with the offline glyph and a countdown ring, and no full map until it comes
  back (§8).
- **What the human firer sees:** the strike's fall (ADR 0027), the offline glyph over each enemy
  building they can see, the sparks and the new damage stages where they see them, and nothing
  about the victim's radar.
- **What the AI firer and the AI victim know:** the AI firer knows only what its `PlayerView` shows
  (enemy `offline_until` is MISSING to it, as today). The AI victim reads its own rows'
  `offline_until` (it already skips firing a blacked-out strike building) and its own fog.

### 5. Interplay
- **Reveal (ADR 0036 §11).** The space centre's sweep is a whole-block +1, separate from the discs.
  If the victim's sweep is on (its space centre outside the ring), the victim still sees the whole
  map, so the vision cut changes nothing it sees until the sweep ends. If the space centre is
  inside the ring, the sweep pauses as today and its own disc is cut as well. The firer's sweep is
  untouched. The radar rule does not read the sweep: a sweeping player whose radar is caught still
  gets a dark scope.
- **Mines (ADR 0037 §8).** Detectors are units (minelayers, scouts), so detection is unchanged.
  `MineMemory` forgets a found enemy mine only where it sees, so a cut base forgets nothing new.
  The overload does not clear mines.
- **Air (ADR 0036).** Aircraft are units: they keep their sight and can cover a blinded base. The
  airfields and pads in the ring are offline (no reload or repair, as today), are cut, and take the
  overload. The overload weapon hits ground only, and buildings are ground.
- **Fog memory.** `explored` never clears. Last-seen records of enemy buildings stay until the spot
  is seen again. A building that dies while its owner's sight is cut has no disc to take away; the
  enemies who saw it fall drop their record of it, as today.
- **Placement** reads `explored`, not `visible`, so building near a blinded base works as before.
- **Attack cues (ADR 0025 §8).** An overload kill raises the victim's cue through its DIED record,
  with no new code. Question 3 asks for one cue per strike for the victim's buildings hit out of
  view, from the STRIKE record (P575b).

### 6. Determinism, replay and hashes
- Integers only. Every number comes from data: the weapon (200, percents), the radius and length
  (`renew_strike.tres`), the rule switch (`rules.tres`) and the radar flags. Ascending row order
  everywhere, no randomness, no time and no frame delta.
- No new Command and no change to SUPERWEAPON 15. No `STATE_FORMAT` change. Hashed values that move:
  `hp` (overload) and `fog_cell` (cut), only in matches where a shipped Dusk Array fires.
- `defs_hash` moves (new weapon, new rule int, new TYPE array). Old replays and a save from an
  older build are refused, as for any data change (ADR 0042: Continue deletes the file with a note).
- State goldens on shipped data that fire a Dusk Array (for example `test_strike_shipped.gd`,
  `test_dev_strikes.gd`, `test_replay_sweep.gd`, the tutorial strike drill) are re-pinned in the row
  that moves them, with this ADR as the reason. Each row lists the exact pins it moves. The frozen
  arena's state goldens and the `[sim]`/`[bases]` workloads do not move. The `defs_hash` pins do
  (P572, P573 and P574 each move them once).

### 7. Cost (150 units at 60 fps)
- Overload: inside the existing blackout pass, one more multiply per building in the ring, once
  per strike. No allocation.
- Vision cut: one more read and compare per row on the owner's fog turn, in both twins.
- Radar: one pass over `building_rows` per player per snapshot capture, on the worker. No
  allocation.
- View: while dark, the scope draws one disc, a glyph and an arc instead of its crop, and the
  minimap skips its paint, so it costs less. The overload sparks use `HitFx`'s ring (16 slots); a
  strike that hits more shown buildings than there are free slots draws sparks on the lowest ids
  first.

### 8. View and HUD (P575, P575b)
- **Dark scope.** The scope's crop, frame, rim wedges and ping are replaced by the HUD panel's dark
  disc, the existing offline glyph (`glyph_offline.svg`, amber) at its centre, and a thin amber
  ring on the rim that drains clockwise to `radar_dark_until`. No noise, no static, no blinking, no
  word: no "OFFLINE", "ONLINE", "NO SIGNAL" or "RADAR DOWN", and no sound line (§11). A tap on the
  dark scope gives the scope a small nudge (the charging strike button's refusal) and opens
  nothing. A full map that is open when the radar goes dark closes (`HudState` back to NONE), and
  hold-to-send through it is cancelled. When the radar comes back, the crop returns on the next
  paint. `MinimapImage` keeps patching its ground from the dirty lists while the scope is dark (the
  CPU work is small), so the picture is current at once.
- **Overload sparks.** For a STRIKE record of kind 2, every building inside its radius that is not
  the firer's and that the local player is shown (`BuildingLayer.is_shown`) gets one `HitFx` flash
  and its chips (the reduced-effects rule drops the chips). A building that died in that tick shows
  its collapse instead (HitFx's DIED rule).
- **Portrait and landscape** (ADR 0015): the scope keeps its size and place. The dark face is drawn
  in the same rect, so nothing moves on a turn.

### 9. The AI (P576)
- Nothing new is needed for the AI to lose sight (§4). `AiStrikes`'s Dusk Array keeps its rule
  (once per wave, the producer cluster of most value near the wave's goal). One tie-break is added:
  between candidates of equal value, the one whose ring also covers a seen or remembered enemy
  radar building (`type_radar` from the view's type table) wins. It reads only what the AI may
  know.
- `AiStrikes` counts no overload kills and no darkness. The data stays tunable, and the
  measurement (P577) decides whether the AI should aim for damage.

### 10. HOW_TO_PLAY rows
Each feature row updates its own rows in the same PR (CLAUDE.md):
- `superweapon-blackout` (P572): add the overload ("every one of those buildings also takes
  an overload hit (`strike_weapon` of the Dusk Array); one with that much health or less left is
  destroyed").
- `superweapon-switched-off` (P573): "...and it sees nothing while it is off: the fog closes in
  where only switched-off buildings saw, unless one of your units or another building sees it;
  your units still see". Only P573 edits this row and only P572 edits `superweapon-blackout`, so
  the two parallel PRs never touch the same line.
- New `superweapon-blackout-radar` (P575): "Your radar building (Signal Mast or Relay Post) is
  switched off by a Dusk Array and you have no other one working | The round radar goes dark: the
  switched-off sign in its middle and an amber ring that runs down until it comes back. Tapping it
  opens nothing, and an open full map folds away. The message at the top still tells you when you
  are attacked. A second radar that works, or one you finish meanwhile, keeps it on". The row's id
  goes into `data/help/how_to_play.tres`.
- `camera-radar` (P575): one clause pointing to `superweapon-blackout-radar`.
- `combat-under-attack` (P575b, only if question 3 is yes): "A Dusk Array's overload on your
  buildings out of view raises one too".
- `superweapon-computer` (P576): fix "Normal and Hard" to what ships (only Hard's build orders
  build a strike building since P192b), and add the radar tie-break.

### 11. Legal screen (ADR 0023 §13)
- "Radar unlocks the minimap" (Tiberian Dawn's Communications Center, Red Alert's Radar Dome) stays
  **not taken**: owning no radar, or low power, never darkens the scope.
- The closest analogues of a strike that shuts down buildings and with them the radar are Tiberian
  Sun's EMP Cannon and Generals Zero Hour's EMP Pulse (already listed for the Blackout Array).
  Game rules are not protected by copyright, but the project avoids look and wording. What we take:
  a building-only disable with a dark disc. What we avoid: static or noise, "radar offline"/"radar
  online" words or announcer lines, blue lightning, EMP wording. "Overload" is a common
  electrical word, and no unit or weapon of those games is called that. The weapon id
  `renew_overload` is internal. The GDD's player word is "overload hit".

### 12. Measurement (P571, P577)
The smoke harness counts, per player and match (added keys, report schema 2 unchanged, as P254
added keys), from STRIKE records, the World before and after the step, and DIED records, outside
the sim:
`strike_fires_rupture`, `strike_fires_blackout`, `strike_damage_enemy` (hp the player's strikes took
from other and neutral rows), `strike_damage_own`, `strike_kills_buildings`, `strike_kills_units`,
`strike_kills_own`, `blackout_building_ticks` (victim side: own complete buildings offline, summed
per step), `sight_cut_building_ticks` (victim side: own buildings with `fog_cell` -1 while offline),
`sight_cells_lost` (victim side, per strike: cells visible at the end of the step before the strike
and not visible after the victim's first fog turn after it), `radar_dark_ticks` (victim side). The
overload's exact share comes from `Strike.hit_damage` on the hp before the step (COMMANDS precedes
the shots). A rupture's kill is a row in the ring that died in the landing step with hp before the
step at or below its hit, which is an upper bound when shots also landed. The report gives per fire:
damage, kills, blackout building-seconds (/15), sight cells lost and radar-dark seconds, plus the
win rate and match length by faction, before and after. Balance runs only on GitHub Actions.

## Consequences
- The Dusk Array now destroys weak buildings and blinds a base. It stays the opposite of the Bore:
  no warning, no own damage, no unit damage, a wide ring and a small hit.
- Three data levers to tune it after P577: the weapon's damage, the rule switch, and the radar
  flags. The ring and the length are unchanged.
- One kernel edit (FOG) with its twin, lockstep and sanitizer cases. Mutation testing applies to
  P572 and P573 (they touch `game/sim/` and `native/`), and to P574 (`game/sim/`).
- Every `defs_hash` pin and the shipped-data state goldens that fire a Dusk Array move once. The
  frozen arenas' state goldens stay.
- The view gains a dark scope state. ADR 0025's "never offline" becomes "never offline by your own
  state".
- An AI-fired Dusk Array weighs more on a human than the reverse (the attention cost of §4).

## Alternatives considered
- **The overload lands in FIRE through the pending strike** (`strike_tick` with a delay of 0). It
  would need a per-player strike type column (`STATE_FORMAT` 8), and it would block a player's
  next strike for a step for no gain. COMMANDS is enough, because SELL already kills there.
- **A surge when the blackout ends** (the damage at `offline_until`). It needs pending state per
  building, the hit comes 30 s after the cause, and the player cannot read it.
- **A non-lethal overload** (hp floor 1). This is question 2 B: one special case more, and a
  building at 1 hp would read as a bug.
- **Cutting the sight of all the victim's buildings while their radar is dark.** A bigger rule
  than Michael's, and it would make the radar a sensor hub, which is a new tech role.
- **Mirroring the dark radar for the AI with an attention window** (AiIntel reads only a
  camera-sized area). This is question 4 B: new AI rules for an interface effect.
- **Sight cut or EMP on units.** Rejected by ADR 0023 (TARGETING and INTEGRATE kernels), and the
  GDD says "Units are not affected".

## Questions for Michael
1. **The radar going dark** reverses your answer to ADR 0025 question 5 ("the radar is never
   offline") for one case only: an enemy Dusk Array on your radar building, while you have no other
   working radar. It never depends on owning a radar or on power. The look is a dark disc with our
   switched-off sign and a countdown ring: no noise, no "offline" word, no announcer. Recommended:
   **yes**. Option B is to drop the radar part and keep only the building sight cut, which keeps
   furthest from Command & Conquer.
2. **Can the overload destroy a building?** A: yes, a building with 200 hp or less left is
   destroyed (recommended). B: no, it stops at 1 hp.
3. **An attack message for the overload:** when a Dusk Array hits your buildings out of view, the
   red message at the top and the radar's rim mark show once, as for a hit ("<building> UNDER
   ATTACK"). If your radar is dark, only the message shows. Recommended: **yes**.
4. **The computer has no radar screen to lose.** It loses the same sight as you, but not the
   overview. A: accept that (recommended). B: give the computer a matching handicap while its radar
   is dark (it only "looks" near its base). B is new AI rules for a screen effect.
