class_name PauseMenu
extends ModalFrame
## The pause menu (ADR 0025 section 11, plan P124; its look is P124b, Michael's design of
## 2026-11-05). The pill's menu button asks `HudState` for the PAUSE unfold; while it is open the
## match is paused (`MatchRunner.paused`, the path the app pause uses: the sim only stops ticking,
## no Command, nothing in the replay or the hash) and the menu is the one thing that takes a touch.
## Resume (or a new match) closes it and unpauses.
## The look: a heavy dim over the field (the HUD under it is all but gone), "PAUSED" top left, a
## card (the faction's emblem, "SKIRMISH . <MAP>", the goal's short form, the objective as a
## checklist line, the match time and the units lost) and one column of full-width buttons: Resume
## (the accent's fill, 56 dp), Restart (the result screen's route: the same scenario and
## opponents, a new main scene; asks first), Surrender (the danger red; resumes, then sends
## SURRENDER through the controller's sink; asks first), Exit to menu (the dev menu until Phase
## 5's start page; asks first) and, in a debug or `dev_menu` build, the Developer menu. Under them
## the toggle chips: Vibration only (saved by `HudPrefs`; Sound, Music and Settings come with
## Phase 5 and stay hidden). Upright the card is above the column; sideways it is to the left.
## The menu is laid out from the top and leaves the foot free: Phase 5's banner ad goes there
## (Michael, 2026-11-05; no ad code here, and none on the battle screen).
## The objective is one checklist line that stays open: the snapshot cannot tell "no enemy
## Headquarters" from "none built yet" and "no production building" from "none yet" without
## reading past the fog, and a won match closes the menu for the result screen.
## The result screen is later in the scene and covers this menu; the menu does not open once the
## match has ended.

const OBJECTIVE: String = "Destroy the enemy Headquarters and every production building."
const GOAL: String = "DESTROY THE ENEMY BASE"  ## The objective's short form, the card's title.
const GLYPH_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"
const EMBLEM_ART: String = "res://assets/art/svg/icons/emblem_%s.svg"
const EMBLEMS: Array[String] = ["renew", "fossil"]  ## By the faction's index, as the accents.
const GLYPH_DP: float = 24.0  ## The glyph in front of a button's word (P118g drew them).
const CARD_DP: float = 300.0  ## The left column's width sideways; upright it takes the width.
const ACTIONS_DP: float = 300.0  ## The least the button column takes sideways.
const BADGE_DP: float = 48.0  ## The round badge of the card, and the emblem in it.
const EMBLEM_DP: float = 32.0
const CHECK_DP: float = 24.0  ## The checklist circle.
const PRIMARY_DP: float = 56.0  ## Resume; every other button is 48 dp (touch-ui-rules' floor).
const SECONDARY_DP: float = 48.0
const TIGHT_DP: float = 8.0  ## The gap between buttons and between the card's rows.
const BUTTON_GAP_DP: float = 12.0  ## The glyph's gap to the word.
const PLAIN: StringName = &"PauseButton"
const PRIMARY: StringName = &"PausePrimary"
const DANGER: StringName = &"PauseDanger"
const CHIP_ON: StringName = &"PauseChip"
const CHIP_OFF: StringName = &"PauseChipOff"
const ACCENTS: Array[StringName] = [&"AccentRenew", &"AccentFossil"]
const SCRIM: StringName = &"PauseScrim"

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink (Surrender).
@export var feed: HudStateFeed  ## Its `state` holds the PAUSE unfold.
@export var pill: EconomyPill  ## Its menu button opens this menu.

var _body: BoxContainer  ## The card's column and the button column.
var _left: VBoxContainer  ## "PAUSED" and the card.
var _actions: VBoxContainer  ## The buttons, and the toggle chips under them.
var _toggles: HBoxContainer
var _tight: Array[BoxContainer] = []  ## Spaced TIGHT_DP apart.
var _loose: Array[BoxContainer] = []  ## Spaced GAP_DP apart.
var _glyphed: Array[Button] = []  ## Every button with a glyph, for the dp step.
var _emblem: TextureRect
var _kicker: Label
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
	_body.name = &"Body"
	_left = VBoxContainer.new()
	_actions = VBoxContainer.new()
	_toggles = HBoxContainer.new()
	super()
	_unframe()
	column.add_child(_body)
	_body.add_child(_left)
	_body.add_child(_actions)
	add_label(_left, "PAUSED", &"CapsBigTitle")
	_build_card()
	_resume = _add_action("RESUME", "resume", _resume_pressed, &"ResumeButton", PRIMARY)
	_add_action("RESTART", "restart", _restart_dialog_open, &"RestartButton", PLAIN)
	_add_action("SURRENDER", "surrender", _surrender_dialog_open, &"SurrenderButton", DANGER)
	_add_action("EXIT TO MENU", "exit", _exit_dialog_open, &"ExitButton", PLAIN)
	if DevRoutes.is_enabled():
		_add_action("DEVELOPER MENU", "menu", _open_dev_menu, &"DevMenuButton", PLAIN)
	_actions.add_child(_toggles)
	_vibration = _add_action("", "vibration", _toggle_vibration, &"VibrationButton", CHIP_ON)
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


