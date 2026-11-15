extends Node
## The device's one save file (ADR 0042 sections 1-4): `user://save.cfg`, a ConfigFile of
## sections, `meta.version`, and a first line `; sha256=<hex of the rest>`. Phase 6 keeps its
## section `ads` here through `get_section` / `set_section` (no ads.cfg). Main thread only.
## No class_name: this is an autoload (tests/project/test_autoloads.gd). Never touched by game/sim.
##
## Write: temp file, read back and hash-check, then bak <- main and main <- temp. Load, newest
## first: a hash-valid `.tmp` (the app was killed between the renames; the load finishes them),
## then `save.cfg`, then `.bak`. No step relies on rename replacing an existing file: each target
## is removed first, and every kill point between the steps still has a valid file to load.

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

var _path_override: String = ""
var _sections: Dictionary = {}  # String -> Dictionary
var _dirty: bool = false
var _flush_queued: bool = false
var _read_only: bool = false


func _ready() -> void:
	_load()


func _exit_tree() -> void:
	if _dirty:
		flush()


## Tests: read and write `path` (and its `.tmp`, `.bak`, `.bad`, and the legacy `settings.cfg`
## beside it) instead of the device's file. Reloads.
func set_path_override(path: String) -> void:
	_path_override = path
	_load()


func clear_path_override() -> void:
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


## Replaces the whole section and queues one write for this frame's end. `meta` is the service's.
func set_section(section: StringName, values: Dictionary) -> void:
	if String(section) == META:
		print("SaveService: section meta is reserved, ignored")
		return
	_sections[String(section)] = values.duplicate(true)
	_dirty = true
	if not _flush_queued:
		_flush_queued = true
		_flush_queued_write.call_deferred()


## Writes now if anything changed. ERR_LOCKED on a newer file (nothing is written).
func flush() -> Error:
	_flush_queued = false
	if _read_only:
		return ERR_LOCKED
	if not _dirty:
		return OK
	var err: Error = _write()
	if err == OK:
		_dirty = false
		saved.emit()
	return err


func _flush_queued_write() -> void:
	if _flush_queued:
		flush()


func _write() -> Error:
	var main: String = path()
	var tmp: String = main + ".tmp"
	var bak: String = main + ".bak"
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


## The two renames (also finishing a killed write on load): main -> bak, tmp -> main.
func _install(tmp: String) -> Error:
	var main: String = path()
	var bak: String = main + ".bak"
	if FileAccess.file_exists(main):
		_remove(bak)
		var err: Error = DirAccess.rename_absolute(main, bak)
		if err != OK:
			return err
	_remove(main)
	return DirAccess.rename_absolute(tmp, main)


func _encode() -> String:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(META, KEY_VERSION, VERSION)
	file.set_value(
		META, KEY_APP_VERSION, str(ProjectSettings.get_setting("application/config/version", ""))
	)
	for section: String in _sections:
		if section == META:
			continue
		var values: Dictionary = _sections[section]
		for key: Variant in values:
			file.set_value(section, str(key), values[key])
	var body: String = file.encode_to_text()
	return "%s%s\n%s" % [HASH_PREFIX, body.sha256_text(), body]


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
	_dirty = false
	_read_only = false
	var main: String = path()
	var tmp: String = main + ".tmp"
	var config: ConfigFile = _read_checked(tmp)
	var from_tmp: bool = config != null
	if not from_tmp:
		_remove(tmp)  # A write that never finished (or no temp at all).
		config = _read_checked(main)
		if config == null:
			_keep_bad(main)
			config = _read_checked(main + ".bak")
			if config == null:
				_keep_bad(main + ".bak")
	if config == null:
		_migrate_v0()
		return
	var version: int = int(config.get_value(META, KEY_VERSION, VERSION))
	if version > VERSION:
		_read_only = true
		print(
			(
				"SaveService: save file is version %d, this app knows %d; not writing"
				% [version, VERSION]
			)
		)
	_take(config)
	if from_tmp and not _read_only and _install(tmp) != OK:
		push_error("SaveService: could not finish the write of %s" % tmp)


func _take(config: ConfigFile) -> void:
	for section: String in config.get_sections():
		if section == META:
			continue
		var values: Dictionary = {}
		for key: String in config.get_section_keys(section):
			values[key] = config.get_value(section, key)
		_sections[section] = values


## v0: no save.cfg but a settings.cfg beside it. Its [hud] keys become section `hud`; the legacy
## file is deleted after the first good write.
func _migrate_v0() -> void:
	var legacy_path: String = path().get_base_dir().path_join(LEGACY_FILE)
	if not FileAccess.file_exists(legacy_path):
		return
	var legacy: ConfigFile = ConfigFile.new()
	if legacy.load(legacy_path) != OK:
		return
	var values: Dictionary = {}
	for key: String in legacy.get_section_keys(LEGACY_SECTION):
		values[key] = legacy.get_value(LEGACY_SECTION, key)
	_sections[LEGACY_SECTION] = values
	_dirty = true
	if flush() == OK:
		_remove(legacy_path)


## A failed main or backup file is kept once as `.bad` (the previous `.bad` is replaced).
func _keep_bad(file_path: String) -> void:
	if not FileAccess.file_exists(file_path):
		return
	var bad: String = path() + ".bad"
	_remove(bad)
	DirAccess.rename_absolute(file_path, bad)


func _remove(file_path: String) -> void:
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)
