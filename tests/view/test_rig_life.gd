extends GdUnitTestSuite
## `RigLife` alone (plan P136, ADR 0027 section 3): the table of kicks without a layer. A SHOT
## record starts a kick for its shooter, born at the snapshot's tick; `advance` brings every kick
## to a match time and reads its offsets: 0 at the shot, the peak at `recoil_out_ms`, an ease back
## to 0 at `recoil_back_ms`, in steps of 0.5 px, along the reverse of the aim as the event holds it.
## The layers' use of it is in test_recoil_units.gd and test_recoil_heads.gd. Born at tick 30 is
## 2000 ms of match time, so `now` below is 2000 + the age.

const TOL: Vector2 = Vector2(0.001, 0.001)
const BORN_MS: float = 2000.0  ## Tick 30.
## Straight east on the screen: (4000, -4000) on the grid is 256 px right and 0 down.
const EAST: Vector2i = Vector2i(4000, -4000)

var _life: RigLife
var _snap: MatchSnapshot


func before_test() -> void:
	_life = RigLife.new()
	_life.setup(LifeSettings.new())
	_snap = MatchSnapshot.new()
	_snap.tick = 30
	_snap.match_serial = 7
	_snap.weapon_ids = [&"tank_cannon", &"heavy_cannon", &"unknown_gun"]


func test_the_offsets_of_a_kick_follow_the_curve_in_half_pixel_steps() -> void:
	# tank_cannon: 3 px, peak at 50 ms, home at 200 ms. The ease back is (1 - u) squared.
	_snap.events = _event(1, Vector2i(10500, 10500), Vector2i(10500, 10500) + EAST, 0)
	var expected: Dictionary[int, float] = {
		0: 0.0, 25: 1.5, 50: 3.0, 75: 2.0, 100: 1.5, 125: 1.0, 150: 0.5, 175: 0.0, 199: 0.0
	}
	for age: int in expected:
		var fresh: RigLife = RigLife.new()
		fresh.setup(LifeSettings.new())
		fresh.shot(_snap, 0, true)
		assert_int(fresh.advance(BORN_MS + age)).is_equal(1)
		var note: String = "age %d" % age
		assert_vector(fresh.turret_offset(0)).override_failure_message(note).is_equal_approx(
			Vector2(-expected[age], 0.0), TOL
		)
		assert_vector(fresh.hull_offset(0)).is_equal(Vector2.ZERO)  # No rock for this weapon.


func test_a_kick_is_over_at_the_back_time_and_sweep_drops_it() -> void:
	_shot(1, 0)
	_life.advance(BORN_MS + 199.0)
	_life.sweep()
	assert_int(_life.count()).is_equal(1)  # Not over yet.
	assert_int(_life.advance(BORN_MS + 200.0)).is_equal(1)
	assert_vector(_life.turret_offset(0)).is_equal(Vector2.ZERO)  # Its last zero is readable,
	assert_int(_life.count()).is_equal(1)
	_life.sweep()  # then it is dropped.
	assert_int(_life.count()).is_equal(0)


func test_a_heavy_gun_rocks_the_hull_and_the_turret_rides_with_it() -> void:
	_shot(1, 1)  # heavy_cannon: 4 px of recoil, 1 px of rock.
	_life.advance(BORN_MS + 50.0)
	assert_vector(_life.hull_offset(0)).is_equal_approx(Vector2(-1.0, 0.0), TOL)
	assert_vector(_life.turret_offset(0)).is_equal_approx(Vector2(-5.0, 0.0), TOL)
	_life.shot(_snap, 0, false)  # A defence: no hull to rock.
	_life.advance(BORN_MS + 50.0)
	assert_vector(_life.hull_offset(0)).is_equal(Vector2.ZERO)
	assert_vector(_life.turret_offset(0)).is_equal_approx(Vector2(-4.0, 0.0), TOL)