## The frame's plate and centring go: the column sits at the top of the scroll, full width, and
## the dim is the pause's own (the HUD under it is hidden by it, ADR 0025 section 1's table).
func _unframe() -> void:
	var scrim: PanelContainer = get_child(0) as PanelContainer
	scrim.theme_type_variation = SCRIM
	var panel: Node = column.get_parent()
	var centre: Node = panel.get_parent()
	var scroll: Node = centre.get_parent()
	panel.remove_child(column)
	scroll.remove_child(centre)
	centre.free()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)


## The card: the emblem in a round badge, the kicker and the goal, the objective's checklist line
## and the foot line.
func _build_card() -> void:
	var card: PanelContainer = PanelContainer.new()
	card.theme_type_variation = &"PauseCard"
	_left.add_child(card)
	var rows: VBoxContainer = VBoxContainer.new()
	_tight.append(rows)
	card.add_child(rows)
	var head: HBoxContainer = HBoxContainer.new()
	_loose.append(head)
	rows.add_child(head)
	var badge: PanelContainer = PanelContainer.new()
	badge.theme_type_variation = &"PauseBadge"
	_fix_size(badge, Vector2(BADGE_DP, BADGE_DP))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(badge)
	_emblem = TextureRect.new()
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fix_size(_emblem, Vector2(EMBLEM_DP, EMBLEM_DP))
	badge.add_child(_emblem)
	var words: VBoxContainer = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	_kicker = add_label(words, "", &"PauseMuted")
	var goal: Label = add_label(words, GOAL, &"CapsTitle")
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var item: HBoxContainer = HBoxContainer.new()
	_loose.append(item)
	rows.add_child(item)
	var circle: PanelContainer = PanelContainer.new()
	circle.name = &"ObjectiveCircle"
	circle.theme_type_variation = &"PauseCheck"
	_fix_size(circle, Vector2(CHECK_DP, CHECK_DP))
	circle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	item.add_child(circle)
	var objective: Label = add_label(item, OBJECTIVE, &"Label")
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var foot: HBoxContainer = HBoxContainer.new()
	_loose.append(foot)
	rows.add_child(foot)
	_time = add_label(foot, "", &"PauseMuted")
	_lost = add_label(foot, "", &"PauseMuted")


func _fix_size(control: Control, dp: Vector2) -> void:
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = dp
	control.add_child(floor_dp)


func _apply_dp() -> void:
	super()
	_body.vertical = HudLayout.is_portrait()
	var gap: int = roundi(UiScale.dp(TIGHT_DP))
	_body.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)) * 2)
	for box: BoxContainer in [_left, _actions, _toggles] + _tight:
		box.add_theme_constant_override("separation", gap)
	for box: BoxContainer in _loose:
		box.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_left.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if _body.vertical else Control.SIZE_SHRINK_BEGIN
	)
	_left.custom_minimum_size.x = 0.0 if _body.vertical else UiScale.dp(CARD_DP)
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.custom_minimum_size.x = 0.0 if _body.vertical else UiScale.dp(ACTIONS_DP)
	for button: Button in _glyphed:
		button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(GLYPH_DP)))
		button.add_theme_constant_override("h_separation", roundi(UiScale.dp(BUTTON_GAP_DP)))


## One button of the column (the chip of the toggle row too: `variation` PauseChip) of type
## variation `variation`, with the P118g glyph `glyph` in front of its word, left aligned.
func _add_action(
	text: String, glyph: String, action: Callable, node_name: StringName, variation: StringName
) -> Button:
	var button: Button = Button.new()
	var chip: bool = variation == CHIP_ON
	button.theme_type_variation = variation
	button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.expand_icon = false
	button.icon = load(GLYPH_ART % glyph) as Texture2D
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if chip else Control.SIZE_EXPAND_FILL
	_fix_size(button, Vector2(0.0, PRIMARY_DP if variation == PRIMARY else SECONDARY_DP))
	button.pressed.connect(action)
	(_toggles if chip else _actions).add_child(button)
	_glyphed.append(button)
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
	_kicker.text = ("SKIRMISH \u00b7 %s" % source.get_file().get_basename().capitalize()).to_upper()
	var snap: MatchSnapshot = runner.snapshot
	var seconds: int = 0 if snap == null else snap.tick / Sim.TICK_RATE
	_time.text = "Time %d:%02d" % [seconds / 60, seconds % 60]
	var lost: int = 0
	if snap != null and scenario.local_player < snap.stat_lost_units.size():
		lost = snap.stat_lost_units[scenario.local_player]
	_lost.text = "Units lost: %d" % lost
	_show_emblem(snap, scenario.local_player)


## The local player's faction emblem (the first row it owns names the faction, as the build
## button's accent does), tinted with that faction's accent.
func _show_emblem(snap: MatchSnapshot, player: int) -> void:
	var faction: int = 0
	if snap != null:
		for row: int in snap.unit_id.size():
			if snap.owner[row] == player:
				faction = clampi(snap.type_faction[snap.type_index[row]], 0, EMBLEMS.size() - 1)
				break
	_emblem.texture = load(EMBLEM_ART % EMBLEMS[faction]) as Texture2D
	_emblem.modulate = get_theme_color(&"light", ACCENTS[faction])


func _show_vibration() -> void:
	var on: bool = HudPrefs.haptics_enabled()
	_vibration.text = "VIBRATION: ON" if on else "VIBRATION: OFF"
	_vibration.theme_type_variation = CHIP_ON if on else CHIP_OFF


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
