class_name CoachMark
extends Control
## The tutorial's coach mark (plan row P542, ADR 0044 section 2): a ring on the beat's anchor and a
## prompt card with Next (a read-only beat only) and Skip. Presentation only: it reads the
## `TutorialDirector`'s signals and calls its `next()` and `skip()`, and sends no Command.
##
## Input: the node and the ring are `MOUSE_FILTER_IGNORE`, so a touch outside the card goes on to
## what is under it, and the gesture a beat asks for (a tap on the ring's unit, a drag, a pinch) is
## never taken. The card's panel is `STOP`, so a tap on the prompt is not a map tap (no stray move
## or deselect); when `place_card` could not clear the ring the panel is `IGNORE` for that
## placement, so the target is never blocked. Next and Skip always stop.
##
## The ring is on a HUD control found by node name under `hud_root` (`anchor_control`), or on a
## world tile projected through the camera (`anchor_tile`); a tile off the screen pins the ring to
## the nearest edge of the safe rect. A control that is missing or hidden gives a card alone. All
## positions are global (screen) px, so the mark works under any parent.
## The card is placed by `place_card`: below the ring, else above, right, left, slid into the room
## and never over the ring; with no ring it stands at the top centre of the room. The room is the
## safe rect below the top HUD row (the pill, the scope and the attack toast's slot, ADR 0025
## section 2: `top_row_dp`), so the card never covers the pause button or the scope. Besides the
## ring it keeps off every visible, enabled button of the HUD (the open drawer's tabs, items and
## close button, the group chips, the command bar; in a menu, that menu's buttons), 8 dp away where
## there is room, and goes narrower (3/4, then 3/5) before it would stand on one; it is placed again
## when one appears, moves or goes. When the beat
## is `stalled()` the card shows a hint line and the ring turns amber and doubles (a shape change as
## well as a colour). The ring pulses unless `reduced` (the Reduced effects switch): then there is
## no Tween at all.
## Looks come from `theme.tres`: PauseCard, PauseButton, PausePrimary and PauseMuted for the card,
## AccentRenew and HudTokens for the ring. No colour literal.

const CARD_WIDTH_DP: float = 360.0  ## Widest the card gets; less where the room is narrower.
const GAP_DP: float = 16.0  ## Between the ring and the card.
const BUTTON_AIR_DP: float = 8.0  ## Between the card and another button of a menu it stands over.
const BUTTON_GAP_DP: float = 12.0  ## Between Skip and Next: a slip must not end the lesson.
const RING_GROW_DP: float = 6.0  ## The ring stands this far outside a control.
const RING_LINE_DP: float = 3.0
const MIN_TARGET_DP: float = 48.0  ## A ring is never smaller than a touch target.
const PULSE_S: float = 0.8
const PULSE_PX_DP: float = 4.0  ## How far the ring breathes out.
const FIND_EVERY: int = 15  ## Frames between looks for a control that is not there.
const ELLIPSE_STEPS: int = 40
const THEME_PATH: String = "res://game/ui/theme.tres"
const EPSILON: float = 0.01
const WIDTH_SHARES: Array[float] = [1.0, 0.75, 0.6]  ## Of the card's width, in the order tried.
const MAX_COLUMNS: int = 9  ## Columns of the search grid in `place_card`.
## Drawn above every other control of the layer, the pause menu included, whatever order the mark
## was added in: the card that asks for Resume must be seen over the open menu.
const Z_ABOVE_MODALS: int = 100

var director: TutorialDirector
var camera: RtsCamera
## The node under which the anchor controls are looked up by name.
var hud_root: Node
## Reduced effects: no pulse. `_ready` adds the player's switch; a test may set it before.
var reduced: bool = false

