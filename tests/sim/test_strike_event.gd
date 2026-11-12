extends GdUnitTestSuite
## The STRIKE event (plan row P133, ADR 0027 section 7, an ADR 0007 section 10 note): an accepted
## SUPERWEAPON, of either kind, appends one record `[STRIKE, building id, point x, point y, kind,
## owner, landing tick or 0, 0]` to `events` in the command's apply (COMMANDS), after the point is
## clamped: the rupture's landing is its `strike_tick`, the blackout's is 0. A dropped command, for
## every drop reason of `Strike.apply_superweapon` and of `Sim._apply`'s gates, writes none. The
## record sits in command order beside the SPAWNED record a PLACE writes, and before the tick's
## IMPACT, SHOT and DIED records. Events are not state (no hash covers them), the record is public
## (the sim writes it whatever the fog; the view filters, ADR 0027 section 6) and a run is the same
## twice, in the GDScript phases and in the C++ kernels. The rigs are `strike_worlds.gd` (two
## ruptures, a blackout, the numbers read from the World's tables) and `blackout_worlds.gd` (armed
## turrets, for a SHOT in the strike's tick).

const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const Blackouts: GDScript = preload("res://tests/sim/support/blackout_worlds.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const STRIKE: int = World.Event.STRIKE
const SPAWNED: int = World.Event.SPAWNED
const SHOT: int = World.Event.SHOT
const IMPACT: int = World.Event.IMPACT
const DIED: int = World.Event.DIED
const STRIDE: int = World.EVENT_STRIDE
const COMBAT_PATH: String = "res://game/sim/Combat.gd"


func _both() -> Array[Array]:
	return SimImpls.CASES.duplicate(true)


## The kinds of the records in `world.events`, in order.
func _kinds(world: World) -> Array[int]:
	var found: Array[int] = []
	for at: int in range(0, world.events.size(), STRIDE):
		found.append(world.events[at])
	return found


## The records of `kind` in `world.events`, each as its 8 ints, in order.
func _records(world: World, kind: int) -> Array[Array]:
	var found: Array[Array] = []
	for at: int in range(0, world.events.size(), STRIDE):
		if world.events[at] == kind:
			found.append(Array(world.events.slice(at, at + STRIDE)))
	return found


## A rig world run to the tick bore A may fire in, and that tick.
func _ready_world() -> Array:
	var world: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	Strikes.run_to(world, tick)
	return [world, tick]


## A command stamped with `sequence`, so that two commands of one player and tick sort the same way
## in every run (`Command.compare` ends on it; the match loop stamps it in play).
func _numbered(command: Command, sequence: int) -> Command:
	command.sequence = sequence
	return command


func test_the_event_kind_is_five_and_a_record_is_eight_ints() -> void:
	assert_int(World.Event.STRIKE).is_equal(5)
	assert_array([SPAWNED, DIED, SHOT, IMPACT]).is_equal([1, 2, 3, 4])
	assert_int(STRIDE).is_equal(8)
	assert_array([Strike.Kind.RUPTURE, Strike.Kind.BLACKOUT]).is_equal([1, 2])


## A rupture: one record, the whole tick's events, with the building's id, the point as the sim
## keeps it, the kind, the owner and the landing tick, which is the `strike_tick` it wrote.
func test_an_accepted_rupture_writes_one_record_with_its_fields() -> void:
	var ready: Array = _ready_world()
	var world: World = ready[0]
	var tick: int = ready[1]
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A, 1, Vector2i(12500, 9500))])
	assert_int(world.dropped_commands).is_equal(0)
	var landing: int = tick + 1 + Strikes.delay_of(world, "bore")
	assert_array(Array(world.events)).is_equal(
		[STRIKE, Strikes.BORE_A, 12500, 9500, Strike.Kind.RUPTURE, 1, landing, 0]
	)
	assert_int(world.strike_tick[1]).is_equal(landing)
	assert_array([world.strike_x[1], world.strike_y[1]]).is_equal([12500, 9500])


