extends Node
## Developer tool (plan row P595): PNG shots of the tutorial guide for a PR. Not part of the game.
## It drives the real main scene to the state of one beat, as the chain sweep does (the sweep's
## `ChainRig` and the mid-play fixtures of `tests/ui/tutorial/support/`), at the six sizes of
## ADR 0015 (`tests/support/screen_sizes.gd`), and saves the viewport as a PNG at 1x:
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://scenes/dev/guide_shots.tscn \
##     -- --out=<dir>
## The shots (`specs()`): four beats at each of the six sizes, one more with Reduced effects on, and
## `support/mine` on the Web phone of 2400x912, where the truck stands under the card's Next and the
## hand drags it clear.
## It needs a checkout: the rig, the fixtures and gdUnit4's suite node (which the rig takes for its
## frames and its window) are loaded by path at run time, never preloaded, because the export
## filter leaves `tests/` and `addons/gdUnit4/` out. The PNGs go to `--out` and are never committed.

const RIG_PATH: String = "res://tests/ui/tutorial/support/chain_rig.gd"
const MIDPLAY_PATH: String = "res://tests/ui/tutorial/support/midplay_fixture.gd"
const SIZES_PATH: String = "res://tests/support/screen_sizes.gd"
const PROFILES_PATH: String = "res://tests/support/ui_profiles.gd"
const SUITE_PATH: String = "res://addons/gdUnit4/src/GdUnitTestSuite.gd"
const LESSON_DIR: String = "res://data/tutorial/"
const OUT_ARG: String = "--out="
const ONLY_ARG: String = "--only="  ## Shoots only the specs whose file name contains this.
## The beats shot at every size: the beat ("lesson/beat") and whether the ring is first walked on
## along the beat's lead-in to the beat's own step (the army selected before `attack`'s enemy).
const BEATS: Array[Dictionary] = [
	{"pair": "basics/attack", "advance": true},
	{"pair": "support/mine", "advance": false},
	{"pair": "basics/groups", "advance": false},
	{"pair": "air/tap-air", "advance": false},
]
## The extra with Reduced effects on, and the Web phone's profile of the drag shot.
const REDUCED_PAIR: String = "basics/attack"
const WEB_PHONE_SMALL: StringName = &"web_phone_small"
const MINE_PAIR: String = "support/mine"
## Frames the hand may take to come to a pose that shows (its loop rests between taps).
const HAND_FRAMES: int = 240
const SETTLE_FRAMES: int = 8
## The PR's budget for a shot; a shot over it is told, not failed (a lossless PNG of a large size
## is, and `quantize(256)` of a copy brings it under).
const PNG_LIMIT_BYTES: int = 300 * 1024

var _out: String = ""
var _only: String = ""
var _suite: Node
var _rig: RefCounted
var _midplay: GDScript
var _profiles: GDScript
var _failures: Array[String] = []


## Every shot: `file` (the PNG's name), `pair`, `size`, `reduced` (Reduced effects on) and
## `advance` (the lead-in is walked on to the beat's own step first).
static func specs() -> Array[Dictionary]:
	var sizes: GDScript = load(SIZES_PATH) as GDScript
	var profiles: GDScript = load(PROFILES_PATH) as GDScript
	var all: Array = sizes.get_script_constant_map()["ALL"]
	var list: Array[Dictionary] = []
	for beat: Dictionary in BEATS:
		for size: Vector2i in all:
			list.append(_spec(beat["pair"], size, false, beat["advance"]))
	list.append(_spec(REDUCED_PAIR, all[0], true, true))
	var web: Vector2i = profiles.by_name(WEB_PHONE_SMALL).window_size
	list.append(_spec(MINE_PAIR, web, false, false))
	return list


