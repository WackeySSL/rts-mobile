class_name BuildButton
extends Button
## BUILD (ADR 0025 section 4, plan P120): the 64 dp round button at the bottom right that opens the
## build drawer (`HudState` DRAWER). The accent disc of the local player's faction carries the
## glyph `glyph_menu_open` over the word "BUILD"; a 4 dp ring round it fills clockwise from the top
## with the item that finishes first among the heads of the player's queues (the least work left),
## and a white disc at the top right counts the items in all the queues (hidden at 0). It reads the
## published snapshot only, redraws when the ring or the count changes (a tick, never per frame at
## rest) and sends nothing. It hides while the drawer or the pause menu is open, and takes the rect
## `HudCorners.place` gives BUILD on `_ready` and on every resize. Stalled and the Ready chip are
## P120c's.

const ICON: String = "res://assets/art/svg/icons/glyph_menu_open.svg"
const TOKENS: StringName = &"HudTokens"
const WORD_FONT: StringName = &"PillWord"  ## 14 dp caps face with its tracking, in the theme.
const NUMBER_FONT: StringName = &"ItemCost"  ## The badge: 18 sp Chakra Petch, as a card's count.
const WORD: String = "BUILD"
const RING_DP: float = 4.0
const GLYPH_DP: float = 26.0
const BADGE_DP: float = 12.5  ## The badge's radius: 18 sp digits fit it.
const ARC_POINTS: int = 48
## One of the two accents (the theme's `AccentRenew`, `AccentFossil`) by the faction's index.
const ACCENTS: Array[StringName] = [&"AccentRenew", &"AccentFossil"]

@export var runner: MatchRunner
@export var feed: HudStateFeed
@export var safe_area: SafeAreaMargin  ## Its gap is the safe rect's (ADR 0025 section 2).

var progress: float = 0.0  ## The ring: the first-finishing head's share, 0 to 1.
var count: int = 0  ## The badge: the items in the player's queues.
var draws: int = 0  ## How many times it was drawn, for the tests.
var badge_font: Font = null  ## The face and size the badge's digits were last drawn with.
var badge_font_size: int = 0

var _glyph: Texture2D = null
var _seen: Vector2i = Vector2i(-1, -1)  ## Serial and tick of the snapshot last read.
var _faction: int = 0
var _dp: float = 1.0  ## Base px per dp, read by `place` (a resize): a frame asks `UiScale` nothing.


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	_glyph = load(ICON)
	pressed.connect(func() -> void: feed.state.open(HudState.Unfold.DRAWER))
	feed.state.changed.connect(_on_changed)
	get_viewport().size_changed.connect(place)
	place()
	_on_changed(HudState.Unfold.NONE)


func _process(_delta: float) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap != null and Vector2i(snap.match_serial, snap.tick) != _seen:
		_seen = Vector2i(snap.match_serial, snap.tick)
		refresh(snap)


## Takes the rect `HudCorners.place` gives BUILD (64 dp, the safe rect's bottom right corner).
func place() -> void:
	_dp = UiScale.dp(1.0)
	var margin_dp: float = SafeAreaMargin.DEFAULT_MARGIN_DP
	margin_dp = margin_dp if safe_area == null else safe_area.margin_dp
	var safe: Rect2 = SafeAreaMargin.rect_inside(get_viewport().get_visible_rect(), margin_dp)
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), UiScale.base_px_per_dp(), false, HudCorners.Shown.new()
	)
	position = rects[HudCorners.BUILD].position
	size = rects[HudCorners.BUILD].size
	queue_redraw()


## The ring and the badge from the snapshot's queues of the local player.
func refresh(snap: MatchSnapshot) -> void:
	var player: int = -1 if runner.scenario == null else runner.scenario.local_player
	var slots: int = BuildSidebar._queue_slots(snap)
	var items: int = 0
	var share: float = 0.0
	var least: int = 1 << 30
	for tab: int in World.TABS:
		var queue: int = player * World.TABS + tab
		var filled: int = BuildSidebar._entry(snap.queue_count, queue)
		items += filled
		if filled > 0:
			var type: int = snap.queue_type[queue * slots]
			var goal: int = maxi(snap.type_build_ticks[type], 1) * Production.PROGRESS_PER_TICK
			var done: int = BuildSidebar._entry(snap.queue_progress, queue)
			if goal - done < least:
				least = goal - done
				share = clampf(float(done) / goal, 0.0, 1.0)
	for row: int in snap.unit_id.size():
		if snap.owner[row] == player:
			var faction: int = clampi(
				snap.type_faction[snap.type_index[row]], 0, ACCENTS.size() - 1
			)
			if faction != _faction:
				_faction = faction
				queue_redraw()
			break
	if items != count or not is_equal_approx(share, progress):
		count = items
		progress = share
		queue_redraw()


func _on_changed(_previous: HudState.Unfold) -> void:
	visible = not (
		feed.state.is_open(HudState.Unfold.DRAWER) or feed.state.is_open(HudState.Unfold.PAUSE)
	)


func _draw() -> void:
	draws += 1
	var dp: float = _dp
	var middle: Vector2 = size * 0.5
	var ring: float = RING_DP * dp
	var outer: float = minf(size.x, size.y) * 0.5
	var accent: StringName = ACCENTS[_faction]
	draw_arc(
		middle, outer - ring * 0.5, 0.0, TAU, ARC_POINTS, get_theme_color(&"border", TOKENS), ring
	)
	if progress > 0.0:
		var to: float = -PI * 0.5 + TAU * progress
		draw_arc(
			middle,
			outer - ring * 0.5,
			-PI * 0.5,
			to,
			ARC_POINTS,
			get_theme_color(&"light", accent),
			ring
		)
	draw_circle(middle, outer - ring, get_theme_color(&"accent", accent))
	var side: float = GLYPH_DP * dp
	draw_texture_rect(
		_glyph,
		Rect2(Vector2(middle.x - side * 0.5, middle.y - side * 0.85), Vector2(side, side)),
		false
	)
	var font: Font = get_theme_font(&"font", WORD_FONT)
	var font_size: int = get_theme_font_size(&"font_size", WORD_FONT)
	var width: float = font.get_string_size(WORD, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(
		font,
		Vector2(middle.x - width * 0.5, middle.y + side * 0.85),
		WORD,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		get_theme_color(&"on_accent", accent)
	)
	if count > 0:
		var at: Vector2 = Vector2(size.x - BADGE_DP * dp, BADGE_DP * dp)
		draw_circle(at, BADGE_DP * dp, get_theme_color(&"text", TOKENS))
		badge_font = get_theme_font(&"font", NUMBER_FONT)  # One place: drawn and recorded.
		badge_font_size = get_theme_font_size(&"font_size", NUMBER_FONT)
		var text: String = str(count)
		var span: float = (
			badge_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, badge_font_size).x
		)
		draw_string(
			badge_font,
			at + Vector2(-span * 0.5, badge_font_size * 0.35),
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			badge_font_size,
			get_theme_color(&"on_accent", accent)
		)
