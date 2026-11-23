extends Node2D
## Wires the main scene to its match: the camera clamps its centre into the map's diamond that
## MapView takes from the runner's World (the scene does not set the size), and starts on the centre
## of the scenario's camera tile. It also gives UiSounds the scenario's local player and the HUD's
## AttackCues (P535), and a lesson's match gets its coach (`TutorialHost`, P544). BattleSounds wires
## itself through its own runner export.

@export var runner: MatchRunner
@export var map_view: MapView
@export var camera: RtsCamera
@export var ui_sounds: UiSounds
@export var attack_cues: AttackCues

## The service that plays the music: the `AudioService` autoload unless a test sets another node
## with `play_music`.
var audio: Node = null


func _ready() -> void:
	var scenario: ScenarioDef = runner.scenario
	camera.set_map_rect(map_view.map_diamond_px())
	camera.centre_on(
		IsoProjection.cell_centre_px(scenario.camera_start_tile.x, scenario.camera_start_tile.y)
	)
	ui_sounds.local_player = scenario.local_player
	ui_sounds.connect_attack_cues(attack_cues)
	runner.ticked.connect(_on_first_tick, CONNECT_ONE_SHOT)
	TutorialHost.attach(self)  # Only a lesson's match gets a director (P544).


## The battle music starts with the first published tick (ADR 0041 section 5), once.
func _on_first_tick(_tick: int) -> void:
	audio = audio if audio != null else get_node_or_null("/root/AudioService")
	if audio != null:
		audio.call(&"play_music", &"battle")
