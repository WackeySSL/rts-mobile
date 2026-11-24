extends GdUnitTestSuite
## The strike keys of the AI-vs-AI report (plan row P571, ADR 0047 section 12): SmokeCount's
## eleven per-player keys on crafted worlds. The six rows of the Kestrel Flats scenario are given
## new owners, types, places and hp, and each step is made by hand: `before_step`, the changes the
## sim would make, the records it would write, and `after_step`. Nothing here runs the sim, so the
## suite pins what the counter reads (the hp before the step, the STRIKE and DIED records, the
## rows' `offline_until` and `fog_cell`, the fog counts) and not the rules of the strike, which
## land in P572 to P574 (the overload is P572's).

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const SmokeCount: GDScript = preload("res://tests/smoke/smoke_count.gd")
## Where the strike point is, in milli-tiles, and a place far outside every radius used here.
const DUMMIES: Array[String] = ["dummy", "dummy"]
const POINT: int = 10000
const FAR: int = 40000
## Rows, as `_put` gives them.
const FIRER: int = 0
const VICTIM_A: int = 1
const VICTIM_B: int = 2
const VICTIM_UNIT: int = 3
const OWN: int = 4
const NEUTRAL: int = 5

var _world: World
var _wp: int = 0
var _fossil_strike: int = -1
var _renew_strike: int = -1
var _building: int = -1
var _hq: int = -1
var _rifle: int = -1
var _fighter: int = -1


func before_test() -> void:
	_world = Smoke.world_of(1, Smoke.FLATS)
	_fossil_strike = _world.type_ids.find(&"fossil_strike")
	_renew_strike = _world.type_ids.find(&"renew_strike")
	_building = _world.type_ids.find(&"renew_hq")
	_hq = _world.type_ids.find(&"headquarters")
	_rifle = _world.type_ids.find(&"rifle_squad")
	_fighter = _world.type_ids.find(&"fossil_fighter")
	_wp = _world.type_strike_weapon[_fossil_strike]
	assert_int(_world.unit_count()).is_equal(6)


func test_a_match_with_no_strike_reads_zero_on_every_key() -> void:
	var record: Dictionary = Smoke.play(1, 120, "cross", DUMMIES)
	for player: Dictionary in record["players"]:
		for key: String in SmokeCount.STRIKE_KEYS:
			assert_bool(player.has(key)).is_true()
			assert_int(player[key]).is_equal(0)


func test_the_keys_are_the_eleven_of_the_adr_and_start_at_zero() -> void:
	(
		assert_array(SmokeCount.STRIKE_KEYS)
		. contains_exactly(
			[
				"strike_fires_rupture",
				"strike_fires_blackout",
				"strike_damage_enemy",
				"strike_damage_own",
				"strike_kills_buildings",
				"strike_kills_units",
				"strike_kills_own",
				"blackout_building_ticks",
				"sight_cut_building_ticks",
				"sight_cells_lost",
				"radar_dark_ticks",
			]
		)
	)
	var counts: Dictionary = SmokeCount.new(2).player_counts(_world, 1)
	for key: String in SmokeCount.STRIKE_KEYS:
		assert_int(counts[key]).is_equal(0)


