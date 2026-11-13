extends GdUnitTestSuite
## The life budget on the base arena (plan P146, ADR 0027 sections 3, 4 and 9) and the damage
## budget on it (plan P162, ADR 0028 section 8, ADR 0029 sections 6 to 13).
## `data/scenarios/perf_bases.tres` (150 mobile rows, 28 buildings of both factions, both strikes
## inside 900 ticks: the scenario the perf arena runs on the phone) is played in SYNC under the main
## scene's view layers plus LifeFx, every enemy shown as in the perf arena, four `_process` calls
## per tick (alpha 0, 0.25, 0.5, 0.75) at the 60 fps frame delta, the camera framed as the arena
## frames it. Passes on the first match, in `before`: FULL (900 ticks as the arena plays); HP40 and
## HP20 (every building and vehicle row's hp set to that part of its max before each tick; the sim
## is not judged); a settled TAIL (frames with no tick); RESTORE (40 %); IN_STEP (20 % and one move
## order for every vehicle, so the hulls turn together); ASSAULT (every mobile row attack-moves);
## HEAL (100 %); COLLAPSE (ten buildings die in one tick, the rest drop to 20 %); FLIP (`reduced`
## on in a running match). A second run has `reduced` on. The damage stage writes are the changes
## of a shown stage, costed with `BuildingDamage.cost` and `VehicleDamage.cost`, and the collapses'
## (the layers keep one counter for all of them).
## What is judged is counted, never timed. The numbers are printed as `LIFE BUDGET` lines.

