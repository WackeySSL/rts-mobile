class_name ResumeStore
extends RefCounted
## The resume file (ADR 0042 section 6): `resume.bin` beside the save file, plus a pointer in
## `SaveService` section `match`. The file holds the match setup and the compressed `Replay`, so
## the restore (plan P515) can play the match again from tick 0 to where the player left. It is
## data of one build only: a file from another `app_version`, or one whose `defs_hash` does not
## match the data now, is refused and deleted. Main thread only; no clock and no randomness, and
## nothing here is read by `game/sim`.
##
## Layout: `MAGIC` (4 bytes), the header's byte count (u32 little endian), the header (JSON
## text: format, app_version, defs_hash as a String, tick, local_player, the setup dictionary, the
## compressed and the raw size of the body, the body's sha256), then the body: `Replay.to_bytes()`
## compressed with zstd. The body's hash is checked before it is decompressed, so a damaged or cut
## file is refused without the engine ever seeing it.
##
## Who writes and deletes: `ResumeWatcher` calls `write_from` on the app pause and `delete` when
## the match ends, is left or replaced; the restore calls `read` and, on a failed restore,
## `delete`. A tutorial lesson is never written (the lesson restarts).

const FORMAT: int = 1
const FILE_NAME: String = "resume.bin"
const SECTION: StringName = &"match"
const MAGIC: PackedByteArray = [0x52, 0x53, 0x4D, 0x31]  # "RSM1"
const COMPRESSION: FileAccess.CompressionMode = FileAccess.COMPRESSION_ZSTD
## Bounds for a corrupt header: the header is a few hundred bytes, the raw replay well under this.
const MAX_HEADER_BYTES: int = 65536
const MAX_BODY_BYTES: int = 134217728
## `read` argument: do not compare the data's defs_hash (a real hash is never 0).
const ANY_DEFS_HASH: int = 0
const K_FORMAT: String = "format"
const K_APP: String = "app_version"
const K_DEFS: String = "defs_hash"
const K_TICK: String = "tick"
const K_PLAYER: String = "local_player"
const K_SETUP: String = "setup"
const K_PACKED: String = "packed_bytes"
const K_RAW: String = "raw_bytes"
const K_SHA: String = "body_sha256"
const P_TICK: String = "tick"
const P_APP: String = "app_version"
const P_BYTES: String = "bytes"
const P_SHA: String = "body_sha256"
const FIXED_BYTES: int = 8  ## MAGIC and the header size.

## A test seam: where the refusal line goes instead of push_warning (unset: push_warning), so a
## test that expects a refusal does not trip the runner's warning check.
static var warning_sink: Callable = Callable()


## Where the file lives: beside the save file, so a test pointed at a temp save file never reaches
## the device's `user://`.
static func path() -> String:
	return SaveService.path().get_base_dir().path_join(FILE_NAME)


## `application/config/version`, the build the file is tied to.
static func app_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Whether a resume file is on disk and the pointer in section `match` names it. A cheap check for
## the main menu: the full validation (format, hash, build, data) is `read`'s.
static func has_file() -> bool:
	var pointer: Dictionary = SaveService.get_section(SECTION)
	return pointer.has(P_SHA) and FileAccess.file_exists(path())


## Writes the file for `runner`'s running match, after the AI and the tick job are idle
## (`wait_idle`). Nothing is written, and an existing file stays, when the runner or the setup is
## null or has no match (ERR_UNCONFIGURED) or a job does not finish (ERR_TIMEOUT). A match that has
## ended, or a lesson, is not resumable: the file is deleted and ERR_UNAVAILABLE comes back.
static func write_from(runner: MatchRunner, setup: MatchSetup) -> Error:
	if runner == null or setup == null:
		return ERR_UNCONFIGURED
	if setup.lesson_id != &"":
		delete()
		return ERR_UNAVAILABLE
	if not runner.wait_idle():
		_warn("ResumeStore: the match did not go idle; no resume file written")
		return ERR_TIMEOUT
	var world: World = runner.world
	var replay: Replay = runner.replay
	if world == null or replay == null:
		return ERR_UNCONFIGURED
	if runner.snapshot != null and runner.snapshot.match_end_tick > 0:
		delete()
		return ERR_UNAVAILABLE
	return write(setup, replay, world.tick, world.defs_hash())