var _ring: Control
var _card: PanelContainer
var _prompt: Label
var _hint: Label
var _row: HBoxContainer
var _next: Button
var _skip: Button
var _beat: TutorialBeatDef = null
var _target: Control = null
var _pulse: Tween = null
var _pulse_value: float = 0.0
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
var _next_find: int = 0
var _blocked_now: Array[Rect2] = []  ## What the card was last placed clear of.
var _hard_now: Array[Rect2] = []
var _blocked_modal: Node = null  ## The modal whose buttons are cached, and when to look again.
var _blocked_controls: Array[Control] = []
var _blocked_scan: int = 0


func _ready() -> void:
	z_index = Z_ABOVE_MODALS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reduced = reduced or MenuPrefs.reduced_effects()
	_ring = Control.new()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.theme_type_variation = &"PauseCard"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP  # Taps on the card are not map taps.
	add_child(_card)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.theme_type_variation = &"PauseMuted"
	_hint.text = tr("Stuck? Try what the card says, or tap Skip to leave.")
	for label: Label in [_prompt, _hint]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(_row)
	_skip = _button("Skip", "SKIP LESSON", &"PauseButton")
	_next = _button("Next", "NEXT", &"PausePrimary")
	_next.pressed.connect(_on_next)
	_skip.pressed.connect(_on_skip)
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
		director.beat_done.connect(_on_beat_done)
		director.lesson_done.connect(_on_lesson_over)
		director.lesson_skipped.connect(_on_lesson_over)
	if _ring != null and director.current != null:
		show_beat(director.current)


## Puts the prompt of `beat` up (when the mark is not yet in the tree, as soon as it is).
func show_beat(beat: TutorialBeatDef) -> void:
	_beat = beat
	if _ring == null:
		return
	_target = null
	_next_find = 0
	_blocked_scan = 0  # The beat's controls may be new: list them again.
	_dirty = true
	_measure()
	_prompt.text = tr(String(beat.prompt_key))
	visible = true
	set_process(true)
	_update()


func hide_mark() -> void:
	_beat = null
	_target = null
	_ring_now = Rect2()
	visible = false
	if _ring != null:
		set_process(false)
	_stop_pulse()


## The control the ring is on (null: no control beat, or none found or shown).
func target_control() -> Control:
	return _target if is_instance_valid(_target) else null


## The ring's rect in screen px, as of the last frame (an empty rect: no ring).
func ring_rect() -> Rect2:
	return _ring_now


## The card's rect in screen px.
func card_rect() -> Rect2:
	return Rect2(_card.global_position, _card.size)


func ring_pulsing() -> bool:
	return _pulse != null and _pulse.is_valid()


## The height of the top HUD row, dp, that the card keeps clear of (ADR 0025 section 2): the scope
## (56, taller than the pill and the toast) and a gap; upright the toast's slot under the pill and
## the scope as well.
static func top_row_dp(portrait: bool) -> float:
	var row: float = HudCorners.SCOPE_DP + HudCorners.GAP_DP
	if portrait:
		row += HudCorners.TOAST_H_DP + HudCorners.GAP_DP
	return row


