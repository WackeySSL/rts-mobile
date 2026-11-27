class_name ArtManifest
extends Resource
## The pre-render manifest (ADR 0053 section 5): one sorted line per committed PNG, so that a
## test can tell a PNG that moved, a missing one and a model that changed without a re-bake. The
## file is written as text by `save`, so rewriting the same inputs gives the same bytes.
## A line is `path|sha256|bytes|WxH|source=sha256;source=sha256|exposure`.

const PATH: String = "res://assets/art/prerender/manifest.tres"
const OWNED: PackedStringArray = ["res://assets/art/iso", "res://assets/art/terrain"]
## ADR 0050 section 1, by footprint: 3x3, 2x2, 1x1.
const FRAME_BYTES: Dictionary[int, int] = {3: 128 * 1024, 2: 80 * 1024, 1: 48 * 1024}

@export var stamp: String = ""  ## The renderer line and the Mesa version of the bake.
@export var entries: PackedStringArray = PackedStringArray()
var kit_dir: String = "res://assets/art/terrain"  ## The kit's folder; its files total at most
var kit_bytes_max: int = 5 * 1024 * 1024  ## 5 MB (ADR 0053 section 7).


static func read(path: String = PATH) -> ArtManifest:
	var found: ArtManifest = load(path) as ArtManifest if ResourceLoader.exists(path) else null
	return found if found != null else ArtManifest.new()


## Lists `path` from the file on disk; `sources` are the model files its bake read.
func add(path: String, sources: PackedStringArray, exposure: float) -> void:
	var image: Image = Image.new()
	image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	var from: PackedStringArray = PackedStringArray()
	for source: String in sources:
		from.append("%s=%s" % [source, FileAccess.get_sha256(source)])
	from.sort()
	var line: String = (
		"%s|%s|%d|%dx%d|%s|%s"
		% [
			path,
			FileAccess.get_sha256(path),
			FileAccess.get_file_as_bytes(path).size(),
			image.get_width(),
			image.get_height(),
			";".join(from),
			str(exposure)
		]
	)
	var kept: PackedStringArray = PackedStringArray()
	for old: String in entries:
		if not old.begins_with(path + "|"):
			kept.append(old)
	kept.append(line)
	kept.sort()
	entries = kept


func save(path: String = PATH) -> void:
	var text: String = (
		'[gd_resource type="Resource" script_class="ArtManifest" format=3]\n\n'
		+ '[ext_resource type="Script" path="res://tools/prerender/ArtManifest.gd" id="1"]\n\n'
		+ (
			'[resource]\nscript = ExtResource("1")\nstamp = %s\nentries = %s\n'
			% [var_to_str(stamp), var_to_str(entries)]
		)
	)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


## What is wrong, one line each: a PNG or a source that differs from its line, a PNG under
## `OWNED` that no line lists, a frame over its byte budget or off its sheet's canvas, a kit over
## its total. `sheets` maps a `*_sheet.tres` path to an `IsoSheetDef`.
func problems(owned: PackedStringArray, sheets: Callable) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var listed: PackedStringArray = PackedStringArray()
	var kit_bytes: int = 0
	for line: String in entries:
		var f: PackedStringArray = line.split("|")
		var path: String = f[0]
		listed.append(path)
		if not FileAccess.file_exists(path):
			found.append("%s: file is missing" % path)
			continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var image: Image = Image.new()
		image.load_png_from_buffer(bytes)
		if FileAccess.get_sha256(path) != f[1] or str(bytes.size()) != f[2]:
			found.append("%s: hash or bytes differ from the manifest" % path)
		if "%dx%d" % [image.get_width(), image.get_height()] != f[3]:
			found.append("%s: size differs from the manifest" % path)
		if path.begins_with(kit_dir):
			kit_bytes += bytes.size()
		var sheet: IsoSheetDef = null
		for item: String in f[4].split(";", false):
			var source: PackedStringArray = item.split("=")
			if FileAccess.get_sha256(source[0]) != source[1]:
				var id: String = source[0].get_file().get_basename().trim_suffix("_detail")
				found.append("%s: source %s moved without a re-bake (%s)" % [id, source[0], path])
			if source[0].ends_with("_sheet.tres"):
				sheet = sheets.call(source[0]) as IsoSheetDef
		if sheet != null:
			found.append_array(_frame_problems(path, bytes.size(), image.get_size(), sheet))
	if kit_bytes > kit_bytes_max:
		found.append("the kit is %d bytes, over %d" % [kit_bytes, kit_bytes_max])
	for dir: String in owned:
		for path: String in _pngs(dir):
			if path not in listed:
				found.append("%s: not in the manifest" % path)
	return found


func _frame_problems(
	path: String, bytes: int, size: Vector2i, sheet: IsoSheetDef
) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var name: String = path.get_file().get_basename()
	if FRAME_BYTES.has(sheet.footprint) and bytes > FRAME_BYTES[sheet.footprint]:
		found.append(
			"%s: %d bytes, over the budget of %d" % [path, bytes, FRAME_BYTES[sheet.footprint]]
		)
	for part: String in sheet.parts:
		var stem: String = "%s_%s" % [sheet.art_id, part]
		if name == stem or name.begins_with(stem + "_d") or name.begins_with(stem + "_f"):
			var canvas: Vector2 = Vector2(sheet.frame_size(StringName(part)))
			var want: Vector2i = Vector2i((canvas * IsoAtlas.part_factor(StringName(part))).round())
			if size != want:
				found.append(
					(
						"%s: %s texels, the sheet's %s canvas at its factor is %s"
						% [path, size, part, want]
					)
				)
	return found


static func _pngs(dir: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return found
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".png"):
			found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		found.append_array(_pngs(dir.path_join(sub)))
	return found
