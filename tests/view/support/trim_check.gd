extends RefCounted
## The "no jump" rule of the atlas trim (plan P306), shared by the suites that drive a site: the box
## a sprite draws from the atlas, in its parent's px, is the box the untrimmed frame showed
## (`IsoSheetDef.frame_box` minus the part's origin, times `WorldSort.ART_SCALE`). Exact at bake
## scale 1.0; below it the crop rounds out by up to TOL_TEXELS texels per side. Not a test suite.

const TOL_TEXELS: float = 2.0  ## The floor and the ceil of the crop, and the clear ring.


## "" when `sprite`, showing frame `frame` of direction `dir` of `part`, draws where the untrimmed
## frame did at bake scale `bake`; else what is wrong.
static func problem(
	sprite: Sprite2D, sheet: IsoSheetDef, part: StringName, dir: int, frame: int, bake: float
) -> String:
	var box: Rect2i = sheet.frame_box(part, dir, frame)
	var want: Rect2 = Rect2(
		Vector2(box.position - sheet.origin(part)) * WorldSort.ART_SCALE,
		Vector2(box.size) * WorldSort.ART_SCALE
	)
	var drawn: Rect2 = Rect2(sprite.offset * sprite.scale, sprite.region_rect.size * sprite.scale)
	var message: String = (
		"%s d%d f%d: drew %s, the untrimmed frame %s" % [part, dir, frame, drawn, want]
	)
	if bake == 1.0:
		return "" if drawn.is_equal_approx(want) else message
	var tol: Vector2 = Vector2.ONE * TOL_TEXELS * sprite.scale
	var outer: Rect2 = Rect2(want.position - tol, want.size + 2.0 * tol)
	if drawn.grow(0.01).encloses(want) and outer.grow(0.01).encloses(drawn):
		return ""
	return message