## Where the card stands: `ring` is the ring's rect (empty: none), `card` the card's size, `room`
## the rect it must lie in, `gap` the room between them and `row_h` the height of the buttons'
## row at the card's foot. The candidates, in order: below the ring, above, right, left, then the
## top and the bottom of `room`, each slid into `room` and taken when it clears the ring. None
## clearing it, the one whose button row misses the ring most, then the one that overlaps it
## least. With no ring and nothing to keep off: the top centre of `room`. `blocked` are rects the
## card should not cover (the buttons of the HUD or of the menu the ring is in), kept `air` away
## while a place has room, and `hard` rects it never covers (an ad band, ad policy): when there are
## any, the sides, corners and a grid of `room` are tried too (with no ring, the top centre first).
## The first place that clears the ring and both lists is taken; none, the first that clears the
## ring, the `blocked` rects themselves and `hard`; none of those, the first that clears the ring
## and `hard`; none of those, the fallback below, which keeps off `hard` wherever a place does.
static func place_card(
	ring: Rect2,
	card: Vector2,
	room: Rect2,
	gap: float,
	row_h: float = 0.0,
	blocked: Array[Rect2] = [],
	hard: Array[Rect2] = [],
	air: float = 0.0
) -> Rect2:
	var fit: Vector2 = card.min(room.size)
	var top: Vector2 = Vector2(room.get_center().x - fit.x * 0.5, room.position.y)
	var searching: bool = not blocked.is_empty() or not hard.is_empty()
	if not ring.has_area() and not searching:
		return Rect2(top, fit)
	var centre: Vector2 = ring.get_center() if ring.has_area() else room.get_center()
	var across: float = centre.x - fit.x * 0.5
	var tries: Array[Vector2] = [top]  # With no ring: the top centre, then the search below.
	if ring.has_area():
		tries = [
			Vector2(across, ring.end.y + gap),
			Vector2(across, ring.position.y - gap - fit.y),
			Vector2(ring.end.x + gap, centre.y - fit.y * 0.5),
			Vector2(ring.position.x - gap - fit.x, centre.y - fit.y * 0.5),
			Vector2(across, room.position.y),
			Vector2(across, room.end.y - fit.y),
		]
	var spread: Array[Vector2] = []
	if searching:
		spread = tries.duplicate()
		(
			spread
			. append_array(
				[
					Vector2(room.position.x, centre.y - fit.y * 0.5),
					Vector2(room.end.x - fit.x, centre.y - fit.y * 0.5),
					room.position,
					Vector2(room.end.x - fit.x, room.position.y),
					Vector2(room.position.x, room.end.y - fit.y),
					room.end - fit,
				]
			)
		)
		var step: float = maxf(fit.y * 0.5, 1.0)
		var columns: Array[float] = [across, room.position.x, room.end.x - fit.x]
		var x_step: float = maxf(fit.x * 0.5, 1.0)
		var x_at: float = room.position.x + x_step
		while x_at < room.end.x - fit.x - EPSILON and columns.size() < MAX_COLUMNS:
			columns.append(x_at)  # A narrow gap between two panels may fit none of the three.
			x_at += x_step
		for x: float in columns:
			var y: float = room.position.y
			while y <= room.end.y - fit.y + EPSILON:
				spread.append(Vector2(x, y))
				y += step
		for keep_soft: bool in [true, false]:  # Button air may go; the ring and the band may not.
			for at: Vector2 in spread:
				var box: Rect2 = Rect2(at.clamp(room.position, room.end - fit), fit)
				if box.intersection(ring).get_area() > EPSILON or _hits_any(box, hard):
					continue
				if not _hits_any(box, blocked, air if keep_soft else 0.0):
					return box
	var best: Rect2 = Rect2(top, fit)
	var least_row: float = INF
	var least: float = INF
	var pool: Array[Vector2] = tries if hard.is_empty() else _clear_of(tries, fit, room, hard)
	if pool.is_empty():
		pool = _clear_of(spread, fit, room, hard)
	if pool.is_empty():
		pool = tries
	for at: Vector2 in pool:
		var box: Rect2 = Rect2(at.clamp(room.position, room.end - fit), fit)
		var over: float = box.intersection(ring).get_area()
		if over <= EPSILON:
			return box
		var row: Rect2 = Rect2(box.position.x, box.end.y - row_h, box.size.x, row_h)
		var row_over: float = row.intersection(ring).get_area()
		if row_over < least_row - EPSILON or (row_over <= least_row + EPSILON and over < least):
			least_row = row_over
			least = over
			best = box
	return best


## The places of `at` whose card, slid into `room`, misses every rect of `rects`.
static func _clear_of(
	at: Array[Vector2], fit: Vector2, room: Rect2, rects: Array[Rect2]
) -> Array[Vector2]:
	var found: Array[Vector2] = []
	for place: Vector2 in at:
		if not _hits_any(Rect2(place.clamp(room.position, room.end - fit), fit), rects):
			found.append(place)
	return found


