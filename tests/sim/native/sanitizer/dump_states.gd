extends SceneTree
## The dump step of the sanitizer job (ADR 0013 section 10, plan P57, qa-engineer). It plays the
## seed-42 perf arena through MatchLoop and, every 15 ticks (Replay.CHECKPOINT_PERIOD), writes the
## state that the native kernels read into a binary file for the C++ harness in
## native/sim_kernels/sanitizer/, which runs core/ over it under AddressSanitizer and UBSan. Nothing
## is committed: the job dumps and consumes the files in one run, so they are never stale.
##
## Run: godot --headless --path . -s res://tests/sim/native/sanitizer/dump_states.gd -- <out dir>
## Output: <out dir>/state_<tick, 5 digits>.bin, then the line "dump_states: wrote N dumps ..." and
## exit code 0; any other exit code, or no such line, is a failure (Godot can exit 0 after a script
## error, so the job reads the line). The out dir is created and its old state_*.bin files removed.
##
## This is a plain script and no GdUnitTestSuite on purpose: run-tests.sh gives gdUnit4 every .gd
## below the folders it is asked for (-a res://tests in verify.sh, -a res://tests/sim/native in the
## native-clang job), and gdUnit4 drops a script that has no GdUnitTestSuite base when it loads it,
## so this one never runs there and check-native-tests.sh (which prunes sanitizer/) never counts it.
##
## File format, little-endian, versioned by World.STATE_FORMAT (the harness refuses a number it
## does not know):
##   "RTSD", u32 World.STATE_FORMAT, u32 tick, then records until the end of the file:
##   u8 kind ('S' one int64, 'I' int32 array, 'B' byte array), u16 name length, name (ASCII),
##   u64 count (1 for 'S'), payload (count int64, int32 or bytes).
## What a kernel needs goes in under the names below; a later kernel (P37n, P39n, P41n, P42n, P46n)
## adds its records in a function of its own here and its case in native/sim_kernels/sanitizer/.
##   world.unit_count, world.flow_cells_per_tick (S), world.field, world.move_cost (I, B)
##   flow.cols, flow.rows, flow.slots (S), flow.key_goal, flow.key_class, flow.requested,
##   flow.ref_count, flow.status (I), and per slot i: flow.slot.<i>.cost, .next, .bucket_head,
##   .link_next, .link_prev (I), .pad_cost (B), .goal_cell, .move_class, .grid_cols, .cell_count,
##   .stride, .level, .pending, .complete (S).
## The INTEGRATE kernel (P37n) reads those too (world.field, world.move_cost, flow.cols, flow.rows,
## the five key columns and the cost, grid_cols, cell_count, stride and complete of each slot) and
## adds, in _write_integrate:
##   world.map_cols, .map_rows, .map_w, .map_h, .map_version, .tick, .line_check_period_ticks,
##   .stall_ticks, .stall_range_spacings, .attack_rekey_milli, flow.classes, flow.requests (S);
##   world.unit_id, .type_index, .pos_x, .pos_y, .goal_x, .goal_y, .group_cell, .order, .nav_mode,
##   .nav_cell, .nav_next, .best_dist, .stall, .intent_x, .intent_y, .push_x, .push_y,
##   .type_speed, .type_spacing, .type_move_class, flow.key_version, flow.last_used (I).
##
## Sim.step does not step FLOW yet (P37b), so nothing in the arena asks for a field. The step does
## it as test_flow_lockstep.gd does: slow, scrub and rock cells painted in, and every REQUEST_EVERY
## ticks a group of rows takes the field of the next of twelve keys, with three repaints that
## re-integrate the fields in use. FlowCache.run is the GDScript twin (no kernels attached), at
## SLICE cells a tick, so that fields are caught mid-integration. The run fails if no dump caught
## a waiting, a half integrated, a served and a re-integrating field. Once P37b lands the arena
## asks by itself and the stand-in can go.

