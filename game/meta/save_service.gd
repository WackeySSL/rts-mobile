extends Node
## The device's one save file (ADR 0042 sections 1-5): `user://save.cfg`, a ConfigFile of
## sections, `meta.version`, and a first line `; sha256=<hex of the rest>`. Phase 6 keeps its
## section `ads` here through `get_section` / `set_section` (no ads.cfg). Main thread only.
## No class_name: this is an autoload (tests/project/test_autoloads.gd). Never touched by game/sim.
##
## Write: temp file, read back and hash-check, then bak <- main and main <- temp. Load, newest
## first: a hash-valid `.tmp` (the app was killed between the renames; the load finishes them),
## then `save.cfg`, then `.bak`. Each rename tries to replace an existing target first (atomic on
## Linux and Android, so the file system's replace-by-rename flush applies) and only on an error
## removes the target and renames again (platforms where rename does not replace). Every kill
## point between the steps still leaves a valid file to load. Limits: Godot has no fsync API, so
## a power cut right after a rename is not covered beyond what the file system does; and rename
## durability on the web's IndexedDB-backed `user://` is unverified (a phone or browser check in
## the Phase 5 gate).
##
## Versions: a hash-valid file without `meta.version` is read as version 0 and goes through the
## `_migrate` steps (0 -> 1 keeps every section; only this service writes the hash line), then is
## rewritten with its version. Migration v0 of the ADR is a different thing: no save file of any
## kind, but a `settings.cfg`: its `[hud]` keys are copied into section `hud`, and `settings.cfg`
## is deleted after that first good write (`HudPrefs` reads this service now, not that file).

## Fires after a successful write.
signal saved

const VERSION: int = 1
const PATH: String = "user://save.cfg"
const META: String = "meta"
const KEY_VERSION: String = "version"
const KEY_APP_VERSION: String = "app_version"
const LEGACY_FILE: String = "settings.cfg"
const LEGACY_SECTION: String = "hud"
const HASH_PREFIX: String = "; sha256="
const MAX_DEPTH: int = 8
const SAVABLE_TYPES: Array[int] = [
	TYPE_BOOL,
	TYPE_INT,
	TYPE_STRING,
	TYPE_STRING_NAME,
	TYPE_PACKED_BYTE_ARRAY,
	TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY,
	TYPE_PACKED_FLOAT32_ARRAY,
	TYPE_PACKED_FLOAT64_ARRAY,
	TYPE_PACKED_STRING_ARRAY,
]
const NAME_FORBIDDEN: String = '=[];"\n\r'

## A test seam: where the error messages go instead of push_error (unset: push_error). A test
## that expects an error reads it here, so the log verify.sh scans has no ERROR line.
var error_sink: Callable = Callable()

var _path_override: String = ""
var _sections: Dictionary = {}  # String -> Dictionary
var _unwritable: Dictionary = {}  # String -> true: kept in memory, left out of the file
var _dirty: bool = false
var _read_only: bool = false


func _ready() -> void:
	# A paused match must not stop the coalesced write.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_load()


## The coalesced write: one flush at the end of the frame that changed a section.
func _process(_delta: float) -> void:
	flush()


## ADR 0042 section 5: the app going to the background, losing focus or closing writes at once.
func _notification(what: int) -> void:
	if (
		what == NOTIFICATION_APPLICATION_PAUSED
		or what == NOTIFICATION_APPLICATION_FOCUS_OUT
		or what == NOTIFICATION_WM_CLOSE_REQUEST
	):
		flush()


func _exit_tree() -> void:
	if _dirty:
		flush()


## Tests: read and write `path` (and its `.tmp`, `.bak`, `.bad`, and the legacy `settings.cfg`
## beside it) instead of the device's file. Pending changes go to the old path first. Reloads.
func set_path_override(path: String) -> void:
	_drain_before_switch()
	_path_override = path
	_load()


func clear_path_override() -> void:
	_drain_before_switch()
	_path_override = ""
	_load()


func path() -> String:
	return _path_override if _path_override != "" else PATH


## True when the file on disk is from a newer app: sections are readable, nothing is written.
func is_read_only() -> bool:
	return _read_only


## A copy of the section (empty when absent).
func get_section(section: StringName) -> Dictionary:
	var values: Variant = _sections.get(String(section), {})
	return (values as Dictionary).duplicate(true)


