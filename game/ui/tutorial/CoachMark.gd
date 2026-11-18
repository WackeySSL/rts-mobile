class_name CoachMark
extends Control
## The tutorial's coach mark (plan row P542, ADR 0044 section 2): a ring on the beat's anchor and a
## prompt card with Next (a read-only beat only) and Skip. Presentation only: it reads the
## `TutorialDirector`'s signals and calls its `next()` and `skip()`, and sends no Command.
##
## Input: the node, the ring and the card's panel and texts are `MOUSE_FILTER_IGNORE`, so a touch
## anywhere but on the Next and Skip buttons goes on to what is under it, and the gesture a beat
## asks for (a tap on the ring's unit, a drag, a pinch) is never taken. Only the two buttons stop.
##
## The ring is on a HUD control found by node name under `hud_root` (`anchor_control`), or on a
## world tile projected through the camera (`anchor_tile`); a tile off the screen pins the ring to
## the nearest edge of the safe rect. A control that is missing or hidden gives a card alone.
## The card is placed by `place_card`: below the ring, else above, right, left, slid into the safe
## rect and never over the ring; with no ring it stands at the top centre, between the pill and the
## scope. When the beat is `stalled()` the card shows a hint line and the ring turns amber and
## doubles (a shape change as well as a colour). The ring pulses unless `reduced` (the Reduced
## effects switch): then there is no Tween at all.
## Looks come from `theme.tres`: PauseCard, PauseButton, PausePrimary and PauseMuted for the card,
## AccentRenew and HudTokens for the ring. No colour literal.

const CARD_WIDTH_DP: float = 360.0  ## Widest the card gets; less where the safe rect is narrower.
const GAP_DP: float = 16.0  ## Between the ring and the card.
const RING_GROW_DP: float = 6.0  ## The ring stands this far outside a control.
const RING_LINE_DP: float = 3.0
const MIN_TARGET_DP: float = 48.0  ## A ring is never smaller than a touch target.
const PULSE_S: float = 0.8
const PULSE_PX_DP: float = 4.0  ## How far the ring breathes out.
const THEME_PATH: String = "res://game/ui/theme.tres"
const EPSILON: float = 0.01

var director: TutorialDirector
var camera: RtsCamera
## The node under which the anchor controls are looked up by name.
var hud_root: Node
## Reduced effects: no pulse. `_ready` reads the player's switch; a test may set it.
var reduced: bool = false

var _ring: Control = Control.new()
var _card: PanelContainer = PanelContainer.new()
var _prompt: Label = Label.new()
var _hint: Label = Label.new()
var _next: Button = Button.new()
var _skip: Button = Button.new()
var _beat: TutorialBeatDef = null
var _target: Control = null
var _pulse: Tween = null
var _key: Array = []  ## What the layout was last made for; a change makes it again.
var _own_theme: bool = false
var _pulse_value: float = 0.0
var _again: int = 0  ## Layouts still to make for the change in hand.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reduced = MenuPrefs.reduced_effects()
	_ring.name = "Ring"
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	_card.name = "Card"
	_card.theme_type_variation = &"PauseCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)
	_prompt.name = "Prompt"
	_hint.name = "Hint"
	_hint.theme_type_variation = &"PauseMuted"
	_hint.text = tr("Stuck? Try what the card says, or tap Skip to leave.")
	for label: Label in [_prompt, _hint]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(label)
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(row)
	_skip.name = "Skip"
	_skip.text = tr("Skip")
	_skip.theme_type_variation = &"PauseButton"
	_next.name = "Next"
	_next.text = tr("Next")
	_next.theme_type_variation = &"PausePrimary"
	for button: Button in [_skip, _next]:
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(button)
	_next.pressed.connect(_on_next)
	_skip.pressed.connect(_on_skip)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	visible = false
	set_process(false)
	if director != null:
		bind(director)


## Follows `new_director`'s beats. Shows at once when a beat is already on.
func bind(new_director: TutorialDirector) -> void:
	if director != null and director != new_director:
		_unbind()
	director = new_director
	if director == null:
		return
	if not director.beat_shown.is_connected(show_beat):
		director.beat_shown.connect(show_beat)
		director.beat_done.connect(_on_beat_done)
		director.lesson_done.connect(_on_lesson_over)
		director.lesson_skipped.connect(_on_lesson_over)
	if is_inside_tree() and director.current != null:
		show_beat(director.current)


## Puts the prompt of `beat` up.
func show_beat(beat: TutorialBeatDef) -> void:
	_beat = beat
	_target = null
	_prompt.text = tr(String(beat.prompt_key))
	_key = []
	visible = true
	set_process(true)
	_update()


func hide_mark() -> void:
	_beat = null
	_target = null
	visible = false
	set_process(false)
	_stop_pulse()


## The control the ring is on (null: no control beat, or none found or shown).
func target_control() -> Control:
	return _target


## The ring's rect in screen px (an empty rect: no ring).
func ring_rect() -> Rect2:
	return _ring_box(_safe())


func card_rect() -> Rect2:
	return Rect2(_card.position, _card.size)


func ring_pulsing() -> bool:
	return _pulse != null and _pulse.is_valid()


