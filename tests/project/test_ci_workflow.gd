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
const ANDROID_JOB: String = "  android-debug-apk:"
const NOTICE_TEST_STEP: String = "      - name: Offline test of the export licence notices"
const NOTICE_TEST_RUN: String = "        run: bash scripts/ci/test-export-notices.sh"
const EXPORT_STEP: String = "      - name: Export debug APK"


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


## P26l: both export scripts append the LLVM libc++ licence to their THIRD_PARTY_LICENSES.txt, and
## this offline test is what fails when one of them stops (ADR 0005 section 5). It has to run in
## the Android job, before the job exports the APK, or a regression would reach the release.
func test_android_job_runs_the_offline_licence_notice_test_before_the_export() -> void:
	var lines: PackedStringArray = _lines("ci.yml")
	var job: int = lines.find(ANDROID_JOB)
	var release: int = lines.find(RELEASE_JOB)
	var step: int = lines.find(NOTICE_TEST_STEP)
	var export_step: int = lines.find(EXPORT_STEP)
	assert_int(job).is_greater(-1)
	assert_int(step).is_greater(job)
	assert_str(lines[step + 1]).is_equal(NOTICE_TEST_RUN)
	# The run line ends the step (a blank line follows). A modifier after it, such as
	# `continue-on-error: true` or `if: false`, would neuter the test and must fail here.
	assert_str(lines[step + 2].strip_edges()).is_empty()
	assert_int(export_step).is_greater(step)
	assert_int(export_step).is_less(release)


## ADR 0013 section 8: SCons and clang-format are pinned in places that cannot share a file (the
## pasted setup script, the session hook, the workflow, the README). Each must equal its owner:
## build-native.sh for SCons, scripts/ci/check-cpp-format.sh for clang-format.
func test_native_tool_pins_agree_everywhere() -> void:
	var scons: String = _pin("res://scripts/build-native.sh", "SCONS_VERSION")
	var clang: String = _pin("res://scripts/ci/check-cpp-format.sh", "CLANG_FORMAT_VERSION")
	assert_str(scons).is_not_empty()
	assert_str(clang).is_not_empty()
	for path: String in [
		"res://scripts/cloud/setup.sh",
		"res://scripts/hooks/session-start.sh",
		"res://.github/workflows/ci.yml",
	]:
		assert_str(_pin(path, "SCONS_VERSION")).is_equal(scons)
		assert_str(_pin(path, "CLANG_FORMAT_VERSION")).is_equal(clang)
	var readme: String = FileAccess.get_file_as_string("res://README.md")
	assert_bool(readme.contains("scons==" + scons)).is_true()
	assert_bool(readme.contains("clang-format==" + clang)).is_true()


## The offline test of the native scripts runs in the verify job, the required check.
func test_verify_job_runs_the_native_script_test() -> void:
	var lines: PackedStringArray = _lines("ci.yml")
	var step: int = lines.find("      - name: Offline test of the native scripts")
	assert_int(step).is_greater(lines.find("  verify:"))
	assert_int(step).is_less(lines.find(ANDROID_JOB))
	assert_str(lines[step + 1]).is_equal("        run: bash scripts/ci/test-native-scripts.sh")
	assert_str(lines[step + 2].strip_edges()).is_empty()


func _pin(path: String, pin_name: String) -> String:
	var rx: RegEx = RegEx.create_from_string("(?m)^\\s*" + pin_name + '[=:]\\s*"([^"]+)"')
	var hit: RegExMatch = rx.search(FileAccess.get_file_as_string(path))
	return hit.get_string(1) if hit != null else ""
