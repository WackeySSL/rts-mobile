class_name LifeRegions
extends RefCounted
## Where each life sprite is in its atlas (plan row P135, ADR 0027, STYLE.md "Life effects"): the
## one table the life layers (P138, P141, P145, P148 to P150) and the gallery's Life page read.
## `tests/art/test_life_atlases.gd` holds it equal to STYLE.md's table and to the ink of the two
## SVGs, so a region here is a region in the file. Pixels are px of the imported texture (import
## scale 0.5), which at camera zoom 1 are world px. Frame k of a kind is `FIRST` moved right by
## k x `STEP`. View-only: no sim file reads it.

enum Atlas { LIFE, STRIKE }

const LIFE_ART: String = "res://assets/art/svg/fx/life_atlas.svg"
const STRIKE_ART: String = "res://assets/art/svg/fx/strike_atlas.svg"

## Which atlas a kind is in, in the order STYLE.md and the gallery list the kinds.
const ATLAS: Dictionary[StringName, int] = {
	&"dust": Atlas.LIFE,
	&"smoke": Atlas.LIFE,
	&"soot": Atlas.LIFE,
	&"steam": Atlas.LIFE,
	&"puff": Atlas.LIFE,
	&"exhaust": Atlas.LIFE,
	&"flare": Atlas.LIFE,
	&"fire": Atlas.LIFE,
	&"spark": Atlas.LIFE,
	&"hit_flash": Atlas.LIFE,
	&"chip": Atlas.LIFE,
	&"dust_cloud": Atlas.LIFE,
	&"ember": Atlas.LIFE,
	&"glow": Atlas.LIFE,
	&"jet": Atlas.LIFE,
	&"lance_down": Atlas.STRIKE,
	&"lance_up": Atlas.STRIKE,
	&"trail": Atlas.STRIKE,
	&"shadow": Atlas.STRIKE,
	&"seed": Atlas.STRIKE,
	&"seed_trail": Atlas.STRIKE,
	&"glint": Atlas.STRIKE,
	&"hex": Atlas.STRIKE,
	&"hex_lit": Atlas.STRIKE,
	&"launch_flash": Atlas.STRIKE,
	&"core_flash": Atlas.STRIKE,
	&"launch_ring": Atlas.STRIKE,
}
## The region of frame 0.
const FIRST: Dictionary[StringName, Rect2i] = {
	&"dust": Rect2i(0, 130, 50, 26),
	&"smoke": Rect2i(0, 0, 42, 38),
	&"soot": Rect2i(0, 42, 42, 38),
	&"steam": Rect2i(140, 0, 42, 38),
	&"puff": Rect2i(140, 42, 22, 20),
	&"exhaust": Rect2i(192, 42, 22, 20),
	&"flare": Rect2i(0, 84, 26, 42),
	&"fire": Rect2i(124, 84, 26, 34),
	&"spark": Rect2i(218, 84, 16, 16),
	&"hit_flash": Rect2i(0, 164, 36, 36),
	&"chip": Rect2i(84, 164, 14, 12),
	&"dust_cloud": Rect2i(0, 206, 64, 44),
	&"ember": Rect2i(142, 164, 14, 14),
	&"glow": Rect2i(140, 206, 56, 56),
	&"jet": Rect2i(182, 164, 40, 18),
	&"lance_down": Rect2i(0, 0, 34, 164),
	&"lance_up": Rect2i(38, 0, 34, 164),
	&"trail": Rect2i(76, 0, 16, 64),
	&"shadow": Rect2i(76, 68, 50, 26),
	&"seed": Rect2i(96, 0, 18, 34),
	&"seed_trail": Rect2i(118, 0, 12, 64),
	&"glint": Rect2i(134, 0, 14, 14),
	&"hex": Rect2i(134, 18, 38, 20),
	&"hex_lit": Rect2i(134, 42, 38, 20),
	&"launch_flash": Rect2i(0, 168, 66, 66),
	&"core_flash": Rect2i(70, 168, 66, 66),
	&"launch_ring": Rect2i(140, 168, 98, 50),
}
const FRAMES: Dictionary[StringName, int] = {
	&"dust": 3,
	&"smoke": 3,
	&"soot": 2,
	&"steam": 2,
	&"puff": 2,
	&"exhaust": 2,
	&"flare": 4,
	&"fire": 3,
	&"spark": 3,
	&"hit_flash": 2,
	&"chip": 3,
	&"dust_cloud": 2,
	&"ember": 2,
	&"glow": 1,
	&"jet": 2,
	&"lance_down": 1,
	&"lance_up": 1,
	&"trail": 1,
	&"shadow": 1,
	&"seed": 1,
	&"seed_trail": 1,
	&"glint": 1,
	&"hex": 1,
	&"hex_lit": 1,
	&"launch_flash": 1,
	&"core_flash": 1,
	&"launch_ring": 1,
}
## The distance in x between two frames of a kind (0 for a kind of one frame).
const STEP: Dictionary[StringName, int] = {
	&"dust": 54,
	&"smoke": 46,
	&"soot": 46,
	&"steam": 46,
	&"puff": 26,
	&"exhaust": 26,
	&"flare": 30,
	&"fire": 30,
	&"spark": 20,
	&"hit_flash": 40,
	&"chip": 18,
	&"dust_cloud": 68,
	&"ember": 18,
	&"glow": 0,
	&"jet": 44,
	&"lance_down": 0,
	&"lance_up": 0,
	&"trail": 0,
	&"shadow": 0,
	&"seed": 0,
	&"seed_trail": 0,
	&"glint": 0,
	&"hex": 0,
	&"hex_lit": 0,
	&"launch_flash": 0,
	&"core_flash": 0,
	&"launch_ring": 0,
}
## The point of a frame that sits on the effect's position, px from the region's top-left: the
## centre of a cloud, a heap, a spark, a flash, a ring, the shadow, the seed and a hexagon, the
## base of a flame, the tip of a lance, and the flush end of a strip.
const ANCHOR: Dictionary[StringName, Vector2] = {
	&"dust": Vector2(25, 13),
	&"smoke": Vector2(21, 19),
	&"soot": Vector2(21, 19),
	&"steam": Vector2(21, 19),
	&"puff": Vector2(11, 10),
	&"exhaust": Vector2(11, 10),
	&"flare": Vector2(13, 38),
	&"fire": Vector2(13, 30),
	&"spark": Vector2(8, 8),
	&"hit_flash": Vector2(18, 18),
	&"chip": Vector2(7, 6),
	&"dust_cloud": Vector2(32, 22),
	&"ember": Vector2(7, 7),
	&"glow": Vector2(28, 28),
	&"jet": Vector2(2, 9),
	&"lance_down": Vector2(17, 157),
	&"lance_up": Vector2(17, 7),
	&"trail": Vector2(8, 64),
	&"shadow": Vector2(25, 13),
	&"seed": Vector2(9, 17),
	&"seed_trail": Vector2(6, 0),
	&"glint": Vector2(7, 7),
	&"hex": Vector2(19, 10),
	&"hex_lit": Vector2(19, 10),
	&"launch_flash": Vector2(33, 33),
	&"core_flash": Vector2(33, 33),
	&"launch_ring": Vector2(49, 25),
}
## Where a strip joins the sprite it trails: the point of the sprite that the strip's anchor sits
## on. The strip is drawn first, so the sprite covers the seam: `trail` is placed with its anchor
## on `lance_down`'s join (the collar's centre), `seed_trail` on `seed`'s.
const JOIN: Dictionary[StringName, Vector2] = {
	&"lance_down": Vector2(17, 65),
	&"seed": Vector2(9, 17),
}
## The edge of a strip that touches its region's edge on purpose, the end the join is on.
const FLUSH_EDGE: Dictionary[StringName, StringName] = {
	&"trail": &"bottom",
	&"seed_trail": &"top",
}
## How far a layer may stretch a strip along its length, in times its region's length: a fall or a
## rise is a short streak that fades to nothing, never a column from the sky to the ground.
const MAX_STRETCH: Dictionary[StringName, float] = {
	&"trail": 2.0,
	&"seed_trail": 2.0,
}
## The sprite kind of each emitter kind the sheets name (`IsoSheetDef.emitters`, ADR 0027 section
## 4): a building's `flame` is drawn with the `flare` sprite. The one place the two names meet;
## `LifeSettings.emit_ms` and `emit_life_ms` are keyed by the sprite kind.
const EMITTER_SPRITE: Dictionary[StringName, StringName] = {
	&"smoke": &"smoke",
	&"steam": &"steam",
	&"flame": &"flare",
}
## The kinds a layer may draw mirrored in x for a second look: the ones that give light, so nothing
## on them is lit from a side (STYLE.md "Life effects"). A cloud, a heap of dust, a lance, the seed
## and a hexagon are lit from the north-west and are never mirrored.
const MIRRORABLE: Array[StringName] = [&"flare", &"fire", &"spark"]
## The net of the Blackout Array (STYLE.md "Life effects", "The net"): hexagons of side 16 world px
## with the lines a layer draws in code, a light line over a dark edge, so the lattice meets the
## `hex` sprite. The width of the edge and of the light line are world px.
const NET_SIDE_PX: float = 16.0  ## A hexagon's side, and half its width.
const NET_COLUMN_PX: float = 24.0
const NET_ROW_PX: float = 13.86
const NET_SHIFT_PX: float = 6.93  ## Every other column moves down by this much.
const NET_LIGHT: Color = Color("D8FFE0")
const NET_EDGE: Color = Color("1F5C3A")
const NET_LIGHT_PX: float = 1.5
const NET_EDGE_PX: float = 3.0


## The region of frame `frame` of `kind`, in imported px.
static func region(kind: StringName, frame: int = 0) -> Rect2i:
	assert(frame >= 0 and frame < FRAMES[kind], "frame out of range")
	var first: Rect2i = FIRST[kind]
	return Rect2i(first.position + Vector2i(frame * STEP[kind], 0), first.size)


## Whether a layer may draw `kind` mirrored.
static func mirrorable(kind: StringName) -> bool:
	return MIRRORABLE.has(kind)


## The SVG a kind is in.
static func texture_path(kind: StringName) -> String:
	return LIFE_ART if ATLAS[kind] == Atlas.LIFE else STRIKE_ART
