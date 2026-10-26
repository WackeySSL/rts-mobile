class_name BuildingRoofLayer
extends Node2D
## The roof parts of the buildings (ADR 0022 sections 2 and 4, plan P84), at z 111: over the unit
## bands and the fog layer, under the health bars. Each building is cut along the middle line of
## its footprint; the rows of the picture north of it are drawn here, in ascending order of the
## footprint's south row (a building south of a 1x1 turret covers its roof), each followed by its
## turret head as a rotated quad of the same atlas, so a building south of a turret still covers
## its head and the heads cost no call of their own. The list, the atlas and the colours are
## BuildingLayer's (`buildings`), so the two parts always agree: a roof carries its footprint's fog
## state as the quad colour, white or the explored dim.
##
## The layer redraws when the list changed (`BuildingLayer.plan_version`) or a head turned in this
## frame, never otherwise. A head turns on the frame clock like a unit's turret.
## `draw_count()` is how often `_draw()` ran, which a test pins.

@export var buildings: BuildingLayer

var _drawn_version: int = 0
var _draws: int = 0
var _quads: int = 0


func _process(delta: float) -> void:
	if buildings == null:
		return
	var turned: bool = buildings.turn_heads(delta)  # It syncs the list first.
	if turned or buildings.plan_version() != _drawn_version:
		_drawn_version = buildings.plan_version()
		queue_redraw()


func _draw() -> void:
	_draws += 1
	_quads = buildings.paint(self, true) if buildings != null else 0


## `_draw()` runs so far; a frame without a change or a turning head must not add one.
func draw_count() -> int:
	return _draws


## Quads the last `_draw()` painted: two for each shown building and one more for a turret head.
func drawn_quads() -> int:
	return _quads