const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
const MAGIC: String = "RTSD"
const MATCH_SEED: int = 42
const TICKS: int = 900
const DUMP_EVERY: int = 15
## Smaller than flow_cells_per_tick (512), so that a 64x64 field takes tens of ticks to integrate.
const SLICE: int = 200
const REQUEST_EVERY: int = 30
const KEYS: int = 12
const GROUPS: int = 10
const GROUP_ROWS: int = 5
const REPAINT_TICKS: Array[int] = [200, 450, 700]
## The cost per terrain (grass, sand, scrub, rock, water) and class (foot, wheeled, tracked), as
## test_flow_lockstep.gd paints them: slow sand (255 is the cap of the bucket ring), scrub for
## foot only.
const GROUND_COST: Array[int] = [10, 10, 10, 12, 41, 255, 13, 0, 0, 0, 0, 0, 0, 0, 0]
## The World members that the INTEGRATE kernel reads or writes, beyond those of the FLOW records.
const INTEGRATE_SCALARS: Array[StringName] = [
	&"map_cols",
	&"map_rows",
	&"map_w",
	&"map_h",
	&"map_version",
	&"tick",
	&"line_check_period_ticks",
	&"stall_ticks",
	&"stall_range_spacings",
	&"attack_rekey_milli"
]
const INTEGRATE_COLUMNS: Array[StringName] = [
	&"unit_id",
	&"type_index",
	&"pos_x",
	&"pos_y",
	&"goal_x",
	&"goal_y",
	&"group_cell",
	&"order",
	&"nav_mode",
	&"nav_cell",
	&"nav_next",
	&"best_dist",
	&"stall",
	&"intent_x",
	&"intent_y",
	&"push_x",
	&"push_y",
	&"type_speed",
	&"type_spacing",
	&"type_move_class"
]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0].is_empty():
		printerr(
			"dump_states: usage: -s res://tests/sim/native/sanitizer/dump_states.gd -- <out dir>"
		)
		quit(2)
		return
	quit(_run(args[0]))


## Plays the arena and writes the dumps; returns the exit code.
@warning_ignore("integer_division")
func _run(out_dir: String) -> int:
	if DirAccess.make_dir_recursive_absolute(out_dir) != OK:
		printerr("dump_states: cannot create %s" % out_dir)
		return 2
	for old: String in DirAccess.get_files_at(out_dir):
		if old.begins_with("state_") and old.ends_with(".bin"):
			DirAccess.remove_absolute(out_dir.path_join(old))
	var world: World = MatchScript.world(MATCH_SEED)
	var rng: DetRandom = DetRandom.create(MATCH_SEED, 9)
	world.terrain_cost = PackedByteArray(GROUND_COST)
	var cells: int = world.map_cols * world.map_rows
	for _paint: int in cells / 10:
		world.set_terrain(rng.next_int(cells), rng.next_int(5))
	var loop: MatchLoop = MatchScript.loop(world, MATCH_SEED)
	var keys: Array[Vector2i] = _keys(cells)
	var repaints: Array[Vector2i] = []
	for _tick: int in REPAINT_TICKS:
		repaints.append(Vector2i(rng.next_int(cells), 3))
	var seen: Dictionary[String, int] = {"waiting": 0, "half": 0, "served": 0, "again": 0}
	var written: int = 0
	for tick: int in TICKS:
		loop.step(world, MatchScript.commands_at(world.tick))
		if tick % REQUEST_EVERY == 0:
			var request: int = tick / REQUEST_EVERY
			_take_field(world, request % GROUPS, keys[request % KEYS])
		if tick in REPAINT_TICKS:
			var paint: Vector2i = repaints[REPAINT_TICKS.find(tick)]
			world.set_terrain(paint.x, paint.y)
		if world.tick % DUMP_EVERY == 0:
			# The state the FLOW call of this tick would find.
			var path: String = out_dir.path_join("state_%05d.bin" % world.tick)
			if not _write(world, path):
				printerr("dump_states: cannot write %s" % path)
				return 1
			written += 1
			_count(world.flow, seen)
		FlowCache.run(world, SLICE)
	print("dump_states: wrote %d dumps to %s (%s)" % [written, out_dir, seen])
	for kind: String in seen:
		if seen[kind] == 0:
			printerr("dump_states: FAIL no dump caught a %s field" % kind)
			return 1
	return 0


## The twelve keys (goal cell, move class): the first two in opposite corners, whose fields cross
## the whole map.
func _keys(cells: int) -> Array[Vector2i]:
	var rng: DetRandom = DetRandom.create(MATCH_SEED, 7)
	var keys: Array[Vector2i] = []
	for key: int in KEYS:
		keys.append(Vector2i(rng.next_int(cells), key % 3))
	keys[0] = Vector2i(0, keys[0].y)
	keys[1] = Vector2i(cells - 1, keys[1].y)
	return keys


