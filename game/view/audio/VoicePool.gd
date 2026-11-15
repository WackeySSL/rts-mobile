class_name VoicePool
extends Node
## The fixed set of players for battle and interface sounds (ADR 0041 section 3). The players are
## made once in `setup`; no player is created or freed while playing, and a play allocates nothing.
## A cue has a `priority` and `max_voices`: a new sound takes a free voice, or steals the oldest
## voice of lower priority, or is dropped. At most `voices_per_tick` new world voices start between
## two `begin_tick` calls; once the budget is spent only a higher-priority sound may still start, by
## stealing a lower-priority voice started in the same tick, so the budget drops by priority and not
## by arrival. `end_ticking` lifts the limit (play outside a tick loop is never blocked; before the
## first `begin_tick` there is none). Which sounds may play
## at all (mute reasons, volume steps) is `AudioService`'s decision, not the pool's.


## Bookkeeping of one voice. `busy` is cleared by the player's `finished` signal or by a steal, so
## the caps do not depend on the audio driver.
class Slot:
	var busy: bool = false
	var cue: StringName = &""
	var priority: int = 0
	var seq: int = 0
	## Started since the last `begin_tick` (world voices only).
	var fresh: bool = false


## Scales the world voices' `max_distance` (the camera zoom check of ADR 0041 section 3).
var distance_scale: float = 1.0

var _settings: AudioSettings
var _world: Array[AudioStreamPlayer2D] = []
var _world_slots: Array[Slot] = []
var _ui: Array[AudioStreamPlayer] = []
var _ui_slots: Array[Slot] = []
var _seq: int = 0
var _tick_left: int = -1


## Makes every player. Call once, from the owner's `_ready`.
func setup(settings: AudioSettings) -> void:
	_settings = settings
	for _i: int in settings.world_voices:
		var world: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		world.bus = &"Sfx"
		world.attenuation = settings.attenuation
		var world_slot: Slot = Slot.new()
		world.finished.connect(_on_finished.bind(world_slot))
		add_child(world)
		_world.append(world)
		_world_slots.append(world_slot)
	for _i: int in settings.ui_voices:
		var ui: AudioStreamPlayer = AudioStreamPlayer.new()
		ui.bus = &"Ui"
		var ui_slot: Slot = Slot.new()
		ui.finished.connect(_on_finished.bind(ui_slot))
		add_child(ui)
		_ui.append(ui)
		_ui_slots.append(ui_slot)


## Starts a new tick's budget of world voices (BattleSounds calls it once per sim tick).
func begin_tick() -> void:
	_tick_left = _settings.voices_per_tick
	for slot: Slot in _world_slots:
		slot.fresh = false


## Lifts the per-tick limit; the owner calls it when its tick loop stops.
func end_ticking() -> void:
	_tick_left = -1


## Plays `stream` at `position` (world px). `max_voices` 0 means only the pool limits the cue.
## Returns whether a voice started.
func play_world(
	stream: AudioStream,
	position: Vector2,
	cue: StringName,
	priority: int = 0,
	max_voices: int = 0,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0
) -> bool:
	if stream == null:
		return false
	var index: int = -1
	if _tick_left == 0:
		index = _pick_fresh_victim(cue, priority, max_voices)
	else:
		index = _pick(_world_slots, cue, priority, max_voices)
	if index < 0:
		return false
	if _tick_left > 0:
		_tick_left -= 1
	var player: AudioStreamPlayer2D = _world[index]
	player.stop()
	player.stream = stream
	player.global_position = position
	player.max_distance = _settings.max_distance * distance_scale
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	_claim(_world_slots[index], cue, priority)
	player.play()
	return true


## Plays `stream` on the interface bus. Returns whether a voice started.
func play_ui(
	stream: AudioStream,
	cue: StringName,
	priority: int = 0,
	max_voices: int = 0,
	volume_db: float = 0.0,
	pitch_scale: float = 1.0
) -> bool:
	if stream == null:
		return false
	var index: int = _pick(_ui_slots, cue, priority, max_voices)
	if index < 0:
		return false
	var player: AudioStreamPlayer = _ui[index]
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	_claim(_ui_slots[index], cue, priority)
	player.play()
	return true


func active_world() -> int:
	return _count_busy(_world_slots)


func active_ui() -> int:
	return _count_busy(_ui_slots)


func world_capacity() -> int:
	return _world.size()


func ui_capacity() -> int:
	return _ui.size()


## Voices of `cue` that are playing now, in both sets.
func active_of(cue: StringName) -> int:
	var count: int = 0
	for slot: Slot in _world_slots:
		if slot.busy and slot.cue == cue:
			count += 1
	for slot: Slot in _ui_slots:
		if slot.busy and slot.cue == cue:
			count += 1
	return count


## Stops the voices that play on `bus` (Sfx: world voices, Ui: interface voices) and frees their
## slots, for a bus that was set to step 0.
func stop_voices(bus: StringName) -> void:
	if bus == &"Sfx":
		for i: int in _world.size():
			_world[i].stop()
			_world_slots[i].busy = false
	elif bus == &"Ui":
		for i: int in _ui.size():
			_ui[i].stop()
			_ui_slots[i].busy = false


func stop_all() -> void:
	for i: int in _world.size():
		_world[i].stop()
		_world_slots[i].busy = false
	for i: int in _ui.size():
		_ui[i].stop()
		_ui_slots[i].busy = false


## The slot to use for a new sound, or -1 to drop it. A cue at its `max_voices` replaces its own
## oldest voice of equal or lower priority; otherwise a free voice, else the oldest voice of
## strictly lower priority.
func _pick(slots: Array[Slot], cue: StringName, priority: int, max_voices: int) -> int:
	if max_voices > 0:
		var same: int = 0
		var oldest_same: int = -1
		for i: int in slots.size():
			var slot: Slot = slots[i]
			if not slot.busy or slot.cue != cue:
				continue
			same += 1
			if slot.priority <= priority and (oldest_same < 0 or slot.seq < slots[oldest_same].seq):
				oldest_same = i
		if same >= max_voices:
			return oldest_same
	var victim: int = -1
	for i: int in slots.size():
		var slot: Slot = slots[i]
		if not slot.busy:
			return i
		if slot.priority < priority and (victim < 0 or slot.seq < slots[victim].seq):
			victim = i
	return victim


## With the tick budget spent: the lowest-priority, then oldest, voice started this tick that is of
## lower priority than the new sound, or -1. A cue at its `max_voices` may only replace its own.
func _pick_fresh_victim(cue: StringName, priority: int, max_voices: int) -> int:
	var victim: int = -1
	var same: int = 0
	for i: int in _world_slots.size():
		var slot: Slot = _world_slots[i]
		if slot.busy and slot.cue == cue:
			same += 1
		if not slot.busy or not slot.fresh or slot.priority >= priority:
			continue
		if victim < 0:
			victim = i
			continue
		var best: Slot = _world_slots[victim]
		if (
			slot.priority < best.priority
			or (slot.priority == best.priority and slot.seq < best.seq)
		):
			victim = i
	if victim >= 0 and max_voices > 0 and same >= max_voices and _world_slots[victim].cue != cue:
		return -1
	return victim


func _claim(slot: Slot, cue: StringName, priority: int) -> void:
	_seq += 1
	slot.busy = true
	slot.cue = cue
	slot.priority = priority
	slot.seq = _seq
	slot.fresh = true


func _count_busy(slots: Array[Slot]) -> int:
	var count: int = 0
	for slot: Slot in slots:
		if slot.busy:
			count += 1
	return count


func _on_finished(slot: Slot) -> void:
	slot.busy = false
