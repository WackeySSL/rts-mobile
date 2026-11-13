extends RefCounted
## What the generator v5a suites share (plan row P163, ADR 0029 section 5): a crafted building with
## the two damage poses, and the key-share raster test that P158a and P158b run on the real
## buildings. Not a test suite (no GdUnitTestSuite base).

## The key-share bands of ADR 0029 section 5: the share of the intact picture's key-band pixels
## that is still key-band at SKADET and KRITISK (the sheet's 70 % and 35 %, with room). SKADET's
## band is kept for the stage index only: it shows the intact picture now (ADR 0034).
const SHARE_BANDS: Array[Vector2] = [Vector2(0.55, 0.85), Vector2(0.20, 0.50)]
const SCALE: float = 0.5  ## The 2x art at zoom 1.
const MIN_ALPHA: float = 0.5  ## A pixel more transparent than this is not ink.
## The crafted building: a body, a tower that carries the beacon, a stack, four team panels, a
## seated mast, and an interior and a slab for the stages.
const PRIMS: Array[String] = [
	"box hull concrete 0 0 0 1.6 1.6 1.0 group=body",
	"box hull steel -0.4 -0.4 1.0 0.3 0.3 0.8 group=tower",
	"box hull rust 0.4 0.4 1.0 0.2 0.2 0.4 group=stack",
	"box hull team -0.6 0.85 0 0.3 0.1 0.3 group=t1",
	"box hull team -0.2 0.85 0 0.3 0.1 0.3 group=t2",
	"box hull team 0.2 0.85 0 0.3 0.1 0.3 group=t3",
	"box hull team 0.6 0.85 0 0.3 0.1 0.3 group=t4",
	"box hull iron 0.4 -0.4 1.0 0.1 0.1 0.4 group=mount",
	"box anim lamp -0.4 -0.4 1.8 0.1 0.1 0.1 group=beacon",
	"box hull interior 0.0 0.2 0.9 0.4 0.4 0.3 group=rooms damage=1",
	"box hull slab 0.3 -0.1 1.0 0.2 0.2 0.1 group=chunk damage=2",
]
const POSES: Array[String] = [
	"anim 2",
	"anim 1 beacon shift 0 0 0.05",
	"dmg2 0 stack hide",
	"dmg2 0 t1 char 100",
	"dmg2 0 t2 hide",
	"dmg2 0 t3 char 100",
	"dmg2 0 tower turn y 12 -0.4 -0.4 1.0",
]
const EMITTERS: Array[String] = [
	"damage 0.2 0.2 1.0", "dmg_spark -0.2 0.3 1.0", "smoke 0.4 0.4 1.4 group=stack"
]


## The crafted building with `extra_prims` added to the default primitives, and `poses` and
## `emitters` as given (lines of any array).
static func building(
	extra_prims: Array = [], poses: Array = POSES, emitters: Array = EMITTERS
) -> ArtModel:
	var prims: Array = []
	prims.append_array(PRIMS)
	prims.append_array(extra_prims)
	return with_prims(prims, poses, emitters, true)


## A crafted building of exactly these primitive, pose and emitter lines.
static func with_prims(
	prims: Array, poses: Array, emitters: Array, animated: bool = false
) -> ArtModel:
	var model: ArtModel = ArtModel.new()
	model.art_id = &"crafted"
	model.faction = &"fossil"
	model.category = &"bld"
	model.footprint = 2
	model.anim_ms = 100 if animated else 0
	model.anim_kritisk = &"run" if animated else &""
	model.prims = PackedStringArray(prims)
	model.poses = PackedStringArray(poses)
	model.emitters = PackedStringArray(emitters)
	return model


## The number of pixels of `image` in the key band of `faction` (ink, hue and saturation).
static func key_pixels(image: Image, faction: StringName) -> int:
	var count: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a >= MIN_ALPHA and ArtPalette.in_key_band(faction, "#" + pixel.to_html(false)):
				count += 1
	return count


## The picture of damage `stage` (0 intact, 1 or 2) of `model` rasterised at zoom 1 with
## `Image.load_svg_from_string`: the whole body at that stage.
static func stage_image(model: ArtModel, stage: int) -> Image:
	var shots: Dictionary[StringName, ArtGen.Shot] = ArtGen.all_shots(model)
	var polys: Array[ArtRender.Poly] = (
		ArtRender.render(model.primitives(&"hull"), 0.0, model.faction)
		if stage == 0
		else ArtGen.stage_polys(model, stage)
	)
	var layout: ArtGen.Layout = shots[&"hull"].layout
	var image: Image = Image.new()
	image.load_svg_from_string(ArtSvg.frame("t", layout.size, layout.origin, polys), SCALE)
	return image


## The key share of `stage` (1 or 2): its key-band pixels over the intact picture's.
static func key_share(model: ArtModel, stage: int) -> float:
	var intact: int = key_pixels(stage_image(model, 0), model.faction)
	return float(key_pixels(stage_image(model, stage), model.faction)) / maxf(float(intact), 1.0)


## What is wrong with the key shares of `model`, one text per stage outside its band; empty when it
## passes.
static func share_problems(model: ArtModel) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	# SKADET has no picture of its own (ADR 0034): only stage 2 is read.
	for stage: int in range(2, 3):
		var share: float = key_share(model, stage)
		var band: Vector2 = SHARE_BANDS[stage - 1]
		if share < band.x or share > band.y:
			found.append(
				"%s stage %d: key share %.2f, not in %s" % [model.art_id, stage, share, band]
			)
	return found