## The second bore is another building of the same player; the record names the one that fired.
func test_the_record_names_the_building_that_fired() -> void:
	var ready: Array = _ready_world()
	var world: World = ready[0]
	Strikes.step(world, [Strikes.fire(Strikes.BORE_B, 1, Vector2i(4500, 4500))])
	assert_int(world.dropped_commands).is_equal(0)
	var landing: int = world.strike_tick[1]
	assert_array(Array(world.events)).is_equal(
		[STRIKE, Strikes.BORE_B, 4500, 4500, Strike.Kind.RUPTURE, 1, landing, 0]
	)


## A blackout: one record, the kind 2 and a landing tick of 0 (it works at once and keeps no point),
## and the player's pending strike stays 0.
func test_an_accepted_blackout_writes_one_record_with_a_landing_tick_of_zero() -> void:
	var world: World = Strikes.world()
	var tick: int = Strikes.fire_tick(world, Strikes.ARRAY)
	Strikes.run_to(world, tick)
	Strikes.step(world, [Strikes.fire(Strikes.ARRAY, 1, Vector2i(24500, 15500))])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array(Array(world.events)).is_equal(
		[STRIKE, Strikes.ARRAY, 24500, 15500, Strike.Kind.BLACKOUT, 1, 0, 0]
	)
	assert_int(world.strike_tick[1]).is_equal(0)
	assert_bool(world.offline_until[world.index_of(Strikes.HQ_2)] > 0).is_true()  # It did work.


## The owner field is the firing player's: player 2's bore writes owner 2, with its own landing.
func test_the_owner_is_the_firing_player() -> void:
	var world: World = Strikes.world()
	var enemy: int = world.add_building(2, Strikes.type_of(world, "bore"), 20, 2)
	var tick: int = world.ready_tick[world.index_of(enemy)] - 1
	Strikes.run_to(world, tick)
	Strikes.step(world, [Strikes.fire(enemy, 2, Vector2i(2500, 15500))])
	assert_int(world.dropped_commands).is_equal(0)
	var landing: int = tick + 1 + Strikes.delay_of(world, "bore")
	assert_array(Array(world.events)).is_equal(
		[STRIKE, enemy, 2500, 15500, Strike.Kind.RUPTURE, 2, landing, 0]
	)


## The point in the record is the clamped one the sim uses, for both kinds: far outside the map it
## ends on the nearest edge, and equals `strike_x`/`strike_y` for the rupture.
func test_the_point_in_the_record_is_the_clamped_one() -> void:
	var ready: Array = _ready_world()
	var world: World = ready[0]
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A, 1, Vector2i(-5000, 99999999))])
	var rupture: Array[Array] = _records(world, STRIKE)
	assert_int(rupture.size()).is_equal(1)
	assert_array([rupture[0][2], rupture[0][3]]).is_equal([0, world.map_h - 1])
	assert_array([world.strike_x[1], world.strike_y[1]]).is_equal([rupture[0][2], rupture[0][3]])
	var blackout: World = Strikes.world()
	Strikes.run_to(blackout, Strikes.fire_tick(blackout, Strikes.ARRAY))
	Strikes.step(blackout, [Command.superweapon(1, Strikes.ARRAY, 1 << 40, -(1 << 40))])
	var clamped: Array[Array] = _records(blackout, STRIKE)
	assert_int(clamped.size()).is_equal(1)
	assert_array([clamped[0][2], clamped[0][3]]).is_equal([blackout.map_w - 1, 0])


