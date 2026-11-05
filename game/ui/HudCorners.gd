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
## folds too (P120d: the drawer's head shows the economy, so it is on screen once).
## The economy card and the full map are one unfold at a time (ADR 0025 section 1), and the card
## and the strike aim's row are not shown together either; a pinned full map does stay open
## through the aim (`_map` keeps it clear of the row and the pill). The card is a transient overlay
## (any next touch closes it): it may cover the toast, the group column and, on the short landscape
## screens, the command bar (its tallest content is about 220 dp, the room under the pill on the
## 800 x 304 dp screen is 224 dp).

const GAP_DP: float = 8.0
const PILL_DP: Vector2 = Vector2(200.0, 48.0)  ## The pill's least width and its height.
## 320 before the menu button (P124), which takes 52 dp of the pill (48 and its divider).
const PILL_MAX_DP: float = 372.0
const SCOPE_DP: float = 56.0
const BUILD_DP: float = 64.0
const READY_DP: Vector2 = Vector2(112.0, 48.0)
const BAR_DP: Vector2 = Vector2(120.0, 64.0)  ## Least width (Deselect and a chip) and height.
const GROUP_DP: float = 56.0
## Upright during the strike aim the column holds this many items in one column (the rest scroll),
## so it never meets the aim's check mark and X (lead decision, P122b).
const AIM_GROUPS: int = 3
const TOAST_H_DP: float = 48.0
const TOAST_W_DP: Vector2 = Vector2(280.0, 360.0)  ## At most, landscape then portrait.
## Least landscape width beside the pill: glyph 24, gap 6, padding and a title of about 14 letters
## ("UNITS UNDER ATTACK"); longer names are trimmed. Below it the toast stands under the top line.
const TOAST_LEAST_DP: float = 200.0
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
	# The pill stays in its corner while the drawer is open (Michael, 2026-11-05): sideways it ends a
	# gap short of the panel, upright the sheet is below it.
	var edge: float = w - SCOPE_DP  # The pill ends a gap short.
	if side:
		edge = open.position.x
	var room: float = minf(PILL_MAX_DP, edge - GAP_DP)
	var pill_w: float = minf(maxf(shown.pill_width, PILL_DP.x), room)
	out[PILL] = Rect2(0.0, 0.0, pill_w, PILL_DP.y)
	if shown.card and not shown.drawer:
		out[CARD] = Rect2(0.0, PILL_DP.y + GAP_DP, minf(CARD_W_DP, w), shown.card_height)
	if bar_on:
		out[BAR] = _bar(w, h, portrait, shown, open, side)
	var column_end: float = 0.0  # Where the group column ends (0 for none), for the toast.
	if not sheet:
		# Upright, the column leaves BUILD (and the Ready chip) their width: that many columns.
		var columns: int = 1 << 20
		if portrait:
			var right: float = BUILD_DP + GAP_DP + (READY_DP.x + GAP_DP if shown.ready else 0.0)
			columns = maxi(floori((w - right) / (GROUP_DP + GAP_DP)), 1)
		var held: int = _groups(out, h, portrait, shown, bar_on, columns)
		for index: int in held:
			column_end = maxf(column_end, out[group_key(index)].end.x)
	if shown.map and not shown.drawer:
		var row: Rect2 = out.get(STRIKE_ROW, Rect2())
		_map(out, w, portrait, strike if shown.strike else build, row, column_end)
	if shown.toast and not shown.map:
		out[TOAST] = _toast(w, portrait, out, open if side else Rect2(w, 0.0, 0.0, 0.0), column_end)
	var result: Dictionary[StringName, Rect2] = {}
	for key: StringName in out:
		var r: Rect2 = out[key]
		var x: float = w - r.position.x - r.size.x if mirror else r.position.x
		result[key] = Rect2(safe.position + Vector2(x, r.position.y) * dp, r.size * dp)
	return result


