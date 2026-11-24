class_name GuideDock
extends RefCounted
## Where the guide's open card stands (ADR 0048 section 1, plan row P584): one pure function of the
## rects `HudCorners.place` returns, so the dock is tested on crafted inputs at the six sizes and
## never searched per frame. Knows no node, no screen and no time. Rects are base px inside `safe`;
## every size below is in dp. Mirrored (left-handed) input is detected from the pill's side and the
## whole dock flips with it.
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
## drops under it) and the toast slot is kept in its place while it is not.
static func shown_for_dock(
	portrait: bool, map_open: bool, drawer: bool, groups: int, strike: bool
) -> HudCorners.Shown:
	var shown: HudCorners.Shown = HudCorners.Shown.new()
	shown.map = map_open or not portrait
	shown.toast = portrait and not map_open
	shown.drawer = drawer
	shown.groups = groups
	shown.strike = strike
	return shown


## The open card's largest rect in base px: under the top row, right of the group column, left of
## the full map and the open panel's handle, at most `card_max_width_dp` wide (centred in the room)
## and `card_max_height_pct` of the safe height high, and short of the sheet and the ad band.
## Empty (size zero) where no room is left.
static func place(
	safe: Rect2,
	portrait: bool,
	dp: float,
	hud_rects: Dictionary[StringName, Rect2],
	settings_values: Dictionary[StringName, float]
) -> Rect2:
	var pill: Rect2 = hud_rects.get(HudCorners.PILL, Rect2())
	var mirror: bool = pill.size.x > 0.0 and pill.get_center().x > safe.get_center().x
	var w: float = safe.size.x / dp
	var h: float = safe.size.y / dp
	var parts: Dictionary[StringName, Rect2] = {}  # dp from the safe top left, unmirrored.
	for key: StringName in hud_rects:
		parts[key] = _to_dp(hud_rects[key], safe, dp, mirror)
	var left: float = 0.0
	for key: StringName in parts:
		if str(key).begins_with("group_"):
			left = maxf(left, parts[key].end.x + GAP_DP)
	var top: float = HudCorners.SCOPE_DP + GAP_DP  # Landscape: under the scope.
	if portrait:  # The toast slot's foot, kept free whether or not a toast shows.
		top += HudCorners.TOAST_H_DP + GAP_DP
		if parts.has(HudCorners.MAP):  # Dropped under the open map.
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
		elif part.position.y < bottom and part.end.y > top:
			right = minf(right, part.position.x - GAP_DP)
	var room: float = right - left
	var height: float = bottom - top
	if room <= 0.0 or height <= 0.0:
		return Rect2()
	var width: float = minf(room, settings_values.get(MAX_WIDTH_KEY, DEFAULT_MAX_WIDTH_DP))
	var dock: Rect2 = Rect2(left + (room - width) * 0.5, top, width, height)
	return _to_px(dock, safe, dp, mirror)


## Where a hand with no anchor points: the middle of the open field under the dock, left of the
## open panel and above the sheet, the command bar and BUILD. Base px.
static func field_point(
	safe: Rect2, dock: Rect2, hud_rects: Dictionary[StringName, Rect2]
) -> Vector2:
	var left: float = safe.position.x
	var right: float = safe.end.x
	var bottom: float = safe.end.y
	var top: float = dock.end.y if dock.size.y > 0.0 else safe.position.y
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
	return Vector2((left + right) * 0.5, (top + maxf(bottom, top)) * 0.5)


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
