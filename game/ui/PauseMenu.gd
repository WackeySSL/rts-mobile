class_name PauseMenu
extends ModalFrame
## The pause menu (ADR 0025 section 11, plan P124; its look is P124b, Michael's design of
## 2026-11-05). The pill's menu button asks `HudState` for the PAUSE unfold; while it is open the
## match is paused (`MatchRunner.paused`, the path the app pause uses: the sim only stops ticking,
## no Command, nothing in the replay or the hash) and the menu is the one thing that takes a touch.
## Resume (or a new match) closes it and unpauses.
## The look: the usual dim over the field and the HUD's own controls hidden under it (ADR 0025's
## layout table: "under the drawer and pause"), "PAUSED" top left, a card (the faction's emblem,
## "SKIRMISH", the map's name, the objective as a checklist line, the match time and the units
## lost) and one column of full-width buttons: Resume
## (the accent's fill, 56 dp), Restart (the result screen's route: the same scenario, level and
## opponents, a new main scene; asks first), Surrender (the danger red; resumes, then sends
## SURRENDER through the controller's sink; asks first), How to play and Settings side by side
## (one row: the foot must stay free; a `MenuStack` over the battle holds P527's screen and Back
## returns here; Settings is the `settings` route of `MenuRoutes` when a row registered it, else
## disabled: TODO P526), Exit to menu (asks first) and, in a debug or `dev_menu` build, the
## Developer menu beside it. Under them the toggle chips: Vibration (saved by `HudPrefs`), Sound
## (the Sfx and Ui buses) and Music (the `AudioService` steps: off is 0, on is the default step of
## `AudioSettings`). Upright the card is above the column; sideways it is to the left.
## Phase 5 (P531, ADR 0043 section 6, ADR 0042 section 5): when `MenuFlow` owns the match, Restart
## and Exit go through it (`restart()`, `return_to_menu()`; both coroutines) and Surrender calls
## `mark_surrendered()` before its Command; a match `DevRoutes` made keeps the dev routes. A
## tutorial lesson's Exit reads "LEAVE TUTORIAL" and goes the same way: no ad is touched. The menu
## opens by itself when the app pauses or loses focus, and the Android Back button opens and closes
## it (it closes a question or the How to play overlay first); it never opens over a result.
## The one ad of the battle screen (Michael, 2026-11-05; ADR 0039 section 6, plan P435): P430's
## `AdBannerBand` at the foot of the open menu, only upright and only where the foot is free (the
## content does not scroll and leaves the band's room, its 16 dp gap included). It is made when the
## menu opens and freed when it closes, so no banner exists while the menu is closed; a resize or
## a turn evaluates it again. The menu is laid out from the top. No rewarded or interstitial ad.
## The objective is one checklist line that stays open: the snapshot cannot tell "no enemy
## Headquarters" from "none built yet" and "no production building" from "none yet" without
## reading past the fog, and a won match closes the menu for the result screen.
## The result screen is later in the scene and covers this menu; the menu does not open once the
## match has ended.

const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")
const OBJECTIVE: String = "Destroy the enemy Headquarters and every production building."
const GLYPH_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"
const EMBLEM_ART: String = "res://assets/art/svg/icons/emblem_%s.svg"
const GLYPH_DP: float = 24.0  ## The glyph in front of a button's word (P118g drew them).
const CARD_DP: float = 300.0  ## The left column's width sideways; upright it takes the width.
const BADGE_DP: float = 48.0  ## The round badge of the card, and the emblem in it.
const EMBLEM_DP: float = 32.0
const CHECK_DP: float = 24.0  ## The checklist circle.
const PRIMARY_DP: float = 56.0  ## Resume; every other button is 48 dp (touch-ui-rules' floor).
const SECONDARY_DP: float = 48.0
const TIGHT_DP: float = 8.0  ## The gap between buttons and between the card's rows.
const BUTTON_GAP_DP: float = 12.0  ## The glyph's gap to the word.
const PLAIN: StringName = &"PauseButton"
const DANGER: StringName = &"PauseDanger"
const PRIMARY_LOOK: StringName = &"PausePrimary"  ## At build; `_show_side` swaps in the side's.
const CHIP_LOOK: StringName = &"PauseChip"
const CHIP_OFF: StringName = &"PauseChipOff"
## Per faction id (`faction_ids`): the accent's theme type, and the variations of Resume, the
## badge and the ON chip that carry it (the Lumen Accord's cyan is the design's).
const SIDES: Dictionary[StringName, Dictionary] = {
	&"renew":
	{
		&"accent": &"AccentRenew",
		&"primary": &"PausePrimary",
		&"badge": &"PauseBadge",
		&"chip": &"PauseChip"
	},
	&"fossil":
	{
		&"accent": &"AccentFossil",
		&"primary": &"PausePrimaryFossil",
		&"badge": &"PauseBadgeFossil",
		&"chip": &"PauseChipFossil"
	},
}
const FALLBACK_SIDE: StringName = &"renew"

