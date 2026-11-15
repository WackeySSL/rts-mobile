extends GdUnitTestSuite
## Pins the vendored Poing AdMob editor part (plan row P410, addons/admob/PATCHES.md). Every
## vendored file has its SHA-256 in tests/project/admob_vendor_manifest.txt, so a change, an added
## file or a missing one fails here. The two local patches are named: the Godot 4.7.2 static
## initializer line, and the placeholder image paths of the mock ads. Both are checked in the text,
## so a re-vendoring that overwrote a patch fails with a message that says which one. The
## placeholder SVGs (art-director) are not in the manifest: the test only needs them to exist.

const ROOT: String = "res://addons/admob"
const MANIFEST: String = "res://tests/project/admob_vendor_manifest.txt"
const PATCHES: String = "res://addons/admob/PATCHES.md"

## Not vendored: fetched by scripts/ci/install-android-plugins.sh (git-ignored).
const SKIPPED_DIRS: Array[String] = ["android", "ios", "downloads"]
const UNPINNED_FILES: Array[String] = ["PATCHES.md"]

const EXPORT_PLUGIN_BASE: String = "res://addons/admob/internal/exporters/base_export_plugin.gd"
const UPSTREAM_KNOWN_LIBS: String = (
	"static var KNOWN_LIBS: Array[String] = " + '["ads"] + MEDIATION_LIBS'
)
const PATCHED_KNOWN_LIBS: String = 'static var KNOWN_LIBS := ["ads"] + MEDIATION_LIBS'

## Patch 2: the six mock scripts that name an image, and the five images they named.
const MOCK_DIR: String = "res://addons/admob/internal/mock"
const PATCHED_MOCKS: Array[String] = [
	"mock_ad_view_plugin.gd",
	"mock_app_open_ad_plugin.gd",
	"mock_interstitial_ad_plugin.gd",
	"mock_native_overlay_ad_plugin.gd",
	"mock_rewarded_ad_plugin.gd",
	"mock_rewarded_interstitial_ad_plugin.gd",
]
const UPSTREAM_IMAGES: Array[String] = [
	"flood_it_icon.svg",
	"google_play_icon.svg",
	"icon-120.png",
	"format-interstitial.svg",
	"format-rewarded-interstitial.svg",
]
const PLACEHOLDERS: Array[String] = [
	"placeholder_app_icon.svg",
	"placeholder_store_icon.svg",
	"placeholder_ad_logo.svg",
	"placeholder_format_interstitial.svg",
	"placeholder_format_rewarded.svg",
]


func test_every_vendored_file_matches_its_pinned_sha256() -> void:
	var pinned: Dictionary[String, String] = _manifest()
	assert_int(pinned.size()).is_greater(200)
	for path: String in pinned:
		(
			assert_bool(FileAccess.file_exists("res://" + path))
			. override_failure_message("%s is in the manifest but missing" % path)
			. is_true()
		)
		(
			assert_str(FileAccess.get_sha256("res://" + path))
			. override_failure_message(
				"%s changed (see addons/admob/PATCHES.md before updating the manifest)" % path
			)
			. is_equal(pinned[path])
		)


func test_no_file_is_vendored_without_a_pin() -> void:
	var pinned: Dictionary[String, String] = _manifest()
	var extra: Array[String] = []
	for path: String in _files(ROOT, true):
		var relative: String = path.trim_prefix("res://")
		if pinned.has(relative) or UNPINNED_FILES.has(path.get_file()):
			continue
		if path.get_file().begins_with("placeholder_") and path.get_base_dir() == ROOT + "/assets":
			continue
		extra.append(relative)
	assert_array(extra).override_failure_message("files without a pin: %s" % str(extra)).is_empty()


func test_godot_472_static_initializer_patch_is_applied() -> void:
	var text: String = FileAccess.get_file_as_string(EXPORT_PLUGIN_BASE)
	(
		assert_bool(text.contains(PATCHED_KNOWN_LIBS))
		. override_failure_message("base_export_plugin.gd lost patch 1 (KNOWN_LIBS without a type)")
		. is_true()
	)
	(
		assert_bool(text.contains(UPSTREAM_KNOWN_LIBS))
		. override_failure_message(
			"base_export_plugin.gd has the upstream v5.1.0 line, which fails in Godot 4.7.2"
		)
		. is_false()
	)
	_patches_names("internal/exporters/base_export_plugin.gd")


