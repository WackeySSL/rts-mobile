class_name CoachMark
extends Control
## The tutorial's coach mark (plan row P542, ADR 0044 section 2, ADR 0048): a ring on the beat's
## anchor and a prompt card with Next (a read-only beat only) and Skip. Presentation only: it reads
## the `TutorialDirector`'s signals and calls its `next()` and `skip()`, and sends no Command.
##
## The card has a wide form (the dock at least `card_wide_dp` wide: the prompt left, a column right
## with the tab on top and Next under it) and a narrow one (a head row with the lesson's short title
## and the tab, then the prompt, then a foot row that shows only where it has a button). The tab
## (P589, ADR 0048 section 2) is one 48 dp button with the counter `n/N` and a chevron, at the
## dock's scope-side corner; a tap folds the card to it and opens it again. Every new beat opens
## the card and a stall opens it once; a turn keeps the choice and it is never saved. In a gap
## between beats the tab stays alone with the next number. Skip shows on a lesson's first card only.
##
## The card stands in `GuideDock`'s rect (P588, ADR 0048 section 1): one place, under the top row
## and clear of every part of the HUD, built from the HUD's own layout and stood again only when
## that changes (`_refresh_dock`). The search of P543g is gone: the card never moves for a ring.
## Where no dock has room (`GuideDock.has_room`) only the folded tab shows, in its own slot
## (`GuideDock.tab_slot`); a tap on it opens the card, which then overlays the HUD under the top
## row.
##
## Input: the node and the ring are `MOUSE_FILTER_IGNORE`, so a touch outside the card goes on to
## what is under it, and the gesture a beat asks for (a tap on the ring's unit, a drag, a pinch) is
## never taken. The card's body is `STOP`, so a tap on the prompt is not a map tap (no stray move
## or deselect), except where the ring meets the card (it turns see-through, ADR 0048 section 3)
## and over a modal (the pause menu), where the body lets every touch through. Next, Skip and the
## tab always stop.
##
## The ring is on a HUD control found by node name under `hud_root` (`anchor_control`), or on a
## world tile projected through the camera (`anchor_tile`); a tile off the screen pins the ring to
## the nearest edge of the safe rect. A control that is missing or hidden gives a card alone. All
## positions are global (screen) px, so the mark works under any parent.
## When the beat is `stalled()` the card shows a hint line and the ring turns amber and doubles (a
## shape change as well as a colour). The ring blinks unless `reduced` (the Reduced effects
## switch): then there is no Tween at all.
## Looks come from `theme.tres`: PauseCard (GuideCardThrough while see-through), PauseButton,
## PausePrimary and PauseMuted for the card, GuideTokens for the ring. No colour literal.

const BUTTON_GAP_DP: float = 12.0  ## Between Skip and Next: a slip must not end the lesson.
const TAB_CLEAR_DP: float = 8.0  ## The least between the tab's rect and a card button's.
const MIN_TEXT_DP: float = 120.0  ## The least width of the prompt beside the buttons' column.
const RING_LINE_DP: float = 3.0
const RING_GROW_DP: float = GuideRing.RING_GROW_DP
const MIN_TARGET_DP: float = GuideRing.MIN_TARGET_DP
const REDUCED_LINE_DP: float = 1.0  ## Reduced effects: a steady frame, this much thicker.
const PILL_STEP_DP: float = 8.0  ## The pill width is read in steps of this.
const FIND_EVERY: int = GuideLookup.FIND_EVERY
const CARD_VARIATION: StringName = &"PauseCard"
const THROUGH_VARIATION: StringName = &"GuideCardThrough"
const THEME_PATH: String = "res://game/ui/theme.tres"
const CHEVRON_PATH: String = "res://assets/art/svg/icons/glyph_chevron.svg"
const CHEVRON_DP: Vector2 = Vector2(14.0, 10.0)
## Drawn above every other control of the layer, the pause menu included, whatever order the mark
## was added in: the card that asks for Resume must be seen over the open menu.
const Z_ABOVE_MODALS: int = 100

var director: TutorialDirector
var camera: RtsCamera
## The node under which the anchor controls are looked up by name.
var hud_root: Node
## The left-handed layout (ADR 0025 section 14): the dock flips with the HUD. Not wired in the game
## yet, as with the command bar's own flag.
var mirror: bool = false
## Every number of the blink (ADR 0048 section 7); a test may swap a copy in.
var settings: GuideSettingsDef = preload("res://data/tutorial/guide_settings.tres"):
	set(value):
		settings = value
		_dock_key = -1  # The dock reads the card's size cap.
		_restart_blink()
## Reduced effects: a steady frame, no Tween. `_ready` adds the player switch; tests may set it.
var reduced: bool = false:
	set(value):
		reduced = value
		_restart_blink()

