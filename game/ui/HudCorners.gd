class_name HudCorners
extends RefCounted
## Where every part of the corner HUD stands (ADR 0025 sections 2 and 14, plan row P119): one pure
## function of the safe rect, the orientation, the dp, the mirror flag and what shows, so the six
## sizes, the short screens and the turn are tested on crafted inputs, and a row that adds a part
## sets one `Shown` entry and reads one rect. `place` knows no node, no screen and no time.
## The frame is the safe rect's own: every size is in dp, the rect it returns is in base px, inside
## `safe`. Mirrored, every rect is flipped about the safe rect's middle (left-handed mode, Phase 5).
## Drawer open: the landscape panel covers the right column (BUILD, the Ready chip, the strike
## button, the scope), the portrait sheet covers the bottom stack and the scope stays; the pill
## goes too, unless `Shown.pill_over_drawer` keeps it (P120, until P120d).
## The economy card, the full map and the strike aim's row are one unfold or mode
## at a time (ADR 0025 section 1), so a set that holds more than one of them is not a screen the
## HUD shows. The card is a transient overlay (any next touch closes it): it may cover the toast,
## the group column and, on the short landscape screens, the command bar (its tallest content is
## about 220 dp, the room under the pill on the 800 x 304 dp screen is 224 dp).

const GAP_DP: float = 8.0
const PILL_DP: Vector2 = Vector2(200.0, 48.0)  ## The pill's least width and its height.
const PILL_MAX_DP: float = 320.0
const SCOPE_DP: float = 56.0
const BUILD_DP: float = 64.0
const READY_DP: Vector2 = Vector2(112.0, 48.0)
const BAR_DP: Vector2 = Vector2(120.0, 64.0)  ## Least width (Deselect and a chip) and height.
const GROUP_DP: float = 56.0
const TOAST_H_DP: float = 48.0
const TOAST_W_DP: Vector2 = Vector2(280.0, 360.0)  ## At most, landscape then portrait.
const MAP_HEAD_DP: float = 48.0
const MAP_BOX_LEAST_H_DP: float = 96.0
const MAP_BOX_DP: Vector2 = Vector2(240.0, 120.0)  ## At most; portrait 260 x 130.
const MAP_BOX_PORTRAIT_DP: Vector2 = Vector2(260.0, 130.0)
const CARD_W_DP: float = 280.0
const DRAWER_DP: Vector2 = Vector2(312.0, 420.0)  ## The landscape panel's width, least and most.
const DRAWER_SHARE: float = 0.4
const SHEET_SHARE: float = 0.5
const SHEET_LEAST_DP: float = 312.0

const PILL: StringName = &"pill"
const SCOPE: StringName = &"scope"
const TOAST: StringName = &"toast"
const BUILD: StringName = &"build"
const READY: StringName = &"ready"
const STRIKE: StringName = &"strike"
const STRIKE_ROW: StringName = &"strike_row"  ## The check mark and the X, left of STRIKE.
const BAR: StringName = &"bar"
const MAP: StringName = &"map"  ## The head and the box.
const MAP_HEAD: StringName = &"map_head"
const MAP_BOX: StringName = &"map_box"
const CARD: StringName = &"card"
const DRAWER: StringName = &"drawer"


## What shows and how wide the parts that size themselves are (dp). A part left out is not in the
## result. Defaults: nothing optional shows, the group column holds "All army" only.
class Shown:
	extends RefCounted

	var left_taken: float = 0.0  ## Width of what stands at the top left already (the Dev button).
	var pill_width: float = 0.0  ## The pill's content width; 0 is its least.
	var bar: bool = false  ## The command bar (a selection, or the slot a mode keeps).
	var bar_width: float = 0.0  ## Landscape content width; 0 is the least.
	var ready: bool = false  ## The Ready chip (until ADR 0026's UI row).
	var strike: bool = false  ## The strike button.
	var aim: bool = false  ## The strike aim's check mark and X.
	var map: bool = false  ## The full map under the scope.
	var toast: bool = false
	var card: bool = false  ## The economy card.
	var card_height: float = 120.0
	var drawer: bool = false
	## The pill stays while the drawer is open (until P120d puts the economy in the drawer's head).
	var pill_over_drawer: bool = false
	var groups: int = 1  ## Buttons in the group column: "All army", saved groups, "+".


## The result's key of group button `index`, 0 on top ("All army").
static func group_key(index: int) -> StringName:
	return StringName("group_%d" % index)


