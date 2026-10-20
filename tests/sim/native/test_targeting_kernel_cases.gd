extends GdUnitTestSuite
## The TARGETING kernel on crafted states (ADR 0013 section 4, plan P41n): the cases that C++ can
## get wrong where GDScript cannot. Exact-distance ties between candidates (the tie that the
## spike's 900 ticks never reached): equal percent and equal squared distance go to the lowest row
## wherever it stands in the grid's visiting order, a nearer or a better candidate wins whatever its
## id, and the ends of the range test are inclusive. The whole engagement pass as a table of states:
## every order, navigation mode, distance class (gone, inside the minimum range, in range, at the
## edges of the weapon range and of the acquire range, beyond them), line (clear, or blocked for
## one, two or all three movement classes) and checked-line value, on and off the unit's line-check
## turn, one subject per state. The order column mixed with targets that are gone, friends,
## neutrals and the unit itself. And seeded random states stepped for six calls. Every case runs on
## two identical Worlds, one with the GDScript phase and one with the kernel, and compares the
## whole state (StateDiff); the values the rule gives are asserted where the case pins one. The
## module's own cases (test_targeting*.gd, test_engagement*.gd) run under both implementations too;
## the 900-tick lockstep is P41n2.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const GridWorld: GDScript = preload("res://tests/sim/support/grid_world.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const TARGETING: int = SimProbe.Phase.TARGETING
const RIFLE: int = 0
const ROCKET: int = 1
const TANK: int = 2
const IDLE: int = World.Order.IDLE
const ATTACK_MOVE: int = World.Order.ATTACK_MOVE
const MOVE: int = World.Order.MOVE
const ATTACK: int = World.Order.ATTACK
const NONE: int = World.NavMode.NONE
const DIRECT: int = World.NavMode.DIRECT
const FIELD: int = World.NavMode.FIELD
const HOLD: int = World.NavMode.HOLD
const CHASE: int = World.NavMode.CHASE
## A `retarget_period_ticks` that no tick of a test reaches: nobody scans.
const NEVER_DUE: int = 1000000
## The subject of the tie cases stands here (the rifle squad: weapon range 4000, acquire 5000), and
## the offsets from it at a distance of exactly 5000: eight with integer legs (3-4-5 and 5-0).
const AT: Vector2i = Vector2i(10000, 6000)
const FIVE_THOUSAND: Array[Vector2i] = [
	Vector2i(3000, 4000),
	Vector2i(4000, 3000),
	Vector2i(5000, 0),
	Vector2i(0, 5000),
	Vector2i(-3000, 4000),
	Vector2i(-4000, -3000),
	Vector2i(-5000, 0),
	Vector2i(3000, -4000)
]
## The engagement table: its weapon (range 4000, minimum range 1000), the acquire range, and the
## distances of its classes; its lanes (one tile row each), the subject's x and the wall column.
const RANGE: int = 4000
const MIN_RANGE: int = 1000
const ACQUIRE: int = 5000
const GAPS: Array[int] = [0, 3000, 4000, 4001, 5000, 5001, 999, 1000]
const SUBJECT_X: int = 5500
const WALL: int = 6
const MAP_COLUMNS: int = 12
const LANES: int = 120
## Terrain of the wall tile in each lane variant: grass (a clear line), rock (blocked for every
## class), 'w' (blocked for tracked units only) and 't' (blocked for wheeled units only).
const WALLS: Array[int] = [0, 2, 3, 4]


## Candidates at exactly the same distance (5000, the acquire range, inclusive) and the same
## percent: the lowest id wins whichever of the four standing places it has. The four places are
## taken from the eight in every order (all 24 permutations of five different quadruples), so the
## lowest id stands in each cell the grid visits first, last and in the middle, and a later
## candidate that ties never wins. The unit is attack-moving and due.
func test_exact_distance_ties_go_to_the_lowest_row_wherever_it_stands() -> void:
	var quadruples: Array[Array] = [
		[0, 1, 2, 3], [4, 5, 6, 7], [0, 2, 4, 6], [1, 3, 5, 7], [0, 3, 5, 6]
	]
	var checked: int = 0
	for places: Array in quadruples:
		for order: Array in _permutations(places):
			var pair: Array[World] = _pair(_tie_world.bind(order))
			for world: World in pair:
				Rig.acquire(world)
				var label: String = "places %s, native %s" % [order, world.native_phases != 0]
				assert_int(world.target[0]).override_failure_message(label).is_equal(2)
				assert_int(world.stats[World.Stat.TARGET_CANDIDATES]).is_equal(4)
			assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
			checked += 1
	assert_int(checked).is_equal(5 * 24)


