extends Node2D
## Wires the main scene to its match: the camera clamps its centre into the map's diamond that
## MapView takes from the runner's World (the scene does not set the size), and starts on the centre
## of the scenario's camera tile. It also gives UiSounds the scenario's local player and the HUD's
## AttackCues, BuildButton and EconomyPill (P535, P505a: the alert, ready and low-power chirps),
## and a lesson's match gets its coach (`TutorialHost`, P544). BattleSounds wires
## itself through its own runner export.

@export var runner: MatchRunner
@export var map_view: MapView
@export var camera: RtsCamera
@export var ui_sounds: UiSounds
@export var attack_cues: AttackCues
@export var build_button: BuildButton
@export var economy_pill: EconomyPill


func _ready() -> void:
	var scenario: ScenarioDef = runner.scenario
	camera.set_map_rect(map_view.map_diamond_px())
	camera.centre_on(
		IsoProjection.cell_centre_px(scenario.camera_start_tile.x, scenario.camera_start_tile.y)
	)
	ui_sounds.local_player = scenario.local_player
	ui_sounds.connect_attack_cues(attack_cues)
	if build_button != null or economy_pill != null:
		ui_sounds.connect_hud(build_button, economy_pill)
	TutorialHost.attach(self)  # Only a lesson's match gets a director (P544).
