extends GdUnitTestSuite
## The life budget on the base arena (plan P146, ADR 0027 sections 3, 4 and 9).
## `data/scenarios/perf_bases.tres` (150 mobile rows, 28 buildings of both factions, both strikes
## inside 900 ticks: the scenario the perf arena runs on the phone) is played for 900 ticks in SYNC
## under the main scene's view layers (WorldSort, UnitLayer, BuildingLayer, GhostMemoryLayer) plus
## LifeFx, every enemy shown as in the perf arena, with four `_process` calls per tick (alpha 0,
## 0.25, 0.5, 0.75) at the 60 fps frame delta and the camera framed as the arena frames it. A second
## run of the same arena has `reduced` on. What is judged is counted, never timed: nodes and
## objects, sprite writes, ring slots, quads and textures. The numbers are printed as `LIFE BUDGET`
## lines, which the PR quotes.

const PATH: String = "res://data/scenarios/perf_bases.tres"
const LIFE_DATA: String = "res://data/life_settings.tres"
const SEED: int = 42
const TICKS: int = 900
const WARM_TICKS: int = 60
## The frame delta at 60 fps: the hulls turn at their rate per frame (a 0 would not turn).
const FRAME_S: float = 1.0 / 60.0
const ALPHAS: Array[float] = [0.0, 0.25, 0.5, 0.75]
## ADR 0027 section 9: the sprite writes a frame may make for life, on average and in any frame.
const AVERAGE_WRITES: int = 60
const WORST_WRITES: int = 150
## A frame in `DRAW_EVERY` ticks is drawn by the engine, to compare the plan with the draw.
const DRAW_EVERY: int = 25
## Objects a rig holds besides its nodes: its Idle, its Pose, its damage Parts and one spare.
const RIG_REFS: int = 4
const MOBILE_ROWS: int = 150
const BUILDING_ROWS: int = 28

var _root: Node2D
var _runner: MatchRunner
var _camera: RtsCamera
var _decals: DecalLayer
var _sort: WorldSort
var _units: UnitLayer
var _buildings: BuildingLayer
var _ghosts: GhostMemoryLayer
var _fx: LifeFx
var _life: LifeSettings
var _full: Pass
var _reduced: Pass
var _mobile_rows: int = 0
var _building_rows: int = 0
var _mobile_owners: Dictionary = {}  ## Owners of the mobile / the building rows at the start.
var _building_owners: Dictionary = {}
var _rig_nodes: int = 0  ## Nodes of the largest rig (a vehicle's: with Scar and Loose, 6).
var _anim_nodes: int = 0  ## `Anim` sprites in the sorted world / animated buildings at the end.
var _anim_entries: int = 0
var _frames_drawn: int = 0
var _draw_mismatches: int = 0
var _quads_drawn: int = 0  ## Quads the sampled frames painted, so the comparison is not vacuous.
var _life_paths: Array[String] = []  ## The texture files of GroundFx, StrikeFx and AirFx.


## What one run measured.
class Pass:
	extends RefCounted
	var label: String = ""
	var frames: int = 0
	var writes_total: int = 0
	var writes_max: int = 0
	var units_writes_max: int = 0  ## The most the unit layer / the building layer wrote in a frame.
	var buildings_writes_max: int = 0
	var ambient_max: int = 0  ## The most slots AirFx held (its ambient ring).
	var dust_max: int = 0  ## GroundFx's.
	var strike_slots_max: int = 0  ## StrikeFx's.
	var kicks_units_max: int = 0  ## The most kicks running in the unit / the building layer.
	var kicks_buildings_max: int = 0
	var quads_max: int = 0  ## The most quads AirFx's ambient ring planned in a frame.
	var ground_max: int = 0  ## GroundFx's.
	var strike_quads_max: int = 0  ## StrikeFx's.
	var items_max: int = 0  ## The most quads of all the layers of LifeFx in a frame.
	var nodes_lo: int = 1 << 30
	var nodes_hi: int = 0
	var objects_lo: int = 1 << 30
	var objects_hi: int = 0
	var prev_rigs: int = -1
	var prev_nodes: int = 0
	var prev_objects: int = 0
	var rigs_new: int = 0  ## Rigs made after the warm-up (a spawned unit finds none in the pool).
	var unexplained_nodes: int = 0  ## Ticks the node count moved with no rig made.
	var unexplained_objects: int = 0
	var strike_parts: int = 0  ## Bit p set: StrikeFx drew a quad of `StrikeFx.Part` p.
	var net_fall_seen: bool = false  ## A frame where a net was falling (scaled above 1).

	func average() -> float:
		return float(writes_total) / float(maxi(frames, 1))

	func line() -> String:
		return (
			(
				"LIFE BUDGET %s frames=%d writes avg=%.1f max=%d total=%d "
				% [label, frames, average(), writes_max, writes_total]
			)
			+ (
				"layer_writes units_max=%d buildings_max=%d "
				% [units_writes_max, buildings_writes_max]
			)
			+ (
				"slots ambient=%d dust=%d strike=%d kicks_units=%d kicks_buildings=%d "
				% [ambient_max, dust_max, strike_slots_max, kicks_units_max, kicks_buildings_max]
			)
			+ (
				"quads ambient=%d ground=%d strike=%d items_max=%d "
				% [quads_max, ground_max, strike_quads_max, items_max]
			)
			+ (
				"nodes=%d..%d objects=%d..%d rigs_new=%d strike_parts=%d"
				% [nodes_lo, nodes_hi, objects_lo, objects_hi, rigs_new, strike_parts]
			)
		)


