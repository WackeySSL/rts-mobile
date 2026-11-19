class_name BattleSounds
extends Node
## The battle sounds (ADR 0041 section 4): one pass over `runner.snapshot.events` inside
## `runner.ticked`, the sim never written. SHOT, IMPACT, DIED, MINE_BLAST, REPAIRED and UNLOADED
## become a cue by int-indexed tables built when a match starts. STRIKE too: a rupture's launch
## sounds when it is accepted, at the silo, when the silo is the viewer's own or seen (as `StrikeFx`
## shows the launch at the building it is shown), and its landing when `StrikeLandings` (a second
## one, as `EffectsLayer` has) says it landed and the point was seen in the last tick it was in the
## air or is seen now, so the landing's own kills cannot silence it. `update` runs every tick before
## the mute gate: a landing that falls during mute is dropped, not deferred. A landing in the step
## it was fired (delay 0) is never in the air in a snapshot, so it has no boom, as it has no burst
## (the shipped delay is 45). A blackout sounds when it is fired, at its point, when that is its
## owner's or seen, a sweep's hum at the view's centre, its owner's only. A warning of an enemy
## strike is a UI cue. SPAWNED is not here yet.
##
## Fairness: a sound plays only where `EffectsLayer` would show the effect, by the tile of the
## point in that tick's fog (`FogLayer.is_seen`, read-only); the death of an own unit always
## sounds, as its effect always shows. A SHOT sounds at the shooter when its tile is seen; a
## hitscan SHOT (projectile speed 0, which lands no IMPACT) from an unseen shooter at a seen
## target sounds at the target, as its tracer shows then. A DIED record with flag 1 (a cancelled
## site) or 2 (boarded) plays nothing, flag 3 (sold) the pack-up. `reveal_enemies` hears
## everything (the perf arena).
##
## A point farther than `hear_margin_px` (world px) from the view is not played. Events of one
## cue in a tick make one voice, louder by `stack_db` for each extra one, and the cue is quiet
## for its `cooldown_ms` after it played; the pool then caps the new voices of a tick
## (`voices_per_tick`). The variant and the pitch come from `(event id * 31 + tick)`, no random
## generator. Nothing is allocated per tick: the per-cue state is packed arrays made at match
## start. The streams (file or placeholder tone) are made once per process for a table. A restart
## (a new `match_serial`) builds the tables again, which also clears the cooldowns, and
## `match_ended` lifts the pool's tick budget.


## The streams and pitch steps of one table, made once per process (`_built`).
class Built:
	extends RefCounted
	var streams: Array[AudioStream] = []
	var first: PackedInt32Array = PackedInt32Array()
	var variants: PackedInt32Array = PackedInt32Array()
	var pitches: PackedInt32Array = PackedInt32Array()
	var pitch_first: PackedInt32Array = PackedInt32Array()
	var pitch_count: PackedInt32Array = PackedInt32Array()


const AudioServiceScript: GDScript = preload("res://game/view/audio/audio_service.gd")
const CUES_PATH: String = "res://data/audio_cues.tres"
const BUS: StringName = AudioServiceScript.BUS_SFX
const NEUTRAL_PITCH: int = 1000
const MAX_VARIANTS: int = 8
const ID_MIX: int = 31
const NEVER_MS: int = -(1 << 40)

static var _built: Dictionary[AudioCueTable, Built] = {}

@export var runner: MatchRunner
@export var table: AudioCueTable
## Hears the events on tiles the fog hides too.
@export var reveal_enemies: bool = false

## The service that plays: the `AudioService` autoload unless a test sets another node with
## `begin_tick`, `can_play`, `play_world`, `end_ticking` and a `settings` property. A duck-typed
## Node because the autoload declares no `class_name` (tests/project/test_autoloads.gd).
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
var _pitches: PackedInt32Array = PackedInt32Array()
var _pitch_first: PackedInt32Array = PackedInt32Array()
var _pitch_count: PackedInt32Array = PackedInt32Array()
var _streams: Array[AudioStream] = []
## Per weapon index and per type index: the cue index, or -1.
var _shot: PackedInt32Array = PackedInt32Array()
var _impact: PackedInt32Array = PackedInt32Array()
var _hitscan: PackedByteArray = PackedByteArray()
var _death: PackedInt32Array = PackedInt32Array()
var _blast: int = -1
var _repair: int = -1
var _unload: int = -1
var _sold: int = -1
var _rupture_launch: int = -1
var _rupture_land: int = -1
var _blackout: int = -1
var _sweep: int = -1
var _landings: StrikeLandings = StrikeLandings.new()


