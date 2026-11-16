extends GdUnitTestSuite
## Pins the vendored Poing AdMob editor part (plan row P410, addons/admob/PATCHES.md). Every
## vendored file has its SHA-256 in tests/project/admob_vendor_manifest.txt, so a change, an added
## file or a missing one fails here. The two local patches are named: the Godot 4.7.2 static
## initializer line, and the placeholder image paths of the mock ads. Both are checked in the text,
## so a re-vendoring that overwrote a patch fails with a message that says which one. The
## placeholder SVGs (art-director) are not in the manifest: the test only needs them to exist.

const ROOT: String = "res://addons/admob"
const MANIFEST: String = "res://tests/project/admob_vendor_manifest.txt"

## Not vendored: fetched by scripts/ci/install-android-plugins.sh (git-ignored).
const SKIPPED_DIRS: Array[String] = ["android", "ios", "downloads"]
const PATCHES_PATH: String = "res://addons/admob/PATCHES.md"
## Import outputs, git-ignored (*.translation in .gitignore), written next to the pinned CSV.
const IMPORT_OUTPUT_EXTENSION: String = "translation"
## Nothing of this kind is vendored (PATCHES.md: no upstream image, font or sound).
const DENIED_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "ogg", "wav", "ttf", "otf"]
const MANIFEST_LINE: String = r"^([0-9a-f]{64}) +(.+)$"
const MIN_PINNED_FILES: int = 200

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
	(
		assert_int(pinned.size())
		. override_failure_message(
			(
				"the manifest pins %d files, fewer than the %d it must hold"
				% [pinned.size(), MIN_PINNED_FILES]
			)
		)
		. is_greater(MIN_PINNED_FILES)
	)
	for path: String in pinned:
		(
			assert_bool(FileAccess.file_exists("res://" + path))
			. override_failure_message("%s is in the manifest but missing" % path)
			. is_true()
		)
		(
			assert_str(FileAccess.get_sha256("res://" + path))
			. override_failure_message(
				(
					(
						"%s changed. See addons/admob/PATCHES.md before updating the manifest; if only a"
						+ " .uid or .import file differs, re-import (godot --headless --path . --import)"
						+ " and regenerate the manifest (addons/THIRD_PARTY.md)"
					)
					% path
				)
			)
			. is_equal(pinned[path])
		)


func test_no_file_is_vendored_without_a_pin() -> void:
	var pinned: Dictionary[String, String] = _manifest()
	var exempt: Array[String] = [PATCHES_PATH]
	for placeholder: String in PLACEHOLDERS:
		exempt.append(ROOT + "/assets/" + placeholder)
		exempt.append(ROOT + "/assets/" + placeholder + ".import")
	var extra: Array[String] = []
	for path: String in _files(ROOT, true, true):
		if (
			pinned.has(path.trim_prefix("res://"))
			or exempt.has(path)
			or path.get_extension() == IMPORT_OUTPUT_EXTENSION
		):
			continue
		extra.append(path.trim_prefix("res://"))
	assert_array(extra).override_failure_message("files without a pin: %s" % str(extra)).is_empty()


func test_no_image_font_or_sound_is_vendored_beyond_the_placeholders() -> void:
	var denied: Array[String] = []
	for path: String in _files(ROOT, true, false):
		if DENIED_EXTENSIONS.has(path.get_extension().to_lower()):
			denied.append(path.trim_prefix("res://"))
	(
		assert_array(denied)
		. override_failure_message(
			"upstream images, fonts or sounds are not vendored (PATCHES.md): %s" % str(denied)
		)
		. is_empty()
	)


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
	for path: String in _files(MOCK_DIR, false, false):
		if path.get_extension() != "gd":
			continue
		var text: String = FileAccess.get_file_as_string(path)
		for image: String in UPSTREAM_IMAGES:
			(
				assert_bool(text.contains(image))
				. override_failure_message(
					"%s still names the upstream image %s (patch 2)" % [path.get_file(), image]
				)
				. is_false()
			)
	for file_name: String in PATCHED_MOCKS:
		_patches_names(file_name)