const SortedTextures: GDScript = preload("res://tests/view/support/sorted_textures.gd")
const PATH: String = "res://data/scenarios/perf_bases.tres"
const LIFE_DATA: String = "res://data/life_settings.tres"
const SEED: int = 42
const TICKS: int = 900
const WARM_TICKS: int = 60
const PASS_TICKS: int = 45
const STEP_TICKS: int = 60
const ASSAULT_TICKS: int = 450
const FALL_TICKS: int = 75
const CRAFTED_WARM: int = 15
## A tick takes milliseconds: a run that makes no progress for this long is stuck in a loop of a
## layer, and the watchdog ends the process (a failing exit) instead of letting it wait for ever.
const STALL_MSEC: int = 30000
const TAIL_FRAMES: int = 32
const FLIP_TICKS: int = 8
const KILLED: int = 10
const FAR_MILLI: int = 2000
## The frame delta at 60 fps: the hulls turn at their rate per frame (a 0 would not turn).
const FRAME_S: float = 1.0 / 60.0
const ALPHAS: Array[float] = [0.0, 0.25, 0.5, 0.75]
## ADR 0027 section 9: the sprite writes a frame may make for life, on average and in any frame.
const AVERAGE_WRITES: int = 60
const WORST_WRITES: int = 150
const BUILDING_STAGE_WRITES: int = 20
const VEHICLE_STAGE_WRITES: int = 40
const PAGE_BUDGET_PX: int = 3584
## The AirFx quads of a frame (its ambient quads and the four rings'), ADR 0029 section 13: the
## quotas 80 + 80 + 16 + 40 + 24 (P149's puff ring).
const AIR_ITEMS: int = 240
## The most a frame of the settled tail may write: idle sweeps and animations only.
const TAIL_WRITES: int = 10
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
var _beat: int = 0  ## Counts the ticks and frames played; the watchdog thread reads it.
var _watching: bool = false
var _watch: Thread
var _fx: LifeFx
var _life: LifeSettings
var _full: Pass
var _reduced: Pass
var _hp40: Pass
var _hp20: Pass
var _tail: Pass
var _restore: Pass
var _in_step: Pass
var _flip: Pass
var _heal: Pass
var _assault_pass: Pass
var _collapse: Pass
var _vehicles: int = 0
var _sorted_textures: int = 0  ## The distinct textures the sprites of WorldSort / the ghosts hold.
var _sorted_is_atlas: bool = false
var _atlas_unchanged: bool = false
var _start_texture: Texture2D
var _fx_items: int = 0  ## CanvasItems under LifeFx when the match opened / after the passes.
var _fx_items_end: int = 0
var _ring_sizes: Array[int] = []  ## The slots of the damage, hit, collapse and puff rings.
var _killed: Array = []  ## The nodes of the buildings the COLLAPSE pass kills.
var _died_tick: int = -1
var _freed_tick: int = -1  ## The first tick every killed node was gone.
var _ambient_before: int = 0  ## Slots before / after `reduced` is switched on in a running match.
var _dust_before: int = 0
var _ambient_after: int = -1
var _dust_after: int = -1
var _page_px: Vector2i = Vector2i.ZERO
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
	var stage_b_max: int = 0  ## The most damage stage writes the buildings / the vehicles made.
	var stage_v_max: int = 0
	var stage_b_total: int = 0
	var stage_v_total: int = 0
	var inconsistent: int = 0  ## Frames where the stage writes exceeded the layer's own counter.
	var turned_max: int = 0  ## The most damaged hulls that changed frame in one frame.
	var dmg_ring_max: int = 0  ## The most puffs the damage / hit / collapse ring held.
	var hit_ring_max: int = 0
	var collapse_ring_max: int = 0
	var puff_ring_max: int = 0  ## The most slots the puff ring held.
	var collapses_max: int = 0  ## The most collapses running at once.
	var collapse_end: int = 0  ## Collapses still running when the pass ended.
	var craters_max: int = 0  ## The most crater sources alive.
	var air_items_max: int = 0  ## The most AirFx quads (ambient and the four rings) in a frame.
	var hitscan_shots: int = 0  ## SHOTs of a speed-0 weapon at a building.
	var hitscan_damage: int = 0  ## Buildings only hitscan shots hit in a tick, whose hp fell.
	var prev_sig: int = 0  ## Collapses running x 100 + hidden, at the last tick.

	func average() -> float:
		return float(writes_total) / float(maxi(frames, 1))

	func line() -> String:
		var fields: Dictionary = {
			"frames": frames,
			"writes_avg": "%.1f" % average(),
			"writes_max": writes_max,
			"writes_total": writes_total,
			"units_max": units_writes_max,
			"buildings_max": buildings_writes_max,
			"ambient": ambient_max,
			"dust": dust_max,
			"strike": strike_slots_max,
			"kicks_units": kicks_units_max,
			"kicks_buildings": kicks_buildings_max,
			"quads_ambient": quads_max,
			"quads_ground": ground_max,
			"quads_strike": strike_quads_max,
			"items_max": items_max,
			"nodes": "%d..%d" % [nodes_lo, nodes_hi],
			"objects": "%d..%d" % [objects_lo, objects_hi],
			"rigs_new": rigs_new,
			"unexplained": "%d/%d" % [unexplained_nodes, unexplained_objects],
			"strike_parts": strike_parts,
			"stage_b_max": stage_b_max,
			"stage_v_max": stage_v_max,
			"turned_max": turned_max,
			"ring_dmg": dmg_ring_max,
			"ring_hit": hit_ring_max,
			"ring_collapse": collapse_ring_max,
			"collapses_max": collapses_max,
			"craters_max": craters_max,
			"air_items_max": air_items_max,
			"hitscan": "%d/%d" % [hitscan_shots, hitscan_damage],
		}
		var text: String = "LIFE BUDGET %s" % label
		for key: String in fields:
			text += " %s=%s" % [key, fields[key]]
		return text


## The stages the layers showed after the last frame, to cost the changes of the next.
class Stages:
	extends RefCounted
	var building: Dictionary[int, int] = {}
	var anim_off: Dictionary[int, bool] = {}
	var vehicle: Dictionary[int, int] = {}
	var hull_dir: Dictionary[int, int] = {}
	var collapse_state: Dictionary[int, int] = {}
	var collapse_step: Dictionary[int, int] = {}
	var turned: int = 0  ## Damaged hulls (a stage above 0) that changed frame since the last call.


