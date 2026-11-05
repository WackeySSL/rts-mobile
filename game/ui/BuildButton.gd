class_name BuildButton
extends Button
## BUILD (ADR 0025 section 4, plan P120): the 64 dp round button at the bottom right that opens the
## build drawer (`HudState` DRAWER). The accent disc of the local player's faction carries the
## glyph `glyph_menu_open` over the word "BUILD"; a 4 dp ring round it fills clockwise from the top
## with the item that finishes first among the heads of the player's queues (the least work left),
## and a white disc at the top right counts the items in all the queues (hidden at 0). It reads the
## published snapshot only, redraws when the ring or the count changes (a tick, never per frame at
## rest) and sends nothing. It hides while the drawer or the pause menu is open, and takes the rect
## `HudCorners.place` gives BUILD on `_ready` and on every resize.
## Stalled (P120c, ADR 0025 section 4): when the heads of the queues did not advance between the
## last two published snapshots while some queue is not empty, the ring turns grey and stops and a
## "!" badge shows at the top left. A queue head that is a finished structure waiting to be placed
## is not stalled (the Ready chip shows it). Low power is no exception and none is needed: every
## head with a producer still gains its share per tick, so it advances; a producer blacked out or
## destroyed on low power is a stall like any other.
## The comparison keeps two integers per queue, made once; the button redraws when `stalled`
## changes, as for the ring and the count.
## The Ready chip (until ADR 0026's P130): a child button left of BUILD (sideways; upright above
## the strike button or BUILD), at the rect `HudCorners`
## gives READY, with the finished structure's card and "Ready"; a tap opens the drawer on the
## Structures tab with that card in view (`BuildSidebar.show_ready`). It hides with BUILD.

signal reserved_changed  ## The room the chip takes beside BUILD changed (`HudLayout.chip_zone_dp`).
signal ready_changed  ## The chip showed or went (`ready_type` crossed -1).

const ICON: String = "res://assets/art/svg/icons/glyph_menu_open.svg"
const TOKENS: StringName = &"HudTokens"
const WORD_FONT: StringName = &"PillWord"  ## 14 dp caps face with its tracking, in the theme.
const NUMBER_FONT: StringName = &"ItemCost"  ## The badge: 18 sp Chakra Petch, as a card's count.
const WORD: String = "BUILD"
const RING_DP: float = 4.0
const GLYPH_DP: float = 26.0
const BADGE_DP: float = 12.5  ## The badge's radius: 18 sp digits fit it.
const ARC_POINTS: int = 48
const STALLED: StringName = &"BuildButton"  ## The theme type that holds the stalled ring's grey.
const CHIP_ICON_DP: float = 28.0
const MARK: String = "!"
## The theme's accent of each side, by faction id (`type_faction` is an index into `faction_ids`,
## in order of first appearance, so the id is the key, as PauseMenu's SIDES are).
const ACCENTS: Dictionary[StringName, StringName] = {
	&"renew": &"AccentRenew", &"fossil": &"AccentFossil"
}
## The side drawn before a snapshot names one, and when none of the player's rows does.
const FALLBACK_SIDE: StringName = &"renew"

@export var runner: MatchRunner
@export var feed: HudStateFeed
@export var safe_area: SafeAreaMargin  ## Its gap is the safe rect's (ADR 0025 section 2).
@export var sidebar: BuildSidebar  ## The Ready chip's tap opens it on the Structures tab.
## Upright the Ready chip stands above the strike button while one is owned (else above BUILD).
@export var strike_aim: StrikeAim

var progress: float = 0.0  ## The ring: the first-finishing head's share, 0 to 1.
var count: int = 0  ## The badge: the items in the player's queues.
var stalled: bool = false  ## No head advanced between the last two snapshots (grey ring, "!").
var ready_type: int = -1  ## The finished structure at the head of the Structures queue, else -1.
var disc_color: Color  ## The colour the disc was last drawn in (the side's accent).
var draws: int = 0  ## How many times it was drawn, for the tests.
var badge_font: Font = null  ## The face and size the badge's digits were last drawn with.
var badge_font_size: int = 0
var ring_color: Color  ## The colour the progress arc was last drawn in (when `ring_drawn`).
var ring_drawn: bool = false  ## The last draw had the progress arc.
var mark_drawn: bool = false  ## The last draw had the "!" disc.

