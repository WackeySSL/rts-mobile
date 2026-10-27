extends GdUnitTestSuite
## What a landed rupture shows (plan P112b, ADR 0023 section 10, assets/art/STYLE.md "Fields"): a
## burst of the effects ring at the point, and the crater decal in the DecalLayer at the rupture's
## radius (the art is the circle of 1.5 tiles, so the Deep Bore's 3 tiles are scale 2). Both are
## made where the local player sees the point's tile as the rupture hits: in the fog of the last
## tick it was in the air or of the tick it landed, since the landing step's own kills take their
## sight away before that tick's fog is made. That is the rule of the craters that destroyed
## buildings leave; `reveal_enemies` shows them everywhere, as it does every effect. The burst is a
## slot of the ring (nothing is made for it) and expires; the crater stays. The warning before the
## landing is StrikeMarkerLayer's. On a 32 x 32 map: player 1's Deep Bore at tile (4, 4) and player
## 2's Blackout Array at (20, 20); 1 dp is 1.75 px.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const Strikes: GDScript = preload("res://tests/sim/support/strike_worlds.gd")
const AT: Vector2i = Vector2i(14500, 20500)  ## Tile (14, 20).
const NEXT_TILE: Vector2i = Vector2i(15500, 20500)  ## Tile (15, 20).
const AT_TILE: Vector2i = Vector2i(14, 20)
const TOL: Vector2 = Vector2(0.001, 0.001)
const SPAWNS: Array[Array] = [[1, "fossil_strike", 4, 4], [2, "renew_strike", 20, 20]]

var _now_ms: int = 0
var _runner: MatchRunner
var _decals: DecalLayer
var _layer: EffectsLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	var spawns: Array[SpawnDef] = []
	for entry: Array in SPAWNS:
		spawns.append(Rig.spawn(entry[0], entry[1], entry[2], entry[3]))
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_decals = auto_free(DecalLayer.new())
	add_child(_decals)
	_make_layer()
	Rig.see(_runner.snapshot, 1, [Vector2i(14, 20)])


func after_test() -> void:
	UiScale.clear_override()
	CommandQueue.clear()


func test_a_rupture_landing_on_seen_ground_bursts_and_leaves_a_crater_of_its_radius() -> void:
	var radius: int = StrikeLandings.rupture_radius(_runner.snapshot)
	assert_int(radius).is_greater(0)
	_land(AT)
	assert_int(_layer.active_count()).is_equal(1)
	_at(200)  # Past the growth of a burst.
	assert_int(_layer.quad_count()).is_equal(1)
	assert_that(_layer.quad_region(0)).is_equal(EffectsLayer.BURST)
	var half: float = IsoProjection.ellipse_px(radius).x
	var ground: Vector2 = IsoProjection.ground_to_px(AT.x, AT.y)
	var rect: Rect2 = _layer.quad_rect(0)
	assert_float(rect.size.x).is_equal_approx(half, 0.01)
	assert_vector(rect.get_center()).is_equal_approx(ground - Vector2(0.0, half * 0.25), TOL)
	assert_int(_decals.crater_count()).is_equal(1)
	var crater: Sprite2D = _decals.find_child("Crater", true, false) as Sprite2D
	assert_vector(crater.position).is_equal(ground)
	var scale: float = float(radius) / DecalLayer.CRATER_ART_RADIUS_MILLI
	assert_vector(crater.scale).is_equal_approx(Vector2.ONE * scale, TOL)


func test_the_deep_bores_crater_is_the_art_scaled_to_twice() -> void:
	_land(AT)
	var crater: Sprite2D = _decals.find_child("Crater", true, false) as Sprite2D
	assert_vector(crater.scale).is_equal_approx(Vector2(2.0, 2.0), TOL)  # 3 tiles on 1.5.


