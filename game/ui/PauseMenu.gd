class_name PauseMenu
extends ModalFrame
## The pause menu (ADR 0025 section 11, plan P124). The pill's menu button asks `HudState` for the
## PAUSE unfold; while it is open the match is paused (`MatchRunner.paused`, the path the app pause
## uses: the sim only stops ticking, no Command, nothing in the replay or the hash) and the menu is
## the one thing that takes a touch. Resume (or a new match) closes it and unpauses.
## The card: "SKIRMISH" and the map's name, the objective, the match time and the units lost.
## Buttons (two to a row, with the Vibration switch across the foot, so they fit a phone held
## sideways): Resume; Restart (the result screen's route: the same scenario and opponents, a new
## main scene; asks first); Surrender (resumes, then sends SURRENDER through the controller's sink;
## asks first); Exit to menu (the dev menu until Phase 5's start page; asks first); in a debug or
## `dev_menu` build the Developer menu; and the Vibration switch, saved by `HudPrefs`. Sound, Music
## and Settings come with Phase 5. No ad, ever: this is the battle (admob-policy).
## The result screen is later in the scene and covers this menu; the menu does not open once the
## match has ended.

const OBJECTIVE: String = "Destroy the enemy Headquarters and every production building."
const GLYPH_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"
const GLYPH_DP: float = 24.0  ## The glyph in front of a button's word (P118g drew them).
const CARD_DP: float = 200.0  ## The card's width: the buttons take the rest (two to a row).

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink (Surrender).
@export var feed: HudStateFeed  ## Its `state` holds the PAUSE unfold.
@export var pill: EconomyPill  ## Its menu button opens this menu.

var _body: BoxContainer
var _card: VBoxContainer
var _actions: VBoxContainer  ## The grid of buttons, and the Vibration switch under it.
var _buttons: GridContainer
var _map: Label
var _time: Label
var _lost: Label
var _resume: Button
var _vibration: Button
var _restart_dialog: ConfirmDialog
var _surrender_dialog: ConfirmDialog
var _exit_dialog: ConfirmDialog
var _surrendered_in: int = -1  ## match_serial of the match a SURRENDER was sent in.


func _ready() -> void:
	_body = BoxContainer.new()  # Before `super()`, whose `_apply_dp` sizes them.
	_card = VBoxContainer.new()
	_actions = VBoxContainer.new()
	_buttons = GridContainer.new()
	_buttons.columns = 2
	super()
	column.add_child(_body)
	_body.add_child(_card)
	add_label(_card, "PAUSED", &"CapsBigTitle")
	add_label(_card, "SKIRMISH", &"CapsTitle")
	_map = add_label(_card, "", &"Label")
	add_label(_card, OBJECTIVE, &"Label").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_time = add_label(_card, "", &"NumberLabel")
	_lost = add_label(_card, "", &"NumberLabel")
	_body.add_child(_actions)
	_actions.add_child(_buttons)
	_resume = _add_action("RESUME", "resume", _resume_pressed, &"ResumeButton")
	_add_action("RESTART", "restart", _restart_dialog_open, &"RestartButton")
	_add_action("SURRENDER", "surrender", _surrender_dialog_open, &"SurrenderButton")
	_add_action("EXIT TO MENU", "exit", _exit_dialog_open, &"ExitButton")
	if DevRoutes.is_enabled():
		_add_action("DEVELOPER MENU", "", _open_dev_menu, &"DevMenuButton")
	_vibration = _add_action("", "vibration", _toggle_vibration, &"VibrationButton", _actions)
	_restart_dialog = _make_dialog("RESTART?", "You lose this match.", "RESTART", _restart)
	_surrender_dialog = _make_dialog(
		"SURRENDER?", "You lose the match at once.", "SURRENDER", _surrender
	)
	_exit_dialog = _make_dialog("EXIT TO MENU?", "You lose this match.", "EXIT", _open_dev_menu)
	if pill != null:
		pill.menu_pressed.connect(_on_menu_pressed)
	feed.state.changed.connect(_on_changed)
	runner.match_ended.connect(_on_match_ended)
	_apply_dp()