@export var runner: MatchRunner
@export var controller: PlayerController  ## The Commands' sink (Surrender).
@export var feed: HudStateFeed  ## Its `state` holds the PAUSE unfold.
@export var pill: EconomyPill  ## Its menu button opens this menu.

## Tests inject a service for the foot banner; null means the AdService autoload.
var ad_service: AdServiceScript = null
## Tests inject fakes; null means the autoloads (MenuFlow, AudioService) and the shared routes.
var menu_flow: Node = null
var audio: Node = null
var routes: MenuRoutes = null  ## Null means `MenuRoutes.shared`, read when used.

var _body: BoxContainer  ## The card's column and the button column.
var _left: VBoxContainer  ## "PAUSED" and the card.
var _actions: VBoxContainer  ## The buttons, and the toggle chips under them.
var _toggles: HFlowContainer
var _pair: HBoxContainer  ## How to play and Settings side by side: one row of the column.
var _leave: HBoxContainer  ## Exit, and the Developer menu beside it in a debug build.
var _tight: Array[BoxContainer] = []  ## Spaced TIGHT_DP apart.
var _loose: Array[BoxContainer] = []  ## Spaced GAP_DP apart.
var _glyphed: Array[Button] = []  ## Every button with a glyph, for the dp step.
var _emblem: TextureRect
var _badge: PanelContainer
var _side: StringName = FALLBACK_SIDE
var _title: Label
var _hidden: Dictionary[Control, Color] = {}  ## The HUD controls hidden while PAUSE shows.
var _time: Label
var _lost: Label
var _resume: Button
var _vibration: Button
var _sound: Button
var _music: Button
var _exit_button: Button
var _settings: Button
var _help: MenuStack  ## The How to play overlay while it is open.
var _restart_dialog: ConfirmDialog
var _surrender_dialog: ConfirmDialog
var _exit_dialog: ConfirmDialog
var _surrendered_in: int = -1  ## match_serial of the match a SURRENDER was sent in.
var _foot: MarginContainer  ## The foot banner's host, freed with it; null while no band exists.
var _band: AdBannerBand
var _foot_check: int = 0  ## Bumped by each placement, so an older awaited check stands down.


func _ready() -> void:
	_body = BoxContainer.new()  # Before `super()`, whose `_apply_dp` sizes them.
	_body.name = &"Body"
	_left = VBoxContainer.new()
	_actions = VBoxContainer.new()
	_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggles = HFlowContainer.new()
	_pair = HBoxContainer.new()
	_leave = HBoxContainer.new()
	super()
	_unframe()
	column.add_child(_body)
	_body.add_child(_left)
	_body.add_child(_actions)
	add_label(_left, "PAUSED", &"CapsBigTitle")
	_build_card()
	_resume = _add_action("RESUME", "resume", _resume_pressed, &"ResumeButton", PRIMARY_LOOK)
	_add_action("RESTART", "restart", _restart_dialog_open, &"RestartButton", PLAIN)
	_add_action("SURRENDER", "surrender", _surrender_dialog_open, &"SurrenderButton", DANGER)
	_actions.add_child(_pair)
	_add_action("HOW TO PLAY", "", _open_help, &"HelpButton", PLAIN, _pair)
	_settings = _add_action("SETTINGS", "", _open_settings, &"SettingsButton", PLAIN, _pair)
	_actions.add_child(_leave)
	_exit_button = _add_action(
		"EXIT TO MENU", "exit", _exit_dialog_open, &"ExitButton", PLAIN, _leave
	)
	if DevRoutes.is_enabled():
		_add_action("DEV MENU", "", _open_dev_menu, &"DevMenuButton", PLAIN, _leave)
	_actions.add_child(_toggles)
	_vibration = _add_action("", "vibration", _toggle_vibration, &"VibrationButton", CHIP_LOOK)
	_sound = _add_action("", "", _toggle_sound, &"SoundButton", CHIP_LOOK)
	_music = _add_action("", "", _toggle_music, &"MusicButton", CHIP_LOOK)
	_restart_dialog = _make_dialog("RESTART?", "You lose this match.", "RESTART", _restart)
	_surrender_dialog = _make_dialog(
		"SURRENDER?", "You lose the match at once.", "SURRENDER", _surrender
	)
	_exit_dialog = _make_dialog("EXIT TO MENU?", "You lose this match.", "EXIT", _exit_match)
	if pill != null:
		pill.menu_pressed.connect(_on_menu_pressed)
	for dialog: ConfirmDialog in [_restart_dialog, _surrender_dialog, _exit_dialog]:
		dialog.visibility_changed.connect(_on_dialog_visibility)
	feed.state.changed.connect(_on_changed)
	runner.match_ended.connect(_on_match_ended)
	_apply_dp()