var _ring: Control
var _gesture: GestureHint  ## The hand (ADR 0048 section 6), drawn above the card and the ring.
var _gesture_plan: GuideHintPlan = GuideHintPlan.new()
var _gesture_box: Rect2 = Rect2()  ## What the hand draws, with its margin (see-through test).
var _gesture_aim: TutorialLeadInDef = null
var _dock_rects: Dictionary[StringName, Rect2] = {}
var _card: PanelContainer
var _prompt: Label
var _hint: Label
var _row: BoxContainer  ## Skip and Next: a row, stacked where the dock is too narrow for both.
var _head: HBoxContainer  ## Narrow form: the lesson's short title and room for the tab.
var _title: Label
var _head_pad: Control
var _main: BoxContainer  ## The prompt and the buttons: side by side (wide) or one over the other.
var _side: BoxContainer  ## The buttons' column (wide: under the tab's room, else beside it).
var _side_pad: Control
var _counter: Label
var _chevron: TextureRect
var _number: int = 0  ## The beat on show (1-based; in a gap the next one) and the lesson's count.
var _total: int = 0
var _open: bool = true  ## The card is unfolded (the player's choice within a beat, never saved).
var _arm_open: bool = false  ## A new beat or a stall: the next layout unfolds the card.
var _roomy: bool = true  ## The last dock had room.
var _gap: bool = false  ## Between two beats: the tab shows alone with the next number.
var _scroll: ScrollContainer  ## The prompt and hint: scrolls where the dock is too short.
var _content: VBoxContainer
var _next: Button
var _skip: Button
var _beat: TutorialBeatDef = null
var _aim: TutorialLeadInDef = null  ## The step of the chain the ring is on (ADR 0048 section 5).
var _fallback: TutorialLeadInDef = null  ## The beat's own anchor as a step: no director.
var _target: Control = null
var _blink: Tween = null
var _blink_alpha: float = 1.0  ## The frame's opacity now.
var _own_theme: bool = false
var _dp: float = 1.0  ## The metrics, read by `_measure` on a resize and never per frame.
var _view: Vector2 = Vector2.ZERO
var _safe_rect: Rect2 = Rect2()
var _room: Rect2 = Rect2()  ## The safe rect below the top HUD row: where the card may stand.
var _ring_now: Rect2 = Rect2()  ## What the last `_update` laid out.
var _stalled_now: bool = false
var _can_next_now: bool = false
var _size_now: Vector2 = Vector2.ZERO
var _points: PackedVector2Array = PackedVector2Array()  ## The tile ring, about its centre.
var _points_for: Vector2 = Vector2.ZERO
var _dirty: bool = true
var _again: int = 0  ## Layouts still to make for the change in hand.
var _card_box: Rect2 = Rect2()  ## The card as last laid out, global px (empty: not shown).
var _through_now: bool = false  ## The card is see-through: the ring meets it.
var _modal_now: bool = false  ## The target is in a modal: the card's body takes no touch.
var _dock: Rect2 = Rect2()  ## `GuideDock.place` for the layout in force (empty: no room).
var _tab_slot: Rect2 = Rect2()  ## `GuideDock.tab_slot`: where the folded tab stands.
var _dock_key: int = -1  ## What the dock was built from, packed; -1 forces the first.
var _dock_band: Rect2 = Rect2()
var _shown: HudCorners.Shown = HudCorners.Shown.new()  ## Reused: filled from `HudState` each look.
var _columns: GroupColumn = null
var _build: BuildButton = null
var _pill: EconomyPill = null
var _next_hud: int = 0
var _lookup: GuideLookup = GuideLookup.new()
var _tab: Button


func _ready() -> void:
	z_index = Z_ABOVE_MODALS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reduced = reduced or MenuPrefs.reduced_effects()
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.theme_type_variation = CARD_VARIATION
	_card.mouse_filter = Control.MOUSE_FILTER_STOP  # Taps on the card are not map taps.
	add_child(_card)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.theme_type_variation = &"GuidePrompt"
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = &"PauseMuted"
	_hint.text = tr("Stuck? Try what the card says, or leave from the menu.")
	_head = HBoxContainer.new()
	_head.name = "Head"
	_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = Label.new()
	_title.name = "Title"
	_title.theme_type_variation = &"PauseMuted"
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_head_pad = _pad("HeadPad")
	_head.add_child(_title)
	_head.add_child(_head_pad)
	column.add_child(_head)
	_main = BoxContainer.new()
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_main)
	_scroll = ScrollContainer.new()
	_scroll.name = "PromptScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # A drag scrolls.
	_main.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_content)
	for label: Label in [_prompt, _hint]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(label)
	_side = BoxContainer.new()
	_side.name = "Side"
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(_side)
	_side_pad = _pad("SidePad")
	_side.add_child(_side_pad)
	_row = BoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_END
	_side.add_child(_row)
	_skip = _button("Skip", "SKIP LESSON", &"PauseButton")
	_next = _button("Next", "NEXT", &"PausePrimary")
	_next.pressed.connect(_on_next)
	_skip.pressed.connect(_on_skip)
	_build_tab()
	_ring = Control.new()  # Drawn above the card, so a see-through card shows it (section 3).
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_gesture = GestureHint.new()
	_gesture.name = "GestureHint"
	_gesture.visible = false
	add_child(_gesture)
	get_viewport().size_changed.connect(_apply_metrics)
	_apply_metrics()
	visible = false
	set_process(false)
	if director != null:
		bind(director)
	var on: TutorialBeatDef = _beat
	if on == null and director != null:
		on = director.current
	if on != null:
		show_beat(on)