## A rupture of 600 against the building class: fires, damage and kills by the side of the row.
func test_a_rupture_counts_damage_and_kills_by_side_and_kind() -> void:
	_put(FIRER, 1, _fossil_strike, FAR, FAR, 900)
	_put(VICTIM_A, 2, _building, POINT, POINT, 500)  # 600 takes 500 and kills.
	_put(VICTIM_B, 2, _building, POINT + 2000, POINT, 700)  # 600 of 700, lives.
	_put(VICTIM_UNIT, 2, _rifle, POINT, POINT + 3000, 100)  # On the radius: 100 and a unit kill.
	_put(OWN, 1, _building, POINT - 1000, POINT, 300)  # Own, 300 and an own kill.
	_put(NEUTRAL, 0, _building, POINT, POINT - 2000, 1000)  # Neutral: 600, lives.
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	var radius: int = _world.type_strike_radius[_fossil_strike]
	assert_int(radius).is_equal(3000)
	_world.tick = 10
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.RUPTURE, 1, 12
			)
		]
	)
	assert_int(counter.strike[1]["strike_fires_rupture"]).is_equal(1)
	assert_int(counter.strike[1]["strike_damage_enemy"]).is_equal(0)  # It lands at tick 12.
	_world.tick = 11
	_step(
		counter,
		[],
		[
			_record(World.Event.DIED, _world.unit_id[VICTIM_A], 0, 0, _building, 2),
			_record(World.Event.DIED, _world.unit_id[VICTIM_UNIT], 0, 0, _rifle, 2),
			_record(World.Event.DIED, _world.unit_id[OWN], 0, 0, _building, 1),
		]
	)
	var mine: Dictionary = counter.strike[1]
	assert_int(mine["strike_damage_enemy"]).is_equal(500 + 600 + 100 + 600)
	assert_int(mine["strike_damage_own"]).is_equal(300)
	assert_int(mine["strike_kills_buildings"]).is_equal(1)
	assert_int(mine["strike_kills_units"]).is_equal(1)
	assert_int(mine["strike_kills_own"]).is_equal(1)
	assert_int(mine["strike_fires_blackout"]).is_equal(0)
	for key: String in SmokeCount.STRIKE_KEYS:
		assert_int(counter.strike[2][key]).is_equal(0)
	# A second landing of the same strike is not read again.
	_world.tick = 12
	_step(counter, [], [])
	assert_int(counter.strike[1]["strike_damage_enemy"]).is_equal(1800)


## The rupture's rules that the harness copies: the layer, a percent of 0, at least 1, a row that
## stands outside the radius or has no hp left, and a death that is a cancelled site.
func test_a_rupture_skips_air_zero_percent_and_rows_outside_and_floors_a_hit_at_one() -> void:
	_put(FIRER, 1, _fossil_strike, FAR, FAR, 900)
	_put(VICTIM_A, 2, _fighter, POINT, POINT, 50)  # Air: the weapon cannot hit it.
	_put(VICTIM_B, 2, _building, POINT, POINT, 5)  # Cancelled site: dies, no kill.
	_put(VICTIM_UNIT, 2, _rifle, POINT, POINT, 80)  # Infantry: percent 0 below.
	_put(OWN, 2, _building, POINT + 3001, POINT, 5)  # One milli past the radius.
	_put(NEUTRAL, 0, _building, POINT, POINT, 0)  # No hp left: skipped.
	_world.weapon_damage[_wp] = 1
	_world.weapon_vs_armour[_wp * World.Armour.size() + World.Armour.BUILDING] = 40
	_world.weapon_vs_armour[_wp * World.Armour.size() + World.Armour.INFANTRY] = 0
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	_world.tick = 20
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.RUPTURE, 1, 21
			)
		]
	)
	_world.tick = 20
	# The cancel flag is the 7th int of a DIED record, `Production.DIED_CANCEL_FLAG_AT`.
	var cancelled: PackedInt32Array = _record(
		World.Event.DIED, _world.unit_id[VICTIM_B], 0, 0, _building, 2
	)
	cancelled[Production.DIED_CANCEL_FLAG_AT] = 1
	_step(counter, [], [cancelled])
	var mine: Dictionary = counter.strike[1]
	# 1 * 40 / 100 is 0, floored to 1: the site (5 hp) takes 1; nothing else is hit.
	assert_int(mine["strike_damage_enemy"]).is_equal(1)
	assert_int(mine["strike_kills_buildings"]).is_equal(0)
	assert_int(mine["strike_kills_units"]).is_equal(0)
	assert_int(mine["strike_damage_own"]).is_equal(0)


