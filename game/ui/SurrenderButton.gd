class_name SurrenderButton
extends Button
## The Surrender button under the Dev button (ADR 0019 section 6, plan P90): a tap asks first, only
## the confirm sends SURRENDER, as a Command through the controller's sink. It lives here until P124
## moves it into the pause menu (ADR 0025 section 11), and sets the dp gap of the stack it is in.

const GAP_DP: float = 8.0

@export var runner: MatchRunner
@export var controller: PlayerController
@export var dialog: ConfirmDialog


func _ready() -> void:
	pressed.connect(dialog.open)
	dialog.confirmed.connect(_on_confirmed)
	runner.match_ended.connect(_on_match_ended)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


func _apply_dp() -> void:
	var row: BoxContainer = get_parent() as BoxContainer
	row.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))


func _on_confirmed() -> void:
	disabled = true
	controller.command_sink.call(Command.surrender(runner.scenario.local_player))


func _on_match_ended(_winner: int) -> void:
	disabled = true
	dialog.close()
