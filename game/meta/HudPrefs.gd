class_name HudPrefs
extends RefCounted
## The player's HUD settings on the device (ADR 0025 section 11, plan P124; ADR 0042 section 3,
## plan P510b): section `hud`, key `haptics`, of `SaveService`'s one save file. Static functions
## only, no Node, no autoload. A missing section, or a key of another type, means the default
## (vibration on). Phase 5's settings screen adds keys to the same section. `vibrates` is the one
## gate every `vibrate` call asks. A `user://settings.cfg` of an older install is moved into the
## save by `SaveService` (migration v0) and deleted.

## The old file, read only by `SaveService`'s migration; kept for the tests that name it.
const PATH: String = "user://settings.cfg"
const SECTION: StringName = &"hud"
const KEY_HAPTICS: String = "haptics"

## The switch as read: 1 on, 0 off, -1 not read since the last change.
static var _haptics: int = -1


## Tests: read and write the save file at `path` (and its neighbours) instead of the device's.
static func set_path_override(path: String) -> void:
	SaveService.set_path_override(path)
	_haptics = -1


static func clear_path_override() -> void:
	SaveService.clear_path_override()
	_haptics = -1


## Forgets the value read, so the next ask reads the section again (a test that changed it).
static func forget_read() -> void:
	_haptics = -1


## The save file in use.
static func path() -> String:
	return SaveService.path()


## Whether the Vibration switch is on (default on).
static func haptics_enabled() -> bool:
	if _haptics < 0:  # Read once, not at every buzz.
		var value: Variant = SaveService.get_section(SECTION).get(KEY_HAPTICS, true)
		_haptics = 0 if value is bool and not value else 1  # Another type: on.
	return _haptics == 1


## Saves the Vibration switch (written at the frame's end). The other keys of the section stay.
static func set_haptics_enabled(on: bool) -> Error:
	var values: Dictionary = SaveService.get_section(SECTION)
	values[KEY_HAPTICS] = on
	_haptics = 1 if on else 0
	return OK if SaveService.set_section(SECTION, values) else ERR_INVALID_DATA


## The gate of every haptic call: the data default (`InputSettings.haptics_enabled`) and the
## player's switch must both be on.
static func vibrates(settings: InputSettings) -> bool:
	return settings.haptics_enabled and haptics_enabled()