## A hit that equals the hp is a kill, one below is not; `Upgrades.taken` scales the hit.
func test_a_hit_at_the_hp_kills_and_the_taken_percent_is_applied() -> void:
	_put(FIRER, 1, _fossil_strike, FAR, FAR, 900)
	_put(VICTIM_A, 2, _building, POINT, POINT, 600)  # hit 600 at 100 percent: kills.
	_put(VICTIM_B, 2, _hq, POINT, POINT, 700)  # taken 150 percent: hit 900 of 700, kills.
	_put(VICTIM_UNIT, 2, _rifle, POINT, POINT, 601)  # Not killed, so no kill even if it dies.
	var stride: int = _world.type_ids.size()
	_world.mod_taken.resize(3 * stride)
	_world.mod_taken.fill(100)
	_world.mod_taken[2 * stride + _hq] = 150
	_world.tick = 30
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.RUPTURE, 1, 32
			)
		]
	)
	_step(
		counter,
		[],
		[
			_record(World.Event.DIED, _world.unit_id[VICTIM_A], 0, 0, _building, 2),
			_record(World.Event.DIED, _world.unit_id[VICTIM_B], 0, 0, _hq, 2),
			_record(World.Event.DIED, _world.unit_id[VICTIM_UNIT], 0, 0, _rifle, 2),
		]
	)
	var mine: Dictionary = counter.strike[1]
	assert_int(mine["strike_kills_buildings"]).is_equal(2)
	assert_int(mine["strike_kills_units"]).is_equal(0)
	assert_int(mine["strike_damage_enemy"]).is_equal(600 + 700 + 600)


## The blackout's overload: building rows of other owners in the radius, from the weapon of the
## firing type, with units, own rows and rows with no hp untouched. The test world's Renew strike is
## given the rupture's weapon at 200 here.
func test_a_blackout_counts_the_overload_on_buildings_of_others() -> void:
	_world.type_strike_weapon[_renew_strike] = _wp
	_world.weapon_damage[_wp] = 200
	_put(FIRER, 1, _renew_strike, FAR, FAR, 900)
	_put(VICTIM_A, 2, _building, POINT, POINT, 150)  # 200: takes 150, dies.
	_put(VICTIM_B, 2, _building, POINT + 3999, POINT, 500)  # Inside 4000: 200.
	_put(VICTIM_UNIT, 2, _rifle, POINT, POINT, 100)  # Units are not building rows.
	_put(OWN, 1, _building, POINT, POINT, 100)  # The firer's own: untouched.
	_put(NEUTRAL, 0, _building, POINT, POINT + 1000, 1000)  # Neutral: 200.
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	_world.tick = 40
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.BLACKOUT, 1, 0
			),
			_record(World.Event.DIED, _world.unit_id[VICTIM_A], 0, 0, _building, 2),
		]
	)
	var mine: Dictionary = counter.strike[1]
	assert_int(mine["strike_fires_blackout"]).is_equal(1)
	assert_int(mine["strike_fires_rupture"]).is_equal(0)
	assert_int(mine["strike_damage_enemy"]).is_equal(150 + 200 + 200)
	assert_int(mine["strike_damage_own"]).is_equal(0)
	assert_int(mine["strike_kills_buildings"]).is_equal(1)
	assert_int(mine["strike_kills_units"]).is_equal(0)
	assert_int(mine["strike_kills_own"]).is_equal(0)


## A Dusk Array with no weapon (-1, the frozen arena's): a blackout fires and does no damage.
func test_a_blackout_with_no_weapon_does_no_damage() -> void:
	_world.type_strike_weapon[_renew_strike] = -1
	_put(FIRER, 1, _renew_strike, FAR, FAR, 900)
	_put(VICTIM_A, 2, _building, POINT, POINT, 10)
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	_world.tick = 40
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.BLACKOUT, 1, 0
			),
			_record(World.Event.DIED, _world.unit_id[VICTIM_A], 0, 0, _building, 2),
		]
	)
	assert_int(counter.strike[1]["strike_fires_blackout"]).is_equal(1)
	assert_int(counter.strike[1]["strike_damage_enemy"]).is_equal(0)
	assert_int(counter.strike[1]["strike_kills_buildings"]).is_equal(0)


