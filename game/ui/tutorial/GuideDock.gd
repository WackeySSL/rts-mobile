class_name GuideDock
extends RefCounted
## Where the guide's open card stands (ADR 0048 section 1, plan row P584): one pure function of the
## rects `HudCorners.place` returns, so the dock is tested on crafted inputs at the six sizes and
## never searched per frame. Knows no node, no screen and no time. Rects are base px inside `safe`;
## every size below is in dp. Mirrored (left-handed) input is flagged by the caller, and the whole
## dock flips with it.
## `settings_values` carries the `GuideSettingsDef` fields the dock reads (P585 builds the resource;
## the names are the plan's and ADR 0048's): `card_max_width_dp` (560) and `card_max_height_pct`
## (45). A key left out takes that default.

const GAP_DP: float = 8.0
const AD_GAP_DP: float = 16.0  ## From an ad band (ad policy).
const MAX_WIDTH_KEY: StringName = &"card_max_width_dp"
const MAX_HEIGHT_KEY: StringName = &"card_max_height_pct"
const DEFAULT_MAX_WIDTH_DP: float = 560.0
const DEFAULT_MAX_HEIGHT_PCT: float = 45.0
## An ad band's rect, when the caller has one (the pause menu): the dock ends 16 dp above it.
const AD_BAND: StringName = &"ad_band"
## The parts left of which a landscape dock must end when they stand in its rows.
const RIGHT_PARTS: Array[StringName] = [
	HudCorners.MAP,
	HudCorners.STRIKE_ROW,
	HudCorners.STRIKE,
	HudCorners.READY,
	HudCorners.BUILD,
	HudCorners.REVEAL,
	HudCorners.REVEAL_LINE,
]


## The `Shown` the dock reads. Landscape keeps the full map reserved whether or not it is open, so
## the card never moves with the radar; upright the map counts only while it is open (the dock then
## drops under it) and the toast slot is kept in its place while it is not. `ready`, `aim` and `bar`
## are the parts of the same names that show; `aim` implies the strike button.
static func shown_for_dock(
	portrait: bool,
	map_open: bool,
	drawer: bool,
	groups: int,
	strike: bool,
	ready: bool = false,
	aim: bool = false,
	bar: bool = false
) -> HudCorners.Shown:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.map = map_open or not portrait
	shown.toast = portrait and not map_open
	shown.drawer = drawer
	shown.groups = groups
	shown.strike = strike or aim
	shown.aim = aim
	shown.ready = ready
	shown.bar = bar
	return shown


## The rects the dock reads: `HudCorners.place` of `shown` (the map reserved), plus what that call
## leaves out while the map shows: the toast (the slot, or the fallback under the top line beside
## an open panel) and the enemy sweep's badge and warning line, taken from a second call with the
## map closed. The card never covers them (ADR 0048 section 1), so they are reserved, not exempt.
static func hud_for_dock(
	safe: Rect2, portrait: bool, dp: float, mirror: bool, shown: HudCorners.Shown
) -> Dictionary[StringName, Rect2]:
	var out: Dictionary[StringName, Rect2] = HudCorners.place(safe, portrait, dp, mirror, shown)
	var open: HudCorners.Shown = HudCorners.Shown.new()
	open.drawer = shown.drawer
	open.groups = shown.groups
	open.strike = shown.strike
	open.aim = shown.aim
	open.ready = shown.ready
	open.bar = shown.bar
	open.bar_width = shown.bar_width
	open.pill_width = shown.pill_width
	open.toast = true
	open.reveal = true
	open.reveal_line = true
	var extra: Dictionary[StringName, Rect2] = HudCorners.place(safe, portrait, dp, mirror, open)
	for key: StringName in [HudCorners.TOAST, HudCorners.REVEAL, HudCorners.REVEAL_LINE]:
		if extra.has(key) and not out.has(key):
			out[key] = extra[key]
	return out


