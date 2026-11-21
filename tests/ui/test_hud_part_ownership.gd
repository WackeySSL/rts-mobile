extends GdUnitTestSuite
## Every HUD script that builds a Node part for itself either parents it in `_init` or frees it on
## `NOTIFICATION_PREDELETE` through `DetachedParts` (P446, P446b). The scan finds the scripts, so a
## new one needs no entry in a hand-kept list.

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UI_DIR: String = "res://game/ui"
const FREE_CALL: String = "DetachedParts.free_unparented("
## A private member initialized with a constructor, typed or not: `var _x: Button = Button.new()`.
const MEMBER: String = r"(?m)^var\s+(_\w+)\s*(?::\s*\w+)?\s*(?::=|=)\s*(\w+)\.new\(\)"


## The class a script name or global class name stands for, or "" when it is not a Node.
func _is_node_class(type_name: String) -> bool:
	var bases: Dictionary = {}
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		bases[str(entry["class"])] = str(entry["base"])
	var name: String = type_name
	while bases.has(name):
		name = str(bases[name])
	return ClassDB.class_exists(name) and ClassDB.is_parent_class(name, "Node")


## The text of the `free_unparented(...)` call in `code`, up to its closing parenthesis; "" if none.
func _free_call(code: String) -> String:
	var at: int = code.find(FREE_CALL)
	if at < 0:
		return ""
	var depth: int = 0
	for i: int in range(at + FREE_CALL.length() - 1, code.length()):
		if code[i] == "(":
			depth += 1
		elif code[i] == ")":
			depth -= 1
			if depth == 0:
				return code.substr(at, i - at + 1)
	return code.substr(at)


## The body of `func _init`, or "".
func _init_body(code: String) -> String:
	var found: RegExMatch = (
		RegEx.create_from_string(r"(?m)^func _init\([^\n]*\n((?:\t[^\n]*\n|\n)*)").search(code)
	)
	return "" if found == null else found.get_string(1)


## Whether `code_part` hands `member` to a parent: `add_child(_x)`, a local `_add(_x, ...)` or
## `_add_button(_x, ...)` helper, or a `for part in [_x, _y]` loop of a body that calls `add_child`.
func _parents(code_part: String, member: String) -> bool:
	var direct: RegEx = RegEx.create_from_string(
		r"(?:add_child|_add|_add_button)\(\s*" + member + r"\b"
	)
	if direct.search(code_part) != null:
		return true
	var looped: RegEx = RegEx.create_from_string(r"for \w+: \w+ in \[[^\]]*\b" + member + r"\b")
	return looped.search(code_part) != null and code_part.contains("add_child(")


func _code(path: String) -> String:
	return "\n".join(FileScan.code_lines(FileAccess.get_file_as_string(path)))


## The `[path, member]` pairs that are Node parts nobody parents or frees.
func _unowned(path: String, code: String) -> Array[String]:
	var found: Array[String] = []
	var call: String = _free_call(code)
	var init_body: String = _init_body(code)
	for hit: RegExMatch in RegEx.create_from_string(MEMBER).search_all(code):
		var member: String = hit.get_string(1)
		if not _is_node_class(hit.get_string(2)):
			continue
		var listed: bool = (
			call != "" and RegEx.create_from_string(r"\b" + member + r"\b").search(call) != null
		)
		# A part under another part is freed with that part, so any `add_child` of it counts when
		# the script frees its roots.
		var parented: bool = _parents(init_body, member) or (call != "" and _parents(code, member))
		if not listed and not parented:
			found.append("%s: %s" % [path, member])
	return found


func test_scan_finds_the_scripts_that_free_their_own_parts() -> void:
	assert_int(_scripts_with_free_call().size()).is_equal(12)


func test_every_node_member_built_with_new_is_parented_in_init_or_freed() -> void:
	var unowned: Array[String] = []
	for path: String in FileScan.list_files(UI_DIR, ".gd"):
		unowned.append_array(_unowned(path, _code(path)))
	(
		assert_array(unowned)
		. override_failure_message(
			(
				"Node members neither parented in _init nor passed to DetachedParts.free_unparented "
				+ "(see game/ui/DetachedParts.gd): %s" % [unowned]
			)
		)
		. is_empty()
	)


func _scripts_with_free_call() -> Array[String]:
	var found: Array[String] = []
	for path: String in FileScan.list_files(UI_DIR, ".gd"):
		if path.ends_with("DetachedParts.gd"):
			continue
		if _free_call(_code(path)) != "":
			found.append(path)
	return found


func test_each_script_that_frees_its_parts_leaves_no_orphans() -> void:
	await await_idle_frame()
	for path: String in _scripts_with_free_call():
		var script: GDScript = load(path)
		var before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
		var node: Node = script.new()
		node.free()
		var leaked: int = (
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) - before
		)
		(
			assert_int(leaked)
			. override_failure_message("%s: orphans leaked: %d" % [path, leaked])
			. is_equal(0)
		)
