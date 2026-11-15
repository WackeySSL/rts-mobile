# AudioService autoload (ADR 0041). Owns the buses' volume steps, the mute reasons and the voice
# pool. Presentation only: nothing in game/sim knows it exists. No class_name (an autoload script
# declares none, tests/project/test_autoloads.gd).
extends Node

## A mute reason was added or the last one cleared; MusicDeck (P501b) pauses its stream on it.
signal mute_changed(muted: bool)

const SETTINGS_PATH: String = "res://data/audio_settings.tres"
const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_SFX: StringName = &"Sfx"
const BUS_UI: StringName = &"Ui"
## The mute reasons of ADR 0041 section 5. Any other id works too; each is a set member.
const REASON_BACKGROUND: StringName = &"background"
const REASON_AD: StringName = &"ad"
const REASON_RESTORING: StringName = &"restoring"

var settings: AudioSettings
var pool: VoicePool

var _steps: Dictionary[StringName, int] = {}
var _reasons: Dictionary[StringName, bool] = {}
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if settings == null:
		settings = load(SETTINGS_PATH) as AudioSettings
	pool = VoicePool.new()
	pool.name = "VoicePool"
	add_child(pool)
	pool.setup(settings)
	set_step(BUS_MUSIC, settings.default_music_step)
	set_step(BUS_SFX, settings.default_sfx_step)
	set_step(BUS_UI, settings.default_ui_step)
	# AdService is Phase 6's autoload and comes before this one; absent until then.
	var ads: Node = get_node_or_null(^"/root/AdService")
	if ads != null:
		if ads.has_signal(&"ad_opened"):
			ads.connect(&"ad_opened", add_mute_reason.bind(REASON_AD))
		if ads.has_signal(&"ad_closed"):
			ads.connect(&"ad_closed", clear_mute_reason.bind(REASON_AD))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			add_mute_reason(REASON_BACKGROUND)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			clear_mute_reason(REASON_BACKGROUND)


## Sets the volume step of Music, Sfx or Ui (clamped to 0..steps); step 0 mutes that bus.
func set_step(bus: StringName, step: int) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0 or bus == BUS_MASTER:
		return
	var clamped: int = clampi(step, 0, settings.steps)
	_steps[bus] = clamped
	AudioServer.set_bus_mute(index, clamped == 0)
	if clamped > 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(float(clamped) / settings.steps))


func get_step(bus: StringName) -> int:
	return _steps.get(bus, 0)


## The player's Sound setting: effects and interface together.
func set_sound_step(step: int) -> void:
	set_step(BUS_SFX, step)
	set_step(BUS_UI, step)


## Adds a reason to mute everything. Idempotent; the Master bus fades out unless the reason is
## `background`, where the engine may not run frames to finish a fade.
func add_mute_reason(reason: StringName) -> void:
	_set_reason(reason, true)


## Clears one reason; the sound returns when the last one is gone, whatever the order.
func clear_mute_reason(reason: StringName) -> void:
	_set_reason(reason, false)


func has_mute_reason(reason: StringName) -> bool:
	return _reasons.has(reason)


func is_muted() -> bool:
	return not _reasons.is_empty()


## Whether a sound on `bus` would be heard now: no mute reason and the bus step above 0.
func can_play(bus: StringName) -> bool:
	return _reasons.is_empty() and get_step(bus) > 0


## A battle sound at `position`, on Sfx. Returns whether a voice started.
func play_world(
	stream: AudioStream,
	position: Vector2,
	cue: StringName,
	priority: int = 0,
	max_voices: int = 0,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0
) -> bool:
	if not can_play(BUS_SFX):
		return false
	return pool.play_world(stream, position, cue, priority, max_voices, volume_db, pitch_scale)


## An interface sound, on Ui. Returns whether a voice started.
func play_ui(
	stream: AudioStream,
	cue: StringName,
	priority: int = 0,
	max_voices: int = 0,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0
) -> bool:
	if not can_play(BUS_UI):
		return false
	return pool.play_ui(stream, cue, priority, max_voices, volume_db, pitch_scale)


## Starts a new sim tick's budget of world voices (`voices_per_tick`).
func begin_tick() -> void:
	pool.begin_tick()


func _set_reason(reason: StringName, on: bool) -> void:
	var was_muted: bool = is_muted()
	if on:
		_reasons[reason] = true
	else:
		_reasons.erase(reason)
	var muted: bool = is_muted()
	if muted == was_muted:
		return
	if muted:
		pool.stop_all()
	_fade_master(muted, reason != REASON_BACKGROUND)
	mute_changed.emit(muted)


func _fade_master(muted: bool, fade: bool) -> void:
	var index: int = AudioServer.get_bus_index(BUS_MASTER)
	if _fade != null:
		_fade.kill()
	var seconds: float = settings.fade_ms / 1000.0
	if not fade or seconds <= 0.0 or not is_inside_tree():
		AudioServer.set_bus_mute(index, muted)
		AudioServer.set_bus_volume_db(index, 0.0)
		return
	var from_db: float = AudioServer.get_bus_volume_db(index)
	var to_db: float = settings.mute_floor_db if muted else 0.0
	if not muted:
		AudioServer.set_bus_mute(index, false)
	_fade = create_tween()
	_fade.tween_method(AudioServer.set_bus_volume_db.bind(index), from_db, to_db, seconds)
	if muted:
		_fade.tween_callback(AudioServer.set_bus_mute.bind(index, true))