## The frame's plate and centring go: the column sits at the top of the scroll, full width.
func _unframe() -> void:
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
	_badge = PanelContainer.new()
	_badge.name = &"Badge"
	_badge.theme_type_variation = &"PauseBadge"
	_fix_size(_badge, Vector2(BADGE_DP, BADGE_DP))
	_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_badge)
	_emblem = TextureRect.new()
	_emblem.name = &"Emblem"
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fix_size(_emblem, Vector2(EMBLEM_DP, EMBLEM_DP))
	_emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_badge.add_child(_emblem)
	var words: VBoxContainer = VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(words)
	add_label(words, "SKIRMISH", &"PauseMuted")
	_title = add_label(words, "", &"CapsTitle")
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	for box: BoxContainer in [_left, _actions, _pair, _leave] + _tight:
		box.add_theme_constant_override("separation", gap)
	_toggles.add_theme_constant_override("h_separation", gap)
	# A wrapped chip row (a 360 dp phone upright) keeps half the gap, so the foot stays free.
	_toggles.add_theme_constant_override("v_separation", roundi(UiScale.dp(TIGHT_DP / 2.0)))
	for box: BoxContainer in _loose:
		box.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	if visible:
		_place_banner()  # A resize or a turn while open.
	_left.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL if _body.vertical else Control.SIZE_SHRINK_BEGIN
	)
	_left.custom_minimum_size.x = 0.0 if _body.vertical else UiScale.dp(CARD_DP)
	for button: Button in _glyphed:
		button.add_theme_constant_override("icon_max_width", roundi(UiScale.dp(GLYPH_DP)))
		button.add_theme_constant_override("h_separation", roundi(UiScale.dp(BUTTON_GAP_DP)))


## One button of the column (the chip of the toggle row too: `variation` PauseChip) of type
## variation `variation`, with the P118g glyph `glyph` in front of its word, left aligned.
func _add_action(
	text: String,
	glyph: String,
	action: Callable,
	node_name: StringName,
	variation: StringName,
	parent: Container = null
) -> Button:
	var button: Button = Button.new()
	var chip: bool = variation == CHIP_LOOK
	button.theme_type_variation = variation
	button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.expand_icon = false
	if glyph != "":
		button.icon = load(GLYPH_ART % glyph) as Texture2D
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if chip else Control.SIZE_EXPAND_FILL
	_fix_size(button, Vector2(0.0, PRIMARY_DP if variation == PRIMARY_LOOK else SECONDARY_DP))
	button.pressed.connect(action)
	if parent == null:
		parent = _toggles if chip else _actions
	parent.add_child(button)
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
	if _can_open():
		feed.state.open(HudState.Unfold.PAUSE)


## The result screen covers the HUD, and a SURRENDER is on its way: nothing opens.
func _can_open() -> bool:
	if runner == null or feed == null:
		return false
	var snap: MatchSnapshot = runner.snapshot
	return snap == null or (snap.match_end_tick <= 0 and snap.match_serial != _surrendered_in)


## The app pauses or loses focus (a call, the shade, a hidden tab): the menu opens, so the match
## stays paused under it until Resume (ADR 0042 section 5). Android's Back opens and closes it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_on_menu_pressed()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


## Decided at once, before the overlay's own deferred pop runs: the overlay (the How to play
## screen) takes Back itself; an open question closes (keep playing); then the menu toggles.
func _on_back() -> void:
	if _help != null or feed == null:
		return
	if visible and _asking():
		_close_dialogs()
		_resume.grab_focus()
	elif feed.state.is_open(HudState.Unfold.PAUSE):
		_resume_pressed()
	elif _can_open():
		feed.state.open(HudState.Unfold.PAUSE)