## A tie needs both the percent and the squared distance: a candidate one milli nearer wins with a
## higher id, a candidate a milli farther loses with a lower one, and a better percent wins from
## farther away. A rocket squad (20% against infantry, 100% against light armour) at AT,
## attack-moving (acquire range 5500), with rifle squads (infantry) and tanks (light) around it,
## the ids from 2 in the order listed.
func test_a_nearer_or_better_candidate_wins_whatever_its_id() -> void:
	# [[type, dx, dy] of each enemy in id order, the winner's id]
	var cases: Array[Array] = [
		[[[RIFLE, 5000, 0], [RIFLE, 4999, 0]], 3],
		[[[RIFLE, 4999, 0], [RIFLE, 5000, 0]], 2],
		[[[RIFLE, 5000, 0], [RIFLE, 0, 5000], [RIFLE, 0, -4999]], 4],
		[[[RIFLE, 4000, 0], [TANK, 5500, 0]], 3],
		[[[TANK, 5500, 0], [RIFLE, 4000, 0]], 2],
		[[[TANK, 0, 5500], [TANK, 0, -5000], [RIFLE, 1000, 0]], 3],
		[[[TANK, 5500, 0], [TANK, 0, 5500]], 2],
	]
	for item: Array in cases:
		var pair: Array[World] = _pair(_percent_world.bind(item[0]))
		for world: World in pair:
			Rig.acquire(world)
			var label: String = "%s, native %s" % [item[0], world.native_phases != 0]
			assert_int(world.target[0]).override_failure_message(label).is_equal(item[1])
		assert_str(StateDiff.first(pair[0], pair[1])).override_failure_message(str(item)).is_empty()


## The range test is inclusive at both ends and nowhere else, for the candidate and for the
## target that is kept: an enemy at exactly the reach (5000, attack-moving) and at exactly the
## minimum range (a gun with 2000) is a candidate, one milli beyond or inside is not. The scan and
## the keep check both: the unit starts with no target, then with the same one held.
func test_the_ends_of_the_range_are_inclusive_for_the_candidate_and_the_kept_target() -> void:
	var gun: UnitDef = Rig.unit(&"gun", 9000, 5000, 4000, 2000, [100, 100, 100, 100])
	# [distance of the enemy along x, whether it is in reach]
	var cases: Array[Array] = [
		[5000, true], [5001, false], [2000, true], [1999, false], [3500, true], [4999, true]
	]
	for item: Array in cases:
		for held: bool in [false, true]:
			var pair: Array[World] = _pair(_gun_world.bind(gun, item[0], held))
			for world: World in pair:
				Rig.acquire(world)
				var label: String = (
					"%d, held %s, native %s" % [item[0], held, world.native_phases != 0]
				)
				var found: bool = world.target[0] == 2
				assert_bool(found).override_failure_message(label).is_equal(item[1])
			assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## The whole engagement pass as a table: one subject and one target per state, 8 distance classes
## (gone, 3000, 4000, 4001, 5000, 5001, 999 and 1000 away, the weapon's range 4000, minimum range
## 1000 and the acquire range 5000), 4 orders, 5 navigation modes, a checked line or not, and 4
## kinds of wall in the lane (none, rock, and the two test terrains) against the three movement
## classes. The ticks 0 to 4 put each subject on its line-check turn once. Not vacuous: every mode
## and every outcome of the pass occurs, and so does a line test that finds the line blocked.
func test_every_state_of_the_engagement_pass_ends_as_the_twin_ends() -> void:
	var states: Array[Array] = []
	for order: int in [IDLE, ATTACK_MOVE, MOVE, ATTACK]:
		for mode: int in [NONE, DIRECT, FIELD, HOLD, CHASE]:
			for gap: int in GAPS:
				for wall: int in WALLS:
					for checked: int in [-1, 5]:
						states.append([order, mode, gap, wall, checked])
	assert_int(states.size()).is_equal(4 * 5 * 8 * 4 * 2)
	var modes: Dictionary[int, int] = {}
	var changed: int = 0
	var checks: int = 0
	for start: int in range(0, states.size(), LANES):
		var chunk: Array = states.slice(start, start + LANES)
		for tick: int in 5:
			var pair: Array[World] = _pair(_table_world.bind(chunk, tick))
			for world: World in pair:
				Rig.acquire(world)
			var found: String = StateDiff.first(pair[0], pair[1])
			(
				assert_str(found)
				. override_failure_message("states from %d, tick %d" % [start, tick])
				. is_empty()
			)
			var world: World = pair[1]
			for lane: int in chunk.size():
				modes[world.nav_mode[2 * lane]] = modes.get(world.nav_mode[2 * lane], 0) + 1
				changed += 1 if world.nav_cell[2 * lane] != chunk[lane][4] else 0
			checks += world.stats[World.Stat.LINE_CHECKS]
	for mode: int in [NONE, DIRECT, HOLD, CHASE, FIELD]:
		assert_int(modes.get(mode, 0)).override_failure_message("mode %d" % mode).is_greater(100)
	assert_int(changed).is_greater(500)
	assert_int(checks).is_greater(100)


