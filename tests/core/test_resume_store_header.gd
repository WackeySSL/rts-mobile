extends GdUnitTestSuite
## ResumeStore's refusals of a file whose bytes were changed (plan P514, ADR 0042 section 6): the
## check covers the header and the body, a header that is not readable or not plausible (not JSON,
## a non-ASCII byte, zero or wrong sizes, a tick or seat the log does not give, another scenario or
## defs hash than the log's) is refused with one line through `warning_sink` and no engine error.

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const SEED: int = 4242
const TICKS: int = 40

var _warnings: Array[String] = []


func before_test() -> void:
	PrefsRig.begin()
	_warnings.clear()
	ResumeStore.warning_sink = func(text: String) -> void: _warnings.append(text)


func after_test() -> void:
	ResumeStore.warning_sink = Callable()
	PrefsRig.end()


func _setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SCENARIO
	setup.match_seed = SEED
	setup.opponents = [load(DevRoutes.OPPONENT_RENEW) as AiDef]
	setup.opponent_levels = [load(DevRoutes.LEVEL_HARD) as AiDifficultyDef]
	return setup


## A running match and its written file: [setup, runner].
func _written() -> Array:
	var setup: MatchSetup = _setup()
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(setup.apply(runner)).is_equal(OK)
	runner.start()
	runner.run_ticks(TICKS)
	assert_int(ResumeStore.write_from(runner, setup)).is_equal(OK)
	return [setup, runner]


func _file(setup: MatchSetup, runner: MatchRunner, tick: int, version: String) -> PackedByteArray:
	return ResumeStore.encode(
		setup, runner.replay, tick, runner.world.defs_hash(), version, runner.world.state_hash()
	)


func _decode(bytes: PackedByteArray) -> ResumeData:
	return ResumeStore.decode(bytes, ResumeStore.app_version(), ResumeStore.ANY_DEFS_HASH)


## A file with a right check but a header changed by `mutate` (a Callable on the header Dictionary).
func _sealed(pair: Array, mutate: Callable, tick: int = TICKS) -> PackedByteArray:
	var runner: MatchRunner = pair[1]
	var raw: PackedByteArray = runner.replay.to_bytes()
	var body: PackedByteArray = raw.compress(ResumeStore.COMPRESSION)
	var header: Dictionary = ResumeStore.make_header(
		pair[0],
		tick,
		runner.world.defs_hash(),
		ResumeStore.app_version(),
		raw.size(),
		body.size(),
		runner.world.state_hash()
	)
	mutate.call(header)
	return ResumeStore.seal(JSON.stringify(header).to_utf8_buffer(), body)


func _refused(bytes: PackedByteArray) -> void:
	_warnings.clear()
	assert_object(_decode(bytes)).is_null()
	assert_int(_warnings.size()).is_equal(1)


func test_an_untouched_sealed_file_is_accepted() -> void:
	var pair: Array = _written()
	assert_object(_decode(_sealed(pair, func(_h: Dictionary) -> void: pass))).is_not_null()


func test_a_header_that_is_not_json_is_refused_quietly() -> void:
	var pair: Array = _written()
	var body: PackedByteArray = PackedByteArray([1, 2, 3])
	_refused(ResumeStore.seal("{not json at all".to_utf8_buffer(), body))
	_refused(ResumeStore.seal("[1, 2]".to_utf8_buffer(), body))
	assert_bool(pair.size() == 2).is_true()


func test_a_header_with_a_non_ascii_byte_is_refused_quietly() -> void:
	var text: PackedByteArray = '{"a": 1}'.to_utf8_buffer()
	text[3] = 0xFF
	_refused(ResumeStore.seal(text, PackedByteArray([1, 2, 3])))


func test_zero_sizes_are_refused_quietly() -> void:
	var pair: Array = _written()
	_refused(_sealed(pair, func(h: Dictionary) -> void: h[ResumeStore.K_RAW] = 0))
	_refused(_sealed(pair, func(h: Dictionary) -> void: h[ResumeStore.K_PACKED] = 0))


func test_a_raw_size_that_is_not_the_body_s_is_refused_quietly() -> void:
	var pair: Array = _written()
	_refused(_sealed(pair, func(h: Dictionary) -> void: h[ResumeStore.K_RAW] += 7))