## PAUSE opened: pause the match and show the card. PAUSE left (Resume, a new match): unpause.
## A `changed` while it stays open (a bar width, the pin) leaves the focus where it is.
func _on_changed(previous: HudState.Unfold) -> void:
	var open: bool = feed.state.is_open(HudState.Unfold.PAUSE)
	if open:
		runner.paused = true
		if previous != HudState.Unfold.PAUSE:
			_fill_card()
			_show_chips()
			_show_exit()
			_hide_hud()
			show_over(_resume)
			_place_banner()
	elif previous == HudState.Unfold.PAUSE:
		runner.paused = false
		_close_help()
		_drop_banner()
		_close_dialogs()
		_restore_hud()
		visible = false


@warning_ignore("integer_division")
func _fill_card() -> void:
	var scenario: ScenarioDef = runner.scenario
	var source: String = scenario.map.resource_path if scenario.map != null else ""
	_title.text = source.get_file().get_basename().capitalize().to_upper()
	_title.visible = _title.text != ""
	var snap: MatchSnapshot = runner.snapshot
	var seconds: int = 0 if snap == null else snap.tick / Sim.TICK_RATE
	_time.text = "Time %d:%02d" % [seconds / 60, seconds % 60]
	var lost: int = 0
	if snap != null and scenario.local_player < snap.stat_lost_units.size():
		lost = snap.stat_lost_units[scenario.local_player]
	_lost.text = "Units lost: %d" % lost
	_show_side(snap, scenario.local_player)


## The local player's side: `type_faction` indexes `faction_ids`, so the id is the key (the first
## row the player owns names it, as BuildSidebar's tab does). Its emblem, in the accent's light, and
## the variations of Resume, the badge and the ON chip.
func _show_side(snap: MatchSnapshot, player: int) -> void:
	var id: StringName = FALLBACK_SIDE
	if snap != null:
		for row: int in snap.unit_id.size():
			if snap.owner[row] != player:
				continue
			var index: int = snap.type_faction[snap.type_index[row]]
			if (
				index >= 0
				and index < snap.faction_ids.size()
				and SIDES.has(snap.faction_ids[index])
			):
				id = snap.faction_ids[index]
				break  # A row without a faction is skipped, as BuildSidebar skips it.
	_side = id
	var side: Dictionary = SIDES[id]
	_emblem.texture = load(EMBLEM_ART % id) as Texture2D
	_emblem.modulate = get_theme_color(&"light", side[&"accent"])
	_badge.theme_type_variation = side[&"badge"]
	_resume.theme_type_variation = side[&"primary"]


## The HUD's controls (the pill, the scope, the group column, BUILD, the command bar and the rest
## of the layer) go clear under the menu and come back at Resume. Their own `visible` is theirs
## (each `place` sets it), so the menu clears their `modulate`, which no one of them writes, and
## puts the saved one back; the result screen and this menu stay.
func _hide_hud() -> void:
	var covered: Array[Node] = get_parent().get_children()
	for node: Node in get_parent().find_children("*", "Control", true, false):
		if (node as Control).top_level:  # A top-level child (the pill's flash) ignores its parent.
			covered.append(node)
	for node: Node in covered:
		var control: Control = node as Control
		if control == null or control == self or control is ResultScreen or is_ancestor_of(control):
			continue
		_hidden[control] = control.modulate
		control.modulate = get_theme_color(&"hidden", &"PauseHud")


func _restore_hud() -> void:
	for control: Control in _hidden:
		if is_instance_valid(control):
			control.modulate = _hidden[control]
	_hidden.clear()


## The foot banner (P435). The band is built hidden, so it holds no show; two frames on, when the
## layout has settled, it is shown only where the banner fits under the content (no scroll, its
## 16 dp gap kept to the last button) and freed where it does not, so a drop never shows a banner.
## Nothing sideways and nothing under an open confirm dialog. `hide_first` takes a shown band down
## while a resize settles, so no banner stands unchecked; the band's own size change (a new banner
## height) checks again without it.
func _place_banner(hide_first: bool = true) -> void:
	if not visible or not HudLayout.is_portrait() or _asking():
		_drop_banner()
		return
	_foot_check += 1
	var serial: int = _foot_check
	if _band == null:
		_foot = MarginContainer.new()
		_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_foot.name = &"Foot"
		add_child(_foot)
		move_child(_foot, 2)  # Under the dialogs.
		_foot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var box: VBoxContainer = VBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_END
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_foot.add_child(box)
		_band = AdBannerBand.new()
		_band.visible = false
		_band.service = ad_service
		box.add_child(_band)
		_band.minimum_size_changed.connect(_place_banner.bind(false))
	elif hide_first:
		_band.visible = false
	_fit_foot()
	_check_foot.call_deferred(serial, 2)


