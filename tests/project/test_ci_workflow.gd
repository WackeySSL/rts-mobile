extends GdUnitTestSuite
## Pins what a review of the workflows can only see by eye (ADR 0005 section 6): the one job with
## contents: write runs only on a push to main, and every action is pinned by commit SHA. A wider
## `if:` would let a pull request or a manual run replace the public pre-release.

const WORKFLOWS: String = "res://.github/workflows/"
const RELEASE_JOB: String = "  android-dev-release:"
const RELEASE_IF: String = (
	"    if: github.event_name == 'push' && github.ref == 'refs/heads/main'"
	+ " && !github.event.repository.fork"
)


func _lines(file_name: String) -> PackedStringArray:
	var file: FileAccess = FileAccess.open(WORKFLOWS + file_name, FileAccess.READ)
	assert_object(file).is_not_null()
	return file.get_as_text().split("\n")


func test_release_job_runs_only_on_a_push_to_main() -> void:
	var lines: PackedStringArray = _lines("ci.yml")
	var job: int = lines.find(RELEASE_JOB)
	assert_int(job).is_greater(-1)
	assert_str(lines[job + 1]).is_equal("    needs: android-debug-apk")
	assert_str(lines[job + 2]).is_equal(RELEASE_IF)


func test_only_the_release_job_can_write_contents() -> void:
	var lines: PackedStringArray = _lines("ci.yml")
	var job: int = lines.find(RELEASE_JOB)
	var writers: Array[int] = []
	for i: int in lines.size():
		if lines[i].strip_edges() == "contents: write":
			writers.append(i)
	assert_array(writers).has_size(1)
	assert_int(writers[0]).is_greater(job)


func test_every_action_is_pinned_by_sha() -> void:
	var pinned: RegEx = RegEx.create_from_string("^\\s*(- )?uses: \\S+@[0-9a-f]{40} # v\\d")
	var checked: int = 0
	for file_name: String in DirAccess.get_files_at(WORKFLOWS):
		if not file_name.ends_with(".yml"):
			continue
		for line: String in _lines(file_name):
			if line.strip_edges().begins_with("uses:") or line.strip_edges().begins_with("- uses:"):
				checked += 1
				(
					assert_object(pinned.search(line))
					. override_failure_message(
						"%s is not pinned by SHA with a version comment: %s" % [file_name, line]
					)
					. is_not_null()
				)
	assert_int(checked).is_greater(0)


## Spike P26n (never merged): the project holds native/probe_tick.gdextension, which Godot's first
## scan loads whatever the web preset excludes. A job that exports the web build from a fresh
## checkout must build the Linux library first, or the scan logs "Can't open dynamic library" and
## export-web.sh's error scan fails the job: the draft PR's Preview run would be red and publish
## nothing. ci.yml's verify job gets the library from the same script.
func test_preview_builds_the_native_library_before_the_web_export() -> void:
	var lines: PackedStringArray = _lines("preview.yml")
	var build: int = -1
	var export: int = -1
	for i: int in lines.size():
		var text: String = lines[i].strip_edges()
		if text == "run: bash scripts/build-native.sh":
			build = i
		elif text == "bash scripts/export-web.sh":
			export = i
	assert_int(build).override_failure_message("preview.yml never runs build-native.sh").is_greater(
		-1
	)
	assert_int(export).override_failure_message("preview.yml never runs export-web.sh").is_greater(
		-1
	)
	assert_int(build).override_failure_message("the library is built after the export").is_less(
		export
	)


## build-native.sh refuses any other scons, so the version that preview.yml installs is the one it
## names.
func test_preview_installs_the_scons_that_build_native_requires() -> void:
	var wanted: RegEx = RegEx.create_from_string('(?m)^SCONS_VERSION="([0-9.]+)"$')
	var script: FileAccess = FileAccess.open("res://scripts/build-native.sh", FileAccess.READ)
	assert_object(script).is_not_null()
	var found: RegExMatch = wanted.search(script.get_as_text())
	assert_object(found).is_not_null()
	var version: String = found.get_string(1)
	var lines: PackedStringArray = _lines("preview.yml")
	assert_bool(lines.has('  SCONS_VERSION: "%s"' % version)).is_true()
	assert_bool(lines.has('        run: pipx install "scons==${SCONS_VERSION}"')).is_true()
