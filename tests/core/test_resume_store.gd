extends GdUnitTestSuite
## ResumeStore (plan P514, ADR 0042 section 6): the file a paused match leaves, the pointer in
## section `match`, and every refusal on read (a damaged, cut or foreign file, another build,
## changed data, a lesson, a log that is not the setup's match) deleting it. The save file and the
## resume file live in the PrefsRig folder, never the device's `user://`.

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const SCENARIO: String = DevRoutes.SKIRMISH_DERRICK
const SEED: int = 4242
const TICKS: int = 40


class FakeFlow:
	extends Node
	signal match_loading(setup: MatchSetup)
	var runner: MatchRunner = null
	var setup: MatchSetup = null

	func current_runner() -> MatchRunner:
		return runner

	func current_setup() -> MatchSetup:
		return setup


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
	setup.map_id = &"kestrel_flats"
	return setup


func _runner(setup: MatchSetup) -> MatchRunner:
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(setup.apply(runner)).is_equal(OK)
	runner.start()
	runner.run_ticks(TICKS)
	return runner


## A running match and its written file: [setup, runner].
func _written() -> Array:
	var setup: MatchSetup = _setup()
	var runner: MatchRunner = _runner(setup)
	assert_int(ResumeStore.write_from(runner, setup)).is_equal(OK)
	return [setup, runner]


func _file(setup: MatchSetup, runner: MatchRunner, tick: int, version: String) -> PackedByteArray:
	return ResumeStore.encode(setup, runner.replay, tick, runner.world.defs_hash(), version)