static func _hits_any(box: Rect2, rects: Array[Rect2], air: float = 0.0) -> bool:
	for rect: Rect2 in rects:
		if box.intersects(rect.grow(air) if air > 0.0 else rect):
			return true
	return false


## The rects the card keeps clear of: into `soft` every visible, enabled button of the scope; into
## `hard` the scope's ad band, grown 16 dp (ad policy). The scope is the modal the target is in (a
## ModalFrame, as the pause menu is), else the whole HUD under `hud_root`, so the card never stands
## on a control the beat needs next: the open drawer's tabs, items and close button, the group
## chips, the command bar. The controls are listed once per scope (and again every `FIND_EVERY`
## frames and on a new beat, for one built later); whether each shows and its rect are read each
## frame, so a chip that appears or a drawer that slides in re-places the card at once.
func _collect_blocked(soft: Array[Rect2], hard: Array[Rect2]) -> void:
	var modal: Node = _target
	while modal != null and not modal is ModalFrame:
		modal = modal.get_parent()
	var scope: Node = modal if modal != null else hud_root
	if scope == null:
		_blocked_modal = null
		return
	var frame: int = Engine.get_process_frames()
	if scope != _blocked_modal or frame >= _blocked_scan:
		_blocked_modal = scope
		_blocked_scan = frame + FIND_EVERY
		_blocked_controls.clear()
		for node: Node in scope.find_children("*", "Control", true, false):
			if node == _target or is_ancestor_of(node):
				continue
			if node is BaseButton or node is AdBannerBand:
				_blocked_controls.append(node as Control)
	for control: Control in _blocked_controls:
		if not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		var button: BaseButton = control as BaseButton
		if button != null and button.disabled:
			continue
		var shown: Rect2 = _visible_rect(control)
		if not shown.has_area():
			continue
		if control is AdBannerBand:  # Content keeps the buttons' gap from an ad (ad policy).
			hard.append(shown.grow(GAP_DP * _dp))
		else:  # `place_card` keeps `BUTTON_AIR_DP` off them while a place has room.
			soft.append(shown)


## `control`'s rect as the player sees it: cut by the scroll areas it stands in and by the screen.
func _visible_rect(control: Control) -> Rect2:
	var shown: Rect2 = control.get_global_rect()
	var up: Node = control.get_parent()
	while up != null and up != hud_root:
		var area: ScrollContainer = up as ScrollContainer
		if area != null:
			shown = shown.intersection(area.get_global_rect())
		up = up.get_parent()
	return shown.intersection(Rect2(Vector2.ZERO, _view))


## Whether the mark must stand down: a visible modal (the pause menu, a question, the result
## screen, an overlay of the menu) covers the HUD and does not hold this beat's target, so the card
## and its ring would sit over a menu they have nothing to say about and would eat its taps. Only a
## card that points into the modal shows over it (the `resume` card over the pause menu).
func _covered() -> bool:
	var host: Node = get_parent()
	if host == null:
		return false
	for node: Node in host.get_children():
		if _covers(node):
			return true
		if node is ModalFrame:  # The questions and the overlays of a menu are its children.
			for inner: Node in node.get_children():
				if _covers(inner):
					return true
	return false


func _covers(node: Node) -> bool:
	var control: Control = node as Control
	if control == null or control == self or not (control is ModalFrame or control is MenuStack):
		return false
	if not control.is_visible_in_tree():
		return false
	return not (is_instance_valid(_target) and control.is_ancestor_of(_target))


func _process(_delta: float) -> void:
	_update()