## Where the card stands: `ring` is the ring's rect (empty: none), `card` the card's size, `safe`
## the rect it must lie in, `gap` the room between them. The candidates, in order: below the ring,
## above, right, left, each slid along its side into `safe` and taken when it clears the ring; none
## clearing it, the one that overlaps it least. With no ring: the top centre of `safe`.
static func place_card(ring: Rect2, card: Vector2, safe: Rect2, gap: float) -> Rect2:
	var fit: Vector2 = card.min(safe.size)
	if not ring.has_area():
		return Rect2(Vector2(safe.get_center().x - fit.x * 0.5, safe.position.y), fit)
	var centre: Vector2 = ring.get_center()
	var tries: Array[Vector2] = [
		Vector2(centre.x - fit.x * 0.5, ring.end.y + gap),
		Vector2(centre.x - fit.x * 0.5, ring.position.y - gap - fit.y),
		Vector2(ring.end.x + gap, centre.y - fit.y * 0.5),
		Vector2(ring.position.x - gap - fit.x, centre.y - fit.y * 0.5),
	]
	var best: Rect2 = Rect2()
	var least: float = INF
	for at: Vector2 in tries:
		var box: Rect2 = Rect2(at.clamp(safe.position, safe.end - fit), fit)
		var over: float = box.intersection(ring).get_area()
		if over < least:
			least = over
			best = box
		if over <= EPSILON:
			break
	return best


func _process(_delta: float) -> void:
	_update()


func _update() -> void:
	if _beat == null:
		return
	var safe: Rect2 = _safe()
	var ring: Rect2 = _ring_box(safe)
	var stalled: bool = director != null and director.stalled() and not director.can_next()
	var can_next: bool = director != null and director.can_next()
	var key: Array = [ring, safe, stalled, can_next, size]
	if key == _key:
		return
	if _again == 0:
		_again = 2  # A label shapes its wrapped text a frame after its width changes: look twice.
	_key = key
	_next.visible = can_next
	_hint.visible = stalled
	_ring.position = Vector2.ZERO
	_ring.size = size
	_ring.queue_redraw()
	_start_pulse()
	var dp: float = UiScale.base_px_per_dp()
	var width: float = minf(CARD_WIDTH_DP * dp, safe.size.x)
	var inner: float = width - _card.get_theme_stylebox(&"panel").get_minimum_size().x
	for label: Label in [_prompt, _hint]:  # The wrapped height needs the width first.
		label.custom_minimum_size.x = inner
		label.size.x = inner
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.size = Vector2(width, _card.get_combined_minimum_size().y)
	_card.position = place_card(ring, _card.size, safe, GAP_DP * dp).position
	_again -= 1
	if _again > 0:
		_key = []


## The ring's box from the beat: a control's rect grown a little, or the tile's ground ellipse, at
## least a touch target and pinned into `safe`. Empty with no anchor or no control to point at.
func _ring_box(safe: Rect2) -> Rect2:
	if _beat == null:
		return Rect2()
	var dp: float = UiScale.base_px_per_dp()
	var box: Rect2 = Rect2()
	match _beat.anchor:
		TutorialBeatDef.Anchor.CONTROL:
			_target = _find_target()
			if _target == null:
				return Rect2()
			box = _target.get_global_rect().grow(RING_GROW_DP * dp)
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
	var least: float = MIN_TARGET_DP * dp
	var fit: Vector2 = box.size.max(Vector2(least, least))
	box = Rect2(box.get_center() - fit * 0.5, fit)
	box.position = box.position.clamp(safe.position, (safe.end - box.size).max(safe.position))
	return box


## The named control under `hud_root`, shown in the tree; found again when the old one is gone.
func _find_target() -> Control:
	if is_instance_valid(_target) and _target.is_visible_in_tree():
		return _target
	if hud_root == null or _beat.anchor_control == &"":
		return null
	var found: Control = hud_root.find_child(String(_beat.anchor_control), true, false) as Control
	return found if found != null and found.is_visible_in_tree() else null


func _draw_ring() -> void:
	var ring: Rect2 = _ring_box(_safe())
	if not ring.has_area() or _beat == null:
		return
	var stalled: bool = _hint.visible
	var tone: Color = (
		get_theme_color(&"money", &"HudTokens")
		if stalled
		else get_theme_color(&"light", &"AccentRenew")
	)
	var dp: float = UiScale.base_px_per_dp()
	var line: float = RING_LINE_DP * dp
	for turn: int in 2 if stalled else 1:  # Stalled: a second, outer ring.
		var out: Rect2 = ring.grow(line * 2.0 * turn + _pulse_value * PULSE_PX_DP * dp)
		if _beat.anchor == TutorialBeatDef.Anchor.CONTROL:
			_ring.draw_rect(out, tone, false, line)
		else:
			_ring.draw_polyline(_ellipse(out), tone, line, true)


static func _ellipse(box: Rect2) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var centre: Vector2 = box.get_center()
	var steps: int = 40
	for step: int in steps + 1:
		var angle: float = TAU * float(step) / steps
		points.append(centre + Vector2(cos(angle), sin(angle)) * box.size * 0.5)
	return points


func _start_pulse() -> void:
	if reduced or ring_pulsing() or not _ring.is_inside_tree():
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


func _safe() -> Rect2:
	return SafeAreaMargin.rect_inside(
		get_viewport().get_visible_rect(), SafeAreaMargin.DEFAULT_MARGIN_DP
	)


## The card's buttons are at least 48 dp, and, with no theme from a HUD root, the card has the
## HUD theme in base px.
func _apply_dp() -> void:
	var dp: float = UiScale.base_px_per_dp()
	if theme == null or _own_theme:
		theme = HudTheme.scaled(load(THEME_PATH), dp)
		_own_theme = true
	for button: Button in [_skip, _next]:
		button.custom_minimum_size = Vector2(MIN_TARGET_DP * dp, MIN_TARGET_DP * dp)
	_key = []


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
