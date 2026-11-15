extends GdUnitTestSuite
## SaveService, part 2 (plan P510): reserved section, value validation, the failed read-back, the
## coalesced and lifecycle flushes, switching the test path. Part 1 is test_save_service.gd.

const SCRIPT: String = "res://game/meta/save_service.gd"

var _dir: String = ""


## The service whose first write fails its read-back.
class FlakyService:
	extends "res://game/meta/save_service.gd"
	var fail_once: bool = true

	func _write() -> Error:
		if fail_once:
			fail_once = false
			return ERR_FILE_CORRUPT
		return super()


func before_test() -> void:
	_dir = "user://test_save_values_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_test() -> void:
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func _service() -> Node:
	var service: Node = auto_free(load(SCRIPT).new())
	service.call("set_path_override", _dir.path_join("save.cfg"))
	return service


## An instance in the tree (its coalesced write runs from _process). The path is set before it
## enters, so _ready never reads the device's file.
func _tree_service() -> Node:
	var service: Node = _service()
	add_child(service)
	return service


func _main() -> String:
	return _dir.path_join("save.cfg")


func test_meta_section_is_reserved_and_version_is_written() -> void:
	var service: Node = _service()
	await (
		assert_error(func() -> void: service.call("set_section", &"meta", {"version": 50}))
		. is_push_warning("SaveService: section 'meta' is reserved")
	)
	service.call("set_section", &"settings", {"a": 1})
	service.call("flush")
	var config: ConfigFile = ConfigFile.new()
	var text: String = FileAccess.get_file_as_string(_main())
	assert_int(config.parse(text.substr(text.find("\n") + 1))).is_equal(OK)
	assert_int(config.get_value("meta", "version")).is_equal(1)


func test_set_section_coalesces_to_one_write_per_frame() -> void:
	var service: Node = _tree_service()
	var count: Array[int] = [0]
	service.connect("saved", func() -> void: count[0] += 1)
	service.call("set_section", &"progress", {"xp": 1})
	service.call("set_section", &"progress", {"xp": 2})
	service.call("set_section", &"settings", {"a": 1})
	assert_bool(FileAccess.file_exists(_main())).is_false()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(count[0]).is_equal(1)
	assert_dict(_service().call("get_section", &"progress")).is_equal({"xp": 2})


func test_lifecycle_notifications_flush_synchronously() -> void:
	var notifications: Array[int] = [
		Node.NOTIFICATION_APPLICATION_PAUSED,
		Node.NOTIFICATION_APPLICATION_FOCUS_OUT,
		Node.NOTIFICATION_WM_CLOSE_REQUEST,
	]
	for what: int in notifications:
		var service: Node = _service()
		service.call("set_section", &"progress", {"xp": what})
		service.notification(what)
		assert_dict(_service().call("get_section", &"progress")).is_equal({"xp": what})


func test_unsaveable_values_are_refused_and_later_saves_still_work() -> void:
	var service: Node = _service()
	var refused: Array[Dictionary] = [
		{"k": RefCounted.new()},
		{"k": null},
		{"k": [1, RefCounted.new()]},
		{"k": {"inner": RefCounted.new()}},
		{"k": NAN},
		{"a=b": 1},
		{"a]b": 1},
		{"a\nb": 1},
		{"": 1},
		{1: 1},
	]
	for values: Dictionary in refused:
		var accepted: Array[bool] = [true]
		await (
			assert_error(func() -> void: accepted[0] = service.call("set_section", &"s", values))
			. is_push_error(_refusal(values))
		)
		assert_bool(accepted[0]).is_false()
	assert_dict(service.call("get_section", &"s")).is_empty()
	var good: Dictionary = {
		"b": true,
		"i": 1,
		"f": 1.5,
		"s": "text",
		"n": &"name",
		"a": [1, "two", [3]],
		"d": {"x": 1, 2: "y"},
		"p": PackedInt32Array([1, 2]),
		"ps": PackedStringArray(["a", "b"]),
	}
	assert_bool(service.call("set_section", &"s", good)).is_true()
	assert_int(service.call("flush")).is_equal(OK)
	var again: Dictionary = _service().call("get_section", &"s")
	assert_array(again["a"]).is_equal([1, "two", [3]])
	assert_dict(again["d"]).is_equal({"x": 1, 2: "y"})
	assert_bool(again["p"] == PackedInt32Array([1, 2])).is_true()


## The error text the service pushes for a refused section `s` (what is wrong is not the point;
## that it is refused and says so is).
func _refusal(values: Dictionary) -> String:
	var key: Variant = values.keys()[0]
	var value: Variant = values[key]
	var problem: String = ""
	if not (key is String):
		problem = "key %s is not a String" % str(key)
	elif key == "":
		problem = "empty label or edge spaces"
	elif String(key).contains("=") or String(key).contains("]") or String(key).contains("\n"):
		problem = "label '%s' has a forbidden character" % String(key).c_escape()
	elif value == null:
		problem = "a value of type %d cannot be saved" % TYPE_NIL
	elif value is float:
		problem = "NaN"
	else:
		problem = "a value of type %d cannot be saved" % TYPE_OBJECT
	return "SaveService: section 's' refused: " + problem


func test_a_failed_read_back_drops_only_the_offending_section() -> void:
	var service: Node = auto_free(FlakyService.new())
	service.call("set_path_override", _main())
	service.call("set_section", &"good", {"k": 1})
	# Bypass the validation: an Object parses back as another value, and the first read-back
	# (forced to fail here) sends the service looking for the section that does not round-trip.
	(service.get("_sections") as Dictionary)["bad"] = {"k": RefCounted.new()}
	service.set("_dirty", true)
	var result: Array[int] = [-1]
	await (
		assert_error(func() -> void: result[0] = service.call("flush"))
		. is_push_error("SaveService: section 'bad' does not survive the file; not saved")
	)
	assert_int(result[0]).is_equal(OK)
	var again: Node = _service()
	assert_dict(again.call("get_section", &"good")).is_equal({"k": 1})
	assert_dict(again.call("get_section", &"bad")).is_empty()
	# The flagged section stays in memory; replacing it with good data saves it.
	assert_bool(service.call("set_section", &"bad", {"k": 2})).is_true()
	assert_int(service.call("flush")).is_equal(OK)
	assert_dict(_service().call("get_section", &"bad")).is_equal({"k": 2})


func test_switching_the_path_saves_pending_changes_to_the_old_path_first() -> void:
	var service: Node = _service()
	service.call("set_section", &"progress", {"xp": 3})
	service.call("set_path_override", _dir.path_join("other.cfg"))
	assert_dict(service.call("get_section", &"progress")).is_empty()
	service.call("set_path_override", _main())
	assert_dict(service.call("get_section", &"progress")).is_equal({"xp": 3})
