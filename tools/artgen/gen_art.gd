extends SceneTree
## The command line of `bash scripts/gen-art.sh` (ADR 0023 section 5): regenerates the SVG frames
## of the models and writes the files that differ.
##
##   --all          every model under assets/art/models
##   --model PATH   one model (project-relative or res://); may be repeated
##   --check        write nothing; exit 1 when a file is missing or differs
##
## Exit: 0 done (also when nothing changed), 1 a model is invalid or `--check` found a difference,
## 2 usage.

const USAGE: String = "usage: gen-art.sh (--all | --model PATH ...) [--check]"


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var paths: Array[String] = []
	var check: bool = false
	var i: int = 0
	while i < args.size():
		match args[i]:
			"--all":
				paths.append_array(ArtGen.model_paths())
			"--check":
				check = true
			"--model":
				i += 1
				if i >= args.size():
					return _usage()
				paths.append(args[i] if args[i].begins_with("res://") else "res://" + args[i])
			_:
				return _usage()
		i += 1
	if paths.is_empty():
		return _usage()
	var changed: int = 0
	var same: int = 0
	for path: String in paths:
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
			changed += 1
			if check:
				print("gen-art: stale or missing %s" % file)
			else:
				_write(file, files[file])
	print("gen-art: %d %s, %d unchanged" % [changed, "stale" if check else "written", same])
	return 1 if check and changed > 0 else 0


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _usage() -> int:
	print("gen-art: " + USAGE)
	return 2