func before() -> void:
	_life = _fresh_life()
	_open()
	_mobile_rows = _count_rows(true)
	_building_rows = _count_rows(false)
	_full = await _play("full")
	_measure_rigs()
	_life_paths = [
		_fx.ground.texture().resource_path,
		_fx.strike.texture().resource_path,
		_fx.air.texture().resource_path,
	]
	_close()
	_life = _fresh_life()
	_life.reduced = true  # The same arena with the life effects off (ADR 0027 section 3).
	_open()
	_reduced = await _play("reduced")
	_close()
	print(_full.line())
	print(_reduced.line())
	print("LIFE BUDGET rig_nodes=%d anim_nodes=%d" % [_rig_nodes, _anim_nodes])


func after() -> void:
	_close()


func _fresh_life() -> LifeSettings:
	return (load(LIFE_DATA) as LifeSettings).duplicate() as LifeSettings


func _close() -> void:
	CommandQueue.clear()
	if is_instance_valid(_root):
		_root.free()
	if is_instance_valid(_runner):
		_runner.free()


func _open() -> void:
	var scenario: ScenarioDef = load(PATH) as ScenarioDef
	_runner = MatchRunner.new()
	_runner.scenario = scenario
	_runner.match_seed = SEED
	_runner.paused = true
	_runner.start()
	_root = Node2D.new()
	add_child(_root)
	_camera = RtsCamera.new()
	_root.add_child(_camera)
	_camera.zoom = Vector2.ONE * 0.75  # The perf arena's start zoom.
	_camera.position = IsoProjection.cell_centre_px(
		scenario.camera_start_tile.x, scenario.camera_start_tile.y
	)
	_decals = DecalLayer.new()
	_root.add_child(_decals)
	_sort = WorldSort.new()
	_sort.runner = _runner
	_sort.bake_scale = 1.0
	_root.add_child(_sort)
	_units = UnitLayer.new()
	_units.runner = _runner
	_units.camera = _camera
	_units.world_sort = _sort
	_units.life = _life
	_units.reveal_enemies = true
	_root.add_child(_units)
	_buildings = BuildingLayer.new()
	_buildings.runner = _runner
	_buildings.camera = _camera
	_buildings.world_sort = _sort
	_buildings.decals = _decals
	_buildings.life = _life
	_buildings.reveal_enemies = true
	_root.add_child(_buildings)
	_ghosts = GhostMemoryLayer.new()
	_ghosts.runner = _runner
	_ghosts.world_sort = _sort
	_ghosts.building_layer = _buildings
	_ghosts.reveal_enemies = true
	_root.add_child(_ghosts)
	_fx = LifeFx.new()
	_fx.runner = _runner
	_fx.camera = _camera
	_fx.life = _life
	_fx.reveal_enemies = true
	_fx.building_layer = _buildings
	_fx.unit_layer = _units
	_root.add_child(_fx)
	for node: Node in [_sort, _units, _buildings, _ghosts, _fx.ground, _fx.strike, _fx.air]:
		node.set_process(false)  # The test calls every `_process` itself, four times a tick.
	_sort.sync()


# The nodes of the largest rig, and the `Anim` sprites against the buildings whose sheet has one.
func _measure_rigs() -> void:
	for row: int in _runner.snapshot.unit_count():
		var rig: Node2D = _units.rig(row)
		if rig != null:
			_rig_nodes = maxi(_rig_nodes, rig.find_children("*", "", true, false).size() + 1)
	for node: Node in _sort.find_children(BuildingAnims.ANIM_NODE, "Sprite2D", true, false):
		_anim_nodes += 1
	for id: int in _buildings._entries:
		var entry: BuildingLayer.Entry = _buildings._entries[id]
		_anim_entries += (
			1 if entry.sheet != null and entry.sheet.has_part(BuildingAnims.ANIM) else 0
		)


