extends SceneTree
## The command line of `bash scripts/gen-intro.sh` (plan row P520): writes the intro layer SVGs
## under assets/art/svg/intro/ and the boot splash PNG assets/art/splash/boot_splash.png from the
## committed icon and brand SVGs, so a second run writes nothing.
##
##   gen-intro.sh            write the files that differ
##   gen-intro.sh --check    write nothing, name the files that differ and exit 4
##
## Exit: 0 done (also when nothing changed), 1 a source the splitter cannot split faithfully or a
## file that could not be written, 2 a wrong argument, 4 `--check` found a difference.


func _init() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var check: bool = args.size() == 1 and args[0] == "--check"
	if not args.is_empty() and not check:
		print("gen-intro: usage: gen-intro.sh [--check]")
		return 2
	var made: Dictionary = ArtIntro.generate()
	var problems: PackedStringArray = made["problems"]
	if not problems.is_empty():
		for problem: String in problems:
			push_error("gen-intro: " + problem)
		return 1
	var files: Dictionary[String, String] = made["files"]
	var stale: Array[String] = []
	for stem: String in files:
		var path: String = "%s%s.svg" % [ArtIntro.LAYER_DIR, stem]
		if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != files[stem]:
			stale.append(path)
			if not check and not _write_text(path, files[stem]):
				return 1
	var splash: Image = ArtIntro.splash()
	var old: Image = null
	if FileAccess.file_exists(ArtIntro.SPLASH_PATH):
		old = Image.load_from_file(ProjectSettings.globalize_path(ArtIntro.SPLASH_PATH))
	if old == null or old.get_data() != splash.get_data() or old.get_size() != splash.get_size():
		stale.append(ArtIntro.SPLASH_PATH)
		if not check and not _write_png(ArtIntro.SPLASH_PATH, splash):
			return 1
	for path: String in stale:
		print("gen-intro: %s: %s" % ["differs" if check else "written", path])
	print("gen-intro: %d files %s" % [stale.size(), "differ" if check else "written"])
	return 4 if check and not stale.is_empty() else 0


func _write_text(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null or not file.store_string(text):
		push_error("gen-intro: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	return true


func _write_png(path: String, image: Image) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error: Error = image.save_png(path)
	if error != OK:
		push_error("gen-intro: cannot write %s (error %d)" % [path, error])
		return false
	return true
