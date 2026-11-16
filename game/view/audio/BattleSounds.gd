class_name BattleSounds
extends Node
## The battle sounds (ADR 0041 section 4): one pass over `runner.snapshot.events` inside
## `runner.ticked`, the sim never written. SHOT, IMPACT, DIED, MINE_BLAST, REPAIRED and UNLOADED
## become a cue by int-indexed tables built when a match starts. STRIKE and SPAWNED are not here
## yet (their rows follow with the cue sets).
##
## Fairness: a sound plays only where `EffectsLayer` would show the effect, by the tile of the point
## in that tick's fog (`FogLayer.is_seen`, read-only); the death of an own unit always sounds, as
## its effect always shows. A DIED record with flag 1 (a cancelled site) or 2 (boarded) plays
## nothing, flag 3 (sold) the pack-up. `reveal_enemies` hears everything (the perf arena).
##
## A point farther than `hear_margin_px` from the view is not played. Events of one cue in a tick
## make one voice, louder by `stack_db` for each extra one, and the cue is quiet for its
## `cooldown_ms` after it played; the pool then caps the new voices of a tick (`voices_per_tick`).
## The variant and the pitch come from `(event id * 31 + tick)`, no random generator. Nothing is
## allocated per tick: the per-cue state is packed arrays made at match start.

const WEAPON_NONE: int = -1
const ID_MIX: int = 31
const NEVER_MS: int = -(1 << 40)

@export var runner: MatchRunner
@export var table: AudioCueTable
## Hears the events on tiles the fog hides too.
@export var reveal_enemies: bool = false

## The service that plays: the `AudioService` autoload unless a test sets another node with
## `begin_tick`, `can_play`, `play_world`, `end_ticking` and a `settings` property.
var audio: Node
## The frame clock in ms that cooldowns run on. Tests replace it.
var clock: Callable = Time.get_ticks_msec
## `() -> Rect2`: the view in world px. Unset, it is the viewport through its canvas transform.
var view_rect: Callable = Callable()

var _serial: int = -1
var _settings: AudioSettings
var _tick: int = 0
var _ear: Rect2 = Rect2()
## Per cue (index of `table.cues`).
var _cooldown: PackedInt32Array = PackedInt32Array()
var _last_ms: PackedInt64Array = PackedInt64Array()
var _count: PackedInt32Array = PackedInt32Array()
var _seed: PackedInt32Array = PackedInt32Array()
var _at: PackedVector2Array = PackedVector2Array()
var _first: PackedInt32Array = PackedInt32Array()
var _variants: PackedInt32Array = PackedInt32Array()
var _streams: Array[AudioStream] = []
## Per weapon index and per type index: the cue index, or -1.
var _shot: PackedInt32Array = PackedInt32Array()
var _impact: PackedInt32Array = PackedInt32Array()
var _death: PackedInt32Array = PackedInt32Array()
var _blast: int = -1
var _repair: int = -1
var _unload: int = -1
var _sold: int = -1


func _ready() -> void:
	if table == null:
		table = load("res://data/audio_cues.tres") as AudioCueTable
	if audio == null:
		audio = get_node_or_null("/root/AudioService")
	if audio != null:
		_settings = audio.get(&"settings") as AudioSettings
	if _settings == null:
		_settings = load("res://data/audio_settings.tres") as AudioSettings
	_make_streams()
	if runner != null:
		runner.ticked.connect(_on_ticked)


func _exit_tree() -> void:
	if audio != null:
		audio.call(&"end_ticking")


