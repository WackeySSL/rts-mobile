extends GdUnitTestSuite
## SaveService (ADR 0042 sections 1-5, plan P510): sections, the atomic write, the load order
## after a kill, a bad-hash temp, a newer version, migration, value validation, the lifecycle
## flush. Each test uses its own Node instance and directory, never the device's file.

const SCRIPT: String = "res://game/meta/save_service.gd"
const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")

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


func test_kill_after_main_became_bak_keeps_the_existing_bak() -> void:
	var service: Node = _service()
	service.call("set_section", &"progress", {"xp": 1})
	service.call("flush")
	service.call("set_section", &"progress", {"xp": 2})
	service.call("flush")
	# A kill after main -> bak and before tmp -> main: no main, bak holds xp 1, the temp xp 2.
	var newest: String = FileAccess.get_file_as_string(_main())
	var older: String = FileAccess.get_file_as_string(_main() + ".bak")
	DirAccess.remove_absolute(_main())
	_put(_main() + ".tmp", newest)
	assert_dict(_service().call("get_section", &"progress")).is_equal({"xp": 2})
	assert_str(FileAccess.get_file_as_string(_main())).is_equal(newest)
	assert_str(FileAccess.get_file_as_string(_main() + ".bak")).is_equal(older)
	assert_bool(FileAccess.file_exists(_main() + ".tmp")).is_false()


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


func test_both_files_corrupt_keeps_two_distinct_bad_copies() -> void:
	var service: Node = _service()
	service.call("set_section", &"progress", {"xp": 1})
	service.call("flush")
	service.call("set_section", &"progress", {"xp": 2})
	service.call("flush")
	_put(_main(), "garbage main")
	_put(_main() + ".bak", "garbage bak")
	assert_dict(_service().call("get_section", &"progress")).is_empty()
	assert_str(FileAccess.get_file_as_string(_main() + ".bad")).is_equal("garbage main")
	assert_str(FileAccess.get_file_as_string(_main() + ".bak.bad")).is_equal("garbage bak")


func test_newer_version_is_read_only_and_never_written() -> void:
	_write_valid(_main(), 99, {"xp": 5})
	var before: String = FileAccess.get_file_as_string(_main())
	var holder: Array[Node] = []
	await (
		assert_error(func() -> void: holder.append(_service()))
		. is_push_warning("SaveService: save file is version 99, this app knows 1; not writing")
	)
	var service: Node = holder[0]
	assert_bool(service.call("is_read_only")).is_true()
	assert_dict(service.call("get_section", &"progress")).is_equal({"xp": 5})
	service.call("set_section", &"progress", {"xp": 6})
	assert_int(service.call("flush")).is_equal(ERR_LOCKED)
	assert_str(FileAccess.get_file_as_string(_main())).is_equal(before)
	assert_bool(FileAccess.file_exists(_main() + ".bak")).is_false()


func test_migration_v0_copies_hud_keys_and_deletes_settings_cfg() -> void:
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


## P510b: HudPrefs reads the migrated key; a Vibration=off survives, and the old file is gone.
func test_hud_prefs_read_a_migrated_vibration_off_and_persist() -> void:
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("hud", "haptics", false)
	legacy.save(_dir.path_join("settings.cfg"))
	PrefsRig.use(_main())
	assert_bool(HudPrefs.haptics_enabled()).is_false()
	assert_bool(FileAccess.file_exists(_dir.path_join("settings.cfg"))).is_false()
	HudPrefs.set_haptics_enabled(true)
	PrefsRig.use(_main())  # Drains, then reloads from the file.
	assert_bool(HudPrefs.haptics_enabled()).is_true()
	HudPrefs.set_haptics_enabled(false)
	PrefsRig.restore()
	PrefsRig.use(_main())
	assert_bool(HudPrefs.haptics_enabled()).is_false()
	PrefsRig.restore()  # Never the device's path.


func test_migration_v0_without_a_hud_section_does_nothing() -> void:
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("other", "k", 1)
	legacy.save(_dir.path_join("settings.cfg"))
	var service: Node = _service()
	assert_dict(service.call("get_section", &"hud")).is_empty()
	assert_bool(FileAccess.file_exists(_main())).is_false()


func test_no_migration_over_corrupt_save_files() -> void:
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("hud", "haptics", false)
	legacy.save(_dir.path_join("settings.cfg"))
	_put(_main(), "garbage")
	var service: Node = _service()
	assert_dict(service.call("get_section", &"hud")).is_empty()
	assert_bool(FileAccess.file_exists(_main() + ".bad")).is_true()


## A settings.cfg beside an existing save (a build between P510 and P510b wrote it) is newer for
## `hud`: its keys go over the section, the other keys stay, and the file is deleted.
func test_a_settings_cfg_beside_a_save_is_taken_over_and_deleted() -> void:
	var service: Node = _service()
	service.call("set_section", &"hud", {"haptics": true, "build_menu_pinned": true})
	service.call("set_section", &"progress", {"xp": 3})
	service.call("flush")
	var legacy: ConfigFile = ConfigFile.new()
	legacy.set_value("hud", "haptics", false)
	legacy.save(_dir.path_join("settings.cfg"))
	var again: Node = _service()
	assert_dict(again.call("get_section", &"hud")).is_equal(
		{"haptics": false, "build_menu_pinned": true}
	)
	assert_dict(again.call("get_section", &"progress")).is_equal({"xp": 3})
	assert_bool(FileAccess.file_exists(_dir.path_join("settings.cfg"))).is_false()
	assert_dict(_service().call("get_section", &"hud")).is_equal(
		{"haptics": false, "build_menu_pinned": true}
	)


## A legacy section that set_section refuses is not deleted: nothing was persisted.
func test_settings_cfg_stays_when_its_hud_section_cannot_be_saved() -> void:
	_put(_dir.path_join("settings.cfg"), "[hud]\n\nhaptics=nan\n")
	var errors: Array[String] = []
	var service: Node = auto_free(load(SCRIPT).new())
	service.set("error_sink", func(text: String) -> void: errors.append(text))
	service.call("set_path_override", _main())
	assert_bool(FileAccess.file_exists(_dir.path_join("settings.cfg"))).is_true()
	assert_dict(service.call("get_section", &"hud")).is_empty()
	assert_array(errors).has_size(1)


func test_file_without_a_version_is_migrated_and_restamped() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("progress", "xp", 9)
	var body: String = config.encode_to_text()
	_put(_main(), "; sha256=%s\n%s" % [body.sha256_text(), body])
	var service: Node = _service()
	assert_dict(service.call("get_section", &"progress")).is_equal({"xp": 9})
	assert_int(service.call("flush")).is_equal(OK)
	var text: String = FileAccess.get_file_as_string(_main())
	var written: ConfigFile = ConfigFile.new()
	written.parse(text.substr(text.find("\n") + 1))
	assert_int(written.get_value("meta", "version")).is_equal(1)
	assert_dict(_service().call("get_section", &"progress")).is_equal({"xp": 9})