func test_mock_ads_name_our_placeholders_not_upstream_images() -> void:
	for file_name: String in PATCHED_MOCKS:
		var text: String = FileAccess.get_file_as_string(MOCK_DIR.path_join(file_name))
		for image: String in UPSTREAM_IMAGES:
			(
				assert_bool(text.contains("admob/assets/" + image))
				. override_failure_message(
					"%s still names the upstream image %s (patch 2)" % [file_name, image]
				)
				. is_false()
			)
		_patches_names(file_name)
	for file_name: String in _files(MOCK_DIR, false):
		var text: String = FileAccess.get_file_as_string(file_name)
		for image: String in UPSTREAM_IMAGES:
			(
				assert_bool(text.contains(image))
				. override_failure_message("%s names the upstream image %s" % [file_name, image])
				. is_false()
			)


func test_placeholder_images_exist_and_are_the_ones_the_mocks_name() -> void:
	var named: Dictionary[String, bool] = {}
	for file_name: String in PATCHED_MOCKS:
		var text: String = FileAccess.get_file_as_string(MOCK_DIR.path_join(file_name))
		var found: RegExMatch = null
		for hit: RegExMatch in RegEx.create_from_string(r"admob/assets/(\S+?\.svg)").search_all(
			text
		):
			found = hit
			named[hit.get_string(1)] = true
		(
			assert_object(found)
			. override_failure_message("%s names no placeholder" % file_name)
			. is_not_null()
		)
	assert_array(named.keys()).contains_exactly_in_any_order(PLACEHOLDERS)
	for placeholder: String in PLACEHOLDERS:
		(
			assert_bool(FileAccess.file_exists(ROOT + "/assets/" + placeholder))
			. override_failure_message(
				"%s is missing (art-director draws it, PATCHES.md lists its size)" % placeholder
			)
			. is_true()
		)


## The plugin stays disabled: enabled, its Android export plugin fails every non-Gradle export and a
## headless editor start downloads binaries without a pin (PATCHES.md, "Not enabled").
## export-android.sh --aab (P410b) enables it for one run only.
func test_plugin_is_not_enabled_in_project_settings() -> void:
	var text: String = FileAccess.get_file_as_string("res://project.godot")
	assert_bool(text.contains("addons/admob")).is_false()
	assert_bool(text.contains("[editor_plugins]")).is_false()


func test_licence_text_is_kept_under_docs_licenses() -> void:
	var kept: String = FileAccess.get_file_as_string(
		"res://docs/licenses/poing-godot-admob-5.1.0/LICENSE.txt"
	)
	assert_str(kept).is_equal(FileAccess.get_file_as_string(ROOT + "/LICENSE"))
	assert_str(kept).contains("MIT License")
	assert_str(kept).contains("Poing Studios")


func _patches_names(name: String) -> void:
	(
		assert_bool(FileAccess.get_file_as_string(PATCHES).contains(name))
		. override_failure_message(
			"addons/admob/PATCHES.md does not name the patched file %s" % name
		)
		. is_true()
	)


func _manifest() -> Dictionary[String, String]:
	var pinned: Dictionary[String, String] = {}
	for line: String in FileAccess.get_file_as_string(MANIFEST).split("\n", false):
		var parts: PackedStringArray = line.split(" ", false, 1)
		assert_int(parts.size()).is_equal(2)
		pinned[parts[1]] = parts[0]
	return pinned


## Every file under `dir`, recursively when `deep`; the fetched folders of the root are skipped.
func _files(dir: String, deep: bool) -> Array[String]:
	var found: Array[String] = []
	var access: DirAccess = DirAccess.open(dir)
	if access == null:
		return found
	for sub: String in access.get_directories():
		if deep and not (dir == ROOT and SKIPPED_DIRS.has(sub)):
			found.append_array(_files(dir.path_join(sub), true))
	for file_name: String in access.get_files():
		found.append(dir.path_join(file_name))
	found.sort()
	return found