## Two accepted commands in one tick write two records, in command order: a blackout and then a
## rupture of one player are both accepted (only a pending rupture blocks a further strike), in the
## order of their sequence numbers; the other way round, the rupture blocks the blackout, which is
## dropped and writes none.
func test_one_record_per_accepted_command_in_command_order() -> void:
	var cases: Array = [
		[Strikes.ARRAY, Strikes.BORE_A, [Strikes.ARRAY, Strikes.BORE_A], 0],
		[Strikes.BORE_A, Strikes.ARRAY, [Strikes.BORE_A], 1],
	]
	for each: Array in cases:
		var world: World = Strikes.world()
		Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
		var first: Command = _numbered(Strikes.fire(each[0], 1, Vector2i(5500, 5500)), 0)
		var second: Command = _numbered(Strikes.fire(each[1], 1, Vector2i(9500, 9500)), 1)
		Strikes.step(world, [second, first])  # The step sorts them; the call order is not the rule.
		var named: Array[int] = []
		for record: Array in _records(world, STRIKE):
			named.append(record[1])
		assert_array(named).override_failure_message("%s" % [each]).is_equal(each[2])
		assert_int(world.dropped_commands).is_equal(each[3])


## Two players, each with a ready bore, fire in one tick: the records follow `Command.compare`
## (player ascending), whatever order the commands are handed in.
func test_two_players_write_their_records_by_player() -> void:
	var world: World = Strikes.world()
	var enemy: int = world.add_building(2, Strikes.type_of(world, "bore"), 20, 2)
	var tick: int = maxi(
		Strikes.fire_tick(world, Strikes.BORE_A), world.ready_tick[world.index_of(enemy)] - 1
	)
	Strikes.run_to(world, tick)
	var theirs: Command = _numbered(Strikes.fire(enemy, 2, Vector2i(2500, 15500)), 0)
	var ours: Command = _numbered(Strikes.fire(Strikes.BORE_A, 1, Vector2i(12500, 9500)), 1)
	Strikes.step(world, [theirs, ours])
	assert_int(world.dropped_commands).is_equal(0)
	var owners: Array[int] = []
	for record: Array in _records(world, STRIKE):
		owners.append(record[5])
	assert_array(owners).is_equal([1, 2])


## Every drop reason writes no record: the command is counted dropped and the tick's events are
## empty. Each case also checks its control (the plain command on time is accepted and writes one),
## so the fault is what drops it.
func test_a_dropped_superweapon_writes_no_event() -> void:
	var rifle: Callable = func(w: World) -> void: Strikes.add(w, 1, "rifle", 5500, 15500)
	var offline: Callable = func(w: World) -> void:
		w.offline_until[w.index_of(Strikes.BORE_A)] = w.tick + 2
	var defeated: Callable = func(w: World) -> void: w.defeated_tick[1] = 3
	var ended: Callable = func(w: World) -> void: w.match_end_tick = 5
	var site: Callable = func(w: World) -> void: w.build_left[w.index_of(Strikes.BORE_A)] = 400
	var cancelled: Callable = func(w: World) -> void: w.build_left[w.index_of(Strikes.BORE_A)] = -1
	var bore: Callable = func() -> Command: return Strikes.fire(Strikes.BORE_A)
	var payload: Callable = func() -> Command:
		var command: Command = Strikes.fire(Strikes.BORE_A)
		command.payload = PackedInt32Array([1])
		return command
	_assert_no_event("not the player's own", func() -> Command: return Strikes.fire(1, 2))
	_assert_no_event("a headquarters", func() -> Command: return Strikes.fire(Strikes.HQ_1))
	_assert_no_event("a unit", func() -> Command: return Strikes.fire(6), rifle)
	_assert_no_event("an id with no row", func() -> Command: return Strikes.fire(999))
	_assert_no_event("id 0", func() -> Command: return Strikes.fire(0))
	_assert_no_event("a negative id", func() -> Command: return Strikes.fire(-1))
	_assert_no_event("still charging", bore, Callable(), 1)
	_assert_no_event("offline", bore, offline)
	_assert_no_event("a site", bore, site)
	_assert_no_event("a cancelled site", bore, cancelled)
	_assert_no_event("a defeated player", bore, defeated)
	_assert_no_event("after the end of the match", bore, ended)
	_assert_no_event("a payload", payload)
	_assert_no_event("a player past the table", func() -> Command: return Strikes.fire(1, 3))
	_assert_no_event("player 0", func() -> Command: return Strikes.fire(Strikes.BORE_A, 0))