## The rect of every part that shows, in base px inside `safe`; `dp` is base px per dp.
static func place(
	safe: Rect2, portrait: bool, dp: float, mirror: bool, shown: Shown
) -> Dictionary[StringName, Rect2]:
	var w: float = safe.size.x / dp
	var h: float = safe.size.y / dp
	var out: Dictionary[StringName, Rect2] = {}  # In dp from the safe rect's top left, unmirrored.
	var open: Rect2 = _drawer(w, h, portrait) if shown.drawer else Rect2()
	var side: bool = shown.drawer and not portrait
	var sheet: bool = shown.drawer and portrait
	var bar_on: bool = shown.bar and not sheet
	var lift: float = BAR_DP.y + GAP_DP if portrait and bar_on else 0.0
	# The right column, from the bottom up: BUILD (lifted over the portrait bar), the strike button.
	var build: Rect2 = Rect2(w - BUILD_DP, h - lift - BUILD_DP, BUILD_DP, BUILD_DP)
	var strike: Rect2 = Rect2(
		w - StrikeButton.SIZE_DP,
		build.position.y - GAP_DP - StrikeButton.SIZE_DP,
		StrikeButton.SIZE_DP,
		StrikeButton.SIZE_DP
	)
	if shown.drawer:
		out[DRAWER] = open
	else:
		out[BUILD] = build
		if shown.ready:
			out[READY] = Rect2(
				build.position.x - GAP_DP - READY_DP.x,
				build.position.y + (BUILD_DP - READY_DP.y) * 0.5,
				READY_DP.x,
				READY_DP.y
			)
		if shown.strike:
			out[STRIKE] = strike
			if shown.aim:
				var action: float = StrikeControls.ACTION_DP
				var row: Vector2 = Vector2(2.0 * action + StrikeControls.GAP_DP, action)
				out[STRIKE_ROW] = Rect2(
					strike.position.x - GAP_DP - row.x,
					strike.position.y + (StrikeButton.SIZE_DP - row.y) * 0.5,
					row.x,
					row.y
				)
	if not side:
		out[SCOPE] = Rect2(w - SCOPE_DP, 0.0, SCOPE_DP, SCOPE_DP)
	var pill_x: float = shown.left_taken + (GAP_DP if shown.left_taken > 0.0 else 0.0)
	if not shown.drawer or shown.pill_over_drawer:
		var edge: float = open.position.x if side else w - SCOPE_DP  # The pill ends a gap short.
		var room: float = minf(PILL_MAX_DP, edge - GAP_DP - pill_x)
		var pill_w: float = minf(maxf(shown.pill_width, PILL_DP.x), room)
		out[PILL] = Rect2(pill_x, 0.0, pill_w, PILL_DP.y)
		if shown.card:
			out[CARD] = Rect2(
				pill_x, PILL_DP.y + GAP_DP, minf(CARD_W_DP, w - pill_x), shown.card_height
			)
	if bar_on:
		out[BAR] = _bar(w, h, portrait, shown, open, side)
	if shown.toast and not shown.map:
		out[TOAST] = _toast(w, portrait, out, open if side else Rect2(w, 0.0, 0.0, 0.0))
	if shown.map and not shown.drawer:
		_map(out, w, portrait, strike if shown.strike else build)
	if not sheet:
		# Upright, the column leaves BUILD (and the Ready chip) their width: that many columns.
		var columns: int = 1 << 20
		if portrait:
			var right: float = BUILD_DP + GAP_DP + (READY_DP.x + GAP_DP if shown.ready else 0.0)
			columns = maxi(floori((w - right) / (GROUP_DP + GAP_DP)), 1)
		_groups(out, h, portrait, shown.groups, bar_on, columns)
	var result: Dictionary[StringName, Rect2] = {}
	for key: StringName in out:
		var r: Rect2 = out[key]
		var x: float = w - r.position.x - r.size.x if mirror else r.position.x
		result[key] = Rect2(safe.position + Vector2(x, r.position.y) * dp, r.size * dp)
	return result


## The open drawer: the landscape panel at the right edge (40 % of the width, 312 to 420 dp), the
## portrait sheet at the bottom (half the height, at least the head, tabs, a row and the queue).
static func _drawer(w: float, h: float, portrait: bool) -> Rect2:
	if portrait:
		var height: float = minf(maxf(h * SHEET_SHARE, SHEET_LEAST_DP), h)
		return Rect2(0.0, h - height, w, height)
	var width: float = minf(clampf(w * DRAWER_SHARE, DRAWER_DP.x, DRAWER_DP.y), w)
	return Rect2(w - width, 0.0, width, h)