func test_placeholder_images_exist_and_are_the_ones_the_mocks_name() -> void:
	var named: Dictionary[String, bool] = {}
	var placeholder_path: RegEx = RegEx.create_from_string(r"admob/assets/(\S+?\.svg)")
	for file_name: String in PATCHED_MOCKS:
		var found_one: bool = false
		for hit: RegExMatch in placeholder_path.search_all(
			FileAccess.get_file_as_string(MOCK_DIR.path_join(file_name))
		):
			found_one = true
			named[hit.get_string(1)] = true
		(
			assert_bool(found_one)
			. override_failure_message("%s names no placeholder" % file_name)
			. is_true()
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


## PATCHES.md says how big each placeholder is; the SVG's own width and height must agree.
func test_placeholder_sizes_match_the_patches_table() -> void:
	var row: RegEx = RegEx.create_from_string(
		r"\| `[^`]+` \| `(placeholder_[a-z_]+\.svg)` \| (\d+) x (\d+) \|"
	)
	var root_tag: RegEx = RegEx.create_from_string(r"<svg\b[^>]*>")
	var width: RegEx = RegEx.create_from_string(r'\swidth="(\d+)(?:px)?"')
	var height: RegEx = RegEx.create_from_string(r'\sheight="(\d+)(?:px)?"')
	var rows: Array[RegExMatch] = row.search_all(FileAccess.get_file_as_string(PATCHES_PATH))
	(
		assert_int(rows.size())
		. override_failure_message(
			"PATCHES.md lists %d placeholder sizes, wanted %d" % [rows.size(), PLACEHOLDERS.size()]
		)
		. is_equal(PLACEHOLDERS.size())
	)
	for hit: RegExMatch in rows:
		var file_name: String = hit.get_string(1)
		var svg: RegExMatch = root_tag.search(
			FileAccess.get_file_as_string(ROOT + "/assets/" + file_name)
		)
		assert_object(svg).override_failure_message("%s has no <svg> tag" % file_name).is_not_null()
		var tag: String = svg.get_string()
		var w: RegExMatch = width.search(tag)
		var h: RegExMatch = height.search(tag)
		(
			assert_bool(w != null and h != null)
			. override_failure_message("%s has no width and height on its <svg> tag" % file_name)
			. is_true()
		)
		(
			assert_str("%s x %s" % [w.get_string(1), h.get_string(1)])
			. override_failure_message("%s is not the size PATCHES.md lists" % file_name)
			. is_equal("%s x %s" % [hit.get_string(2), hit.get_string(3)])
		)


## The plugin stays disabled: enabled, its Android export plugin fails every non-Gradle export and a
## headless editor start downloads binaries without a pin (PATCHES.md, "Not enabled").
## export-android.sh --aab (P410b) enables it for one run only.
func test_plugin_is_not_enabled_in_project_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	assert_int(config.load("res://project.godot")).is_equal(OK)
	var enabled: PackedStringArray = config.get_value(
		"editor_plugins", "enabled", PackedStringArray()
	)
	for entry: String in enabled:
		(
			assert_bool(entry.contains("addons/admob"))
			. override_failure_message(
				(
					"project.godot enables %s: the plugin stays disabled (PATCHES.md, Not enabled)"
					% entry
				)
			)
			. is_false()
		)


func test_licence_text_is_kept_under_docs_licenses() -> void:
	var kept: String = FileAccess.get_file_as_string(
		"res://docs/licenses/poing-godot-admob-5.1.0/LICENSE.txt"
	)
	(
		assert_str(kept)
		. override_failure_message("the kept licence differs from addons/admob/LICENSE")
		. is_equal(FileAccess.get_file_as_string(ROOT + "/LICENSE"))
	)
	assert_str(kept).override_failure_message("the kept licence is not the MIT text").contains(
		"MIT License"
	)
	(
		assert_str(kept)
		. override_failure_message("the kept licence does not name Poing Studios")
		. contains("Poing Studios")
	)


func _patches_names(name: String) -> void:
	(
		assert_bool(FileAccess.get_file_as_string(PATCHES_PATH).contains(name))
		. override_failure_message(
			"addons/admob/PATCHES.md does not name the patched file %s" % name
		)
		. is_true()
	)


## The manifest is plain `sha256sum` output: `sha256sum -c` accepts it (addons/THIRD_PARTY.md).
func _manifest() -> Dictionary[String, String]:
	var line_format: RegEx = RegEx.create_from_string(MANIFEST_LINE)
	var pinned: Dictionary[String, String] = {}
	var number: int = 0
	for line: String in FileAccess.get_file_as_string(MANIFEST).split("\n", false):
		number += 1
		var hit: RegExMatch = line_format.search(line)
		(
			assert_object(hit)
			. override_failure_message(
				"%s line %d is not sha256sum output: '%s'" % [MANIFEST, number, line]
			)
			. is_not_null()
		)
		if hit != null:
			pinned[hit.get_string(2)] = hit.get_string(1)
	return pinned


## Every file under `dir`, recursively when `deep`. `skip_fetched` leaves out the installer's
## fetched folders of the root (git-ignored).
func _files(dir: String, deep: bool, skip_fetched: bool) -> Array[String]:
	var found: Array[String] = []
	var access: DirAccess = DirAccess.open(dir)
	if access == null:
		return found
	for sub: String in access.get_directories():
		if deep and not (skip_fetched and dir == ROOT and SKIPPED_DIRS.has(sub)):
			found.append_array(_files(dir.path_join(sub), true, skip_fetched))
	for file_name: String in access.get_files():
		found.append(dir.path_join(file_name))
	found.sort()
	return found
