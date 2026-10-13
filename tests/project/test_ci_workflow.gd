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
const CHECK_STEP: String = "Check the native suites ran (check-native-tests.sh)"
const CHECK_RUN: String = "run: bash scripts/ci/check-native-tests.sh"
const VERIFY_STEP: String = (
	"Verify (native build, format, lint, import, tests, " + "C++ format, sim smoke, error scan)"
)
const VERIFY_RUN: String = "run: bash scripts/verify.sh 2>&1 | tee " + '"$RUNNER_TEMP/verify.log"'
const INSTALL_STEP: String = "Install the native toolchain (SCons, %s, binutils)"
const KEY_STEP: String = "Read the native cache key"
## The key is assigned first so that a failing build-native.sh fails this step, not actions/cache.
const KEY_ASSIGN: String = 'key="$(bash scripts/build-native.sh%s --print-cache-key)"'
const KEY_ECHO: String = 'echo "key=$key" >> "$GITHUB_OUTPUT"'
const BUILD_STEP: String = "Build the library (clang, optimize=speed)"
const GATE_STEP: String = "Run the native suites (gdUnit4), when discovery finds one"
const GATE_RUN: String = (
	'if [ -n "$(bash scripts/ci/check-native-tests.sh --list)" ]; then'
	+ " bash scripts/run-tests.sh -a res://tests/sim/native; fi"
)
const CACHE_STEP: String = "Cache godot-cpp and the SCons object cache"
const CACHE_KEY: String = "key: ${{ steps.native-key.outputs.key }}"
## P55a, the Android job (ADR 0013 sections 8 and 10).
const NDK_STEP: String = "Install the Android NDK (install-ndk.sh)"
const NDK_RUN: String = "run: bash scripts/ci/install-ndk.sh"
const ANDROID_INSTALL_STEP: String = "Install the native toolchain (SCons, binutils)"
const ANDROID_INSTALL_RUN: Array[String] = [
	"run: |",
	'pipx install "scons==${SCONS_VERSION}"',
	"sudo apt-get install -y --no-install-recommends binutils",
]
## P55a2: the ELF checks of export-android.sh, tested offline with the NDK's llvm tools.
const ELF_STEP: String = "Offline test of the packed-library ELF checks"
const ELF_RUN: String = "run: bash scripts/ci/test-android-elf.sh"
const KEYS_STEP: String = "Read the native cache keys"
## One key line per library, printed for the flags of its build step.
const KEY_VAR: String = '%s="$(bash scripts/build-native.sh%s --print-cache-key)"'
const KEYS_OUT: String = (
	'{ echo "host=$host"; echo "android_debug=$android_debug";'
	+ ' echo "android_release=$android_release"; } >> "$GITHUB_OUTPUT"'
)
const ANDROID_FLAGS: String = " --platform android --arch arm64 --target template_"
## The fourth cache step of the job holds the Godot editor and templates, and nothing of the SDK.
const GODOT_CACHE_STEP: String = "Cache Godot editor and export templates (web and Android debug)"
const GODOT_CACHE_PATHS: Array[String] = [
	"~/.local/opt/godot-${{ env.GODOT_VERSION }}",
	"~/.local/share/godot/export_templates/${{ env.GODOT_VERSION }}.stable",
]
## Any line of the job that names the NDK or the SDK folder (comments are skipped before the match).
const SDK_WORDS: String = "(?i)ndk|ANDROID_HOME|ANDROID_SDK|lib/android"
## The libraries in the order the job builds them, the host's first. The id names the key's output
## and its shell variable.
const LIBRARIES: Array[Dictionary] = [
	{
		"id": "host",
		"flags": "",
		"cache": "Cache godot-cpp and the SCons object cache (host library)",
		"build": "Build the host library (linux, template_debug)",
	},
	{
		"id": "android_debug",
		"flags": ANDROID_FLAGS + "debug",
		"cache": "Cache godot-cpp and the SCons object cache (Android template_debug)",
		"build": "Build the Android library (arm64, template_debug)",
	},
	{
		"id": "android_release",
		"flags": ANDROID_FLAGS + "release",
		"cache": "Cache godot-cpp and the SCons object cache (Android template_release)",
		"build": "Build the Android library (arm64, template_release)",
	},
]


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


## ADR 0013 section 10: check-native-tests.sh is a step after verify.sh, never inside verify.sh.
func test_verify_job_checks_the_native_suites_after_verify_sh() -> void:
	var job: PackedStringArray = _job(_lines("ci.yml"), "  verify:")
	_assert_step(job, VERIFY_STEP, [VERIFY_RUN])
	_assert_step(job, CHECK_STEP, [CHECK_RUN])
	_assert_order(job, [VERIFY_STEP, CHECK_STEP])
	var verify_sh: String = FileAccess.get_file_as_string("res://scripts/verify.sh")
	assert_bool(verify_sh.contains("check-native-tests")).is_false()