## Follows `new_director`'s beats; the old one's are let go and its card is put away.
func bind(new_director: TutorialDirector) -> void:
	if director != null and director != new_director:
		_unbind()
		hide_mark()
	director = new_director
	if director == null:
		return
	if not director.beat_shown.is_connected(show_beat):
		director.beat_shown.connect(show_beat)
		director.target_changed.connect(_on_target_changed)
		director.beat_done.connect(_on_beat_done)
		director.lesson_done.connect(_on_lesson_over)
		director.lesson_skipped.connect(_on_lesson_over)
	if _ring != null and director.current != null:
		show_beat(director.current)


## Puts the prompt of `beat` up (when the mark is not yet in the tree, as soon as it is).
func show_beat(beat: TutorialBeatDef) -> void:
	_beat = beat
	_fallback = TutorialChain.final_step(beat)
	_aim = null
	_sync_aim()
	if _ring == null:
		return
	_lookup.rescan()
	_gap = false
	_arm_open = true
	_dirty = true
	_measure()
	_number = director.progress().x + 1 if director != null else 1
	_total = director.progress().y if director != null else 1
	_title.text = tr(String(director.lesson.title_key)) if _lesson_known() else ""
	_counter.text = "%d/%d" % [_number, _total]
	_prompt.text = tr(String(beat.prompt_key))
	if _scroll.scroll_vertical != 0:
		_scroll.scroll_vertical = 0
	visible = true
	set_process(true)
	_update()


func hide_mark() -> void:
	_gap = false
	_beat = null
	_aim = null
	_target = null
	_ring_now = Rect2()
	_clear_gesture()
	visible = false
	if _ring != null:
		set_process(false)
	_stop_blink()


## Between two beats: nothing but the tab, with the next beat's number (ADR 0048 section 2).
func _show_gap() -> void:
	_beat = null
	_aim = null
	_target = null
	_ring_now = Rect2()
	_clear_gesture()
	_gap = true
	_number = director.progress().x + 1
	_total = director.progress().y
	_counter.text = "%d/%d" % [_number, _total]
	_stop_blink()
	_ring.queue_redraw()
	_dirty = true
	visible = true
	set_process(true)
	_measure()
	_update()


func _lesson_known() -> bool:
	return director != null and director.lesson != null


## The counter on the tab: "n/N" (an empty string: no tab text yet).
func counter_text() -> String:
	return _counter.text


## Whether the card is unfolded (false: only the tab shows, or nothing in a covered state).
func card_open() -> bool:
	return _card.visible


## The control the ring is on (null: no control beat, or none found or shown).
func target_control() -> Control:
	return _target if is_instance_valid(_target) else null


## The ring's rect in screen px, as of the last frame (an empty rect: no ring).
func ring_rect() -> Rect2:
	return _ring_now


## The card's rect in screen px.
func card_rect() -> Rect2:
	return Rect2(_card.global_position, _card.size)


## The dock the card stands in (an empty rect: no room, the card is folded to its tab).
func dock_rect() -> Rect2:
	return _dock


## The folded tab's rect in screen px (an empty rect: it does not show).
func tab_rect() -> Rect2:
	return Rect2(_tab.global_position, _tab.size) if _tab.is_visible_in_tree() else Rect2()


## Whether the card is see-through now: the ring meets it (ADR 0048 section 3).
func see_through() -> bool:
	return _through_now


## The frame's opacity now: 1.0 steady, else eased between the low alpha and 1.0.
func ring_alpha() -> float:
	return _blink_alpha


## The frame's line, px: Reduced effects makes it 1 dp thicker.
func ring_line_px() -> float:
	return (RING_LINE_DP + (REDUCED_LINE_DP if reduced else 0.0)) * _dp


## The frame's colour now (the blink's opacity in its alpha) and how many rings it draws.
func ring_tone() -> Color:
	var tone: Color = get_theme_color(&"ring_stalled" if _stalled_now else &"ring", &"GuideTokens")
	tone.a *= _blink_alpha
	return tone


func ring_count() -> int:
	return 2 if _stalled_now else 1