## A command for another tick is dropped by `Sim.step` before any rule runs: no record.
func test_a_command_of_another_tick_writes_no_event() -> void:
	var ready: Array = _ready_world()
	var world: World = ready[0]
	var late: Command = Strikes.fire(Strikes.BORE_A)
	late.tick = world.tick - 1
	var early: Command = Strikes.fire(Strikes.BORE_A)
	early.tick = world.tick + 1
	Sim.step(world, [late, early] as Array[Command])
	assert_int(world.dropped_commands).is_equal(2)
	assert_array(Array(world.events)).is_empty()
	assert_int(world.strike_tick[1]).is_equal(0)


## A further SUPERWEAPON while the player's rupture is pending is dropped and writes none; the
## first one's record was written in its own step only (events are the last tick's).
func test_a_second_superweapon_while_a_rupture_is_pending_writes_no_event() -> void:
	var ready: Array = _ready_world()
	var world: World = ready[0]
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A, 1, Vector2i(12500, 9500))])
	assert_int(_records(world, STRIKE).size()).is_equal(1)
	Strikes.step(world, [Strikes.fire(Strikes.BORE_B, 1, Vector2i(4500, 4500))])
	assert_int(world.dropped_commands).is_equal(1)
	assert_array(Array(world.events)).is_empty()  # No STRIKE, and the first one's is gone.


## The guards that `Sim._apply` never lets through (a player past the pending table, a type past a
## rule table) and a strike kind that is neither rupture nor blackout: `apply_superweapon` itself
## returns false and writes nothing; the same untouched World then accepts and writes one.
func test_the_guards_of_apply_superweapon_write_no_event() -> void:
	var ready: Array = _ready_world()
	var world: World = ready[0]
	var stray: Command = Strikes.fire(Strikes.BORE_A, 9)
	stray.tick = world.tick
	assert_bool(Strike.apply_superweapon(world, stray)).is_false()
	var short: World = Strikes.world()
	Strikes.run_to(short, Strikes.fire_tick(short, Strikes.BORE_A))
	short.type_charge_ticks = PackedInt32Array()
	assert_bool(Strike.apply_superweapon(short, Strikes.fire(Strikes.BORE_A))).is_false()
	var odd: World = Strikes.world()
	Strikes.run_to(odd, Strikes.fire_tick(odd, Strikes.BORE_A))
	odd.type_strike_kind[Strikes.type_of(odd, "bore")] = 4  # Kind 3 is REVEAL (P233); 4 is unknown.
	assert_bool(Strike.apply_superweapon(odd, Strikes.fire(Strikes.BORE_A))).is_false()
	for each: World in [world, short, odd]:
		assert_array(Array(each.events)).is_empty()
		assert_int(each.strike_tick[1]).is_equal(0)
	var control: Command = Strikes.fire(Strikes.BORE_A)
	control.tick = world.tick
	assert_bool(Strike.apply_superweapon(world, control)).is_true()
	assert_int(_records(world, STRIKE).size()).is_equal(1)


## The record sits in COMMANDS in command order beside the SPAWNED record of a PLACE: with the PLACE
## first it is [SPAWNED, STRIKE], with the strike first [STRIKE, SPAWNED].
func test_the_record_follows_command_order_beside_a_place() -> void:
	for strike_first: bool in [false, true]:
		var world: World = Strikes.world()
		var bore: int = Strikes.type_of(world, "bore")
		Strikes.step(world, [Command.queue(1, bore)])
		Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A))
		var place: Command = Command.place(1, 6700, 8300)  # The tile (6, 8), next to the HQ.
		var fire: Command = Strikes.fire(Strikes.BORE_A)
		var label: String = "strike first" if strike_first else "place first"
		_numbered(place, 1 if strike_first else 0)
		_numbered(fire, 0 if strike_first else 1)
		Strikes.step(world, [place, fire])
		assert_int(world.dropped_commands).override_failure_message(label).is_equal(0)
		var expected: Array = [STRIKE, SPAWNED] if strike_first else [SPAWNED, STRIKE]
		assert_array(_kinds(world)).override_failure_message(label).is_equal(expected)
		var placed: Array = _records(world, SPAWNED)[0]
		assert_int(placed[4]).is_equal(bore)  # The new building, not the firing one.
		assert_int(_records(world, STRIKE)[0][1]).is_equal(Strikes.BORE_A)


