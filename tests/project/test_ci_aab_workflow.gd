extends GdUnitTestSuite
## P410c (ADR 0040 sections 3 and 4): pins what a review of ci.yml can only see by eye in the job
## android-aab. It runs on pull requests only, after verify, reads no secret, uploads nothing and
## restores its caches without saving them. It makes its key in RUNNER_TEMP and deletes it in a step
## that always runs.

const JOB: String = "  android-aab:"
const ORDER: Array[String] = [
	"Install the Android NDK (install-ndk.sh)",
	"Build the Android library (arm64, template_release)",
	"Install Godot (editor, web templates and the Gradle build template)",
	"Export the Play bundle (generated key, nothing uploaded)",
	"Clean-tree check",
	"Delete the generated keystore",
]
const FORBIDDEN: Array[String] = [
	"secrets.", "upload-artifact", "contents: write", "continue-on-error", "actions/cache@"
]


func _job() -> PackedStringArray:
	var file: FileAccess = FileAccess.open("res://.github/workflows/ci.yml", FileAccess.READ)
	assert_object(file).is_not_null()
	var lines: PackedStringArray = file.get_as_text().split("\n")
	var start: int = lines.find(JOB)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < lines.size() and not (lines[end].begins_with("  ") and lines[end][2] != " "):
		end += 1
	return lines.slice(start + 1, end)


## A step without its blank and comment lines, stripped: its "- name:" line to the next step.
func _step(job: PackedStringArray, step_name: String) -> PackedStringArray:
	var start: int = job.find("      - name: " + step_name)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < job.size() and not job[end].begins_with("      - "):
		end += 1
	var out: PackedStringArray = PackedStringArray()
	for line: String in job.slice(start, end):
		if not line.strip_edges().is_empty() and not line.strip_edges().begins_with("#"):
			out.append(line.strip_edges())
	return out


func test_android_aab_job_is_pr_only_read_only_and_deletes_its_key() -> void:
	var job: PackedStringArray = _job()
	assert_str(job[0]).is_equal("    needs: verify")
	assert_str(job[1]).is_equal("    if: github.event_name == 'pull_request'")
	assert_array(Array(job)).contains(["      contents: read"])
	var text: String = "\n".join(job)
	for forbidden: String in FORBIDDEN:
		(
			assert_str(text)
			. override_failure_message("the android-aab job must not contain '%s'" % forbidden)
			. not_contains(forbidden)
		)
	var last: int = -1
	for step_name: String in ORDER:
		var at: int = job.find("      - name: " + step_name)
		assert_int(at).override_failure_message("step '%s'" % step_name).is_greater(last)
		last = at
	assert_array(Array(_step(job, ORDER[2]))).contains_exactly(
		["- name: " + ORDER[2], "run: bash scripts/ci/install-godot.sh --android-source"]
	)
	assert_array(Array(_step(job, ORDER[5]))).contains_exactly(
		["- name: " + ORDER[5], "if: always()", 'run: rm -f "$RUNNER_TEMP/aab-check.keystore"']
	)
	var export: String = "\n".join(_step(job, ORDER[3]))
	assert_str(export).contains('keystore="$RUNNER_TEMP/aab-check.keystore"')
	assert_str(export).contains("-storepass:env AAB_KEY_PASSWORD")
	assert_str(export).contains("bash scripts/export-android.sh --aab")
