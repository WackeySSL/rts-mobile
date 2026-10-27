extends GdUnitTestSuite
## How the view finds a rupture that landed (plan P112b, ADR 0023 section 10): from the published
## snapshot alone, a player's `strike_tick` that was set and is not what the last look saw has
## landed at the point it was fired at. The sim clears `strike_tick` in the landing step and leaves
## the point, so the point is kept from the sight of the pending strike (a rupture fired again at
## once overwrites it). One landing for one rupture, never one for a rupture that is still in the
## air, and none across a new match. The radius is the first rupture type's, never a blackout's.

const Rig: GDScript = preload("res://tests/input/support/strike_rig.gd")
const Seen: GDScript = preload("res://tests/view/support/building_rig.gd")
const EVERYONE: int = 0  ## A viewer the fog does not cover: it sees every point.
const VIEWER: int = 1
const AT_ONE: Vector2i = Vector2i(7500, 8500)
const AT_TWO: Vector2i = Vector2i(15500, 11500)

var _world: World
var _lands: StrikeLandings


func before_test() -> void:
	_world = Rig.world()
	_world.tick = 100
	_lands = StrikeLandings.new()


func test_a_rupture_that_clears_is_one_landing_at_the_point_it_was_fired_at() -> void:
	_fire(1, AT_ONE, 145)
	assert_int(_lands.update(Rig.snapshot(_world), EVERYONE)).is_equal(0)  # In the air.
	_world.tick = 144
	assert_int(_lands.update(Rig.snapshot(_world), EVERYONE)).is_equal(0)  # Still in the air.
	_world.strike_tick[1] = 0  # The sim leaves the point, but another can overwrite it.
	_world.strike_x[1] = 1
	_world.strike_y[1] = 2
	assert_int(_lands.update(Rig.snapshot(_world), EVERYONE)).is_equal(1)
	assert_that(_lands.point(0)).is_equal(AT_ONE)
	assert_int(_lands.update(Rig.snapshot(_world), EVERYONE)).is_equal(0)  # Told once.


func test_the_same_snapshot_twice_and_a_quiet_match_land_nothing() -> void:
	var snap: MatchSnapshot = Rig.snapshot(_world)
	assert_int(_lands.update(snap, EVERYONE)).is_equal(0)
	assert_int(_lands.update(snap, EVERYONE)).is_equal(0)
	_fire(2, AT_TWO, 145)
	snap = Rig.snapshot(_world)
	assert_int(_lands.update(snap, EVERYONE)).is_equal(0)
	assert_int(_lands.update(snap, EVERYONE)).is_equal(0)


func test_two_players_landing_in_one_tick_are_told_in_player_order() -> void:
	_fire(2, AT_TWO, 145)
	_fire(1, AT_ONE, 146)
	_lands.update(Rig.snapshot(_world), EVERYONE)
	_world.strike_tick[1] = 0
	_world.strike_tick[2] = 0
	assert_int(_lands.update(Rig.snapshot(_world), EVERYONE)).is_equal(2)
	assert_that(_lands.point(0)).is_equal(AT_ONE)
	assert_that(_lands.point(1)).is_equal(AT_TWO)


## The player may fire again from the step after the landing; a frame that played both steps shows
## the landing to the handler of its own tick, but a snapshot that jumps from one pending strike to
## another still lands the first at its own point.
func test_a_rupture_fired_again_lands_the_first_at_its_own_point() -> void:
	_fire(1, AT_ONE, 145)
	_lands.update(Rig.snapshot(_world), EVERYONE)
	_fire(1, AT_TWO, 190)
	assert_int(_lands.update(Rig.snapshot(_world), EVERYONE)).is_equal(1)
	assert_that(_lands.point(0)).is_equal(AT_ONE)
	_world.strike_tick[1] = 0
	assert_int(_lands.update(Rig.snapshot(_world), EVERYONE)).is_equal(1)
	assert_that(_lands.point(0)).is_equal(AT_TWO)


func test_a_new_match_forgets_a_pending_rupture_and_does_not_land_one_it_finds_in_the_air() -> void:
	_fire(1, AT_ONE, 145)
	_lands.update(Rig.snapshot(_world, 1), EVERYONE)
	_world.strike_tick[1] = 0
	assert_int(_lands.update(Rig.snapshot(_world, 2), EVERYONE)).is_equal(0)  # Another match.
	_fire(1, AT_TWO, 160)
	assert_int(_lands.update(Rig.snapshot(_world, 2), EVERYONE)).is_equal(0)  # Remembered.
	_world.strike_tick[1] = 0
	assert_int(_lands.update(Rig.snapshot(_world, 2), EVERYONE)).is_equal(1)
	assert_that(_lands.point(0)).is_equal(AT_TWO)


