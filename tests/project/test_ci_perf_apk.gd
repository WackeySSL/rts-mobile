extends GdUnitTestSuite
## Pins the perf APK of the gate (P51r, ADR 0012 section 4): the CI job that exports it with the
## release template, the preset that keeps the dev menu in it, and the checks of
## `export-android.sh --release` (not debuggable, the dev_menu feature in the pack, the release
## template's engine library). A wrong edit still exports an APK: a debug template gives timings
## that the gate does not accept, and a pack without dev_menu has no Perf arena button. A new
## suite, because test_ci_workflow.gd holds gdlint's 20 public methods.

const WORKFLOW: String = "res://.github/workflows/ci.yml"
const PERF_JOB: String = "  android-perf-apk:"
const PUBLISH_JOB: String = "  android-perf-release:"
const DEBUG_JOB: String = "  android-debug-apk:"
const EXPORT_SCRIPT: String = "res://scripts/export-android.sh"
const PUBLISH_SCRIPT: String = "res://scripts/ci/publish-dev-release.sh"
const INSTALL_SCRIPT: String = "res://scripts/ci/install-godot.sh"
const APK_PATH: String = "build/android/rts-mobile-perf-release.apk"
const NOTICE_PATH: String = "build/android/THIRD_PARTY_LICENSES.txt"
const ARTIFACT: String = "rts-mobile-perf-release-apk-${{ github.sha }}"
const KEYSTORE_FILE: String = '"$RUNNER_TEMP/perf.keystore"'

const NDK_STEP: String = "Install the Android NDK (install-ndk.sh)"
const TOOLCHAIN_STEP: String = "Install the native toolchain (SCons, binutils)"
const KEYS_STEP: String = "Read the native cache keys"
const CACHE: String = "Cache godot-cpp and the SCons object cache"
const HOST_CACHE: String = CACHE + " (host library)"
const RELEASE_CACHE: String = CACHE + " (Android template_release)"
const HOST_BUILD: String = "Build the host library (linux, template_debug)"
const RELEASE_BUILD: String = "Build the Android library (arm64, template_release)"
const GODOT_CACHE: String = "Cache Godot editor and export templates (web and Android release)"
const GODOT_STEP: String = "Install Godot (editor, web and Android release templates)"
const EXPORT_STEP: String = "Export perf APK (release template)"
const TREE_STEP: String = "Clean-tree check"
const UPLOAD_STEP: String = "Upload perf APK"
const DELETE_STEP: String = "Delete perf keystore"

const KEY_LINES: Array[String] = [
	"id: native-keys",
	"run: |",
	'host="$(bash scripts/build-native.sh --print-cache-key)"',
	(
		'android_release="$(bash scripts/build-native.sh --platform android --arch arm64'
		+ ' --target template_release --print-cache-key)"'
	),
	'{ echo "host=$host"; echo "android_release=$android_release"; } >> "$GITHUB_OUTPUT"',
]
const GODOT_CACHE_PATHS: Array[String] = [
	"~/.local/opt/godot-${{ env.GODOT_VERSION }}",
	"~/.local/share/godot/export_templates/${{ env.GODOT_VERSION }}.stable",
]
const GODOT_CACHE_KEY: String = (
	"key: godot-${{ env.GODOT_VERSION }}-linux-x86_64-android-release-"
	+ "${{ hashFiles('scripts/ci/install-godot.sh', 'scripts/ci/remote_zip.py') }}"
)
## The export step as written: a key generated for the run, the release variables, the script.
const EXPORT_LINES: Array[String] = [
	"run: |",
	"umask 077",
	'keystore="$RUNNER_TEMP/perf.keystore"',
	'password="$(openssl rand -hex 16)"',
	'echo "::add-mask::$password"',
	(
		'PERF_KEY_PASSWORD="$password" keytool -genkeypair -keystore "$keystore"'
		+ " -alias perfkey -keyalg RSA \\"
	),
	(
		"-keysize 2048 -validity 10000 -storepass:env PERF_KEY_PASSWORD"
		+ " -keypass:env PERF_KEY_PASSWORD \\"
	),
	'-dname "CN=rts-mobile perf"',
	'GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$keystore" \\',
	'GODOT_ANDROID_KEYSTORE_RELEASE_USER="perfkey" \\',
	'GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$password" \\',
	"bash scripts/export-android.sh --release",
]
const SDK_WORDS: String = "(?i)ndk|ANDROID_HOME|ANDROID_SDK|lib/android"


