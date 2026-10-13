extends Node2D
## Wires the main scene to its match: the test map takes the scenario's size (the scene does not
## set it), the camera clamps to the map rect and starts on the centre of the scenario's camera
## tile.

@export var runner: MatchRunner
@export var map_view: TestMapView
@export var camera: RtsCamera


func _ready() -> void:
	var scenario: ScenarioDef = runner.scenario
	map_view.size_tiles = scenario.map_size_tiles
	camera.set_map_rect(Rect2(map_view.map_rect_px()))
	var start_tile: Vector2 = Vector2(scenario.camera_start_tile) + Vector2(0.5, 0.5)
	camera.centre_on(start_tile * float(ViewScale.PX_PER_TILE))