func _put(bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(ResumeStore.path(), FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _pointer() -> Dictionary:
	return SaveService.get_section(ResumeStore.SECTION)


func _decode(bytes: PackedByteArray) -> ResumeData:
	return ResumeStore.decode(bytes, ResumeStore.app_version(), ResumeStore.ANY_DEFS_HASH)


func test_write_then_read_gives_the_setup_the_log_and_the_tick() -> void:
	var pair: Array = _written()
	var setup: MatchSetup = pair[0]
	var runner: MatchRunner = pair[1]
	assert_bool(ResumeStore.has_file()).is_true()
	assert_str(ResumeStore.path().get_base_dir()).is_equal(PrefsRig.dir())
	var data: ResumeData = ResumeStore.read(runner.world.defs_hash())
	assert_object(data).is_not_null()
	assert_dict(data.setup.to_dict()).is_equal(setup.to_dict())
	assert_array(data.replay.to_bytes()).is_equal(runner.replay.to_bytes())
	assert_int(data.tick).is_equal(TICKS)
	assert_int(data.tick).is_equal(runner.world.tick)
	assert_int(data.local_player).is_equal(setup.scenario().local_player)
	assert_str(data.app_version).is_equal(ResumeStore.app_version())
	assert_int(data.defs_hash).is_equal(runner.world.defs_hash())
	assert_bool(data.replay.checkpoint_ticks.size() > 0).is_true()


func test_the_pointer_names_the_file() -> void:
	_written()
	var pointer: Dictionary = _pointer()
	var size: int = FileAccess.get_file_as_bytes(ResumeStore.path()).size()
	assert_int(pointer[ResumeStore.P_TICK]).is_equal(TICKS)
	assert_str(pointer[ResumeStore.P_APP]).is_equal(ResumeStore.app_version())
	assert_int(pointer[ResumeStore.P_BYTES]).is_equal(size)
	assert_int(str(pointer[ResumeStore.P_SHA]).length()).is_equal(64)


func test_a_second_write_replaces_the_file_and_leaves_no_temp_file() -> void:
	var pair: Array = _written()
	var runner: MatchRunner = pair[1]
	runner.run_ticks(30)
	assert_int(ResumeStore.write_from(runner, pair[0])).is_equal(OK)
	assert_bool(FileAccess.file_exists(ResumeStore.path() + ".tmp")).is_false()
	assert_int(ResumeStore.read().tick).is_equal(TICKS + 30)
	assert_int(_pointer()[ResumeStore.P_TICK]).is_equal(TICKS + 30)


func test_a_lesson_is_never_written_and_deletes_an_old_file() -> void:
	var pair: Array = _written()
	var lesson: MatchSetup = _setup()
	lesson.lesson_id = &"lesson_1"
	assert_int(ResumeStore.write_from(pair[1], lesson)).is_equal(ERR_UNAVAILABLE)
	assert_bool(FileAccess.file_exists(ResumeStore.path())).is_false()
	assert_bool(_pointer().is_empty()).is_true()


func test_an_ended_match_is_not_written_and_deletes_the_file() -> void:
	var pair: Array = _written()
	var runner: MatchRunner = pair[1]
	runner.snapshot.match_end_tick = 5
	assert_int(ResumeStore.write_from(runner, pair[0])).is_equal(ERR_UNAVAILABLE)
	assert_bool(ResumeStore.has_file()).is_false()


func test_nulls_write_nothing_and_keep_an_existing_file() -> void:
	var pair: Array = _written()
	assert_int(ResumeStore.write_from(null, pair[0])).is_equal(ERR_UNCONFIGURED)
	assert_int(ResumeStore.write_from(pair[1], null)).is_equal(ERR_UNCONFIGURED)
	assert_bool(ResumeStore.has_file()).is_true()


func test_delete_removes_file_temp_and_pointer_and_is_safe_twice() -> void:
	_written()
	var temp: FileAccess = FileAccess.open(ResumeStore.path() + ".tmp", FileAccess.WRITE)
	temp.store_string("half a write")
	temp.close()
	ResumeStore.delete()
	ResumeStore.delete()
	assert_bool(FileAccess.file_exists(ResumeStore.path())).is_false()
	assert_bool(FileAccess.file_exists(ResumeStore.path() + ".tmp")).is_false()
	assert_bool(_pointer().is_empty()).is_true()
	assert_bool(ResumeStore.has_file()).is_false()


func test_no_file_reads_as_null() -> void:
	assert_object(ResumeStore.read()).is_null()
	assert_bool(ResumeStore.has_file()).is_false()


func test_a_refusal_logs_one_line_through_the_sink() -> void:
	_put("not a resume file at all".to_utf8_buffer())
	ResumeStore.read()
	assert_int(_warnings.size()).is_equal(1)
	assert_bool(_warnings[0].contains("not a resume file")).is_true()


func test_a_damaged_body_is_refused_and_deleted() -> void:
	_written()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ResumeStore.path())
	bytes[bytes.size() - 3] ^= 0x55
	_put(bytes)
	assert_object(ResumeStore.read()).is_null()
	assert_bool(FileAccess.file_exists(ResumeStore.path())).is_false()
	assert_bool(_pointer().is_empty()).is_true()


func test_a_cut_file_is_refused() -> void:
	_written()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(ResumeStore.path())
	for keep: int in [0, 3, 9, bytes.size() / 2, bytes.size() - 1]:
		assert_object(_decode(bytes.slice(0, keep))).is_null()


func test_a_foreign_file_is_refused_and_deleted() -> void:
	_put("not a resume file at all".to_utf8_buffer())
	assert_object(ResumeStore.read()).is_null()
	assert_bool(FileAccess.file_exists(ResumeStore.path())).is_false()


func test_another_app_version_is_refused_and_deleted() -> void:
	var pair: Array = _written()
	_put(_file(pair[0], pair[1], TICKS, "Beta 0"))
	assert_object(ResumeStore.read()).is_null()
	assert_bool(FileAccess.file_exists(ResumeStore.path())).is_false()


func test_other_data_is_refused_and_deleted() -> void:
	var pair: Array = _written()
	assert_object(ResumeStore.read((pair[1] as MatchRunner).world.defs_hash() + 1)).is_null()
	assert_bool(FileAccess.file_exists(ResumeStore.path())).is_false()


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


func test_encode_refuses_unusable_input() -> void:
	var pair: Array = _written()
	var replay: Replay = (pair[1] as MatchRunner).replay
	assert_bool(ResumeStore.encode(null, replay, 1, 1, "x").is_empty()).is_true()
	assert_bool(ResumeStore.encode(pair[0], null, 1, 1, "x").is_empty()).is_true()
	assert_bool(ResumeStore.encode(pair[0], replay, -1, 1, "x").is_empty()).is_true()
