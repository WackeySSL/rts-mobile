extends GdUnitTestSuite
## BattleSounds (ADR 0041 section 4, plan P502) on scripted snapshots: the fog gate (an unseen enemy
## event gives no cue, a seen one does, the death of an own unit always does), the DIED flags, the
## per-tick voice budget on the real pool, the cooldown and the stack, and no object made per tick.
## On controls_test: player 1 sees tile (8, 18) and not tile (40, 40).

const Fog: GDScript = preload("res://tests/view/support/fog_rig.gd")
const Rig: GDScript = preload("res://tests/view/support/effects_rig.gd")
const SERVICE_SCRIPT: String = "res://game/view/audio/audio_service.gd"
const SEEN: Vector2i = Vector2i(8500, 18500)
const DARK: Vector2i = Vector2i(40500, 40500)
const EVERYWHERE: Rect2 = Rect2(-100000, -100000, 200000, 200000)


## Stands in for AudioService where the cue itself is the subject: records each play.
class Spy:
	extends Node
	var settings: AudioSettings
	var plays: int = 0
	var cues: Array[StringName] = []
	var last_db: float = 0.0
	var last_pitch: float = 0.0

	func can_play(_bus: StringName) -> bool:
		return true

	func begin_tick() -> void:
		pass

	func end_ticking() -> void:
		pass

	func play_world(
		_stream: AudioStream,
		_position: Vector2,
		cue: StringName,
		_priority: int = 0,
		_max_voices: int = 0,
		volume_db: float = 0.0,
		pitch_scale: float = 1.0
	) -> bool:
		plays += 1
		cues.append(cue)
		last_db = volume_db
		last_pitch = pitch_scale
		return true


var _now_ms: int = 0
var _tick: int = 0
var _runner: MatchRunner
var _sounds: BattleSounds
var _spy: Spy
var _settings: AudioSettings
var _service: Node
var _tank: int = 0


func before_test() -> void:
	_now_ms = 1000
	_tick = 0
	_settings = (load("res://data/audio_settings.tres") as AudioSettings).duplicate()
	_settings.fade_ms = 0
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Fog.scenario(1)
	_runner.start()
	_tank = _runner.snapshot.type_ids.find(&"light_tank")
	_spy = auto_free(Spy.new())
	_spy.settings = _settings
	_make(_spy)


func after_test() -> void:
	if _service != null:
		_service.free()
		_service = null
	CommandQueue.clear()


func _make(audio: Node) -> void:
	if _sounds != null:
		_sounds.free()
	_sounds = BattleSounds.new()
	_sounds.runner = _runner
	_sounds.audio = audio
	_sounds.clock = func() -> int: return _now_ms
	_sounds.view_rect = func() -> Rect2: return EVERYWHERE
	add_child(_sounds)


func _real_service() -> Node:
	_service = (load(SERVICE_SCRIPT) as GDScript).new()
	_service.set("settings", _settings)
	add_child(_service)
	_make(_service)
	return _service


func _deliver(events: PackedInt32Array) -> void:
	_tick += 1
	_runner.snapshot.events = events
	_runner.ticked.emit(_tick)


func _record(kind: int, at: Vector2i, unit_id: int = 1, owner_id: int = 2) -> PackedInt32Array:
	match kind:
		World.Event.SHOT:
			return Rig.shot(at, at, 0, unit_id)
		World.Event.IMPACT:
			return Rig.impact(at, 0, unit_id)
		World.Event.DIED:
			return Rig.died(at, _tank, unit_id, owner_id)
	# MINE_BLAST and REPAIRED: [kind, id, x, y, weapon or target id, owner, 0, 0].
	return PackedInt32Array([kind, unit_id, at.x, at.y, 0, owner_id, 0, 0])


func _died(flag: int, owner_id: int = 1) -> PackedInt32Array:
	var events: PackedInt32Array = Rig.died(SEEN, _tank, 1, owner_id)
	events[Removal.DIED_FLAG_AT] = flag
	return events


func test_an_unseen_enemy_event_is_silent_and_a_seen_one_sounds() -> void:
	var kinds: Array[int] = [
		World.Event.SHOT,
		World.Event.IMPACT,
		World.Event.DIED,
		World.Event.MINE_BLAST,
		World.Event.REPAIRED,
		World.Event.UNLOADED,
	]
	for kind: int in kinds:
		_spy.plays = 0
		_now_ms += 1000
		_deliver(_record(kind, DARK))
		assert_int(_spy.plays).override_failure_message("dark kind %d" % kind).is_equal(0)
		_deliver(_record(kind, SEEN))
		assert_int(_spy.plays).override_failure_message("seen kind %d" % kind).is_equal(1)


func test_the_death_of_an_own_unit_in_the_dark_sounds_and_reveal_enemies_hears_all() -> void:
	_deliver(_record(World.Event.DIED, DARK, 1, 1))
	assert_int(_spy.plays).is_equal(1)
	_now_ms += 1000
	_deliver(_record(World.Event.SHOT, DARK))
	assert_int(_spy.plays).is_equal(1)
	_sounds.reveal_enemies = true
	_deliver(_record(World.Event.SHOT, DARK))
	assert_int(_spy.plays).is_equal(2)


