extends Node2D
## Wires the main scene to its match: the camera clamps to the map rect that MapView takes from the
## runner's World (the scene does not set the size), and starts on the centre of the scenario's
## camera tile.

@export var runner: MatchRunner
@export var map_view: MapView
@export var camera: RtsCamera


func _ready() -> void:
	var scenario: ScenarioDef = runner.scenario
	camera.set_map_rect(Rect2(map_view.map_rect_px()))
	var start_tile: Vector2 = Vector2(scenario.camera_start_tile) + Vector2(0.5, 0.5)
	camera.centre_on(start_tile * float(ViewScale.PX_PER_TILE))