func test_the_offset_runs_along_the_reverse_of_the_aim_whatever_its_direction() -> void:
	_snap.events = _event(1, Vector2i(5000, 5000), Vector2i(9000, 5000), 0)  # Along grid x.
	_life.shot(_snap, 0, true)
	_life.advance(BORN_MS + 50.0)
	var drawn: Vector2 = IsoProjection.ground_to_px(4000, 0)  # 128 px right, 64 down.
	assert_vector(_life.turret_offset(0)).is_equal_approx(-drawn.normalized() * 3.0, TOL)


func test_the_age_only_moves_forward() -> void:
	# WORKER mode restarts alpha at 0 after a pause: the clock steps back by up to a tick.
	_shot(1, 0)
	_life.advance(BORN_MS + 100.0)
	var held: Vector2 = _life.turret_offset(0)
	assert_float(_life.age_at(0)).is_equal(100.0)
	_life.advance(BORN_MS + 100.0 - 66.7)  # The step back.
	assert_float(_life.age_at(0)).is_equal(100.0)
	assert_vector(_life.turret_offset(0)).is_equal(held)
	_life.advance(BORN_MS + 125.0)
	assert_float(_life.age_at(0)).is_equal(125.0)
	assert_vector(_life.turret_offset(0)).is_equal_approx(Vector2(-1.0, 0.0), TOL)


func test_a_clock_before_the_birth_gives_age_0_and_no_offset() -> void:
	_shot(1, 0)
	_life.advance(BORN_MS - 500.0)
	assert_float(_life.age_at(0)).is_equal(0.0)
	assert_vector(_life.turret_offset(0)).is_equal(Vector2.ZERO)
	_life.sweep()
	assert_int(_life.count()).is_equal(1)  # Not over: it has not begun.


func test_a_second_shot_of_a_rig_restarts_its_slot_and_other_rigs_have_their_own() -> void:
	_shot(1, 0)
	_shot(2, 1)
	assert_int(_life.count()).is_equal(2)
	_life.advance(BORN_MS + 100.0)
	_snap.tick = 31
	_shot(1, 0)  # Rig 1 again, a tick later.
	assert_int(_life.count()).is_equal(2)
	assert_int(_life.id_at(0)).is_equal(1)
	_life.advance(BORN_MS + 100.0)  # Age of the restarted kick: 100 - 66.7 = 33.3 ms.
	assert_float(_life.age_at(0)).is_equal_approx(33.333, 0.01)
	assert_float(_life.age_at(1)).is_equal(100.0)  # The other one is untouched.


func test_sweep_keeps_the_kicks_that_go_on_whatever_slot_the_finished_one_was_in() -> void:
	for id: int in [10, 11, 12, 13]:
		_shot(id, 0)
	_life.end(1)
	_life.end(3)
	_life.sweep()
	assert_int(_life.count()).is_equal(2)
	var left: Array[int] = [_life.id_at(0), _life.id_at(1)]
	left.sort()
	assert_array(left).is_equal([10, 12])
	_life.advance(BORN_MS + 50.0)  # The moved kick has its own data.
	assert_vector(_life.turret_offset(0)).is_equal_approx(Vector2(-3.0, 0.0), TOL)
	assert_vector(_life.turret_offset(1)).is_equal_approx(Vector2(-3.0, 0.0), TOL)


func test_a_full_table_starts_nothing_and_changes_nothing() -> void:
	var small: LifeSettings = LifeSettings.new()
	small.kick_slots = 2
	_life.setup(small)
	_shot(1, 0)
	_shot(2, 0)
	_shot(3, 0)
	assert_int(_life.count()).is_equal(2)
	assert_int(_life.id_at(0)).is_equal(1)
	assert_int(_life.id_at(1)).is_equal(2)
	_shot(1, 0)  # A rig that has a slot restarts it even when the table is full.
	assert_int(_life.count()).is_equal(2)


