extends GdUnitTestSuite
## Follow-up #87: the required check "verify" of ci.yml is a gate over the "checks" job and the four
## shards of the "tests" job. Pins what a review can only see by eye: the gate's needs and its
## verdict, the matrix, and the two places where the split of the suite files is checked.

const WORKFLOW: String = "res://.github/workflows/ci.yml"
const CHECKS_JOB: String = "  checks:"
const TESTS_JOB: String = "  tests:"
const GATE_JOB: String = "  verify:"
const SHARD_VERIFY_STEP: String = "Verify (native build, import, this shard's suites, error scan)"
const SHARD_TEST_STEP: String = "Offline test of the test sharding"
const SHARD_COVER_STEP: String = "Check that the shards cover every suite file once"


## "verify", the required check, gates on the checks job and every tests shard, and the Android
## jobs keep needing it alone. A red or skipped needed job turns it red; a cancelled run skips it.
func test_verify_is_a_gate_over_the_checks_job_and_the_four_test_shards() -> void:
	var lines: PackedStringArray = _lines()
	var gate: PackedStringArray = _job(lines, GATE_JOB)
	assert_array(Array(gate)).contains(
		["    needs: [checks, tests]", "    if: ${{ !cancelled() }}", "    runs-on: ubuntu-24.04"]
	)
	var text: String = "\n".join(gate)
	assert_bool(text.contains("CHECKS: ${{ needs.checks.result }}")).is_true()
	assert_bool(text.contains("TESTS: ${{ needs.tests.result }}")).is_true()
	assert_bool(text.contains('[ "$CHECKS" = "success" ] && [ "$TESTS" = "success" ]')).is_true()
	var tests: PackedStringArray = _job(lines, TESTS_JOB)
	assert_array(Array(tests)).contains(["        shard: [1, 2, 3, 4]", "      fail-fast: false"])
	assert_array(Array(tests)).contains(["    name: tests (shard ${{ matrix.shard }} of 4)"])
	for job_name: String in ["  android-debug-apk:", "  android-aab:", "  android-perf-apk:"]:
		assert_array(Array(_job(lines, job_name))).contains(["    needs: verify"])


## The split is checked twice, offline on a fixture and on this tree in the checks job, and in every
## shard before it runs; the matrix width is read from the job, never typed twice there.
func test_the_test_sharding_is_checked_in_the_checks_job_and_in_every_shard() -> void:
	var lines: PackedStringArray = _lines()
	var checks: PackedStringArray = _job(lines, CHECKS_JOB)
	_assert_step(
		checks,
		SHARD_TEST_STEP,
		[
			"run: |",
			"bash scripts/ci/test-shard-tests.sh",
			"python3 -I scripts/ci/shard-tests.py --check 4",
		]
	)
	var tests: PackedStringArray = _job(lines, TESTS_JOB)
	_assert_step(
		tests,
		SHARD_COVER_STEP,
		[
			"env:",
			"SHARDS: ${{ strategy.job-total }}",
			'run: python3 -I scripts/ci/shard-tests.py --check "$SHARDS"',
		]
	)
	var cover: int = tests.find("      - name: " + SHARD_COVER_STEP)
	assert_int(cover).is_greater(-1)
	assert_int(tests.find("      - name: " + SHARD_VERIFY_STEP)).is_greater(cover)
	assert_bool(FileAccess.file_exists("res://scripts/ci/shard-tests.py")).is_true()


func _lines() -> PackedStringArray:
	var file: FileAccess = FileAccess.open(WORKFLOW, FileAccess.READ)
	assert_object(file).is_not_null()
	return file.get_as_text().split("\n")


func _job(lines: PackedStringArray, header: String) -> PackedStringArray:
	var start: int = lines.find(header)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < lines.size() and not (lines[end].begins_with("  ") and lines[end][2] != " "):
		end += 1
	return lines.slice(start + 1, end)


## A step is exactly its name line and these lines (comments and blank lines aside).
func _assert_step(job: PackedStringArray, step_name: String, body: Array) -> void:
	var start: int = job.find("      - name: " + step_name)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < job.size() and not job[end].begins_with("      - "):
		end += 1
	var step: Array = []
	for line: String in job.slice(start, end):
		if not line.strip_edges().is_empty() and not line.strip_edges().begins_with("#"):
			step.append(line.strip_edges())
	assert_array(step).contains_exactly(["- name: " + step_name] + body)