## Writes `setup`, `replay` (the log of the match up to `tick`, the World's tick) and the pointer.
## Temp file, read back and compared, then renamed over the old file: a kill at any point leaves
## the old file or the new one, never a torn one. The pointer is written last.
static func write(setup: MatchSetup, replay: Replay, tick: int, defs_hash: int) -> Error:
	var bytes: PackedByteArray = encode(setup, replay, tick, defs_hash, app_version())
	if bytes.is_empty():
		return ERR_INVALID_DATA
	var target: String = path()
	var tmp: String = target + ".tmp"
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_bytes(tmp) != bytes:
		DirAccess.remove_absolute(tmp)
		return write_error if write_error != OK else ERR_FILE_CORRUPT
	var renamed: Error = DirAccess.rename_absolute(tmp, target)
	if renamed != OK and FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)  # A platform where rename does not replace.
		renamed = DirAccess.rename_absolute(tmp, target)
	if renamed != OK:
		DirAccess.remove_absolute(tmp)
		return renamed
	var pointer: Dictionary = {
		P_TICK: tick,
		P_APP: app_version(),
		P_BYTES: bytes.size(),
		P_SHA: str(_header_of(bytes).get(K_SHA, "")),
	}
	if not SaveService.set_section(SECTION, pointer):
		return ERR_INVALID_DATA
	return SaveService.flush()


## The file's bytes for these inputs, with `version` as the build; empty when an input is unusable
## (a null, a negative tick). Public so a test can write a file as another build would.
static func encode(
	setup: MatchSetup, replay: Replay, tick: int, defs_hash: int, version: String
) -> PackedByteArray:
	if setup == null or replay == null or tick < 0:
		return PackedByteArray()
	var raw: PackedByteArray = replay.to_bytes()
	var body: PackedByteArray = raw.compress(COMPRESSION)
	var seat: int = setup.local_seat
	var scenario: ScenarioDef = setup.scenario()
	if seat == 0 and scenario != null:
		seat = scenario.local_player
	var header: Dictionary = {
		K_FORMAT: FORMAT,
		K_APP: version,
		K_DEFS: str(defs_hash),
		K_TICK: tick,
		K_PLAYER: seat,
		K_SETUP: setup.to_dict(),
		K_PACKED: body.size(),
		K_RAW: raw.size(),
		K_SHA: _sha(body),
	}
	var text: PackedByteArray = JSON.stringify(header).to_utf8_buffer()
	var out: PackedByteArray = MAGIC.duplicate()
	out.resize(FIXED_BYTES)
	out.encode_u32(MAGIC.size(), text.size())
	out.append_array(text)
	out.append_array(body)
	return out


## The valid file's content, or null. Any refusal (a cut or damaged file, another format, another
## build, a defs_hash other than `defs_hash` when that is not `ANY_DEFS_HASH`, a malformed setup or
## log, a log that is not the setup's match, a lesson) deletes the file and its pointer and logs
## one warning line. Null without a deletion when there is no file.
static func read(defs_hash: int = ANY_DEFS_HASH) -> ResumeData:
	if not FileAccess.file_exists(path()):
		return null
	var data: ResumeData = decode(FileAccess.get_file_as_bytes(path()), app_version(), defs_hash)
	if data == null:
		delete()
	return data


## `read` without the file: the content of `bytes` for the build `version`, or null.
static func decode(bytes: PackedByteArray, version: String, defs_hash: int) -> ResumeData:
	var header: Dictionary = _header_of(bytes)
	var problem: String = _header_problem(header, version, defs_hash)
	if problem == "":
		var data: ResumeData = _body_data(header, bytes.slice(FIXED_BYTES + _header_size(bytes)))
		if data != null:
			return data
		problem = "the log, the setup or the body is malformed"
	_warn("ResumeStore: resume file refused (%s)" % problem)
	return null