func test_a_body_over_the_cap_is_refused() -> void:
	var pair: Array = _written()
	var over: int = ResumeStore.MAX_BODY_BYTES + 1
	_refused(_sealed(pair, func(h: Dictionary) -> void: h[ResumeStore.K_RAW] = over))


func test_a_file_over_the_cap_is_refused_and_deleted() -> void:
	var file: FileAccess = FileAccess.open(ResumeStore.path(), FileAccess.WRITE)
	file.store_buffer(PackedByteArray([0, 0, 0, 0]))
	file.seek(ResumeStore.MAX_FILE_BYTES)
	file.store_8(0)
	file.close()
	assert_object(ResumeStore.read()).is_null()
	assert_bool(FileAccess.file_exists(ResumeStore.path())).is_false()
	assert_int(_warnings.size()).is_equal(1)


func test_a_tampered_tick_or_seat_is_refused() -> void:
	var pair: Array = _written()
	_refused(_sealed(pair, func(_h: Dictionary) -> void: pass, 1000000))
	_refused(_sealed(pair, func(h: Dictionary) -> void: h[ResumeStore.K_PLAYER] = 7))
	var last: int = (pair[1] as MatchRunner).replay.checkpoint_ticks[-1]
	_refused(_sealed(pair, func(_h: Dictionary) -> void: pass, last + Replay.CHECKPOINT_PERIOD))
	assert_object(_decode(_sealed(pair, func(_h: Dictionary) -> void: pass, last))).is_not_null()


func test_a_header_changed_after_the_check_is_refused() -> void:
	var pair: Array = _written()
	var bytes: PackedByteArray = ResumeStore.encode(
		pair[0], (pair[1] as MatchRunner).replay, TICKS, 5, ResumeStore.app_version(), 1
	)
	bytes[ResumeStore.FIXED_BYTES + 3] ^= 1
	_refused(bytes)


func test_a_header_defs_hash_that_is_not_the_log_s_is_refused() -> void:
	var pair: Array = _written()
	var runner: MatchRunner = pair[1]
	var bytes: PackedByteArray = ResumeStore.encode(
		pair[0],
		runner.replay,
		TICKS,
		runner.world.defs_hash() + 1,
		ResumeStore.app_version(),
		runner.world.state_hash()
	)
	_refused(bytes)


func test_a_setup_of_another_scenario_than_the_log_is_refused() -> void:
	var pair: Array = _written()
	var other: MatchSetup = MatchSetup.new()
	other.scenario_path = "res://data/scenarios/controls_test.tres"
	other.match_seed = SEED
	_refused(_file(other, pair[1], TICKS, ResumeStore.app_version()))


func test_a_log_of_another_match_is_refused() -> void:
	var pair: Array = _written()
	var other: MatchSetup = MatchSetup.from_dict((pair[0] as MatchSetup).to_dict())
	other.match_seed = SEED + 1
	assert_object(_decode(_file(other, pair[1], TICKS, ResumeStore.app_version()))).is_null()


func test_a_tick_before_the_last_checkpoint_is_refused() -> void:
	var pair: Array = _written()
	assert_object(_decode(_file(pair[0], pair[1], 5, ResumeStore.app_version()))).is_null()


func test_a_lesson_in_the_file_is_refused() -> void:
	var pair: Array = _written()
	var lesson: MatchSetup = MatchSetup.from_dict((pair[0] as MatchSetup).to_dict())
	lesson.lesson_id = &"lesson_1"
	assert_object(_decode(_file(lesson, pair[1], TICKS, ResumeStore.app_version()))).is_null()


func test_a_cut_file_is_refused() -> void:
	_written()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ResumeStore.path())
	for keep: int in [0, 3, 9, bytes.size() / 2, bytes.size() - 1]:
		assert_object(_decode(bytes.slice(0, keep))).is_null()


func test_encode_refuses_unusable_input() -> void:
	var pair: Array = _written()
	var replay: Replay = (pair[1] as MatchRunner).replay
	assert_bool(ResumeStore.encode(null, replay, 1, 1, "x", 1).is_empty()).is_true()
	assert_bool(ResumeStore.encode(pair[0], null, 1, 1, "x", 1).is_empty()).is_true()
	assert_bool(ResumeStore.encode(pair[0], replay, -1, 1, "x", 1).is_empty()).is_true()