func ring_blinking() -> bool:
	return _blink != null and _blink.is_valid()


## The height of the top HUD row, dp, that the card keeps clear of (ADR 0025 section 2): the scope
## (56, taller than the pill and the toast) and a gap; upright the toast's slot under the pill and
## the scope as well.
static func top_row_dp(portrait: bool) -> float:
	var row: float = HudCorners.SCOPE_DP + HudCorners.GAP_DP
	if portrait:
		row += HudCorners.TOAST_H_DP + HudCorners.GAP_DP
	return row


## The dock and the folded tab's slot, again when what they are built from changed: the screen (a
## resize or turn calls `_apply_metrics`, which clears the key), the unfolds of `HudState` (drawer,
## full map, the command bar's slot, width and height: what its `changed` signal reports, read
## here as the key so a change the signal does not name is seen too), the group column's count,
## the strike button, the aim, the Ready chip, the pill's width and an ad band. A pure function of
## `GuideDock`, so nothing is searched. Returns whether it stood them again.
func _refresh_dock() -> bool:
	_find_hud()
	var shown: HudCorners.Shown = _shown
	shown.drawer = false
	shown.map = false
	shown.card = false
	shown.bar = false
	shown.bar_width = 0.0
	shown.bar_tall = true
	var hud: HudState = director.hud if director != null else null
	if hud != null:
		hud.fill(shown)
		hud.fill_bar(shown)
	var portrait: bool = HudLayout.is_portrait()
	var aim: StrikeAim = director.strike_aim if director != null else null
	var groups: int = _columns.item_count() if is_instance_valid(_columns) else 1
	var ready: bool = is_instance_valid(_build) and _build.ready_type >= 0
	var pill: int = ceili(_pill.size.x / _dp / PILL_STEP_DP) if is_instance_valid(_pill) else 0
	var band: Rect2 = _ad_band()
	var flags: int = (
		int(portrait)
		| int(shown.map) << 1
		| int(shown.drawer) << 2
		| int(aim != null and aim.owned) << 3
		| int(aim != null and aim.active) << 4
		| int(ready) << 5
		| int(shown.bar) << 6
		| int(shown.bar_tall) << 7
	)
	var key: int = (
		flags | groups << 8 | roundi(shown.bar_width) << 16 | int(mirror) << 30 | pill << 32
	)
	if key == _dock_key and band == _dock_band:
		return false
	_dock_key = key
	_dock_band = band
	var dock_shown: HudCorners.Shown = GuideDock.shown_for_dock(
		portrait,
		shown.map,
		shown.drawer,
		groups,
		aim != null and aim.owned,
		ready,
		aim != null and aim.active,
		shown.bar,
		shown.bar_tall
	)
	dock_shown.bar_width = shown.bar_width
	dock_shown.pill_width = pill * PILL_STEP_DP
	var rects: Dictionary[StringName, Rect2] = GuideDock.hud_for_dock(
		_safe_rect, portrait, _dp, mirror, dock_shown
	)
	if band.has_area():
		rects[GuideDock.AD_BAND] = band
	_dock_rects = rects
	var values: Dictionary[StringName, float] = {
		GuideDock.MAX_WIDTH_KEY: settings.card_max_width_dp,
		GuideDock.MAX_HEIGHT_KEY: float(settings.card_max_height_pct),
	}
	_dock = GuideDock.place(_safe_rect, portrait, _dp, mirror, rects, values)
	_tab_slot = GuideDock.tab_slot(_safe_rect, _dp, mirror, rects)
	var roomy: bool = GuideDock.has_room(_dock, _dp)
	if roomy != _roomy:
		_roomy = roomy
		_arm_open = true  # Room came or went: the card opens where it fits (below).
	_open = _open and roomy  # With no room the card stays folded until the layout changes.
	return true


## Looks for the HUD parts the dock reads (the group column, BUILD, the pill) while one is missing,
## every `FIND_EVERY` frames.
func _find_hud() -> void:
	if hud_root == null:
		return
	if is_instance_valid(_columns) and is_instance_valid(_build) and is_instance_valid(_pill):
		return
	var frame: int = Engine.get_process_frames()
	if frame < _next_hud:
		return
	_next_hud = frame + FIND_EVERY
	_columns = _first(GroupColumn) as GroupColumn
	_build = _first(BuildButton) as BuildButton
	_pill = _first(EconomyPill) as EconomyPill


func _first(type: Script) -> Node:
	for node: Node in hud_root.find_children("*", type.get_global_name(), true, false):
		return node
	return null


## The modal (a ModalFrame, as the pause menu is) that holds the target, else null.
func _modal_of(node: Node) -> Node:
	while node != null and not node is ModalFrame:
		node = node.get_parent()
	return node


## The visible rect of the ad band of the scope the target is in (the modal, else the HUD).
func _ad_band() -> Rect2:
	var modal: Node = _modal_of(_target)
	return _lookup.ad_band(modal if modal != null else hud_root, hud_root, _view)