## A sweep is no fire.
func test_a_sweep_is_no_fire() -> void:
	_put(FIRER, 1, _fossil_strike, FAR, FAR, 900)
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	_world.tick = 5
	_step(counter, [], [_record(World.Event.STRIKE, 99, 0, 0, Strike.Kind.REVEAL, 1, 0)])
	for key: String in SmokeCount.STRIKE_KEYS:
		assert_int(counter.strike[1][key]).is_equal(0)


## Own complete buildings that are offline, per step, while `offline_until` is above the stamp; a
## site, an online building, a unit and the other player's rows do not count.
func test_blackout_building_ticks_count_complete_offline_buildings_per_step() -> void:
	_put(VICTIM_A, 2, _building, POINT, POINT, 500)
	_put(VICTIM_B, 2, _building, POINT, POINT, 500)
	_put(VICTIM_UNIT, 2, _rifle, POINT, POINT, 500)
	_put(OWN, 2, _building, POINT, POINT, 500)  # A site: build_left above 0.
	_put(NEUTRAL, 1, _building, POINT, POINT, 500)  # The firer's building, online.
	_world.build_left[OWN] = 4
	for row: int in [VICTIM_A, VICTIM_B, VICTIM_UNIT, OWN]:
		_world.offline_until[row] = 20
	_world.offline_until[VICTIM_B] = 18
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	# Stamps 1 to 17: both buildings; 18 and 19: B is back (offline_until is not above the stamp);
	# 20: none.
	for tick: int in range(1, 22):
		_world.tick = tick
		counter.after_step(_world)
	assert_int(counter.strike[2]["blackout_building_ticks"]).is_equal(17 * 2 + 2)
	assert_int(counter.strike[1]["blackout_building_ticks"]).is_equal(0)
	assert_int(counter.strike[2]["radar_dark_ticks"]).is_equal(0)


## The window is opened by a blackout's STRIKE record too, so a World that starts with nothing
## offline still counts what the blackout makes offline.
func test_a_blackout_fired_during_the_run_opens_the_counting() -> void:
	_put(FIRER, 1, _renew_strike, FAR, FAR, 900)
	_put(VICTIM_A, 2, _building, POINT, POINT, 500)
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	var length: int = _world.type_strike_ticks[_renew_strike]
	_world.tick = 9
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.BLACKOUT, 1, 0
			)
		],
		func() -> void: _world.offline_until[VICTIM_A] = 10 + length
	)
	assert_int(counter.strike[2]["blackout_building_ticks"]).is_equal(1)
	for tick: int in range(11, 10 + length + 3):
		_world.tick = tick
		counter.after_step(_world)
	# Stamps 10 to 10 + length - 1 are offline: `length` steps.
	assert_int(counter.strike[2]["blackout_building_ticks"]).is_equal(length)


## Own buildings with `fog_cell` -1 while offline: the cut, from the rows' own column.
func test_sight_cut_building_ticks_count_offline_buildings_with_no_disc() -> void:
	_put(VICTIM_A, 2, _building, POINT, POINT, 500)
	_put(VICTIM_B, 2, _building, POINT, POINT, 500)
	_put(OWN, 2, _building, POINT, POINT, 500)  # Online with no disc: not a cut.
	_world.offline_until[VICTIM_A] = 6
	_world.offline_until[VICTIM_B] = 6
	_world.fog_cell[VICTIM_A] = -1
	_world.fog_cell[VICTIM_B] = 12
	_world.fog_cell[OWN] = -1
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	for tick: int in range(1, 9):
		_world.tick = tick
		if tick == 4:  # The disc of B goes in the victim's next fog turn.
			_world.fog_cell[VICTIM_B] = -1
		counter.after_step(_world)
	# A: stamps 1 to 5 (5), B: stamps 4 and 5 (2).
	assert_int(counter.strike[2]["sight_cut_building_ticks"]).is_equal(5 + 2)
	assert_int(counter.strike[2]["blackout_building_ticks"]).is_equal(5 + 5)
	assert_int(counter.strike[1]["sight_cut_building_ticks"]).is_equal(0)


