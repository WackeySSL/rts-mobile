class_name MusicDeck
extends Node
## The music of ADR 0041 section 5: two players on the Music bus, a crossfade between loops over
## `crossfade_ms`, a sting (`sting_ids`) that plays once while the loop fades out, and a duck of
## `duck_db` for `duck_ms` under a strike. The ids map to streams through
## `AudioSettings.music_tracks`. AudioService owns the deck and calls it. The duck moves the two
## players, not the Music bus, so it never fights the player's Music step.
##
## Every fade starts from the players' current levels, so a request in the middle of a crossfade
## never makes a level jump: the new track takes the quieter player, the other one fades out from
## where it is, and a request for the track that is fading out reverses that fade.
##
## The deck pauses with `mute_changed`: at once for `background`, after the Master fade for the
## other reasons; the fade and duck tweens pause with the streams. A track asked for while muted
## starts when the sound returns. Presentation only.

## A sting played to its end, or `stop()` cut it short (one signal for both: the result screen
## moves on either way).
signal sting_finished(id: StringName)

var _settings: AudioSettings
var _service: Node
var _players: Array[AudioStreamPlayer] = []
## Per player: the track it holds, its level (dB), and the level the running fade started from and
## goes to. The shared duck offset (dB, 0 or -duck_db) is added on top.
var _ids: Array[StringName] = [&"", &""]
var _levels: Array[float] = []
var _from: Array[float] = []
var _to: Array[float] = []
var _duck_db: float = 0.0
## The index of the player that holds the current track; -1 before the first one.
var _front: int = -1
var _current: StringName = &""
## A track asked for while muted: the crossfade starts when the sound returns.
var _waiting: bool = false
var _paused: bool = false
var _fade: Tween
var _duck_tween: Tween
var _mute_tween: Tween
## The fade and duck tweens that have not finished, to pause and resume with the streams.
var _live: Array[Tween] = []


func setup(settings: AudioSettings, service: Node) -> void:
	_settings = settings
	_service = service
	_levels = [settings.mute_floor_db, settings.mute_floor_db]
	_from = _levels.duplicate()
	_to = _levels.duplicate()
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


## Silences both players at once. A sting cut short still emits `sting_finished`. The duck ends.
func stop() -> void:
	var cut: StringName = _current
	_current = &""
	_waiting = false
	_kill(_fade)
	_kill(_duck_tween)
	_duck_db = 0.0
	for i: int in 2:
		_players[i].stop()
		_ids[i] = &""
		_levels[i] = _settings.mute_floor_db
	_apply()
	if _settings.sting_ids.has(cut):
		sting_finished.emit(cut)


## Lowers the music by `duck_db`, holds `duck_ms`, then restores it over `duck_release_ms`. A
## second strike restarts the hold.
func duck() -> void:
	_kill(_duck_tween)
	if not is_inside_tree():
		return
	_duck_db = -_settings.duck_db
	_apply()
	_duck_tween = _new_tween()
	_duck_tween.tween_interval(_settings.duck_ms / 1000.0)
	_duck_tween.tween_method(_set_duck, _duck_db, 0.0, _settings.duck_release_ms / 1000.0)


## The test hooks: the running tweens, to step them without frames.
func fade_tween_for_tests() -> Tween:
	return _fade


func duck_tween_for_tests() -> Tween:
	return _duck_tween


func player_for_tests(index: int) -> AudioStreamPlayer:
	return _players[index]


func level_for_tests(index: int) -> float:
	return _levels[index]


func duck_db_now() -> float:
	return _duck_db


func _start(id: StringName, stream: AudioStream) -> void:
	_waiting = false
	var back: int = 1 - _front if _front >= 0 else -1
	var reverse: bool = back >= 0 and _ids[back] == id and _players[back].playing
	var incoming: int = 0
	if reverse:
		incoming = back
	else:
		if _front >= 0 and _levels[_front] < _levels[1 - _front]:
			incoming = _front
		elif _front >= 0:
			incoming = 1 - _front
		_ids[incoming] = id
		_players[incoming].stream = stream
		_players[incoming].play()
		# A sting is heard at full level while the loop goes out beneath it.
		_levels[incoming] = 0.0 if _settings.sting_ids.has(id) else _settings.mute_floor_db
	_front = incoming
	_from = _levels.duplicate()
	_to = [_settings.mute_floor_db, _settings.mute_floor_db]
	_to[incoming] = 0.0
	_apply()
	_kill(_fade)
	if not is_inside_tree():
		_set_mix(1.0)
		_finish_fade()
		return
	_fade = _new_tween()
	_fade.tween_method(_set_mix, 0.0, 1.0, _settings.crossfade_ms / 1000.0)
	_fade.tween_callback(_finish_fade)


## `t` 0..1 through the crossfade, in amplitude, from the levels the fade started at.
func _set_mix(t: float) -> void:
	for i: int in 2:
		_levels[i] = _db(lerpf(db_to_linear(_from[i]), db_to_linear(_to[i]), t))
	_apply()


func _finish_fade() -> void:
	for i: int in 2:
		if _to[i] <= _settings.mute_floor_db:
			_players[i].stop()
			_ids[i] = &""
			_levels[i] = _settings.mute_floor_db
	_apply()


func _db(linear: float) -> float:
	return maxf(linear_to_db(linear), _settings.mute_floor_db)


func _set_duck(db: float) -> void:
	_duck_db = db
	_apply()


func _apply() -> void:
	for i: int in 2:
		_players[i].volume_db = maxf(_levels[i] + _duck_db, _settings.mute_floor_db)


## A tween that starts paused while the deck is.
func _new_tween() -> Tween:
	var tween: Tween = create_tween()
	_live.append(tween)
	tween.finished.connect(_live.erase.bind(tween))
	if _paused:
		tween.pause()
	return tween


func _on_mute_changed(muted: bool) -> void:
	_kill(_mute_tween)
	if muted:
		var at_once: bool = _service.has_mute_reason(&"background") or _settings.fade_ms <= 0
		if at_once or not is_inside_tree():
			_pause_all(true)
		else:
			# The Master fades out first; the streams pause when it is silent.
			_mute_tween = create_tween()
			_mute_tween.tween_interval(_settings.fade_ms / 1000.0)
			_mute_tween.tween_callback(_pause_all.bind(true))
		return
	_pause_all(false)
	if _waiting:
		var stream: AudioStream = _settings.music_tracks.get(_current)
		if stream != null:
			_start(_current, stream)


func _pause_all(paused: bool) -> void:
	_paused = paused
	for player: AudioStreamPlayer in _players:
		player.stream_paused = paused
	for tween: Tween in _live:
		if paused:
			tween.pause()
		else:
			tween.play()


func _on_player_finished(index: int) -> void:
	# A sting ends by itself (loops are flagged in the import). Clearing `_current` lets the same
	# sting play again.
	if index != _front or _current.is_empty():
		return
	var ended: StringName = _current
	_current = &""
	_ids[index] = &""
	if _settings.sting_ids.has(ended):
		sting_finished.emit(ended)


func _kill(tween: Tween) -> void:
	if tween != null:
		_live.erase(tween)
		tween.kill()
