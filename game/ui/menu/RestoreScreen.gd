class_name RestoreScreen
extends MenuScreen
## What Continue shows while the match is played again (ADR 0042 section 6, plan P515): an opaque
## screen with a progress bar and Cancel. It starts `MenuFlow.continue_match()` once, follows the
## `Restorer`'s `progressed` and asks `MenuFlow.cancel_restore()` on Cancel (the file stays). On
## success the match replaces the menu; on a failure the menu comes back with a notice.

var _bar: ProgressBar
var _started: bool = false


func _ready() -> void:
	super()
	MainMenuText.register()
	var title: Label = Label.new()
	title.text = tr(MainMenuText.RESTORING)
	title.theme_type_variation = &"MenuTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_bar = ProgressBar.new()
	_bar.theme_type_variation = &"MenuXpBar"
	_bar.show_percentage = false
	_bar.custom_minimum_size.y = UiScale.dp(MainMenu.XP_BAR_DP)
	column.add_child(_bar)
	add_button(tr(MainMenuText.RESTORE_CANCEL), MenuFlow.cancel_restore)
	MenuFlow.restore_started.connect(_on_started)
	if not _started:
		_started = true
		MenuFlow.continue_match()  # A coroutine nobody awaits: this screen is gone when it ends.


## Back stops the restore like Cancel; the file stays.
func on_back() -> bool:
	MenuFlow.cancel_restore()
	return true


func _exit_tree() -> void:
	if MenuFlow.restore_started.is_connected(_on_started):
		MenuFlow.restore_started.disconnect(_on_started)


func _on_started(restorer: Restorer) -> void:
	restorer.progressed.connect(_on_progress)


func _on_progress(done: int, total: int) -> void:
	_bar.max_value = maxi(total, 1)
	_bar.value = done
