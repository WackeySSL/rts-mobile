class_name PickSnapshot
extends RefCounted
## What the Picker needs to know about every unit, on or off screen, as parallel arrays in World
## row order (ascending id). UnitLayer.fill_pick_snapshot() fills it and resizes the arrays in
## place, so one snapshot can be refilled every frame without allocating. A hidden enemy (one the
## local player's fog hides, P47) is in the arrays like any other unit, but its `pickable` entry is
## 0, so no tap and no box reaches it.
## The buildings (P115b) are in their own parallel arrays: `BuildingLayer.fill_pick_snapshot()`
## lists the ones it shows (the ones the fog hides are left out), and no box query reads them.

var ids: PackedInt32Array = PackedInt32Array()
var owners: PackedInt32Array = PackedInt32Array()
var type_index: PackedInt32Array = PackedInt32Array()
## Unit centres, base px: the lifted ones (ADR 0023 section 3), the ground point raised by the
## sheet's `pick_lift_px` at the camera zoom.
var screen_pos: PackedVector2Array = PackedVector2Array()
## How high each centre stands above the unit's ground point, base px (`lift_of`): a mark that lies
## on the ground, the attack's flash, adds it back. A row with no entry stands on the ground.
var lift_px: PackedFloat32Array = PackedFloat32Array()
## Hit radius in base px: the larger of the minimum (dp) and the unit's selection radius on screen.
var radius_px: PackedFloat32Array = PackedFloat32Array()
## 0 for a row the Picker must skip (an enemy the fog hides), 1 for every other row. A row with no
## entry (`row >= pickable.size()`, as in a snapshot built by hand) is pickable.
var pickable: PackedByteArray = PackedByteArray()

## A building is picked on its silhouette (ADR 0023 section 3): the footprint's diamond, half
## `building_half` wide and high round `building_centres`, plus the rectangle between the diamond's
## side corners and `building_rise` above them. All in base px on the screen, at the camera's zoom.
var building_ids: PackedInt32Array = PackedInt32Array()
var building_owners: PackedInt32Array = PackedInt32Array()
var building_centres: PackedVector2Array = PackedVector2Array()
var building_half: PackedVector2Array = PackedVector2Array()
var building_rise: PackedFloat32Array = PackedFloat32Array()  ## Centre to the sprite's top.
## The sort key (the world y of the footprint centre): the larger one is drawn in front.
var building_keys: PackedFloat32Array = PackedFloat32Array()
## 0 for a building the sim would drop an ATTACK on, 1 for every other. The view draws an enemy
## building when any cell of its footprint is seen, the sim takes an attack on it only when the cell
## under its position is (`Targeting.sees`). A shape with no entry is targetable.
var building_targetable: PackedByteArray = PackedByteArray()


func size() -> int:
	return ids.size()


## How far above its ground point the centre of unit `index` stands, base px; 0 for a row with no
## entry (a snapshot built by hand).
func lift_of(index: int) -> float:
	return lift_px[index] if index < lift_px.size() else 0.0


func building_count() -> int:
	return building_ids.size()


## Whether an ATTACK on building `shape` (an index of the building arrays) is taken by the sim.
func is_targetable(shape: int) -> bool:
	return shape >= building_targetable.size() or building_targetable[shape] != 0
