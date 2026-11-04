extends "res://tests/view/support/damage_fx_suite.gd"
## The crater's smoke and embers after a collapse (plan P165, ADR 0029 sections 6, 8 and 9): they
## start 900 ms after the DIED and never for a site, and an own or shown building placed on the
## tiles stops them in that very tick. The fixture is `scenes/main.tscn`'s order: `AirFx` (in
## `LifeFx`) connects to `ticked` before `BuildingLayer`, so the layer is brought up to date by
## `AirFx` itself. Fixture: support/damage_fx_suite.gd with that order.

const SPAWNS: Array = [[1, 4, 4], [2, 24, 24], [1, 2, 20]]
const CRATER_STYLES: Array[int] = [
	DamageFx.Style.CRATER_SMOKE, DamageFx.Style.EMBER, DamageFx.Style.GLOW_FAINT
]


## `damage_fx_suite._open` with `AirFx` made, and so connected, first.
func _open(spawns: Array, quiet: Array[int] = [QUIET, 0, 0, 0, 0], reveal: bool = true) -> void:
	_life = DATA.duplicate() as LifeSettings
	_def = Dmg.sheet()
	_def.emitters = PackedStringArray(POINT_NAMES)
	_def.emitter_points = PackedVector2Array(POINT_AT)
	_def.emitter_quiet = PackedInt32Array(quiet)
	_runner = auto_free(Dmg.runner(spawns))
	_sort = auto_free(Dmg.sort(_runner, _def))
	add_child(_sort)
	_camera = auto_free(RtsCamera.new())
	add_child(_camera)
	_buildings = auto_free(BuildingLayer.new())
	_buildings.runner = _runner
	_buildings.world_sort = _sort
	_buildings.camera = _camera
	_buildings.reveal_enemies = reveal
	_buildings.life = _life
	_air = auto_free(AirFx.new())
	_air.runner = _runner
	_air.camera = _camera
	_air.life = _life
	_air.building_layer = _buildings
	add_child(_air)  # Connected to `ticked` first.
	add_child(_buildings)
	_buildings.set_process(false)
	_buildings._process(0.0)
	_air.set_process(false)
	_camera.position = _centre(1)
	Rig.at(_runner, 0, 0.0)


## Opens the fixture and runs one tick, so the rings follow the match before anything dies.
func _start(spawns: Array, reveal: bool = true) -> void:
	_open(spawns, [0, 0, 0, 0, 0], reveal)
	_runner.run_ticks(1)


func _kill(ids: Array) -> int:
	for id: int in ids:
		_runner.world.hp[_runner.world.index_of(id)] = 0
	_runner.run_ticks(1)
	return _runner.snapshot.tick


## The crater puffs now in the ring, as `{birth tick: true}`.
func _births_into(found: Dictionary) -> void:
	var ring: FxRing = _air.damage().ring
	for index: int in ring.count():
		if CRATER_STYLES.has(ring.puff_style(index)):
			found[roundi(ring.puff_born(index) * 15.0 / 1000.0)] = true


## Kills building 1 and plays 45 ticks, adding a building of its type on its tiles just before tick
## `place_at` (-1: none). Returns `{"died": tick, "births": {tick: true}}`.
func _scenario(place_at: int) -> Dictionary:
	_start(SPAWNS)
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[snap.index_of(1)]
	var at: Vector2i = Rig.position_of(_runner, 1)
	var died: int = _kill([1])
	var births: Dictionary = {}
	for tick: int in range(died + 1, died + 45):
		if tick == place_at:
			_runner.world.add_unit(1, type, at.x, at.y)
		_runner.run_ticks(1)
		_births_into(births)
	return {"died": died, "births": births}


func test_the_crater_source_starts_at_900_ms_and_not_for_a_site() -> void:
	_start(SPAWNS)
	var centre: Vector2 = _centre(1)
	var died: int = _kill([1])
	assert_int(_air.damage().crater_count()).is_equal(1)
	var seen: Dictionary = {}
	for tick: int in range(died + 1, died + 14):  # Up to 13 ticks, 867 ms: still falling.
		_runner.run_ticks(1)
		_births_into(seen)
	assert_int(seen.size()).is_equal(0)
	for tick: int in range(died + 14, died + 40):
		_runner.run_ticks(1)
		_births_into(seen)
	assert_int(seen.size()).is_greater(0)
	for index: int in _air.damage().ring.count():  # Over the crater, on the centre line.
		if _air.damage().ring.puff_style(index) == DamageFx.Style.CRATER_SMOKE:
			assert_float(_air.damage().ring.puff_at(index).y).is_equal_approx(centre.y, 0.01)
	_air.damage().clear()
	_runner.world.build_left[_runner.world.index_of(3)] = 100000
	_runner.run_ticks(1)  # The layer notes that building 3 is a site.
	_kill([3])
	assert_int(_air.damage().crater_count()).is_equal(0)  # A site's crater has no smoke over it.


func test_an_own_building_placed_on_a_live_source_stops_its_births_in_that_tick() -> void:
	var control: Dictionary = _scenario(-1)
	var died: int = control["died"]
	var births: Dictionary = control["births"]
	var later: Array = births.keys().filter(func(tick: int) -> bool: return tick >= died + 16)
	assert_int(later.size()).is_greater(0)
	var place_at: int = later.min()  # A tick in which the source would have puffed.
	var placed: Dictionary = _scenario(place_at)
	assert_bool(placed["births"].has(place_at)).is_false()
	for tick: int in placed["births"]:
		assert_int(tick).is_less(place_at)
	assert_int(_air.damage().crater_count()).is_equal(0)


func test_a_hidden_enemy_building_placed_on_it_stops_it_only_when_shown() -> void:
	_start(SPAWNS, false)
	var snap: MatchSnapshot = _runner.snapshot
	var type: int = snap.type_index[snap.index_of(1)]
	var at: Vector2i = Rig.position_of(_runner, 1)
	var cells: Array[Vector2i] = []  # The tiles of the crater and its surroundings.
	for y: int in 4:
		for x: int in 4:
			cells.append(Vector2i(3 + x, 3 + y))
	_kill([1])
	assert_int(_air.damage().crater_count()).is_equal(1)
	_runner.world.add_unit(2, type, at.x, at.y)
	_runner.run_ticks(1)
	assert_int(_air.damage().crater_count()).is_equal(1)  # Hidden: the smoke goes on.
	Buildings.see(_runner.snapshot, 1, cells)
	_runner.ticked.emit(_runner.snapshot.tick)  # The fog opens over it; the real sim would not.
	assert_int(_air.damage().crater_count()).is_equal(0)  # Shown: it stops in that tick.


func test_without_collapse_slots_the_crater_and_its_smoke_still_stand() -> void:
	_start(SPAWNS)
	_life.collapse_max = 0
	_buildings.decals.crater_texture = ImageTexture.create_from_image(
		Image.create(8, 4, false, Image.FORMAT_RGBA8)
	)
	var node: Node2D = _buildings.building(1)
	_kill([1])
	assert_int(_buildings.collapse().count()).is_equal(0)  # No sequence,
	assert_object(node.get_parent()).is_null()  # the node goes at once,
	assert_int(_buildings.decals.crater_count()).is_equal(1)  # the crater is laid,
	assert_int(_air.damage().crater_count()).is_equal(1)  # and it smokes.
