class_name GhostMarks
extends RefCounted
## The one texture of the placement ghost's marks (ADR 0023 section 3, STYLE.md "Ghosts", plan
## P86): a 64 x 32 diamond tile quad for each of the wash (a solid diamond) and the hatch (the
## imported `ui/ghost_hatch.svg` cut to the diamond), and a frame (the diamond's outline, a stroke
## `FRAME_PX` wide centred on its edge, so the strokes of two neighbouring tiles lie on each other
## and the footprint's border is as wide as the lines between its cells). All are white and grey
## with the edge antialiased, tinted when drawn, and packed by `RuntimeAtlas` into one page, so the
## three marks of every cell of a footprint are regions of one texture. Nothing here is art: the
## wash and the frame are computed, the hatch is the file the art director drew.

const TILE: Vector2i = GroundAtlas.TILE_PX  ## One cell's diamond: 64 x 32.
const FRAME_MARGIN: int = 4  ## The frame's image is wider than the diamond by this on each side.
const FRAME_PX: float = 3.0  ## The stroke, centred on the diamond's edge.
## From a diamond's middle to its edge, perpendicular, px: 32 x 16 / sqrt(32^2 + 16^2).
const EDGE_PX: float = 14.3108
const HATCH_ART: String = "res://assets/art/svg/ui/ghost_hatch.svg"
const WASH: StringName = &"wash"
const FRAME: StringName = &"frame"
## The hatch cuts, one per parity of (column + row). The art (64 px square at import scale 0.5)
## has bands along x + y = const that repeat every 32 px of x + y. A cell's middle lies 48 px of
## x + y further on for each column and 16 px less for each row, half a period either way, so the
## cells of one parity take the cut HATCH_STEP_PX rows higher than the others and the bands lie on
## straight lines through every cell edge of a footprint, not broken at each.
const HATCHES: Array[StringName] = [&"hatch_0", &"hatch_1"]
const HATCH_STEP_PX: int = 16


## The page with the three marks as regions; the hatch is left out when its file cannot be read.
static func build() -> RuntimeAtlas:
	var sources: Dictionary[StringName, Image] = {
		WASH: _diamond(0, false), FRAME: _diamond(FRAME_MARGIN, true)
	}
	var art: Texture2D = load(HATCH_ART) as Texture2D
	var hatch: Image = null if art == null else art.get_image()
	if hatch != null and not hatch.is_empty():
		if hatch.is_compressed():
			hatch.decompress()
		hatch.convert(Image.FORMAT_RGBA8)
		for phase: int in HATCHES.size():
			sources[HATCHES[phase]] = _cut(hatch, phase)
	return RuntimeAtlas.build_images(sources, 256)


## The hatch region of `cell`'s tile quad: the parity of (column + row) picks the cut that keeps the
## bands on one line through the cell and its neighbours.
static func hatch_for(cell: Vector2i) -> StringName:
	return HATCHES[posmod(cell.x + cell.y, HATCHES.size())]


## An RGBA8 image of the diamond tile with a margin of `margin` px on every side: white where the
## diamond is, or with `outline` where `FRAME_PX` about its edge is; the edge is antialiased by the
## pixel's distance to it.
static func _diamond(margin: int, outline: bool) -> Image:
	var wide: Vector2i = TILE + Vector2i.ONE * 2 * margin
	var image: Image = Image.create_empty(wide.x, wide.y, false, Image.FORMAT_RGBA8)
	for y: int in wide.y:
		for x: int in wide.x:
			var edge: float = _inside(Vector2(x + 0.5, y + 0.5) - Vector2(wide) * 0.5)
			var cover: float = edge + 0.5
			if outline:
				cover = FRAME_PX * 0.5 - absf(edge) + 0.5
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(cover, 0.0, 1.0)))
	return image


## Cut `phase` of the hatch (an RGBA8 image) as a diamond tile: its own pixels, kept only inside the
## diamond. Phase 0 is the middle rows, phase 1 starts HATCH_STEP_PX rows higher.
@warning_ignore("integer_division")
static func _cut(hatch: Image, phase: int) -> Image:
	var top: int = maxi((hatch.get_height() - TILE.y) / 2 - phase * HATCH_STEP_PX, 0)
	var tile: Image = Image.create_empty(TILE.x, TILE.y, false, Image.FORMAT_RGBA8)
	tile.blit_rect(hatch, Rect2i(0, top, TILE.x, TILE.y), Vector2i.ZERO)
	for y: int in TILE.y:
		for x: int in TILE.x:
			var colour: Color = tile.get_pixel(x, y)
			var edge: float = _inside(Vector2(x + 0.5, y + 0.5) - Vector2(TILE) * 0.5)
			colour.a *= clampf(edge + 0.5, 0.0, 1.0)
			tile.set_pixel(x, y, colour)
	return tile


## How far, px, `from` (a point relative to the diamond's middle) lies inside the edge of the
## diamond tile: negative outside it.
static func _inside(from: Vector2) -> float:
	var reach: float = absf(from.x) / (TILE.x * 0.5) + absf(from.y) / (TILE.y * 0.5)
	return (1.0 - reach) * EDGE_PX