func before() -> void:
	_start_watchdog()
	_life = _fresh_life()
	_open()
	_mobile_rows = _count_rows(true)
	_building_rows = _count_rows(false)
	_full = await _play("full", TICKS, WARM_TICKS, 0, 0)
	_measure_rigs()
	_hp40 = await _play("hp40", PASS_TICKS, CRAFTED_WARM, 40, 0)
	_hp20 = await _play("hp20", PASS_TICKS, CRAFTED_WARM, 20, 0)
	_vehicles = _count_vehicles()
	_tail = _settled_tail("tail", TAIL_FRAMES)
	_restore = await _play("restore", PASS_TICKS, CRAFTED_WARM, 40, 0)
	_in_step = await _play("in_step", STEP_TICKS, CRAFTED_WARM, 20, 1)
	_assault_pass = await _play("assault", ASSAULT_TICKS, 0, 0, 3)
	_heal = await _play("heal", PASS_TICKS, CRAFTED_WARM, 100, 0)  # Every stage back to 0.
	_collapse = await _play("collapse", FALL_TICKS, 0, 0, 2)
	_collapse.collapse_end = _buildings.collapse().count()
	for ring: FxRing in _rings_of(_fx.air):
		_ring_sizes.append(ring._size)
	_flip = await _play("flip", FLIP_TICKS, FLIP_TICKS, 0, 5)
	_ambient_after = _fx.air.slot_count()
	_dust_after = _fx.ground.slot_count()
	_life.reduced = false
	_collect_textures()
	_fx_items_end = _fx.find_children("*", "CanvasItem", true, false).size()
	_life_paths = [
		_fx.ground.texture().resource_path,
		_fx.strike.texture().resource_path,
		_fx.air.texture().resource_path,
	]
	_close()
	_life = _fresh_life()
	_life.reduced = true  # The same arena with the life effects off (ADR 0027 section 3).
	_open()
	_reduced = await _play("reduced", TICKS, WARM_TICKS, 0, 0)
	_close()
	_stop_watchdog()
	for run: Pass in _damage_passes() + [_reduced]:
		print(run.line())
	print(
		(
			"LIFE BUDGET freed_ticks=%d reduced_switch ambient %d->%d dust %d->%d"
			% [_freed_tick - _died_tick, _ambient_before, _ambient_after, _dust_before, _dust_after]
		)
	)
	print("LIFE BUDGET page=%dx%d vehicles=%d" % [_page_px.x, _page_px.y, _vehicles])


func after() -> void:
	_stop_watchdog()
	_close()


func _start_watchdog() -> void:
	_watching = true
	_watch = Thread.new()
	_watch.start(_watchdog)


func _stop_watchdog() -> void:
	_watching = false
	if _watch != null and _watch.is_started():
		_watch.wait_to_finish()


# Runs on its own thread. Hang guard only; never affects results; exit 137 is intended.
func _watchdog() -> void:
	var last: int = -1
	var since: int = Time.get_ticks_msec()
	while _watching:
		OS.delay_msec(1000)
		if _beat != last:
			last = _beat
			since = Time.get_ticks_msec()
		elif Time.get_ticks_msec() - since >= STALL_MSEC:
			push_error("test_life_budget: no progress for %d ms, a layer loops" % STALL_MSEC)
			OS.kill(OS.get_process_id())


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
	_fx_items = _fx.find_children("*", "CanvasItem", true, false).size()
	_sort.sync()
	_page_px = _sort.atlas.page_px()
	_start_texture = _sort.atlas.texture()


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


# Plays `ticks` ticks, four frames each and one engine frame after them. `hp_percent` above 0 sets
# the hp of every building and vehicle row to that part of its max before each tick; `extra` 1
# sends every vehicle on one move order at the start, 2 kills `KILLED` buildings, 3 sends the
# vehicles of each side against the buildings of the other.
func _play(label: String, ticks: int, warm: int, hp_percent: int, extra: int) -> Pass:
	var made: Pass = Pass.new()
	made.label = label
	var stages: Stages = Stages.new()
	_note_stages(stages)  # The stages the pass starts from.
	for tick: int in ticks:
		_beat += 1
		if hp_percent > 0:
			_set_hp(hp_percent)
		if tick == 0:
			_order(extra)
		var hp_before: Dictionary[int, int] = _building_hp()
		_runner.run_ticks(1)
		if tick == 0 and extra == 2:
			_died_tick = _runner.snapshot.tick
		made.hitscan_shots += _hitscan_at_buildings()
		made.hitscan_damage += _hitscan_damage(hp_before)
		for alpha: float in ALPHAS:
			_beat += 1
			_frame(alpha, made, stages)
		await get_tree().process_frame  # The engine's frame: it draws and frees what was queued.
		if tick % DRAW_EVERY == DRAW_EVERY - 1:
			_compare_draw()
		_note_freed()
		if tick >= warm:
			_count_nodes(made)
	return made


# The frames of a pass with no tick, no order and no hp change: the snapshot stands still.
func _settled_tail(label: String, frames: int) -> Pass:
	var made: Pass = Pass.new()
	made.label = label
	var stages: Stages = Stages.new()
	_note_stages(stages)
	for frame: int in frames:
		_frame(ALPHAS[frame % ALPHAS.size()], made, stages)
	return made


