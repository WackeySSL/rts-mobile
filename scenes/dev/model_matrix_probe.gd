extends Node
## Developer tool (plan row P656d3, risk 1): proves that `MODEL_MATRIX` stays each sprite's own
## when sprites of one texture and one material batch on the Compatibility renderer. Eight sprites
## share one texture and one material; the vertex stage hands each sprite's origin to the fragment
## stage, which paints it as a colour. Each sprite's pixel must equal its own origin.
##   xvfb-run -a godot --rendering-driver opengl3 --path . res://scenes/dev/model_matrix_probe.tscn
## Prints `model_matrix_probe: PASS` or `FAIL` and quits with exit code 0 or 1. Opened without a
## real renderer (the scene scan) it does nothing.

const SIZE: int = 16
const PROBE_SHADER: String = """
shader_type canvas_item;
varying flat vec2 origin;
void vertex() { origin = MODEL_MATRIX[3].xy; }
void fragment() { COLOR = vec4(origin.x / 255.0, origin.y / 255.0, 0.0, 1.0); }
"""

var _viewport: SubViewport
var _frames: int = 0
var _spots: Array[Vector2i] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	var image: Image = Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	var shader: Shader = Shader.new()
	shader.code = PROBE_SHADER
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 64)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	for i: int in 8:
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = texture
		sprite.material = material
		sprite.centered = false
		sprite.position = Vector2(8 + i * 30, 10 + (i % 3) * 14)
		sprite.scale = Vector2(1 + (i % 2), 1)  # The origin is the translation, not the scale.
		_viewport.add_child(sprite)
		_spots.append(Vector2i(sprite.position))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames < 5:
		return
	var image: Image = _viewport.get_texture().get_image()
	var ok: bool = true
	for want: Vector2i in _spots:
		var got: Color = image.get_pixelv(want + Vector2i(2, 2))
		var seen: Vector2i = Vector2i(roundi(got.r * 255.0), roundi(got.g * 255.0))
		ok = ok and seen == want
		print("model_matrix_probe: sprite at %s reads %s" % [want, seen])
	print("model_matrix_probe: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