## One tick's events. A frame that plays several ticks calls this once per tick.
func _on_ticked(tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null or audio == null or snap.events.is_empty():
		return
	if not bool(audio.call(&"can_play", &"Sfx")):
		return
	if snap.match_serial != _serial:
		_build(snap)
	_tick = tick
	_ear = _view_rect().grow(_settings.hear_margin_px)
	var viewer: int = FogLayer.local_player_of(runner)
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		_read(snap, events, at, viewer)
	audio.call(&"begin_tick")
	_play_pending()


## Counts the events of one record into its cue, if it is heard.
func _read(snap: MatchSnapshot, events: PackedInt32Array, at: int, viewer: int) -> void:
	var x: int = events[at + 2]
	var y: int = events[at + 3]
	var cue: int = -1
	var own_death: bool = false
	match events[at]:
		World.Event.SHOT:
			cue = _by_weapon(_shot, events[at + 5])
		World.Event.IMPACT:
			cue = _by_weapon(_impact, events[at + 5])
		World.Event.MINE_BLAST:
			cue = _blast
		World.Event.REPAIRED:
			cue = _repair
		World.Event.UNLOADED:
			cue = _unload
		World.Event.DIED:
			cue = _death_cue(events, at)
			own_death = events[at + 5] == viewer
		_:
			return
	if cue < 0:
		return
	if not (own_death or reveal_enemies or FogLayer.is_seen(snap, viewer, x, y)):
		return
	var point: Vector2 = IsoProjection.ground_to_px(x, y)
	if not _ear.has_point(point):
		return
	_add(cue, point, events[at + 1])


## The cue of a DIED record: none for a cancelled site or a boarding, the pack-up for a sale.
func _death_cue(events: PackedInt32Array, at: int) -> int:
	match events[at + Removal.DIED_FLAG_AT]:
		0:
			var type: int = events[at + 4]
			return _death[type] if type >= 0 and type < _death.size() else -1
		Removal.FLAG_SOLD:
			return _sold
	return -1


func _by_weapon(cues: PackedInt32Array, weapon: int) -> int:
	return cues[weapon] if weapon >= 0 and weapon < cues.size() else -1


## One event of cue `cue` at `point`; the first of the tick sets the place and the variant.
func _add(cue: int, point: Vector2, unit_id: int) -> void:
	if int(clock.call()) - _last_ms[cue] < _cooldown[cue]:
		return
	if _count[cue] == 0:
		_at[cue] = point
		_seed[cue] = unit_id * ID_MIX + _tick
	_count[cue] += 1


## Plays one voice per cue that has events, then clears the counts.
func _play_pending() -> void:
	var now: int = int(clock.call())
	for cue: int in _count.size():
		var events_of: int = _count[cue]
		if events_of == 0:
			continue
		_count[cue] = 0
		var def: AudioCueDef = table.cues[cue]
		var seed_of: int = _seed[cue]
		var stream: AudioStream = _streams[_first[cue] + posmod(seed_of, _variants[cue])]
		var pitch: int = def.pitch_steps[posmod(seed_of, def.pitch_steps.size())]
		var stacked: float = _settings.stack_db * float(mini(events_of, def.max_stack + 1) - 1)
		var started: bool = bool(
			audio.call(
				&"play_world",
				stream,
				_at[cue],
				def.id,
				def.priority,
				def.max_voices,
				def.volume_db + stacked,
				float(pitch) / 1000.0
			)
		)
		if started:
			_last_ms[cue] = now


func _view_rect() -> Rect2:
	if view_rect.is_valid():
		return view_rect.call() as Rect2
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Rect2()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()


## One stream per variant of every cue: the file streams, else placeholder tones. Made once.
func _make_streams() -> void:
	_streams.clear()
	_first.resize(table.cues.size())
	_variants.resize(table.cues.size())
	for cue: int in table.cues.size():
		var def: AudioCueDef = table.cues[cue]
		_first[cue] = _streams.size()
		if not def.streams.is_empty():
			_streams.append_array(def.streams)
			_variants[cue] = def.streams.size()
			continue
		var count: int = maxi(def.variants, 1)
		for variant: int in count:
			var hz: int = def.tone_hz + def.tone_hz * variant * 7 / 100
			_streams.append(PlaceholderTone.make(hz, def.tone_ms, def.noise_permille))
		_variants[cue] = count


## The tables of a match: cooldowns, per-cue state, and the cue of each weapon and type.
func _build(snap: MatchSnapshot) -> void:
	_serial = snap.match_serial
	var size: int = table.cues.size()
	_cooldown.resize(size)
	_last_ms.resize(size)
	_count.resize(size)
	_seed.resize(size)
	_at.resize(size)
	for cue: int in size:
		var ms: int = table.cues[cue].cooldown_ms
		_cooldown[cue] = ms if ms >= 0 else _settings.cooldown_ms
		_last_ms[cue] = NEVER_MS
		_count[cue] = 0
	_shot.resize(snap.weapon_ids.size())
	_impact.resize(snap.weapon_ids.size())
	for weapon: int in snap.weapon_ids.size():
		var weapon_id: StringName = snap.weapon_ids[weapon]
		var hitscan: bool = (
			weapon < snap.weapon_projectile_speed.size()
			and snap.weapon_projectile_speed[weapon] == 0
		)
		var family: StringName = table.shot_hitscan if hitscan else table.shot_shell
		_shot[weapon] = table.index_of(table.shot_cues.get(weapon_id, family))
		_impact[weapon] = table.index_of(table.impact_cues.get(weapon_id, table.impact_default))
	_death.resize(snap.type_ids.size())
	for type: int in snap.type_ids.size():
		_death[type] = table.index_of(_death_id(snap, type))
	_blast = table.index_of(table.mine_blast)
	_repair = table.index_of(table.repaired)
	_unload = table.index_of(table.unloaded)
	_sold = table.index_of(table.sold)


func _death_id(snap: MatchSnapshot, type: int) -> StringName:
	if type < snap.type_armour.size() and snap.type_armour[type] == World.Armour.BUILDING:
		return table.death_building
	if WorldSort.is_flyer(snap, type):
		return table.death_air
	var foot: bool = (
		type < snap.type_move_class.size() and snap.type_move_class[type] == World.MoveClass.FOOT
	)
	return table.death_foot if foot else table.death_vehicle