# Notes the first tick at which every node of the killed buildings is gone.
func _note_freed() -> void:
	if _freed_tick >= 0 or _killed.is_empty():
		return
	for node: Variant in _killed:
		if is_instance_valid(node):
			return
	_freed_tick = _runner.snapshot.tick


# The hp of every building of the published snapshot, by id.
func _building_hp() -> Dictionary[int, int]:
	var snap: MatchSnapshot = _runner.snapshot
	var found: Dictionary[int, int] = {}
	for row: int in snap.unit_count():
		if snap.type_foot_w[snap.type_index[row]] > 0:
			found[snap.unit_id[row]] = snap.hp[row]
	return found


# The buildings that a hitscan SHOT of this tick hit, that no shell hit in it (no IMPACT at it and
# no shell fired at it), and whose hp fell since `before`: only the hitscan shot can have done it.
func _hitscan_damage(before: Dictionary[int, int]) -> int:
	var snap: MatchSnapshot = _runner.snapshot
	var speeds: PackedInt32Array = snap.weapon_projectile_speed
	var events: PackedInt32Array = snap.events
	var hitscan: Dictionary[int, bool] = {}
	var shells: Dictionary[int, bool] = {}
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		var kind: int = events[at]
		if kind == World.Event.IMPACT:
			shells[events[at + 4]] = true
		elif kind == World.Event.SHOT:
			var weapon: int = events[at + 5]
			if weapon >= 0 and weapon < speeds.size() and speeds[weapon] == 0:
				hitscan[events[at + 4]] = true
			else:
				shells[events[at + 4]] = true
	var found: int = 0
	for id: int in hitscan:
		var row: int = snap.index_of(id)
		if row >= 0 and before.has(id) and not shells.has(id) and snap.hp[row] < before[id]:
			found += 1
	return found


# The SHOTs of this tick whose weapon is a hitscan one (speed 0) and whose target is a building.
func _hitscan_at_buildings() -> int:
	var snap: MatchSnapshot = _runner.snapshot
	var speeds: PackedInt32Array = snap.weapon_projectile_speed
	var events: PackedInt32Array = snap.events
	var found: int = 0
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] != World.Event.SHOT:
			continue
		var weapon: int = events[at + 5]
		if weapon < 0 or weapon >= speeds.size() or speeds[weapon] != 0:
			continue
		var row: int = snap.index_of(events[at + 4])
		found += 1 if row >= 0 and snap.type_foot_w[snap.type_index[row]] > 0 else 0
	return found


## Costs the changes of a shown stage since the last call and remembers the stages now: x the
## buildings' writes (`BuildingDamage.cost`), y the vehicles' (`VehicleDamage.cost`).
func _note_stages(stages: Stages) -> Vector2i:
	var by_buildings: int = 0
	var by_vehicles: int = 0
	stages.turned = 0
	var live: Dictionary[int, bool] = {}
	for id: int in _buildings._entries:
		var entry: BuildingLayer.Entry = _buildings._entries[id]
		if entry.patch == null:
			continue
		live[id] = true
		if stages.building.has(id) and stages.building[id] != entry.stage_shown:
			by_buildings += BuildingDamage.cost(
				stages.building[id], entry.stage_shown, stages.anim_off[id] != entry.anim_off
			)
		stages.building[id] = entry.stage_shown
		stages.anim_off[id] = entry.anim_off
	for id: int in stages.building.keys():
		if not live.has(id):
			stages.building.erase(id)
			stages.anim_off.erase(id)
	var snap: MatchSnapshot = _runner.snapshot
	var seen: Dictionary[int, bool] = {}
	for row: int in snap.unit_count():
		var rig: UnitLayer.Rig = _units.rig(row) as UnitLayer.Rig
		if rig == null or rig.damage == null:
			continue
		var id: int = snap.unit_id[row]
		var parts: VehicleDamage.Parts = rig.damage
		seen[id] = true
		if stages.hull_dir.has(id) and stages.hull_dir[id] != parts.dir and parts.shown > 0:
			stages.turned += 1
		stages.hull_dir[id] = parts.dir
		if stages.vehicle.has(id) and stages.vehicle[id] != parts.shown:
			by_vehicles += VehicleDamage.cost(stages.vehicle[id], parts.shown, _life.damage_loose)
		stages.vehicle[id] = parts.shown
	for id: int in stages.vehicle.keys():
		if not seen.has(id):
			stages.vehicle.erase(id)
			stages.hull_dir.erase(id)
	by_buildings += _note_collapses(stages)
	return Vector2i(by_buildings, by_vehicles)