func test_no_kick_for_a_shot_without_a_weapon_row_an_aim_or_a_known_weapon() -> void:
	_snap.events = _event(1, Vector2i(5000, 5000), Vector2i(9000, 5000), 2)  # unknown_gun
	_life.shot(_snap, 0, true)
	_snap.events = _event(1, Vector2i(5000, 5000), Vector2i(9000, 5000), -1)
	_life.shot(_snap, 0, true)
	_snap.events = _event(1, Vector2i(5000, 5000), Vector2i(9000, 5000), 3)  # Past the table.
	_life.shot(_snap, 0, true)
	_snap.events = _event(1, Vector2i(5000, 5000), Vector2i(5000, 5000), 0)  # No aim.
	_life.shot(_snap, 0, true)
	assert_int(_life.count()).is_equal(0)
	var flat: LifeSettings = LifeSettings.new()
	flat.recoil_px[&"tank_cannon"] = 0.0
	_life.setup(flat)
	_shot(1, 0)
	assert_int(_life.count()).is_equal(0)


func test_a_new_match_empties_the_table_and_the_same_match_does_not() -> void:
	_shot(1, 0)
	_life.follow(7)  # The first call takes the serial.
	assert_int(_life.count()).is_equal(0)
	_shot(1, 0)
	_life.follow(7)
	assert_int(_life.count()).is_equal(1)
	_life.follow(8)
	assert_int(_life.count()).is_equal(0)


func test_degenerate_times_are_read_as_at_least_a_ms() -> void:
	var odd: LifeSettings = LifeSettings.new()
	odd.recoil_out_ms = 0
	odd.recoil_back_ms = 0
	_life.setup(odd)
	_shot(1, 0)
	_life.advance(BORN_MS)  # No division by zero: peak at 1 ms, over at 2.
	assert_vector(_life.turret_offset(0)).is_equal(Vector2.ZERO)
	_life.advance(BORN_MS + 1.0)
	assert_vector(_life.turret_offset(0)).is_equal_approx(Vector2(-3.0, 0.0), TOL)
	_life.advance(BORN_MS + 2.0)
	assert_vector(_life.turret_offset(0)).is_equal(Vector2.ZERO)
	_life.sweep()
	assert_int(_life.count()).is_equal(0)


func test_the_peak_is_rounded_to_half_pixels_and_a_tiny_kick_is_nothing() -> void:
	var life: LifeSettings = LifeSettings.new()
	life.recoil_px[&"tank_cannon"] = 2.3
	life.recoil_px[&"heavy_cannon"] = 0.2
	life.rock_px.erase(&"heavy_cannon")
	_life.setup(life)
	_shot(1, 0)
	_shot(2, 1)
	_life.advance(BORN_MS + 50.0)
	assert_vector(_life.turret_offset(0)).is_equal_approx(Vector2(-2.5, 0.0), TOL)
	assert_vector(_life.turret_offset(1)).is_equal(Vector2.ZERO)  # 0.2 px is under a step.


func test_setup_sizes_the_table_and_empties_it() -> void:
	_shot(1, 0)
	_life.writes = 5
	_life.setup(LifeSettings.new())
	assert_int(_life.count()).is_equal(0)
	assert_int(_life.writes).is_equal(0)


## Starts a kick of rig `id` with the weapon at index `weapon` of the snapshot's table, straight
## east on the screen from tile (10, 10).
func _shot(id: int, weapon: int) -> void:
	_snap.events = _event(id, Vector2i(10500, 10500), Vector2i(10500, 10500) + EAST, weapon)
	_life.shot(_snap, 0, true)


## [SHOT, shooter id, shooter x, shooter y, target id, weapon, target x, target y].
func _event(id: int, from: Vector2i, to: Vector2i, weapon: int) -> PackedInt32Array:
	return PackedInt32Array([World.Event.SHOT, id, from.x, from.y, 99, weapon, to.x, to.y])
