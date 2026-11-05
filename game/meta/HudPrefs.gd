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
## The switch as read: 1 on, 0 off, -1 not read since the last change.
static var _haptics: int = -1


## Tests: read and write `path` instead of the device's file.
static func set_path_override(path: String) -> void:
	_path_override = path
	_haptics = -1


static func clear_path_override() -> void:
	_path_override = ""
	_haptics = -1


## Forgets the value read, so the next ask reads the file again (a test that wrote it by hand).
static func forget_read() -> void:
	_haptics = -1


static func path() -> String:
	return _path_override if _path_override != "" else PATH


## Whether the Vibration switch is on (default on).
static func haptics_enabled() -> bool:
	if _haptics < 0:  # Read once, not at every buzz.
		var file: ConfigFile = ConfigFile.new()
		var on: bool = true  # A missing or unreadable file, or a key of another type: on.
		if file.load(path()) == OK:
			var value: Variant = file.get_value(SECTION, KEY_HAPTICS, true)
			if value is bool:
				on = value
		_haptics = 1 if on else 0
	return _haptics == 1


## Saves the Vibration switch. The other keys of the file stay.
static func set_haptics_enabled(on: bool) -> Error:
	var file: ConfigFile = ConfigFile.new()
	file.load(path())  # A missing file starts an empty one; an unreadable one is replaced.
	file.set_value(SECTION, KEY_HAPTICS, on)
	_haptics = 1 if on else 0
	return file.save(path())


## The gate of every haptic call: the data default (`InputSettings.haptics_enabled`) and the
## player's switch must both be on.
static func vibrates(settings: InputSettings) -> bool:
	return settings.haptics_enabled and haptics_enabled()