func test_the_radius_is_the_first_rupture_types_and_not_the_blackouts() -> void:
	var snap: MatchSnapshot = Rig.snapshot(_world)
	var bore: int = Rig.type_of(_world, "fossil_strike")
	var array: int = Rig.type_of(_world, "renew_strike")
	assert_int(snap.type_strike_kind[bore]).is_equal(Strike.Kind.RUPTURE)
	assert_int(snap.type_strike_kind[array]).is_equal(Strike.Kind.BLACKOUT)
	assert_int(StrikeLandings.rupture_radius(snap)).is_equal(snap.type_strike_radius[bore])
	assert_int(snap.type_strike_radius[array]).is_not_equal(snap.type_strike_radius[bore])
	snap.type_strike_kind[bore] = Strike.Kind.NONE  # A roster without a rupture.
	assert_int(StrikeLandings.rupture_radius(snap)).is_equal(0)


## The viewer's sight of the point is the fog of the last snapshot the rupture was in the air in:
## the landing step's kills take sight away before the landing snapshot is made, and a sight that
## comes later is not the ground as it hit.
func test_the_sight_is_that_of_the_last_snapshot_the_rupture_was_in_the_air_in() -> void:
	_fire(1, AT_ONE, 145)
	_lands.update(_snapshot_seeing([_tile(AT_ONE)]), VIEWER)
	_world.strike_tick[1] = 0
	assert_int(_lands.update(_snapshot_seeing([]), VIEWER)).is_equal(1)  # The seer died with it.
	assert_bool(_lands.was_seen(0)).is_true()
	_fire(1, AT_TWO, 190)
	_lands.update(_snapshot_seeing([_tile(AT_TWO)]), VIEWER)
	_lands.update(_snapshot_seeing([]), VIEWER)  # The sight ended while it was still in the air.
	_world.strike_tick[1] = 0
	assert_int(_lands.update(_snapshot_seeing([_tile(AT_TWO)]), VIEWER)).is_equal(1)
	assert_bool(_lands.was_seen(0)).is_false()  # Seen only as it landed: the caller's rule.


func test_each_landing_keeps_its_own_sight_and_a_new_match_forgets_it() -> void:
	_fire(1, AT_ONE, 145)
	_fire(2, AT_TWO, 146)
	_lands.update(_snapshot_seeing([_tile(AT_TWO)]), VIEWER)
	_world.strike_tick[1] = 0
	_world.strike_tick[2] = 0
	assert_int(_lands.update(_snapshot_seeing([]), VIEWER)).is_equal(2)
	assert_bool(_lands.was_seen(0)).is_false()  # Player 1's, at AT_ONE.
	assert_bool(_lands.was_seen(1)).is_true()  # Player 2's, at AT_TWO.
	_fire(1, AT_ONE, 160)
	_lands.update(_snapshot_seeing([_tile(AT_ONE)], 2), VIEWER)
	_world.strike_tick[1] = 0
	assert_int(_lands.update(_snapshot_seeing([], 2), VIEWER)).is_equal(1)
	assert_bool(_lands.was_seen(0)).is_true()
	_fire(1, AT_ONE, 190)
	_lands.update(_snapshot_seeing([_tile(AT_ONE)], 3), VIEWER)  # Another match, a rupture seen.
	_fire(1, AT_TWO, 200)
	_lands.update(_snapshot_seeing([], 4), VIEWER)  # Another: its first sight is of the dark.
	_world.strike_tick[1] = 0
	assert_int(_lands.update(_snapshot_seeing([_tile(AT_TWO)], 4), VIEWER)).is_equal(1)
	assert_bool(_lands.was_seen(0)).is_false()


## Player `player` fires a rupture at `at` that lands on tick `landing`.
func _fire(player: int, at: Vector2i, landing: int) -> void:
	_world.strike_x[player] = at.x
	_world.strike_y[player] = at.y
	_world.strike_tick[player] = landing


## The snapshot of the world with exactly `tiles` visible to the viewer.
func _snapshot_seeing(tiles: Array, serial: int = 0) -> MatchSnapshot:
	var snap: MatchSnapshot = Rig.snapshot(_world, serial)
	Seen.see(snap, VIEWER, tiles)
	return snap


func _tile(at: Vector2i) -> Vector2i:
	return Vector2i(at.x / World.MILLI_PER_TILE, at.y / World.MILLI_PER_TILE)