func test_a_smaller_radius_is_a_smaller_burst_and_crater() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var bore: int = snap.type_strike_kind.find(Strike.Kind.RUPTURE)
	snap.type_strike_radius[bore] = 1500
	_land(AT)
	_at(200)
	var crater: Sprite2D = _decals.find_child("Crater", true, false) as Sprite2D
	assert_vector(crater.scale).is_equal_approx(Vector2.ONE, TOL)
	assert_float(_layer.quad_rect(0).size.x).is_equal_approx(IsoProjection.ellipse_px(1500).x, 0.01)


func test_a_landing_on_ground_the_player_does_not_see_shows_nothing() -> void:
	_layer.reveal_enemies = false
	_land(NEXT_TILE)  # The seen tile is the one beside it: the tile of the point decides.
	assert_int(_layer.active_count()).is_equal(0)
	assert_int(_decals.crater_count()).is_equal(0)
	_land(AT)
	assert_int(_layer.active_count()).is_equal(1)
	assert_int(_decals.crater_count()).is_equal(1)


func test_the_fog_of_the_landing_tick_decides_and_not_a_later_sight() -> void:
	Rig.see(_runner.snapshot, 1, [])
	_land(AT)
	Rig.see(_runner.snapshot, 1, [Vector2i(14, 20)])  # Seen afterwards: too late for this one.
	_runner.ticked.emit(_runner.snapshot.tick)
	assert_int(_layer.active_count()).is_equal(0)
	assert_int(_decals.crater_count()).is_equal(0)


## Sim.step lands the rupture, then unstamps the sight of the rows it killed, then the snapshot is
## made: the fog of the landing tick is dark where the only own row that saw the point just died.
## The ground was seen as the rupture hit, so it bursts and leaves its crater.
func test_a_rupture_that_kills_the_only_row_seeing_its_point_still_bursts_and_leaves_a_crater(
) -> void:
	var world: World = Strikes.world(false)  # A real fog; the bores and the HQ are far away.
	var tick: int = Strikes.fire_tick(world, Strikes.BORE_A)
	Strikes.run_to(world, tick)
	var seer: int = Strikes.add(world, 1, "rifle", Strikes.POINT.x, Strikes.POINT.y)
	Strikes.stamp(world)
	world.hp[world.index_of(seer)] = Strikes.damage_on(world, world.index_of(seer))
	Strikes.step(world, [Strikes.fire(Strikes.BORE_A)])
	_publish(world)
	assert_int(world.strike_tick[1]).is_greater(0)
	assert_bool(FogLayer.is_seen(_runner.snapshot, 1, Strikes.POINT.x, Strikes.POINT.y)).is_true()
	while world.strike_tick[1] != 0:
		Strikes.step(world)
		_publish(world)
	assert_int(world.index_of(seer)).is_equal(-1)  # Died in the landing step...
	var snap: MatchSnapshot = _runner.snapshot
	assert_bool(FogLayer.is_seen(snap, 1, Strikes.POINT.x, Strikes.POINT.y)).is_false()  # ...blind.
	assert_int(_layer.active_count()).is_equal(2)  # The seer's own death burst and the rupture's.
	assert_int(_decals.crater_count()).is_equal(1)


func test_ground_seen_in_the_last_tick_in_the_air_counts_when_the_landing_tick_lost_it() -> void:
	_land_in(AT, [[AT_TILE]], [])
	assert_int(_layer.active_count()).is_equal(1)
	assert_int(_decals.crater_count()).is_equal(1)


func test_ground_seen_only_in_the_landing_tick_counts_too() -> void:
	_land_in(AT, [[]], [AT_TILE])
	assert_int(_layer.active_count()).is_equal(1)
	assert_int(_decals.crater_count()).is_equal(1)


func test_ground_seen_early_in_the_air_but_dark_in_the_last_tick_and_at_the_landing_is_not(
) -> void:
	_land_in(AT, [[AT_TILE], [], []], [])
	assert_int(_layer.active_count()).is_equal(0)
	assert_int(_decals.crater_count()).is_equal(0)


