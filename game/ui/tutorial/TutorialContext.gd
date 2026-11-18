class_name TutorialContext
extends RefCounted
## What `TutorialConditions` reads, gathered by the director each frame: the published snapshot,
## the selection, the open unfold, the camera and the placement and strike modes. Plain values, so
## a condition is a pure function of a context and a test builds one without any node. The
## snapshot is never written (a published snapshot is read-only, ADR 0012 section 3).

var snapshot: MatchSnapshot = null
var local_player: int = 1
var selection: SelectionModel = null
var hud: HudState = null
## The camera: the index of the nearest zoom level and the world position its centre looks at.
var zoom_level: int = 0
var camera_centre: Vector2 = Vector2.ZERO
## The build drawer's tab (`World.Tab`).
var drawer_tab: int = 0
## The type index being placed, -1 when no placement is on.
var placement_type: int = -1
var strike_aiming: bool = false
var strike_has_point: bool = false


## A copy of the values, for the baseline a beat compares against (the snapshot and the other
## objects are shared, the camera values are copied).
func baseline() -> TutorialContext:
	var copy: TutorialContext = TutorialContext.new()
	copy.snapshot = snapshot
	copy.local_player = local_player
	copy.selection = selection
	copy.hud = hud
	copy.zoom_level = zoom_level
	copy.camera_centre = camera_centre
	copy.drawer_tab = drawer_tab
	copy.placement_type = placement_type
	copy.strike_aiming = strike_aiming
	copy.strike_has_point = strike_has_point
	return copy
