extends GdUnitTestSuite
## The kernel boundary (ADR 0013 section 2, plan P54): what the library says about itself,
## SimKernels.check_world over the checked table of the five ported phases (on the main thread and
## on a worker Thread), the table's names against the World's lists, and the write cases of ADR 0013
## section 2 through the FLOW kernel (P30n: FlowCache.run). A real World's members are typed and
## refuse a wrong value, so the fault cases check a Mirror, which answers Object.get from a
## Dictionary. Numbers are literals: the status codes are world_status.h's, the phase ids
## SimProbe.Phase's (one case checks world_access.h's mirrors of them). The table is read from
## world_access.h itself (there is no test-only bound entry), one X(owner, name, kind, size,
## phases) line per name, the line order being its index.

const KernelSpy: GDScript = preload("res://tests/sim/support/kernel_spy.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const StateDiff: GDScript = preload("res://tests/sim/support/state_diff.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const HEADER: String = "res://native/sim_kernels/src/bind/world_access.h"
const FLOW_SOURCE: String = "res://native/sim_kernels/src/bind/kernel_flow.cpp"
## FLOW, TARGETING, SEPARATION, INTEGRATE and FOG.
const PHASES: Array[int] = [1, 3, 5, 6, 10]
## The slots of the flow cache (flow_cache_size).
const SLOTS: int = 8
## The names in each list, 107 in the table (a port adds names here, so a dropped or added name
## shows in a diff). INTEGRATE's 49 are the names kernel_integrate.cpp gets or sets (P37n) and
## SEPARATION's 20 those of kernel_separation.cpp (P39n; it was 28, with the eight that Separation
## does not read: max_rows, map_cols, map_rows, map_w, map_h, move_cost, type_speed and
## type_move_class). TARGETING's 35 are the names kernel_targeting.cpp gets or sets (P41n; it was
## 32: max_rows, hp and type_speed lose its bit, and line_check_period_ticks, nav_cell, field,
## nav_next, best_dist and stall gain it); since P46b it is 40: the vision rule reads the fog's
## cols, rows, cells, player_count and visible; since P71b it is 41: a lock on a target that stands
## still keeps the row's goal, so the kernel reads type_speed again. FOG's 25 are the names
## kernel_fog.cpp gets or sets (P46n; it was 29: max_rows, map_cols, map_rows and type_speed lose
## its bit, type_sight stays because the pad mask is the size of that table).
const LIST_SIZES: Dictionary[int, int] = {1: 26, 3: 41, 5: 20, 6: 49, 10: 25}
## A status is the table index of the first bad name times FAULT_COUNT, plus its fault.
const FAULT_PHASE: int = 1
const FAULT_OWNER: int = 2
const FAULT_TYPE: int = 3
const FAULT_SIZE: int = 4
const FAULT_COUNT: int = 5
## The World member that holds each helper object.
const HELPERS: Dictionary[String, String] = {
	"FLOW": "flow", "FOG": "fog", "SEP": "sep_grid", "TARGET": "target_grid"
}
const KIND_TYPES: Dictionary[String, int] = {
	"INT": TYPE_INT,
	"BOOL": TYPE_BOOL,
	"I32": TYPE_PACKED_INT32_ARRAY,
	"BYTES": TYPE_PACKED_BYTE_ARRAY,
	"ARRAY": TYPE_ARRAY,
}
## The mask of each token of the table's phases column: 1 << the SimProbe.Phase id, PH_ALL all five.
const PHASE_BITS: Dictionary[String, int] = {
	"0": 0, "PH_F": 2, "PH_T": 8, "PH_S": 32, "PH_I": 64, "PH_G": 1024, "PH_ALL": 0x46A
}
## The arrays with no fixed length: the anchors of the size rules, the events and the fog masks
## (only the sight radii size those). Every other array has a rule, and no scalar has one.
const ANY_NAMES: Array[String] = [
	"WORLD.events",
	"WORLD.type_speed",
	"WORLD.weapon_range",
	"FOG.mask_start",
	"FOG.mask_radius",
	"FOG.mask_half"
]
## What the FLOW kernel gets or sets (P30n), in table order: the old list's max_rows, map_cols,
## map_rows and flow_cache_size are neither read nor written by it.
const FLOW_NAMES: Array[String] = [
	"WORLD.unit_id",
	"WORLD.field",
	"WORLD.stats",
	"WORLD.move_cost",
	"FLOW.cols",
	"FLOW.rows",
	"FLOW.key_goal",
	"FLOW.key_class",
	"FLOW.ref_count",
	"FLOW.requested",
	"FLOW.status",
	"FLOW.fields",
	"SLOT.goal_cell",
	"SLOT.move_class",
	"SLOT.grid_cols",
	"SLOT.cell_count",
	"SLOT.stride",
	"SLOT.level",
	"SLOT.pending",
	"SLOT.complete",
	"SLOT.cost",
	"SLOT.next",
	"SLOT.pad_cost",
	"SLOT.bucket_head",
	"SLOT.link_next",
	"SLOT.link_prev"
]
## The phases of names that a swap of two masks would exchange, and the phase of each helper that
## only one phase uses.
const PHASES_OF: Dictionary[String, Array] = {
	"WORLD.hp": [],
	"WORLD.max_rows": [],
	"WORLD.type_speed": [3, 6],
	"WORLD.line_check_period_ticks": [3, 6],
	"WORLD.order_target": [3],
	"WORLD.target": [3],
	"WORLD.field": [1, 3, 6],
	"WORLD.nav_cell": [3, 6],
	"WORLD.nav_next": [3, 6],
	"WORLD.best_dist": [3, 6],
	"WORLD.stall": [3, 6],
	"WORLD.group_cell": [6],
	"WORLD.flow_cache_size": [],
	"WORLD.fog_cell": [10],
	"WORLD.map_version": [6],
	"WORLD.events": [],
	"WORLD.type_radius": [5],
	"WORLD.type_spacing": [6],
	"WORLD.type_sight": [10],
	"WORLD.type_acquire": [3],
	"WORLD.type_armour": [3],
	"WORLD.type_move_class": [3, 6],
	"FLOW.requests": [6],
	"FLOW.last_used": [6],
	"SLOT.goal_cell": [1],
	"SLOT.cell_count": [1, 6],
	"FOG.cols": [3, 10],
	"FOG.rows": [3, 10],
	"FOG.cells": [3, 10],
	"FOG.player_count": [3, 10],
	"FOG.visible": [3, 10]
}
const OWNER_PHASE: Dictionary[String, int] = {"SEP": 5, "TARGET": 3, "FOG": 10}


## An Object whose members are the entries of `values`: Object.get falls back to _get, so a member
## can hold a value of any type. With `fresh`, an object or Array it answers is a new copy on
## every read, so the Variant that Object.get returns holds the only reference to it (a library
## that keeps a bare pointer to what it fetched then reads freed memory).
class Mirror:
	extends RefCounted

	var values: Dictionary = {}
	var fresh: bool = false

	func _get(property: StringName) -> Variant:
		var value: Variant = values.get(property)
		return _renewed(value) if fresh else value

	func _renewed(value: Variant) -> Variant:
		if value is Mirror:
			var copy: Mirror = Mirror.new()
			copy.fresh = true
			for key: Variant in value.values:
				copy.values[key] = _renewed(value.values[key])
			return copy
		if value is Array:
			var items: Array = []
			for item: Variant in value:
				items.append(_renewed(item))
			return items
		return value


func test_the_library_reports_its_abi_and_the_phases_it_implements() -> void:
	var kernels: Object = _kernels()
	assert_str(kernels.get_class()).is_equal("SimKernels")
	assert_int(kernels.abi_version()).is_equal(1)
	assert_int(kernels.phases()).is_equal(SimImpls.expected_mask())


## The constexpr mirrors in world_access.h (CLAUDE.md rule 1 allows a commented mirror of a
## GDScript const) are read from the file: every PHASE_<name> is the id of SimProbe.Phase.<name>
## and every PH_<letter> shifts the right one, so a renumbering cannot leave them behind.
func test_the_phase_mirrors_in_world_access_h_equal_simprobe_phase() -> void:
	var ids: Dictionary[String, int] = {}
	var bits: Dictionary[String, String] = {}
	var id_line: RegEx = RegEx.create_from_string("int64_t PHASE_(\\w+) = (\\d+);")
	var bit_line: RegEx = RegEx.create_from_string(
		"int64_t (PH_\\w) = int64_t\\(1\\) << PHASE_(\\w+);"
	)
	for line: String in FileAccess.get_file_as_string(HEADER).split("\n"):
		var id: RegExMatch = id_line.search(line)
		if id != null:
			ids[id.get_string(1)] = id.get_string(2).to_int()
		var bit: RegExMatch = bit_line.search(line)
		if bit != null:
			bits[bit.get_string(1)] = bit.get_string(2)
	var named: Dictionary[String, int] = {"FLOW": SimProbe.Phase.FLOW}
	named["TARGETING"] = SimProbe.Phase.TARGETING
	named["SEPARATION"] = SimProbe.Phase.SEPARATION
	named["INTEGRATE"] = SimProbe.Phase.INTEGRATE
	named["FOG"] = SimProbe.Phase.FOG
	assert_dict(ids).is_equal(named)
	var letters: Dictionary[String, String] = {"PH_F": "FLOW", "PH_T": "TARGETING"}
	letters.merge({"PH_S": "SEPARATION", "PH_I": "INTEGRATE", "PH_G": "FOG"})
	assert_dict(bits).is_equal(letters)


func test_sim_impls_attaches_the_kernels_after_prepare_and_detaches_them() -> void:
	var world: World = World.new()
	assert_array(SimImpls.use(world, SimImpls.Impl.NATIVE)).is_empty()
	assert_bool(world.prepared).is_true()
	assert_str(world.kernels.get_class()).is_equal("SimKernels")
	assert_int(world.native_phases).is_equal(world.kernels.phases())
	for phase: int in PHASES:
		var expected: bool = ((SimImpls.expected_mask() >> phase) & 1) == 1
		assert_bool(SimImpls.is_native(world, phase)).is_equal(expected)
	assert_array(SimImpls.use(world, SimImpls.Impl.GDSCRIPT)).is_empty()
	assert_object(world.kernels).is_null()
	assert_int(world.native_phases).is_equal(0)
	# A spy is no SimKernels: its bits do not make a phase native. The library's class with a bit
	# set is native for that phase only.
	world.kernels = KernelSpy.new()
	world.native_phases = 0x7FF
	assert_bool(SimImpls.is_native(world, 6)).is_false()
	world.kernels = _kernels()
	world.native_phases = 1 << 6
	assert_bool(SimImpls.is_native(world, 6)).is_true()
	assert_bool(SimImpls.is_native(world, 5)).is_false()


## A caller that ignores the problems would run its native pass on the GDScript twin, so each one
## is named: kernels of another class, and a mask other than EXPECTED_PHASES' (the spy has bits
## no kernel sets). Both are still attached, as the problems say.
func test_sim_impls_names_kernels_of_another_class_and_a_wrong_mask() -> void:
	var spy: RefCounted = KernelSpy.new()
	spy.reported_phases = 0x7FF
	var world: World = World.new()
	var problems: Array[String] = SimImpls.use(world, SimImpls.Impl.NATIVE, spy)
	assert_int(problems.size()).is_equal(2)
	assert_str(problems[0]).contains("RefCounted")
	assert_str(problems[1]).contains("2047")
	assert_object(world.kernels).is_same(spy)
	assert_int(world.native_phases).is_equal(0x7FF)
	# One bit per id: FLOW 1, TARGETING 3, SEPARATION 5, INTEGRATE 6 and FOG 10.
	assert_int(SimImpls.expected_mask(PHASES)).is_equal(0x46A)


func test_check_world_accepts_a_prepared_world_for_each_of_the_five_phases() -> void:
	var kernels: Object = _kernels()
	for world: World in _clean_worlds():
		for phase: int in PHASES:
			var status: int = kernels.check_world(world, phase)
			var label: String = "phase %d on %dx%d" % [phase, world.map_cols, world.map_rows]
			assert_int(status).override_failure_message(label).is_equal(0)


## The row count may be max_rows and not one more (a World built past its cap before prepare()).
func test_check_world_allows_exactly_max_rows_rows_and_rejects_one_more() -> void:
	var kernels: Object = _kernels()
	var at: int = _table().find_custom(func(e: Dictionary) -> bool: return e.name == "unit_id")
	assert_int(at).is_greater(0)
	for rows: int in [3, 4]:
		var world: World = World.new()
		world.max_rows = 3
		for row: int in rows:
			world.add_unit(1, 0, 1500 + 1000 * row, 500)
		world.prepare()
		for phase: int in PHASES:
			var status: int = kernels.check_world(world, phase)
			var expected: int = 0 if rows == 3 else at * FAULT_COUNT + FAULT_SIZE
			assert_int(status).override_failure_message("%d rows" % rows).is_equal(expected)


func test_check_world_rejects_an_unprepared_world_and_leaves_it_unchanged() -> void:
	var kernels: Object = _kernels()
	var world: World = World.new()
	world.add_unit(1, 0, 1500, 500)
	var before: PackedInt64Array = world.hash_parts()
	for phase: int in PHASES:
		# Nothing has a wrong type, but stats and the helpers' arrays are not sized yet.
		assert_int(kernels.check_world(world, phase) % FAULT_COUNT).is_equal(FAULT_SIZE)
	assert_array(world.hash_parts()).is_equal(before)
	assert_bool(world.prepared).is_false()
	assert_int(world.stats.size()).is_equal(0)


func test_every_list_is_not_empty_and_every_name_exists_with_its_type() -> void:
	var world: World = _arena()
	var table: Array[Dictionary] = _table()
	assert_int(table.size()).is_equal(107)
	for phase: int in PHASES:
		var size: int = _listed(table, phase).size()
		assert_int(size).override_failure_message("phase %d" % phase).is_equal(LIST_SIZES[phase])
	for owner: String in HELPERS:  # The helper objects the owners are reached through.
		assert_int(typeof(world.get(HELPERS[owner]))).is_equal(TYPE_OBJECT)
	var seen: Array[String] = []
	for entry: Dictionary in table:
		var label: String = "%s.%s" % [entry.owner, entry.name]
		assert_bool(seen.has(label)).override_failure_message("twice: " + label).is_false()
		seen.append(label)
		var value: Variant
		for source: Object in _sources(world, entry.owner):
			value = source.get(entry.name)
			var type: int = typeof(value)
			assert_int(type).override_failure_message(label).is_equal(KIND_TYPES[entry.kind])
		if label == "FLOW.fields":
			# In no HASHED or UNHASHED list on purpose (P31b): checked by its declared kind.
			assert_bool(value.is_typed()).is_true()
			assert_object(value.get_typed_script()).is_equal(FlowField)
		else:
			var listed: bool = _lists(entry.owner).has(StringName(entry.name))
			assert_bool(listed).override_failure_message(label).is_true()
	# What P26h and P26i name: every member of the cache and of a slot (FLOW's list holds the six
	# STATE_ARRAYS, stride, level, pending and the bool complete), and fog's dirty blocks.
	assert_array(_names(table, "FLOW")).contains(FlowCache.UNHASHED + [&"fields"])
	assert_array(_names(table, "SLOT")).contains(FlowField.UNHASHED)
	var flow_slot: Array[StringName] = []
	for index: int in _listed(table, 1):
		if table[index].owner == "SLOT":
			flow_slot.append(StringName(table[index].name))
	var wanted: Array = FlowField.STATE_ARRAYS + [&"stride", &"level", &"pending", &"complete"]
	assert_array(flow_slot).contains(wanted)
	var fog_blocks: Array = [&"listed", &"dirty", &"dirty_count", &"dirty_full"]
	assert_array(_names(table, "FOG")).contains(fog_blocks)


## The length rules and the phases are the table's data, so they are pinned here by literals: a
## rule weakened to ANY or NONE, or a mask moved to another phase, fails. (A rule swapped for
## another fails the length test below.)
func test_the_table_pins_the_length_rule_and_the_phases_of_the_names() -> void:
	for entry: Dictionary in _table():
		var label: String = "%s.%s" % [entry.owner, entry.name]
		var is_array: bool = entry.kind in ["I32", "BYTES", "ARRAY"]
		var any: bool = ANY_NAMES.has(label)
		assert_bool(entry.size == "ANY").override_failure_message(label).is_equal(any)
		assert_bool(entry.size == "NONE").override_failure_message(label).is_equal(not is_array)
		var phases: Array = PHASES_OF.get(label, [])
		if OWNER_PHASE.has(entry.owner) and not PHASES_OF.has(label):
			phases = [OWNER_PHASE[entry.owner]]
		if PHASES_OF.has(label) or OWNER_PHASE.has(entry.owner):
			var found: Array[int] = _phases_of(entry)
			assert_array(found).override_failure_message(label).is_equal(phases)


## Each size rule is the number its name says, computed here from the World's own members, on
## worlds where two numbers of a rule differ (the arena is square and has a weapon per type).
func test_every_array_has_the_length_its_rule_names_on_worlds_of_different_shapes() -> void:
	var table: Array[Dictionary] = _table()
	for world: World in _clean_worlds():
		for entry: Dictionary in table:
			if entry.size in ["NONE", "ANY", "ROWS_CAP"]:
				continue
			var want: int = _rule_length(world, entry.size)
			for source: Object in _sources(world, entry.owner):
				var length: int = source.get(entry.name).size()
				var label: String = (
					"%s.%s on %dx%d" % [entry.owner, entry.name, world.map_cols, world.map_rows]
				)
				assert_int(length).override_failure_message(label).is_equal(want)
	var odd: World = _odd_world(40, 24)  # Three types with two weapons: no two rules coincide.
	assert_int(odd.type_speed.size()).is_equal(3)
	assert_int(odd.weapon_range.size()).is_equal(2)


func test_the_bound_methods_are_the_contract_and_none_takes_a_packed_array() -> void:
	var methods: Array[String] = []
	for method: Dictionary in ClassDB.class_get_method_list(&"SimKernels", true):
		methods.append(method.name)
		for argument: Dictionary in method.args:
			var kind: int = argument.type
			var packed: bool = kind >= TYPE_PACKED_BYTE_ARRAY and kind < TYPE_MAX
			var label: String = "%s(%s)" % [method.name, argument.name]
			assert_bool(packed).override_failure_message(label).is_false()
	# No test-only entry (ADR 0013 section 2): a port adds its kernel's name here.
	var bound: Array[String] = ["abi_version", "phases", "build_info", "check_world", "flow"]
	bound.append_array(["separation", "integrate", "targeting", "fog"])
	assert_array(methods).contains_exactly_in_any_order(bound)


## Each name of each list with a wrong type, too long and too short, each helper object and the
## slot objects missing, a phase with no list and no World: the status names the first bad name.
## Also when every object and Array the library fetches is a fresh copy that only the fetched
## value keeps alive.
func test_check_world_names_the_first_bad_name_and_what_is_wrong_with_it() -> void:
	var kernels: Object = _kernels()
	var table: Array[Dictionary] = _table()
	var tags: Array[String] = []
	for world: World in [_arena(), _odd_world(40, 24)]:
		var cases: Array[Array] = _fault_cases(world, table)
		for fresh: bool in [false, true]:
			for entry: Array in cases:
				if entry[0] != null:
					entry[0].fresh = fresh
				var status: int = kernels.check_world(entry[0], entry[1])
				var label: String = "%s fresh %s" % [entry[3], fresh]
				assert_int(status).override_failure_message(label).is_equal(entry[2])
				tags.append(entry[4])
	# Every kind meets each fault it can have, and the other faults happen.
	for tag: String in ["INT/3", "BOOL/3", "I32/3", "I32/4", "BYTES/3", "BYTES/4", "ARRAY/3"]:
		assert_array(tags).contains([tag])
	for tag: String in ["ARRAY/4", "owner/2", "phase/1", "clean/0", "first/3"]:
		assert_array(tags).contains([tag])


## The list of the table is FLOW_NAMES, and kernel_flow.cpp names those and no other: a name it
## fetched outside the list would reach the engine without check_world's type test.
func test_flow_gets_and_sets_exactly_the_names_of_its_list() -> void:
	var table: Array[Dictionary] = _table()
	var names: Array[String] = []
	for index: int in _listed(table, 1):
		names.append("%s.%s" % [table[index].owner, table[index].name])
	assert_array(names).contains_exactly(FLOW_NAMES)
	var used: Array[String] = []
	var ids: RegEx = RegEx.create_from_string("\\bID_(WORLD|FLOW|SLOT)_(\\w+)")
	for found: RegExMatch in ids.search_all(FileAccess.get_file_as_string(FLOW_SOURCE)):
		var name: String = "%s.%s" % [found.get_string(1), found.get_string(2)]
		if not used.has(name):
			used.append(name)
	assert_array(used).contains_exactly_in_any_order(FLOW_NAMES)


## An array the call writes in place is seen through an alias taken before it, with no copy held
## and with one (a duplicate() keeps its old values; the member forks once and writes in place
## after that), the scalars arrive as the twin's, a budget-0 call writes nothing, and the call that
## completes the field swaps cost and next and sets `complete`.
func test_the_flow_kernel_writes_in_place_and_sets_what_the_twin_sets() -> void:
	for hold: bool in [false, true]:
		var seen: Dictionary = _write_case(_flow_pair(), hold)
		assert_dict(seen).override_failure_message("hold %s" % hold).is_equal(_written(hold))


func test_the_flow_write_cases_give_the_same_observations_on_a_worker_thread() -> void:
	for hold: bool in [false, true]:
		var thread: Thread = Thread.new()
		assert_int(thread.start(_write_case.bind(_flow_pair(), hold))).is_equal(OK)
		assert_dict(thread.wait_to_finish()).is_equal(_written(hold))


func test_check_world_gives_the_same_statuses_on_a_worker_thread() -> void:
	var kernels: Object = _kernels()
	var cases: Array[Array] = _fault_cases(_arena(), _table())
	for world: World in _clean_worlds():  # The real World, read through its own members.
		for phase: int in PHASES:
			cases.append([world, phase, 0, "world phase %d" % phase, "world/0"])
	var thread: Thread = Thread.new()
	assert_int(thread.start(_check_all.bind(kernels, cases))).is_equal(OK)
	var found: Array = thread.wait_to_finish()
	assert_int(found.size()).is_equal(cases.size())
	for index: int in cases.size():
		assert_int(found[index]).override_failure_message(cases[index][3]).is_equal(cases[index][2])


## The lockstep oracle and the checked table's lists cover the four Phase 3 lists (ADR 0017 section
## 3): an extra entry in any one array names that array, and the table may name each of them.
func test_the_oracle_and_the_table_lists_cover_the_phase_3_lists() -> void:
	var phase_3: Array[StringName] = []
	phase_3.assign(
		World.PLAYER_ARRAYS + World.ORE_ARRAYS + World.GHOST_ARRAYS + World.DERIVED_ARRAYS
	)
	for member: StringName in phase_3:
		var other: World = _arena()
		var column: PackedInt32Array = other.get(member)
		column.append(7)
		other.set(member, column)
		assert_str(StateDiff.first(_arena(), other)).override_failure_message(member).is_equal(
			String(member)
		)
		assert_array(_lists("WORLD")).override_failure_message(member).contains([member])


## What _write_case sees: every observation true, and only a held copy keeps its old values.
func _written(hold: bool) -> Dictionary:
	var seen: Dictionary = {"settled": 5, "alias": true, "member": true, "scalars": true}
	seen.merge({"again": true, "refs": true, "idle": true, "copy_kept": hold, "pending": true})
	seen["done"] = true
	return seen


## The arena with one wheeled key taken on both Worlds, the first running C++ and the second the
## twin. Rows 0 to 2 follow the field.
func _flow_pair() -> Array[World]:
	var pair: Array[World] = [_arena(), _arena()]
	assert_array(SimImpls.use(pair[0], SimImpls.Impl.NATIVE)).is_empty()
	assert_bool(SimImpls.is_native(pair[0], SimProbe.Phase.FLOW)).is_true()
	for world: World in pair:
		var slot: int = world.flow.acquire(2080, World.MoveClass.WHEELED, world.map_version, 1)
		for row: int in 3:
			world.field[row] = slot
	return pair


## FlowCache.run on both Worlds with a budget below the field's cells, observed on the Thread that
## calls it. `hold` keeps a duplicate() of `next` across the calls.
static func _write_case(pair: Array[World], hold: bool) -> Dictionary:
	var world: World = pair[0]
	var twin: World = pair[1]
	var field: FlowField = world.flow.field(0)
	var served: FlowField = twin.flow.field(0)
	var alias: PackedInt32Array = field.next
	var copy: PackedInt32Array = field.next.duplicate() if hold else PackedInt32Array()
	# Own storage: a duplicate() shares its buffer with `copy` until one of them is written.
	var old_values: Array = Array(copy)
	var seen: Dictionary = {}
	FlowCache.run(world, 5)
	FlowCache.run(twin, 5)
	seen["settled"] = world.stats[World.Stat.FLOW_CELLS]
	seen["alias"] = alias == served.next and alias.count(FlowField.UNREACHED) < alias.size()
	seen["member"] = field.next == served.next
	var scalars: Array[StringName] = [&"goal_cell", &"move_class", &"grid_cols", &"cell_count"]
	scalars.append_array([&"stride", &"level", &"pending", &"complete"])
	seen["scalars"] = field.pending > 0 and field.goal_cell == 2080
	for scalar: StringName in scalars:
		seen["scalars"] = seen["scalars"] and field.get(scalar) == served.get(scalar)
	seen["refs"] = world.flow.ref_count == twin.flow.ref_count and world.flow.refs(0) == 3
	FlowCache.run(world, 5)
	FlowCache.run(twin, 5)
	seen["again"] = alias == served.next and field.pending == served.pending
	# Kept only if the write forked: a write through the held buffer would change `copy` as well.
	seen["copy_kept"] = hold and Array(copy) == old_values and copy != field.next
	# The flow cache is derived state and not hashed, so the hash only says the call touched no
	# other state; StateDiff compares the flow cache and every slot with the twin's.
	var hash_before: int = world.state_hash()
	var snapshot: PackedInt32Array = field.next.duplicate()
	world.stats.fill(0)
	twin.stats.fill(0)
	FlowCache.run(world, 0)
	FlowCache.run(twin, 0)
	seen["idle"] = world.state_hash() == hash_before and field.next == snapshot
	seen["idle"] = seen["idle"] and StateDiff.first(world, twin) == ""
	seen["pending"] = world.stats[World.Stat.FLOW_CELLS] == 0 and field.pending == served.pending
	FlowCache.run(world, 100000)
	FlowCache.run(twin, 100000)
	seen["done"] = field.complete and field.pending == 0 and field.move_class == 1
	seen["done"] = seen["done"] and field.cost == served.cost and field.cost != snapshot
	seen["done"] = seen["done"] and StateDiff.first(world, twin) == ""
	return seen


## The statuses of check_world for [world, phase, ...] cases, in order. Runs on a worker.
static func _check_all(kernels: Object, cases: Array[Array]) -> Array[int]:
	var found: Array[int] = []
	for entry: Array in cases:
		found.append(kernels.check_world(entry[0], entry[1]))
	return found


## [mirror or null, phase, expected status, label, "KIND/fault"] for every fault of every list.
func _fault_cases(world: World, table: Array[Dictionary]) -> Array[Array]:
	var wrong: Dictionary[String, Variant] = {"INT": "x", "BOOL": 1, "I32": PackedByteArray()}
	wrong["BYTES"] = PackedInt32Array()
	wrong["ARRAY"] = 7
	var past_cap: int = world.max_rows + 1  # What unit_id may not reach.
	var cases: Array[Array] = []
	for phase: int in PHASES:
		cases.append([_mirror(world, table), phase, 0, "clean %d" % phase, "clean/0"])
		var first: Dictionary[String, int] = {}
		for index: int in _listed(table, phase):
			var entry: Dictionary = table[index]
			var label: String = "phase %d %s.%s" % [phase, entry.owner, entry.name]
			first[entry.owner] = first.get(entry.owner, index)
			cases.append(_case(world, table, phase, index, FAULT_TYPE, wrong[entry.kind], label))
			if entry.size == "NONE" or entry.size == "ANY":
				continue
			var key: StringName = StringName(entry.name)
			var old: Variant = _holder(_mirror(world, table), entry, index).values[key]
			var steps: Array[int] = [1, -1]
			if entry.size == "ROWS_CAP":
				steps = [past_cap]
			for step: int in steps:
				var value: Variant = _resized(old, step)
				cases.append(_case(world, table, phase, index, FAULT_SIZE, value, label))
		# Two bad names, the first and the last of the list: the status is the first one's.
		var ends: Array[int] = _listed(table, phase)
		var early: Variant = wrong[table[ends[0]].kind]
		var pair: Array = _case(world, table, phase, ends[0], FAULT_TYPE, early, "two bad names")
		var late: Dictionary = table[ends[-1]]
		_holder(pair[0], late, ends[-1]).values[StringName(late.name)] = wrong[late.kind]
		pair[4] = "first/3"
		cases.append(pair)
		for owner: String in first:
			var status: int = first[owner] * FAULT_COUNT + FAULT_OWNER
			var mirror: Mirror = null
			if owner != "WORLD":
				mirror = _mirror(world, table)
				if owner == "SLOT":
					mirror.values[&"flow"].values[&"fields"][first[owner] % SLOTS] = 7
				else:
					mirror.values[StringName(HELPERS[owner])] = 7
			cases.append([mirror, phase, status, "phase %d no %s" % [phase, owner], "owner/2"])
	for phase: int in [0, 2, 4, 7, 8, 9, 11, -1, 63, 64, 1000]:
		cases.append([_mirror(world, table), phase, FAULT_PHASE, "phase %d" % phase, "phase/1"])
	return cases


## A case: a mirror with `value` in entry `index`.
func _case(
	world: World,
	table: Array[Dictionary],
	phase: int,
	index: int,
	fault: int,
	value: Variant,
	label: String
) -> Array:
	var mirror: Mirror = _mirror(world, table)
	var entry: Dictionary = table[index]
	_holder(mirror, entry, index).values[StringName(entry.name)] = value
	var tag: String = "%s/%d" % [entry.kind, fault]
	return [mirror, phase, index * FAULT_COUNT + fault, "%s fault %d" % [label, fault], tag]


## The Mirror that holds `entry` (table index `index`): the World's, a helper's or, for a slot
## name, slot `index % SLOTS`, so that the faults land in different slots.
func _holder(mirror: Mirror, entry: Dictionary, index: int) -> Mirror:
	if entry.owner == "WORLD":
		return mirror
	if entry.owner == "SLOT":
		return mirror.values[&"flow"].values[&"fields"][index % SLOTS]
	return mirror.values[StringName(HELPERS[entry.owner])]


## One more or fewer entry (a Mirror for the Array of slots).
func _resized(old: Variant, step: int) -> Variant:
	var copy: Variant = old.duplicate()
	if copy is Array:
		if step > 0:
			copy.append(Mirror.new())
		else:
			copy.pop_back()
	else:
		copy.resize(copy.size() + step)
	return copy


## The World, its helpers and their slots as Mirrors that hold the values of the real ones, so that
## a case changes a single value. The slots are the Mirrors in the Array `fields`.
func _mirror(world: World, table: Array[Dictionary]) -> Mirror:
	var root: Mirror = Mirror.new()
	var helpers: Dictionary[String, Mirror] = {"WORLD": root}
	for owner: String in HELPERS:
		helpers[owner] = Mirror.new()
		root.values[StringName(HELPERS[owner])] = helpers[owner]
	var slots: Array = []
	for _slot: FlowField in world.flow.fields:
		slots.append(Mirror.new())
	helpers["FLOW"].values[&"fields"] = slots
	for entry: Dictionary in table:
		var key: StringName = StringName(entry.name)
		if entry.owner == "SLOT":
			for slot: int in slots.size():
				slots[slot].values[key] = world.flow.fields[slot].get(key)
		elif entry.name != "fields":
			helpers[entry.owner].values[key] = _sources(world, entry.owner)[0].get(key)
	return root


func _kernels() -> Object:
	var kernels: Object = SimImpls.create_kernels()
	assert_object(kernels).is_not_null()
	return kernels


func _arena() -> World:
	return World.from_scenario(load(ARENA_PATH) as ScenarioDef)


## A World on a map of `cols` x `rows` tiles with three players, three types and two weapons (a
## rifle twin shares the rifle), five rows and the cap of data/rules.tres.
func _odd_world(cols: int, rows: int) -> World:
	var tank: UnitDef = load("res://data/units/light_tank.tres") as UnitDef
	var rifle: UnitDef = load("res://data/units/rifle_squad.tres") as UnitDef
	var twin: UnitDef = rifle.duplicate() as UnitDef
	twin.type_id = &"rifle_twin"
	var spawn: SpawnDef = SpawnDef.new()
	spawn.owner = 1
	spawn.unit = tank
	spawn.count = 5
	spawn.origin_tile = Vector2i(2, 2)
	spawn.columns = 3
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(cols, rows)
	scenario.rules = load("res://data/rules.tres") as RulesDef
	scenario.player_count = 3
	scenario.roster.assign([tank, rifle, twin])
	scenario.spawns.assign([spawn])
	return World.from_scenario(scenario)


## The prepared worlds that check_world accepts: the square arena, an empty World and two maps
## that are not square (one wide, one tall).
func _clean_worlds() -> Array[World]:
	var empty: World = World.new()
	empty.prepare()
	return [_arena(), empty, _odd_world(40, 24), _odd_world(24, 40)]


## The length rule `rule` asks for, from the World's own numbers and the structure constants.
func _rule_length(world: World, rule: String) -> int:
	var cells: int = world.map_cols * world.map_rows
	var padded: int = (world.map_cols + 2) * (world.map_rows + 2)
	var rules: Dictionary[String, int] = {
		"ROWS": world.unit_id.size(),
		"MAX_ROWS": world.max_rows,
		"STATS": 10,  # World.Stat.size(): the three counters of P70 are written by no kernel.
		"TYPES": world.type_speed.size(),
		"WEAPONS": world.weapon_range.size(),
		"ARMOURS": 4 * world.weapon_range.size(),
		"COSTS": 3 * cells,
		"SLOTS": world.flow_cache_size,
		"PADDED": padded,
		"BUCKETS": 512,
		"SEP_GRID": world.sep_grid.cols * world.sep_grid.rows,
		"TARGET_GRID": world.target_grid.cols * world.target_grid.rows,
		"FOG_CELLS": world.fog.player_count * cells,
		"FOG_PLAYERS": world.fog.player_count,
		"FOG_DIRTY": world.fog.player_count * (cells / 4),
	}
	return rules[rule]


## The rows of SIM_CHECKED_TABLE in world_access.h as {owner, name, kind, size, phases}, in line
## order. The pinned counts (107 names, LIST_SIZES) fail a parser that skips a line.
func _table() -> Array[Dictionary]:
	var row: RegEx = RegEx.create_from_string("^\\s*X\\((\\w+), (\\w+), (\\w+), (\\w+), ([^)]+)\\)")
	var table: Array[Dictionary] = []
	for line: String in FileAccess.get_file_as_string(HEADER).split("\n"):
		var found: RegExMatch = row.search(line)
		if found == null:
			continue
		var entry: Dictionary = {"owner": found.get_string(1), "name": found.get_string(2)}
		entry["kind"] = found.get_string(3)
		entry["size"] = found.get_string(4)
		var mask: int = 0
		for token: String in found.get_string(5).split("|"):
			mask |= PHASE_BITS[token.strip_edges()]
		entry["phases"] = mask
		table.append(entry)
	return table


## The table indexes whose name is in the list of `phase`.
func _listed(table: Array[Dictionary], phase: int) -> Array[int]:
	var found: Array[int] = []
	for index: int in table.size():
		if ((table[index].phases >> phase) & 1) == 1:
			found.append(index)
	return found


## The phases whose list holds `entry`.
func _phases_of(entry: Dictionary) -> Array[int]:
	var found: Array[int] = []
	for phase: int in PHASES:
		if ((entry.phases >> phase) & 1) == 1:
			found.append(phase)
	return found


func _names(table: Array[Dictionary], owner: String) -> Array:
	var names: Array = []
	for entry: Dictionary in table:
		if entry.owner == owner:
			names.append(StringName(entry.name))
	return names


## The objects that hold the names of `owner`: the World, a helper, or every slot.
func _sources(world: World, owner: String) -> Array[Object]:
	var by_owner: Dictionary[String, Array] = {"WORLD": [world], "FLOW": [world.flow]}
	by_owner["SLOT"] = world.flow.fields
	by_owner["FOG"] = [world.fog]
	by_owner["SEP"] = [world.sep_grid]
	by_owner["TARGET"] = [world.target_grid]
	var found: Array[Object] = []
	found.assign(by_owner[owner])
	return found


## The names the shape lists (World) or HASHED and UNHASHED (a helper) have for `owner`.
func _lists(owner: String) -> Array:
	var lists: Dictionary[String, Array] = {"FLOW": FlowCache.UNHASHED, "SLOT": FlowField.UNHASHED}
	lists["FOG"] = FogGrid.HASHED + FogGrid.UNHASHED
	lists["SEP"] = SpatialGrid.UNHASHED
	lists["TARGET"] = SpatialGrid.UNHASHED
	if owner != "WORLD":
		return lists[owner]
	var world_lists: Array = World.ROW_ARRAYS + World.TYPE_ARRAYS + World.WEAPON_ARRAYS
	world_lists += World.PROJECTILE_ARRAYS + World.MAP_ARRAYS + World.SCRATCH_ARRAYS
	world_lists += World.PLAYER_ARRAYS + World.ORE_ARRAYS + World.GHOST_ARRAYS
	world_lists += World.DERIVED_ARRAYS
	return world_lists + World.RUNTIME_ARRAYS + World.HASHED_SCALARS + World.UNHASHED_SCALARS