## P55: native-clang builds with the flags its cache key names; gdUnit4 runs only if a suite exists,
## and the check comes last, once the gated run has written its results.xml.
func test_native_clang_job_builds_with_clang_at_speed_and_gates_gdunit4_on_discovery() -> void:
	var job: PackedStringArray = _job(_lines("ci.yml"), "  native-clang:")
	var flags: String = " --compiler clang --optimize speed"
	_assert_step(job, KEY_STEP, ["id: native-key", "run: |", KEY_ASSIGN % flags, KEY_ECHO])
	_assert_step(job, BUILD_STEP, ["run: bash scripts/build-native.sh" + flags])
	_assert_step(job, GATE_STEP, ["run: |", GATE_RUN])
	_assert_step(job, CHECK_STEP, [CHECK_RUN])
	_assert_order(job, [KEY_STEP, CACHE_STEP, BUILD_STEP, GATE_STEP, CHECK_STEP])


## ADR 0013 section 8: both jobs cache godot-cpp and SCons objects under build-native.sh's key. The
## key needs the toolchain, the restore needs the key, and both come before the build.
func test_native_caches_use_the_key_that_build_native_prints() -> void:
	var lines: PackedStringArray = _lines("ci.yml")
	assert_array(Array(lines)).contains("  SCONS_CACHE: /home/runner/.cache/rts-mobile-scons")
	var verify: PackedStringArray = _job(lines, "  verify:")
	_assert_step(verify, KEY_STEP, ["id: native-key", "run: |", KEY_ASSIGN % "", KEY_ECHO])
	_assert_order(verify, [INSTALL_STEP % "clang-format", KEY_STEP, CACHE_STEP, VERIFY_STEP])
	var clang: PackedStringArray = _job(lines, "  native-clang:")
	_assert_order(clang, [INSTALL_STEP % "clang", KEY_STEP, CACHE_STEP, BUILD_STEP])
	for job: PackedStringArray in [verify, clang]:
		_assert_cache_step(job)
		_assert_job_always_runs(job)


## P55a (ADR 0013 sections 8 and 10): the Android job installs the NDK, reads three keys, restores
## three caches and then builds the host's Linux library before the two Android ones, all before the
## export. The generated .gdextension names all six libraries, so without the host library the
## editor cannot load it. Each key is printed for exactly the flags of its build, and the NDK is
## never cached: see _assert_ndk_is_never_cached.
func test_android_job_installs_the_ndk_and_builds_the_host_library_first() -> void:
	var job: PackedStringArray = _job(_lines("ci.yml"), ANDROID_JOB)
	_assert_step(job, NDK_STEP, [NDK_RUN])
	_assert_step(job, ANDROID_INSTALL_STEP, ANDROID_INSTALL_RUN)
	var keys: Array = ["id: native-keys", "run: |"]
	var caches: Array = []
	var builds: Array = []
	for library: Dictionary in LIBRARIES:
		var id: String = library["id"]
		var flags: String = library["flags"]
		var cache_name: String = library["cache"]
		var build_name: String = library["build"]
		keys.append(KEY_VAR % [id, flags])
		_assert_cache_step(job, cache_name, "key: ${{ steps.native-keys.outputs.%s }}" % id)
		_assert_step(job, build_name, ["run: bash scripts/build-native.sh" + flags])
		caches.append(cache_name)
		builds.append(build_name)
	keys.append(KEYS_OUT)
	_assert_step(job, KEYS_STEP, keys)
	var first: Array = ["Select JDK 17", NDK_STEP, ANDROID_INSTALL_STEP, KEYS_STEP]
	_assert_order(job, first + caches + builds + ["Export debug APK"])
	_assert_ndk_is_never_cached(job)
	_assert_job_always_runs(job)


## P55a2 (ADR 0013 section 10): export-android.sh runs the ELF and libc++ symbol checks on the
## packed library. This offline test of them runs in the job after the NDK install (it uses the
## NDK's llvm tools too) and before the export, as a step with no `if:` or `continue-on-error`.
func test_android_job_runs_the_offline_elf_test_between_the_ndk_install_and_the_export() -> void:
	var job: PackedStringArray = _job(_lines("ci.yml"), ANDROID_JOB)
	_assert_step(job, ELF_STEP, [ELF_RUN])
	_assert_order(job, [NDK_STEP, ELF_STEP, "Export debug APK"])


