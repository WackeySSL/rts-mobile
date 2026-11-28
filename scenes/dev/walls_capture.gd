extends Node
## Developer tool (plan row P656d2): PNG shots of the raised rock walls on Curlew Crags for the
## lead's look check, with the flag FORCED ON here and nowhere else. Not part of the game.
## The wall art is P656d4's and is not in the kit yet, so this tool draws PLACEHOLDER pieces in
## memory (flat-shaded prisms, one colour per face): they only show where the walls stand and how
## they sort, they are not the look and they are never saved into `assets/`.
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://scenes/dev/walls_capture.tscn \
##     -- --out=<dir>
## Writes `walls-<zoom>x.png` at zoom 1 and 2 (landscape 1280 x 720), the fog off: every wall lit.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const SCENARIO: String = "res://data/scenarios/skirmish_curlew_crags.tres"
const OUT_ARG: String = "--out="
const ZOOMS: Array[float] = [1.0, 2.0]
const SETTLE_FRAMES: int = 20
const TOP: Color = Color8(158, 150, 138)
const FACE_SE: Color = Color8(112, 104, 94)
const FACE_SW: Color = Color8(88, 82, 74)
const RIM: Color = Color8(58, 54, 50)

var _out: String = ""
var _main: Node
var _frames: int = 0
var _step: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			_out = arg.trim_prefix(OUT_ARG)
	if _out.is_empty():
		# Opened without --out (the scene scan instantiates every scene): it does nothing.
		print("walls_capture: pass --out=<dir> after -- to save the shots")
		set_process(false)
		return
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = _main.get_node("MatchRunner") as MatchRunner
	runner.scenario = load(SCENARIO)
	var walls: WallLayer = _main.get_node("WallLayer") as WallLayer
	walls.loader = Callable(self, "_placeholder_pieces")
	walls.fog = null  # Every wall lit: a look at the walls, not at the fog.
	walls.walls_enabled = true  # The one place the flag is forced on.
	add_child(_main)
	(_main.get_node("FogLayer") as FogLayer).visible = false


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return
	var camera: RtsCamera = _main.get_node("Camera") as RtsCamera
	var zoom: float = ZOOMS[_step]
	camera.zoom = Vector2(zoom, zoom)
	camera.centre_on(IsoProjection.cell_centre_px(28, 27))
	if _frames < SETTLE_FRAMES + 4 * (_step + 1):
		return
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(_out.path_join("walls-%dx.png" % int(zoom)))
	print("walls_capture: rows %d" % (_main.get_node("WallLayer") as WallLayer).row_count())
	_step += 1
	if _step >= ZOOMS.size():
		get_tree().quit()


## A placeholder prism per kit key, drawn pixel by pixel on the 128 x 136 canvas of A3.
func _placeholder_pieces(_look: StringName) -> Dictionary[StringName, Image]:
	var pieces: Dictionary[StringName, Image] = {}
	for key: StringName in WallKit.all_keys():
		var parts: PackedStringArray = String(key).split("/")
		pieces[key] = _draw(parts[1], parts[2])
	return pieces


func _draw(kind: String, mask: String) -> Image:
	var size: Vector2i = TerrainKitDef.WALL_CANVAS
	var image: Image = Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: int in size.y:
		for x: int in size.x:
			var colour: Color = _pixel(kind, mask, x, y)
			if colour.a > 0.0:
				image.set_pixel(x, y, colour)
	return image


func _pixel(kind: String, mask: String, x: int, y: int) -> Color:
	var in_top: bool = absf(x - 64.0) / 64.0 + absf(y - 40.0) / 32.0 <= 1.0
	if kind == "wall_top":
		return TOP if in_top else Color(0, 0, 0, 0)
	if kind == "wall_face":
		var se_edge: float = 72.0 - (x - 64.0) / 2.0
		var sw_edge: float = 72.0 - (64.0 - x) / 2.0
		if x >= 64 and mask != "sw" and y > se_edge and y <= se_edge + 64.0:
			return FACE_SE
		if x < 64 and mask != "se" and y > sw_edge and y <= sw_edge + 64.0:
			return FACE_SW
		return Color(0, 0, 0, 0)
	# A rim: a dark line along the back edges of the top diamond, 4 texels thick.
	var ne: float = 8.0 + (x - 64.0) / 2.0
	var nw: float = 8.0 + (64.0 - x) / 2.0
	var on_ne: bool = x >= 64 and y >= ne and y < ne + 4.0
	var on_nw: bool = x < 64 and y >= nw and y < nw + 4.0
	var show_ne: bool = mask in ["ne", "n"]
	var show_nw: bool = mask in ["nw", "n"]
	if mask == "inner_n":
		return RIM if absf(x - 64.0) + (y - 8.0) * 2.0 < 10.0 and y >= 8 else Color(0, 0, 0, 0)
	return RIM if (on_ne and show_ne) or (on_nw and show_nw) else Color(0, 0, 0, 0)
