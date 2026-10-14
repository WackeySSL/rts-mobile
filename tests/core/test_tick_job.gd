extends GdUnitTestSuite
## TickJob's guards (ADR 0012 section 2, plan P38j): a job that may run on a worker thread holds
## only sim objects, reaches no Node and no Resource, and its files name no tree, input, OS,
## autoload, signal or deferred call. The jobs here run the perf arena (seed 42) directly, with no
## runner, the native kernels attached (ADR 0013 section 3; verify.sh always builds the library).

const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const HoldingProbe: GDScript = preload("res://tests/core/support/holding_probe.gd")
const ARENA_PATH: String = "res://data/scenarios/perf_arena.tres"
const SEED: int = 42
## The types a TickJob property may have, and the contract's fields with theirs.
const ALLOWED_TYPES: Array[String] = [
	"World", "MatchLoop", "SimProbe", "MatchSnapshot", "Array[Command]", "Semaphore", "int", "bool"
]
const CONTRACT_FIELDS: Dictionary[String, String] = {
	"world": "World",
	"loop": "MatchLoop",
	"probe": "SimProbe",
	"commands": "Array[Command]",
	"snapshot": "MatchSnapshot",
	"previous": "MatchSnapshot",
	"post_usec": "int",
	"end_usec": "int",
}
## The code that runs inside TickJob.run() on the worker.
const WORKER_FILES: Array[String] = [
	"res://game/core/TickJob.gd",
	"res://game/core/MatchSnapshot.gd",
	"res://game/core/TimingProbe.gd",
	"res://game/core/StepProbe.gd",
]
## The banned names, each matched in code after string literals and comments are stripped, with a
## line it must flag and a legal line it must pass, at the same index.
const BANNED: Array[String] = [
	r"\bget_tree\b",
	r"\bget_node\b",
	r"\bEngine\.",
	r"\bInput\.",
	r"\bOS\.",
	r"\bCommandQueue\b",
	r"\bDetRng\b",
	r"\bsignal\s",
	r"\.emit\(",
	r"\bcall_deferred\(",
]
const FLAGGED: Array[String] = [
	"var tree: SceneTree = get_tree()",
	'var hud: Node = get_node("Hud")',
	"var frame: int = Engine.get_process_frames()",
	'if Input.is_action_pressed("ui_accept"):',
	"OS.delay_msec(1)",
	"CommandQueue.drain_into(commands)",
	"var rng: DetRandom = DetRng.create(1, 2)",
	"signal published(tick: int)",
	"published.emit(snapshot.tick)",
	'call_deferred("publish")',
]
const LEGAL: Array[String] = [
	"var budget_tree: int = 0",
	"var budget_node: int = 0",
	'var label: String = "Engine.get_process_frames()"',
	"TouchInput.reset()",
	"var x: int = pos_x[0]  # OS.delay_msec(1) is banned",
	"var stats: CommandQueueStats = null",
	"var rng: DetRandom = world.rng  # not DetRng",
	"var signal_count: int = 0",
	"var count: int = probe.emitted(1)",
	"var call_deferred_count: int = 0",
]
const STRING_LITERAL: String = r"\"(?:[^\"\\]|\\.)*\"|'(?:[^'\\]|\\.)*'"


## Every script variable of a TickJob has an allowed type, and the contract's fields are there with
## theirs. run() steps the tick, captures it, and empties the command list after the step: the
## command is applied once, and a second run neither records nor stamps it again.
func test_the_property_list_holds_only_the_allowed_types_and_run_clears_the_commands() -> void:
	var job: TickJob = _arena_job()
	var types: Dictionary[String, String] = {}
	for property: Dictionary in job.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			types[String(property["name"])] = _type_name(property)
	var wrong: Array[String] = []
	for name: String in types:
		if not ALLOWED_TYPES.has(types[name]):
			wrong.append("%s: %s" % [name, types[name]])
	assert_array(wrong).is_empty()
	for name: String in CONTRACT_FIELDS:
		assert_str(types.get(name, "missing")).override_failure_message(name).is_equal(
			CONTRACT_FIELDS[name]
		)
	var command: Command = Command.move(1, PackedInt32Array([1]), 30500, 20500)
	job.commands.append(command)
	job.run()
	assert_bool(job.commands.is_empty()).is_true()
	# The arena's two scenario orders come first.
	assert_array([command.tick, command.sequence, job.loop.next_sequence]).is_equal([0, 2, 3])
	assert_array([job.snapshot.tick, job.world.tick]).is_equal([1, 1])
	var logged: int = job.loop.replay.commands.size()
	job.previous = job.snapshot
	job.snapshot = _new_snapshot()
	job.run()
	assert_array([command.tick, command.sequence, job.loop.next_sequence]).is_equal([0, 2, 3])
	assert_array([job.snapshot.tick, job.loop.replay.commands.size()]).is_equal([2, logged])