## Order targets and targets that name a row that is not one: a unit that is gone (an id between
## two others, past the last row, 0, negative), a friend, a neutral unit, the unit itself, and the
## ends of the int32 range. An ATTACK row locks an enemy and falls back to an attack-move at the
## target's last place for anything else; an attack-moving or idle row drops what it holds unless
## it is a valid enemy in reach, and a MOVE row drops all of it. One row of each order for each
## reference, every unit due on every tick.
func test_targets_that_are_not_valid_enemies_are_dropped_or_fall_back() -> void:
	var references: Array[int] = [0, 1, 2, 3, 4, 7, 99, 2147483647, -1, -2147483648]
	var pair: Array[World] = _pair(_reference_world.bind(references))
	var attackers: Array[int] = []
	for row: int in pair[0].unit_count():
		if pair[0].order[row] == ATTACK:
			attackers.append(row)
	for world: World in pair:
		Rig.acquire(world)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
	# Not vacuous: the ATTACK rows split into those that kept the lock and those that fell back.
	var locked: int = 0
	var fell: int = 0
	for row: int in attackers:
		locked += 1 if pair[1].order[row] == ATTACK else 0
		fell += 1 if pair[1].order[row] == ATTACK_MOVE else 0
	assert_int(locked).is_greater(0)
	assert_int(fell).is_greater(locked)
	assert_int(locked + fell).is_equal(attackers.size())


## A type with no weapon (a weapon index of -1) and a type that names a weapon the tables lack are
## unarmed: a row of one leaves its target and its navigation mode alone, whatever it holds, in
## acquisition and in engagement (a stale target on such a row stays, and nothing chases or holds),
## while an ATTACK row still locks its target. The tables read 0 outside their window in C++, so
## a pass that treated the two as armed would clear the target (no candidate) or chase (a reach of
## 0 never holds), which is not what the twin does. 108 rows: 3 types, 3 orders, 4 held targets
## (none, one in weapon range, one beyond it inside the acquire range, one that is gone) and 3
## modes, with an armed type for contrast.
func test_unarmed_types_leave_the_target_and_the_mode_of_their_rows_alone() -> void:
	var pair: Array[World] = _pair(_unarmed_world)
	var before: Array[Vector3i] = []  # target, mode, order
	for row: int in pair[0].unit_count():
		before.append(Vector3i(pair[0].target[row], pair[0].nav_mode[row], pair[0].order[row]))
	for world: World in pair:
		Rig.acquire(world)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()
	var world: World = pair[1]
	var kept: int = 0
	var moved: int = 0
	for row: int in world.unit_count():
		var held: Vector3i = before[row]
		var label: String = "row %d" % row
		if world.type_index[row] == RIFLE:
			moved += (
				1
				if Vector2i(held.x, held.y) != Vector2i(world.target[row], world.nav_mode[row])
				else 0
			)
		elif held.z != ATTACK:
			assert_int(world.target[row]).override_failure_message(label).is_equal(held.x)
			# A mode is left alone while the row holds a target that exists; with none (or one that
			# is gone) engagement takes a unit out of HOLD and CHASE whatever its weapon.
			if held.x == 1 or held.x == 2:
				assert_int(world.nav_mode[row]).override_failure_message(label).is_equal(held.y)
				kept += 1
	assert_int(kept).is_greater(20)
	assert_int(moved).is_greater(10)