# The writes of the collapses since the last call, from the states `BuildingCollapse` keeps: the
# start when a slot leaves PENDING, a step when its step changed, the hide when it turns HIDDEN.
# They come out of the same share as the stage writes (`BuildingLayer._write_stages`).
func _note_collapses(stages: Stages) -> int:
	var writes: int = 0
	var coll: BuildingCollapse = _buildings.collapse()
	var live: Dictionary[int, bool] = {}
	for at: int in coll._n:
		var slot: int = coll._order[at]
		var id: int = coll._entry[slot].id
		var state: int = coll._state[slot]
		var step: int = coll._step[slot]
		var was: int = stages.collapse_state.get(id, BuildingCollapse.PENDING)
		if was == BuildingCollapse.PENDING and state != BuildingCollapse.PENDING:
			writes += BuildingCollapse.START_WRITES
		if step != stages.collapse_step.get(id, 0):
			writes += BuildingCollapse.STEP_WRITES
		if was != BuildingCollapse.HIDDEN and state == BuildingCollapse.HIDDEN:
			writes += BuildingCollapse.HIDE_WRITES
		stages.collapse_state[id] = state
		stages.collapse_step[id] = step
		live[id] = true
	for id: int in stages.collapse_state.keys():
		if not live.has(id):
			stages.collapse_state.erase(id)
			stages.collapse_step.erase(id)
	return writes


# Sets the hp of every building and vehicle row of the World to `percent` of its max.
func _set_hp(percent: int) -> void:
	var world: World = _runner.world
	for row: int in world.unit_id.size():
		if _is_building(row) or _is_vehicle(row):
			world.hp[row] = world.type_max_hp[world.type_index[row]] * percent / 100


func _is_building(row: int) -> bool:
	var snap: MatchSnapshot = _runner.snapshot
	return snap.type_foot_w[snap.type_index[row]] > 0 and snap.build_left[row] == 0


func _is_vehicle(row: int) -> bool:
	var rig: UnitLayer.Rig = null
	if row < _runner.snapshot.unit_count():
		rig = _units.rig(row) as UnitLayer.Rig
	return rig != null and rig.damage != null


func _count_vehicles() -> int:
	var found: int = 0
	for row: int in _runner.snapshot.unit_count():
		found += 1 if _is_vehicle(row) else 0
	return found


# What a pass does at its first tick (see `_play`).
func _order(extra: int) -> void:
	if extra == 1:
		_send_vehicles()
	elif extra == 2:
		_kill_buildings()
	elif extra == 3:
		_assault()
	elif extra == 5:  # The player's switch to reduced in a running match.
		_ambient_before = _fx.air.slot_count()
		_dust_before = _fx.ground.slot_count()
		_life.reduced = true


# One move order for every vehicle of each side towards the north-west corner of the map.
func _send_vehicles() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	for player: int in [1, 2]:
		var ids: PackedInt32Array = PackedInt32Array()
		for row: int in snap.unit_count():
			if snap.owner[row] == player and _is_vehicle(row):
				ids.append(snap.unit_id[row])
		if not ids.is_empty():
			CommandQueue.submit(Command.move(player, ids, FAR_MILLI, FAR_MILLI))


# Every mobile row of each side (tanks, squads, harvesters) attack-moves to the building of the
# other side nearest to its first one: the shots hit buildings, which then take damage stages and
# fall.
func _assault() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	for player: int in [1, 2]:
		var ids: PackedInt32Array = PackedInt32Array()
		var lead: Vector2i = Vector2i(-1, -1)
		for row: int in snap.unit_count():
			if snap.owner[row] == player and snap.type_speed[snap.type_index[row]] > 0:
				ids.append(snap.unit_id[row])
				lead = lead if lead.x >= 0 else Vector2i(snap.pos_x[row], snap.pos_y[row])
		var target: Vector2i = Vector2i(-1, -1)
		var best: int = 1 << 60
		for row: int in snap.unit_count():
			if snap.owner[row] != player and _is_building(row):
				var at: Vector2i = Vector2i(snap.pos_x[row], snap.pos_y[row])
				if best > (at - lead).length_squared():
					best = (at - lead).length_squared()
					target = at
		if target.x >= 0 and not ids.is_empty():
			CommandQueue.submit(Command.attack_move(player, ids, target.x, target.y))