## The open drawer: the landscape panel at the right edge (40 % of the width, 312 to 420 dp), the
## portrait sheet at the bottom (half the height, at least the tabs and a row of cards).
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
## dp, the pill's line 48); landscape, centred between the pill (or the safe edge) and the scope (or
## the open panel). Where that room is under `TOAST_LEAST_DP` (a wide pill beside the open panel on
## a narrow phone) the toast stands under the top line instead, as the portrait rule has it: from
## the start (right of the group column, which starts on that line), a gap under the scope's foot,
## no further right than the open panel or the safe edge. The pill stays in its corner with the
## drawer open, so the room is that of the closed drawer, up to the panel.
static func _toast(
	w: float, portrait: bool, placed: Dictionary[StringName, Rect2], open: Rect2, column_end: float
) -> Rect2:
	if portrait:
		var top: float = SCOPE_DP + GAP_DP
		return Rect2(0.0, top, minf(w, TOAST_W_DP.y), TOAST_H_DP)
	var left: float = 0.0
	if placed.has(PILL):
		left = placed[PILL].end.x + GAP_DP
	var edge: float = (open.position.x if open.size.x > 0.0 else w) - GAP_DP
	var right: float = edge if open.size.x > 0.0 else w - SCOPE_DP - GAP_DP
	if right - left < TOAST_LEAST_DP:
		var start: float = column_end + GAP_DP if column_end > 0.0 else 0.0
		var top: float = SCOPE_DP + GAP_DP
		return Rect2(start, top, maxf(minf(TOAST_W_DP.x, edge - start), 0.0), TOAST_H_DP)
	var width: float = minf(TOAST_W_DP.x, right - left)
	return Rect2(left + (right - left - width) * 0.5, 0.0, width, TOAST_H_DP)


## The full map: under the scope, right-aligned, when the room down to the right column's next part
## holds the head and a box 96 dp high at least; else left of the column, from the safe top.
## Left of the column, while the strike aim's row (`row`, empty when it does not show) stands in
## its way, the map ends a gap left of the row and narrows (the box stays 2:1, 192 dp wide at the
## least) to start a gap right of the pill and of the group column (`column_end`, 0 for none), the
## larger of the two: the pinned map and the aim meet only here.
static func _map(
	out: Dictionary[StringName, Rect2],
	w: float,
	portrait: bool,
	next: Rect2,
	row: Rect2,
	column_end: float
) -> void:
	var cap: Vector2 = MAP_BOX_PORTRAIT_DP if portrait else MAP_BOX_DP
	var top: float = SCOPE_DP + GAP_DP
	var box_h: float = minf(cap.y, next.position.y - GAP_DP - top - MAP_HEAD_DP)
	var box: Rect2
	if box_h >= MAP_BOX_LEAST_H_DP:
		box = Rect2(w - 2.0 * box_h, top + MAP_HEAD_DP, 2.0 * box_h, box_h)
	else:
		var right: float = w - StrikeButton.SIZE_DP - GAP_DP
		var width: float = cap.x
		if row.size.x > 0.0 and row.position.y < MAP_HEAD_DP + cap.y + GAP_DP:
			right = row.position.x - GAP_DP
			var from: float = out[PILL].end.x + GAP_DP if out.has(PILL) else 0.0
			from = maxf(from, column_end + GAP_DP if column_end > 0.0 else 0.0)
			width = clampf(right - from, 2.0 * MAP_BOX_LEAST_H_DP, cap.x)
		box = Rect2(right - width, MAP_HEAD_DP, width, width * cap.y / cap.x)
	out[MAP_HEAD] = Rect2(box.position.x, box.position.y - MAP_HEAD_DP, box.size.x, MAP_HEAD_DP)
	out[MAP_BOX] = box
	out[MAP] = out[MAP_HEAD].merge(box)


## The group column at the left edge: 56 dp buttons, as many to a column as the room holds, more
## columns to the right. Landscape: from below the pill down to the bar (or the safe bottom), from
## the top. Portrait: above the bar, up to the 40 % line (ADR 0015 section 5), against the bottom;
## a column taller than that line only where more columns would stand in BUILD's way (a cutout on a
## short phone), which the ADR's 360 x 700 dp numbers never reach.
static func _groups(
	out: Dictionary[StringName, Rect2],
	h: float,
	portrait: bool,
	shown: Shown,
	bar_on: bool,
	columns: int
) -> int:
	var bottom: float = h - (BAR_DP.y + GAP_DP if bar_on else 0.0)
	var top: float = h - floorf(HudLayout.STACK_SHARE * h)
	if not portrait:
		top = minf(PILL_DP.y + GAP_DP, bottom - GROUP_DP)
	var step: float = GROUP_DP + GAP_DP
	var fit: int = floori((bottom - top + GAP_DP) / step)
	var count: int = shown.groups
	if portrait and shown.aim:  # One column of three at most; the rest scroll (the node's part).
		columns = 1
		count = mini(count, maxi(mini(AIM_GROUPS, fit), 1))
	var per: int = maxi(fit, ceili(float(count) / columns))
	for index: int in count:
		var column: int = index / per
		var row: int = index % per
		var rows: int = mini(per, count - column * per)  # A portrait column rests on the bottom.
		var y: float = bottom - rows * step + GAP_DP + row * step if portrait else top + row * step
		out[group_key(index)] = Rect2(column * step, y, GROUP_DP, GROUP_DP)
	return count