func test_perf_job_runs_after_verify_on_a_push_or_a_manual_run_only() -> void:
	var job: PackedStringArray = _job(PERF_JOB)
	assert_str(job[0]).is_equal("    needs: verify")
	assert_str(job[1]).is_equal(
		"    if: github.event_name == 'push' || github.event_name == 'workflow_dispatch'"
	)
	var read_only: Array = ["    permissions:", "      contents: read"]
	assert_array(Array(job.slice(4, 6))).is_equal(read_only)
	for line: String in job:
		assert_bool(line.contains("pull_request")).is_false()
		assert_bool(line.begins_with("    continue-on-error:")).is_false()


func test_perf_job_builds_the_host_and_release_libraries_before_the_release_install() -> void:
	var job: PackedStringArray = _job(PERF_JOB)
	_assert_step(job, NDK_STEP, ["run: bash scripts/ci/install-ndk.sh"])
	_assert_step(
		job,
		TOOLCHAIN_STEP,
		[
			"run: |",
			'pipx install "scons==${SCONS_VERSION}"',
			"sudo apt-get install -y --no-install-recommends binutils",
		]
	)
	_assert_step(job, KEYS_STEP, KEY_LINES)
	_assert_cache(job, HOST_CACHE, "key: ${{ steps.native-keys.outputs.host }}")
	_assert_cache(job, RELEASE_CACHE, "key: ${{ steps.native-keys.outputs.android_release }}")
	_assert_step(job, HOST_BUILD, ["run: bash scripts/build-native.sh"])
	_assert_step(
		job,
		RELEASE_BUILD,
		[
			"run: bash scripts/build-native.sh --platform android --arch arm64 --target template_release"
		]
	)
	_assert_step(job, GODOT_STEP, ["run: bash scripts/ci/install-godot.sh --android-release"])
	var steps: Array = ["Select JDK 17", NDK_STEP, TOOLCHAIN_STEP, KEYS_STEP, HOST_CACHE]
	steps.append_array([RELEASE_CACHE, HOST_BUILD, RELEASE_BUILD, GODOT_CACHE, GODOT_STEP])
	_assert_order(job, steps + [EXPORT_STEP, TREE_STEP, "Job summary", UPLOAD_STEP, DELETE_STEP])


## The Godot cache of this job has a key of its own: one shared with android-debug-apk would restore
## a folder without android_release.apk and never save the folder that has it. Beside it the job
## has the two library caches and no other cache, and no line outside the NDK step names the NDK or
## the SDK folder (the NDK is never cached, ADR 0013 section 8).
func test_perf_job_caches_only_godot_and_the_two_libraries() -> void:
	var job: PackedStringArray = _job(PERF_JOB)
	var godot: Array = Array(_step(job, GODOT_CACHE))
	assert_array(godot).has_size(8)
	assert_str(godot[2]).starts_with("uses: actions/cache@")
	assert_str(godot[7]).is_equal(GODOT_CACHE_KEY)
	godot.remove_at(7)
	godot.remove_at(2)
	var wanted: Array = ["- name: " + GODOT_CACHE, "id: godot-cache", "with:", "path: |"]
	assert_array(godot).contains_exactly(wanted + GODOT_CACHE_PATHS)
	var debug_godot_key: String = _step(
		_job(DEBUG_JOB), "Cache Godot editor and export templates (web and Android debug)"
	)[7]
	assert_str(debug_godot_key).is_not_equal(GODOT_CACHE_KEY)
	var sdk_words: RegEx = RegEx.create_from_string(SDK_WORDS)
	var allowed: Array = ["- name: " + NDK_STEP, "run: bash scripts/ci/install-ndk.sh"]
	var caches: int = 0
	for line: String in job:
		var text: String = line.strip_edges().trim_prefix("- ")
		if text.begins_with("#"):
			continue
		caches += 1 if text.begins_with("uses: actions/cache") else 0
		if sdk_words.search(line) != null:
			assert_array(allowed).contains([line.strip_edges()])
	assert_int(caches).is_equal(3)


## The key is generated for the run and passed as the release keystore; nothing leaves the run: the
## job reads no secret, the file lives in $RUNNER_TEMP and is deleted by a step that always runs,
## and no real ad ID or store key can reach the APK (monetization rules).
func test_perf_job_signs_with_a_key_generated_for_the_run_and_deletes_it() -> void:
	var job: PackedStringArray = _job(PERF_JOB)
	_assert_step(job, EXPORT_STEP, EXPORT_LINES)
	_assert_step(job, DELETE_STEP, ["if: always()", "run: rm -f " + KEYSTORE_FILE])
	_assert_order(job, [EXPORT_STEP, DELETE_STEP])
	for line: String in job:
		var text: String = line.strip_edges()
		assert_bool(text.contains("secrets.")).is_false()
		assert_bool(text.contains("KEYSTORE_DEBUG")).is_false()
		assert_bool(text.to_lower().contains("ca-app-pub")).is_false()


