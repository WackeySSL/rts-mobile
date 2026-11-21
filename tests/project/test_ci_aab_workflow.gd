extends GdUnitTestSuite
## P410c (ADR 0040 sections 3 and 4): pins what a review of ci.yml can only see by eye in the job
## android-aab. It runs on pull requests and on a push to main, after verify, reads no secret and
## uploads nothing. It restores its caches without saving them, except the Gradle cache, which
## only a push to main saves (a PR sees only main's caches). It makes its key in RUNNER_TEMP and
## deletes it in a step that always runs.

const JOB: String = "  android-aab:"
const ORDER: Array[String] = [
	"Install the Android NDK (install-ndk.sh)",
	"Build the Android library (arm64, template_release)",
	"Install Godot (editor, web templates and the Gradle build template)",
	"Cache Gradle",
	"Export the Play bundle (generated key, nothing uploaded)",
	"Save the Gradle cache (main only)",
	"Clean-tree check",
	"Delete the generated keystore",
]
const AAB_IF: String = (
	"    if: github.event_name == 'pull_request' || "
	+ "(github.event_name == 'push' && github.ref == 'refs/heads/main')"
)
const SAVE_IF: String = (
	"if: success() && github.event_name == 'push' && "
	+ "steps.gradle-cache.outputs.cache-hit != 'true'"
)
const FORBIDDEN: Array[String] = [
	"secrets.",
	"upload-artifact",
	"contents: write",
	"continue-on-error",
	"actions/cache@",
	"pull_request_target"
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


func test_android_aab_job_is_read_only_and_deletes_its_key() -> void:
	var job: PackedStringArray = _job()
	assert_str(job[0]).is_equal("    needs: verify")
	assert_str(job[1]).is_equal(AAB_IF)
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
	assert_array(Array(_step(job, ORDER[7]))).contains_exactly(
		["- name: " + ORDER[7], "if: always()", 'run: rm -f "$RUNNER_TEMP/aab-check.keystore"']
	)
	var export: String = "\n".join(_step(job, ORDER[4]))
	assert_str(export).contains('keystore="$RUNNER_TEMP/aab-check.keystore"')
	assert_str(export).contains("-storepass:env AAB_KEY_PASSWORD")
	assert_str(export).contains("bash scripts/export-android.sh --aab")


## A PR sees only the caches saved on main, and no other job runs a Gradle export, so this job must
## save the `gradle-` key on a push to main, under the very key its restore step reads, after the
## export and only when it succeeded. The restore also falls back to the key's prefix.
func test_gradle_cache_is_saved_on_main_under_the_key_the_restore_reads() -> void:
	var job: PackedStringArray = _job()
	var restore: PackedStringArray = _step(job, "Cache Gradle")
	var save: PackedStringArray = _step(job, "Save the Gradle cache (main only)")
	var restore_key: String = ""
	var save_key: String = ""
	for line: String in restore:
		if line.begins_with("key: "):
			restore_key = line
	for line: String in save:
		if line.begins_with("key: "):
			save_key = line
	assert_str(restore_key).starts_with("key: gradle-")
	assert_str(save_key).is_equal(restore_key)
	assert_str(restore[2]).starts_with(
		"uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9"
	)
	assert_str(save[2]).starts_with(
		"uses: actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9"
	)
	(
		assert_array(Array(save))
		. contains(
			[
				SAVE_IF,
				"~/.gradle/caches",
				"~/.gradle/wrapper",
			]
		)
	)
	assert_array(Array(restore)).contains(["id: gradle-cache", "gradle-${{ env.GODOT_VERSION }}-"])
	var text: String = "\n".join(save)
	for banned: String in ["keystore", "secrets.", "RUNNER_TEMP", "AAB_KEY"]:
		assert_str(text).not_contains(banned)
