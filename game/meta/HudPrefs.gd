class_name HudPrefs
extends RefCounted
## The player's HUD settings on the device (ADR 0025 section 11, plan P124; ADR 0042 section 3,
## plan P510b): section `hud`, key `haptics`, of `SaveService`'s one save file. Static functions
## only, no Node, no autoload. A missing section, or a key of another type, means the default
## (vibration on). Phase 5's settings screen adds keys to the same section. `vibrates` is the one
## gate every `vibrate` call asks. A `user://settings.cfg` of an older install is moved into the
## save by `SaveService` (migration v0) and deleted.

## The old file, read only by `SaveService`'s migration; named here for the tests.
const PATH: String = "user://" + SaveService.LEGACY_FILE
const SECTION: StringName = &"hud"
const KEY_HAPTICS: String = "haptics"


## Tests: read and write the save file at `path` (and its neighbours) instead of the device's.
static func set_path_override(path: String) -> void:
	SaveService.set_path_override(path)


static func clear_path_override() -> void:
	SaveService.clear_path_override()


## Kept for the callers of the old cache: nothing is cached now, so there is nothing to forget.
static func forget_read() -> void:
	pass


## The save file in use.
static func path() -> String:
	return SaveService.path()


## Whether the Vibration switch is on (default on). Read from the service's section at each ask,
## so a direct `SaveService` write or a path switch shows at once.
static func haptics_enabled() -> bool:
	var value: Variant = SaveService.get_section(SECTION).get(KEY_HAPTICS, true)
	return not (value is bool and not value)  # Another type: on.


## Saves the Vibration switch (written at the frame's end). The other keys of the section stay.
## ERR_LOCKED when the save is from a newer app, ERR_INVALID_DATA when the service refuses it;
## nothing changes then.
static func set_haptics_enabled(on: bool) -> Error:
	if SaveService.is_read_only():
		return ERR_LOCKED
	var values: Dictionary = SaveService.get_section(SECTION)
	values[KEY_HAPTICS] = on
	return OK if SaveService.set_section(SECTION, values) else ERR_INVALID_DATA


## The gate of every haptic call: the data default (`InputSettings.haptics_enabled`) and the
## player's switch must both be on.
static func vibrates(settings: InputSettings) -> bool:
	return settings.haptics_enabled and haptics_enabled()