## Removes the file, its temp file and the pointer. Safe when there is nothing.
static func delete() -> void:
	for file_path: String in [path(), path() + ".tmp"]:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)
	if not SaveService.get_section(SECTION).is_empty():
		SaveService.set_section(SECTION, {})
		SaveService.flush()


static func _warn(text: String) -> void:
	if warning_sink.is_valid():
		warning_sink.call(text)
	else:
		push_warning(text)


static func _sha(bytes: PackedByteArray) -> String:
	var context: HashingContext = HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _header_size(bytes: PackedByteArray) -> int:
	return int(bytes.decode_u32(MAGIC.size()))


## The header dictionary, or {} when the bytes are not a file of this layout.
static func _header_of(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < FIXED_BYTES or bytes.slice(0, MAGIC.size()) != MAGIC:
		return {}
	var size: int = _header_size(bytes)
	if size <= 0 or size > MAX_HEADER_BYTES or bytes.size() < FIXED_BYTES + size:
		return {}
	var text: String = bytes.slice(FIXED_BYTES, FIXED_BYTES + size).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func _header_problem(header: Dictionary, version: String, defs_hash: int) -> String:
	if header.is_empty():
		return "not a resume file"
	for key: String in [K_FORMAT, K_APP, K_DEFS, K_TICK, K_PLAYER, K_SETUP, K_PACKED, K_RAW, K_SHA]:
		if not header.has(key):
			return "missing " + key
	var problem: String = ""
	if not _whole(header[K_FORMAT]) or int(header[K_FORMAT]) != FORMAT:
		problem = "another file format"
	elif not (header[K_APP] is String) or header[K_APP] != version:
		problem = "another app version"
	elif not (header[K_DEFS] is String) or not (header[K_DEFS] as String).is_valid_int():
		problem = "bad defs hash"
	elif defs_hash != ANY_DEFS_HASH and int(header[K_DEFS] as String) != defs_hash:
		problem = "the data changed"
	elif not (header[K_SHA] is String):
		problem = "bad body hash"
	for key: String in [K_TICK, K_PLAYER, K_PACKED, K_RAW]:
		if problem == "" and (not _whole(header[key]) or int(header[key]) < 0):
			problem = "bad " + key
	if problem == "" and int(header[K_RAW]) > MAX_BODY_BYTES:
		problem = "body too large"
	return problem


static func _whole(value: Variant) -> bool:
	return (value is int) or (value is float and is_finite(value) and value == floorf(value))


static func _body_data(header: Dictionary, body: PackedByteArray) -> ResumeData:
	if body.size() != int(header[K_PACKED]) or _sha(body) != header[K_SHA]:
		return null
	var setup: MatchSetup = MatchSetup.from_dict(header[K_SETUP])
	var raw_size: int = int(header[K_RAW])
	var raw: PackedByteArray = body.decompress(raw_size, COMPRESSION)
	var replay: Replay = Replay.from_bytes(raw) if raw.size() == raw_size else null
	if setup == null or replay == null or setup.lesson_id != &"":
		return null
	var defs: int = int(header[K_DEFS] as String)
	var tick: int = int(header[K_TICK])
	var last_checkpoint: int = 0
	if not replay.checkpoint_ticks.is_empty():
		last_checkpoint = replay.checkpoint_ticks[replay.checkpoint_ticks.size() - 1]
	if replay.scenario_path != setup.scenario_path or replay.seed != setup.match_seed:
		return null
	if tick < last_checkpoint or replay.defs_hash != defs:
		return null
	var data: ResumeData = ResumeData.new()
	data.setup = setup
	data.replay = replay
	data.tick = tick
	data.local_player = int(header[K_PLAYER])
	data.app_version = header[K_APP]
	data.defs_hash = defs
	return data
