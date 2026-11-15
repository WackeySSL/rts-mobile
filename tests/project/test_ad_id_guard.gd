extends GdUnitTestSuite
## The ad ID guard (ADR 0039 section 9, P420): no real AdMob ID in any git-tracked text file. A real
## ID ("ca-app-pub-" or "pub-" plus 16 digits) may reach a build only from the git-ignored
## `ad_ids.cfg` that a workflow writes (ADR 0040 section 7). Only Google's test publisher and the
## all-zero placeholder are allowed in the tree.
##
## The file list is `git ls-files`, run from the project root, so it is exactly the tracked files
## and no ignore rule is re-implemented here. A missing git or a failing command fails the suite:
## a guard that cannot list the tree must not pass. The list is read as lines, not with `-z`:
## `OS.execute` returns the output as one String, which cannot hold NUL bytes, so a NUL-separated
## list would arrive truncated (a first try listed far too few files).
##
## Known gaps, by design: an ID split by string concatenation in code, text in UTF-16, binary files
## (P414's AAB check covers the export) and untracked files (the ignore rule below keeps
## `ad_ids.cfg` out of git).

## Google's published test publisher, see https://developers.google.com/admob/android/test-ads.
## Allowed by publisher prefix only (the exact test unit values on that page could not be fetched
## from the session that wrote this). That is safe: this publisher never serves real ads, so no
## suffix under it can earn or cost anything.
const TEST_PUBLISHER: String = "3940256099942544"
## The placeholder that docs may use.
const PLACEHOLDER_PUBLISHER: String = "0000000000000000"
const ALLOWED_PUBLISHERS: Array[String] = [TEST_PUBLISHER, PLACEHOLDER_PUBLISHER]
## "ca-app-pub-" and bare "pub-" IDs, App ID ("~") and unit ID ("/") alike: the publisher decides.
## Case-insensitive, and 16 or more digits, so a longer run is never mistaken for an allowed one:
## only exact equality with an allowed publisher passes.
const ID_PATTERN: String = r"(?i)(?<![A-Za-z0-9])(?:ca-app-)?pub-(\d{16,})"
const IDS_FILE: String = "ad_ids.cfg"
## Fewer tracked files than this means the listing broke, not that the repository shrank.
const MIN_TRACKED_FILES: int = 1000
## Files whose text was actually read and scanned (the rest are binary or skipped).
const MIN_SCANNED_FILES: int = 1000
## Binary kinds, never read (the NUL check in `scan` catches any other binary file).
const BINARY_EXTENSIONS: Array[String] = [
	"png",
	"jpg",
	"jpeg",
	"webp",
	"ogg",
	"wav",
	"mp3",
	"ttf",
	"otf",
	"woff",
	"woff2",
	"apk",
	"aab",
	"jar",
	"so",
	"dll",
	"dylib",
	"a",
	"o",
	"zip",
	"gz",
	"keystore",
	"jks",
	"ico",
	"pck"
]

static var _pattern: RegEx

## Keeps a scratch directory alive for the test that made it.
var _scratch: DirAccess


## Every ID in `text` whose publisher is not allowed, as "N: <id>" with N the 1-based line.
static func find_ids(text: String) -> Array[String]:
	var hits: Array[String] = []
	if not text.to_lower().contains("pub-"):
		return hits
	if _pattern == null:
		_pattern = RegEx.create_from_string(ID_PATTERN)
	for found: RegExMatch in _pattern.search_all(text):
		if ALLOWED_PUBLISHERS.has(found.get_string(1)):
			continue
		var line: int = text.substr(0, found.get_start()).count("\n") + 1
		hits.append("%d: %s" % [line, found.get_string()])
	return hits


## The offenders among `paths` (relative to the absolute directory `root`), as "path:N: <id>", or
## "path: unreadable (<error>)" for a file that cannot be opened. `stats["scanned"]` counts the
## files whose text was read.
static func scan(root: String, paths: Array[String], stats: Dictionary = {}) -> Array[String]:
	var offenders: Array[String] = []
	var scanned: int = 0
	for path: String in paths:
		if BINARY_EXTENSIONS.has(path.get_extension().to_lower()):
			continue
		var file: FileAccess = FileAccess.open(root.path_join(path), FileAccess.READ)
		if file == null:
			offenders.append(
				"%s: unreadable (%s)" % [path, error_string(FileAccess.get_open_error())]
			)
			continue
		var bytes: PackedByteArray = file.get_buffer(file.get_length())
		file.close()
		if bytes.has(0):
			continue  # A binary file.
		scanned += 1
		# ASCII decoding never complains about stray bytes, unlike UTF-8 (verify.sh fails on that).
		for hit: String in find_ids(bytes.get_string_from_ascii()):
			offenders.append("%s:%s" % [path, hit])
	stats["scanned"] = scanned
	return offenders