## Cells visible before the strike and not visible after the victim's first fog turn at or after
## it. Player 2's turns are the steps that start at a tick with (tick - 1) % 3 == 0.
func test_sight_cells_lost_wait_for_the_victims_first_fog_turn() -> void:
	_put(FIRER, 1, _renew_strike, FAR, FAR, 900)
	var cells: int = _world.fog.cells
	for cell: int in 10:
		_world.fog.visible[cells + cell] = 1  # Player 2's block: cells 0 to 9 seen.
		_world.fog.visible[cell] = 1  # Player 1's block.
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	# The step that starts at tick 3 is not player 2's turn (its turns start at 1, 4, 7, ...).
	_world.tick = 3
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.BLACKOUT, 1, 0
			)
		],
		func() -> void:
			_world.fog.visible[cells + 0] = 0  # Seen change that is not the victim's turn.
			_world.fog.visible[0] = 0
	)
	assert_int(counter.strike[2]["sight_cells_lost"]).is_equal(0)
	# The step that starts at tick 4 is: cells 1 and 2 drop out, cell 20 comes in.
	_step(
		counter,
		[],
		[],
		func() -> void:
			_world.fog.visible[cells + 1] = 0
			_world.fog.visible[cells + 2] = 0
			_world.fog.visible[cells + 20] = 3
	)
	# Cells 0, 1 and 2 were visible before the strike and are not now; cell 20 is new.
	assert_int(counter.strike[2]["sight_cells_lost"]).is_equal(3)
	assert_int(counter.strike[1]["sight_cells_lost"]).is_equal(0)
	# Settled once: a later turn with more cells gone does not add to it.
	_step(counter, [], [], func() -> void: _world.fog.visible[cells + 5] = 0)
	_step(counter, [], [], func() -> void: _world.fog.visible[cells + 6] = 0)
	_step(counter, [], [], func() -> void: _world.fog.visible[cells + 7] = 0)
	assert_int(counter.strike[2]["sight_cells_lost"]).is_equal(3)


## A fire in the step that is the victim's own fog turn settles in that step.
func test_sight_cells_lost_count_in_the_strike_step_when_it_is_the_victims_turn() -> void:
	_put(FIRER, 1, _renew_strike, FAR, FAR, 900)
	var cells: int = _world.fog.cells
	for cell: int in 10:
		_world.fog.visible[cells + cell] = 2
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	_world.tick = 4
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.BLACKOUT, 1, 0
			)
		],
		func() -> void:
			for cell: int in 4:
				_world.fog.visible[cells + cell] = 0
	)
	assert_int(counter.strike[2]["sight_cells_lost"]).is_equal(4)


## A rupture's cells are read at its landing, not at its fire.
func test_sight_cells_lost_of_a_rupture_are_read_from_the_landing_step() -> void:
	_put(FIRER, 1, _fossil_strike, FAR, FAR, 900)
	var cells: int = _world.fog.cells
	for cell: int in 10:
		_world.fog.visible[cells + cell] = 1
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	_world.tick = 5
	_step(
		counter,
		[Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)],
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.RUPTURE, 1, 8
			)
		],
		func() -> void: _world.fog.visible[cells + 9] = 0
	)
	assert_int(counter.strike[2]["sight_cells_lost"]).is_equal(0)
	_world.tick = 7  # The landing step starts at tick 7 (stamp 8) and is player 2's turn.
	_step(counter, [], [], func() -> void: _world.fog.visible[cells + 8] = 0)
	assert_int(counter.strike[2]["sight_cells_lost"]).is_equal(1)  # Cell 9 went before it.


## Until P574 there is no `type_radar`: offline buildings never darken a radar.
func test_radar_dark_ticks_read_zero_while_the_world_has_no_radar_table() -> void:
	_put(VICTIM_A, 2, _building, POINT, POINT, 500)
	_world.offline_until[VICTIM_A] = 10
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	for tick: int in range(1, 6):
		_world.tick = tick
		counter.after_step(_world)
	assert_int(counter.strike[2]["blackout_building_ticks"]).is_equal(5)
	assert_int(counter.strike[2]["radar_dark_ticks"]).is_equal(0)


