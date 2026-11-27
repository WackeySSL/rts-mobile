extends SceneTree
## Writes manifest lines (ADR 0053 section 5), run by `scripts/prerender.sh` under xvfb after the
## post and the copy into the repo. `--mesa V` is the Mesa version of the image.
##   --png res://a.png,res://b.png  --sources res://x_detail.tres,res://x_sheet.tres,..
##   [--exposure 1.0]    lists the PNGs; without --png it only stamps the manifest
##   --stamp-only        prints `prerender-stamp: <renderer line> / Mesa <V>` and a
##                       `prerender-entry:` line per listed PNG; writes nothing
## Exit 0 done, 1 the manifest holds PNGs of another stamp (a re-bake row re-renders them all).

const BakeModel: GDScript = preload("res://tools/prerender/bake_model.gd")


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var opts: Dictionary = {"mesa": "", "png": "", "sources": "", "exposure": "1.0"}
	for i: int in args.size():
		if args[i].begins_with("--"):
			var flag: bool = i + 1 >= args.size() or args[i + 1].begins_with("--")
			opts[args[i].trim_prefix("--")] = "" if flag else args[i + 1]
	var stamp: String = "%s / Mesa %s" % [BakeModel.stamp(), opts.mesa]
	if opts.has("stamp-only"):
		print("prerender-stamp: ", stamp)
		for line: String in ArtManifest.read().entries:
			print("prerender-entry: ", line)
		quit(0)
		return
	var manifest: ArtManifest = ArtManifest.read()
	if not manifest.entries.is_empty() and manifest.stamp != stamp:
		printerr(
			(
				"write_manifest: the manifest is stamped '%s', this image is '%s'"
				% [manifest.stamp, stamp]
			)
		)
		quit(1)
		return
	manifest.stamp = stamp
	for png: String in String(opts.png).split(",", false):
		manifest.add(png, String(opts.sources).split(",", false), float(opts.exposure))
	manifest.save()
	quit(0)
