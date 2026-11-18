class_name MenuPrefs
extends RefCounted
## The player's Settings-screen values on the device (plan P526, ADR 0042 section 1): section
## `settings` of `SaveService`'s one save file, keys `sound_step`, `music_step` and `reduced`.
## Vibration is `HudPrefs`' (section `hud`). Static functions only. A missing key, or one of
## another type, means the default. `MenuFlow` reads `reduced_effects()` into `IntroPlayer.reduced`,
## and the volume steps through `apply_audio` once `AudioService` is up.

const SECTION: StringName = &"settings"
const KEY_SOUND: String = "sound_step"
const KEY_MUSIC: String = "music_step"
const KEY_REDUCED: String = "reduced"


## The saved step, or `fallback` when none is saved (or it is not an int).
static func sound_step(fallback: int) -> int:
	return _step(KEY_SOUND, fallback)


static func music_step(fallback: int) -> int:
	return _step(KEY_MUSIC, fallback)


static func set_sound_step(step: int) -> Error:
	return _write(KEY_SOUND, step)


static func set_music_step(step: int) -> Error:
	return _write(KEY_MUSIC, step)


## Reduced effects, default off.
static func reduced_effects() -> bool:
	var value: Variant = SaveService.get_section(SECTION).get(KEY_REDUCED, false)
	return value is bool and value


static func set_reduced_effects(on: bool) -> Error:
	return _write(KEY_REDUCED, on)


## Puts the saved steps on `audio` (the `AudioService`); a step never saved stays as it is.
static func apply_audio(audio: Node) -> void:
	var values: Dictionary = SaveService.get_section(SECTION)
	if values.get(KEY_SOUND) is int:
		audio.call("set_sound_step", values[KEY_SOUND])
	if values.get(KEY_MUSIC) is int:
		audio.call("set_step", &"Music", values[KEY_MUSIC])


static func _step(key: String, fallback: int) -> int:
	var value: Variant = SaveService.get_section(SECTION).get(key)
	return value if value is int else fallback


## Merges one key into the section. ERR_LOCKED on a newer save, ERR_INVALID_DATA on a refusal.
static func _write(key: String, value: Variant) -> Error:
	if SaveService.is_read_only():
		return ERR_LOCKED
	var values: Dictionary = SaveService.get_section(SECTION)
	values[key] = value
	return OK if SaveService.set_section(SECTION, values) else ERR_INVALID_DATA
