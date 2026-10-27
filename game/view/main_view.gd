extends Node2D
## Wires the main scene to its match: the camera clamps its centre into the map's diamond that
## MapView takes from the runner's World (the scene does not set the size), and starts on the centre
## of the scenario's camera tile.

@export var runner: MatchRunner
@export var map_view: MapView
@export var camera: RtsCamera


func _ready() -> void:
	var scenario: ScenarioDef = runner.scenario
	camera.set_map_rect(map_view.map_diamond_px())
	camera.centre_on(
		IsoProjection.cell_centre_px(scenario.camera_start_tile.x, scenario.camera_start_tile.y)
	)
