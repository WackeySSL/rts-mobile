extends GdUnitTestSuite
## Plan P508 (ADR 0041 section 7, ADR 0046): the asset scan for everything under assets/audio/.
## Every file has a row in assets/CREDITS.md with a source and an allowed licence (CC0 1.0, CC BY
## 3.0 or 4.0, or "This repository (tools/sfxgen)" with "All rights reserved (AppCode ApS)"); sound
## effects are mono 16-bit WAV at 22,050 or 44,100 Hz that never reach full scale, music is Ogg
## Vorbis; all audio together stays inside the 12 MB budget; no stream a cue names is missing and
## no file is left unused. The scan proves a row exists and is allowed; it cannot prove it true.

const AUDIO: String = "res://assets/audio"
const CREDITS: String = "res://assets/CREDITS.md"
const CUES: String = "res://data/audio_cues.tres"
const BUDGET_BYTES: int = 12 * 1024 * 1024
const RATES: Array[int] = [22050, 44100]
## Files Godot or the repository keeps beside the audio that are not audio.
const SKIPPED_SUFFIXES: Array[String] = [".import", ".uid", ".gitkeep", ".md", ".txt"]


func test_every_audio_file_has_a_credits_row() -> void:
	var rows: Array[PackedStringArray] = _credit_rows()
	for file: String in _audio_files():
		var row: PackedStringArray = _row_for(rows, file)
		assert_int(row.size()).override_failure_message("no CREDITS row for " + file).is_greater(0)


func test_every_row_has_an_allowed_licence_and_a_source() -> void:
	var rows: Array[PackedStringArray] = _credit_rows()
	for file: String in _audio_files():
		var row: PackedStringArray = _row_for(rows, file)
		if row.is_empty():
			continue  # reported by the test above
		var author: String = row[1].strip_edges()
		var source: String = row[2].strip_edges()
		var licence: String = row[3].strip_edges()
		assert_str(author).override_failure_message("author missing: " + file).is_not_empty()
		if _is_generated(source):
			(
				assert_str(licence)
				. override_failure_message("generated audio must be all rights reserved: " + file)
				. is_equal("All rights reserved (AppCode ApS)")
			)
		else:
			(
				assert_str(source)
				. override_failure_message("source must be the file's own page URL: " + file)
				. starts_with("https://")
			)
			(
				assert_bool(_allowed_licence(licence))
				. override_failure_message("licence not allowed for " + file + ": " + licence)
				. is_true()
			)


func test_formats_follow_the_folder() -> void:
	for file: String in _audio_files():
		var extension: String = file.get_extension().to_lower()
		if file.begins_with(AUDIO + "/sfx/"):
			assert_str(extension).override_failure_message("sfx must be WAV: " + file).is_equal(
				"wav"
			)
		elif file.begins_with(AUDIO + "/music/"):
			assert_str(extension).override_failure_message("music must be OGG: " + file).is_equal(
				"ogg"
			)
		else:
			fail("audio outside assets/audio/sfx and assets/audio/music: " + file)


func test_sfx_wav_files_are_mono_16_bit_at_an_allowed_rate_below_full_scale() -> void:
	for file: String in _audio_files():
		if file.get_extension().to_lower() != "wav":
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(file)
		var info: Dictionary = _wav_info(bytes)
		(
			assert_bool(info.has("error"))
			. override_failure_message(file + ": " + str(info.get("error", "")))
			. is_false()
		)
		if info.has("error"):
			continue
		assert_int(int(info["format"])).override_failure_message(file + " not PCM").is_equal(1)
		assert_int(int(info["channels"])).override_failure_message(file + " not mono").is_equal(1)
		assert_int(int(info["bits"])).override_failure_message(file + " not 16 bit").is_equal(16)
		assert_array(RATES).override_failure_message(file + " rate " + str(info["rate"])).contains(
			[int(info["rate"])]
		)
		assert_int(int(info["data_size"])).override_failure_message(file + " empty").is_greater(0)
		var peak: int = _peak(bytes, int(info["data_start"]), int(info["data_size"]))
		assert_int(peak).override_failure_message(file + " reaches full scale").is_less(32767)


func test_all_audio_stays_inside_the_budget() -> void:
	var total: int = 0
	for file: String in _audio_files():
		total += FileAccess.get_file_as_bytes(file).size()
	assert_int(total).override_failure_message("audio is %d bytes" % total).is_less_equal(
		BUDGET_BYTES
	)


