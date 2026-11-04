class_name HudPrefs
extends RefCounted
## The player's HUD settings on the device (ADR 0025 section 11, plan P124; the file and the test
## hook are ADR 0024 section 7's): `user://settings.cfg`, section `[hud]`, key `haptics`. Static
## functions only, no Node, no autoload. A missing or unreadable file, or a key of another type,
## means the default (vibration on). Phase 5's settings screen takes the file over and adds keys.
## `vibrates` is the one gate every `vibrate` call asks.

const PATH: String = "user://settings.cfg"
const SECTION: String = "hud"
const KEY_HAPTICS: String = "haptics"

static var _path_override: String = ""


## Tests: read and write `path` instead of the device's file.
static func set_path_override(path: String) -> void:
	_path_override = path


static func clear_path_override() -> void:
	_path_override = ""


static func path() -> String:
	return _path_override if _path_override != "" else PATH


## Whether the Vibration switch is on (default on).
static func haptics_enabled() -> bool:
	var file: ConfigFile = ConfigFile.new()
	if file.load(path()) != OK:
		return true
	var value: Variant = file.get_value(SECTION, KEY_HAPTICS, true)
	return value if value is bool else true


## Saves the Vibration switch. The other keys of the file stay.
static func set_haptics_enabled(on: bool) -> Error:
	var file: ConfigFile = ConfigFile.new()
	file.load(path())  # A missing file starts an empty one; an unreadable one is replaced.
	file.set_value(SECTION, KEY_HAPTICS, on)
	return file.save(path())


## The gate of every haptic call: the data default (`InputSettings.haptics_enabled`) and the
## player's switch must both be on.
static func vibrates(settings: InputSettings) -> bool:
	return settings.haptics_enabled and haptics_enabled()