## A World with no map has clear lines (line_clear is true while no map is loaded): an
## attack-moving unit with a target out of weapon range and inside its acquire range chases it.
func test_a_world_with_no_map_has_clear_lines() -> void:
	var pair: Array[World] = _pair(_mapless_world)
	for world: World in pair:
		Rig.acquire(world)
		var label: String = "native %s" % (world.native_phases != 0)
		assert_int(world.map_cols).override_failure_message(label).is_equal(0)
		assert_int(world.nav_mode[0]).override_failure_message(label).is_equal(CHASE)
		assert_int(world.stats[World.Stat.LINE_CHECKS]).override_failure_message(label).is_equal(1)
	assert_str(StateDiff.first(pair[0], pair[1])).is_empty()


## Seeded random Worlds, six calls each: 100 units of the three shipped types (some off the map)
## with random owners, orders, navigation modes, targets (valid, gone or itself), order targets,
## goals and navigation columns, a random tick and random cadences, on a map with random rock, and
## in one World of four a type that is unarmed. After every call the units walk a few steps, one
## dies now and then (its id is gone, the rows close up) and the grid is rebuilt, as the tick does.
## The twin and the kernel end every call in the same state, and the work counts are not zero.
func test_random_states_stepped_for_six_calls_agree_with_the_twin() -> void:
	var rng: DetRandom = DetRandom.create(41, 2)
	var looked: int = 0
	var checked: int = 0
	for _world: int in 24:
		var pair: Array[World] = _pair(_random_world.bind(rng.next_u32()))
		var walk: DetRandom = DetRandom.create(rng.next_u32(), 3)
		for call: int in 6:
			for world: World in pair:
				Rig.acquire(world)
			var found: String = StateDiff.first(pair[0], pair[1])
			assert_str(found).override_failure_message("call %d: %s" % [call, found]).is_empty()
			var steps: Array[int] = []
			for _row: int in pair[0].unit_count():
				steps.append(walk.next_int(1201) - 600)
				steps.append(walk.next_int(1201) - 600)
			var dies: int = walk.next_int(pair[0].unit_count() * 2)
			for world: World in pair:
				_walk(world, steps, dies)
		# The counts add up over the six calls.
		looked += pair[1].stats[World.Stat.TARGET_CANDIDATES]
		checked += pair[1].stats[World.Stat.LINE_CHECKS]
	assert_int(looked).is_greater(10000)
	assert_int(checked).is_greater(100)


## Moves every unit by its two steps, kills row `dies` (if there is one) and removes the dead, and
## advances the tick by one.
func _walk(world: World, steps: Array[int], dies: int) -> void:
	for row: int in world.unit_count():
		world.pos_x[row] = clampi(world.pos_x[row] + steps[2 * row], -3000, 25000)
		world.pos_y[row] = clampi(world.pos_y[row] + steps[2 * row + 1], -3000, 15000)
	if dies < world.unit_count():
		world.hp[dies] = 0
	world.remove_dead()
	world.tick += 1


## Two Worlds from the same builder, the first running the GDScript phase and the second the kernel.
func _pair(build: Callable) -> Array[World]:
	var pair: Array[World] = []
	for impl: int in SimImpls.IMPLS:
		var world: World = build.call()
		assert_array(SimImpls.attach(world, impl, TARGETING)).is_empty()
		pair.append(world)
	return pair


## The rifle squad (id 1, attack-moving, due at tick 0 with period 5: (0 + 5) % 5 = 0 for id 5, so
## the tick is moved to make id 1 due) at AT, and four tied enemies (ids 2 to 5, owner 2, rifle
## squads) at the offsets `FIVE_THOUSAND[order[k]]`.
func _tie_world(order: Array) -> World:
	var world: World = Rig.data_world(30, 16)
	world.add_unit(1, RIFLE, AT.x, AT.y)
	world.order[0] = ATTACK_MOVE
	for place: int in order:
		var at: Vector2i = AT + FIVE_THOUSAND[place]
		world.add_unit(2, RIFLE, at.x, at.y)
	world.tick = Rig.due_tick_for(world, 1)
	return world


## A rocket squad (id 1) attack-moving at AT with the units of `stand` around it: [type, dx, dy],
## owner 2, ids 2 and up.
func _percent_world(stand: Array) -> World:
	var world: World = Rig.data_world(30, 16)
	world.add_unit(1, ROCKET, AT.x, AT.y)
	world.order[0] = ATTACK_MOVE
	for item: Array in stand:
		world.add_unit(2, int(item[0]), AT.x + int(item[1]), AT.y + int(item[2]))
	world.tick = Rig.due_tick_for(world, 1)
	return world


