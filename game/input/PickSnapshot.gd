class_name PickSnapshot
extends RefCounted
## What the Picker needs to know about every unit on screen, as parallel arrays in World row
## order (ascending id). UnitLayer.fill_pick_snapshot() fills it and resizes the arrays in place,
## so one snapshot can be refilled every frame without allocating.

var ids: PackedInt32Array = PackedInt32Array()
var owners: PackedInt32Array = PackedInt32Array()
var type_index: PackedInt32Array = PackedInt32Array()
var screen_pos: PackedVector2Array = PackedVector2Array()  ## Unit centres, base px.
## Hit radius in base px: the larger of the minimum (dp) and the unit's selection radius on screen.
var radius_px: PackedFloat32Array = PackedFloat32Array()


func size() -> int:
	return ids.size()
