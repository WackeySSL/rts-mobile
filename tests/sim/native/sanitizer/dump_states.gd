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
##
## Sim.step steps FLOW itself (P37b), so the step only plays and nothing here calls FlowCache. The
## fields come from real orders: the arena's own (both sides attack-move across its rock wall,
## where a blocked line asks for a field), and a wave every WAVE_EVERY ticks that sends units back
## across the wall to new targets, all queued to the MatchLoop. Slow sand, scrub and rock are
## painted in, so that the costs differ; and three repaints a few ticks before a dump
## (World.set_terrain, as a building will) re-integrate the fields in use. The run fails if no
## dump caught a waiting, a half integrated, a served and a re-integrating field.

const MatchScript: GDScript = preload("res://tests/sim/support/match_script.gd")
const MAGIC: String = "RTSD"
const MATCH_SEED: int = 42
const TICKS: int = 900
const DUMP_EVERY: int = 15
## The ticks of the repaints (a set_terrain after the step of that tick): each lies three ticks
## before a dump, so that the two FLOW slices between them and the dump leave the fields in use half
## integrated again (the step before a dump has no slice, ADR 0012 section 5).
const REPAINT_TICKS: Array[int] = [206, 446, 701]
## A wave: from WAVE_FIRST, every WAVE_EVERY ticks, one player's units on one side of the wall
## (about one in WAVE_SHARE of them) move to a tile on the other side. Waves alternate between the
## players and the sides. WALL_X lies between the two rock columns of the arena's wall.
const WAVE_FIRST: int = 120
const WAVE_EVERY: int = 30
const WAVE_SHARE: int = 5
const WALL_X: int = 32000
## The cost per terrain (grass, sand, scrub, rock, water) and class (foot, wheeled, tracked), as
## test_flow_lockstep.gd paints them: slow sand (255 is the cap of the bucket ring), scrub for
## foot only.
const GROUND_COST: Array[int] = [10, 10, 10, 12, 41, 255, 13, 0, 0, 0, 0, 0, 0, 0, 0]


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
	var repaints: Array[Vector2i] = []
	for _tick: int in REPAINT_TICKS:
		repaints.append(Vector2i(rng.next_int(cells), 3))
	var seen: Dictionary[String, int] = {"waiting": 0, "half": 0, "served": 0, "again": 0}
	var written: int = 0
	for tick: int in TICKS:
		loop.step(world, _orders_at(world))
		if tick in REPAINT_TICKS:
			var paint: Vector2i = repaints[REPAINT_TICKS.find(tick)]
			world.set_terrain(paint.x, paint.y)
		if world.tick % DUMP_EVERY == 0:
			# The state the FLOW call of the next tick finds.
			var path: String = out_dir.path_join("state_%05d.bin" % world.tick)
			if not _write(world, path):
				printerr("dump_states: cannot write %s" % path)
				return 1
			written += 1
			_count(world.flow, seen)
	print("dump_states: wrote %d dumps to %s (%s)" % [written, out_dir, seen])
	for kind: String in seen:
		if seen[kind] == 0:
			printerr("dump_states: FAIL no dump caught a %s field" % kind)
			return 1
	return 0


## The orders of this tick: the match script's, and on the tick of a wave the wave's.
@warning_ignore("integer_division")
func _orders_at(world: World) -> Array[Command]:
	var orders: Array[Command] = MatchScript.commands_at(world.tick)
	var since: int = world.tick - WAVE_FIRST
	if since < 0 or since % WAVE_EVERY != 0:
		return orders
	var wave: int = since / WAVE_EVERY
	var player: int = 1 + wave % 2
	var west: bool = wave % 4 < 2
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in world.unit_count():
		var id: int = world.unit_id[row]
		if world.owner[row] == player and (world.pos_x[row] < WALL_X) == west:
			if (id + wave) % WAVE_SHARE == 0:
				ids.append(id)
	if not ids.is_empty():
		var tile_x: int = (34 if west else 3) + wave * 7 % 27
		var tile_y: int = 3 + wave * 11 % 58
		orders.append(Command.move(player, ids, tile_x * 1000 + 500, tile_y * 1000 + 500))
	return orders


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
