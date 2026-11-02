class_name SurrenderButton
extends Button
## The Surrender button under the Dev button (ADR 0019 section 6, plan P90): a tap asks first, only
## the confirm sends SURRENDER, as a Command through the controller's sink. It lives here until P124
## moves it into the pause menu (ADR 0025 section 11).

@export var runner: MatchRunner
@export var controller: PlayerController
@export var dialog: ConfirmDialog


func _ready() -> void:
	pressed.connect(dialog.open)
	dialog.confirmed.connect(_on_confirmed)
	runner.match_ended.connect(_on_match_ended)


func _on_confirmed() -> void:
	disabled = true
	controller.command_sink.call(Command.surrender(runner.scenario.local_player))


func _on_match_ended(_winner: int) -> void:
	disabled = true
	dialog.close()