## `control`'s rect as the player sees it: cut by the scroll areas it stands in and by the screen.
func _visible_rect(control: Control) -> Rect2:
	return GuideRing.visible_rect(control, hud_root, _view)


## Whether the mark must stand down for a visible modal that does not hold the target.
func _covered() -> bool:
	return GuideLookup.covered(get_parent(), self, _target)


func _process(_delta: float) -> void:
	_update()


## One look at the beat: the ring's box, the dock and the card's state; the card is laid out only on
## a change (a new beat, the dock, the buttons that show, the ring meeting or leaving the card).
func _update() -> void:
	if (_beat == null and not _gap) or not is_inside_tree():
		return
	if not is_instance_valid(_target):
		_target = null  # Freed with its HUD: never passed on.
	_sync_aim()
	_resolve_target()
	var covered: bool = _covered()
	if covered == visible:  # The state changed: a hidden mark draws nothing and takes no touch.
		visible = not covered
		_dirty = true
		if covered:
			_stop_blink()
	if covered:
		return
	var ring: Rect2 = _ring_box()
	var docked: bool = _refresh_dock()
	_update_gesture(ring)
	var stalled: bool = director != null and director.stalled() and not director.can_next()
	var can_next: bool = director != null and director.can_next()
	var modal: bool = _modal_of(_target) != null
	if stalled and not _stalled_now:
		_arm_open = true  # The hint line is new: open the card once.
	var reshaped: bool = (
		_dirty
		or docked
		or stalled != _stalled_now
		or can_next != _can_next_now
		or modal != _modal_now
		or size != _size_now
	)
	var changed: bool = reshaped or ring != _ring_now or _meets(ring) != _through_now
	if not changed and _again == 0:
		return
	if changed:
		_again = 2  # A label shapes its wrapped text a frame after its width changes: look twice.
	_dirty = false
	_ring_now = ring
	_stalled_now = stalled
	_can_next_now = can_next
	_modal_now = modal
	_size_now = size
	_next.visible = can_next
	_skip.visible = _first_card()
	_hint.visible = stalled
	_ring.global_position = Vector2.ZERO
	_ring.size = _view
	if ring.size != _points_for:
		_points_for = ring.size
		_points = GuideRing.ellipse(ring.size * 0.5)
	_ring.queue_redraw()
	if ring.has_area():
		_start_blink()
	else:
		_stop_blink()
	_layout_card(ring)
	_again -= 1


## Whether the ring meets the card as laid out last (ADR 0048 section 3). The ring already stands
## 6 dp outside its control, and the dock stands 8 dp from every HUD part, so a HUD neighbour never
## meets the card; a tile, a modal's button or the ghost's check mark can.
func _meets(ring: Rect2) -> bool:
	if not _card.visible:
		return false
	return (ring.has_area() and _card_box.intersects(ring)) or _card_box.intersects(_gesture_box)


## Stands the card in the dock, or on the folded tab's slot when the dock has no room (ADR 0048
## section 1): the tab shows alone; a tap on it opens the card, which then may overlay the HUD
## under the top row. Where the ring meets the card the card turns see-through and its body takes
## no touch (section 3); over a modal its body never takes one. Next, Skip and the tab always do.
func _layout_card(ring: Rect2) -> void:
	var roomy: bool = GuideDock.has_room(_dock, _dp)
	var slotted: bool = not roomy and _tab_slot.has_area()
	if _arm_open:
		_arm_open = false
		_open = roomy  # A new beat or a stall opens the card; with no room only the tab shows.
	_tab.visible = roomy or slotted
	_place_tab(roomy)
	_chevron.rotation = 0.0 if _open else PI
	var shown: bool = not _gap and (_open or not _tab.visible)
	_card.visible = shown
	if not shown:
		_card_box = Rect2()
		_through_now = false
		return
	var stand: Rect2 = _dock
	if not roomy:
		var width: float = minf(settings.card_max_width_dp * _dp, _room.size.x)
		stand = Rect2(
			_room.position + Vector2((_room.size.x - width) * 0.5, 0.0),
			Vector2(width, _room.size.y)
		)
	_skip.visible = _first_card() and not _modal_now  # The pause menu has Leave tutorial.
	_fit_card(stand.size.x, stand.size.y)
	_card.global_position = stand.position
	_card_box = Rect2(stand.position, _card.size)
	_through_now = _meets(ring)
	_card.theme_type_variation = THROUGH_VARIATION if _through_now else CARD_VARIATION
	var passes: bool = _through_now or _modal_now
	var filter: Control.MouseFilter = (
		Control.MOUSE_FILTER_IGNORE if passes else Control.MOUSE_FILTER_STOP
	)
	_card.mouse_filter = filter
	_scroll.mouse_filter = filter
	if _modal_now and _next.visible and _touches_modal(_modal_of(_target)):
		_next.visible = false  # Next shows over a modal only where it clears every button of it.
	if not roomy:
		_place_tab(false)


