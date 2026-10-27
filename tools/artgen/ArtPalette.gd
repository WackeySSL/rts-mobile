class_name ArtPalette
extends RefCounted
## The colours of the art generator (ADR 0023 sections 5 and 6, assets/art/STYLE.md "Light" and
## "Palette per faction"). A material is one hex colour, the colour of its left face (the mid tone);
## the top and the right face are the same colour at 100 % and 62 % of the top (Spec 02: top 100 %,
## left 82 %, right 62 %). The material `team` is each faction's key triad, light, mid and dark.

const TEAM: StringName = &"team"
## The three levels of a face: lit from above, the left face, the right face.
const TOP: int = 0
const LEFT: int = 1
const RIGHT: int = 2
const SHADES: Array[float] = [1.0, 0.82, 0.62]
## Key triads (light, mid, dark): the only colours a team zone may use. The match-start bake
## replaces these six hex strings with the player's triad and nothing else.
const KEYS: Dictionary[StringName, Array] = {
	&"fossil": ["#FF9446", "#E8681F", "#B04B12"],
	&"renew": ["#62D6EE", "#1FA6C8", "#137C99"],
}
## ADR 0023 section 6 as changed by the key band: rust #6E5D50, lamp #FFF1D6 (warm white), glass
## #B4C8CF and mint #A8F5B0 replace the canvas colours that fell in a key colour's hue band.
const MATERIALS: Dictionary[StringName, Dictionary] = {
	&"fossil":
	{
		&"steel": "#6B7366",
		&"concrete": "#9F9A8E",
		&"rust": "#6E5D50",
		&"iron": "#3B3F39",
		&"lamp": "#FFF1D6",
		&"olive": "#7D8562",
	},
	&"renew":
	{
		&"ceramic": "#D5DBDC",
		&"graphite": "#414A51",
		&"titanium": "#8A9398",
		&"glass": "#B4C8CF",
		&"bluegrey": "#7D8B96",
		&"mint": "#A8F5B0",
	},
}
const DARK_EDGE: float = 0.45  ## The edge of a material: its mid tone at this factor.
const LIGHT_EDGE: float = 0.4  ## The thin light edge on top faces: top tone towards white.


static func has_material(faction: StringName, material: StringName) -> bool:
	return material == TEAM or MATERIALS.get(faction, {}).has(material)


## The fill of a face of `material` at `level` (TOP, LEFT or RIGHT), as "#RRGGBB".
static func tone(faction: StringName, material: StringName, level: int) -> String:
	if material == TEAM:
		return KEYS[faction][level]
	return _hex(_channels(faction, material, SHADES[level] / SHADES[LEFT]))


## The edge of a face: the light edge on a top face, the dark edge on the others.
static func edge(faction: StringName, material: StringName, light: bool) -> String:
	if material == TEAM:
		return KEYS[faction][TOP if light else RIGHT]
	if not light:
		return _hex(_channels(faction, material, DARK_EDGE))
	var top: Vector3 = _channels(faction, material, SHADES[TOP] / SHADES[LEFT])
	return _hex(top + (Vector3(255.0, 255.0, 255.0) - top) * LIGHT_EDGE)


static func _channels(faction: StringName, material: StringName, factor: float) -> Vector3:
	var mid: Color = Color(MATERIALS[faction][material])
	var scaled: Vector3 = Vector3(mid.r8, mid.g8, mid.b8) * factor
	return scaled.clamp(Vector3.ZERO, Vector3(255.0, 255.0, 255.0))


static func _hex(channels: Vector3) -> String:
	return "#%02X%02X%02X" % [roundi(channels.x), roundi(channels.y), roundi(channels.z)]
