class_name RevealBadge
extends Control
## The enemy's sweep on the HUD (ADR 0036 sections 11 and 12, plan P235). While another player's
## sweep is on (`snapshot.reveal` 1) a satellite badge stays lit; while it is paused (2) it is
## dimmed with a pause mark (never colour alone); at 0 it goes. When a sweep is fired (the STRIKE
## event of kind REVEAL, once) a warning line stands beside the badge for `life.reveal_warn_ms`.
## Information only: it takes no touch. Its rect is `HudCorners.REVEAL` and, with the line,
## `REVEAL_LINE` (the right column's next part up), taken on every change and resize. It hides
## while the drawer, the full map or the pause menu is open, as the column it stands in does.
## It reads only `runner.snapshot` and writes nothing to the sim.

const DEFAULT_LIFE: LifeSettings = preload("res://data/life_settings.tres")
const LINE: String = "Enemy sweep on you"
const LINE_PAD_DP: float = 8.0  ## The plate's inner margin each side of the text.
const GLYPH_PAD: float = 0.14  ## The satellite's inset in the badge, share of its side.
const DIM_ALPHA: float = 0.45
const TEXT_VARIATION: StringName = &"ItemCaption"

@export var runner: MatchRunner
@export var aim: StrikeAim  ## Whether the strike button stands in the column.
@export var feed: HudStateFeed
@export var safe_area: SafeAreaMargin
@export var build_button: BuildButton  ## Its Ready chip stands in the column upright.
@export var group_column: GroupColumn  ## The line starts right of it.
@export var life: LifeSettings

var state: int = 0  ## The shown sweep: 0 none, 1 on, 2 paused (an enemy's; on beats paused).
var line_ms: float = 0.0  ## What the warning line has left.

var _badge: Rect2 = Rect2()  ## The badge in this node's own space.
var _line: Rect2 = Rect2()  ## The line's plate in this node's own space (empty: none).
var _covered: bool = false  ## A drawer, the full map or the pause menu covers the column.
var _last: Vector2i = Vector2i(-1, -1)  ## The state and the Ready chip at the last refresh.
var _text: Label = Label.new()
var _serial: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)  # Only while the warning line has time left.
	if life == null:
		life = DEFAULT_LIFE
	_text.theme_type_variation = TEXT_VARIATION
	_text.text = LINE
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_text)
	if runner != null:
		runner.ticked.connect(_on_ticked)
	if aim != null:
		aim.changed.connect(refresh)
	if feed != null:
		feed.state.changed.connect(refresh.unbind(1))
	if group_column != null:
		group_column.laid_out.connect(refresh)
	get_viewport().size_changed.connect(refresh)
	refresh()


func _process(delta: float) -> void:
	advance(delta * 1000.0)


## A frame of `delta_ms` passed: the warning line ages and goes, but only while it can be seen: a
## drawer, the full map or the pause menu over the column stops its clock.
func advance(delta_ms: float) -> void:
	if line_ms <= 0.0 or _covered:
		return
	line_ms -= delta_ms
	if line_ms <= 0.0:
		line_ms = 0.0
		refresh()


func _on_ticked(_tick: int) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null:
		return
	var player: int = FogLayer.local_player_of(runner)
	var fresh: bool = snap.match_serial != _serial
	if fresh:  # A new match: no warning of the last one stays.
		_serial = snap.match_serial
		line_ms = 0.0
	var raised: bool = false
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.STRIKE and events[at + 4] == Strike.Kind.REVEAL:
			if events[at + 5] != player:
				line_ms = float(life.reveal_warn_ms)
				raised = true
	if not raised and state_of(snap, player) == Reveal.State.OFF:
		line_ms = 0.0  # The sweep is over: its warning does not outlive it.
	var chip: int = 1 if build_button != null and build_button.ready_type >= 0 else 0
	var now: Vector2i = Vector2i(state_of(snap, player), chip)
	if raised or now != _last or fresh:
		refresh()


## The enemy sweep's state in `snap` for `player`: 1 when any other player's sweep is on, else 2
## when one is paused, else 0.
static func state_of(snap: MatchSnapshot, player: int) -> int:
	var found: int = 0
	for other: int in range(1, snap.reveal.size()):
		if other != player and snap.reveal[other] != 0:
			found = Reveal.State.ON if snap.reveal[other] == Reveal.State.ON else maxi(found, 2)
	return found


## Reads the state and takes the rect; hidden while nothing shows or the column is covered.
func refresh() -> void:
	if not is_inside_tree():
		return
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	state = 0
	if snap != null:
		state = state_of(snap, FogLayer.local_player_of(runner))
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	feed.state.fill(shown)
	feed.state.fill_bar(shown)
	_covered = shown.drawer or shown.map or feed.state.is_open(HudState.Unfold.PAUSE)
	_last = Vector2i(state, 1 if build_button != null and build_button.ready_type >= 0 else 0)
	set_process(line_ms > 0.0)
	visible = (state != 0 or line_ms > 0.0) and not _covered
	if not visible:
		return
	shown.reveal = true
	shown.reveal_line = line_ms > 0.0
	shown.strike = aim != null and aim.owned
	shown.ready = build_button != null and build_button.ready_type >= 0
	shown.groups = group_column.item_count() if group_column != null else 1
	var margin_dp: float = SafeAreaMargin.DEFAULT_MARGIN_DP
	margin_dp = margin_dp if safe_area == null else safe_area.margin_dp
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), UiScale.base_px_per_dp(), false, shown
	)
	var span: Rect2 = rects[HudCorners.REVEAL]
	var line: Rect2 = rects.get(HudCorners.REVEAL_LINE, Rect2())
	if line.size.x > 0.0:
		span = span.merge(line)
	position = span.position
	size = span.size
	_badge = Rect2(rects[HudCorners.REVEAL].position - position, rects[HudCorners.REVEAL].size)
	_text.visible = line.size.x > 0.0
	_line = Rect2()
	if _text.visible:
		_line = Rect2(line.position - position, line.size)
		var pad: float = UiScale.dp(LINE_PAD_DP)
		_text.position = _line.position + Vector2(pad, 0.0)
		_text.size = _line.size - Vector2(pad * 2.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var plate: StyleBox = get_theme_stylebox(&"panel", &"HudPanel")
	if _line.size.x > 0.0:
		draw_style_box(plate, _line)  # The line reads on any ground.
	if state == 0:
		return
	draw_style_box(plate, _badge)
	var pad: float = _badge.size.x * GLYPH_PAD
	var inside: Rect2 = _badge.grow(-pad)
	var tint: Color = get_theme_color(&"danger", SweepMark.TOKENS)
	if state == Reveal.State.PAUSED:
		tint.a = DIM_ALPHA
	SweepMark.satellite(self, inside, tint)
	if state == Reveal.State.PAUSED:
		var corner: Rect2 = Rect2(_badge.end - _badge.size * 0.5, _badge.size * 0.42)
		var text: Color = get_theme_color(&"text", SweepMark.TOKENS)
		SweepMark.pause(self, corner, text, get_theme_color(&"panel", SweepMark.TOKENS))