## The command bar: bottom left, as wide as its content and no wider than the room beside BUILD
## (and the Ready chip) or the open panel; the portrait bar is the full width.
static func _bar(
	w: float, h: float, portrait: bool, shown: Shown, open: Rect2, side: bool
) -> Rect2:
	if portrait:
		return Rect2(0.0, h - BAR_DP.y, w, BAR_DP.y)
	var taken: float = BUILD_DP + GAP_DP
	taken += READY_DP.x + GAP_DP if shown.ready else 0.0
	var room: float = w - (open.size.x + GAP_DP if side else taken)
	return Rect2(0.0, h - BAR_DP.y, minf(maxf(shown.bar_width, BAR_DP.x), room), BAR_DP.y)


## The toast: portrait, under the pill at the start, a gap under the scope's foot (the scope is 56
## dp, the pill's line 48); landscape, centred between the pill (or the safe edge) and the scope
## (or the open panel).
static func _toast(
	w: float, portrait: bool, placed: Dictionary[StringName, Rect2], open: Rect2
) -> Rect2:
	if portrait:
		return Rect2(0.0, SCOPE_DP + GAP_DP, minf(w, TOAST_W_DP.y), TOAST_H_DP)
	var left: float = 0.0
	if placed.has(PILL):
		left = placed[PILL].end.x + GAP_DP
	var right: float = (open.position.x if open.size.x > 0.0 else w - SCOPE_DP) - GAP_DP
	var width: float = minf(TOAST_W_DP.x, right - left)
	return Rect2(left + (right - left - width) * 0.5, 0.0, width, TOAST_H_DP)


## The full map: under the scope, right-aligned, when the room down to the right column's next part
## holds the head and a box 96 dp high at least; else left of the column, from the safe top.
static func _map(out: Dictionary[StringName, Rect2], w: float, portrait: bool, next: Rect2) -> void:
	var cap: Vector2 = MAP_BOX_PORTRAIT_DP if portrait else MAP_BOX_DP
	var top: float = SCOPE_DP + GAP_DP
	var box_h: float = minf(cap.y, next.position.y - GAP_DP - top - MAP_HEAD_DP)
	var box: Rect2
	if box_h >= MAP_BOX_LEAST_H_DP:
		box = Rect2(w - 2.0 * box_h, top + MAP_HEAD_DP, 2.0 * box_h, box_h)
	else:
		box = Rect2(w - StrikeButton.SIZE_DP - GAP_DP - cap.x, MAP_HEAD_DP, cap.x, cap.y)
	out[MAP_HEAD] = Rect2(box.position.x, box.position.y - MAP_HEAD_DP, box.size.x, MAP_HEAD_DP)
	out[MAP_BOX] = box
	out[MAP] = out[MAP_HEAD].merge(box)


## The group column at the left edge: 56 dp buttons, as many to a column as the room holds, more
## columns to the right. Landscape: from below the pill down to the bar (or the safe bottom), from
## the top. Portrait: above the bar, up to the 40 % line (ADR 0015 section 5), against the bottom;
## a column taller than that line only where more columns would stand in BUILD's way (a cutout
## on a short phone), which the ADR's 360 x 700 dp numbers never reach.
static func _groups(
	out: Dictionary[StringName, Rect2],
	h: float,
	portrait: bool,
	count: int,
	bar_on: bool,
	columns: int
) -> void:
	var bottom: float = h - (BAR_DP.y + GAP_DP if bar_on else 0.0)
	var top: float = h - floorf(HudLayout.STACK_SHARE * h) if portrait else PILL_DP.y + GAP_DP
	var step: float = GROUP_DP + GAP_DP
	var per: int = maxi(floori((bottom - top + GAP_DP) / step), ceili(float(count) / columns))
	for index: int in count:
		var column: int = index / per
		var row: int = index % per
		var rows: int = mini(per, count - column * per)  # A portrait column rests on the bottom.
		var y: float = bottom - rows * step + GAP_DP + row * step if portrait else top + row * step
		out[group_key(index)] = Rect2(column * step, y, GROUP_DP, GROUP_DP)