func test_no_tracked_text_file_holds_a_real_ad_id() -> void:
	var root: String = ProjectSettings.globalize_path("res://")
	var listed: Array = _git(root, ["-c", "core.quotepath=off", "ls-files"])
	if listed[0] != 0:
		fail("git ls-files failed: " + str(listed[1]))
		return
	var files: Array[String] = []
	for path: String in (listed[1] as String).split("\n", false):
		files.append(path)
	(
		assert_int(files.size())
		. override_failure_message(
			"git ls-files listed %d files, fewer than %d" % [files.size(), MIN_TRACKED_FILES]
		)
		. is_greater_equal(MIN_TRACKED_FILES)
	)
	var stats: Dictionary = {}
	var offenders: Array[String] = scan(root, files, stats)
	(
		assert_array(offenders)
		. override_failure_message(
			(
				"a real-looking AdMob ID is tracked (only Google's test publisher is allowed):\n"
				+ "\n".join(offenders)
			)
		)
		. is_empty()
	)
	(
		assert_int(stats["scanned"] as int)
		. override_failure_message(
			"only %d text files were scanned, fewer than %d" % [stats["scanned"], MIN_SCANNED_FILES]
		)
		. is_greater_equal(MIN_SCANNED_FILES)
	)


func test_the_guard_bites_on_a_planted_real_looking_id() -> void:
	# Built at run time, so this file holds no such ID itself and the tree scan stays green.
	var prefix: String = "ca-app-" + "pub-"
	var publisher: String = "1234567890" + "123456"
	var app_id: String = prefix + publisher + "~" + "1234567890"
	var unit_id: String = prefix + publisher + "/" + "1234567890"
	var bare: String = "pub" + "-" + publisher
	var text: String = 'ok\nkey = "%s"\nunit: %s\nx %s y' % [app_id, unit_id, bare]
	assert_array(find_ids(text)).contains_exactly(
		["2: %s%s" % [prefix, publisher], "3: %s%s" % [prefix, publisher], "4: " + bare]
	)


func test_scan_reports_a_planted_id_in_a_scratch_file_and_nothing_else() -> void:
	_scratch = DirAccess.create_temp("ad_id_guard_")
	var dir: String = _scratch.get_current_dir()
	var planted: String = "ca-app-" + "pub-" + "1234567890" + "123456" + "/" + "1234567890"
	_write(dir.path_join("planted.cfg"), '[ads]\nunit = "%s"\n' % planted)
	_write(
		dir.path_join("clean.md"),
		"ca-app-" + "pub-" + TEST_PUBLISHER + "~3347511713 and pub-" + PLACEHOLDER_PUBLISHER + "\n"
	)
	var stats: Dictionary = {}
	var paths: Array[String] = ["planted.cfg", "clean.md"]
	assert_array(scan(dir, paths, stats)).contains_exactly(
		["planted.cfg:2: " + planted.get_slice("/", 0)]
	)
	assert_int(stats["scanned"] as int).is_equal(2)


func test_an_unreadable_file_is_an_offender() -> void:
	_scratch = DirAccess.create_temp("ad_id_guard_")
	var paths: Array[String] = ["missing.txt"]
	var offenders: Array[String] = scan(_scratch.get_current_dir(), paths)
	assert_array(offenders).has_size(1)
	assert_str(offenders[0]).starts_with("missing.txt: unreadable (")


func test_the_guard_allows_google_test_ids_and_the_placeholder() -> void:
	var prefix: String = "ca-app-" + "pub-"
	var text: String = (
		"%s%s~3347511713\n%s%s/6300978111\npub-%s\n"
		% [prefix, TEST_PUBLISHER, prefix, TEST_PUBLISHER, PLACEHOLDER_PUBLISHER]
	)
	assert_array(find_ids(text)).is_empty()


func test_only_exact_allowed_publishers_pass_and_case_is_ignored() -> void:
	var longer: String = "pub" + "-" + TEST_PUBLISHER + "7"
	var upper: String = "CA-APP-" + "PUB-" + "1234567890" + "123456"
	assert_array(find_ids(longer + "\n" + upper)).has_size(2)


func test_ids_with_fewer_than_sixteen_digits_or_a_glued_prefix_are_not_publishers() -> void:
	assert_array(find_ids("ca-app-" + "pub-12345/67890")).is_empty()
	assert_array(find_ids("xpub" + "-" + "1234567890" + "123456")).is_empty()


func test_the_ids_file_is_ignored_and_not_tracked() -> void:
	var root: String = ProjectSettings.globalize_path("res://")
	var ignored: Array = _git(root, ["check-ignore", "-q", IDS_FILE])
	(
		assert_int(ignored[0] as int)
		. override_failure_message(
			".gitignore must ignore %s (git check-ignore exit code)" % IDS_FILE
		)
		. is_equal(0)
	)
	# Not tracked, so a workflow's own write of the file never turns this red.
	var tracked: Array = _git(root, ["ls-files", "--error-unmatch", IDS_FILE])
	(
		assert_int(tracked[0] as int)
		. override_failure_message(
			"%s is tracked: only a workflow writes it, into the export" % IDS_FILE
		)
		. is_not_equal(0)
	)


## `git -C root <args>`: [exit code, stdout]. stderr is not read.
func _git(root: String, args: Array[String]) -> Array:
	var output: Array = []
	var full: Array[String] = ["-C", root]
	full.append_array(args)
	var code: int = OS.execute("git", full, output, false)
	return [code, "" if output.is_empty() else output[0]]


func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(text)
	file.close()
