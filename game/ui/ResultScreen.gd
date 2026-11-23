class_name ResultScreen
extends ModalFrame
## The result screen (ADR 0019 section 6, plan P90): on `match_ended` it covers the HUD with the
## outcome as an emblem and a word, the match time and each player's units built and lost,
## buildings lost and credits harvested, from the published snapshot. Started from the menu
## (`MenuFlow` owns the match, ADR 0043 section 6) the buttons are the flow's: "Back" awaits
## `leave_match()` (counts the match, then the menu; the Tutorial screen after a lesson) and
## "Play again" awaits `restart()`; a second tap while one runs does nothing. Started from the
## dev menu, "Play again" opens a new main scene for the same scenario, opponents and level, and
## "Back" the dev menu. The screen also shows the XP the match paid and the rank bar filling from
## the old XP to the new (a rank-up restarts the bar in the new rank, ADR 0045), and plays the
## victory or defeat sting once. Sideways the banner and the table stand side by side, upright one
## above the other.
## The `OfferSlot` under the table (game/ui/menu/OfferSlot.gd) is hidden and 0 tall while it holds
## no visible child; its one child is the `DoubleXpOffer` (game/ui/ads/, plan P432), which owns
## every ad call and shows only for a scored award. This script calls no ad; it hands the offer
## the award and follows `Progression.xp_changed`, so a Double XP bonus moves the bar.

const MenuFlowScript: GDScript = preload("res://game/ui/menu/menu_flow_service.gd")
const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const AudioServiceScript: GDScript = preload("res://game/view/audio/audio_service.gd")
const XP_BAR_DP: float = 12.0
const XP_FILL_SECONDS: float = 1.2  ## The whole fill; a rank-up gives each half its share.
const EMBLEM_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"
const EMBLEM_DP: float = 64.0

@export var runner: MatchRunner
## Tests inject these before the match ends; null means the autoloads. `rank_xp` is the XP each
## rank starts at (from `data/meta/progression.tres` when empty).
var flow: MenuFlowScript = null:
	set = _set_flow
var progression: ProgressionScript = null
var audio: AudioServiceScript = null
var rank_xp: PackedInt32Array = PackedInt32Array()
## The Double XP offer in the slot; tests give it their own ad backend.
var offer: DoubleXpOffer

var _xp_box: VBoxContainer
var _gained: Label
var _rank_label: Label
var _rank_up: Label
var _xp_bar: ProgressBar
var _xp_text: Label
var _xp_view: Dictionary = {}
var _xp_shown: bool = false
var _fill: Tween
var _sting_played: bool = false
var _leaving: bool = false
var _score_seen: bool = false  ## `match_scored` fired (an award, or none for this match).
var _offer_slot: OfferSlot
var _xp_source: ProgressionScript = null
var _body: BoxContainer
var _emblem: TextureRect
var _title: Label
var _time: Label
var _grid: GridContainer
var _again: Button
var _back_button: Button
var _scroll: ScrollContainer  ## The panel's scroll; its bar takes width while it shows.


func _ready() -> void:
	ResultText.register()  # Before any `tr()` below.
	_body = BoxContainer.new()  # Before `super()`, whose `_apply_dp` sizes them.
	_emblem = TextureRect.new()
	_grid = GridContainer.new()
	_xp_bar = ProgressBar.new()
	super()
	column.add_child(_body)
	var banner: VBoxContainer = VBoxContainer.new()
	_body.add_child(banner)
	var head: HBoxContainer = HBoxContainer.new()
	banner.add_child(head)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_emblem)
	_title = add_label(head, "", &"CapsBigTitle")
	_time = add_label(banner, "", &"NumberLabel")
	_xp_box = VBoxContainer.new()
	_xp_box.name = &"XpBox"
	_xp_box.visible = false
	banner.add_child(_xp_box)
	_gained = add_label(_xp_box, "", &"CapsTitle")
	_rank_label = add_label(_xp_box, "", &"Label")
	_xp_bar.name = &"XpBar"
	_xp_bar.show_percentage = false
	_xp_box.add_child(_xp_bar)
	_xp_text = add_label(_xp_box, "", &"NumberLabel")
	_rank_up = add_label(_xp_box, tr(ResultText.RANK_UP), &"CapsTitle")
	_rank_up.name = &"RankUp"
	_rank_up.visible = false
	_body.add_child(_grid)
	_offer_slot = OfferSlot.add_to(column, self)
	offer = DoubleXpOffer.new()
	_offer_slot.add_child(offer)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	MapSelectText.register()
	_again = add_button(row, _again_text(), _play_again)
	_again.name = &"PlayAgainButton"
	var floors: Array[Node] = _again.find_children("*", "DpMinSize", false, false)
	if floors.size() == 1:  # Exactly one: a change to `add_button` must not drop the re-pin.
		# After DpMinSize's reset, UiScale and theme.
		(floors[0] as DpMinSize).applied.connect(_pin_again)
	else:
		push_warning("ResultScreen: PLAY AGAIN has %d DpMinSize nodes, not 1" % floors.size())
	_back_button = add_button(row, tr(ResultText.BACK), _back)
	_back_button.name = &"BackButton"
	var node: Node = panel
	while node != null and not node is ScrollContainer:
		node = node.get_parent()
	_scroll = node as ScrollContainer
	if _scroll != null:  # A bar that shows after the pin takes width: re-pin (a no-op when equal).
		_scroll.get_v_scroll_bar().visibility_changed.connect(_pin_again)
	_pin_again()  # After BACK: the pin leaves its width room.
	flow = flow if flow != null else (MenuFlow as MenuFlowScript)  # The setter connects.
	progression = progression if progression != null else (Progression as ProgressionScript)
	audio = audio if audio != null else (AudioService as AudioServiceScript)
	runner.match_ended.connect(_on_match_ended)
	_apply_dp()