## The tab at the dock's scope-side corner (right; mirrored, left), or in its own slot where the
## dock has no room. The same place whether the card is open or folded.
func _place_tab(roomy: bool) -> void:
	var size_px: Vector2 = Vector2(MIN_TARGET_DP, MIN_TARGET_DP) * _dp
	_tab.size = size_px
	if roomy:
		var left: float = _dock.position.x if mirror else _dock.end.x - size_px.x
		_tab.global_position = Vector2(left, _dock.position.y)
	else:
		_tab.global_position = _tab_slot.position


## Skip shows only on a lesson's first card (ADR 0048 section 2, answer 4).
func _first_card() -> bool:
	return director != null and not _gap and director.progress().x == 0


## Whether the card's visible Next is under 8 dp from a visible button of `modal`.
func _touches_modal(modal: Node) -> bool:
	return GuideLookup.touches(Rect2(_next.global_position, _next.size), modal, _dp)


func _on_tab() -> void:
	_open = not _open
	_dirty = true
	_update()


## Gives the card `width` px, never more, and the height its wrapped text needs at that width, at
## most `max_height`: past that the prompt scrolls in its own area and the buttons keep their foot
## row. The row stacks where the width cannot hold Skip and Next side by side. Returns the size. The
## labels' and the box's cached minimums are dropped first, or the height read is the one of the
## width before.
func _fit_card(width: float, max_height: float = INF) -> Vector2:
	var margin: Vector2 = _card.get_theme_stylebox(&"panel").get_minimum_size()
	var inner: float = floorf(width - margin.x)  # Whole px: a label is never over.
	var gap: float = BUTTON_GAP_DP * _dp
	var least: float = ceilf(MIN_TARGET_DP * _dp)  # A button's minimum is whole px.
	# Wide by the dock's width, and in any landscape dock: a head row would cost 48 dp of the 126 dp
	# a small phone's dock has (ADR 0048 section 2, deviation noted there).
	var wide: bool = width >= settings.card_wide_dp * _dp or not HudLayout.is_portrait()
	var across: float = 0.0
	var widest: float = least
	var count: int = 0
	for button: Button in [_skip, _next]:
		button.clip_text = false
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		if button.visible:
			count += 1
			var button_width: float = CoachButtonWidth.of(button, MIN_TARGET_DP * _dp)
			widest = maxf(widest, button_width)
			across += button_width + (gap if across > 0.0 else 0.0)
	if wide and inner - widest - gap < MIN_TEXT_DP * _dp:
		wide = false  # Not even a column beside the prompt leaves it its least width.
	var text_width: float = inner
	_head.visible = not wide
	_side_pad.visible = wide
	_main.vertical = not wide
	_main.move_child(_side, 0 if mirror and wide else 1)
	_head.move_child(_head_pad, 0 if mirror else 1)
	_side.visible = wide or count > 0
	_row.visible = count > 0  # An action beat has no button: the row takes no height.
	if wide:  # The buttons go under the tab, stacked or in a row, else beside it, by the height.
		var stacked: float = count * least + maxf(count - 1.0, 0.0) * gap
		# The tab stands at the card's corner, the pad `margin.top` below it: the real gap between
		# the tab and the button under it is that margin plus the separation (at least 8 dp).
		var top_margin: float = _card.get_theme_stylebox(&"panel").get_margin(SIDE_TOP)
		var tight: float = maxf(TAB_CLEAR_DP * _dp - top_margin, 0.0)
		var avail: float = max_height - margin.y
		var beside: bool = count > 0 and least + tight + least > avail
		var side: float = least
		if count > 0:
			side = across + gap + least if beside else maxf(least, across)
		var under: bool = not beside and least + tight + stacked <= avail
		var squeezed: bool = false  # No column fits the height either: the row keeps its words.
		if count > 0 and inner - side - gap < MIN_TEXT_DP * _dp:  # Too little left for the prompt:
			squeezed = least + tight + stacked > avail
			if not squeezed:  # the buttons stack in a column under the tab.
				beside = false
				under = true
		if under:
			side = widest if count > 0 else least
		_side.vertical = not beside
		_side.move_child(_side_pad, 0 if mirror or not beside else 1)
		_row.vertical = under
		var below: float = stacked if under else least  # The row's height under the tab.
		_side.add_theme_constant_override(
			"separation",
			roundi(gap) if beside else floori(clampf(avail - least - below, tight, gap))
		)
		_side.custom_minimum_size.x = side
		text_width = maxf(inner - side - gap, minf(MIN_TEXT_DP * _dp, inner))
		if squeezed:  # The prompt takes what is left and scrolls in it.
			text_width = maxf(inner - side - gap, 0.0)
	else:
		_side.vertical = true
		_row.vertical = across > inner
		_side.custom_minimum_size.x = 0.0
	for button: Button in [_skip, _next]:
		# Stacked, a button is as wide as the card: only there may a longer text be trimmed.
		var own: float = CoachButtonWidth.of(button, MIN_TARGET_DP * _dp)
		var trim: bool = _row.vertical and not wide and own > inner
		button.clip_text = trim
		button.text_overrun_behavior = (
			TextServer.OVERRUN_TRIM_ELLIPSIS if trim else TextServer.OVERRUN_NO_TRIMMING
		)
	for box: Container in [_row, _side, _main]:  # A button's trim drops its minimum: sort again.
		box.update_minimum_size()
		box.queue_sort()
	for label: Label in [_prompt, _hint]:  # The wrapped height needs the width first.
		label.custom_minimum_size.x = text_width
		label.size.x = text_width
		label.update_minimum_size()
	_content.custom_minimum_size.x = text_width
	_content.update_minimum_size()
	var column: Control = _main.get_parent() as Control
	var sep: float = column.get_theme_constant(&"separation")
	var used: float = margin.y
	if not wide:
		used += least + sep
		if count > 0:
			used += _row.get_combined_minimum_size().y + gap  # `_main`'s own separation.
	var room: float = maxf(floorf(max_height - used), 0.0)
	_scroll.custom_minimum_size = Vector2(
		text_width, minf(_content.get_combined_minimum_size().y, room)
	)
	_main.update_minimum_size()
	column.update_minimum_size()
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.update_minimum_size()
	_card.size = Vector2(width, _card.get_combined_minimum_size().y)
	return _card.size