## The record comes before the tick's SHOT: the array fires in a step where a turret outside its
## reach shoots (the blackout rig's turrets shoot at their dummies every cooldown).
func test_the_record_comes_before_the_ticks_shot() -> void:
	var world: World = Blackouts.world()
	Blackouts.run_to(world, Blackouts.fire_tick(world) + 30)
	var turret: int = world.index_of(Blackouts.TURRET_OUT)
	while world.cooldown[turret] != 1:  # It shoots in the next step.
		Blackouts.step(world)
	Blackouts.step(world, [Blackouts.fire()])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array(_kinds(world)).is_equal([STRIKE, SHOT])
	assert_array(Blackouts.shooters(world)).is_equal([Blackouts.TURRET_OUT])
	var at: Vector2i = Blackouts.POINT
	assert_array(Array(world.events.slice(0, STRIDE))).is_equal(
		[STRIKE, Blackouts.ARRAY, at.x, at.y, Strike.Kind.BLACKOUT, 1, 0, 0]
	)


## The record comes before the tick's IMPACT and DIED: a shell in flight lands in the step
## (PROJECTILES), and a rupture with no warning lands in it too, right after FIRE, killing a row
## that REMOVE then writes as DIED. The shell is seeded by hand into the slot on top of the free
## stack and borrows the bore's strike weapon, the one weapon of the rig.
func test_the_record_comes_before_the_ticks_impact_and_died() -> void:
	var ready: Array = _ready_world()
	var world: World = ready[0]
	world.type_strike_delay[Strikes.type_of(world, "bore")] = 0
	var victim: int = Strikes.add(world, 2, "rifle", Strikes.POINT.x, Strikes.POINT.y)
	world.hp[world.index_of(victim)] = Strikes.damage_on(world, world.index_of(victim))
	var mark: int = Strikes.add(world, 2, "tank", 20500, 15500)
	world.proj_free_top -= 1
	var slot: int = world.proj_free[world.proj_free_top]
	world.proj_id[slot] = world.next_projectile_id
	world.next_projectile_id += 1
	world.proj_owner[slot] = 1
	world.proj_weapon[slot] = 0
	world.proj_target[slot] = mark
	world.proj_x[slot] = 20500
	world.proj_y[slot] = 15500
	world.proj_aim_x[slot] = 20500
	world.proj_aim_y[slot] = 15500
	world.proj_ticks[slot] = 1
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	assert_int(world.dropped_commands).is_equal(0)
	assert_array(_kinds(world)).is_equal([STRIKE, IMPACT, DIED])
	assert_int(_records(world, DIED)[0][1]).is_equal(victim)
	assert_int(world.strike_tick[1]).is_equal(0)  # It landed in the same step.
	assert_int(_records(world, STRIKE)[0][6]).is_equal(world.tick)  # Landing = this step's stamp.


