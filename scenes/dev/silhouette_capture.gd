extends Node
## Developer tool (plan row P656d3): PNG shots of the raised walls with unit silhouettes on Curlew
## Crags, for the look gate. The flag is FORCED ON here, the fog is off and every enemy shows, and
## four tanks are put round one wall: an own and an enemy tank behind it (their silhouettes show
## through it) and an own and an enemy tank in front of it. Not part of the game.
##   xvfb-run -a -s "-screen 0 1400x1400x24" godot --rendering-driver opengl3 --path . \
##     res://scenes/dev/silhouette_capture.tscn -- --out=<dir>
## Writes `sil-<landscape|portrait>-<zoom>x.png` for zoom 0.75 and 2.0.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const SCENARIO: String = "res://data/scenarios/skirmish_curlew_crags.tres"
const OUT_ARG: String = "--out="
const SIZES: Dictionary[String, Vector2i] = {
	"landscape": Vector2i(1280, 720),
	"portrait": Vector2i(720, 1280),
}
const ZOOMS: Array[float] = [0.75, 2.0]
const SETTLE_FRAMES: int = 24

var _out: String = ""
var _main: Node
var _frames: int = 0
var _step: int = 0
var _wall: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			_out = arg.trim_prefix(OUT_ARG)
	if _out.is_empty():
		print("silhouette_capture: pass --out=<dir> after -- to save the shots")
		set_process(false)
		return
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = _main.get_node("MatchRunner") as MatchRunner
	runner.scenario = load(SCENARIO)
	var walls: WallLayer = _main.get_node("WallLayer") as WallLayer
	walls.fog = null  # Every wall lit: a look at the walls and the silhouettes, not at the fog.
	walls.walls_enabled = true  # The one place the flag is forced on here.
	(_main.get_node("UnitLayer") as UnitLayer).reveal_enemies = true
	add_child(_main)
	(_main.get_node("FogLayer") as FogLayer).visible = false
	runner.paused = true


@warning_ignore("integer_division")
func _process(_delta: float) -> void:
	var runner: MatchRunner = _main.get_node("MatchRunner") as MatchRunner
	var walls: WallLayer = _main.get_node("WallLayer") as WallLayer
	if _wall.x < 0:
		if walls.row_count() > 0:
			_wall = _find_wall(runner.snapshot, walls)
			_place(runner.snapshot)
		return
	var names: Array = SIZES.keys()
	var size_name: String = names[_step / ZOOMS.size()]
	var zoom: float = ZOOMS[_step % ZOOMS.size()]
	if _frames == 0:
		get_window().size = SIZES[size_name]
	_frames += 1
	var camera: RtsCamera = _main.get_node("Camera") as RtsCamera
	camera.zoom = Vector2(zoom, zoom)
	camera.centre_on(IsoProjection.cell_centre_px(_wall.x, _wall.y) + Vector2(0.0, -20.0))
	if _frames < SETTLE_FRAMES:
		return
	var path: String = _out.path_join("sil-%s-%sx.png" % [size_name, str(zoom)])
	get_viewport().get_texture().get_image().save_png(path)
	print("silhouette_capture: %s (wall %s)" % [path, _wall])
	_step += 1
	_frames = 0
	if _step >= SIZES.size() * ZOOMS.size():
		get_tree().quit()


## A wall cell with open ground in its three front neighbours and a free cell behind, near the
## middle of the map.
@warning_ignore("integer_division")
func _find_wall(snap: MatchSnapshot, walls: WallLayer) -> Vector2i:
	var cols: int = snap.map_cols
	var best: Vector2i = Vector2i(-1, -1)
	var best_gap: int = 1 << 30
	for cell: int in snap.terrain.size():
		var col: int = cell % cols
		var row: int = cell / cols
		if (
			col < 3
			or row < 3
			or col > cols - 4
			or row > snap.map_rows - 4
			or not walls.is_wall(cell)
		):
			continue
		var open: bool = true
		for offset: Vector2i in [
			Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(0, -1)
		]:
			open = open and not walls.is_wall(cell + offset.y * cols + offset.x)
		var gap: int = absi(col - cols / 2) + absi(row - snap.map_rows / 2)
		if open and gap < best_gap:
			best_gap = gap
			best = Vector2i(col, row)
	return best


## Own tank 1 and enemy tank 1 behind the wall, one more of each in front, on the ground.
func _place(snap: MatchSnapshot) -> void:
	var player: int = FogLayer.local_player_of(_main.get_node("MatchRunner") as MatchRunner)
	var spots: Array[Vector2i] = [
		Vector2i(_wall.x - 1, _wall.y),
		Vector2i(_wall.x, _wall.y - 1),
		Vector2i(_wall.x, _wall.y + 1),
		Vector2i(_wall.x + 1, _wall.y),
	]
	var own: Array[int] = []
	var enemy: Array[int] = []
	var layer: UnitLayer = _main.get_node("UnitLayer") as UnitLayer
	for row: int in snap.owner.size():
		if layer.rig(row) == null:
			continue
		(own if snap.owner[row] == player else enemy).append(row)
	var rows: Array[int] = [own[0], enemy[0], own[1], enemy[1]]
	for at: int in rows.size():
		snap.pos_x[rows[at]] = spots[at].x * 1000 + 500
		snap.pos_y[rows[at]] = spots[at].y * 1000 + 500
		snap.prev_pos_x[rows[at]] = snap.pos_x[rows[at]]
		snap.prev_pos_y[rows[at]] = snap.pos_y[rows[at]]
	snap.tick += 1