## The walk goes from a job on the prepared arena through script variables and Array and
## Dictionary keys and values: the World (with the native kernels as a leaf), the MatchLoop and
## its Replay, the StepProbe and a TimingProbe, the command list and both snapshots. It finds no
## Node and no Resource, before and after a run. A probe behind the StepProbe that holds a Node, or
## a Resource in an Array or a Dictionary, is found, and so are kernels that are a Node.
func test_nothing_reachable_from_a_job_is_a_node_or_a_resource() -> void:
	var job: TickJob = _arena_job()
	assert_array(SimImpls.use(job.world, SimImpls.Impl.NATIVE)).is_empty()
	var step: StepProbe = job.probe as StepProbe
	var timing: TimingProbe = TimingProbe.new()
	step.target = timing
	var command: Command = Command.move(1, PackedInt32Array([1]), 30500, 20500)
	job.commands.append(command)
	var visited: Dictionary = {}
	assert_array(_engine_objects(job, visited)).is_empty()
	var reached: Array[Object] = [job.world, job.world.rng, job.world.fog, job.world.flow]
	reached.append_array([job.loop, job.loop.replay, step, timing, command])
	reached.append_array([job.previous, job.previous.fog, job.snapshot])
	for object: Object in reached:
		(
			assert_bool(visited.has(object.get_instance_id()))
			. override_failure_message(str(object))
			. is_true()
		)
	assert_bool(visited.has(job.world.kernels.get_instance_id())).is_false()
	job.run()
	visited.clear()
	assert_array(_engine_objects(job, visited)).is_empty()
	assert_bool(visited.has(job.snapshot.fog.get_instance_id())).is_true()
	var holding: SimProbe = HoldingProbe.new()
	step.target = holding
	var node: Node = auto_free(Node.new())
	holding.held = node
	assert_array(_engine_objects(job, {})).is_equal(["job.probe.target.held: Node"])
	var resource: Resource = Resource.new()
	holding.held = [{&"inner": resource}]
	assert_array(_engine_objects(job, {})).is_equal(["job.probe.target.held[0][inner]: Resource"])
	holding.held = {resource: 1}
	assert_array(_engine_objects(job, {})).is_equal(["job.probe.target.held.key: Resource"])
	holding.held = null
	job.world.kernels = node
	assert_array(_engine_objects(job, {})).is_equal(["job.world.kernels: Node"])


func test_the_worker_files_use_none_of_the_banned_names() -> void:
	var patterns: Array[RegEx] = _compile_all(BANNED)
	var strings: RegEx = RegEx.create_from_string(STRING_LITERAL)
	var violations: Array[String] = []
	for path: String in WORKER_FILES:
		var source: String = FileAccess.get_file_as_string(path)
		assert_str(source).override_failure_message(path).contains("func ")
		var lines: PackedStringArray = source.split("\n")
		for index: int in lines.size():
			if _banned_in(lines[index], patterns, strings) >= 0:
				violations.append("%s:%d: %s" % [path, index + 1, lines[index]])
	assert_array(violations).is_empty()


## Each banned name flags its own fixture line, and its legal line (the name inside another word,
## in a string or in a comment, or a near miss) passes every pattern.
func test_the_scan_flags_each_banned_name_and_passes_its_legal_line() -> void:
	var patterns: Array[RegEx] = _compile_all(BANNED)
	var strings: RegEx = RegEx.create_from_string(STRING_LITERAL)
	assert_array([FLAGGED.size(), LEGAL.size()]).is_equal([BANNED.size(), BANNED.size()])
	for index: int in BANNED.size():
		(
			assert_int(_banned_in(FLAGGED[index], patterns, strings))
			. override_failure_message(FLAGGED[index])
			. is_equal(index)
		)
		(
			assert_int(_banned_in(LEGAL[index], patterns, strings))
			. override_failure_message(LEGAL[index])
			. is_equal(-1)
		)


