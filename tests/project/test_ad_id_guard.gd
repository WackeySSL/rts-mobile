extends GdUnitTestSuite
## The ad ID guard (ADR 0039 section 9, P420): no real AdMob ID in any git-tracked text file. A real
## ID ("ca-app-pub-" or "pub-" plus 16 digits) may reach a build only from the git-ignored
## `ad_ids.cfg` that a workflow writes (ADR 0040 section 7). Only Google's test publisher and the
## all-zero placeholder are allowed in the tree.
##
## The file list is `git ls-files`, run from the project root, so it is exactly the tracked files
## and no ignore rule is re-implemented here. A missing git or a failing command fails the suite:
## a guard that cannot list the tree must not pass.

## Google's published test publisher, see https://developers.google.com/admob/android/test-ads.
## Allowed by publisher prefix only: the exact test unit values on that page could not be fetched
## from this session, so every ID under this publisher passes, whatever its suffix.
const TEST_PUBLISHER: String = "3940256099942544"
## The placeholder that docs may use.
const PLACEHOLDER_PUBLISHER: String = "0000000000000000"
const ALLOWED_PUBLISHERS: Array[String] = [TEST_PUBLISHER, PLACEHOLDER_PUBLISHER]
## "ca-app-pub-" and bare "pub-" IDs, App ID ("~") and unit ID ("/") alike: the publisher decides.
const ID_PATTERN: String = r"(?:ca-app-pub-|\bpub-)(\d{16})"
const IDS_FILE: String = "res://ad_ids.cfg"
const GITIGNORE: String = "res://.gitignore"
const IGNORE_LINES: Array[String] = ["ad_ids.cfg", "/ad_ids.cfg"]
## Binary kinds, never read (the NUL check below catches any other binary file).
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


## Every ID in `text` whose publisher is not allowed, as "line N: <id>".
static func find_ids(text: String) -> Array[String]:
	var hits: Array[String] = []
	var pattern: RegEx = RegEx.create_from_string(ID_PATTERN)
	var lines: PackedStringArray = text.split("\n")
	for index: int in lines.size():
		for found: RegExMatch in pattern.search_all(lines[index]):
			if not ALLOWED_PUBLISHERS.has(found.get_string(1)):
				hits.append("line %d: %s" % [index + 1, found.get_string()])
	return hits


func test_no_tracked_text_file_holds_a_real_ad_id() -> void:
	var files: Array[String] = _tracked_files()
	(
		assert_int(files.size())
		. override_failure_message("git ls-files listed too few files")
		. is_greater(500)
	)
	var root: String = ProjectSettings.globalize_path("res://")
	var offenders: Array[String] = []
	for path: String in files:
		if BINARY_EXTENSIONS.has(path.get_extension().to_lower()):
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(root.path_join(path))
		if bytes.has(0):
			continue  # A binary file.
		for hit: String in find_ids(bytes.get_string_from_utf8()):
			offenders.append("%s %s" % [path, hit])
	(
		assert_array(offenders)
		. override_failure_message(
			"a real-looking AdMob ID is tracked (only Google's test publisher is allowed)"
		)
		. is_empty()
	)


func test_the_guard_bites_on_a_planted_real_looking_id() -> void:
	# Built at run time, so this file holds no such ID itself and the tree scan stays green.
	var prefix: String = "ca-app-" + "pub-"
	var publisher: String = "1234567890" + "123456"
	var app_id: String = prefix + publisher + "~" + "1234567890"
	var unit_id: String = prefix + publisher + "/" + "1234567890"
	var bare: String = "pub" + "-" + publisher
	var text: String = 'ok\nkey = "%s"\nunit: %s\nx %s y' % [app_id, unit_id, bare]
	assert_array(find_ids(text)).is_equal(
		[
			"line 2: %s%s" % [prefix, publisher],
			"line 3: %s%s" % [prefix, publisher],
			"line 4: " + bare
		]
	)


func test_the_guard_allows_google_test_ids_and_the_placeholder() -> void:
	var prefix: String = "ca-app-" + "pub-"
	var text: String = (
		"%s%s~3347511713\n%s%s/6300978111\npub-%s\n"
		% [prefix, TEST_PUBLISHER, prefix, TEST_PUBLISHER, PLACEHOLDER_PUBLISHER]
	)
	assert_array(find_ids(text)).is_empty()


func test_ids_with_fewer_than_sixteen_digits_are_not_publishers() -> void:
	assert_array(find_ids("ca-app-" + "pub-12345/67890")).is_empty()


func test_the_ids_file_is_absent_and_ignored() -> void:
	(
		assert_bool(FileAccess.file_exists(IDS_FILE))
		. override_failure_message(
			"res://ad_ids.cfg is in the tree: only a workflow writes it, into the export"
		)
		. is_false()
	)
	var ignored: bool = false
	for line: String in FileAccess.get_file_as_string(GITIGNORE).split("\n"):
		if IGNORE_LINES.has(line.strip_edges()):
			ignored = true
	assert_bool(ignored).override_failure_message(".gitignore must ignore ad_ids.cfg").is_true()


## Paths relative to the project root, from `git ls-files`.
func _tracked_files() -> Array[String]:
	var root: String = ProjectSettings.globalize_path("res://")
	var output: Array = []
	var code: int = OS.execute(
		"git", ["-C", root, "-c", "core.quotepath=off", "ls-files"], output, true
	)
	assert_int(code).override_failure_message("git ls-files failed: " + str(output)).is_equal(0)
	var files: Array[String] = []
	if output.is_empty():
		return files
	for path: String in (output[0] as String).split("\n", false):
		files.append(path)
	return files
