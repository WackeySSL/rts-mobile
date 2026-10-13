extends GdUnitTestSuite
## The kernel boundary (ADR 0013 section 2, plan P54): what the library says about itself,
## SimKernels.check_world over the checked table of the five ported phases (on the main thread and
## on a worker Thread), and the table's names against the World's lists. No kernel exists yet, so
## the write cases land with FLOW (P30n). A real World's members are typed and refuse a wrong
## value, so the fault cases check a Mirror, which answers Object.get from a Dictionary. Numbers
## are literals: the status codes are world_status.h's, the phase ids SimProbe.Phase's (SimProbe
## arrives with P33).

const KernelSpy: GDScript = preload("res://tests/sim/support/kernel_spy.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
## FLOW, TARGETING, SEPARATION, INTEGRATE and FOG.
const PHASES: Array[int] = [1, 3, 5, 6, 10]
## The slots of the flow cache (flow_cache_size).
const SLOTS: int = 8
## The names in each list, 106 in the table (a port adds names here, so a dropped or added name
## shows in a diff).
const LIST_SIZES: Dictionary[int, int] = {1: 30, 3: 32, 5: 28, 6: 53, 10: 29}
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


## An Object whose members are the entries of `values`: Object.get falls back to _get, so a member
## can hold a value of any type.
class Mirror:
	extends RefCounted

	var values: Dictionary = {}

	func _get(property: StringName) -> Variant:
		return values.get(property)


func test_the_library_reports_its_abi_and_the_phases_it_implements() -> void:
	var kernels: Object = _kernels()
	assert_str(kernels.get_class()).is_equal("SimKernels")
	assert_int(kernels.abi_version()).is_equal(1)
	assert_int(kernels.phases()).is_equal(SimImpls.expected_mask())


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
	# A spy is no SimKernels: its bits do not make a phase native.
	world.kernels = KernelSpy.new()
	world.native_phases = 0x7FF
	assert_bool(SimImpls.is_native(world, 6)).is_false()


func test_check_world_accepts_a_prepared_world_for_each_of_the_five_phases() -> void:
	var kernels: Object = _kernels()
	var empty: World = World.new()
	empty.prepare()
	for world: World in [_arena(), empty]:
		for phase: int in PHASES:
			var status: int = kernels.check_world(world, phase)
			assert_int(status).override_failure_message("phase %d" % phase).is_equal(0)


## The row count may be max_rows and not one more (a World built past its cap before prepare()).
func test_check_world_allows_exactly_max_rows_rows_and_rejects_one_more() -> void:
	var kernels: Object = _kernels()
	var at: int = _table(kernels).find_custom(
		func(e: Dictionary) -> bool: return e.name == "unit_id"
	)
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
	var table: Array[Dictionary] = _table(_kernels())
	assert_int(table.size()).is_equal(106)
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
	assert_array(_names(table, "FOG")).contains(
		[&"listed", &"dirty", &"dirty_count", &"dirty_full"]
	)


func test_no_bound_method_takes_a_packed_array() -> void:
	var methods: Array[String] = []
	for method: Dictionary in ClassDB.class_get_method_list(&"SimKernels", true):
		methods.append(method.name)
		for argument: Dictionary in method.args:
			var kind: int = argument.type
			var packed: bool = kind >= TYPE_PACKED_BYTE_ARRAY and kind < TYPE_MAX
			var label: String = "%s(%s)" % [method.name, argument.name]
			assert_bool(packed).override_failure_message(label).is_false()
	assert_array(methods).contains(["phases", "check_world", "checked_names"])


## Each name of each list with a wrong type, too long and too short, each helper object and the
## slot objects missing, a phase with no list and no World: the status names the first bad name.
func test_check_world_names_the_first_bad_name_and_what_is_wrong_with_it() -> void:
	var kernels: Object = _kernels()
	var cases: Array[Array] = _fault_cases(_arena(), _table(kernels))
	var tags: Array[String] = []
	for entry: Array in cases:
		var status: int = kernels.check_world(entry[0], entry[1])
		assert_int(status).override_failure_message(entry[3]).is_equal(entry[2])
		tags.append(entry[4])
	# Every kind meets each fault it can have, and the other faults happen.
	for tag: String in ["INT/3", "BOOL/3", "I32/3", "I32/4", "BYTES/3", "BYTES/4", "ARRAY/3"]:
		assert_array(tags).contains([tag])
	for tag: String in ["ARRAY/4", "owner/2", "phase/1", "clean/0", "first/3"]:
		assert_array(tags).contains([tag])


func test_check_world_gives_the_same_statuses_on_a_worker_thread() -> void:
	var kernels: Object = _kernels()
	var cases: Array[Array] = _fault_cases(_arena(), _table(kernels))
	var thread: Thread = Thread.new()
	assert_int(thread.start(_check_all.bind(kernels, cases))).is_equal(OK)
	var found: Array = thread.wait_to_finish()
	assert_int(found.size()).is_equal(cases.size())
	for index: int in cases.size():
		assert_int(found[index]).override_failure_message(cases[index][3]).is_equal(cases[index][2])


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


## SimKernels.checked_names() as {owner, name, kind, size, phases}, in table order.
func _table(kernels: Object) -> Array[Dictionary]:
	var table: Array[Dictionary] = []
	for line: String in kernels.checked_names():
		var part: PackedStringArray = line.split(" ")
		var entry: Dictionary = {"owner": part[0], "name": part[1], "kind": part[2]}
		entry["size"] = part[3]
		entry["phases"] = int(part[4])
		table.append(entry)
	return table


## The table indexes whose name is in the list of `phase`.
func _listed(table: Array[Dictionary], phase: int) -> Array[int]:
	var found: Array[int] = []
	for index: int in table.size():
		if ((table[index].phases >> phase) & 1) == 1:
			found.append(index)
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
	return world_lists + World.RUNTIME_ARRAYS + World.HASHED_SCALARS + World.UNHASHED_SCALARS