# The mobile rows (speed above 0) or the building rows of the match at the start.
func _count_rows(mobile: bool) -> int:
	var snap: MatchSnapshot = _runner.snapshot
	var found: int = 0
	for row: int in snap.unit_count():
		var type: int = snap.type_index[row]
		if mobile and snap.type_speed[type] > 0:
			found += 1
			_mobile_owners[snap.owner[row]] = true
		elif not mobile and snap.type_foot_w[type] > 0:
			found += 1
			_building_owners[snap.owner[row]] = true
	return found


# Plays the arena for `TICKS` ticks, four frames each and one engine frame after them.
func _play(label: String) -> Pass:
	var made: Pass = Pass.new()
	made.label = label
	for tick: int in TICKS:
		_runner.run_ticks(1)
		for alpha: float in ALPHAS:
			_frame(alpha, made)
		await get_tree().process_frame  # The engine's frame: it draws and frees what was queued.
		if tick % DRAW_EVERY == DRAW_EVERY - 1:
			_compare_draw()
		if tick >= WARM_TICKS:
			_count_nodes(made)
	return made


# The node and object counts after a tick: they move only when a rig is made (a unit spawned).
func _count_nodes(made: Pass) -> void:
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var rigs: int = _units.rigs_made()
	if made.prev_rigs >= 0:
		if rigs == made.prev_rigs:
			made.unexplained_nodes += 1 if nodes != made.prev_nodes else 0
			made.unexplained_objects += 1 if objects != made.prev_objects else 0
		else:
			made.rigs_new += rigs - made.prev_rigs
	made.prev_rigs = rigs
	made.prev_nodes = nodes
	made.prev_objects = objects
	made.nodes_lo = mini(made.nodes_lo, nodes)
	made.nodes_hi = maxi(made.nodes_hi, nodes)
	made.objects_lo = mini(made.objects_lo, objects)
	made.objects_hi = maxi(made.objects_hi, objects)


# One frame at `alpha`: every layer's `_process` in the main scene's tree order, then the counts.
func _frame(alpha: float, made: Pass) -> void:
	_runner._micro_ticks = roundi(alpha * float(MatchRunner.MICRO_TICKS_PER_TICK))
	var before_units: int = _units.life_writes()
	var before_buildings: int = _buildings.life_writes()
	_fx.ground._process(FRAME_S)
	_fx.strike._process(FRAME_S)
	_fx.air._process(FRAME_S)
	_units._process(FRAME_S)
	_buildings._process(FRAME_S)
	_ghosts._process(FRAME_S)
	var by_units: int = _units.life_writes() - before_units
	var by_buildings: int = _buildings.life_writes() - before_buildings
	var spent: int = by_units + by_buildings
	made.frames += 1
	made.writes_total += spent
	made.writes_max = maxi(made.writes_max, spent)
	made.units_writes_max = maxi(made.units_writes_max, by_units)
	made.buildings_writes_max = maxi(made.buildings_writes_max, by_buildings)
	var air: AirFx = _fx.air
	made.ambient_max = maxi(made.ambient_max, air.slot_count())
	made.dust_max = maxi(made.dust_max, _fx.ground.slot_count())
	made.strike_slots_max = maxi(made.strike_slots_max, _fx.strike.slot_count())
	made.kicks_units_max = maxi(made.kicks_units_max, _units.kick_count())
	made.kicks_buildings_max = maxi(made.kicks_buildings_max, _buildings.kick_count())
	if _fx.strike.net_count() > 0 and _fx.strike.net_scale(0) > 1.0:
		made.net_fall_seen = true
	for index: int in _fx.strike.quad_count():
		made.strike_parts |= 1 << _fx.strike.quad_part(index)
	var ground: int = _fx.ground.quad_count()
	var strike: int = _fx.strike.quad_count()
	var rings: int = (
		air.damage().ring.quad_count()
		+ air.hits().ring.quad_count()
		+ air.collapses().ring.quad_count()
	)
	made.quads_max = maxi(made.quads_max, air.quad_count())
	made.ground_max = maxi(made.ground_max, ground)
	made.strike_quads_max = maxi(made.strike_quads_max, strike)
	made.items_max = maxi(made.items_max, ground + strike + air.quad_count() + rings)