func test_every_stream_a_cue_names_exists() -> void:
	for path: String in _cue_audio_paths():
		(
			assert_bool(FileAccess.file_exists(path))
			. override_failure_message("missing stream " + path)
			. is_true()
		)


func test_no_audio_file_is_unused() -> void:
	var text: String = _reference_text()
	for file: String in _audio_files():
		(
			assert_bool(text.contains(file))
			. override_failure_message("unused audio file " + file)
			. is_true()
		)


## The credit rows: the cells of each table line of assets/CREDITS.md (at least four).
func _credit_rows() -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	for line: String in FileAccess.get_file_as_string(CREDITS).split("\n"):
		if not line.begins_with("| "):
			continue
		var cells: PackedStringArray = line.trim_prefix("| ").split(" | ")
		if cells.size() >= 4:
			rows.append(cells)
	return rows


## The row that names `file`: its first cell holds the path in backticks, or a folder path ending in
## a slash that the file lies under.
func _row_for(rows: Array[PackedStringArray], file: String) -> PackedStringArray:
	var relative: String = file.trim_prefix("res://")
	for row: PackedStringArray in rows:
		if row[0].contains("`" + relative + "`"):
			return row
	for row: PackedStringArray in rows:
		for part: String in row[0].split("`"):
			if (
				part.begins_with("assets/audio/")
				and part.ends_with("/")
				and relative.begins_with(part)
			):
				return row
	return PackedStringArray()


func _is_generated(source: String) -> bool:
	return source.to_lower().begins_with("this repository (tools/sfxgen)")


func _allowed_licence(licence: String) -> bool:
	var plain: String = licence.replace("-", " ").to_upper()
	return (
		plain.begins_with("CC0 1.0")
		or plain.begins_with("CC BY 3.0")
		or plain.begins_with("CC BY 4.0")
	)


func _audio_files() -> Array[String]:
	var found: Array[String] = []
	_walk(AUDIO, found)
	found.sort()
	return found


func _walk(folder: String, found: Array[String]) -> void:
	for file: String in DirAccess.get_files_at(folder):
		var skip: bool = false
		for suffix: String in SKIPPED_SUFFIXES:
			if file.ends_with(suffix):
				skip = true
		if not skip:
			found.append(folder + "/" + file)
	for sub: String in DirAccess.get_directories_at(folder):
		_walk(folder + "/" + sub, found)


## Every res://assets/audio path the cue table names as an external resource.
func _cue_audio_paths() -> Array[String]:
	var paths: Array[String] = []
	var expression: RegEx = RegEx.create_from_string('path="(res://assets/audio/[^"]+)"')
	for hit: RegExMatch in expression.search_all(FileAccess.get_file_as_string(CUES)):
		paths.append(hit.get_string(1))
	return paths


## The text a file's path may appear in: the data resources, the audio code and the scenes.
func _reference_text() -> String:
	var text: String = ""
	for folder: String in ["res://data", "res://game/view/audio", "res://scenes"]:
		text += _text_below(folder)
	return text


func _text_below(folder: String) -> String:
	var text: String = ""
	for file: String in DirAccess.get_files_at(folder):
		if file.get_extension() in ["tres", "gd", "tscn"]:
			text += FileAccess.get_file_as_string(folder + "/" + file)
	for sub: String in DirAccess.get_directories_at(folder):
		text += _text_below(folder + "/" + sub)
	return text


## The fmt and data chunks of a RIFF WAVE file, or {"error": ...}.
func _wav_info(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {"error": "not a RIFF file"}
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {"error": "not a WAVE file"}
	var info: Dictionary = {}
	var at: int = 12
	while at + 8 <= bytes.size():
		var tag: String = bytes.slice(at, at + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(at + 4)
		if tag == "fmt " and at + 24 <= bytes.size():
			info["format"] = bytes.decode_u16(at + 8)
			info["channels"] = bytes.decode_u16(at + 10)
			info["rate"] = bytes.decode_u32(at + 12)
			info["bits"] = bytes.decode_u16(at + 22)
		elif tag == "data":
			info["data_start"] = at + 8
			info["data_size"] = mini(size, bytes.size() - at - 8)
			break
		at += 8 + size + (size & 1)
	if not (info.has("format") and info.has("data_start")):
		return {"error": "no fmt or data chunk"}
	return info


func _peak(bytes: PackedByteArray, start: int, size: int) -> int:
	var peak: int = 0
	var at: int = start
	while at + 2 <= start + size:
		peak = maxi(peak, absi(bytes.decode_s16(at)))
		at += 2
	return peak