## The rule of ADR 0047 section 3 from a radar table (the one P574 adds to the World): dark when a
## complete radar is offline and no complete radar is online.
func test_radar_dark_ticks_follow_the_rule_once_the_world_has_a_radar_table() -> void:
	_put(VICTIM_A, 2, _hq, POINT, POINT, 500)  # Radar, offline until 10.
	_put(VICTIM_B, 2, _hq, POINT, POINT, 500)  # Radar, becomes online later.
	_put(OWN, 2, _rifle, POINT, POINT, 500)  # Not a radar.
	_world.offline_until[VICTIM_A] = 10
	_world.offline_until[VICTIM_B] = 6
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	var flags: PackedInt32Array = PackedInt32Array()
	flags.resize(_world.type_ids.size())
	flags[_hq] = 1
	counter.radar_flags = flags
	# Stamps 1 to 5: both radars offline: dark. 6 to 9: B is back online: not dark. 10: A back.
	for tick: int in range(1, 12):
		_world.tick = tick
		counter.after_step(_world)
	assert_int(counter.strike[2]["radar_dark_ticks"]).is_equal(5)
	assert_int(counter.strike[1]["radar_dark_ticks"]).is_equal(0)
	# A radar that is still a site is no radar: the lone complete one, offline, is dark.
	_world.build_left[VICTIM_B] = 3
	_world.offline_until[VICTIM_B] = 0
	_world.offline_until[VICTIM_A] = 100
	var again: SmokeCount = SmokeCount.new(2)
	again.start(_world)
	again.radar_flags = counter.radar_flags
	_world.tick = 20
	again.after_step(_world)
	assert_int(again.strike[2]["radar_dark_ticks"]).is_equal(1)


func test_the_counting_reads_the_world_and_changes_nothing_in_it() -> void:
	_put(FIRER, 1, _fossil_strike, FAR, FAR, 900)
	_put(VICTIM_A, 2, _building, POINT, POINT, 500)
	var counter: SmokeCount = SmokeCount.new(2)
	counter.start(_world)
	_world.tick = 10
	var before: String = World.hash_hex(_world.state_hash())
	counter.before_step(_world, [Command.superweapon(1, _world.unit_id[FIRER], POINT, POINT)])
	_world.events = _events(
		[
			_record(
				World.Event.STRIKE, _world.unit_id[FIRER], POINT, POINT, Strike.Kind.RUPTURE, 1, 11
			)
		]
	)
	_world.tick = 11
	counter.after_step(_world)
	_world.tick = 10
	assert_str(World.hash_hex(_world.state_hash())).is_equal(before)


## Gives `row` an owner, a type, a place and hp (and no pending work or offline time).
func _put(row: int, owner: int, type: int, x: int, y: int, hit_points: int) -> void:
	_world.owner[row] = owner
	_world.type_index[row] = type
	_world.pos_x[row] = x
	_world.pos_y[row] = y
	_world.hp[row] = hit_points
	_world.build_left[row] = 0
	_world.offline_until[row] = 0


## One step by hand: the counter reads the World before it, `change` is what the sim would do to
## it (the records it writes are `records`), and the tick moves on by one.
func _step(
	counter: SmokeCount,
	commands: Array[Command],
	records: Array[PackedInt32Array],
	change: Callable = Callable()
) -> void:
	counter.before_step(_world, commands)
	if change.is_valid():
		change.call()
	_world.events = _events(records)
	_world.tick += 1
	counter.after_step(_world)


func _record(
	kind: int, a: int = 0, b: int = 0, c: int = 0, d: int = 0, e: int = 0, f: int = 0, g: int = 0
) -> PackedInt32Array:
	return PackedInt32Array([kind, a, b, c, d, e, f, g])


func _events(records: Array[PackedInt32Array]) -> PackedInt32Array:
	var events: PackedInt32Array = PackedInt32Array()
	for entry: PackedInt32Array in records:
		events.append_array(entry)
	return events