func _ready() -> void:
	if table == null:
		table = load(CUES_PATH) as AudioCueTable
	if table == null:
		push_error("BattleSounds: %s did not load; no battle sounds" % CUES_PATH)
		return
	if audio == null:
		audio = get_node_or_null("/root/AudioService")
	if audio != null:
		_settings = audio.get(&"settings") as AudioSettings
	if _settings == null:
		_settings = load("res://data/audio_settings.tres") as AudioSettings
	_use_built()
	if runner != null:
		runner.ticked.connect(_on_ticked)
		runner.match_ended.connect(_on_match_ended)


func _exit_tree() -> void:
	if audio != null:
		audio.call(&"end_ticking")


## The match is over: the pool's per-tick budget must not stay set.
func _on_match_ended(_winner: int) -> void:
	if audio != null:
		audio.call(&"end_ticking")


## One tick's events. A frame that plays several ticks calls this once per tick.
func _on_ticked(tick: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap == null or audio == null:
		return
	var viewer: int = FogLayer.local_player_of(runner)
	# Before the gates: the memory of the ruptures in the air must see every tick, muted or not.
	var landed: int = _landings.update(snap, 0 if reveal_enemies else viewer)
	if snap.events.is_empty() and landed == 0:
		return
	# Muted, or the Sfx bus at step 0: nothing would play, so skip the pass (and its cooldowns).
	if not bool(audio.call(&"can_play", BUS)):
		return
	if snap.match_serial != _serial:
		_build(snap)
	_tick = tick
	_ear = _view_rect().grow(_settings.hear_margin_px)
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		_read(snap, events, at, viewer)
	_land_due(snap, landed, viewer)
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
		World.Event.STRIKE:
			_read_strike(snap, events, at, viewer)
			return
		_:
			return
	if cue < 0:
		return
	var heard: bool = own_death or reveal_enemies or FogLayer.is_seen(snap, viewer, x, y)
	if not heard and events[at] == World.Event.SHOT and _is_hitscan(events[at + 5]):
		# The tracer shows when the target's tile is seen, and a hitscan shot lands no IMPACT.
		x = events[at + 6]
		y = events[at + 7]
		heard = FogLayer.is_seen(snap, viewer, x, y)
	if not heard:
		return
	var point: Vector2 = IsoProjection.ground_to_px(x, y)
	if not _ear.has_point(point):
		return
	_add(cue, point, events[at + 1])


## A STRIKE record `[STRIKE, building id, x, y, kind, owner, landing tick, 0]`.
func _read_strike(snap: MatchSnapshot, events: PackedInt32Array, at: int, viewer: int) -> void:
	var own: bool = events[at + 5] == viewer
	var x: int = events[at + 2]
	var y: int = events[at + 3]
	match events[at + 4]:
		Strike.Kind.RUPTURE:
			# At the silo, where `StrikeFx` shows the launch (the footprint centre stands for
			# `BuildingLayer.is_shown`'s footprint test).
			var silo: int = snap.index_of(events[at + 1])
			if silo >= 0:
				_hear(
					snap,
					_rupture_launch,
					snap.pos_x[silo],
					snap.pos_y[silo],
					own,
					events[at + 1],
					viewer
				)
		Strike.Kind.BLACKOUT:
			_hear(snap, _blackout, x, y, own, events[at + 1], viewer)
		Strike.Kind.REVEAL:
			# A sweep has no point: only its owner hears it, at the middle of the view.
			if (own or reveal_enemies) and _sweep >= 0:
				_add(_sweep, _ear.get_center(), events[at + 1])


## The landings `StrikeLandings` found this tick, each where the viewer saw the point as it hit.
func _land_due(snap: MatchSnapshot, landed: int, viewer: int) -> void:
	for index: int in landed:
		var at: Vector2i = _landings.point(index)
		var seen: bool = _landings.was_seen(index) or reveal_enemies
		_hear(snap, _rupture_land, at.x, at.y, seen, index, viewer)


## One event of `cue` at the world point (`x`, `y`), counted when `own` or the point is seen and
## inside the ear.
func _hear(snap: MatchSnapshot, cue: int, x: int, y: int, own: bool, id: int, viewer: int) -> void:
	if cue < 0:
		return
	if not (own or reveal_enemies or FogLayer.is_seen(snap, viewer, x, y)):
		return
	var point: Vector2 = IsoProjection.ground_to_px(x, y)
	if _ear.has_point(point):
		_add(cue, point, id)


## The cue of a DIED record: none for a cancelled site or a boarding, the pack-up for a sale.
func _death_cue(events: PackedInt32Array, at: int) -> int:
	match events[at + Removal.DIED_FLAG_AT]:
		0:
			var type: int = events[at + 4]
			return _death[type] if type >= 0 and type < _death.size() else -1
		Removal.FLAG_SOLD:
			return _sold
	return -1


func _is_hitscan(weapon: int) -> bool:
	return weapon >= 0 and weapon < _hitscan.size() and _hitscan[weapon] == 1


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
		# The variant and the pitch step are the two digits of one number, so every pair occurs.
		var spread: int = posmod(_seed[cue], _variants[cue] * _pitch_count[cue])
		var stream: AudioStream = _streams[_first[cue] + spread % _variants[cue]]
		var pitch: int = _pitches[_pitch_first[cue] + spread / _variants[cue]]
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


## The streams and pitch steps of `table`, made once per process.
func _use_built() -> void:
	var built: Built = _built.get(table) as Built
	if built == null:
		built = _make_built(table)
		_built[table] = built
	_streams = built.streams
	_first = built.first
	_variants = built.variants
	_pitches = built.pitches
	_pitch_first = built.pitch_first
	_pitch_count = built.pitch_count


## One stream per variant of every cue: the file streams (a null one skipped), else placeholder
## tones; an empty `pitch_steps` is one neutral step.
static func _make_built(cues: AudioCueTable) -> Built:
	var built: Built = Built.new()
	for def: AudioCueDef in cues.cues:
		built.first.append(built.streams.size())
		var files: int = 0
		for stream: AudioStream in def.streams:
			if stream != null:
				built.streams.append(stream)
				files += 1
		if files == 0:
			files = clampi(def.variants, 1, MAX_VARIANTS)
			for variant: int in files:
				var hz: int = def.tone_hz + def.tone_hz * variant * 7 / 100
				var tone: AudioStream = PlaceholderTone.make(hz, def.tone_ms, def.noise_permille)
				built.streams.append(tone)
		built.variants.append(files)
		built.pitch_first.append(built.pitches.size())
		if def.pitch_steps.is_empty():
			built.pitches.append(NEUTRAL_PITCH)
			built.pitch_count.append(1)
		else:
			built.pitches.append_array(def.pitch_steps)
			built.pitch_count.append(def.pitch_steps.size())
	return built


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
	_hitscan.resize(snap.weapon_ids.size())
	for weapon: int in snap.weapon_ids.size():
		var weapon_id: StringName = snap.weapon_ids[weapon]
		var hitscan: bool = (
			weapon < snap.weapon_projectile_speed.size()
			and snap.weapon_projectile_speed[weapon] == 0
		)
		_hitscan[weapon] = 1 if hitscan else 0
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
	_rupture_launch = table.index_of(table.strike_rupture_launch)
	_rupture_land = table.index_of(table.strike_rupture_land)
	_blackout = table.index_of(table.strike_blackout)
	_sweep = table.index_of(table.strike_sweep)


func _death_id(snap: MatchSnapshot, type: int) -> StringName:
	if type < snap.type_armour.size() and snap.type_armour[type] == World.Armour.BUILDING:
		return table.death_building
	if WorldSort.is_flyer(snap, type):
		return table.death_air
	var foot: bool = (
		type < snap.type_move_class.size() and snap.type_move_class[type] == World.MoveClass.FOOT
	)
	return table.death_foot if foot else table.death_vehicle
