class_name BakeMaterials
extends RefCounted
## The bake's materials: one `ShaderMaterial` of `detail.gdshader` per `DetailMaterial`, and a
## noise texture all of them share.

const SHADER: Shader = preload("res://tools/prerender/detail.gdshader")
const NOISE_SEED: int = 655
const NOISE_SIZE: int = 256

static var _noise: ImageTexture


## name -> Material for every material of `model`; the TEAM ones take `team` as their paint.
static func for_model(model: DetailModel, team: Color) -> Dictionary:
	var found: Dictionary = {}
	for def: DetailMaterial in model.materials:
		var m: ShaderMaterial = ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("base", team if def.kind == DetailMaterial.Kind.TEAM else def.base)
		m.set_shader_parameter("metal", def.metallic)
		m.set_shader_parameter("rough", def.roughness)
		m.set_shader_parameter("kind", int(def.kind))
		m.set_shader_parameter("nz", noise())
		found[def.id] = m
	return found


static func noise() -> ImageTexture:
	if _noise == null:
		var n: FastNoiseLite = FastNoiseLite.new()
		n.seed = NOISE_SEED
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 0.03
		n.fractal_octaves = 5
		n.fractal_gain = 0.55
		var img: Image = n.get_seamless_image(NOISE_SIZE, NOISE_SIZE, false, false, 0.2, false)
		img.convert(Image.FORMAT_L8)
		img.generate_mipmaps()
		_noise = ImageTexture.create_from_image(img)
	return _noise


## Drops the shared texture, so the process can exit with no resource in use.
static func release() -> void:
	_noise = null