## One look at the beat: the ring's box and the card's state; the card is laid out only on a change.
func _update() -> void:
	if _beat == null or not is_inside_tree():
		return
	_resolve_target()
	var covered: bool = _covered()
	if covered == visible:  # The state changed: a hidden mark draws nothing and takes no touch.
		visible = not covered
		_dirty = true
		if covered:
			_stop_pulse()
	if covered:
		return
	var ring: Rect2 = _ring_box()
	var blocked: Array[Rect2] = []
	var hard: Array[Rect2] = []
	_collect_blocked(blocked, hard)
	var stalled: bool = director != null and director.stalled() and not director.can_next()
	var can_next: bool = director != null and director.can_next()
	var changed: bool = (
		_dirty
		or ring != _ring_now
		or blocked != _blocked_now
		or hard != _hard_now
		or stalled != _stalled_now
		or can_next != _can_next_now
		or size != _size_now
	)
	if not changed and _again == 0:
		return
	if changed:
		_again = 2  # A label shapes its wrapped text a frame after its width changes: look twice.
	_dirty = false
	_ring_now = ring
	_blocked_now = blocked
	_hard_now = hard
	_stalled_now = stalled
	_can_next_now = can_next
	_size_now = size
	_next.visible = can_next
	_hint.visible = stalled
	_ring.global_position = Vector2.ZERO
	_ring.size = _view
	if ring.size != _points_for:
		_points_for = ring.size
		_points = _ellipse(ring.size * 0.5)
	_ring.queue_redraw()
	if ring.has_area():
		_start_pulse()
	else:
		_stop_pulse()
	var full: float = minf(CARD_WIDTH_DP * _dp, _room.size.x)
	var row_h: float = (
		MIN_TARGET_DP * _dp + _card.get_theme_stylebox(&"panel").get_margin(SIDE_BOTTOM)
	)
	var air: float = BUTTON_AIR_DP * _dp
	var placed: Rect2 = Rect2()
	var found: bool = false
	for share: float in WIDTH_SHARES:  # A narrower card where the full one has no free place.
		var size_now: Vector2 = _fit_card(full * share)
		var at: Rect2 = place_card(ring, size_now, _room, GAP_DP * _dp, row_h, blocked, hard, air)
		if share == WIDTH_SHARES[0]:
			placed = at
		if _is_clear(at, ring, blocked, hard):
			placed = at
			found = true
			break
	if not found:  # No free place at any width: the full card, placed as well as it can be.
		_fit_card(full)
	_card.global_position = placed.position
	# A card that could not clear the ring lets touches through, so it never blocks the target.
	var covers: bool = placed.intersection(ring).get_area() > EPSILON
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE if covers else Control.MOUSE_FILTER_STOP
	_again -= 1


## Gives the card `width` px and the height its wrapped text needs; returns that size.
func _fit_card(width: float) -> Vector2:
	var panel: StyleBox = _card.get_theme_stylebox(&"panel")
	var inner: float = width - panel.get_minimum_size().x
	for label: Label in [_prompt, _hint]:  # The wrapped height needs the width first.
		label.custom_minimum_size.x = inner
		label.size.x = inner
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.size = Vector2(width, _card.get_combined_minimum_size().y)
	return _card.size


## Whether `box` is off the ring, the hard rects and every blocked button (with the air).
func _is_clear(box: Rect2, ring: Rect2, blocked: Array[Rect2], hard: Array[Rect2]) -> bool:
	if box.intersection(ring).get_area() > EPSILON or _hits_any(box, hard):
		return false
	return not _hits_any(box, blocked)


## The ring's box from the beat, global px: a control's rect grown a little, or the tile's ground
## ellipse, at least a touch target and pinned into the safe rect. Empty with no anchor or no
## control to point at. Pure: it reads `_target`, it never looks for one.
func _ring_box() -> Rect2:
	var box: Rect2 = Rect2()
	match _beat.anchor:
		TutorialBeatDef.Anchor.CONTROL:
			if not is_instance_valid(_target):
				return Rect2()
			box = _target.get_global_rect().grow(RING_GROW_DP * _dp)
		TutorialBeatDef.Anchor.TILE:
			if camera == null:
				return Rect2()
			var world: Vector2 = IsoProjection.cell_centre_px(
				_beat.anchor_tile.x, _beat.anchor_tile.y
			)
			var radius: Vector2 = IsoProjection.ellipse_px(ViewScale.MILLI_PER_TILE) * camera.zoom
			box = Rect2(camera.world_to_screen(world) - radius, radius * 2.0)
		_:
			return Rect2()
	var least: float = MIN_TARGET_DP * _dp
	var fit: Vector2 = box.size.max(Vector2(least, least))
	box = Rect2(box.get_center() - fit * 0.5, fit)
	var top_left: Vector2 = _safe_rect.position
	box.position = box.position.clamp(top_left, (_safe_rect.end - box.size).max(top_left))
	return box.intersection(_safe_rect) if box.intersects(_safe_rect) else box  # Never past an edge.