func test_each_rupture_is_judged_by_its_own_sight_and_the_next_one_by_its_own() -> void:
	_land_in(AT, [[AT_TILE]], [])
	_land_in(NEXT_TILE, [[AT_TILE]], [])  # Seen tile is not the one it hits.
	assert_int(_decals.crater_count()).is_equal(1)
	_land_in(AT, [[AT_TILE]], [])
	assert_int(_decals.crater_count()).is_equal(2)


func test_reveal_enemies_shows_a_landing_in_the_dark_too() -> void:
	Rig.see(_runner.snapshot, 1, [])
	_layer.reveal_enemies = true
	_land(AT)
	assert_int(_layer.active_count()).is_equal(1)
	assert_int(_decals.crater_count()).is_equal(1)


func test_a_rupture_still_in_the_air_shows_nothing_and_the_burst_expires_but_the_crater_stays(
) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.strike_x[1] = AT.x
	snap.strike_y[1] = AT.y
	snap.strike_tick[1] = snap.tick + 45
	for _step: int in 3:
		_runner.ticked.emit(snap.tick)
	assert_int(_layer.active_count()).is_equal(0)
	assert_int(_decals.crater_count()).is_equal(0)
	snap.strike_tick[1] = 0
	_runner.ticked.emit(snap.tick)
	assert_int(_layer.active_count()).is_equal(1)
	_at(EffectsLayer.LIFETIME_MS[EffectsLayer.Kind.BURST] - 1)
	assert_int(_layer.active_count()).is_equal(1)
	_at(EffectsLayer.LIFETIME_MS[EffectsLayer.Kind.BURST])
	assert_int(_layer.active_count()).is_equal(0)
	assert_int(_decals.crater_count()).is_equal(1)


func test_the_burst_takes_a_slot_of_the_ring_and_no_object() -> void:
	_layer.decals = null  # The burst alone: no crater to count.
	_layer.capacity = 4
	for _round: int in 40:
		_land(AT)
	assert_int(_layer.active_count()).is_equal(4)  # The ring is full; the oldest are overwritten.
	assert_int(_layer.get_child_count()).is_equal(0)
	_at(100)
	assert_int(_layer.quad_count()).is_equal(4)


## A layer on the fake clock and out of the frame loop, drawing craters into `_decals`.
func _make_layer() -> void:
	_now_ms = 0
	_layer = auto_free(EffectsLayer.new())
	_layer.runner = _runner
	_layer.decals = _decals
	_layer.clock = func() -> int: return _now_ms
	add_child(_layer)
	_layer.set_process(false)


## Player 1's rupture at `at` goes up and lands: the tick it is in the air, then the one it is not.
func _land(at: Vector2i) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.strike_x[1] = at.x
	snap.strike_y[1] = at.y
	snap.strike_tick[1] = snap.tick + 45
	_runner.ticked.emit(snap.tick)
	snap.strike_tick[1] = 0
	_runner.ticked.emit(snap.tick)


## Player 1's rupture at `at` is in the air for one tick per entry of `in_the_air`, each with the
## tiles the local player sees in it, and lands in a tick in which it sees `at_landing`.
func _land_in(at: Vector2i, in_the_air: Array, at_landing: Array) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.strike_x[1] = at.x
	snap.strike_y[1] = at.y
	snap.strike_tick[1] = snap.tick + 45
	for tiles: Array in in_the_air:
		Rig.see(snap, 1, tiles)
		_runner.ticked.emit(snap.tick)
	Rig.see(snap, 1, at_landing)
	snap.strike_tick[1] = 0
	_runner.ticked.emit(snap.tick)


## Publishes the state of `world` as the runner's snapshot of a new tick.
func _publish(world: World) -> void:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = _runner.snapshot.match_serial
	snap.capture(world, null)
	_runner.snapshot = snap
	_runner.ticked.emit(snap.tick)


## The effects of the last tick `age` ms after they were born (at clock 0), planned.
func _at(age: int) -> void:
	_now_ms = age
	_layer._process(0.0)
