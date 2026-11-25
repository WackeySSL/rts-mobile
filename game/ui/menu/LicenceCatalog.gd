class_name LicenceCatalog
extends RefCounted
## The rows of the Licences screen (plan P529, ADR 0043 section 7, ADR 0046), in the order shown.
## Which build-dependent rows appear is a build-time fact read once by `from_build`: libc++ on
## Android, godot-cpp's MIT on every build that packs the kernels (the export feature tag
## `sim_kernels`, which exactly the presets packing `native/` set, and the editor), whether or not
## the library loads. The texts outside `assets/` are the copies under `res://assets/licenses/`
## (a test keeps them equal to `docs/licenses/`). Godot's own COPYRIGHT.txt and LICENSE.txt are
## packed too although the screen reads the Engine API: the copies stay byte-equal (the audit
## copy).

const KERNELS_TAG: String = "sim_kernels"
const LICENCES_DIR: String = "res://assets/licenses/"
const ASSET_LICENCE: String = "res://assets/LICENSE.md"
const CREDITS: String = "res://assets/CREDITS.md"
const FONT_DIR: String = "res://assets/art/fonts/"
const OFL_NAME: String = "OFL.txt"
## A family whose folder name does not capitalise into its name.
const FAMILY_NAMES: Dictionary[String, String] = {"ibm-plex-mono": "IBM Plex Mono"}
const LIBCXX: String = "llvm-libc++/LICENSE.TXT"
const GODOT_CPP: String = "godot-cpp-4.5-stable/LICENSE.md"
const POING_ADMOB: String = "poing-godot-admob-5.1.0/LICENSE.txt"
## TODO P411: the plugin's text file lands here with Phase 6's P411; the row shows once it exists.
const PLAY_BILLING: String = "godot-google-play-billing/LICENSE.txt"
const MISSING_TEXT: String = "The licence text of %s is not packed with this build yet."
const NO_CREDITS: String = "No asset under a Creative Commons Attribution licence is listed."
## The licence column of a CREDITS row that asks for a credit line.
const CC_BY: String = "(?i)CC[ -]BY"

var android: bool = false
var kernels: bool = false


static func from_build() -> LicenceCatalog:
	var catalog: LicenceCatalog = LicenceCatalog.new()
	catalog.android = OS.has_feature("android")
	catalog.kernels = OS.has_feature(KERNELS_TAG) or OS.has_feature("editor")
	return catalog


func build() -> Array[LicenceEntry]:
	var rows: Array[LicenceEntry] = []
	rows.append(
		LicenceEntry.make(tr("Game art and audio"), _read(ASSET_LICENCE, "the game's assets"))
	)
	rows.append(
		LicenceEntry.make(tr("Asset credits (CC BY)"), credit_lines(_read(CREDITS, "credits")))
	)
	rows.append(LicenceEntry.make(tr("Godot Engine"), Engine.get_license_text()))
	rows.append(
		LicenceEntry.make(tr("Godot copyright"), copyright_text(Engine.get_copyright_info()))
	)
	var info: Dictionary = Engine.get_license_info()
	var names: Array = info.keys()
	names.sort()
	for license_name: String in names:
		rows.append(LicenceEntry.make(license_name, str(info[license_name])))
	if android:
		rows.append(_packed(tr("LLVM libc++"), LIBCXX))
	if kernels:
		rows.append(_packed(tr("godot-cpp"), GODOT_CPP))
	for family: String in _font_folders():
		var family_name: String = FAMILY_NAMES.get(family, family.replace("-", " ").capitalize())
		var title: String = family_name + tr(" font")
		rows.append(LicenceEntry.make(title, _read(FONT_DIR + family + "/" + OFL_NAME, title)))
	rows.append(_packed(tr("Poing AdMob plugin"), POING_ADMOB))
	if FileAccess.file_exists(LICENCES_DIR + PLAY_BILLING):
		rows.append(_packed(tr("Google Play Billing plugin"), PLAY_BILLING))
	return rows


## The credit lines (file, author, licence, source) of every CREDITS.md table row whose licence
## names a CC BY licence; CC0 rows need none.
func credit_lines(credits_md: String) -> String:
	var by: RegEx = RegEx.create_from_string(CC_BY)
	var lines: PackedStringArray = []
	for line: String in credits_md.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells: PackedStringArray = line.split("|")
		if cells.size() < 6 or by.search(cells[4]) == null:
			continue
		var cell_text: Array[String] = []
		for index: int in [1, 2, 4, 3]:
			cell_text.append(cells[index].strip_edges())
		lines.append("\n".join(cell_text))
	return "\n\n".join(lines) if not lines.is_empty() else tr(NO_CREDITS)


## `Engine.get_copyright_info()` as text: each component, then its parts (files, copyright and
## licence).
func copyright_text(info: Array[Dictionary]) -> String:
	var blocks: PackedStringArray = []
	for component: Dictionary in info:
		var lines: PackedStringArray = [str(component.get("name", ""))]
		for part: Dictionary in component.get("parts", []):
			lines.append("Files: " + ", ".join(PackedStringArray(part.get("files", []))))
			lines.append("Copyright: " + "; ".join(PackedStringArray(part.get("copyright", []))))
			lines.append("Licence: " + str(part.get("license", "")))
		blocks.append("\n".join(lines))
	return "\n\n".join(blocks)


func _packed(title: String, file: String) -> LicenceEntry:
	return LicenceEntry.make(title, _read(LICENCES_DIR + file, title))


func _read(path: String, what: String) -> String:
	if not FileAccess.file_exists(path):
		return tr(MISSING_TEXT) % what
	return FileAccess.get_file_as_string(path)


func _font_folders() -> PackedStringArray:
	var folders: PackedStringArray = []
	for folder: String in DirAccess.get_directories_at(FONT_DIR):
		if FileAccess.file_exists(FONT_DIR + folder + "/" + OFL_NAME):
			folders.append(folder)
	folders.sort()
	return folders