## A job on the arena with seed 42 at tick 0, as the runner hands it over: the World, the loop,
## a StepProbe without a target, an empty command list, the tick-0 snapshot as `previous` and a
## new snapshot of the same match.
func _arena_job() -> TickJob:
	var scenario: ScenarioDef = load(ARENA_PATH) as ScenarioDef
	var job: TickJob = TickJob.new()
	job.world = World.from_scenario(scenario, DetRandom.create(SEED, DetRandom.STREAM_SIM))
	job.loop = MatchLoop.create(scenario, ARENA_PATH, SEED, job.world)
	job.probe = StepProbe.new()
	job.previous = _new_snapshot()
	job.previous.capture(job.world, null)
	job.snapshot = _new_snapshot()
	return job


func _new_snapshot() -> MatchSnapshot:
	var snapshot: MatchSnapshot = MatchSnapshot.new()
	snapshot.match_serial = 1
	return snapshot


## "int", "bool", a class name, or "Array[Class]" for a typed Array; anything else by type id.
func _type_name(property: Dictionary) -> String:
	match int(property["type"]):
		TYPE_INT:
			return "int"
		TYPE_BOOL:
			return "bool"
		TYPE_OBJECT:
			return String(property["class_name"])
		TYPE_ARRAY:
			if int(property["hint"]) == PROPERTY_HINT_ARRAY_TYPE:
				return "Array[%s]" % property["hint_string"]
	return "type %d" % int(property["type"])


## Every Node or Resource reachable from `root` through script variables and Array and Dictionary
## keys and values, as "path: class". `visited` gets each object walked (instance id to path), so
## a cycle ends there. A World's NON_STATE_MEMBERS (the kernels, a RefCounted) are leaves: checked,
## never walked.
func _engine_objects(root: Object, visited: Dictionary) -> Array[String]:
	var found: Array[String] = []
	_walk(root, "job", visited, found)
	return found


func _walk(value: Variant, path: String, visited: Dictionary, found: Array[String]) -> void:
	match typeof(value):
		TYPE_ARRAY:
			var items: Array = value
			for index: int in items.size():
				_walk(items[index], "%s[%d]" % [path, index], visited, found)
		TYPE_DICTIONARY:
			var entries: Dictionary = value
			for key: Variant in entries:
				_walk(key, path + ".key", visited, found)
				_walk(entries[key], "%s[%s]" % [path, str(key)], visited, found)
		TYPE_OBJECT:
			var object: Object = value
			if object == null or _found(object, path, found):
				return
			if visited.has(object.get_instance_id()):
				return
			visited[object.get_instance_id()] = path
			var leaves: Array[StringName] = []
			if object is World:
				leaves = World.NON_STATE_MEMBERS
			for property: Dictionary in object.get_property_list():
				if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
					continue
				var name: StringName = property["name"]
				var child: Variant = object.get(name)
				var child_path: String = "%s.%s" % [path, name]
				if not leaves.has(name):
					_walk(child, child_path, visited, found)
				elif child is Object:
					_found(child, child_path, found)


## Adds `object` to `found` when it is a Node or a Resource, and says whether it did.
func _found(object: Object, path: String, found: Array[String]) -> bool:
	if object is Node or object is Resource:
		found.append("%s: %s" % [path, object.get_class()])
		return true
	return false


func _compile_all(sources: Array[String]) -> Array[RegEx]:
	var compiled: Array[RegEx] = []
	for source: String in sources:
		var regex: RegEx = RegEx.create_from_string(source)
		assert_bool(regex.is_valid()).override_failure_message(source).is_true()
		compiled.append(regex)
	return compiled


## The index of the first pattern that matches the code of `line` (string literals and the comment
## stripped), or -1.
func _banned_in(line: String, patterns: Array[RegEx], strings: RegEx) -> int:
	var code: String = strings.sub(line, '""', true)
	var comment: int = code.find("#")
	if comment >= 0:
		code = code.substr(0, comment)
	for index: int in patterns.size():
		if patterns[index].search(code) != null:
			return index
	return -1