# Kills `KILLED` complete buildings (not the headquarters, so the match goes on) and drops every
# other building to 20 %, so their stage writes come in the frames the collapses write in: both
# take their writes from the same 20.
func _kill_buildings() -> void:
	var world: World = _runner.world
	var killed: int = 0
	for row: int in world.unit_id.size():
		if not _is_building(row):
			continue
		var type_id: StringName = world.type_ids[world.type_index[row]]
		if killed < KILLED and type_id != &"headquarters" and type_id != &"renew_hq":
			_killed.append(_buildings.building(world.unit_id[row]))
			world.hp[row] = 0
			killed += 1
		else:
			world.hp[row] = world.type_max_hp[world.type_index[row]] * 20 / 100


# The node and object counts after a tick: they move only when a rig is made (a unit spawned).
func _count_nodes(made: Pass) -> void:
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var rigs: int = _units.rigs_made()
	# A building that dies lays a crater (a node) and a collapse that hides or ends frees nodes: the
	# collapses running and the ones hidden change on those ticks and on no other.
	var coll: BuildingCollapse = _buildings.collapse()
	var hidden: int = 0
	for at: int in coll._n:
		hidden += 1 if coll._state[coll._order[at]] == BuildingCollapse.HIDDEN else 0
	var sig: int = coll._n * 100 + hidden
	if made.prev_rigs >= 0:
		if rigs == made.prev_rigs and sig == made.prev_sig:
			made.unexplained_nodes += 1 if nodes != made.prev_nodes else 0
			made.unexplained_objects += 1 if objects != made.prev_objects else 0
		elif rigs != made.prev_rigs:
			made.rigs_new += rigs - made.prev_rigs
	made.prev_sig = sig
	made.prev_rigs = rigs
	made.prev_nodes = nodes
	made.prev_objects = objects
	made.nodes_lo = mini(made.nodes_lo, nodes)
	made.nodes_hi = maxi(made.nodes_hi, nodes)
	made.objects_lo = mini(made.objects_lo, objects)
	made.objects_hi = maxi(made.objects_hi, objects)


# One frame at `alpha`: every layer's `_process` in the main scene's tree order, then the counts.
func _frame(alpha: float, made: Pass, stages: Stages) -> void:
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
	var staged: Vector2i = _note_stages(stages)
	made.frames += 1
	made.writes_total += spent
	made.writes_max = maxi(made.writes_max, spent)
	made.stage_b_total += staged.x
	made.stage_v_total += staged.y
	made.stage_b_max = maxi(made.stage_b_max, staged.x)
	made.stage_v_max = maxi(made.stage_v_max, staged.y)
	made.turned_max = maxi(made.turned_max, stages.turned)
	if staged.x > by_buildings or staged.y > by_units:
		made.inconsistent += 1
	made.units_writes_max = maxi(made.units_writes_max, by_units)
	made.buildings_writes_max = maxi(made.buildings_writes_max, by_buildings)
	var air: AirFx = _fx.air
	made.dmg_ring_max = maxi(made.dmg_ring_max, air.damage().ring.count())
	made.hit_ring_max = maxi(made.hit_ring_max, air.hits().ring.count())
	made.collapse_ring_max = maxi(made.collapse_ring_max, air.collapses().ring.count())
	made.puff_ring_max = maxi(made.puff_ring_max, air.puffs().ring.count())
	made.collapses_max = maxi(made.collapses_max, _buildings.collapse().count())
	made.craters_max = maxi(made.craters_max, air.damage().crater_count())
	var rings: int = 0  # The quads of the damage, hit, collapse and puff rings.
	for ring: FxRing in _rings_of(air):
		rings += ring.quad_count()
	made.air_items_max = maxi(made.air_items_max, air.quad_count() + rings)
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
	made.quads_max = maxi(made.quads_max, air.quad_count())
	made.ground_max = maxi(made.ground_max, ground)
	made.strike_quads_max = maxi(made.strike_quads_max, strike)
	made.items_max = maxi(made.items_max, ground + strike + air.quad_count() + rings)


func _rings_of(air: AirFx) -> Array[FxRing]:
	return [air.damage().ring, air.hits().ring, air.collapses().ring, air.puffs().ring]


