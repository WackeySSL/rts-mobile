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
const INSTALLER_STEP: String = "Offline test of the cloud Android installer"
const INSTALLER_RUN: String = "run: bash scripts/ci/test-install-android.sh"
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
## P51: the golden hashes (P49a) join the one run-tests.sh call, and the check requires them.
const GATE_RUN: String = (
	'if [ -n "$(bash scripts/ci/check-native-tests.sh --list)" ]; then'
	+ " bash scripts/run-tests.sh -a res://tests/sim/native"
	+ " -a res://tests/perf/test_golden_hashes.gd; fi"
)
const GATE_CHECK_RUN: String = CHECK_RUN + " --require test_golden_hashes"
## P51b: the determinism job on arm64 Linux (ADR 0013 section 10).
const ARM64_JOB: String = "  determinism-arm64:"
const ARM64_RUNNER: String = "    runs-on: ubuntu-24.04-arm"
## --arch arm64 is the host's architecture, which build-native.sh refuses to build on any other.
const ARM64_FLAGS: String = " --arch arm64 --compiler clang --optimize speed"
const ARM64_CACHE_STEP: String = "Cache Godot editor and web export templates"
const ARM64_CACHE_KEY: String = (
	"key: godot-${{ env.GODOT_VERSION }}-linux-arm64-web-"
	+ "${{ hashFiles('scripts/ci/install-godot.sh', 'scripts/ci/remote_zip.py') }}"
)
const ARM64_GODOT_STEP: String = "Install Godot (arm64 editor + web no-threads templates only)"
const ARM64_INSTALL_RUN: Array[String] = [
	"run: |",
	'pipx install "scons==${SCONS_VERSION}"',
	"sudo apt-get install -y --no-install-recommends binutils clang",
]
const ARM64_BUILD_STEP: String = "Build the library (arm64, clang, optimize=speed)"
const ARM64_RUN_STEP: String = "Run the determinism suites (gdUnit4)"
## The native suites and the three suites of the plan, in the one run-tests.sh call that the
## check reads.
const ARM64_SUITES: Array[String] = [
	"res://tests/sim/native",
	"res://tests/sim/test_determinism.gd",
	"res://tests/sim/test_world_hash.gd",
	"res://tests/perf/test_golden_hashes.gd",
]
const ARM64_CHECK_RUN: String = (
	CHECK_RUN + " --require test_golden_hashes --require test_determinism --require test_world_hash"
)
const GODOT_SCRIPT: String = "res://scripts/ci/install-godot.sh"
## P51: the verify job's summary copies the PERF lines of the verify log.
const SUMMARY_STEP: String = "Job summary"
const PERF_PATTERN: String = "^PERF sim (units=|impl=native)"
const PERF_GREP: String = (
	"grep -a -E '"
	+ PERF_PATTERN
	+ "' "
	+ '"$RUNNER_TEMP/verify.log" 2>/dev/null'
	+ ' || echo "no PERF line (the perf suite did not run)"'
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
## P57 (ADR 0013 section 10): the sanitizer jobs.
const CHANGES_JOB: String = "  sanitizer-changes:"
const SANITIZER_JOB: String = "  sanitizers:"
const DIFF_STEP: String = "Does the pull request touch the native code or what it runs on"
## P57b: the folders of ADR 0013 section 10 and, since the lead's decision of 2026-10-14, the files
## that drive the job. `grep -Eq` reads it, so each dot of a file name is escaped.
const CHANGES_PATTERN: String = (
	"^(native/|game/sim/|data/|tests/sim/native/|tests/sim/support/"
	+ "|scripts/build-native\\.sh$|scripts/ci/run-sanitizer-harness\\.sh$"
	+ "|\\.github/workflows/ci\\.yml$)"
)
const CHANGES_TOUCHED: Array[String] = [
	"native/sim_kernels/src/bind/kernel_flow.cpp",
	"game/sim/Sim.gd",
	"data/rules.tres",
	"tests/sim/native/test_flow_lockstep.gd",
	"tests/sim/support/match_script.gd",
	"scripts/build-native.sh",
	"scripts/ci/run-sanitizer-harness.sh",
	".github/workflows/ci.yml",
]
## Near misses: other files of the same folders, a name that merely starts or ends like a driver,
## and a name with another character where a dot stands.
const CHANGES_UNTOUCHED: Array[String] = [
	"README.md",
	"docs/plans/2026-10-11-phase-2.md",
	"game/view/Unit.gd",
	"tests/sim/test_sim.gd",
	"tests/sim/supported/x.gd",
	"tests/project/test_ci_workflow.gd",
	"scripts/verify.sh",
	"scripts/build-native.sh.orig",
	"scripts/build-native-sh",
	"scripts/ci/run-sanitizer-harness.shx",
	"scripts/ci/check-native-tests.sh",
	"scripts/build-native.sh/x",
	"x/scripts/build-native.sh",
	".github/workflows/preview.yml",
	".github/workflows/ci.yml.bak",
	".github/workflows/ci-yml",
	"x.github/workflows/ci.yml",
]
const UBSAN_FLAGS: String = " --sanitize undefined"
const UBSAN_BUILD_STEP: String = "Build the UBSan library (g++ -O1, shared libubsan)"
const UBSAN_RUN_STEP: String = "Run the native suites on the UBSan library (gdUnit4)"
const UBSAN_RUN: String = "run: bash scripts/run-tests.sh -a res://tests/sim/native"
const ASLR_STEP: String = "Lower the address randomisation for AddressSanitizer"
const ASLR_RUN: String = "run: sudo sysctl -w vm.mmap_rnd_bits=28"
const HARNESS_STEP: String = "Dump the arena's states and run the ASan harness over core/"
const HARNESS_RUN: String = 'run: bash scripts/ci/run-sanitizer-harness.sh "$RUNNER_TEMP/sanitizer"'
const DUMP_STEP: String = "res://tests/sim/native/sanitizer/dump_states.gd"
const DUMP_READER: String = "res://native/sim_kernels/sanitizer/dump.h"
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


## P55b: the offline test of the cloud Android installer runs in the verify job, the required check.
func test_verify_job_runs_the_cloud_installer_test() -> void:
	_assert_step(_job(_lines("ci.yml"), "  verify:"), INSTALLER_STEP, [INSTALLER_RUN])


## ADR 0013 section 10: check-native-tests.sh is a step after verify.sh, never inside verify.sh.
func test_verify_job_checks_the_native_suites_after_verify_sh() -> void:
	var job: PackedStringArray = _job(_lines("ci.yml"), "  verify:")
	_assert_step(job, VERIFY_STEP, [VERIFY_RUN])
	_assert_step(job, CHECK_STEP, [CHECK_RUN])
	_assert_order(job, [VERIFY_STEP, CHECK_STEP])
	var verify_sh: String = FileAccess.get_file_as_string("res://scripts/verify.sh")
	assert_bool(verify_sh.contains("check-native-tests")).is_false()


## P51: the summary of the verify job copies the GDScript and the impl=native PERF line, after the
## VERIFY SUMMARY block, in a step that runs when verify.sh failed too.
func test_verify_job_summary_copies_the_two_perf_lines() -> void:
	var job: PackedStringArray = _job(_lines("ci.yml"), "  verify:")
	var step: Array = Array(_step(job, SUMMARY_STEP))
	assert_array(step).contains(["if: always()", PERF_GREP])
	_assert_order(job, [VERIFY_STEP, SUMMARY_STEP])
	var block: int = step.find(
		"sed -n '/===== VERIFY SUMMARY =====/,$p' " + '"$RUNNER_TEMP/verify.log"'
	)
	assert_int(block).is_greater(-1)
	assert_int(step.find(PERF_GREP)).is_greater(block)
	var selected: Array[String] = [
		"PERF sim units=150 ticks=900 runs=3 mean_ms=1.020 hash=4eb974e71b2107be",
		"PERF sim impl=native units=150 ticks=900 runs=3 mean_ms=0.308 hash=4eb974e71b2107be",
	]
	for line: String in selected:
		assert_bool(_perf_selected(line)).is_true()
	# The note without the library, the per-run lines and the sub-lines are no PERF line, and a PERF
	# line starts at the start of a line in the log.
	var skipped: Array[String] = [
		"perf: no native line, the SimKernels library is not loaded",
		"RUN sim seed=42 run=0 mean_ms=1.020 hash=4eb974e71b2107be",
		"RUN sim impl=native seed=42 run=0 mean_ms=0.308 hash=4eb974e71b2107be",
		"STEP sim mean_ms=0.900 p50_ms=0.800",
		"STEP sim impl=native mean_ms=0.300 p50_ms=0.200",
		"WATCH sim commands order_tick=0 commands_ms=1.235 crafted_units=150",
		" PERF sim units=150 ticks=900",
	]
	for line: String in skipped:
		assert_bool(_perf_selected(line)).is_false()


## P55: native-clang builds with the flags its cache key names; gdUnit4 runs only if a suite exists,
## and the check comes last, once the gated run has written its results.xml. P51: the golden hashes
## run in that one call and the check requires them.
func test_native_clang_job_builds_with_clang_at_speed_and_gates_gdunit4_on_discovery() -> void:
	var job: PackedStringArray = _job(_lines("ci.yml"), "  native-clang:")
	var flags: String = " --compiler clang --optimize speed"
	_assert_step(job, KEY_STEP, ["id: native-key", "run: |", KEY_ASSIGN % flags, KEY_ECHO])
	_assert_step(job, BUILD_STEP, ["run: bash scripts/build-native.sh" + flags])
	_assert_step(job, GATE_STEP, ["run: |", GATE_RUN])
	_assert_step(job, CHECK_STEP, [GATE_CHECK_RUN])
	_assert_order(job, [KEY_STEP, CACHE_STEP, BUILD_STEP, GATE_STEP, CHECK_STEP])


## P51b (ADR 0013 section 10): the arm64 job runs on the arm64 runner, installs the arm64 editor
## under a cache key that names the architecture, builds the library for its own host with clang
## at speed, plays the native suites, the two determinism suites and the golden hashes in one
## call, and the check requires the three suites outside tests/sim/native. None of the three
## reads a clock (the job times nothing), and install-godot.sh holds a pin for each editor build.
func test_arm64_job_builds_a_clang_library_and_runs_the_determinism_suites() -> void:
	var lines: PackedStringArray = _lines("ci.yml")
	var job: PackedStringArray = _job(lines, ARM64_JOB)
	assert_str(job[0]).is_equal(ARM64_RUNNER)
	var cache: Array = Array(_step(job, ARM64_CACHE_STEP))
	assert_array(cache).has_size(7)
	assert_str(cache[1]).starts_with("uses: actions/cache@")
	cache.remove_at(1)
	var wanted: Array = ["- name: " + ARM64_CACHE_STEP, "with:", "path: |"]
	assert_array(cache).contains_exactly(wanted + GODOT_CACHE_PATHS + [ARM64_CACHE_KEY])
	_assert_step(job, ARM64_GODOT_STEP, ["run: bash scripts/ci/install-godot.sh"])
	_assert_step(job, INSTALL_STEP % "clang", ARM64_INSTALL_RUN)
	var key: Array = ["id: native-key", "run: |", KEY_ASSIGN % ARM64_FLAGS, KEY_ECHO]
	_assert_step(job, KEY_STEP, key)
	_assert_cache_step(job)
	_assert_step(job, ARM64_BUILD_STEP, ["run: bash scripts/build-native.sh" + ARM64_FLAGS])
	var run: String = "bash scripts/run-tests.sh -a " + " -a ".join(ARM64_SUITES)
	_assert_step(job, ARM64_RUN_STEP, ["run: |", run])
	_assert_step(job, CHECK_STEP, [ARM64_CHECK_RUN])
	var steps: Array = [ARM64_CACHE_STEP, ARM64_GODOT_STEP, INSTALL_STEP % "clang", KEY_STEP]
	_assert_order(job, steps + [CACHE_STEP, ARM64_BUILD_STEP, ARM64_RUN_STEP, CHECK_STEP])
	_assert_job_always_runs(job)
	for line: String in lines:
		assert_bool(line.contains("needs:") and line.contains("determinism")).is_false()
	var clock: RegEx = RegEx.create_from_string("\\bTime\\.|get_ticks_")
	assert_bool(DirAccess.dir_exists_absolute(ARM64_SUITES[0])).is_true()
	for suite: String in ARM64_SUITES.slice(1):
		assert_bool(FileAccess.file_exists(suite)).is_true()
		var found: RegExMatch = clock.search(FileAccess.get_file_as_string(suite))
		(
			assert_object(found)
			. override_failure_message("%s reads a clock, and this job times nothing" % suite)
			. is_null()
		)
	var x86_pin: String = _pin(GODOT_SCRIPT, "EDITOR_SHA512_X86_64")
	var arm_pin: String = _pin(GODOT_SCRIPT, "EDITOR_SHA512_ARM64")
	var sha512: RegEx = RegEx.create_from_string("^[0-9a-f]{128}$")
	assert_object(sha512.search(x86_pin)).is_not_null()
	assert_object(sha512.search(arm_pin)).is_not_null()
	assert_str(arm_pin).is_not_equal(x86_pin)


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


## P57: the sanitizer jobs run on pull requests only, the first decides from the files of the merge
## commit against its first parent whether the second runs, and neither is a required check or a
## dependency of one (`verify` is the only required check, and the Android jobs need it alone).
## P57b: the filter is the four folders and the files that drive the job.
func test_sanitizer_changes_job_filters_a_pull_request_by_folders_and_driving_files() -> void:
	var lines: PackedStringArray = _lines("ci.yml")
	var job: PackedStringArray = _job(lines, CHANGES_JOB)
	assert_str(job[0]).is_equal("    if: github.event_name == 'pull_request'")
	assert_array(Array(job)).contains(["          fetch-depth: 2"])
	_assert_step(
		job,
		DIFF_STEP,
		[
			"id: diff",
			"env:",
			"PATTERN: '%s'" % CHANGES_PATTERN,
			"run: |",
			"relevant=true",
			'if files="$(git diff --no-renames --name-only HEAD^1 HEAD)"; then',
			'grep -Eq "$PATTERN" <<<"$files" || relevant=false',
			"fi",
			'echo "relevant=$relevant" >> "$GITHUB_OUTPUT"',
		]
	)
	var needers: Array[String] = []
	for i: int in lines.size():
		if lines[i].contains("needs:") and lines[i].contains("sanitiz"):
			needers.append(lines[i])
	assert_array(needers).is_equal(["    needs: sanitizer-changes"])


## P57b: the pattern of the workflow takes the folders and the four driving files and nothing near
## them. It reads the pattern from ci.yml, so that it tests the workflow and not the constant above,
## and runs the real `grep -E` that the job runs, over the changed paths one to a line as the job's
## here-string lists them. The pattern goes in as a file (-f) and not as an argument, so that no
## quoting of OS.execute can change it: the pattern ends two alternatives in a `$`, and a shell
## expands a `$name` in an argument.
func test_the_sanitizer_filter_matches_what_drives_the_job_and_nothing_near_it() -> void:
	var line: RegEx = RegEx.create_from_string("(?m)^ +PATTERN: '(.+)'$")
	var found: RegExMatch = line.search(FileAccess.get_file_as_string(WORKFLOWS + "ci.yml"))
	assert_object(found).is_not_null()
	var access: DirAccess = DirAccess.create_temp("ci_workflow_filter_")
	var pattern_file: String = access.get_current_dir().path_join("pattern.txt")
	var paths_file: String = access.get_current_dir().path_join("paths.txt")
	_store(pattern_file, found.get_string(1) + "\n")
	_store(paths_file, "\n".join(CHANGES_TOUCHED + CHANGES_UNTOUCHED) + "\n")
	var output: Array = []
	var code: int = OS.execute("grep", ["-E", "-f", pattern_file, paths_file], output, true)
	(
		assert_int(code)
		. override_failure_message("grep exited %d (0 is a match, 1 none): %s" % [code, output])
		. is_equal(0)
	)
	var matched: Array[String] = []
	for path: String in String(output[0]).split("\n", false):
		matched.append(path)
	assert_array(matched).is_equal(CHANGES_TOUCHED)


## P57: the UBSan library is built, the real native suites run on it and are checked, and the ASan
## harness follows, in that order; every report is fatal (halt_on_error), and no step or job can
## be switched off by an `if:` or `continue-on-error` beyond the job's own filter.
func test_sanitizer_job_builds_the_ubsan_library_then_runs_the_suites_and_the_harness() -> void:
	var job: PackedStringArray = _job(_lines("ci.yml"), SANITIZER_JOB)
	(
		assert_array(Array(job.slice(0, 3)))
		. is_equal(
			[
				"    needs: sanitizer-changes",
				"    if: needs.sanitizer-changes.outputs.relevant == 'true'",
				"    runs-on: ubuntu-24.04",
			]
		)
	)
	assert_array(Array(job)).contains(["      UBSAN_OPTIONS: halt_on_error=1:print_stacktrace=1"])
	for line: String in job:
		assert_bool(line.begins_with("    continue-on-error:")).is_false()
		assert_bool(line.strip_edges().begins_with("continue-on-error:")).is_false()
	_assert_step(job, ANDROID_INSTALL_STEP, ANDROID_INSTALL_RUN)
	_assert_step(job, KEY_STEP, ["id: native-key", "run: |", KEY_ASSIGN % UBSAN_FLAGS, KEY_ECHO])
	_assert_cache_step(job)
	_assert_step(job, UBSAN_BUILD_STEP, ["run: bash scripts/build-native.sh" + UBSAN_FLAGS])
	_assert_step(job, UBSAN_RUN_STEP, [UBSAN_RUN])
	_assert_step(job, CHECK_STEP, [CHECK_RUN])
	_assert_step(job, ASLR_STEP, [ASLR_RUN])
	_assert_step(job, HARNESS_STEP, [HARNESS_RUN])
	_assert_order(
		job,
		[
			ANDROID_INSTALL_STEP,
			KEY_STEP,
			CACHE_STEP,
			UBSAN_BUILD_STEP,
			UBSAN_RUN_STEP,
			CHECK_STEP,
			ASLR_STEP,
			HARNESS_STEP
		]
	)


## P57 (lead decision, 2026-10-14): the dump step is a plain script and no gdUnit4 suite, so
## that run-tests.sh (which hands gdUnit4 every .gd below the folder it is asked for, in verify.sh
## and the native-clang job) never runs it, and check-native-tests.sh (which prunes sanitizer/)
## never requires it. The proof that no suite named after it reaches results.xml is a run of both.
func test_the_dump_step_is_a_plain_script_and_no_gdunit_suite() -> void:
	var script: GDScript = load(DUMP_STEP) as GDScript
	assert_object(script).is_not_null()
	assert_str(script.get_instance_base_type()).is_equal("SceneTree")
	assert_object(script.get_base_script()).is_null()
	assert_bool(DUMP_STEP.get_file().begins_with("test_")).is_false()


## P57: the harness refuses a dump of a World.STATE_FORMAT its reader does not know, and only the
## sanitizer job (not a required check) would notice a bump of the number. So the number must be in
## the reader's KNOWN_FORMATS: the pull request that bumps STATE_FORMAT updates the reader and the
## dump step in the same pull request, under verify.
func test_the_dump_reader_knows_the_state_format_of_the_world() -> void:
	var line: RegEx = RegEx.create_from_string("KNOWN_FORMATS\\[\\] = \\{([\\d, ]+)\\}")
	var found: RegExMatch = line.search(FileAccess.get_file_as_string(DUMP_READER))
	assert_object(found).is_not_null()
	var known: Array[int] = []
	for number: String in found.get_string(1).split(","):
		known.append(number.strip_edges().to_int())
	assert_array(known).contains([World.STATE_FORMAT])


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


func _perf_selected(line: String) -> bool:
	return RegEx.create_from_string(PERF_PATTERN).search(line) != null


func _pin(path: String, pin_name: String) -> String:
	var rx: RegEx = RegEx.create_from_string("(?m)^\\s*" + pin_name + '[=:]\\s*"([^"]+)"')
	var hit: RegExMatch = rx.search(FileAccess.get_file_as_string(path))
	return hit.get_string(1) if hit != null else ""


func _store(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_object(file).is_not_null()
	file.store_string(text)
	file.close()