## The open card's largest allowed rect in base px (P588 sizes the card to its content and
## top-aligns it): under the top row and the toast, right of the group column, left of the full map
## and the open panel's handle, at most `card_max_width_dp` wide (centred in the room) and
## `card_max_height_pct` of the safe height high, and short of the sheet, the command bar, the
## right column and the ad band. Empty (size zero) where no room is left. `hud_rects` come from
## `hud_for_dock`; `mirror` is the flag they were placed with.
static func place(
	safe: Rect2,
	portrait: bool,
	dp: float,
	mirror: bool,
	hud_rects: Dictionary[StringName, Rect2],
	settings_values: Dictionary[StringName, float]
) -> Rect2:
	var w: float = safe.size.x / dp
	var h: float = safe.size.y / dp
	var parts: Dictionary[StringName, Rect2] = {}  # dp from the safe top left, unmirrored.
	for key: StringName in hud_rects:
		parts[key] = _to_dp(hud_rects[key], safe, dp, mirror)
	var left: float = 0.0
	var index: int = 0
	while parts.has(HudCorners.group_key(index)):
		left = maxf(left, parts[HudCorners.group_key(index)].end.x + GAP_DP)
		index += 1
	var top: float = HudCorners.SCOPE_DP + GAP_DP  # Landscape: under the scope.
	if portrait:  # The toast slot's foot, kept free whether or not a toast shows.
		top += HudCorners.TOAST_H_DP + GAP_DP
	if parts.has(HudCorners.TOAST):  # The fallback toast under the top line too.
		top = maxf(top, parts[HudCorners.TOAST].end.y + GAP_DP)
	if portrait and parts.has(HudCorners.MAP):  # Dropped under the open map.
		top = maxf(top, parts[HudCorners.MAP].end.y + GAP_DP)
	var cap: float = h * settings_values.get(MAX_HEIGHT_KEY, DEFAULT_MAX_HEIGHT_PCT) / 100.0
	var bottom: float = minf(top + cap, h)
	if parts.has(AD_BAND):
		bottom = minf(bottom, parts[AD_BAND].position.y - AD_GAP_DP)
	var right: float = w
	if parts.has(HudCorners.DRAWER):
		var open: Rect2 = parts[HudCorners.DRAWER]
		if portrait:
			bottom = minf(bottom, open.position.y - GAP_DP)
		else:
			right = open.position.x - HudCorners.CLOSE_DP - GAP_DP
	for key: StringName in RIGHT_PARTS:
		var part: Rect2 = parts.get(key, Rect2())
		if part.size.x <= 0.0:
			continue
		if portrait:  # The right column below the dock: it ends a gap above its topmost part.
			if part.end.x > left and part.position.y >= top:
				bottom = minf(bottom, part.position.y - GAP_DP)
		elif part.position.y < bottom + GAP_DP and part.end.y > top:
			right = minf(right, part.position.x - GAP_DP)
	var bar: Rect2 = parts.get(HudCorners.BAR, Rect2())
	if bar.size.x > 0.0 and bar.end.x > left and bar.position.x < right and bar.position.y >= top:
		bottom = minf(bottom, bar.position.y - GAP_DP)
	var room: float = right - left
	var height: float = bottom - top
	if room <= 0.0 or height <= 0.0:
		return Rect2()
	var width: float = minf(room, settings_values.get(MAX_WIDTH_KEY, DEFAULT_MAX_WIDTH_DP))
	var dock: Rect2 = Rect2(left + (room - width) * 0.5, top, width, height)
	return _to_px(dock, safe, dp, mirror)


## Where a hand with no anchor points: the middle of the open field under the card's foot (`foot`,
## a y in base px; below zero it is the dock's own foot), left of the open panel and above the
## sheet, the command bar and BUILD, and clear of the group column, the strike button and its aim
## row, the Ready chip and the enemy sweep's badge and line. Base px.
static func field_point(
	safe: Rect2, dock: Rect2, hud_rects: Dictionary[StringName, Rect2], foot: float = -1.0
) -> Vector2:
	var left: float = safe.position.x
	var right: float = safe.end.x
	var bottom: float = safe.end.y
	var top: float = foot if foot >= 0.0 else dock.end.y if dock.size.y > 0.0 else safe.position.y
	for key: StringName in [HudCorners.BAR, HudCorners.BUILD]:
		if hud_rects.has(key):
			bottom = minf(bottom, hud_rects[key].position.y)
	if hud_rects.has(HudCorners.DRAWER):
		var open: Rect2 = hud_rects[HudCorners.DRAWER]
		if open.size.x >= safe.size.x - 1.0:  # The sheet spans the width.
			bottom = minf(bottom, open.position.y)
		elif open.get_center().x > safe.get_center().x:
			right = open.position.x
		else:
			left = open.end.x
	bottom = maxf(bottom, top)
	var keys: Array[StringName] = [
		HudCorners.READY,
		HudCorners.STRIKE,
		HudCorners.STRIKE_ROW,
		HudCorners.REVEAL,
		HudCorners.REVEAL_LINE
	]
	var index: int = 0
	while hud_rects.has(HudCorners.group_key(index)):
		keys.append(HudCorners.group_key(index))
		index += 1
	for key: StringName in keys:
		var part: Rect2 = hud_rects.get(key, Rect2())
		if part.size.x <= 0.0 or part.position.y >= bottom or part.end.y <= top:
			continue
		if part.get_center().x > safe.get_center().x:
			right = minf(right, part.position.x)
		else:
			left = maxf(left, part.end.x)
	return Vector2((left + right) * 0.5, (top + bottom) * 0.5)


static func _to_dp(rect: Rect2, safe: Rect2, dp: float, mirror: bool) -> Rect2:
	var r: Rect2 = Rect2((rect.position - safe.position) / dp, rect.size / dp)
	if mirror:
		r.position.x = safe.size.x / dp - r.position.x - r.size.x
	return r


static func _to_px(rect: Rect2, safe: Rect2, dp: float, mirror: bool) -> Rect2:
	var r: Rect2 = rect
	if mirror:
		r.position.x = safe.size.x / dp - r.position.x - r.size.x
	return Rect2(safe.position + r.position * dp, r.size * dp)