## Replaces the whole section and queues one write for this frame's end. Returns false (and
## changes nothing) when the section or a value would not survive the file: names and keys are
## non-empty Strings without `= [ ] ; "` or a line break and without edge spaces; values are
## bool, int, float (not NaN), String, StringName, Array, Dictionary (String, StringName or int
## keys) or a packed array of numbers or strings, never null or an Object. `meta` is the
## service's.
func set_section(section: StringName, values: Dictionary) -> bool:
	var section_name: String = String(section)
	if section_name == META:
		push_warning("SaveService: section 'meta' is reserved")
		return false
	var problem: String = _name_problem(section_name)
	for key: Variant in values:
		if problem != "":
			break
		if not (key is String or key is StringName):
			problem = "key %s is not a String" % str(key)
		else:
			problem = _name_problem(String(key))
		if problem == "":
			problem = _value_problem(values[key], 0)
	if problem != "":
		_report_error("SaveService: section '%s' refused: %s" % [section_name, problem])
		return false
	_sections[section_name] = values.duplicate(true)
	_unwritable.erase(section_name)
	_dirty = true
	set_process(true)  # Flushes once, next frame.
	return true


## Writes now if anything changed. ERR_LOCKED on a newer file (nothing is written).
func flush() -> Error:
	set_process(false)
	if _read_only:
		return ERR_LOCKED
	if not _dirty:
		return OK
	var err: Error = _write()
	if err == ERR_FILE_CORRUPT:
		# The read-back failed: find what does not round-trip, keep it out of the file (it stays
		# in memory, flagged until set_section replaces it) and write the rest.
		var offenders: Array[String] = _unwritable_sections()
		for offender: String in offenders:
			_unwritable[offender] = true
			_report_error(
				"SaveService: section '%s' does not survive the file; not saved" % offender
			)
		if offenders.is_empty():
			_report_error("SaveService: the written file failed its read-back")
		else:
			err = _write()
	if err == OK:
		_dirty = false
		saved.emit()
	return err


func _report_error(text: String) -> void:
	if error_sink.is_valid():
		error_sink.call(text)
	else:
		push_error(text)


func _drain_before_switch() -> void:
	if not _dirty or _read_only:
		return
	var err: Error = flush()
	if err != OK:
		_report_error("SaveService: changes for %s were not saved (error %d)" % [path(), err])


func _name_problem(label: String) -> String:
	if label == "" or label != label.strip_edges():
		return "empty label or edge spaces"
	for character: String in NAME_FORBIDDEN:
		if label.contains(character):
			return "label '%s' has a forbidden character" % label.c_escape()
	return ""


func _value_problem(value: Variant, depth: int) -> String:
	if depth > MAX_DEPTH:
		return "nested deeper than %d" % MAX_DEPTH
	var kind: int = typeof(value)
	var problem: String = ""
	if kind == TYPE_ARRAY:
		for item: Variant in value as Array:
			problem = _value_problem(item, depth + 1)
			if problem != "":
				break
	elif kind == TYPE_DICTIONARY:
		for key: Variant in value as Dictionary:
			if not (key is String or key is StringName or key is int):
				problem = "a nested key is not a String or int"
			else:
				problem = _value_problem((value as Dictionary)[key], depth + 1)
			if problem != "":
				break
	elif kind == TYPE_FLOAT:
		problem = "NaN" if is_nan(value) else ""
	elif not SAVABLE_TYPES.has(kind):
		problem = "a value of type %d cannot be saved" % kind
	return problem


func _write() -> Error:
	var tmp: String = path() + ".tmp"
	var text: String = _encode()
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var write_err: Error = file.get_error()
	file.close()
	if write_err != OK or _read_checked(tmp) == null:  # Read back: the hash must match.
		_remove(tmp)
		return write_err if write_err != OK else ERR_FILE_CORRUPT
	return _install(tmp)


## The two renames (also finishing a killed write on load): main -> bak, tmp -> main. With no
## main (killed between them) the existing bak stays.
func _install(tmp: String) -> Error:
	var main: String = path()
	if FileAccess.file_exists(main):
		var err: Error = _rename(main, main + ".bak")
		if err != OK:
			return err
	return _rename(tmp, main)


## Replace-by-rename first; remove the target and retry only when that fails.
func _rename(from: String, to: String) -> Error:
	var err: Error = DirAccess.rename_absolute(from, to)
	if err != OK and FileAccess.file_exists(to):
		_remove(to)
		err = DirAccess.rename_absolute(from, to)
	return err


func _encode() -> String:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(META, KEY_VERSION, VERSION)
	file.set_value(
		META, KEY_APP_VERSION, str(ProjectSettings.get_setting("application/config/version", ""))
	)
	for section: String in _sections:
		if section == META or _unwritable.has(section):
			continue
		var values: Dictionary = _sections[section]
		for key: Variant in values:
			file.set_value(section, str(key), values[key])
	var body: String = file.encode_to_text()
	return "%s%s\n%s" % [HASH_PREFIX, body.sha256_text(), body]


