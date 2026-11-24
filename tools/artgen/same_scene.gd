extends SceneTree
## `bash scripts/same-scene.sh OUT.png`: writes the same-scene sheet and prints the bands it misses
## (ADR 0050 section 8). Exit 0 when the look holds, 1 when a band is missed, 2 on a wrong argument.


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not args[0].ends_with(".png"):
		print("same-scene: usage: same-scene.sh OUT.png")
		quit(2)
		return
	var bands: SameSceneBands = SameScene.load_bands()
	var err: Error = SameScene.sheet(bands).save_png(args[0])
	var missed: PackedStringArray = SameScene.audit(bands)
	for line: String in missed:
		print("same-scene: " + line)
	print("same-scene: %s (%s), %d band(s) missed" % [args[0], error_string(err), missed.size()])
	quit(1 if err != OK or not missed.is_empty() else 0)
