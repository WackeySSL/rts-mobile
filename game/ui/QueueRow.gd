class_name QueueRow
extends VBoxContainer
## The queue row at the foot of the build drawer (ADR 0025 section 5, plan P120b): a label with the
## producer's display name and "N IN QUEUE", then one `THUMB_DP` thumb per queue slot: the item's
## card picture, the head with a progress bar, an empty slot as a dashed frame. A tap on an item
## asks to cancel it (`cancel_requested(slot)`); the sender then hands the Command over (`wait_for`)
## and the row takes no tap until a snapshot newer than the tick the runner stamped on it
## (`command.tick >= 0 and snapshot_tick > command.tick`, PlacementController's rule: on Android the
## first snapshot after a tap is published before the Command is drained into the next tick), or
## until another queue is shown (`release`), so a quick second tap never names a slot that the first
## cancel has shifted. A thumb is a `HoldButton`: a finger that moves beyond `slop_dp`, a hold of
## `hold_ms` (final once it fires, ADR 0004; a drag after it does not take it back), a modal or a
## turn make it no tap. The row keeps no snapshot; the thumbs are made once per slot count and only
## change when what they show changes.

signal cancel_requested(slot: int)  ## A tap on the item in `slot` (0 is the head).

const THUMB_DP: float = 56.0  ## The height, and the width where the panel has room for it.
const THUMB_LEAST_DP: float = 48.0  ## The least width: the thumbs shrink to fit the panel.
const LABEL_VARIATION: StringName = &"ItemCaption"
const BAR_DP: float = 6.0
const GAP_DP: float = 0.0  ## Five 56 dp thumbs are the 280 dp of the narrowest panel's content.
const INSET_DP: float = 1.5  ## The frame sits this far inside the thumb: neighbours stay apart.
const DASH_DP: Vector2 = Vector2(6.0, 3.0)  ## The dash and the gap of an empty slot's frame.
const COUNT_TEXT: String = "%s  %d IN QUEUE"

var slop_dp: float = 12.0  ## `InputSettings.tap_slop_dp`.
var hold_ms: int = 300  ## `InputSettings.long_press_ms`: a longer press is no tap.

var _label: Label = Label.new()
var _row: HBoxContainer = HBoxContainer.new()
var _thumbs: Array[QueueThumb] = []
var _waiting: bool = false  ## A cancel was asked for; taps wait.
var _command: Command = null  ## The CANCEL in flight; the runner stamps its `tick`.


func _ready() -> void:
	name = "QueueRow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override(&"separation", 0)
	_label.name = "Label"
	_label.theme_type_variation = LABEL_VARIATION
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_label)
	_row.name = "Thumbs"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	get_viewport().size_changed.connect(_apply_dp)


## True while taps are ignored (a cancel was asked for and no newer snapshot has been shown).
func is_waiting() -> bool:
	return _waiting


## The CANCEL that the tap asked for, sent: taps wait until a snapshot past its stamped tick.
func wait_for(command: Command) -> void:
	_command = command


## Ends the wait: another queue is shown (its slots are not the shifted ones), or nothing was sent.
func release() -> void:
	_waiting = false
	_command = null


## The thumb of `slot` (tests and the sidebar's checks).
func thumb(slot: int) -> Control:
	return _thumbs[slot] if slot >= 0 and slot < _thumbs.size() else null


func thumb_count() -> int:
	return _thumbs.size()


## Shows one queue: `owner_name` and the items (`types`, the card picture of each in `art`, the
## head's `share`). `snapshot_tick` is the tick of the snapshot they come from: past the tick of the
## Command handed to `wait_for`, it ends the wait.
func show_queue(
	owner_name: String,
	slots: int,
	types: PackedInt32Array,
	art: Array[Texture2D],
	share: float,
	snapshot_tick: int
) -> void:
	if _command != null and _command.tick >= 0 and snapshot_tick > _command.tick:
		release()
	_fit(slots)
	var text: String = COUNT_TEXT % [owner_name, types.size()]
	if text != _label.text:
		_label.text = text
	for slot: int in _thumbs.size():
		var item: QueueThumb = _thumbs[slot]
		var filled: bool = slot < types.size()
		var type: int = types[slot] if filled else -1
		var progress: float = share if filled and slot == 0 else 0.0
		var texture: Texture2D = art[slot] if filled else null
		if (
			type != item.type_index
			or texture != item.picture.texture
			or not is_equal_approx(progress, item.share)
		):
			item.type_index = type
			item.picture.texture = texture
			item.share = progress
			item.head = filled and slot == 0
			item.mouse_filter = Control.MOUSE_FILTER_STOP if filled else Control.MOUSE_FILTER_IGNORE
			item.queue_redraw()


## The thumbs for `slots` slots, made once.
func _fit(slots: int) -> void:
	if slots == _thumbs.size():
		return
	while _thumbs.size() > slots:
		var old: QueueThumb = _thumbs.pop_back()
		_row.remove_child(old)
		old.queue_free()
	while _thumbs.size() < slots:
		var item: QueueThumb = QueueThumb.new()
		item.name = "Slot%d" % _thumbs.size()
		item.tapped.connect(_on_tapped.bind(_thumbs.size()))
		var fit: DpMinSize = DpMinSize.new()
		fit.min_dp = Vector2(THUMB_LEAST_DP, THUMB_DP)
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_child(fit)
		_row.add_child(item)
		_thumbs.append(item)
	_apply_dp()


func _on_tapped(slot: int) -> void:
	if _waiting or slot >= _thumbs.size() or _thumbs[slot].type_index < 0 or _thumbs[slot].moved:
		return
	_waiting = true
	cancel_requested.emit(slot)


## The thresholds of a touch on a thumb (`tap_slop_dp`, `long_press_ms`).
func configure(slop: float, hold: int) -> void:
	slop_dp = slop
	hold_ms = hold
	_apply_dp()


func _apply_dp() -> void:
	_row.add_theme_constant_override(&"separation", roundi(UiScale.dp(GAP_DP)))
	for item: QueueThumb in _thumbs:
		item.slop_dp = slop_dp
		item.hold_ms = hold_ms
		item.line_inset = UiScale.dp(INSET_DP)
		item.dash = Vector2(UiScale.dp(DASH_DP.x), UiScale.dp(DASH_DP.y))
		item.bar = UiScale.dp(BAR_DP)
		item.line = get_theme_color(&"text", &"HudTokens")
		item.track = get_theme_color(&"panel", &"HudTokens")
		item.fill = get_theme_color(&"ok", &"HudTokens")
		item.queue_redraw()
