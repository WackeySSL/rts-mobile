class_name ArtIcon
extends RefCounted
## The item card of a type (ADR 0023 section 5, the canvas's "Byggekort"): its default view
## (`d06`, `d10` for the Lumen Accord, the one view of a building) and its cast shadow on a dark
## plate with a faint 2:1 grid and a corner in the faction's key colour, 128 x 128 px. It is a
## texture import like every UI icon, so the faction's own key triad stays as drawn.

const SIZE: int = 128
const PLATE: String = "#1C2127"
const RIM: String = "#2F363D"
const GRID: String = "#2A3036"
const GRID_STEP_PX: int = 16  ## Between two lines of one family: a grid diamond is 32 x 16 px.
const GRID_LINE_PX: float = 1.5
const INSET_PX: float = 6.0  ## The grid and the picture keep this far from the card's edge.
const FIT_PX: Vector2 = Vector2(104.0, 92.0)  ## The room for the picture and its shadow.
const MAX_SCALE: float = 1.5  ## A small unit is enlarged, not past this.
const CORNER_PX: int = 36  ## The key-colour corner, top left.


## The SVG text of the card of `model`.
static func card(model: ArtModel) -> String:
	var dir: int = model.default_dir()
	var yaw: float = 0.0 if model.category == &"bld" else ArtGen.yaw(dir)
	var body: Array[ArtRender.Poly] = ArtRender.render(
		model.primitives(&"hull"), yaw, model.faction
	)
	for part: StringName in [&"turret", &"head"]:
		var parts: Array[ArtRender.Poly] = ArtRender.render(
			model.primitives(part), ArtGen.yaw(dir), model.faction
		)
		var at: Vector2 = ArtGen.mount_px(model, 6 if model.category == &"bld" else dir)
		for poly: ArtRender.Poly in parts:
			for i: int in poly.points.size():
				poly.points[i] += at
		body.append_array(parts)
	var shadow: Array[ArtRender.Poly] = ArtShadow.polys(model.shadow_prims(), yaw)
	var box: Rect2 = ArtRender.bounds(shadow + body)
	var scale: float = minf(minf(FIT_PX.x / box.size.x, FIT_PX.y / box.size.y), MAX_SCALE)
	var origin: Vector2 = Vector2.ONE * SIZE / 2.0 - box.get_center() * scale
	var lines: PackedStringArray = ArtSvg.group('stroke-width="2"', [_plate()])
	lines.append_array(ArtSvg.group("", _grid()))
	lines.append_array(ArtSvg.group("", [_corner(model.faction)]))
	lines.append_array(ArtSvg.group('opacity="%s"' % ArtShadow.OPACITY, shadow, origin, scale))
	lines.append_array(
		ArtSvg.group(
			'stroke-width="%d" stroke-linejoin="round"' % ArtSvg.EDGE_PX, body, origin, scale
		)
	)
	var comment: String = (
		"%s item card: %s from assets/art/models, do not edit" % [model.art_id, ArtGen.MARKER]
	)
	return ArtSvg.document(comment, Vector2i(SIZE, SIZE), lines)


## The plate, a square with its corners cut.
static func _plate() -> ArtRender.Poly:
	var plate: ArtRender.Poly = ArtRender.Poly.new()
	plate.points = _points(
		[[8, 2], [120, 2], [126, 8], [126, 120], [120, 126], [8, 126], [2, 120], [2, 8]]
	)
	plate.fill = PLATE
	plate.stroke = RIM
	return plate


## The corner in the faction's key colour, over the grid.
static func _corner(faction: StringName) -> ArtRender.Poly:
	var corner: ArtRender.Poly = ArtRender.Poly.new()
	corner.points = _points([[8, 2], [CORNER_PX, 2], [2, CORNER_PX], [2, 8]])
	corner.fill = ArtPalette.KEYS[faction][1]
	return corner


## Lines of slope 1/2 and -1/2 through the card's centre every `GRID_STEP_PX`, each a thin strip.
static func _grid() -> Array[ArtRender.Poly]:
	var found: Array[ArtRender.Poly] = []
	var high: float = SIZE - INSET_PX
	for slope: float in [0.5, -0.5]:
		for k: int in range(-8, 16):
			var c: float = k * GRID_STEP_PX
			# The line y = slope x + c inside the inset square.
			var x0: float = maxf(INSET_PX, minf((INSET_PX - c) / slope, (high - c) / slope))
			var x1: float = minf(high, maxf((INSET_PX - c) / slope, (high - c) / slope))
			if x1 - x0 < 1.0:
				continue
			var strip: ArtRender.Poly = ArtRender.Poly.new()
			var y0: float = slope * x0 + c
			var y1: float = slope * x1 + c
			strip.points = PackedVector2Array(
				[
					Vector2(x0, y0),
					Vector2(x1, y1),
					Vector2(x1, y1 + GRID_LINE_PX),
					Vector2(x0, y0 + GRID_LINE_PX)
				]
			)
			strip.fill = GRID
			found.append(strip)
	return found


static func _points(pairs: Array) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for pair: Array in pairs:
		points.append(Vector2(pair[0], pair[1]))
	return points