var _glyph: Texture2D = null
var _chip_type: int = -1  ## The type whose card the chip shows.
var _compared: Vector2i = Vector2i(-1, -1)  ## Serial and tick of the snapshot last compared.
var _before_count: PackedInt32Array = PackedInt32Array([0, 0, 0])  ## By tab, at that snapshot:
var _before_done: PackedInt32Array = PackedInt32Array([0, 0, 0])  ## items and the head's progress.
var _seen: Vector2i = Vector2i(-1, -1)  ## Serial and tick of the snapshot last read.
var _side: StringName = FALLBACK_SIDE  ## The local player's faction id.
var _strike_owned: bool = false  ## The strike button showed when the chip was last placed.
var _chip_room: float = 0.0  ## dp from the safe right edge to the chip's left, and a gap.
var _dp: float = 1.0  ## Base px per dp, read by `place` (a resize): a frame asks `UiScale` nothing.
@onready var _chip: Button = $ReadyChip  ## In the scene, so that placement's buttons can clear it.


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	_glyph = load(ICON)
	pressed.connect(func() -> void: feed.state.open(HudState.Unfold.DRAWER))
	_chip.pressed.connect(func() -> void: sidebar.show_ready())
	feed.state.changed.connect(_on_changed)
	if strike_aim != null:
		strike_aim.changed.connect(_on_strike_changed)
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
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.ready = true  # The chip's rect; whether it shows is `ready_type`.
	_strike_owned = strike_aim != null and strike_aim.owned
	shown.strike = _strike_owned
	var rects: Dictionary[StringName, Rect2] = HudCorners.place(
		safe, HudLayout.is_portrait(), UiScale.base_px_per_dp(), false, shown
	)
	position = rects[HudCorners.BUILD].position
	size = rects[HudCorners.BUILD].size
	_chip.position = rects[HudCorners.READY].position - position
	_chip.size = rects[HudCorners.READY].size
	_chip.add_theme_constant_override("icon_max_width", roundi(CHIP_ICON_DP * _dp))
	_chip_room = (safe.end.x - rects[HudCorners.READY].position.x) / _dp + HudCorners.GAP_DP
	_reserve()
	queue_redraw()


## Writes the room the chip takes into `HudLayout.chip_zone_dp` (landscape, while it shows). The
## command bar reads `HudCorners` now; the static stays only for the tests that pin it.
func _reserve() -> void:
	var room: float = _chip_room if _chip.visible and not HudLayout.is_portrait() else 0.0
	if room != HudLayout.chip_zone_dp:
		HudLayout.chip_zone_dp = room
		reserved_changed.emit()


func _exit_tree() -> void:
	HudLayout.chip_zone_dp = 0.0