static func _spec(pair: String, size: Vector2i, reduced: bool, advance: bool) -> Dictionary:
	var file: String = (
		"%s-%dx%d%s.png" % [pair.replace("/", "-"), size.x, size.y, "-reduced" if reduced else ""]
	)
	return {"file": file, "pair": pair, "size": size, "reduced": reduced, "advance": advance}


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			_out = arg.trim_prefix(OUT_ARG)
		elif arg.begins_with(ONLY_ARG):
			_only = arg.trim_prefix(ONLY_ARG)
	if _out.is_empty():
		# Opened without --out (the scene scan instantiates every scene): it does nothing.
		print("guide_shots: pass --out=<dir> after -- to save the shots")
		return
	DirAccess.make_dir_recursive_absolute(_out)
	await _run()
	for line: String in _failures:
		printerr("guide_shots: ", line)
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _run() -> void:
	var suite_script: GDScript = load(SUITE_PATH) as GDScript
	_midplay = load(MIDPLAY_PATH) as GDScript
	_profiles = load(PROFILES_PATH) as GDScript
	if suite_script == null or _midplay == null or _profiles == null:
		_failures.append("the rig, the fixtures or gdUnit4 are missing: run from a checkout")
		return
	_suite = suite_script.new() as Node
	add_child(_suite)
	_rig = (load(RIG_PATH) as GDScript).new(_suite)
	var dir: String = "user://guide_shots_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	SaveService.set_path_override(dir.path_join("save.cfg"))
	BuildSidebar.set_slide_ms_override(0)
	for spec: Dictionary in specs():
		if _only.is_empty() or String(spec["file"]).contains(_only):
			await _shoot(spec)
	BuildSidebar.clear_slide_ms_override()
	SaveService.clear_path_override()
	UiScale.clear_override()
	for file_name: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	DirAccess.remove_absolute(dir)


## One shot: the match at the size, the fixture, the beat shown, the lead-in walked on when asked,
## the hand waited for, the viewport saved.
func _shoot(spec: Dictionary) -> void:
	var pair: String = spec["pair"]
	var lesson: TutorialLessonDef = load("%s%s.tres" % [LESSON_DIR, pair.get_slice("/", 0)])
	var beat: TutorialBeatDef = _beat_of(lesson, pair.get_slice("/", 1))
	var profile: UiMetrics = _rig.profile_of(spec["size"])
	if beat == null or profile == null:
		_failures.append("%s: no beat or no profile for %s" % [spec["file"], spec["size"]])
		return
	var scenario: ScenarioDef = lesson.scenario
	if _midplay.has(pair):
		scenario = _midplay.scenario_for(pair, scenario)
	await _rig.open(lesson, profile, scenario)
	_rig.mark.reduced = spec["reduced"]
	if _midplay.has(pair):
		var fixture: Object = _midplay.new(_suite, _rig.main, _rig.selection, _rig.sidebar)
		_rig.feed.state.close(_rig.feed.state.current)
		await fixture.prepare(pair)
		if not String(fixture.failure).is_empty():
			_failures.append("%s: fixture: %s" % [spec["file"], fixture.failure])
			_rig.close()
			return
		_rig.feed.state.close(_rig.feed.state.current)
	else:
		await _rig.enter({"unfold": HudState.Unfold.NONE, "tab": 0, "select": 0})
	await _rig.show(lesson, beat)
	var rounds: int = beat.lead_in.size()
	while spec["advance"] and rounds > 0 and beat.lead_in.has(_rig.director.active_target()):
		rounds -= 1
		if not await _rig.satisfy(_rig.director.active_target()):
			_failures.append("%s: a lead-in step cannot be met" % spec["file"])
			break
	if not await _hand_shown():
		print("guide_shots: WARNING ", spec["file"], " has no hand in it")
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _out.path_join(spec["file"])
	if image.save_png(path) != OK:
		_failures.append("%s: could not save %s" % [spec["file"], path])
	elif FileAccess.get_file_as_bytes(path).size() > PNG_LIMIT_BYTES:
		# Not a failure: a lossless 1x shot of a large size is over it; quantize to 256 colours.
		print("guide_shots: ", spec["file"], " is over ", PNG_LIMIT_BYTES, " bytes")
	print("guide_shots: ", spec["file"], " ", image.get_size())
	_rig.close()
	await get_tree().process_frame


## Waits for the ring to settle and for the hand to be on a pose that draws (its loop rests). A
## DRAG is shot in its still key pose (Reduced effects: the finger on its start point, the arrow
## showing): mid-travel the press ring sits on whatever the finger has reached. Returns whether a
## hand shows.
func _hand_shown() -> bool:
	for _frame: int in SETTLE_FRAMES:
		await get_tree().process_frame
	var hand: GestureHint = _rig.mark.find_child("GestureHint", true, false) as GestureHint
	if hand == null or not hand.visible:
		return false
	if _rig.mark.gesture_plan().kind == TutorialBeatDef.Gesture.DRAG:
		_rig.mark.reduced = true
		await get_tree().process_frame
		await get_tree().process_frame
		return hand.draw_pose() != null
	for _frame: int in HAND_FRAMES:
		var pose: GestureHint.Pose = hand.draw_pose()
		if pose != null and pose.alpha >= 1.0 and pose.pressed:
			return true
		await get_tree().process_frame
	return false


func _beat_of(lesson: TutorialLessonDef, id: String) -> TutorialBeatDef:
	for beat: TutorialBeatDef in lesson.beats:
		if String(beat.id) == id:
			return beat
	return null