## Keeps `_target` the named control while it stands and shows; looks again for a missing one
## every `FIND_EVERY` frames, not every frame.
func _resolve_target() -> void:
	if _beat.anchor != TutorialBeatDef.Anchor.CONTROL:
		_target = null
		return
	if is_instance_valid(_target) and _target.is_visible_in_tree():
		return
	_target = null
	var frame: int = Engine.get_process_frames()
	if hud_root == null or _beat.anchor_control == &"" or frame < _next_find:
		return
	_next_find = frame + FIND_EVERY
	var found: Control = hud_root.find_child(String(_beat.anchor_control), true, false) as Control
	if found != null and found.is_visible_in_tree():
		_target = found


func _draw_ring() -> void:
	if not _ring_now.has_area() or _beat == null:
		return
	var tone: Color = (
		get_theme_color(&"money", &"HudTokens")
		if _stalled_now
		else get_theme_color(&"light", &"AccentRenew")
	)
	var line: float = RING_LINE_DP * _dp
	var centre: Vector2 = _ring_now.get_center()
	var half: Vector2 = _ring_now.size * 0.5
	for turn: int in 2 if _stalled_now else 1:  # Stalled: a second, outer ring.
		var grow: float = line * 2.0 * turn + _pulse_value * PULSE_PX_DP * _dp
		if _beat.anchor == TutorialBeatDef.Anchor.CONTROL:
			_ring.draw_rect(_ring_now.grow(grow).intersection(_safe_rect), tone, false, line)
		else:
			_ring.draw_set_transform(centre, 0.0, (half + Vector2(grow, grow)) / half)
			_ring.draw_polyline(_points, tone, line, true)
			_ring.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The ellipse of semi-axes `half`, about the origin, closed.
static func _ellipse(half: Vector2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for step: int in ELLIPSE_STEPS + 1:
		var angle: float = TAU * float(step) / ELLIPSE_STEPS
		points.append(Vector2(cos(angle), sin(angle)) * half)
	return points


func _start_pulse() -> void:
	if reduced or ring_pulsing():
		return
	_pulse = create_tween().set_loops()
	_pulse.tween_method(_set_pulse, 0.0, 1.0, PULSE_S)
	_pulse.tween_method(_set_pulse, 1.0, 0.0, PULSE_S)


func _set_pulse(value: float) -> void:
	_pulse_value = value
	_ring.queue_redraw()


func _stop_pulse() -> void:
	if _pulse != null:
		_pulse.kill()
		_pulse = null
	_pulse_value = 0.0


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
	_row.add_theme_constant_override("separation", roundi(BUTTON_GAP_DP * _dp))
	for button: Button in [_skip, _next]:
		button.custom_minimum_size = Vector2(MIN_TARGET_DP * _dp, MIN_TARGET_DP * _dp)
	_dirty = true


func _on_next() -> void:
	if director != null:
		director.next()


func _on_skip() -> void:
	if director != null:
		director.skip()


func _on_beat_done(_done: TutorialBeatDef) -> void:
	hide_mark()


func _on_lesson_over(_id: StringName) -> void:
	hide_mark()


func _unbind() -> void:
	if director.beat_shown.is_connected(show_beat):
		director.beat_shown.disconnect(show_beat)
		director.beat_done.disconnect(_on_beat_done)
		director.lesson_done.disconnect(_on_lesson_over)
		director.lesson_skipped.disconnect(_on_lesson_over)
