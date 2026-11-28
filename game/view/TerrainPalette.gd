class_name TerrainPalette
extends RefCounted
## The terrain colours by terrain id (assets/art/STYLE.md "Fog and terrain"), the one table behind
## `MapView.colors` (and so the minimap's picture) and the map select's preview (P666b), so the
## pictures of one map never drift apart. A terrain id the table lacks is `MISSING`. A key
## `<id>_b` and `<id>_c` is the second and third tone of the tile of `<id>`; the gallery's
## `TERRAIN_COLORS` holds the same keys (P52 compares them).

const MISSING: Color = Color.MAGENTA

const COLORS: Dictionary[StringName, Color] = {
	&"grass": Color("5E7D4A"),
	&"grass_b": Color("6F8F57"),
	&"sand": Color("CDB98F"),
	&"scrub": Color("4E5A3A"),
	&"scrub_b": Color("6B7A4F"),
	&"scrub_c": Color("8C9A6B"),
	&"rock": Color("6E6A66"),
	&"rock_b": Color("8C8782"),
	&"rock_c": Color("4F4B48"),
	&"water": Color("2E5E7E"),
	&"water_b": Color("3C7396"),
	&"ore": Color("8A6F4D"),
}


## The colour of terrain `id`, `MISSING` when the table has none.
static func colour(id: StringName) -> Color:
	return COLORS.get(id, MISSING)
