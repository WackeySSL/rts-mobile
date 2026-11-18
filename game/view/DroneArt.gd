class_name DroneArt
extends RefCounted
## The repair drone's art (plan row P280, ADR 0037 sections 5 and 14, STYLE.md "The medic squads"
## and "Drone effect"): one hand-written atlas, `assets/art/svg/fx/drone_atlas.svg`, with the
## Lumen Accord's drone in two rotor-blur frames and its ground shadow. P281's repair effect layer
## flies the drone from a Drone Dock to a vehicle and back; the art gallery shows it. It carries no
## team colour. View-only: no sim file reads it.

const ART: String = "res://assets/art/svg/fx/drone_atlas.svg"
const FRAMES: int = 2  ## The rotor blur alternates between these two frames.
## The two drone frames and the shadow, in px of the imported texture (import scale 0.5), which at
## camera zoom 1 are world px. Each sprite stands at the centre of its region.
const REGIONS: Array[Rect2i] = [Rect2i(0, 0, 40, 36), Rect2i(40, 0, 40, 36)]
const SHADOW: Rect2i = Rect2i(80, 0, 40, 36)
const SIZE_PX: Vector2i = Vector2i(120, 36)


## The region of frame `frame` (0 or 1, any integer folds into them).
static func region(frame: int) -> Rect2i:
	return REGIONS[posmod(frame, FRAMES)]