## Waits `frames` more frames (no await: a menu freed meanwhile just stops) and then fits the band.
func _check_foot(serial: int, frames: int) -> void:
	if serial != _foot_check or _band == null:
		return
	if frames > 0:
		get_tree().process_frame.connect(_check_foot.bind(serial, frames - 1), CONNECT_ONE_SHOT)
		return
	var content_end: float = column.global_position.y + column.get_combined_minimum_size().y
	var room: float = UiScale.safe_rect_base().end.y - content_end
	if room < _band.preview_reserved_px() - 0.5:
		_drop_banner()
	else:
		_band.visible = true


## The foot's margins: the safe rect's own sides, the bottom its own inset (not the larger of the
## two, as SafeAreaMargin takes), as MenuScreen does, so the band lies on the safe rect's bottom.
func _fit_foot() -> void:
	var full: Rect2 = get_viewport().get_visible_rect()
	var safe: Rect2 = UiScale.safe_rect_base().intersection(full)
	var inset: Vector2i = SafeAreaMargin.inset_px(full, 0.0)
	_foot.add_theme_constant_override("margin_left", inset.x)
	_foot.add_theme_constant_override("margin_right", inset.x)
	_foot.add_theme_constant_override("margin_bottom", ceili(maxf(full.end.y - safe.end.y, 0.0)))


## A question or the How to play overlay stands over the foot: no banner there.
func _asking() -> bool:
	return (
		_restart_dialog.visible
		or _surrender_dialog.visible
		or _exit_dialog.visible
		or _help != null
	)


func _on_dialog_visibility() -> void:
	if visible:
		_place_banner()


func _drop_banner() -> void:
	_foot_check += 1
	if _foot != null:
		remove_child(_foot)
		_foot.free()
	_foot = null
	_band = null


func _show_chips() -> void:
	_show_chip(_vibration, "VIBRATION: ON", "VIBRATION: OFF", HudPrefs.haptics_enabled())
	_show_chip(_sound, "SOUND", "SOUND: OFF", _step(AudioService.BUS_SFX) > 0)
	_show_chip(_music, "MUSIC", "MUSIC: OFF", _step(AudioService.BUS_MUSIC) > 0)


## Sound and Music read their bare word while on (the accent's colour) and "...: OFF" greyed out,
## so the three chips share one row upright and the foot stays free.
func _show_chip(chip: Button, on_text: String, off_text: String, on: bool) -> void:
	chip.text = on_text if on else off_text
	chip.theme_type_variation = SIDES[_side][&"chip"] if on else CHIP_OFF


func _toggle_vibration() -> void:
	HudPrefs.set_haptics_enabled(not HudPrefs.haptics_enabled())
	_show_chips()


## Sound is the Sfx and Ui buses together (the player's Sound setting, AudioService); off is step 0
## and on is the default step of `AudioSettings`. Finer steps are the Settings screen's (P526).
func _toggle_sound() -> void:
	var service: Node = _audio()
	var settings: AudioSettings = service.get(&"settings") as AudioSettings
	var on: bool = _step(AudioService.BUS_SFX) > 0
	service.call(&"set_sound_step", 0 if on else settings.default_sfx_step)
	_show_chips()


func _toggle_music() -> void:
	var service: Node = _audio()
	var settings: AudioSettings = service.get(&"settings") as AudioSettings
	var on: bool = _step(AudioService.BUS_MUSIC) > 0
	service.call(&"set_step", AudioService.BUS_MUSIC, 0 if on else settings.default_music_step)
	_show_chips()


func _step(bus: StringName) -> int:
	return int(_audio().call(&"get_step", bus))


func _audio() -> Node:
	return audio if audio != null else AudioService


func _routes() -> MenuRoutes:
	return routes if routes != null else MenuRoutes.shared


func _flow() -> Node:
	return menu_flow if menu_flow != null else MenuFlow