# Compares what each layer planned in the last frame with what the engine painted.
func _compare_draw() -> void:
	_frames_drawn += 1
	var air: AirFx = _fx.air
	if _fx.ground.drawn_quads() != _fx.ground.quad_count():
		_draw_mismatches += 1
	if _fx.strike.drawn_quads() != _fx.strike.quad_count():
		_draw_mismatches += 1
	if air.drawn_quads() != air.quad_count():
		_draw_mismatches += 1
	_quads_drawn += air.drawn_quads() + _fx.ground.drawn_quads() + _fx.strike.drawn_quads()


func test_the_arena_is_150_mobile_rows_and_28_buildings() -> void:
	assert_int(_mobile_rows).is_equal(MOBILE_ROWS)
	assert_int(_building_rows).is_equal(BUILDING_ROWS)
	assert_int(_full.frames).is_equal(TICKS * ALPHAS.size())
	assert_array(_mobile_owners.keys()).contains_exactly_in_any_order([1, 2])  # Both factions.
	assert_array(_building_owners.keys()).contains_exactly_in_any_order([1, 2])


func test_every_animated_building_has_its_anim_node() -> void:
	assert_int(_anim_entries).is_greater(0)
	assert_int(_anim_nodes).is_equal(_anim_entries)


func test_nodes_and_objects_are_flat_after_the_warm_up() -> void:
	# A count moves only when a rig is made (a unit the queues spawned finds none in the pool).
	for run: Pass in [_full, _reduced]:
		assert_int(run.unexplained_nodes).is_equal(0)
		assert_int(run.unexplained_objects).is_equal(0)
		assert_int(run.nodes_hi - run.nodes_lo).is_less_equal(run.rigs_new * _rig_nodes)
		assert_int(run.objects_hi - run.objects_lo).is_less_equal(
			run.rigs_new * (_rig_nodes + RIG_REFS)
		)


func test_life_writes_stay_at_sixty_on_average_and_one_fifty_in_any_frame() -> void:
	for run: Pass in [_full, _reduced]:
		assert_float(run.average()).is_less_equal(float(AVERAGE_WRITES))
		assert_int(run.writes_max).is_less_equal(WORST_WRITES)
	assert_int(_full.writes_total).is_greater(0)


func test_every_kind_stays_within_its_quota() -> void:
	for run: Pass in [_full, _reduced]:
		assert_int(run.dust_max).is_less_equal(_life.dust_slots)
		assert_int(run.strike_slots_max).is_less_equal(_life.strike_slots)
		assert_int(run.ambient_max).is_less_equal(_life.emitter_slots)
		assert_int(run.kicks_units_max).is_less_equal(_life.kick_slots)
		assert_int(run.quads_max).is_less_equal(_life.emitter_slots)
		assert_int(run.ground_max).is_less_equal(_life.dust_slots)
		assert_int(run.strike_quads_max).is_less_equal(_life.strike_slots * StrikeFx.QUADS_PER_SLOT)
	# The test is not vacuous: the full run uses each of them.
	assert_int(_full.ambient_max).is_greater(0)
	assert_int(_full.dust_max).is_greater(0)
	assert_int(_full.kicks_units_max).is_greater(0)


func test_each_life_layer_draws_from_one_texture() -> void:
	assert_array(_life_paths).is_equal(
		[LifeRegions.LIFE_ART, LifeRegions.STRIKE_ART, LifeRegions.LIFE_ART]
	)
	assert_int(_frames_drawn).is_greater(0)
	assert_int(_quads_drawn).is_greater(0)
	assert_int(_draw_mismatches).is_equal(0)  # The plan is painted one quad for one.


func test_both_strikes_draw_every_part_of_their_launch_and_fall() -> void:
	# The lance's launch and fall, the net's seed, trail, glint and lattice: every part drew.
	assert_int(_full.strike_parts).is_equal((1 << StrikeFx.Part.size()) - 1)
	assert_bool(_full.net_fall_seen).is_true()  # The net came down (scaled above 1) in a frame.


func test_reduced_takes_the_writes_and_the_quads_down() -> void:
	assert_int(_reduced.frames).is_equal(_full.frames)
	assert_int(_reduced.writes_total).is_less(_full.writes_total)
	assert_int(_reduced.writes_max).is_less_equal(_full.writes_max)
	assert_int(_full.ground_max).is_greater(0)
	assert_int(_full.quads_max).is_greater(0)
	assert_int(_reduced.ground_max).is_equal(0)  # No dust.
	assert_int(_reduced.quads_max).is_equal(0)  # No smoke, steam or flame.
	assert_int(_reduced.dust_max).is_equal(0)
	assert_int(_reduced.ambient_max).is_equal(0)
	assert_int(_reduced.items_max).is_less(_full.items_max)
