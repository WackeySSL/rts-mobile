extends SceneTree
## The command line of `bash scripts/gen-sfx.sh` (plan row P507): renders every parameter file
## under tools/sfxgen/params to assets/audio/sfx/<family>/<id>.wav.
##
##   gen-sfx.sh                 every parameter file
##   gen-sfx.sh --params PATH   one file (res:// or a path from the project root)
##   gen-sfx.sh --check         writes nothing, names the WAVs that differ and exits 4
##
## Exit: 0 done, 1 a parameter file is invalid or a write failed, 2 a wrong argument, 4 `--check`
## found a difference.

const USAGE: String = "usage: gen-sfx.sh [--params PATH] [--check]"
const PARAMS_DIR: String = "res://tools/sfxgen/params"


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var only: String = ""
	var check: bool = false
	var i: int = 0
	while i < args.size():
		if args[i] == "--check":
			check = true
		elif args[i] == "--params" and i + 1 < args.size():
			i += 1
			only = args[i]
		else:
			print("gen-sfx: " + USAGE)
			return 2
		i += 1
	var paths: Array[String] = []
	if only != "":
		paths.append(only)
	elif DirAccess.dir_exists_absolute(PARAMS_DIR):
		for f: String in DirAccess.get_files_at(PARAMS_DIR):
			if f.ends_with(".tres"):
				paths.append(PARAMS_DIR + "/" + f)
		paths.sort()
	var stale: int = 0
	for path: String in paths:
		var params: SfxParams = load(path) as SfxParams
		if params == null or params.id == &"":
			print("gen-sfx: %s is not a valid SfxParams file" % path)
			return 1
		var out: String = params.output_path()
		var same: bool = (
			FileAccess.file_exists(out)
			and FileAccess.get_file_as_bytes(out) == SfxSynth.file_bytes(params)
		)
		if same:
			continue
		if check:
			print("gen-sfx: differs: " + out)
			stale += 1
			continue
		var err: Error = SfxSynth.write(params, out)
		if err != OK:
			print("gen-sfx: cannot write %s (error %d)" % [out, err])
			return 1
		print("gen-sfx: wrote " + out)
	return 4 if stale > 0 else 0