## True when MenuFlow built this match (a menu or tutorial start); a dev-route match is not its.
func _owned() -> bool:
	return _flow().call(&"current_runner") == runner


func _is_lesson() -> bool:
	var setup: MatchSetup = _flow().call(&"current_setup") as MatchSetup if _owned() else null
	return setup != null and setup.lesson_id != &""


## A lesson's Exit reads "LEAVE TUTORIAL" (it goes to the menu the same way: no ad is touched).
func _show_exit() -> void:
	var lesson: bool = _is_lesson()
	_exit_button.text = "LEAVE TUTORIAL" if lesson else "EXIT TO MENU"
	_exit_dialog.question = "LEAVE TUTORIAL?" if lesson else "EXIT TO MENU?"
	_settings.disabled = not _routes().has(MenuRoutes.SETTINGS)  # P526 registers the route.


func _open_help() -> void:
	_open_overlay(HowToPlayScreen.new())


func _open_settings() -> void:
	if _routes().has(MenuRoutes.SETTINGS):
		_open_overlay(_routes().make(MenuRoutes.SETTINGS))


## A one-screen detour over the menu (the banner goes while it stands): a `MenuStack` whose root
## is a blank screen, so a Back that pops `screen` lands on the root and closes the overlay.
func _open_overlay(screen: MenuScreen) -> void:
	if _help != null or screen == null:
		if screen != null:
			screen.free()
		return
	_help = MenuStack.new()
	_help.name = &"HelpOverlay"
	_help.slide_ms = 0  # Cuts: a detour is never a slide to cancel.
	_help.backdrop_color = get_theme_color(&"outline", &"BoxOverlay")  # The menu scene's own.
	add_child(_help)  # Last child: over the foot and the dialogs.
	_help.push(MenuScreen.new())
	_help.screen_changed.connect(_on_help_changed)
	_help.push(screen)
	_place_banner()


## Back (or the screen's BACK button) has popped to the root: the pause menu is on show again.
func _on_help_changed(_screen: MenuScreen) -> void:
	if _help != null and _help.depth() < 2:
		_close_help()
		_show_chips()  # The Settings screen may have changed the audio steps.
		_place_banner()
		if visible and _resume != null:
			_resume.grab_focus()


func _close_help() -> void:
	if _help == null:
		return
	var overlay: MenuStack = _help
	_help = null
	remove_child(overlay)
	overlay.queue_free()


func _resume_pressed() -> void:
	feed.state.close(HudState.Unfold.PAUSE)


func _restart_dialog_open() -> void:
	_restart_dialog.open()


func _surrender_dialog_open() -> void:
	_surrender_dialog.open()


func _exit_dialog_open() -> void:
	_exit_dialog.open()


## Through MenuFlow when it owns the match (it handles the seed and the start-credits bonus: a
## mid-match restart counts nothing and shows no ad); the dev path otherwise.
func _restart() -> void:
	if _owned():
		var error: Error = await _flow().call(&"restart") as Error
		if error != OK:
			push_warning("PauseMenu: restart refused (%s)" % error_string(error))
		return
	DevRoutes.open_main_with(
		get_tree(),
		runner.scenario.resource_path,
		runner.opponents,
		runner.opponent_levels,
		runner.first_opponent
	)


## Resumes first, so the tick that carries the Command runs.
func _surrender() -> void:
	var snap: MatchSnapshot = runner.snapshot
	if snap != null:
		if snap.match_serial == _surrendered_in:
			return  # Once per match, as P90's button was.
		_surrendered_in = snap.match_serial
	feed.state.close(HudState.Unfold.PAUSE)
	if _owned():
		_flow().call(&"mark_surrendered")  # Before the Command: the sim cannot tell it from a defeat.
	controller.command_sink.call(Command.surrender(runner.scenario.local_player))


## Exit to menu and Leave tutorial: no XP, no ad bookkeeping (MenuFlow.return_to_menu).
func _exit_match() -> void:
	if _owned():
		_flow().call(&"return_to_menu")
		return
	_open_dev_menu()


func _open_dev_menu() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)


func _on_match_ended(_winner: int) -> void:
	feed.state.close(HudState.Unfold.PAUSE)
	_close_dialogs()


func _close_dialogs() -> void:
	for dialog: ConfirmDialog in [_restart_dialog, _surrender_dialog, _exit_dialog]:
		dialog.close()