func _apply_dp() -> void:
	super()
	var gap: int = roundi(UiScale.dp(GAP_DP))
	_body.vertical = HudLayout.is_portrait()
	_body.add_theme_constant_override("separation", gap * 2)
	_grid.add_theme_constant_override("h_separation", gap)
	_emblem.custom_minimum_size = UiScale.dp_vec(EMBLEM_DP, EMBLEM_DP)
	_xp_bar.custom_minimum_size.y = UiScale.dp(XP_BAR_DP)


@warning_ignore("integer_division")
func _on_match_ended(winner: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	var local: int = runner.scenario.local_player
	var result: String = "draw" if winner == 0 else ("victory" if winner == local else "defeat")
	_emblem.texture = load(EMBLEM_ART % result) as Texture2D
	_emblem.modulate = get_theme_color(StringName(result), &"ResultScreen")
	_title.text = tr(ResultText.title_key(result))
	var seconds: int = snap.match_end_tick / Sim.TICK_RATE
	_time.text = tr(ResultText.MATCH_TIME) % [seconds / 60, seconds % 60]
	for cell: Node in _grid.get_children():
		_grid.remove_child(cell)
		cell.free()
	var counts: Array[PackedInt32Array] = [
		snap.stat_built, snap.stat_lost_units, snap.stat_lost_buildings, snap.stat_harvested
	]
	var players: int = snap.stat_built.size() - 1
	_grid.columns = players + 1
	add_label(_grid, "", &"Label")
	for player: int in range(1, players + 1):
		var who: String = tr(ResultText.YOU)
		if player != local:
			who = tr(ResultText.ENEMY) if players == 2 else tr(ResultText.PLAYER_N) % player
		add_label(_grid, who, &"Label")
	for line: int in ResultText.STAT_KEYS.size():
		add_label(_grid, tr(ResultText.STAT_KEYS[line]), &"Label")
		for player: int in range(1, players + 1):
			var number: Label = add_label(_grid, str(counts[line][player]), &"NumberLabel")
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_dp()
	_xp_shown = false
	_show_xp()
	_play_sting(result)
	show_over(_again)


## Whether `MenuFlow` owns this match (started from the menu), not the dev routes.
func _owns() -> bool:
	return flow != null and flow.current_runner() == runner


func _set_flow(value: MenuFlowScript) -> void:
	if flow != null and flow.match_scored.is_connected(_on_match_scored):
		flow.match_scored.disconnect(_on_match_scored)
	flow = value
	if flow != null:
		flow.match_scored.connect(_on_match_scored)


## The victory or the defeat sting, once per ended match; a draw is not a win.
func _play_sting(result: String) -> void:
	if _sting_played:
		return
	_sting_played = true
	audio.play_music(&"victory" if result == "victory" else &"defeat")


## The award can arrive after the screen showed (a score that lands late): the block shows then.
func _on_match_scored(_summary: MatchSummary, _award: XpAward) -> void:
	_score_seen = true
	if visible:
		_show_xp()


## Shows the XP of the scored match (nothing for a match that paid none) and starts the fill.
func _show_xp() -> void:
	var award: XpAward = flow.last_award() if _owns() else null
	# The offer reserves its space while the screen owns the match and its score is still pending.
	var pending: bool = (
		award == null and _owns() and not _score_seen and flow.last_summary() == null
	)
	offer.set_award(award, progression, pending)
	# The XP box holds its space too (invisible) while the score is pending, so a late award that
	# fills it moves nothing; a score that pays nothing collapses it.
	if not _xp_shown:
		_xp_box.visible = pending
		_xp_box.modulate.a = float(not pending)  # Not a colour: 0 while it only holds space.
	if _xp_shown or award == null:
		return
	if _xp_source != progression:
		if _xp_source != null:
			_xp_source.xp_changed.disconnect(_on_xp_changed)
		_xp_source = progression
		_xp_source.xp_changed.connect(_on_xp_changed)
	_xp_shown = true
	var table: PackedInt32Array = rank_xp if not rank_xp.is_empty() else _table()
	_xp_view = xp_view(progression.xp(), award.base_xp, table)
	_xp_box.visible = true
	_xp_box.modulate.a = float(_xp_box.visible)  # 1: shown.
	_gained.text = tr(ResultText.XP_GAINED) % award.base_xp
	_rank_up.visible = false
	_set_range(_xp_view["from_floor"], _xp_view["from_next"])
	_xp_bar.value = _xp_view["old"]
	_rank_label.text = _rank_text(_xp_view["old_rank"])
	_xp_text.text = _xp_line()
	if _fill != null:
		_fill.kill()
	_fill = create_tween()
	if _xp_view["rank_up"]:
		_fill.tween_property(_xp_bar, "value", _xp_bar.max_value, XP_FILL_SECONDS / 2.0)
		_fill.tween_callback(_enter_new_rank)
		_fill.tween_property(_xp_bar, "value", float(_xp_view["total"]), XP_FILL_SECONDS / 2.0)
	else:
		_fill.tween_property(_xp_bar, "value", float(_xp_view["total"]), XP_FILL_SECONDS)


## A bonus (Double XP) moved the total: the gain and the bar follow, settled at once.
func _on_xp_changed() -> void:
	if not _xp_shown or progression.xp() == _xp_view["total"]:
		return
	var table: PackedInt32Array = rank_xp if not rank_xp.is_empty() else _table()
	var gained: int = progression.xp() - int(_xp_view["old"])
	_xp_view = xp_view(progression.xp(), gained, table)
	_gained.text = tr(ResultText.XP_GAINED) % gained
	_xp_text.text = _xp_line()
	_set_range(_xp_view["from_floor"], _xp_view["from_next"])
	_rank_label.text = _rank_text(_xp_view["old_rank"])
	if _fill != null:
		_fill.kill()
	settle()


## Ends the fill at once (also what a test calls instead of waiting).
func settle() -> void:
	if not _xp_shown:
		return
	if _fill != null:
		_fill.kill()
	_enter_new_rank()
	_xp_bar.value = float(_xp_view["total"])


func _enter_new_rank() -> void:
	_set_range(_xp_view["floor"], _xp_view["next"])
	_xp_bar.value = _xp_view["floor"]
	_rank_label.text = _rank_text(_xp_view["new_rank"])
	_rank_up.visible = _xp_view["rank_up"]


## The bar's range: a top rank (no next) is a full bar.
func _set_range(floor_xp: int, next_xp: int) -> void:
	_xp_bar.min_value = floor_xp
	_xp_bar.max_value = maxi(next_xp, floor_xp + 1)


func _rank_text(rank: int) -> String:
	return tr(ResultText.RANK_LINE) % [rank, progression.title(rank).to_upper()]


func _xp_line() -> String:
	var total: int = _xp_view["total"]
	if _xp_view["top"]:
		return tr(ResultText.XP_TOTAL) % total
	return tr(ResultText.XP_PROGRESS) % [total, _xp_view["next"]]


func _table() -> PackedInt32Array:
	var def: ProgressionDef = load(ProgressionScript.DEF_PATH) as ProgressionDef
	return PackedInt32Array(def.rank_xp) if def != null else PackedInt32Array()


## The rank (1 up) of `total` XP: the last rank whose start it has reached.
static func rank_at(total: int, table: PackedInt32Array) -> int:
	var found: int = 1
	for index: int in table.size():
		if total >= table[index]:
			found = index + 1
	return found


## The bar's numbers for a match that paid `gained` XP and left the player at `total`: the old and
## the new rank, the range of each (`from_*` before, `floor`/`next` after; equal at the top rank)
## and whether a rank was gained. Integers only.
static func xp_view(total: int, gained: int, table: PackedInt32Array) -> Dictionary:
	var old: int = maxi(0, total - gained)
	var old_rank: int = rank_at(old, table)
	var new_rank: int = rank_at(total, table)
	var last: int = table.size() - 1
	return {
		"old": old,
		"total": total,
		"old_rank": old_rank,
		"new_rank": new_rank,
		"rank_up": new_rank > old_rank,
		"from_floor": table[old_rank - 1] if last >= 0 else 0,
		"from_next": table[mini(old_rank, last)] if last >= 0 else 0,
		"floor": table[new_rank - 1] if last >= 0 else 0,
		"next": table[mini(new_rank, last)] if last >= 0 else 0,
		"top": new_rank > last,
	}


func _play_again() -> void:
	if _leaving:
		return
	if not _owns():
		DevRoutes.open_main_with(
			get_tree(),
			runner.scenario.resource_path,
			runner.opponents,
			runner.opponent_levels,
			runner.first_opponent
		)
		return
	_set_leaving(true, true)
	var error: Error = await flow.restart()
	if error != OK:  # Refused (busy, a bad setup): the buttons come back live.
		push_warning("ResultScreen: restart refused (%s)" % error_string(error))
	_set_leaving(false, true)


func _back() -> void:
	if _leaving:
		return
	if not _owns():
		DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)
		return
	_set_leaving(true, false)
	await flow.leave_match(_back_screen())
	_set_leaving(false, false)