## A gun (type 0: range 4000, minimum range 2000, acquire range 5000) attack-moving at AT with an
## enemy `gap` east of it, which it holds by hand with `held`.
func _gun_world(gun: UnitDef, gap: int, held: bool) -> World:
	var world: World = Rig.world_of([gun], 30, 16)
	world.add_unit(1, 0, AT.x, AT.y)
	world.add_unit(2, 0, AT.x + gap, AT.y)
	world.order[0] = ATTACK_MOVE
	world.target[0] = 2 if held else 0
	world.tick = Rig.due_tick_for(world, 1)
	return world


## The map of the engagement table: MAP_COLUMNS x LANES tiles, three gun types that differ in
## their movement class (foot, wheeled, tracked), and a pair of rows for each of the `chunk`
## states [order, mode, gap, wall, checked]: the subject at (SUBJECT_X, the middle of lane k) and
## its target `gap` to the east (gap 0: the target is a unit that is gone, id 99999). The wall
## tile of the lane, column WALL, has the terrain of the state. Nobody scans (the targets are set
## by hand), the line-check period is 5 and the World is at `tick`, so a subject is on its turn
## when `(tick + id) % 5 == 0`. The navigation columns hold values that a reset would change.
func _table_world(chunk: Array, tick: int) -> World:
	var units: Array[UnitDef] = []
	for move_class: int in 3:
		var name: StringName = StringName("table%d" % move_class)
		var def: UnitDef = Rig.unit(name, 9000, ACQUIRE, RANGE, MIN_RANGE, [100, 100, 100, 100])
		def.move_class = move_class
		units.append(def)
	var world: World = Rig.world_of(units, MAP_COLUMNS, LANES)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	world.retarget_period_ticks = NEVER_DUE
	for lane: int in chunk.size():
		var state: Array = chunk[lane]
		var y: int = lane * 1000 + 500
		if state[3] != 0:
			world.set_terrain(lane * MAP_COLUMNS + WALL, state[3])
		var row: int = world.unit_count()
		world.add_unit(1, lane % 3, SUBJECT_X, y)
		world.add_unit(2, lane % 3, SUBJECT_X + int(state[2]), y)
		var target_id: int = world.unit_id[row + 1] if state[2] != 0 else 99999
		world.order[row] = state[0]
		world.target[row] = target_id
		if state[0] == ATTACK:
			world.order_target[row] = target_id
		world.nav_mode[row] = state[1]
		world.nav_cell[row] = state[4]
		world.field[row] = 3
		world.nav_next[row] = 4
		world.best_dist[row] = 9
		world.stall[row] = 2
	world.tick = tick
	return world


## One enemy (id 2, owner 2), one friend (id 3), one neutral unit (id 4, owner 0) and, for each
## of `references`, an ATTACK row, an attack-moving row, an idle row and a MOVE row (all of
## player 1, in a line from 6000 east in steps of 10) whose order target and target are that
## reference; then the same four rows naming themselves. The first four units are within reach of
## each other. Every unit is due on every tick.
func _reference_world(references: Array[int]) -> World:
	var world: World = Rig.data_world(20, 12)
	world.add_unit(1, RIFLE, 6000, 6000)
	world.add_unit(2, RIFLE, 8000, 6000)
	world.add_unit(1, RIFLE, 6500, 6000)
	world.add_unit(0, RIFLE, 7000, 6000)
	var selves: Array[int] = [-3]
	for reference: int in references + selves:
		for order: int in [ATTACK, ATTACK_MOVE, IDLE, MOVE]:
			var row: int = world.unit_count()
			world.add_unit(1, RIFLE, 6000 + row * 10, 6000)
			var named: int = world.unit_id[row] if reference == -3 else reference
			world.order[row] = order
			world.order_target[row] = named
			world.target[row] = named
	world.retarget_period_ticks = 1
	world.tick = 0
	return world


