extends Node2D
## Wires the main scene's camera to its map: the camera clamps to the map rect and starts on its
## centre. P13 builds the map from the scenario and starts on its camera tile instead.

@export var map_view: TestMapView
@export var camera: RtsCamera


func _ready() -> void:
	var rect: Rect2 = Rect2(map_view.map_rect_px())
	camera.set_map_rect(rect)
	camera.centre_on(rect.get_center())
