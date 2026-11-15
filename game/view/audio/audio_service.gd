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
## The root child whose `ad_opened` and `ad_closed` signals mute the sound (Phase 6's autoload).
## Set it before the service enters the tree; tests use another name, so a real AdService is
## left alone.
var ad_service_name: StringName = &"AdService"

var _pool: VoicePool
var _steps: Dictionary[StringName, int] = {}
var _reasons: Dictionary[StringName, bool] = {}
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if settings == null:
		settings = load(SETTINGS_PATH) as AudioSettings
	_pool = VoicePool.new()
	_pool.name = "VoicePool"
	add_child(_pool)
	_pool.setup(settings)
	set_step(BUS_MUSIC, settings.default_music_step)
	set_step(BUS_SFX, settings.default_sfx_step)
	set_step(BUS_UI, settings.default_ui_step)
	# AdService is Phase 6's autoload; hook it now if it is already in the tree, else when it
	# appears, so the autoload order does not matter.
	var ads: Node = get_tree().root.get_node_or_null(NodePath(ad_service_name))
	if ads != null:
		connect_ad_service(ads)
	else:
		get_tree().node_added.connect(_on_node_added)


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
	if clamped == 0:
		_pool.stop_voices(bus)
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
	return _pool.play_world(stream, position, cue, priority, max_voices, volume_db, pitch_scale)


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
	return _pool.play_ui(stream, cue, priority, max_voices, volume_db, pitch_scale)


## Lifts the per-tick limit when the tick loop stops.
func end_ticking() -> void:
	_pool.end_ticking()


## Test-only: the voice pool, to count voices and call it directly.
func get_pool_for_tests() -> VoicePool:
	return _pool


## Starts a new sim tick's budget of world voices (`voices_per_tick`).
func begin_tick() -> void:
	_pool.begin_tick()


## Mutes while `ads` reports an ad open (`ad_opened(placement)`, `ad_closed(placement)`).
## Idempotent.
func connect_ad_service(ads: Node) -> void:
	if ads.has_signal(&"ad_opened") and not ads.is_connected(&"ad_opened", _on_ad_opened):
		ads.connect(&"ad_opened", _on_ad_opened)
	if ads.has_signal(&"ad_closed") and not ads.is_connected(&"ad_closed", _on_ad_closed):
		ads.connect(&"ad_closed", _on_ad_closed)


func disconnect_ad_service(ads: Node) -> void:
	if ads.has_signal(&"ad_opened") and ads.is_connected(&"ad_opened", _on_ad_opened):
		ads.disconnect(&"ad_opened", _on_ad_opened)
	if ads.has_signal(&"ad_closed") and ads.is_connected(&"ad_closed", _on_ad_closed):
		ads.disconnect(&"ad_closed", _on_ad_closed)
	clear_mute_reason(REASON_AD)


func _on_node_added(node: Node) -> void:
	if node.name == ad_service_name and node.get_parent() == get_tree().root:
		get_tree().node_added.disconnect(_on_node_added)
		connect_ad_service(node)


## `ad_opened` and `ad_closed` carry the placement; the mute does not need it.
func _on_ad_opened(_placement: StringName = &"") -> void:
	add_mute_reason(REASON_AD)


func _on_ad_closed(_placement: StringName = &"") -> void:
	clear_mute_reason(REASON_AD)


func _set_reason(reason: StringName, on: bool) -> void:
	var was_muted: bool = is_muted()
	if on:
		_reasons[reason] = true
	else:
		_reasons.erase(reason)
	var muted: bool = is_muted()
	# Going to the background mutes at once, also in the middle of another reason's fade.
	var instant: bool = on and reason == REASON_BACKGROUND
	if muted == was_muted and not instant:
		return
	if muted and not was_muted:
		_pool.stop_all()
	_fade_master(muted, not instant)
	if muted != was_muted:
		mute_changed.emit(muted)


func _set_master_db(db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(BUS_MASTER), db)


func _fade_master(muted: bool, fade: bool) -> void:
	var index: int = AudioServer.get_bus_index(BUS_MASTER)
	if _fade != null:
		_fade.kill()
	var seconds: float = settings.fade_ms / 1000.0
	var to_db: float = settings.mute_floor_db if muted else 0.0
	if not fade or seconds <= 0.0 or not is_inside_tree():
		AudioServer.set_bus_mute(index, muted)
		AudioServer.set_bus_volume_db(index, to_db)
		return
	if not muted:
		AudioServer.set_bus_mute(index, false)
	_fade = create_tween()
	_fade.tween_method(_set_master_db, AudioServer.get_bus_volume_db(index), to_db, seconds)
	if muted:
		_fade.tween_callback(AudioServer.set_bus_mute.bind(index, true))