## Whether the prompt is longer than its area and scrolls (the dock is too short for it).
func prompt_scrolls() -> bool:
	return _scroll.get_v_scroll_bar().max_value > _scroll.get_v_scroll_bar().page + 0.5


## Plays the hand where `GuideHintPlan` puts it (ADR 0048 section 6) and keeps its box for the
## see-through test. A new gesture or step starts its loop again.
func _update_gesture(ring: Rect2) -> void:
	if _gesture == null:
		return
	var foot: float = -1.0  # Below the dock's foot; with no dock, below the card.
	if not GuideDock.has_room(_dock, _dp) and _card_box.has_area():
		foot = _card_box.end.y
	var field: Vector2 = GuideDock.field_point(_safe_rect, _dock, _dock_rects, foot)
	var lead: bool = _beat != null and _beat.lead_in.has(_aim)
	var plan: GuideHintPlan = _gesture_plan
	plan.resolve(_beat, _aim, lead, ring, camera, field, _safe_rect, _dp, settings.hint_size_dp)
	_gesture_box = plan.bounds
	var shown: bool = plan.kind != TutorialBeatDef.Gesture.NONE
	_gesture.visible = shown
	if not shown:
		return
	var again: bool = plan.kind != _gesture.kind or _aim != _gesture_aim
	_gesture_aim = _aim
	if _gesture.settings != settings:
		_gesture.settings = settings
	_gesture.reduced = reduced
	_gesture.kind = plan.kind
	_gesture.vector_dp = plan.vector_dp
	_gesture.size = Vector2.ONE * settings.hint_size_dp * _dp
	_gesture.global_position = plan.point - _gesture.size * 0.5
	if again:
		_gesture.restart()


func _clear_gesture() -> void:
	_gesture_box = Rect2()
	_gesture_aim = null
	if _gesture != null:
		_gesture.visible = false


## The hand's plan for the frame (kind, point, bounds).
func gesture_plan() -> GuideHintPlan:
	return _gesture_plan


## The ring's box for the active step (`GuideRing.box`). Pure: it reads `_target`, never looks.
func _ring_box() -> Rect2:
	if _beat == null:
		return Rect2()
	return GuideRing.box(_aim, _target, camera, hud_root, _view, _safe_rect, _dp)


## Takes the active step of the director's chain (the beat's own anchor with no director).
func _sync_aim() -> void:
	var want: TutorialLeadInDef = null
	if _beat != null:
		if director != null and director.current == _beat:
			want = director.active_target()
		if want == null:
			want = _fallback
	if want == _aim:
		return
	_aim = want
	_target = null
	_lookup.reset_step()
	_dirty = true


## The director moved the chain on: look for the new step's control now, not at the next find.
func _on_target_changed(_step: TutorialLeadInDef) -> void:
	_sync_aim()
	if _ring != null:
		_update()


func _resolve_target() -> void:
	_target = _lookup.find(_aim, hud_root, _target)
	_lookup.reveal(_target as ItemTile)


