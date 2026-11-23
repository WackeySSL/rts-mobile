extends SceneTree
## The command line of `bash scripts/gen-music.sh` (plan row P506): renders every parameter file
## under tools/musgen/params to assets/audio/music/<id>.ogg through a temporary WAV and
## `ffmpeg -c:a libvorbis -q:a 3`.
##
##   gen-music.sh                 every parameter file
##   gen-music.sh --params PATH   one file (res://, user:// or a path from the project root)
##   gen-music.sh --out DIR       write under DIR instead of res://assets/audio/music
##   gen-music.sh --ffmpeg PATH   the encoder (default `ffmpeg`, or the MUSGEN_FFMPEG variable)
##
## Exit: 0 done, 1 a parameter file is invalid or the encoder failed, 2 a wrong argument or a
## parameter file that does not exist, 4 ffmpeg or its libvorbis encoder is missing.

const USAGE: String = "usage: gen-music.sh [--params PATH] [--out DIR] [--ffmpeg PATH]"
const PARAMS_DIR: String = "res://tools/musgen/params"


func _init() -> void:
	quit(run(OS.get_cmdline_user_args()))


func run(args: PackedStringArray) -> int:
	var options: Dictionary = _parse(args)
	if options.is_empty():
		print("gen-music: " + USAGE)
		return 2
	var paths: Array[String] = []
	var only: String = options["params"]
	if only != "":
		if not FileAccess.file_exists(only):
			print("gen-music: no parameter file %s" % only)
			return 2
		paths.append(only)
	else:
		for f: String in DirAccess.get_files_at(PARAMS_DIR):
			if f.ends_with(".tres"):
				paths.append(PARAMS_DIR + "/" + f)
		paths.sort()
	if not _encoder_ok(options["ffmpeg"]):
		return 4
	for path: String in paths:
		if not _render(path, options["out"], options["ffmpeg"]):
			return 1
	return 0


func _parse(args: PackedStringArray) -> Dictionary:
	var env: String = OS.get_environment("MUSGEN_FFMPEG")
	var options: Dictionary = {
		"params": "", "out": MusicParams.DEFAULT_ROOT, "ffmpeg": env if env != "" else "ffmpeg"
	}
	var i: int = 0
	while i < args.size():
		if args[i] == "--params" and i + 1 < args.size():
			i += 1
			options["params"] = args[i] if args[i].contains("://") else "res://" + args[i]
		elif args[i] == "--out" and i + 1 < args.size():
			i += 1
			options["out"] = args[i].trim_suffix("/")
		elif args[i] == "--ffmpeg" and i + 1 < args.size():
			i += 1
			options["ffmpeg"] = args[i]
		else:
			return {}
		i += 1
	return options


## True when `ffmpeg` runs and lists libvorbis; otherwise says what is missing.
func _encoder_ok(ffmpeg: String) -> bool:
	var output: Array = []
	if OS.execute(ffmpeg, ["-hide_banner", "-encoders"], output) != OK:
		print(
			"gen-music: FFMPEG MISSING: '%s' did not run (set --ffmpeg or MUSGEN_FFMPEG)" % ffmpeg
		)
		return false
	if not str(output[0]).contains("libvorbis"):
		print("gen-music: LIBVORBIS MISSING: '%s' has no libvorbis encoder" % ffmpeg)
		return false
	return true


func _render(path: String, root: String, ffmpeg: String) -> bool:
	var params: MusicParams = load(path) as MusicParams
	if params == null:
		print("gen-music: %s is not a MusicParams file" % path)
		return false
	var found: Array[String] = params.problems()
	if not found.is_empty():
		print("gen-music: %s is invalid: %s" % [path, "; ".join(found)])
		return false
	var wav: String = "user://musgen_%s.wav" % params.id
	if MusicSynth.to_stream(params).save_to_wav(wav) != OK:
		print("gen-music: cannot write %s" % wav)
		return false
	var out: String = params.output_path(root)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	# bitexact: no encoder tag and a fixed Ogg serial, so the same WAV gives the same file.
	var arguments: PackedStringArray = [
		"-y",
		"-loglevel",
		"error",
		"-i",
		ProjectSettings.globalize_path(wav),
		"-fflags",
		"+bitexact",
		"-flags:a",
		"+bitexact",
		"-map_metadata",
		"-1",
		"-c:a",
		"libvorbis",
		"-q:a",
		"3",
		ProjectSettings.globalize_path(out)
	]
	var status: int = OS.execute(ffmpeg, arguments)
	DirAccess.remove_absolute(wav)
	if status != 0:
		print("gen-music: ffmpeg failed (%d) for %s" % [status, path])
		return false
	print("gen-music: wrote " + out)
	return true
