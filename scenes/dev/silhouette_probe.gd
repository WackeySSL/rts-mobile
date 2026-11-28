extends Node
## Developer tool (plan row P656d3): renders `silhouette.gdshader` over a crafted wall grid and
## compares every pixel's coverage with the GDScript twin `WallCover.covered`, for two unit ground
## heights, and checks the x-ray colours (a team texel keeps its hue, any other is the body colour).
## The shader's output is not headless; this is the render test, to run under a real renderer:
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://scenes/dev/silhouette_probe.tscn
## Prints `silhouette_probe: PASS` or `FAIL` and quits with code 0 or 1. A pixel whose centre lies
## within a hair of a cell edge may round either way: up to MISMATCH_MAX_PER_MILLE per thousand of
## the pixels may differ. Opened without a real renderer (the scene scan) it does nothing.

const GRID: Vector2i = Vector2i(12, 12)
const MAP: Array[String] = [
	"............",
	"..#.........",
	"............",
	"......##....",
	"......##....",
	"............",
	".###........",
	"............",
	"........#...",
	".........#..",
	"............",
	"............",
]
const VIEW: Vector2i = Vector2i(512, 384)
const SHIFT: Vector2 = Vector2(200.0, 0.0)  ## World x of the viewport's left edge is -200.
const GROUNDS: Array[float] = [30.0, 100.0]  ## Unit ground y of the two renders.
const MISMATCH_MAX_PER_MILLE: int = 3
const TEAM: Color = Color8(255, 148, 70)
const GREY: Color = Color8(128, 128, 128)

var _sort: WorldSort
var _viewport: SubViewport
var _sprite: Sprite2D
var _raised: PackedByteArray = PackedByteArray()
var _step: int = 0
var _frames: int = 0
var _ok: bool = true


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_raised.resize(GRID.x * GRID.y)
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(GRID.x * GRID.y)
	for row: int in GRID.y:
		for col: int in GRID.x:
			var wall: bool = MAP[row][col] == "#"
			_raised[row * GRID.x + col] = 1 if wall else 0
			mask[row * GRID.x + col] = 255 if wall else 0
	_sort = WorldSort.new()
	add_child(_sort)
	var material: ShaderMaterial = _sort.silhouette_material()
	material.set_shader_parameter(
		"wall_mask",
		ImageTexture.create_from_image(
			Image.create_from_data(GRID.x, GRID.y, false, Image.FORMAT_R8, mask)
		)
	)
	material.set_shader_parameter("grid_size", GRID)
	var image: Image = Image.create_empty(VIEW.x, VIEW.y, false, Image.FORMAT_RGBA8)
	image.fill(TEAM)
	image.fill_rect(Rect2i(0, 0, VIEW.x >> 1, VIEW.y >> 1), GREY)  # The top left quarter is no team.
	_viewport = SubViewport.new()
	_viewport.size = VIEW
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	_viewport.canvas_transform = Transform2D(0.0, SHIFT)
	_sprite = Sprite2D.new()
	_sprite.texture = ImageTexture.create_from_image(image)
	_sprite.centered = false
	_sprite.material = material
	_viewport.add_child(_sprite)
	_place(GROUNDS[0])


## The sprite stands at the unit's ground point (x 0, y `ground_y`) and its texture covers the view.
func _place(ground_y: float) -> void:
	_sprite.position = Vector2(0.0, ground_y)
	_sprite.offset = -SHIFT - _sprite.position  # Texel (0, 0) at world (-200, 0).


@warning_ignore("integer_division")
func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 4:
		return
	_frames = 0
	var ground_y: float = GROUNDS[_step]
	var image: Image = _viewport.get_texture().get_image()
	var mismatches: int = 0
	var covered: int = 0
	var bad_colour: int = 0
	for y: int in VIEW.y:
		for x: int in VIEW.x:
			var pixel: Color = image.get_pixel(x, y)
			var world: Vector2 = Vector2(x + 0.5, y + 0.5) - SHIFT
			var want: bool = WallCover.covered(_raised, GRID.x, world, ground_y)
			var got: bool = pixel.a > 0.01
			mismatches += 1 if want != got else 0
			covered += 1 if got else 0
			if got and want:
				var team_pixel: bool = x >= (VIEW.x >> 1) or y >= (VIEW.y >> 1)
				var is_team: bool = pixel.r > 0.8 and pixel.b < 0.5  # TEAM's hue survives.
				var is_body: bool = pixel.r < 0.2 and pixel.g < 0.2 and pixel.b < 0.2
				bad_colour += 0 if (is_team if team_pixel else is_body) else 1
	var limit: int = (VIEW.x * VIEW.y * MISMATCH_MAX_PER_MILLE) / 1000
	var ok: bool = mismatches <= limit and bad_colour <= limit and covered > 1000
	_ok = _ok and ok
	print(
		(
			"silhouette_probe: ground y %s: covered %d px, mismatches %d (limit %d), bad colours %d"
			% [ground_y, covered, mismatches, limit, bad_colour]
		)
	)
	_step += 1
	if _step >= GROUNDS.size():
		print("silhouette_probe: %s" % ("PASS" if _ok else "FAIL"))
		get_tree().quit(0 if _ok else 1)
		return
	_place(GROUNDS[_step])
