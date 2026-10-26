extends SceneTree
## The command line of `bash scripts/gen-art.sh` (ADR 0023 section 5): regenerates the SVG frames of
## every model under assets/art/models and writes the files that differ, so a second run writes
## nothing. It takes no argument; plan row P99b adds `--model PATH` (one model) and `--check`
## (write nothing, fail on a difference), as the plan's split trigger of P99 says.
##
## Exit: 0 done (also when nothing changed), 1 a model is invalid, 2 an argument was given.

const USAGE: String = "usage: gen-art.sh (takes no argument)"


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	if not args.is_empty():
		print("gen-art: " + USAGE)
		return 2
	var written: int = 0
	var same: int = 0
	for path: String in ArtGen.model_paths():
		var model: ArtModel = load(path) as ArtModel
		if model == null:
			print("gen-art: %s is not an ArtModel" % path)
			return 1
		var problems: PackedStringArray = model.problems()
		if not problems.is_empty():
			print("gen-art: %s\n  %s" % [path, "\n  ".join(problems)])
			return 1
		var files: Dictionary[String, String] = ArtGen.build(model)
		for file: String in files:
			if FileAccess.file_exists(file) and FileAccess.get_file_as_string(file) == files[file]:
				same += 1
				continue
			written += 1
			_write(file, files[file])
	print("gen-art: %d written, %d unchanged" % [written, same])
	return 0


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
