extends SceneTree
## The command line of `bash scripts/gen-art.sh` (ADR 0023 section 5): regenerates the SVG frames,
## sheets and item cards of the models under assets/art/models and `assets/art/iso/index.tres`,
## and writes the files that differ, so a second run writes nothing.
##
##   gen-art.sh                  every model (`--all` says it too)
##   gen-art.sh --model PATH     one model (any `.tres` ArtModel): `res://...`, a path from the
##                               project root or an absolute one
##   gen-art.sh --check          writes nothing, names the files that differ and exits 4
##
## Exit: 0 done (also when nothing changed, or `--check` found nothing), 1 a model is invalid,
## 2 a wrong argument or a model file that does not exist, 4 `--check` found a difference.

const USAGE: String = "usage: gen-art.sh [--all | --model PATH] [--check]"
const SHOWN: int = 20  ## Files a `--check` names before it says how many more.


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var options: Dictionary = _parse(args)
	if options.is_empty():
		print("gen-art: " + USAGE)
		return 2
	var paths: Array[String] = ArtGen.model_paths()
	var only: String = options["model"]
	if only != "":
		if not FileAccess.file_exists(only):
			print("gen-art: no model file %s" % only)
			return 2
		paths = [only]
	var files: Dictionary[String, String] = {}
	for path: String in paths:
		if not _add(path, files):
			return 1
	files[IsoIndex.PATH] = ArtGen.index_text()
	var stale: Array[String] = ArtGen.stale(files)
	var check: bool = options["check"]
	if check:
		for path: String in stale.slice(0, SHOWN):
			print("gen-art: differs: " + path)
	else:
		for path: String in stale:
			_write(path, files[path])
	var verb: String = "differ" if check else "written"
	print("gen-art: %d %s, %d unchanged" % [stale.size(), verb, files.size() - stale.size()])
	return 4 if check and not stale.is_empty() else 0


## The options `{check, model}` of the arguments, `{}` when one is wrong.
func _parse(args: PackedStringArray) -> Dictionary:
	var check: bool = false
	var all: bool = false
	var only: String = ""
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--check":
				check = true
			"--all":
				all = true
			"--model":
				i += 1
				if i >= args.size() or only != "":
					return {}
				only = _model_path(args[i])
			_:
				return {}
		i += 1
	return {} if all and only != "" else {"check": check, "model": only}


## Adds the files of the model at `path` to `files`; false (and says why) when it is not valid.
func _add(path: String, files: Dictionary[String, String]) -> bool:
	var model: ArtModel = load(path) as ArtModel
	if model == null:
		print("gen-art: %s is not an ArtModel" % path)
		return false
	var problems: PackedStringArray = model.problems()
	if not problems.is_empty():
		print("gen-art: %s\n  %s" % [path, "\n  ".join(problems)])
		return false
	files.merge(ArtGen.build(model))
	return true


## `res://assets/...` as it is, an absolute path of the project made one, a path from its root too.
func _model_path(argument: String) -> String:
	var path: String = ProjectSettings.localize_path(argument)
	return path if path.is_absolute_path() else "res://" + path.trim_prefix("./")


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