## The NDK is never cached (ADR 0013 section 8). The job has the three library caches (godot-cpp and
## the SCons objects, pinned exactly above) and the Godot cache (the editor and templates, pinned
## here), and no other step of any kind that restores or saves a cache, whatever its path: every
## `uses: actions/cache` variant is counted. Beyond that, no line of the job outside its comments
## names the NDK or the SDK folder except the install step, so no path or key can reach them.
func _assert_ndk_is_never_cached(job: PackedStringArray) -> void:
	var godot: Array = Array(_step(job, GODOT_CACHE_STEP))
	assert_array(godot).has_size(8)
	assert_str(godot[2]).starts_with("uses: actions/cache@")
	assert_str(godot[7]).starts_with("key: godot-")
	godot.remove_at(7)
	godot.remove_at(2)
	var wanted: Array = ["- name: " + GODOT_CACHE_STEP, "id: godot-cache", "with:", "path: |"]
	assert_array(godot).contains_exactly(wanted + GODOT_CACHE_PATHS)
	var sdk_words: RegEx = RegEx.create_from_string(SDK_WORDS)
	var allowed: Array = ["- name: " + NDK_STEP, NDK_RUN]
	var cache_steps: int = 0
	for line: String in job:
		var text: String = line.strip_edges().trim_prefix("- ")
		if text.begins_with("#"):
			continue
		cache_steps += 1 if text.begins_with("uses: actions/cache") else 0
		if sdk_words.search(line) != null:
			(
				assert_array(allowed)
				. override_failure_message("A line names the NDK or the SDK folder: " + line)
				. contains([line.strip_edges()])
			)
	assert_int(cache_steps).is_equal(1 + LIBRARIES.size())


## Michael's "NDK r29" (2026-10-13): the NDK is pinned once, in build-native.sh. install-ndk.sh
## reads that line and ci.yml names no NDK version, so none of the three can disagree.
func test_the_ndk_is_pinned_once_in_build_native_sh() -> void:
	assert_str(_pin("res://scripts/build-native.sh", "NDK_VERSION")).is_equal("29.0.14206865")
	var version: RegEx = RegEx.create_from_string("\\d+\\.\\d+\\.\\d{6,}")
	for path: String in ["res://scripts/ci/install-ndk.sh", "res://.github/workflows/ci.yml"]:
		assert_object(version.search(FileAccess.get_file_as_string(path))).is_null()


## The lines of one job: from the line after its header to the next job (or the comment before it).
func _job(lines: PackedStringArray, header: String) -> PackedStringArray:
	var start: int = lines.find(header)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < lines.size() and not (lines[end].begins_with("  ") and lines[end][2] != " "):
		end += 1
	return lines.slice(start + 1, end)


## One step of a job, stripped, without its blank and comment lines: its "- name:" line to the next.
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


## A step is exactly its name line and these lines: no `if:` or `continue-on-error` can neuter it.
func _assert_step(job: PackedStringArray, step_name: String, body: Array) -> void:
	assert_array(Array(_step(job, step_name))).contains_exactly(["- name: " + step_name] + body)


## The steps exist and come in this order: a missing one is -1, never greater than the last.
func _assert_order(job: PackedStringArray, step_names: Array) -> void:
	var last: int = -1
	for step_name: String in step_names:
		var at: int = job.find("      - name: " + step_name)
		assert_int(at).is_greater(last)
		last = at


## Job-level keys sit at four spaces: no `if:` switches the job off and no failure is tolerated.
func _assert_job_always_runs(job: PackedStringArray) -> void:
	for line: String in job:
		assert_bool(line.begins_with("    if:")).is_false()
		assert_bool(line.begins_with("    continue-on-error:")).is_false()


## The cache step is actions/cache itself (not /restore, which never saves), whose SHA pin the test
## above checks, with exactly godot-cpp and the SCons cache folder under build-native.sh's key. An
## `if:` or `continue-on-error` would show as an extra line.
func _assert_cache_step(
	job: PackedStringArray, step_name: String = CACHE_STEP, key: String = CACHE_KEY
) -> void:
	var step: Array = Array(_step(job, step_name))
	assert_array(step).has_size(7)
	assert_str(step[1]).starts_with("uses: actions/cache@")
	step.remove_at(1)
	var wanted: Array = ["- name: " + step_name, "with:", "path: |"]
	wanted.append_array(["native/godot-cpp", "${{ env.SCONS_CACHE }}", key])
	assert_array(step).contains_exactly(wanted)


func _pin(path: String, pin_name: String) -> String:
	var rx: RegEx = RegEx.create_from_string("(?m)^\\s*" + pin_name + '[=:]\\s*"([^"]+)"')
	var hit: RegExMatch = rx.search(FileAccess.get_file_as_string(path))
	return hit.get_string(1) if hit != null else ""
