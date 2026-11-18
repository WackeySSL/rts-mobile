class_name MineMarkArt
extends RefCounted
## The mine marks' art (plan row P292, ADR 0037 section 8, STYLE.md "The minelayers"): per faction
## one mark for an own mine and one for a known enemy mine,
## `assets/art/svg/marks/mine_<faction>_<kind>.svg`.
## They are "Keep File" imports: the bake reads the text and `IsoPlayerArt.recolour` swaps the
## faction's key triad for the owner's, as for the iso frames. P293's `MineLayer` draws them; the
## art gallery shows them. The ground point and the canvas are fixed here, once, for both.

const PATH: String = "res://assets/art/svg/marks/mine_%s_%s.svg"
const OWN: String = "own"
const KNOWN: String = "known"
const KINDS: Array[String] = [OWN, KNOWN]
const SIZE_PX: Vector2 = Vector2(144.0, 96.0)  ## The canvas, 2x art px.
## The ground point of a mark, 2x art px: the centre of the mine's base on the ground, and of the
## known mark's notched rim. A sprite of the mark at scale s stands on a map point with its
## offset set to `-ORIGIN_PX * s`.
const ORIGIN_PX: Vector2 = Vector2(72.0, 60.0)


## The SVG text of the mark of `kind` (`OWN` or `KNOWN`) of `faction` (`fossil` or `renew`), in
## the faction's key triad.
static func text(faction: StringName, kind: String) -> String:
	return FileAccess.get_file_as_string(PATH % [faction, kind])