## The record is public: the sim writes it in full whatever the fog, as the rupture's warning is
## (ADR 0027 section 6 leaves the filtering to the view). Player 2 fires in a world with real fog
## where player 1 sees neither its bore nor the point, and the record is in `events` and in a
## snapshot of the tick, unfiltered; a viewer's fog decides only what is drawn.
func test_the_record_is_written_whatever_the_fog_and_reaches_the_snapshot() -> void:
	var world: World = Strikes.world(false)
	var enemy: int = world.add_building(2, Strikes.type_of(world, "bore"), 20, 2)
	Strikes.stamp(world)
	var tick: int = world.ready_tick[world.index_of(enemy)] - 1
	Strikes.run_to(world, tick)
	var point: Vector2i = Vector2i(26500, 3500)  # Far from player 1's sight.
	Strikes.step(world, [Strikes.fire(enemy, 2, point)])
	assert_int(world.dropped_commands).is_equal(0)
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.capture(world, null)
	for cell: int in [snap.cell_of(point.x, point.y), snap.cell_of(21500, 3500)]:
		assert_bool(world.fog.is_visible(1, cell)).is_false()  # Player 1 sees neither.
	var landing: int = world.strike_tick[2]
	var expected: Array = [STRIKE, enemy, point.x, point.y, Strike.Kind.RUPTURE, 2, landing, 0]
	assert_array(Array(world.events)).is_equal(expected)
	assert_array(Array(snap.events)).is_equal(expected)


## Events are not state: appending, removing or changing the record moves no hash section, so no
## golden hash or checkpoint can move with it.
func test_the_record_is_not_part_of_the_state_hash() -> void:
	var ready: Array = _ready_world()
	var world: World = ready[0]
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A, 1, Vector2i(12500, 9500))])
	assert_int(world.events.size()).is_equal(STRIDE)
	var with_record: PackedInt64Array = world.hash_parts()
	var hash_with: int = world.state_hash()
	var kept: PackedInt32Array = world.events.duplicate()
	world.events.clear()
	assert_array(Array(world.hash_parts())).is_equal(Array(with_record))
	assert_int(world.state_hash()).is_equal(hash_with)
	world.events.append_array(kept)
	world.events[2] = 1
	world.events[6] = 77
	assert_int(world.state_hash()).is_equal(hash_with)
	assert_int(World.STATE_FORMAT).is_equal(6)  # No layout version moved with the event (6: P232).


## A run is the same twice and in both implementations: the same scripted match (a blackout, then
## a rupture, then a second rupture after the first has landed, with a squad walking so that the
## kernels have work) gives the same events, record by record, and the same state hash, in the
## GDScript phases and in the C++ kernels, and a second run of each equals the first.
func test_a_run_writes_the_same_records_twice_and_in_both_implementations(
	impl: int, _test_parameters := _both()
) -> void:
	var first: Dictionary = _play(impl)
	var again: Dictionary = _play(impl)
	var other: Dictionary = _play(SimImpls.Impl.GDSCRIPT)
	assert_array(first.problems).is_empty()
	(
		assert_array(first.strikes)
		. is_equal(
			[
				[STRIKE, Strikes.ARRAY, 24500, 15500, Strike.Kind.BLACKOUT, 1, 0, 0],
				[STRIKE, Strikes.BORE_A, 12500, 9500, Strike.Kind.RUPTURE, 1, first.landing_a, 0],
				[STRIKE, Strikes.BORE_B, 4500, 4500, Strike.Kind.RUPTURE, 1, first.landing_b, 0],
			]
		)
	)
	assert_array(first.log).is_equal(again.log)
	assert_int(first.hash).is_equal(again.hash)
	assert_array(first.log).is_equal(other.log)
	assert_int(first.hash).is_equal(other.hash)


