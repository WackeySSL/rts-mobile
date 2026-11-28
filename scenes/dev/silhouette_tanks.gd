extends Node
## Developer tool (plan row P656d3): a close shot at zoom 2 of tanks behind and in front of a thick
## rock wall on the controls_test map, for the look gate. A 3 x 3 block of rock is made on the
## snapshot, an own and an enemy tank stand behind it (their silhouettes show through it, the enemy
## because the fog is off) and one of each in front. `--walls=off` is the same frame with the flag
## off. `--look=a` is the first silhouette look (A), the default is B. Not part of the game.
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://scenes/dev/silhouette_tanks.tscn \
##     -- --out=<dir> [--walls=off]
## Writes `tanks-walls-A.png`, `tanks-walls-B.png` or `tanks-walls-off.png`.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const SCENARIO: String = "res://data/scenarios/controls_test.tres"
const BLOCK_FROM: Vector2i = Vector2i(20, 20)
const BLOCK_TO: Vector2i = Vector2i(22, 22)
## Rows of the controls_test tanks (own 0 and 1, enemy 30 and 31) and where they stand.
const SPOTS: Dictionary[int, Vector2i] = {
	0: Vector2i(19, 21),  # Own, behind the block.
	30: Vector2i(21, 19),  # Enemy, behind it.
	1: Vector2i(24, 22),  # Own, in front.
	31: Vector2i(22, 24),  # Enemy, in front.
}
const SETTLE_FRAMES: int = 30

var _out: String = ""
var _on: bool = true
var _look: int = WallCover.LOOK_B
var _main: Node
var _frames: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--walls=off":
			_on = false
		elif arg == "--look=a":
			_look = WallCover.LOOK_A
	if _out.is_empty():
		print("silhouette_tanks: pass --out=<dir> after -- to save the shot")
		set_process(false)
		return
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	var walls: WallLayer = _main.get_node("WallLayer") as WallLayer
	walls.fog = null
	walls.walls_enabled = _on
	(_main.get_node("MatchRunner") as MatchRunner).scenario = load(SCENARIO)
	(_main.get_node("UnitLayer") as UnitLayer).reveal_enemies = true
	(_main.get_node("WorldSort") as WorldSort).silhouette_look = _look
	add_child(_main)
	(_main.get_node("FogLayer") as FogLayer).visible = false
	(_main.get_node("MatchRunner") as MatchRunner).paused = true


func _process(_delta: float) -> void:
	_frames += 1
	var runner: MatchRunner = _main.get_node("MatchRunner") as MatchRunner
	if _frames == 3:
		_build(runner.snapshot)
	var camera: RtsCamera = _main.get_node("Camera") as RtsCamera
	camera.zoom = Vector2(2.0, 2.0)
	camera.centre_on(IsoProjection.cell_centre_px(21, 21) + Vector2(0.0, -10.0))
	if _frames < SETTLE_FRAMES:
		return
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = _out.path_join(
		"tanks-walls-%s.png" % (("A" if _look == WallCover.LOOK_A else "B") if _on else "off")
	)
	image.save_png(path)
	print("silhouette_tanks: %s" % path)
	get_tree().quit()


## The rock block on the snapshot's terrain (the flag off draws it as flat rock) and the tanks.
func _build(snap: MatchSnapshot) -> void:
	var rock: int = snap.terrain_ids.find(&"rock")
	for row: int in range(BLOCK_FROM.y, BLOCK_TO.y + 1):
		for col: int in range(BLOCK_FROM.x, BLOCK_TO.x + 1):
			snap.terrain[row * snap.map_cols + col] = rock
	snap.map_version += 1
	for row: int in SPOTS:
		snap.pos_x[row] = SPOTS[row].x * 1000 + 500
		snap.pos_y[row] = SPOTS[row].y * 1000 + 500
		snap.prev_pos_x[row] = snap.pos_x[row]
		snap.prev_pos_y[row] = snap.pos_y[row]
	snap.tick += 1