func _collect_textures() -> void:
	var atlas: Texture2D = _sort.atlas.texture()
	var sorted: Array[Texture2D] = SortedTextures.textures(_sort)
	_sorted_textures = sorted.size()
	_sorted_is_atlas = sorted.size() == 1 and sorted[0] == atlas
	_atlas_unchanged = atlas == _start_texture


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
	for ring: FxRing in _rings_of(air):
		var painted: int = 0
		for pass_of: int in FxRing.PASSES:
			painted += ring.drawn(pass_of)
		if painted != ring.quad_count():
			_draw_mismatches += 1
		_quads_drawn += painted


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


# --- The damage budget (plan P162) ---


func test_the_damage_stage_writes_stay_in_their_shares_of_a_frame() -> void:
	assert_int(_life.damage_building_writes).is_equal(BUILDING_STAGE_WRITES)
	assert_int(_life.damage_writes_per_frame - _life.damage_building_writes).is_equal(
		VEHICLE_STAGE_WRITES
	)
	# The building total holds the stage writes and the collapses' (start, steps, hide).
	for run: Pass in _damage_passes():
		assert_int(run.stage_b_max).is_less_equal(BUILDING_STAGE_WRITES)
		assert_int(run.stage_v_max).is_less_equal(VEHICLE_STAGE_WRITES)
		assert_int(run.inconsistent).is_equal(0)
	# The passes did drop the stages of buildings and vehicles: the test is not vacuous.
	for run: Pass in [_full, _hp40, _hp20, _restore, _in_step]:
		assert_int(run.stage_v_total).is_greater(0)
	# A building has a picture only at KRITISK (ADR 0034): a pass that reaches or leaves it writes
	# (`_hp20`, `_restore` 2 -> 0, `_in_step`); `_full` and `_hp40` need not.
	for run: Pass in [_hp20, _restore, _in_step]:
		assert_int(run.stage_b_total).is_greater(0)
	assert_int(_collapse.stage_b_total).is_greater(0)  # The collapses' writes.
	assert_int(_vehicles).is_greater(0)


func test_nothing_is_rewritten_when_nothing_changes() -> void:
	# A settled tail: no tick, no order and no hp change, only the frames of the interpolation.
	# A rewrite of the same stage costs 0 in the stage totals; `writes_max` below catches it.
	assert_int(_tail.frames).is_equal(TAIL_FRAMES)
	assert_int(_tail.stage_b_total).is_equal(0)
	assert_int(_tail.stage_v_total).is_equal(0)
	assert_int(_tail.writes_max).is_less_equal(TAIL_WRITES)


func test_all_life_writes_stay_inside_the_budget_in_every_damage_pass() -> void:
	for run: Pass in _damage_passes():
		assert_float(run.average()).is_less_equal(float(AVERAGE_WRITES))
		assert_int(run.writes_max).is_less_equal(WORST_WRITES)
	# The in-step pass turns damaged hulls together while their stages drop (the worst frame).
	assert_int(_in_step.turned_max).is_greater_equal(_vehicles / 2)


func test_nodes_and_objects_stay_flat_in_the_damage_passes() -> void:
	for run: Pass in [_hp40, _hp20, _restore, _in_step]:
		assert_int(run.nodes_hi - run.nodes_lo).is_equal(0)
		assert_int(run.objects_hi - run.objects_lo).is_equal(0)
	# A node changes only with a spawned rig, a fallen building's crater or a collapse's start or end.
	for run: Pass in _damage_passes():
		assert_int(run.unexplained_nodes).is_equal(0)
	# Objects too. Where shots and falling buildings run, a bare Object (not a Node or a Resource)
	# comes and goes, origin unknown: the assault pass moved 2 more than its 5 nodes in this run
	# (P195d-2, ADR 0033; no slack, the falls are not counted). The collapse pass: 1 tick.
	for run: Pass in [_full, _hp40, _hp20, _tail, _restore, _in_step, _heal, _flip]:
		assert_int(run.unexplained_objects).is_equal(0)
	var moved: int = _assault_pass.nodes_hi - _assault_pass.nodes_lo
	assert_int(_assault_pass.objects_hi - _assault_pass.objects_lo).is_less_equal(moved + 2)
	assert_int(_collapse.unexplained_objects).is_less_equal(1)


func test_the_killed_buildings_are_freed_when_their_collapse_ends() -> void:
	assert_int(_collapse.collapse_end).is_equal(0)
	assert_int(_killed.size()).is_equal(KILLED)
	for node: Variant in _killed:
		assert_bool(is_instance_valid(node)).is_false()
	# DIED plus `collapse_end_ms` of match time in ticks, and the engine frees it in its frame.
	var ticks: int = ceili(float(_life.collapse_end_ms) * float(Sim.TICK_RATE) / 1000.0)
	assert_int(_freed_tick).is_greater(0)
	assert_int(_freed_tick - _died_tick).is_less_equal(ticks)