func test_perf_job_uploads_the_apk_and_its_licences_under_one_artifact_name() -> void:
	var job: PackedStringArray = _job(PERF_JOB)
	var upload: Array = Array(_step(job, UPLOAD_STEP))
	assert_array(upload).has_size(9)
	assert_str(upload[1]).starts_with("uses: actions/upload-artifact@")
	upload.remove_at(1)
	var wanted: Array = ["- name: " + UPLOAD_STEP, "with:", "name: " + ARTIFACT, "path: |"]
	wanted.append_array([APK_PATH, NOTICE_PATH, "if-no-files-found: error", "retention-days: 14"])
	assert_array(upload).contains_exactly(wanted)
	# The same clean-tree step as android-debug-apk has.
	_assert_step(job, TREE_STEP, Array(_step(_job(DEBUG_JOB), TREE_STEP).slice(1)))


## Same rules as android-dev-release (ADR 0005 section 6), and the artifact it downloads is the one
## the job above uploads.
func test_perf_release_job_runs_only_on_a_push_to_main_and_publishes_this_runs_apk() -> void:
	var job: PackedStringArray = _job(PUBLISH_JOB)
	assert_str(job[0]).is_equal("    needs: android-perf-apk")
	var push_to_main: String = "    if: github.event_name == 'push'"
	push_to_main += " && github.ref == 'refs/heads/main' && !github.event.repository.fork"
	assert_str(job[1]).is_equal(push_to_main)
	var group: Array = ["    permissions:", "      contents: write", "    concurrency:"]
	group.append_array(["      group: android-perf-release", "      cancel-in-progress: false"])
	assert_array(Array(job.slice(4, 9))).is_equal(group)
	var download: Array = Array(_step(job, "Download the perf APK of this run"))
	assert_str(download[1]).starts_with("uses: actions/download-artifact@")
	download.remove_at(1)
	var wanted: Array = ["- name: Download the perf APK of this run", "with:", "name: " + ARTIFACT]
	assert_array(download).contains_exactly(wanted + ["path: ${{ runner.temp }}/apk"])
	var publish: Array = ["env:", "GH_TOKEN: ${{ github.token }}"]
	publish.append('run: bash scripts/ci/publish-dev-release.sh "$RUNNER_TEMP/apk" perf')
	_assert_step(job, "Replace the android-perf-release pre-release", publish)


## Plan P51r: the two checks the job makes of the APK itself, in the script it runs. The text pins
## are what a removal or a weakening would break; scripts/ci/test-export-notices.sh runs them.
func test_the_release_export_checks_debuggable_dev_menu_and_the_engine_library() -> void:
	var script: String = FileAccess.get_file_as_string(EXPORT_SCRIPT)
	var release_block: int = script.find('if [ "$EXPORT_MODE" = release ]; then')
	assert_int(release_block).is_greater(-1)
	var checks: Array[String] = [
		'aapt2" dump badging "$apk"',
		"! grep -q 'application-debuggable' <<<\"$badging\"",
		'debuggable\\(0x0101000f\\)=.*(true|0xffffffff)\' <<<"$manifest"',
		'unzip -p "$apk" assets/project.binary | strings | grep -A1 -x _custom_features',
		'grep -qx dev_menu <<<"$features"',
		'unzip -p "$template_dir/android_release.apk" "$abi_dir/libgodot_android.so"',
	]
	var last: int = release_block
	for check: String in checks:
		var at: int = script.find(check, last)
		assert_int(at).override_failure_message("Missing or out of order: " + check).is_greater(
			last
		)
		last = at
	assert_bool(script.contains('"--export-$EXPORT_MODE" "$PRESET"')).is_true()
	assert_bool(script.contains('"android_${EXPORT_MODE}.apk"')).is_true()


