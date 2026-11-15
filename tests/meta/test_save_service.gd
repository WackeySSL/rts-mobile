extends GdUnitTestSuite
## SaveService (ADR 0042 sections 1-3, plan P510): sections, the atomic write, the load order
## after a kill, a bad-hash temp, a newer version, migration v0. Each test uses its own Node
## instance and directory, never the device's file.

const SCRIPT: String = "res://game/meta/save_service.gd"

var _dir: String = ""


func before_test() -> void:
	_dir = "user://test_save_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_test() -> void:
	for file_name: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)


func _service() -> Node:
	var service: Node = auto_free(load(SCRIPT).new())
	service.call("set_path_override", _dir.path_join("save.cfg"))
	return service


func _main() -> String:
	return _dir.path_join("save.cfg")


func _put(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _write_valid(path: String, version: int, values: Dictionary) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", version)
	for key: String in values:
		config.set_value("progress", key, values[key])
	var body: String = config.encode_to_text()
	_put(path, "; sha256=%s\n%s" % [body.sha256_text(), body])


func test_sections_round_trip_through_a_new_instance() -> void:
	var service: Node = _service()
	service.call("set_section", &"progress", {"xp": 120, "name": "a", "flags": [1, 2]})
	service.call("set_section", &"ads", {"granted": true})
	assert_int(service.call("flush")).is_equal(OK)
	var again: Node = _service()
	assert_dict(again.call("get_section", &"progress")).is_equal(
		{"xp": 120, "name": "a", "flags": [1, 2]}
	)
	assert_dict(again.call("get_section", &"ads")).is_equal({"granted": true})
	assert_dict(again.call("get_section", &"absent")).is_empty()


func test_get_section_is_a_copy_and_unknown_sections_survive() -> void:
	var service: Node = _service()
	service.call("set_section", &"future", {"k": 1})
	var copy: Dictionary = service.call("get_section", &"future")
	copy["k"] = 99
	assert_dict(service.call("get_section", &"future")).is_equal({"k": 1})
	service.call("flush")
	assert_dict(_service().call("get_section", &"future")).is_equal({"k": 1})


func test_saved_signal_and_clean_flush_writes_nothing() -> void:
	var service: Node = _service()
	var count: Array[int] = [0]
	service.connect("saved", func() -> void: count[0] += 1)
	assert_int(service.call("flush")).is_equal(OK)
	assert_int(count[0]).is_equal(0)
	service.call("set_section", &"settings", {"a": 1})
	service.call("flush")
	assert_int(count[0]).is_equal(1)
	assert_bool(FileAccess.file_exists(_main())).is_true()
	assert_bool(FileAccess.file_exists(_main() + ".tmp")).is_false()


func test_second_write_keeps_the_previous_file_as_bak() -> void:
	var service: Node = _service()
	service.call("set_section", &"settings", {"a": 1})
	service.call("flush")
	service.call("set_section", &"settings", {"a": 2})
	service.call("flush")
	DirAccess.remove_absolute(_main())
	assert_dict(_service().call("get_section", &"settings")).is_equal({"a": 1})


func test_kill_between_the_renames_keeps_the_newest_data() -> void:
	var service: Node = _service()
	service.call("set_section", &"progress", {"xp": 1})
	service.call("flush")
	service.call("set_section", &"progress", {"xp": 2})
	service.call("flush")
	# Rebuild the state of a kill after the temp was written and before either rename:
	# main holds xp 1, the temp holds xp 2.
	var newest: String = FileAccess.get_file_as_string(_main())
	var older: String = FileAccess.get_file_as_string(_main() + ".bak")
	_put(_main(), older)
	DirAccess.remove_absolute(_main() + ".bak")
	_put(_main() + ".tmp", newest)
	var loaded: Node = _service()
	assert_dict(loaded.call("get_section", &"progress")).is_equal({"xp": 2})
	# The load finished the renames: no temp, the new file is main, the old one is bak.
	assert_bool(FileAccess.file_exists(_main() + ".tmp")).is_false()
	assert_str(FileAccess.get_file_as_string(_main())).is_equal(newest)
	assert_str(FileAccess.get_file_as_string(_main() + ".bak")).is_equal(older)
	assert_dict(_service().call("get_section", &"progress")).is_equal({"xp": 2})


func test_kill_after_the_first_rename_loads_the_temp() -> void:
	var service: Node = _service()
	service.call("set_section", &"progress", {"xp": 7})
	service.call("flush")
	DirAccess.rename_absolute(_main(), _main() + ".tmp")  # main is gone, temp holds the data
	assert_dict(_service().call("get_section", &"progress")).is_equal({"xp": 7})
	assert_bool(FileAccess.file_exists(_main())).is_true()


func test_bad_hash_temp_is_deleted_and_main_wins() -> void:
	var service: Node = _service()
	service.call("set_section", &"progress", {"xp": 1})
	service.call("flush")
	_put(_main() + ".tmp", "; sha256=deadbeef\n[progress]\nxp=999\n")
	assert_dict(_service().call("get_section", &"progress")).is_equal({"xp": 1})
	assert_bool(FileAccess.file_exists(_main() + ".tmp")).is_false()


func test_bad_main_falls_back_to_bak_and_is_kept_as_bad() -> void:
	var service: Node = _service()
	service.call("set_section", &"progress", {"xp": 1})
	service.call("flush")
	service.call("set_section", &"progress", {"xp": 2})
	service.call("flush")
	_put(_main(), "garbage")
	assert_dict(_service().call("get_section", &"progress")).is_equal({"xp": 1})
	assert_bool(FileAccess.file_exists(_main() + ".bad")).is_true()


func test_newer_version_is_read_only_and_never_written() -> void:
	_write_valid(_main(), 99, {"xp": 5})
	var before: String = FileAccess.get_file_as_string(_main())
	var service: Node = _service()
	assert_bool(service.call("is_read_only")).is_true()
	assert_dict(service.call("get_section", &"progress")).is_equal({"xp": 5})
	service.call("set_section", &"progress", {"xp": 6})
	assert_int(service.call("flush")).is_equal(ERR_LOCKED)
	assert_str(FileAccess.get_file_as_string(_main())).is_equal(before)
	assert_bool(FileAccess.file_exists(_main() + ".bak")).is_false()


func test_migration_v0_moves_hud_keys_and_deletes_settings_cfg() -> void:
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("hud", "haptics", false)
	legacy.set_value("hud", "build_menu_pinned", true)
	legacy.save(_dir.path_join("settings.cfg"))
	var service: Node = _service()
	assert_dict(service.call("get_section", &"hud")).is_equal(
		{"haptics": false, "build_menu_pinned": true}
	)
	assert_bool(FileAccess.file_exists(_main())).is_true()
	assert_bool(FileAccess.file_exists(_dir.path_join("settings.cfg"))).is_false()
	assert_dict(_service().call("get_section", &"hud")).is_equal(
		{"haptics": false, "build_menu_pinned": true}
	)


func test_save_cfg_wins_over_a_stale_settings_cfg() -> void:
	var service: Node = _service()
	service.call("set_section", &"hud", {"haptics": true})
	service.call("flush")
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("hud", "haptics", false)
	legacy.save(_dir.path_join("settings.cfg"))
	assert_dict(_service().call("get_section", &"hud")).is_equal({"haptics": true})


func test_meta_section_is_reserved_and_version_is_written() -> void:
	var service: Node = _service()
	service.call("set_section", &"meta", {"version": 50})
	service.call("set_section", &"settings", {"a": 1})
	service.call("flush")
	var config: ConfigFile = ConfigFile.new()
	var text: String = FileAccess.get_file_as_string(_main())
	assert_int(config.parse(text.substr(text.find("\n") + 1))).is_equal(OK)
	assert_int(config.get_value("meta", "version")).is_equal(1)