func _draw_ring() -> void:
	if not _ring_now.has_area() or _aim == null:
		return
	var tone: Color = ring_tone()
	var line: float = ring_line_px()
	var centre: Vector2 = _ring_now.get_center()
	var half: Vector2 = _ring_now.size * 0.5
	for turn: int in ring_count():  # Stalled: a second, outer ring.
		var grow: float = line * 2.0 * turn
		if _aim.anchor == TutorialBeatDef.Anchor.CONTROL:
			_ring.draw_rect(_ring_now.grow(grow).intersection(_safe_rect), tone, false, line)
		else:
			_ring.draw_set_transform(centre, 0.0, (half + Vector2(grow, grow)) / half)
			_ring.draw_polyline(_points, tone, line, true)
			_ring.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _start_blink() -> void:
	if reduced or ring_blinking() or settings.blink_period_ms <= 0:
		return
	var low: float = settings.blink_low_alpha_pct / 100.0
	var half: float = settings.blink_period_ms / 2000.0
	_blink = create_tween().set_loops()
	_blink.tween_method(_set_blink, 1.0, low, half).set_trans(Tween.TRANS_SINE)
	_blink.tween_method(_set_blink, low, 1.0, half).set_trans(Tween.TRANS_SINE)


## A changed switch or settings kills the Tween; the next look makes the right one.
func _restart_blink() -> void:
	_stop_blink()
	if _ring != null and _beat != null and is_inside_tree():
		_dirty = true
		_update()


func _set_blink(value: float) -> void:
	_blink_alpha = value
	_ring.queue_redraw()


func _stop_blink() -> void:
	if _blink != null:
		_blink.kill()
		_blink = null
	_blink_alpha = 1.0


## An empty spacer of a touch target's size: the tab stands over it.
func _pad(node_name: String) -> Control:
	var pad: Control = Control.new()
	pad.name = node_name
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pad


## The tab: one button with the counter over a chevron, 48 dp square (it fits the folded slot).
func _build_tab() -> void:
	_tab = Button.new()
	_tab.name = "Tab"
	_tab.theme_type_variation = &"PauseButton"
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.visible = false
	_tab.pressed.connect(_on_tab)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_counter = Label.new()
	_counter.name = "Counter"
	_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chevron = TextureRect.new()
	_chevron.name = "Chevron"
	_chevron.texture = load(CHEVRON_PATH)
	_chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron.resized.connect(func() -> void: _chevron.pivot_offset = _chevron.size / 2.0)
	stack.add_child(_counter)
	stack.add_child(_chevron)
	_tab.add_child(stack)
	add_child(_tab)


## A card button, at least 48 dp each way.
func _button(node_name: String, text: String, variation: StringName) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = tr(text)
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	_row.add_child(button)
	return button


## Reads the dp, the screen and the safe rect: a resize does it, never a frame.
func _measure() -> void:
	_dp = UiScale.base_px_per_dp()
	var full: Rect2 = get_viewport().get_visible_rect()
	_view = full.size
	_safe_rect = SafeAreaMargin.rect_inside(full, SafeAreaMargin.DEFAULT_MARGIN_DP)
	var top: float = minf(top_row_dp(HudLayout.is_portrait()) * _dp, _safe_rect.size.y * 0.5)
	_room = Rect2(_safe_rect.position + Vector2(0.0, top), _safe_rect.size - Vector2(0.0, top))


## A resize: the metrics again, and the card the HUD theme in base px when no HUD root has given it
## one.
func _apply_metrics() -> void:
	_measure()
	if theme == null or _own_theme:
		theme = HudTheme.scaled(load(THEME_PATH), _dp)
		_own_theme = true
	for box: Container in [_row, _main]:
		box.add_theme_constant_override("separation", roundi(BUTTON_GAP_DP * _dp))
	var least: Vector2 = Vector2(MIN_TARGET_DP, MIN_TARGET_DP) * _dp
	for button: Button in [_skip, _next, _tab]:
		button.custom_minimum_size = least
	for pad: Control in [_head_pad, _side_pad]:
		pad.custom_minimum_size = least
	_chevron.custom_minimum_size = CHEVRON_DP * _dp
	_dock_key = -1  # A resize or turn: the dock is stood again at the next look.
	_dirty = true


func _on_next() -> void:
	if director != null:
		director.next()


func _on_skip() -> void:
	if director != null:
		director.skip()


func _on_beat_done(_done: TutorialBeatDef) -> void:
	if director != null and director.running():
		_show_gap()
	else:
		hide_mark()


func _on_lesson_over(_id: StringName) -> void:
	hide_mark()


func _unbind() -> void:
	if director.beat_shown.is_connected(show_beat):
		director.beat_shown.disconnect(show_beat)
		director.target_changed.disconnect(_on_target_changed)
		director.beat_done.disconnect(_on_beat_done)
		director.lesson_done.disconnect(_on_lesson_over)
		director.lesson_skipped.disconnect(_on_lesson_over)
