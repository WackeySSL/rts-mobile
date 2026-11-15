extends SceneTree
## The command line of `bash scripts/gen-sfx.sh` (plan row P507): renders every parameter file
## under tools/sfxgen/params to assets/audio/sfx/<family>/<id>.wav.
##
##   gen-sfx.sh                 every parameter file
##   gen-sfx.sh --params PATH   one file (res://, user:// or a path from the project root)
##   gen-sfx.sh --out DIR       write under DIR instead of res://assets/audio/sfx (tests use it)
##   gen-sfx.sh --check         writes nothing, names the WAVs that differ and exits 4
##
## Exit: 0 done (also when nothing changed, or `--check` found nothing), 1 a parameter file is
## invalid or a write failed, 2 a wrong argument or a parameter file that does not exist,
## 4 `--check` found a difference.

const USAGE: String = "usage: gen-sfx.sh [--params PATH] [--out DIR] [--check]"
const PARAMS_DIR: String = "res://tools/sfxgen/params"


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var options: Dictionary = _parse(args)
	if options.is_empty():
		print("gen-sfx: " + USAGE)
		return 2
	var only: String = options["params"]
	var paths: Array[String] = []
	if only != "":
		if not FileAccess.file_exists(only):
			print("gen-sfx: no parameter file %s" % only)
			return 2
		paths.append(only)
	elif DirAccess.dir_exists_absolute(PARAMS_DIR):
		for f: String in DirAccess.get_files_at(PARAMS_DIR):
			if f.ends_with(".tres"):
				paths.append(PARAMS_DIR + "/" + f)
		paths.sort()
	var stale: int = 0
	for path: String in paths:
		var code: int = _render(path, options["out"], options["check"])
		if code == 1:
			return 1
		if code == 4:
			stale += 1
	return 4 if stale > 0 else 0


## The options, or an empty dictionary for a wrong argument.
func _parse(args: PackedStringArray) -> Dictionary:
	var options: Dictionary = {"params": "", "out": SfxParams.DEFAULT_ROOT, "check": false}
	var i: int = 0
	while i < args.size():
		if args[i] == "--check":
			options["check"] = true
		elif args[i] == "--params" and i + 1 < args.size():
			i += 1
			options["params"] = args[i] if args[i].contains("://") else "res://" + args[i]
		elif args[i] == "--out" and i + 1 < args.size():
			i += 1
			options["out"] = args[i].trim_suffix("/")
		else:
			return {}
		i += 1
	return options


## The valid parameter file at `path`, or null after naming what is wrong.
func _load(path: String) -> SfxParams:
	var params: SfxParams = load(path) as SfxParams
	if params == null:
		print("gen-sfx: %s is not an SfxParams file" % path)
		return null
	var found: Array[String] = SfxSynth.problems(params)
	if not found.is_empty():
		print("gen-sfx: %s is invalid: %s" % [path, "; ".join(found)])
		return null
	return params


## 0 up to date or written, 1 invalid or failed, 4 differs (`check` only).
func _render(path: String, root: String, check: bool) -> int:
	var params: SfxParams = _load(path)
	if params == null:
		return 1
	var bytes: PackedByteArray = SfxSynth.wav_bytes(params)
	if bytes.is_empty():
		print("gen-sfx: cannot render %s" % path)
		return 1
	var out: String = params.output_path(root)
	if FileAccess.file_exists(out) and FileAccess.get_file_as_bytes(out) == bytes:
		return 0
	if check:
		print("gen-sfx: differs: " + out)
		return 4
	var err: Error = SfxSynth.write_bytes(bytes, out)
	if err != OK:
		print("gen-sfx: cannot write %s (error %d)" % [out, err])
		return 1
	print("gen-sfx: wrote " + out)
	return 0
