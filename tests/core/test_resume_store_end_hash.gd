extends GdUnitTestSuite
## The end hash of the resume header (plan P516, ADR 0042 section 6): `World.state_hash()` at the
## stored tick, written as a String in the sealed header. It is read back as written, a header
## without it or with a value that is not an integer string is refused, and a changed digit breaks
## the seal. The restore's own comparison is in test_restorer.gd.

const PrefsRig: GDScript = preload("res://tests/support/prefs_rig.gd")
const TICKS: int = 40

var _warnings: Array[String] = []


func before_test() -> void:
	PrefsRig.begin()
	_warnings.clear()
	ResumeStore.warning_sink = func(text: String) -> void: _warnings.append(text)


func after_test() -> void:
	ResumeStore.warning_sink = Callable()
	PrefsRig.end()


func _runner() -> Array:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = DevRoutes.SKIRMISH_DERRICK
	setup.match_seed = 4242
	setup.opponents = [load(DevRoutes.OPPONENT_RENEW) as AiDef]
	setup.opponent_levels = [load(DevRoutes.LEVEL_HARD) as AiDifficultyDef]
	var runner: MatchRunner = auto_free(MatchRunner.new())
	assert_int(setup.apply(runner)).is_equal(OK)
	runner.start()
	runner.run_ticks(TICKS)
	return [setup, runner]


## A file with a right seal whose header `mutate` has changed.
func _sealed(pair: Array, mutate: Callable) -> PackedByteArray:
	var runner: MatchRunner = pair[1]
	var raw: PackedByteArray = runner.replay.to_bytes()
	var body: PackedByteArray = raw.compress(ResumeStore.COMPRESSION)
	var header: Dictionary = ResumeStore.make_header(
		pair[0],
		TICKS,
		runner.world.defs_hash(),
		ResumeStore.app_version(),
		raw.size(),
		body.size(),
		runner.world.state_hash()
	)
	mutate.call(header)
	return ResumeStore.seal(JSON.stringify(header).to_utf8_buffer(), body)


func _decode(bytes: PackedByteArray) -> ResumeData:
	return ResumeStore.decode(bytes, ResumeStore.app_version(), ResumeStore.ANY_DEFS_HASH)


func _refused(bytes: PackedByteArray) -> void:
	_warnings.clear()
	assert_object(_decode(bytes)).is_null()
	assert_int(_warnings.size()).is_equal(1)


func test_the_end_hash_is_read_back_as_written() -> void:
	var pair: Array = _runner()
	var data: ResumeData = _decode(_sealed(pair, func(_h: Dictionary) -> void: pass))
	assert_int(data.end_hash).is_equal((pair[1] as MatchRunner).world.state_hash())


func test_a_file_written_from_a_runner_holds_the_worlds_hash_at_its_tick() -> void:
	var pair: Array = _runner()
	assert_int(ResumeStore.write_from(pair[1], pair[0])).is_equal(OK)
	var data: ResumeData = ResumeStore.read()
	assert_int(data.tick).is_equal(TICKS)
	assert_int(data.end_hash).is_equal((pair[1] as MatchRunner).world.state_hash())


func test_a_resealed_end_hash_is_read_as_the_new_value() -> void:
	# The seal covers the header, so a change without a new seal is refused (the next test); a
	# resealed one is the writer's own word, and the restore compares it to the replay.
	var pair: Array = _runner()
	var data: ResumeData = _decode(
		_sealed(pair, func(h: Dictionary) -> void: h[ResumeStore.K_END] = "12345")
	)
	assert_int(data.end_hash).is_equal(12345)


func test_an_end_hash_flipped_in_the_bytes_breaks_the_seal() -> void:
	var pair: Array = _runner()
	var bytes: PackedByteArray = _sealed(pair, func(_h: Dictionary) -> void: pass)
	var header: String = bytes.slice(ResumeStore.FIXED_BYTES).get_string_from_ascii()
	var key: String = '"end_hash":"'
	var at: int = header.find(key) + key.length()
	assert_int(header.find(key)).is_greater(0)
	bytes[ResumeStore.FIXED_BYTES + at] ^= 1  # One digit of the end hash.
	_refused(bytes)


func test_a_missing_or_unreadable_end_hash_is_refused() -> void:
	var pair: Array = _runner()
	_refused(_sealed(pair, func(h: Dictionary) -> void: h.erase(ResumeStore.K_END)))
	_refused(_sealed(pair, func(h: Dictionary) -> void: h[ResumeStore.K_END] = "abc"))
	_refused(_sealed(pair, func(h: Dictionary) -> void: h[ResumeStore.K_END] = 5))


func test_the_format_is_2_and_a_format_1_file_is_refused_and_deleted() -> void:
	assert_int(ResumeStore.FORMAT).is_equal(2)
	var pair: Array = _runner()
	var old: PackedByteArray = _sealed(
		pair,
		func(h: Dictionary) -> void:
			h[ResumeStore.K_FORMAT] = 1
			h.erase(ResumeStore.K_END)
	)
	_refused(old)
	var file: FileAccess = FileAccess.open(ResumeStore.path(), FileAccess.WRITE)
	file.store_buffer(old)
	file.close()
	_warnings.clear()
	assert_object(ResumeStore.read()).is_null()
	assert_int(_warnings.size()).is_equal(1)
	assert_bool(FileAccess.file_exists(ResumeStore.path())).is_false()
