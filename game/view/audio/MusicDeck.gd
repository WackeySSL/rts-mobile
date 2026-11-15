class_name MusicDeck
extends Node
## The music of ADR 0041 section 5: two players on the Music bus, a crossfade between loops over
## `crossfade_ms`, a sting (`sting_ids`) that plays once while the loop fades out, and a duck of
## `duck_db` for `duck_ms` under a strike. The ids map to streams through
## `AudioSettings.music_tracks`. AudioService owns the deck and calls it; the deck pauses with
## `mute_changed` and starts nothing while the sound is muted (the request waits and starts when
## the sound returns). The duck moves the two players, not the Music bus, so it never fights the
## player's Music step. Presentation only.

## A sting played to its end; the result screen can show its buttons then.
signal sting_finished(id: StringName)

var _settings: AudioSettings
var _service: Node
var _players: Array[AudioStreamPlayer] = []
## Fade level (dB) of each player, and the shared duck offset (dB, 0 or -duck_db).
var _levels: Array[float] = [0.0, 0.0]
var _duck_db: float = 0.0
## The index of the player that holds the current track; -1 before the first one.
var _front: int = -1
var _current: StringName = &""
## A track asked for while muted: the crossfade starts when the sound returns.
var _waiting: bool = false
var _fade: Tween
var _duck_tween: Tween


func setup(settings: AudioSettings, service: Node) -> void:
	_settings = settings
	_service = service
	for i: int in 2:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Player%d" % i
		player.bus = &"Music"
		add_child(player)
		_players.append(player)
		player.finished.connect(_on_player_finished.bind(i))
	service.mute_changed.connect(_on_mute_changed)


func current() -> StringName:
	return _current


## Crossfades to `id`, or plays it as a sting. False for an unknown id and for the track that is
## already current (nothing restarts).
func play(id: StringName) -> bool:
	var stream: AudioStream = _settings.music_tracks.get(id)
	if stream == null or id == _current:
		return false
	_current = id
	if _service.is_muted():
		_waiting = true
		return true
	_start(id, stream)
	return true


func stop() -> void:
	_current = &""
	_waiting = false
	_kill(_fade)
	for i: int in 2:
		_players[i].stop()
		_levels[i] = _settings.mute_floor_db
	_apply()


## Lowers the music by `duck_db`, holds `duck_ms`, then restores it. A second strike restarts it.
func duck() -> void:
	_kill(_duck_tween)
	_duck_db = -_settings.duck_db
	_apply()
	_duck_tween = create_tween()
	_duck_tween.tween_interval(_settings.duck_ms / 1000.0)
	_duck_tween.tween_method(_set_duck, _duck_db, 0.0, 0.1)


## The test hooks: the running fade and duck tweens, to step them without frames.
func fade_tween_for_tests() -> Tween:
	return _fade


func duck_tween_for_tests() -> Tween:
	return _duck_tween


func player_for_tests(index: int) -> AudioStreamPlayer:
	return _players[index]


func duck_db_now() -> float:
	return _duck_db


func _start(id: StringName, stream: AudioStream) -> void:
	_waiting = false
	var out: int = _front
	_front = 1 - _front if _front >= 0 else 0
	var incoming: AudioStreamPlayer = _players[_front]
	incoming.stream = stream
	_levels[_front] = _settings.mute_floor_db
	incoming.stream_paused = false
	incoming.play()
	var sting: bool = _settings.sting_ids.has(id)
	if sting:
		# The sting is heard at full level while the loop goes out beneath it (the duck of §5).
		_levels[_front] = 0.0
	_apply()
	_kill(_fade)
	_fade = create_tween()
	var seconds: float = _settings.crossfade_ms / 1000.0
	var from_out: float = _levels[out] if out >= 0 else _settings.mute_floor_db
	_fade.tween_method(_set_mix.bind(out, sting, from_out), 0.0, 1.0, seconds)
	_fade.tween_callback(_finish_fade.bind(out))


## `t` 0..1 through the crossfade: the outgoing player down, the incoming one up (a sting is
## already at full level).
func _set_mix(t: float, out: int, sting: bool, from_out: float) -> void:
	if not sting:
		_levels[_front] = _db(t)
	if out >= 0:
		_levels[out] = lerpf(from_out, _settings.mute_floor_db, t) if sting else _db(1.0 - t)
	_apply()


func _finish_fade(out: int) -> void:
	if out >= 0:
		_players[out].stop()
		_levels[out] = _settings.mute_floor_db
	_apply()


func _db(linear: float) -> float:
	return maxf(linear_to_db(linear), _settings.mute_floor_db)


func _set_duck(db: float) -> void:
	_duck_db = db
	_apply()


func _apply() -> void:
	for i: int in 2:
		_players[i].volume_db = maxf(_levels[i] + _duck_db, _settings.mute_floor_db)


func _on_mute_changed(muted: bool) -> void:
	for player: AudioStreamPlayer in _players:
		player.stream_paused = muted
	if not muted and _waiting:
		var stream: AudioStream = _settings.music_tracks.get(_current)
		if stream != null:
			_start(_current, stream)


func _on_player_finished(index: int) -> void:
	# Only a sting ends by itself (loops are flagged in the import); the front player's end is it.
	if index == _front and _settings.sting_ids.has(_current):
		sting_finished.emit(_current)


func _kill(tween: Tween) -> void:
	if tween != null:
		tween.kill()