func _apply_dp() -> void:
	super()
	_body.vertical = HudLayout.is_portrait()
	_body.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)) * 2)
	var gap: int = roundi(UiScale.dp(GAP_DP))
	_buttons.add_theme_constant_override("h_separation", gap)
	_buttons.add_theme_constant_override("v_separation", gap)
	_card.custom_minimum_size.x = UiScale.dp(CARD_DP)
	_actions.add_theme_constant_override("separation", gap)
	for row: Container in [_buttons, _actions]:
		for button: Node in row.get_children():
			if button is Button:
				button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(GLYPH_DP)))


## One button of the grid, with the P118g glyph `glyph` ("" for none) in front of its word.
func _add_action(
	text: String, glyph: String, action: Callable, node_name: StringName, parent: Container = null
) -> Button:
	var button: Button = add_button(_buttons if parent == null else parent, text, action)
	button.name = node_name
	if glyph != "":
		button.icon = load(GLYPH_ART % glyph) as Texture2D
		button.expand_icon = false
	return button


func _make_dialog(
	question: String, detail: String, yes_text: String, on_yes: Callable
) -> ConfirmDialog:
	var dialog: ConfirmDialog = ConfirmDialog.new()
	dialog.question = question
	dialog.detail = detail
	dialog.yes_text = yes_text
	dialog.no_text = "KEEP PLAYING"
	dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dialog)
	dialog.confirmed.connect(on_yes)
	return dialog


func _on_menu_pressed() -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap != null and (snap.match_end_tick > 0 or snap.match_serial == _surrendered_in):
		return  # The result screen covers the HUD, and a SURRENDER is on its way: nothing opens.
	feed.state.open(HudState.Unfold.PAUSE)


## PAUSE opened: pause the match and show the card. PAUSE left (Resume, a new match): unpause.
## A `changed` while it stays open (a bar width, the pin) leaves the focus where it is.
func _on_changed(previous: HudState.Unfold) -> void:
	var open: bool = feed.state.is_open(HudState.Unfold.PAUSE)
	if open:
		runner.paused = true
		if previous != HudState.Unfold.PAUSE:
			_fill_card()
			_show_vibration()
			show_over(_resume)
	elif previous == HudState.Unfold.PAUSE:
		runner.paused = false
		_close_dialogs()
		visible = false


@warning_ignore("integer_division")
func _fill_card() -> void:
	var scenario: ScenarioDef = runner.scenario
	var source: String = scenario.map.resource_path if scenario.map != null else ""
	_map.text = source.get_file().get_basename().capitalize()
	var snap: MatchSnapshot = runner.snapshot
	var seconds: int = 0 if snap == null else snap.tick / Sim.TICK_RATE
	_time.text = "Time %d:%02d" % [seconds / 60, seconds % 60]
	var lost: int = 0
	if snap != null and scenario.local_player < snap.stat_lost_units.size():
		lost = snap.stat_lost_units[scenario.local_player]
	_lost.text = "Units lost %d" % lost


func _show_vibration() -> void:
	_vibration.text = "VIBRATION: ON" if HudPrefs.haptics_enabled() else "VIBRATION: OFF"


func _toggle_vibration() -> void:
	HudPrefs.set_haptics_enabled(not HudPrefs.haptics_enabled())
	_show_vibration()


func _resume_pressed() -> void:
	feed.state.close(HudState.Unfold.PAUSE)


func _restart_dialog_open() -> void:
	_restart_dialog.open()


func _surrender_dialog_open() -> void:
	_surrender_dialog.open()


func _exit_dialog_open() -> void:
	_exit_dialog.open()


func _restart() -> void:
	DevRoutes.open_main_with(get_tree(), runner.scenario.resource_path, runner.opponents)


## Resumes first, so the tick that carries the Command runs.
func _surrender() -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap != null:
		if snap.match_serial == _surrendered_in:
			return  # Once per match, as P90's button was.
		_surrendered_in = snap.match_serial
	feed.state.close(HudState.Unfold.PAUSE)
	controller.command_sink.call(Command.surrender(runner.scenario.local_player))


func _open_dev_menu() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)


func _on_match_ended(_winner: int) -> void:
	feed.state.close(HudState.Unfold.PAUSE)
	_close_dialogs()


func _close_dialogs() -> void:
	for dialog: ConfirmDialog in [_restart_dialog, _surrender_dialog, _exit_dialog]:
		dialog.close()