## The rows of `group` leave their fields and take the field of `key`, or -1 when every slot is
## referenced. Group 0 holds the last rows of the World, group 1 the rows before them and so on.
func _take_field(world: World, group: int, key: Vector2i) -> void:
	var first: int = 0
	if group < GROUPS - 1:
		first = maxi(world.unit_count() - (group + 1) * GROUP_ROWS, 0)
	for row: int in range(first, first + GROUP_ROWS):
		world.field[row] = -1
	var slot: int = world.flow.acquire(key.x, key.y, world.map_version, world.tick)
	for row: int in range(first, first + GROUP_ROWS):
		world.field[row] = slot


## Adds to `seen` which kinds of field this cache holds.
func _count(flow: FlowCache, seen: Dictionary[String, int]) -> void:
	for slot: int in flow.status.size():
		var field: FlowField = flow.fields[slot]
		var status: int = flow.status[slot]
		seen["waiting"] += int(status == FlowCache.Status.WAITING)
		seen["half"] += int(status == FlowCache.Status.ACTIVE and field.pending > 0)
		seen["served"] += int(status != FlowCache.Status.FREE and field.complete)
		seen["again"] += int(
			field.complete and (status == FlowCache.Status.WAITING or field.pending > 0)
		)


## The FLOW kernel's inputs: what SimKernels.flow reads and writes (bind/kernel_flow.cpp).
func _write(world: World, path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_32(World.STATE_FORMAT)
	file.store_32(world.tick)
	_write_flow(file, world)
	_write_integrate(file, world)
	var ok: bool = file.get_error() == OK
	file.close()
	return ok


func _write_flow(file: FileAccess, world: World) -> void:
	var flow: FlowCache = world.flow
	_scalar(file, "world.unit_count", world.unit_count())
	_scalar(file, "world.flow_cells_per_tick", world.flow_cells_per_tick)
	_ints(file, "world.field", world.field)
	_bytes(file, "world.move_cost", world.move_cost)
	_scalar(file, "flow.cols", flow.cols)
	_scalar(file, "flow.rows", flow.rows)
	_scalar(file, "flow.slots", flow.fields.size())
	_ints(file, "flow.key_goal", flow.key_goal)
	_ints(file, "flow.key_class", flow.key_class)
	_ints(file, "flow.requested", flow.requested)
	_ints(file, "flow.ref_count", flow.ref_count)
	_ints(file, "flow.status", flow.status)
	for slot: int in flow.fields.size():
		var field: FlowField = flow.fields[slot]
		var prefix: String = "flow.slot.%d." % slot
		_ints(file, prefix + "cost", field.cost)
		_ints(file, prefix + "next", field.next)
		_ints(file, prefix + "bucket_head", field.bucket_head)
		_ints(file, prefix + "link_next", field.link_next)
		_ints(file, prefix + "link_prev", field.link_prev)
		_bytes(file, prefix + "pad_cost", field.pad_cost)
		_scalar(file, prefix + "goal_cell", field.goal_cell)
		_scalar(file, prefix + "move_class", field.move_class)
		_scalar(file, prefix + "grid_cols", field.grid_cols)
		_scalar(file, prefix + "cell_count", field.cell_count)
		_scalar(file, prefix + "stride", field.stride)
		_scalar(file, prefix + "level", field.level)
		_scalar(file, prefix + "pending", field.pending)
		_scalar(file, prefix + "complete", int(field.complete))


## The INTEGRATE kernel's inputs that the FLOW records above do not hold: what
## SimKernels.integrate reads and writes (bind/kernel_integrate.cpp).
func _write_integrate(file: FileAccess, world: World) -> void:
	for member: StringName in INTEGRATE_SCALARS:
		_scalar(file, "world.%s" % member, world.get(member))
	for member: StringName in INTEGRATE_COLUMNS:
		_ints(file, "world.%s" % member, world.get(member))
	_scalar(file, "flow.classes", world.flow.classes)
	_scalar(file, "flow.requests", world.flow.requests)
	_ints(file, "flow.key_version", world.flow.key_version)
	_ints(file, "flow.last_used", world.flow.last_used)


func _head(file: FileAccess, kind: String, record: String, count: int) -> void:
	file.store_8(kind.unicode_at(0))
	file.store_16(record.length())
	file.store_buffer(record.to_ascii_buffer())
	file.store_64(count)


func _scalar(file: FileAccess, record: String, value: int) -> void:
	_head(file, "S", record, 1)
	file.store_64(value)


func _ints(file: FileAccess, record: String, values: PackedInt32Array) -> void:
	_head(file, "I", record, values.size())
	file.store_buffer(values.to_byte_array())


func _bytes(file: FileAccess, record: String, values: PackedByteArray) -> void:
	_head(file, "B", record, values.size())
	file.store_buffer(values)