## The names agree across the preset, the export script, the publish script and the job.
func test_preset_script_and_job_agree_on_the_perf_apk() -> void:
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	var presets: Array[String] = []
	var names: Array[String] = []
	for section: String in ["preset.1", "preset.2"]:
		var preset_name: String = config.get_value(section, "name")
		var export_path: String = config.get_value(section, "export_path")
		presets.append(preset_name)
		names.append(export_path.get_file())
		assert_str(export_path).is_equal(export_path.get_base_dir() + "/" + names[-1])
	assert_str(config.get_value("preset.2", "export_path")).is_equal(APK_PATH)
	var script: String = FileAccess.get_file_as_string(EXPORT_SCRIPT)
	assert_array(_all(script, 'PRESET="([^"]+)"')).is_equal(presets)
	assert_array(_all(script, 'APK_NAME="([^"]+)"')).is_equal(names)
	var publish: String = FileAccess.get_file_as_string(PUBLISH_SCRIPT)
	assert_array(_all(publish, 'APK_NAME="([^"]+)"')).is_equal(names)
	var tags: Array[String] = ["android-dev-latest", "android-perf-release"]
	assert_array(_all(publish, 'TAG="([^"]+)"')).is_equal(tags)


## The preset keeps the dev menu where OS.is_debug_build() is false and never drops the kernels
## library from the pack (the Web preset alone excludes native/*); signing values stay out of it.
func test_perf_preset_keeps_dev_menu_and_native_library_and_no_signing_values() -> void:
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load("res://export_presets.cfg")).is_equal(OK)
	var section: String = "preset.2"
	var options: String = "preset.2.options"
	assert_str(config.get_value(section, "platform")).is_equal("Android")
	assert_str(config.get_value(section, "custom_features")).is_equal("dev_menu")
	var excluded: String = config.get_value(section, "exclude_filter")
	assert_str(excluded).is_equal("tests/*, addons/gdUnit4/*")
	assert_bool(config.get_value(options, "gradle_build/use_gradle_build")).is_false()
	assert_bool(config.get_value(options, "architectures/arm64-v8a")).is_true()
	for abi: String in ["armeabi-v7a", "x86", "x86_64"]:
		assert_bool(config.get_value(options, "architectures/" + abi)).is_false()
	assert_str(config.get_value(options, "package/unique_name")).is_equal("dk.appcode.rts.dev")
	assert_bool(config.get_value(options, "package/signed")).is_true()
	for key: String in config.get_section_keys(options):
		assert_bool(key.begins_with("keystore/")).is_false()
	assert_str(config.get_value("preset.1", "custom_features")).is_empty()


func test_install_godot_fetches_the_release_template_only_on_request() -> void:
	var script: String = FileAccess.get_file_as_string(INSTALL_SCRIPT)
	assert_bool(script.contains("--android-release) WITH_ANDROID_RELEASE=1 ;;")).is_true()
	var sum: RegEx = RegEx.create_from_string(
		'ANDROID_RELEASE_SUM="[0-9a-f]{64}  android_release.apk"'
	)
	assert_object(sum.search(script)).is_not_null()
	assert_bool(script.contains('MEMBERS="$MEMBERS templates/android_release.apk"')).is_true()
	var debug_install: String = "Install Godot (editor, web and Android debug templates)"
	_assert_step(
		_job(DEBUG_JOB), debug_install, ["run: bash scripts/ci/install-godot.sh --android"]
	)


## All the first groups of a regex over a text, in order.
func _all(text: String, pattern: String) -> Array[String]:
	var found: Array[String] = []
	for hit: RegExMatch in RegEx.create_from_string("(?m)^\\s*" + pattern).search_all(text):
		found.append(hit.get_string(1))
	return found


func _job(header: String) -> PackedStringArray:
	var file: FileAccess = FileAccess.open(WORKFLOW, FileAccess.READ)
	assert_object(file).is_not_null()
	var lines: PackedStringArray = file.get_as_text().split("\n")
	var start: int = lines.find(header)
	assert_int(start).is_greater(-1)
	var end: int = start + 1
	while end < lines.size() and not (lines[end].begins_with("  ") and lines[end][2] != " "):
		end += 1
	return lines.slice(start + 1, end)


## One step of a job, stripped, without its blank and comment lines.
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


func _assert_order(job: PackedStringArray, step_names: Array) -> void:
	var last: int = -1
	for step_name: String in step_names:
		var at: int = job.find("      - name: " + step_name)
		assert_int(at).is_greater(last)
		last = at


func _assert_cache(job: PackedStringArray, step_name: String, key: String) -> void:
	var step: Array = Array(_step(job, step_name))
	assert_array(step).has_size(7)
	assert_str(step[1]).starts_with("uses: actions/cache@")
	step.remove_at(1)
	var wanted: Array = ["- name: " + step_name, "with:", "path: |"]
	wanted.append_array(["native/godot-cpp", "${{ env.SCONS_CACHE }}", key])
	assert_array(step).contains_exactly(wanted)