## The World of the unarmed rows: the rifle squad (type 0, armed) and the rocket squad (type 1, no
## weapon) and the tank (type 2, a weapon index past the tables). Enemy 1 stands 3000 east of the
## subjects (inside the rifle's weapon range), enemy 2 4800 east (out of it, inside its acquire
## range); the subjects stand in a line of 7 milli steps from 9500. Every unit is due on every
## tick, and a stale navigation cell and the three modes (none, hold, chase) are set by hand.
func _unarmed_world() -> World:
	var world: World = Rig.data_world(20, 12)
	world.type_weapon[ROCKET] = -1
	world.type_weapon[TANK] = world.weapon_range.size()
	world.add_unit(2, RIFLE, 12500, 6000)
	world.add_unit(2, RIFLE, 14300, 6000)
	for type: int in [RIFLE, ROCKET, TANK]:
		for order: int in [IDLE, ATTACK_MOVE, ATTACK]:
			for held: int in [0, 1, 2, 99999]:
				for mode: int in [NONE, HOLD, CHASE]:
					var row: int = world.unit_count()
					world.add_unit(1, type, 9500 + row * 7, 6000)
					world.order[row] = order
					world.target[row] = held
					world.order_target[row] = held
					world.nav_mode[row] = mode
					world.nav_cell[row] = 3
	world.retarget_period_ticks = 1
	world.line_check_period_ticks = 1
	return world


## A hand-built World with no map (no map size): one weapon of range 4000 (acquire range 5000), an
## attack-moving unit at (100, 100) that holds enemy 2 at (4700, 100) by hand, and nobody scans.
func _mapless_world() -> World:
	var world: World = World.new()
	world.type_ids.append(&"type")
	world.type_weapon.append(0)
	world.type_acquire.append(5000)
	world.weapon_range.append(4000)
	world.weapon_min_range.append(0)
	world.weapon_vs_armour = PackedInt32Array([100, 100, 100, 100])
	world.add_unit(1, 0, 100, 100)
	world.add_unit(2, 0, 4700, 100)
	world.order[0] = ATTACK_MOVE
	world.target[0] = 2
	world.retarget_period_ticks = NEVER_DUE
	world.line_check_period_ticks = 1
	return world


## 100 random units on a 20 x 12 tile map; see test_random_states_stepped_for_six_calls....
func _random_world(seed: int) -> World:
	var rng: DetRandom = DetRandom.create(seed, 4)
	var world: World = Rig.data_world(20, 12)
	world.terrain_cost = PackedByteArray(GridWorld.GROUND_COST)
	for _paint: int in 30:
		world.set_terrain(rng.next_int(20 * 12), 2)
	var count: int = 100
	for _unit: int in count:
		var x: int = rng.next_int(14000) + 3000
		var y: int = rng.next_int(8000) + 2000
		if rng.next_int(10) == 0:
			x = rng.next_int(26000) - 3000
			y = rng.next_int(18000) - 3000
		world.add_unit(rng.next_int(3), rng.next_int(3), x, y)
	for row: int in count:
		world.order[row] = rng.next_int(4)
		world.nav_mode[row] = rng.next_int(5)
		world.target[row] = _any_id(rng, row, count)
		world.order_target[row] = _any_id(rng, row, count)
		world.goal_x[row] = rng.next_int(20000)
		world.goal_y[row] = rng.next_int(12000)
		world.nav_cell[row] = rng.next_int(3) - 1
		world.field[row] = rng.next_int(4) - 1
		world.nav_next[row] = rng.next_int(3) - 2
		world.best_dist[row] = rng.next_int(100)
		world.stall[row] = rng.next_int(5)
	# One World in four has an unarmed type: no weapon, or a weapon the tables lack.
	var unarmed: int = rng.next_int(4)
	if unarmed == 2:
		world.type_weapon[TANK] = -1
	elif unarmed == 3:
		world.type_weapon[ROCKET] = world.weapon_range.size() + rng.next_int(3)
	var periods: Array[int] = [0, 1, 2, 3, 5]
	world.retarget_period_ticks = periods[rng.next_int(periods.size())]
	world.line_check_period_ticks = periods[rng.next_int(periods.size())]
	world.tick = rng.next_int(40)
	return world


## A unit id for a random reference: 0, the unit itself, another unit or one that is gone.
func _any_id(rng: DetRandom, row: int, count: int) -> int:
	var kind: int = rng.next_int(10)
	if kind < 4:
		return 0
	if kind == 4:
		return row + 1
	if kind == 5:
		return count + 1 + rng.next_int(5)
	return 1 + rng.next_int(count)


## Every permutation of `items`, the first element varying slowest.
func _permutations(items: Array) -> Array[Array]:
	if items.size() <= 1:
		return [items.duplicate()]
	var found: Array[Array] = []
	for at: int in items.size():
		var rest: Array = items.duplicate()
		rest.remove_at(at)
		for tail: Array in _permutations(rest):
			found.append([items[at]] + tail)
	return found