## Where Back lands: a lesson (P544) returns to the Tutorial screen, a skirmish to the main menu
## (&""). Play again after a lesson still restarts the lesson.
func _back_screen() -> StringName:
	var setup: MatchSetup = flow.current_setup()
	return TutorialStart.RETURN_SCREEN if setup != null and setup.lesson_id != &"" else &""


## The phone's Back button on the shown result is the Back button.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_visible_in_tree():
		_back()


## While the flow prepares the next match (it may wait for a late ad to close) both buttons are
## off; on the Play again path that button reads "STARTING…". `_pin_again` keeps its width at the
## wider of the two texts at all times, so the row does not move when the text changes.
func _set_leaving(leaving: bool, again_path: bool) -> void:
	_leaving = leaving
	if again_path:
		_again.text = tr(MapSelectText.STARTING) if leaving else _again_text()
	_again.disabled = leaving
	_back_button.disabled = leaving


func _again_text() -> String:
	return tr(ResultText.PLAY_AGAIN)


## Pins the minimum width to the wider of the idle and the STARTING text (and the dp floor) with
## the current theme and scale, but never wider than the row can be: the inner safe width less the
## plate, the vertical scrollbar while it shows (its `visibility_changed` re-pins, since the flag
## is stale inside one emission), BACK's minimum and the gap. A longer text is
## trimmed with "…" instead of overflowing. BACK's floor is set here (its own `DpMinSize`'s
## `min_dp.x`, or `BUTTON_DP` without one, at the same dp as what it sets next), because PLAY
## AGAIN's `applied` fires before BACK's reset on a dp change; that is synchronous, so it needs no
## deferred call and nothing shows a frame late.
## Without a `DpMinSize` (the error state) the floor is `BUTTON_DP` itself and nothing re-pins on a
## turn; with one, it resets the minimum on a turn and emits `applied`, which re-pins it.
func _pin_again() -> void:
	# On a normal exit the bar's emission arrives while the screen is still in the tree; this only
	# catches one during teardown, after it has left.
	if not is_inside_tree():
		return
	var shown: String = _again.text
	var floor_px: float = UiScale.dp(BUTTON_DP.x)
	var wide: float = floor_px
	_again.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING  # Trimmed text has no minimum.
	_again.custom_minimum_size.x = floor_px
	for text: String in [_again_text(), tr(MapSelectText.STARTING)]:
		_again.text = text
		wide = maxf(wide, _again.get_combined_minimum_size().x)
	_again.text = shown
	var row: Control = _again.get_parent() as Control
	var inner: Rect2 = SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)
	var plate: float = panel.get_combined_minimum_size().x - column.get_combined_minimum_size().x
	var room: float = inner.size.x - plate
	var bar: VScrollBar = _scroll.get_v_scroll_bar() if _scroll != null else null
	if bar != null and bar.visible:
		room -= bar.get_combined_minimum_size().x
	var back_floor: Array[Node] = _back_button.find_children("*", "DpMinSize", false, false)
	var back_dp: float = (
		(back_floor[0] as DpMinSize).min_dp.x if back_floor.size() == 1 else BUTTON_DP.x
	)
	_back_button.custom_minimum_size.x = UiScale.dp(back_dp)
	room -= _back_button.get_combined_minimum_size().x + row.get_theme_constant("separation")
	_again.custom_minimum_size.x = clampf(wide, floor_px, maxf(floor_px, room))
	_again.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