## Sections whose text does not parse back to the same values.
func _unwritable_sections() -> Array[String]:
	var offenders: Array[String] = []
	for section: String in _sections:
		if section == META or _unwritable.has(section):
			continue
		var values: Dictionary = _sections[section]
		var one: ConfigFile = ConfigFile.new()
		for key: Variant in values:
			one.set_value(section, str(key), values[key])
		var back: ConfigFile = ConfigFile.new()
		var ok: bool = back.parse(one.encode_to_text()) == OK
		for key: Variant in values:
			if ok and back.get_value(section, str(key), null) != values[key]:
				ok = false
		if not ok:
			offenders.append(section)
	return offenders


## The file's ConfigFile when it exists, carries the hash line and the hash matches; else null.
func _read_checked(file_path: String) -> ConfigFile:
	if not FileAccess.file_exists(file_path):
		return null
	var text: String = FileAccess.get_file_as_string(file_path)
	if not text.begins_with(HASH_PREFIX):
		return null
	var newline: int = text.find("\n")
	if newline < 0:
		return null
	var expected: String = text.substr(HASH_PREFIX.length(), newline - HASH_PREFIX.length())
	var body: String = text.substr(newline + 1)
	if body.sha256_text() != expected:
		return null
	var config: ConfigFile = ConfigFile.new()
	if config.parse(body) != OK:
		return null
	return config


func _load() -> void:
	_sections = {}
	_unwritable = {}
	_dirty = false
	_read_only = false
	var main: String = path()
	var tmp: String = main + ".tmp"
	var bak: String = main + ".bak"
	var any_file: bool = (
		FileAccess.file_exists(main) or FileAccess.file_exists(tmp) or FileAccess.file_exists(bak)
	)
	var config: ConfigFile = _read_checked(tmp)
	var from_tmp: bool = config != null
	if not from_tmp:
		_remove(tmp)  # A write that never finished (or no temp at all).
		config = _read_checked(main)
		if config == null:
			_keep_bad(main)
			config = _read_checked(bak)
			if config == null:
				_keep_bad(bak)
	if config == null:
		if not any_file:  # Corrupt files are not a first launch: no migration over them.
			_migrate_v0()
		return
	var raw_version: Variant = config.get_value(META, KEY_VERSION, 0)
	var version: int = raw_version if raw_version is int else 0
	if version > VERSION:
		_read_only = true
		push_warning(
			(
				"SaveService: save file is version %d, this app knows %d; not writing"
				% [version, VERSION]
			)
		)
	elif version < VERSION:
		_migrate(config, version)
		_dirty = true  # Rewritten with its version at the next flush.
	_take(config)
	if from_tmp and not _read_only and _install(tmp) != OK:
		_report_error("SaveService: could not finish the write of %s" % tmp)


## Ordered steps, one per version: step n turns a version n file into n + 1.
func _migrate(config: ConfigFile, from: int) -> void:
	for step: int in range(from, VERSION):
		match step:
			0:
				pass  # Version 0 had no version key; its sections are already ours.
			_:
				_report_error("SaveService: no migration from version %d" % step)
	config.set_value(META, KEY_VERSION, VERSION)


func _take(config: ConfigFile) -> void:
	for section: String in config.get_sections():
		if section == META:
			continue
		var values: Dictionary = {}
		for key: String in config.get_section_keys(section):
			values[key] = config.get_value(section, key)
		_sections[section] = values


## v0 of the ADR: no save file of any kind, but a settings.cfg beside it. Its [hud] keys are
## copied into section `hud`; settings.cfg is deleted once the save file is written.
func _migrate_v0() -> void:
	var legacy_path: String = path().get_base_dir().path_join(LEGACY_FILE)
	var legacy: ConfigFile = ConfigFile.new()
	if legacy.load(legacy_path) != OK:
		return
	if not legacy.has_section(LEGACY_SECTION):
		return
	var values: Dictionary = {}
	for key: String in legacy.get_section_keys(LEGACY_SECTION):
		values[key] = legacy.get_value(LEGACY_SECTION, key)
	_sections[LEGACY_SECTION] = values
	_dirty = true
	if flush() == OK:
		_remove(legacy_path)


## A failed file is kept once beside itself as `<name>.bad` (`save.cfg.bad`, `save.cfg.bak.bad`),
## replacing an older copy.
func _keep_bad(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		_rename(file_path, file_path + ".bad")


func _remove(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
