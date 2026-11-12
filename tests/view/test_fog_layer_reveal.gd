extends GdUnitTestSuite
## The fog fade of the satellite sweep (plan P235, ADR 0036 section 11): when the local player's
## own sweep turns on, or pauses and resumes, the image moves from the old alpha to the new over
## `life.reveal_fade_ms` (data/life_settings.tres) instead of jumping, both ways alike, through a
## patch and through a rebuild (the sweep's flip overflows the dirty list). The layer's millisecond
## clock is a fake that the test moves. The rig is fog_rig.gd (the controls_test scenario, 48 x 48,
## player 1 sees only its tank block).

const Rig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const LIFE: LifeSettings = preload("res://data/life_settings.tres")
const FADE_MS: int = 600
const FAR: Vector2i = Vector2i(40, 40)  ## A tile of the sweep that nobody sees at tick 0.

var _runner: MatchRunner
var _fog: FogLayer
var _now: Array[int] = [1000]


func before_test() -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Rig.scenario(1)
	_runner.start()
	_fog = auto_free(FogLayer.new())
	_fog.runner = _runner
	_fog.life = LIFE.duplicate()
	_fog.msec_clock = func() -> int: return _now[0]
	add_child(_fog)
	_fog.set_process(false)


func _alpha() -> int:
	return _fog.image().get_pixel(FAR.x, FAR.y).a8


## One tick in which the local player's sweep is `state` and `FAR` is `seen`; `rebuild` also marks
## the dirty list as overflowed, as a sweep over the whole map does.
func _tick(state: int, seen: bool, rebuild: bool = false) -> void:
	var snap: MatchSnapshot = _runner.snapshot
	snap.reveal = PackedInt32Array([0, state, 0])
	Rig.flip(snap, 1, [FAR] as Array[Vector2i], seen)
	if rebuild:
		snap.fog.dirty_full[0] = 1
	_runner.ticked.emit(snap.tick)


func test_the_data_file_holds_the_fade_time() -> void:
	assert_int(LIFE.reveal_fade_ms).is_equal(FADE_MS)


func test_a_sweep_that_begins_fades_the_fog_out_and_one_that_pauses_fades_it_back() -> void:
	assert_int(_alpha()).is_equal(255)
	_tick(Reveal.State.ON, true)
	assert_bool(_fog.is_fading()).is_true()
	assert_int(_alpha()).is_equal(255)  # Nothing jumped: the fade has not moved yet.
	_now[0] += FADE_MS / 2
	_fog._process(0.0)
	assert_int(_alpha()).is_between(100, 160)  # About halfway from 255 to 0.
	_now[0] += FADE_MS
	_fog._process(0.0)
	assert_bool(_fog.is_fading()).is_false()
	assert_int(_alpha()).is_equal(0)
	_tick(Reveal.State.PAUSED, false)  # The pause: the whole way back, in the same time.
	assert_bool(_fog.is_fading()).is_true()
	assert_int(_alpha()).is_equal(0)
	_now[0] += FADE_MS / 2
	_fog._process(0.0)
	assert_int(_alpha()).is_between(40, 100)  # Halfway from 0 to the explored 140.
	assert_bool(_fog.is_fading()).is_true()
	_now[0] += FADE_MS
	_fog._process(0.0)
	assert_bool(_fog.is_fading()).is_false()
	assert_int(_alpha()).is_equal(Rig.EXPLORED)  # Explored and not seen now.
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)).is_empty()


func test_the_fade_runs_through_a_rebuild_too() -> void:
	_tick(Reveal.State.ON, true, true)
	assert_bool(_fog.is_fading()).is_true()
	assert_int(_alpha()).is_equal(255)
	_now[0] += FADE_MS * 2
	_fog._process(0.0)
	assert_array(Rig.mismatches(_fog.image(), _runner.snapshot.fog, 1)).is_empty()


func test_a_patch_during_the_fade_lands_on_the_goal_and_a_gap_ends_the_fade() -> void:
	_tick(Reveal.State.ON, true)
	var other: Vector2i = Vector2i(41, 40)
	var snap: MatchSnapshot = _runner.snapshot
	Rig.flip(snap, 1, [other] as Array[Vector2i], true)  # Another tile, mid-fade.
	_runner.ticked.emit(snap.tick)
	assert_bool(_fog.is_fading()).is_true()
	_now[0] += FADE_MS * 2
	_fog._process(0.0)
	assert_int(_fog.image().get_pixel(other.x, other.y).a8).is_equal(0)
	assert_int(_alpha()).is_equal(0)
	_tick(Reveal.State.PAUSED, false)
	Rig.flip(snap, 1, [FAR] as Array[Vector2i], false, 3)  # A gap in the ticks: no fade, a snap.
	_runner.ticked.emit(snap.tick)
	assert_bool(_fog.is_fading()).is_false()
	assert_array(Rig.mismatches(_fog.image(), snap.fog, 1)).is_empty()


func test_a_zero_fade_time_jumps_and_an_enemys_sweep_or_a_plain_flip_never_fades() -> void:
	_fog.life.reveal_fade_ms = 0
	_tick(Reveal.State.ON, true)
	assert_bool(_fog.is_fading()).is_false()
	assert_int(_alpha()).is_equal(0)
	_fog.life.reveal_fade_ms = FADE_MS
	var snap: MatchSnapshot = _runner.snapshot
	snap.reveal = PackedInt32Array([0, Reveal.State.ON, Reveal.State.ON])  # No flip of the local one.
	Rig.flip(snap, 1, [Vector2i(42, 42)] as Array[Vector2i], true)
	_runner.ticked.emit(snap.tick)
	assert_bool(_fog.is_fading()).is_false()  # A tank walking is no sweep.