func test_slots_and_quotas_hold_in_every_damage_pass() -> void:
	# The data of ADR 0029 section 13 (the plan's P148 row said 64 for the damage ring).
	assert_int(_life.damage_slots).is_equal(80)
	assert_int(_life.hit_slots).is_equal(16)
	assert_int(_life.collapse_slots).is_equal(40)
	assert_int(_life.collapse_max).is_equal(16)
	assert_int(_life.crater_sources).is_equal(16)
	assert_int(_life.puff_slots).is_equal(24)
	assert_array(_ring_sizes).is_equal(
		[_life.damage_slots, _life.hit_slots, _life.collapse_slots, _life.puff_slots]
	)
	for run: Pass in _damage_passes():
		assert_int(run.dmg_ring_max).is_less_equal(_life.damage_slots)
		assert_int(run.hit_ring_max).is_less_equal(_life.hit_slots)
		assert_int(run.collapse_ring_max).is_less_equal(_life.collapse_slots)
		assert_int(run.collapses_max).is_less_equal(_life.collapse_max)
		assert_int(run.craters_max).is_less_equal(_life.crater_sources)
		assert_int(run.air_items_max).is_less_equal(AIR_ITEMS)
		assert_int(run.quads_max).is_less_equal(_life.emitter_slots)
		assert_int(run.ambient_max).is_less_equal(_life.emitter_slots)
		assert_int(run.dust_max).is_less_equal(_life.dust_slots)
		assert_int(run.strike_slots_max).is_less_equal(_life.strike_slots)
		assert_int(run.kicks_units_max).is_less_equal(_life.kick_slots)
		assert_int(run.kicks_buildings_max).is_less_equal(_life.kick_slots)
	# The passes reached them: the test is not vacuous.
	assert_int(_hp20.dmg_ring_max).is_greater(0)
	assert_int(_assault_pass.hit_ring_max).is_greater(0)  # Shots hit shown buildings.
	assert_int(_assault_pass.puff_ring_max).is_between(1, _life.puff_slots)  # Shells smoke.
	assert_int(_collapse.collapse_ring_max).is_greater(0)
	assert_int(_collapse.collapses_max).is_greater(0)
	assert_int(_collapse.craters_max).is_greater(0)
	assert_int(_assault_pass.kicks_buildings_max).is_greater(0)
	# Every vehicle weapon fires a shell: the hits of the flash and chips are the rifles'.
	assert_int(_assault_pass.hitscan_shots).is_greater(0)
	assert_int(_collapse.hitscan_shots).is_greater(0)
	# And a hitscan shot hurts: a building only hitscan shots hit lost hp in that tick.
	assert_int(_assault_pass.hitscan_damage).is_greater(0)


func test_the_sorted_world_draws_from_one_texture_and_the_page_fits() -> void:
	# The ghost layer's clause (one texture, the atlas, a Damage child on a remembered stage) is
	# pinned by test_ghost_memory_layer.gd and test_building_damage_ghost.gd; this arena shows
	# every enemy, so it has no ghost records to look at.
	assert_int(_sorted_textures).is_equal(1)
	assert_bool(_sorted_is_atlas).is_true()
	assert_bool(_atlas_unchanged).is_true()  # No second bake in the run.
	assert_int(_page_px.x).is_greater(0)
	assert_int(_page_px.y).is_less_equal(PAGE_BUDGET_PX)


func test_life_fx_has_the_same_three_canvas_items_after_the_damage_passes() -> void:
	assert_int(_fx_items).is_equal(3)  # GroundFx, StrikeFx and AirFx: the rings add none.
	assert_int(_fx_items_end).is_equal(3)
	for run: Pass in _damage_passes():
		assert_int(run.items_max).is_greater(0)


func test_the_switch_to_reduced_in_a_running_match_empties_the_effects() -> void:
	assert_int(_ambient_before).is_greater(0)
	assert_int(_dust_before).is_greater(0)
	assert_int(_ambient_after).is_equal(0)
	assert_int(_dust_after).is_equal(0)


func _damage_passes() -> Array[Pass]:
	return [_full, _hp40, _hp20, _tail, _restore, _in_step, _assault_pass, _heal, _collapse, _flip]