func test_a_point_beyond_the_hear_margin_is_silent() -> void:
	var here: Vector2 = IsoProjection.ground_to_px(SEEN.x, SEEN.y)
	var margin: float = _settings.hear_margin_px
	_sounds.view_rect = func() -> Rect2:
		return Rect2(here + Vector2(margin + 50.0, 0.0), Vector2.ONE)
	_deliver(_record(World.Event.SHOT, SEEN))
	assert_int(_spy.plays).is_equal(0)
	_sounds.view_rect = func() -> Rect2:
		return Rect2(here + Vector2(margin - 50.0, 0.0), Vector2.ONE)
	_deliver(_record(World.Event.SHOT, SEEN))
	assert_int(_spy.plays).is_equal(1)


func test_the_died_flags_cancelled_and_boarded_are_silent_and_sold_packs_up() -> void:
	for flag: int in [Removal.FLAG_CANCELLED, Removal.FLAG_BOARDED]:
		_now_ms += 1000
		_deliver(_died(flag))
		assert_int(_spy.plays).override_failure_message("flag %d" % flag).is_equal(0)
	_now_ms += 1000
	_deliver(_died(Removal.FLAG_SOLD))
	assert_array(_spy.cues).is_equal([&"sold"])
	_now_ms += 1000
	_runner.snapshot.type_move_class[_tank] = World.MoveClass.FOOT
	_sounds._serial = -1  # A new match builds the tables again.
	_deliver(_died(0))
	assert_array(_spy.cues).is_equal([&"sold", &"death_foot"])


func test_a_death_cue_follows_the_move_class_and_a_building_collapses() -> void:
	_deliver(Rig.died(SEEN, _tank))
	_runner.snapshot.type_armour[_tank] = World.Armour.BUILDING
	_sounds._serial = -1  # A new match builds the tables again.
	_now_ms += 1000
	_deliver(Rig.died(SEEN, _tank))
	assert_array(_spy.cues).is_equal([&"death_vehicle", &"death_building"])


func test_the_same_cue_inside_its_cooldown_plays_once() -> void:
	_deliver(_record(World.Event.SHOT, SEEN))
	_now_ms += _settings.cooldown_ms - 10
	_deliver(_record(World.Event.SHOT, SEEN))
	assert_int(_spy.plays).is_equal(1)
	_now_ms += 20
	_deliver(_record(World.Event.SHOT, SEEN))
	assert_int(_spy.plays).is_equal(2)


func test_events_of_one_cue_in_a_tick_make_one_louder_voice() -> void:
	_deliver(_record(World.Event.SHOT, SEEN))
	var single_db: float = _spy.last_db
	_now_ms += 1000
	var events: PackedInt32Array = _record(World.Event.SHOT, SEEN, 1)
	events.append_array(_record(World.Event.SHOT, SEEN, 2))
	events.append_array(_record(World.Event.SHOT, SEEN, 3))
	_deliver(events)
	assert_int(_spy.plays).is_equal(2)
	assert_float(_spy.last_db).is_equal_approx(single_db + 2.0 * _settings.stack_db, 0.001)


func test_the_variant_and_pitch_depend_only_on_the_event_and_the_tick() -> void:
	var pitches: Array[float] = []
	for _round: int in 2:
		_tick = 6
		_now_ms += 1000
		_deliver(_record(World.Event.SHOT, SEEN, 4))
		pitches.append(_spy.last_pitch)
	assert_float(pitches[0]).is_equal(pitches[1])


func test_at_most_voices_per_tick_new_voices_start() -> void:
	_settings.voices_per_tick = 3
	var service: Node = _real_service()
	var events: PackedInt32Array = PackedInt32Array()
	for kind: int in [
		World.Event.SHOT,
		World.Event.IMPACT,
		World.Event.MINE_BLAST,
		World.Event.REPAIRED,
		World.Event.UNLOADED,
		World.Event.DIED,
	]:
		events.append_array(_record(kind, SEEN, 1, 1))
	_deliver(events)
	assert_int(service.get_pool_for_tests().active_world()).is_equal(3)


func test_a_tick_makes_no_object() -> void:
	var events: PackedInt32Array = _record(World.Event.SHOT, SEEN)
	events.append_array(_record(World.Event.DIED, SEEN, 2))
	events.append_array(_record(World.Event.IMPACT, DARK, 3))
	for _warm: int in 3:
		_now_ms += 1000
		_deliver(events)
	var before: int = roundi(Performance.get_monitor(Performance.OBJECT_COUNT))
	for _round: int in 200:
		_now_ms += 1000
		_deliver(events)
	assert_int(roundi(Performance.get_monitor(Performance.OBJECT_COUNT))).is_equal(before)
	assert_int(_spy.plays).is_greater(100)


func test_every_roster_weapon_and_type_has_a_cue_and_every_mapped_cue_exists() -> void:
	var table: AudioCueTable = load("res://data/audio_cues.tres") as AudioCueTable
	var ids: Array[StringName] = [
		table.shot_hitscan,
		table.shot_shell,
		table.impact_default,
		table.mine_blast,
		table.repaired,
		table.unloaded,
		table.death_foot,
		table.death_vehicle,
		table.death_air,
		table.death_building,
		table.sold,
	]
	ids.append_array(table.shot_cues.values())
	ids.append_array(table.impact_cues.values())
	for cue_id: StringName in ids:
		assert_int(table.index_of(cue_id)).override_failure_message(str(cue_id)).is_greater(-1)
	for weapon: StringName in table.shot_cues:
		assert_bool(FileAccess.file_exists("res://data/weapons/%s.tres" % weapon)).is_true()