## The ring, the badge, the stalled look and the Ready chip from the snapshot's queues of the local
## player. The stalled look compares with the snapshot compared last, so a snapshot seen twice
## (a test's direct call and a frame) changes nothing.
func refresh(snap: MatchSnapshot) -> void:
	var player: int = -1 if runner.scenario == null else runner.scenario.local_player
	var slots: int = BuildSidebar._queue_slots(snap)
	var key: Vector2i = Vector2i(snap.match_serial, snap.tick)
	var compare: bool = key != _compared
	if compare and key.x != _compared.x:  # A new match: nothing to compare with yet.
		_before_count.fill(0)
		_before_done.fill(0)
	var items: int = 0
	var share: float = 0.0
	var least: int = 1 << 30
	var waiting: bool = false  ## Some queue is not empty and is not a structure waiting to be placed.
	var moved: bool = false  ## And some such head advanced (a new queue or a finished item counts).
	var finished: int = -1
	for tab: int in World.TABS:
		var queue: int = player * World.TABS + tab
		var filled: int = BuildSidebar._entry(snap.queue_count, queue)
		var done: int = 0
		items += filled
		if filled > 0:
			var type: int = snap.queue_type[queue * slots]
			var goal: int = maxi(snap.type_build_ticks[type], 1) * Production.PROGRESS_PER_TICK
			done = BuildSidebar._entry(snap.queue_progress, queue)
			if goal - done < least:
				least = goal - done
				share = clampf(float(done) / goal, 0.0, 1.0)
			if tab == World.Tab.STRUCTURES and done >= goal:
				finished = type
			else:
				waiting = true
				moved = moved or _before_count[tab] == 0 or filled < _before_count[tab]
				moved = moved or done > _before_done[tab]
		if compare:
			_before_count[tab] = filled
			_before_done[tab] = done
	_compared = key
	var side: StringName = FALLBACK_SIDE
	for row: int in snap.unit_id.size():
		if snap.owner[row] == player:
			var index: int = snap.type_faction[snap.type_index[row]]
			if index < 0 or index >= snap.faction_ids.size():
				continue  # A row without a faction is skipped, as BuildSidebar skips it.
			if ACCENTS.has(snap.faction_ids[index]):
				side = snap.faction_ids[index]
				break
	if side != _side:
		_side = side
		queue_redraw()
	var halted: bool = waiting and (stalled if not compare else not moved)
	if finished != ready_type:
		_show_ready(snap, finished)
	if halted != stalled or items != count or not is_equal_approx(share, progress):
		stalled = halted
		count = items
		progress = share
		queue_redraw()


## The chip for the finished structure `type` (-1: none): its card, and shown while there is one.
func _show_ready(snap: MatchSnapshot, type: int) -> void:
	var was: bool = ready_type >= 0
	ready_type = type
	_chip.visible = type >= 0
	_reserve()
	if was != (type >= 0):
		ready_changed.emit()
	if type >= 0 and type != _chip_type:
		_chip_type = type
		var art: String = CommandBar.ICON_ART % snap.type_ids[type]
		_chip.icon = load(art) if ResourceLoader.exists(art) else null


## The strike building was gained or lost (`StrikeAim.changed` also fires on every charge tick).
func _on_strike_changed() -> void:
	if strike_aim.owned != _strike_owned:
		place()


func _on_changed(_previous: HudState.Unfold) -> void:
	visible = not (
		feed.state.is_open(HudState.Unfold.DRAWER) or feed.state.is_open(HudState.Unfold.PAUSE)
	)


func _draw() -> void:
	draws += 1
	ring_drawn = false
	mark_drawn = false
	var dp: float = _dp
	var middle: Vector2 = size * 0.5
	var ring: float = RING_DP * dp
	var outer: float = minf(size.x, size.y) * 0.5
	var accent: StringName = ACCENTS[_side]
	draw_arc(
		middle, outer - ring * 0.5, 0.0, TAU, ARC_POINTS, get_theme_color(&"border", TOKENS), ring
	)
	if progress > 0.0:
		var to: float = -PI * 0.5 + TAU * progress
		ring_color = (
			get_theme_color(&"ring_stalled", STALLED)
			if stalled
			else get_theme_color(&"light", accent)
		)
		draw_arc(middle, outer - ring * 0.5, -PI * 0.5, to, ARC_POINTS, ring_color, ring)
		ring_drawn = true
	disc_color = get_theme_color(&"accent", accent)
	draw_circle(middle, outer - ring, disc_color)
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
	if stalled:  # A shape besides the grey: the "!" disc at the top left.
		mark_drawn = true
		var mark: Vector2 = Vector2(BADGE_DP * dp, BADGE_DP * dp)
		draw_circle(mark, BADGE_DP * dp, get_theme_color(&"danger", TOKENS))
		var face: Font = get_theme_font(&"font", NUMBER_FONT)
		var face_size: int = get_theme_font_size(&"font_size", NUMBER_FONT)
		var wide: float = face.get_string_size(MARK, HORIZONTAL_ALIGNMENT_LEFT, -1, face_size).x
		draw_string(
			face,
			mark + Vector2(-wide * 0.5, face_size * 0.35),
			MARK,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			face_size,
			get_theme_color(&"font_color", &"ReadyBadge")  # The dark type: about 6:1 on the red.
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