## Combat's header names the real writer order (P133 corrects "the first `events` writer of a tick
## is `advance_projectiles`", stale since a PLACE wrote a SPAWNED in COMMANDS): COMMANDS, then
## PROJECTILES, FIRE, REMOVE and PRODUCTION, with the STRIKE record in COMMANDS.
func test_combats_header_names_the_real_writer_order() -> void:
	var text: String = FileAccess.get_file_as_string(COMBAT_PATH)
	assert_bool(text.is_empty()).is_false()
	assert_bool(text.contains("The first `events` writer of a tick is")).is_false()
	var commands: int = text.find("COMMANDS write first")
	var strike: int = text.find("SUPERWEAPON's STRIKE", commands)
	var projectiles: int = text.find("`advance_projectiles` (its IMPACTs)", strike)
	var fire: int = text.find("`fire` (its SHOTs)", projectiles)
	var remove: int = text.find("REMOVE (DIED)", fire)
	var production: int = text.find("PRODUCTION", remove)
	assert_bool(commands > 0 and strike > commands and projectiles > strike).is_true()
	assert_bool(fire > projectiles and remove > fire and production > remove).is_true()
	assert_bool(text.contains("a PLACE's SPAWNED")).is_true()


## Plays the scripted match under `impl`: a rifle of player 1 walks, the array fires at its first
## tick, bore A at its own (the blackout first, because a pending rupture would block it) and bore
## B right after bore A has landed. Returns the problems of attaching `impl`, every record of the
## run as [tick, ...8 ints] in one flat list (`log`), the STRIKE records in order, the two landing
## ticks and the final state hash.
func _play(impl: int) -> Dictionary:
	var world: World = Strikes.world()
	var rifle: int = Strikes.add(world, 1, "rifle", 5500, 15500)
	Strikes.add(world, 2, "rifle", 24500, 16500)
	var problems: Array[String] = SimImpls.use(world, impl)
	var fire_array: int = Strikes.fire_tick(world, Strikes.ARRAY)
	var fire_a: int = Strikes.fire_tick(world, Strikes.BORE_A)
	var landing_a: int = fire_a + 1 + Strikes.delay_of(world, "bore")
	var fire_b: int = landing_a + 1
	var log: Array[int] = []
	var strikes: Array[Array] = []
	var script: Dictionary[int, Command] = {
		0: Command.move(1, PackedInt32Array([rifle]), 20500, 5500),
		fire_array: Strikes.fire(Strikes.ARRAY, 1, Vector2i(24500, 15500)),
		fire_a: Strikes.fire(Strikes.BORE_A, 1, Vector2i(12500, 9500)),
		fire_b: Strikes.fire(Strikes.BORE_B, 1, Vector2i(4500, 4500)),
	}
	for _step: int in fire_b + 20:
		var now: int = world.tick
		var commands: Array = [script[now]] if script.has(now) else []
		Strikes.step(world, commands)
		for at: int in range(0, world.events.size(), STRIDE):
			log.append(now)
			log.append_array(Array(world.events.slice(at, at + STRIDE)))
			if world.events[at] == STRIKE:
				strikes.append(Array(world.events.slice(at, at + STRIDE)))
	return {
		"problems": problems,
		"log": log,
		"strikes": strikes,
		"landing_a": landing_a,
		"landing_b": fire_b + 1 + Strikes.delay_of(world, "bore"),
		"hash": world.state_hash(),
	}


## Runs `make`'s command (a Callable, because a command is stamped in place and cannot be shared by
## two Worlds) in a rig world at the first tick the bore may fire (`early` ticks before it), after
## `prepare` changed the World: the command is dropped and counted and the tick's events are empty.
## The control, a fresh world on time with the plain command, is accepted and writes one.
func _assert_no_event(
	label: String, make: Callable, prepare: Callable = Callable(), early: int = 0
) -> void:
	var world: World = Strikes.world()
	Strikes.run_to(world, Strikes.fire_tick(world, Strikes.BORE_A) - early)
	if prepare.is_valid():
		prepare.call(world)
	Strikes.step(world, [make.call()])
	assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
	assert_array(Array(world.events)).override_failure_message(label).is_empty()
	var fine: World = Strikes.world()
	Strikes.run_to(fine, Strikes.fire_tick(fine, Strikes.BORE_A))
	Strikes.step(fine, [Strikes.fire(Strikes.BORE_A)])
	assert_array([fine.dropped_commands, _records(fine, STRIKE).size()]).is_equal([0, 1])
