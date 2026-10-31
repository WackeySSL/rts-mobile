class_name HudLayout
extends RefCounted
## Where the battle-screen HUD keeps room for the build menu (ADR 0015 section 5, ADR 0023 section
## 12, plan rows P85 and P85d). Landscape: three floating panels over the map, the build panel at
## the bottom right (`panel_px` wide, the bottom row's right end, which `right_zone_px` reserves
## for the SelectionPanel's band), the minimap's slot at the top right (`SLOT_DP`) and the status
## pill at the top left after the Dev button (`PILL_DP`). Portrait: the sidebar's bottom band,
## whose height `BuildSidebar` puts in `bottom_zone_dp` (`band_dp`) from `_ready` and on every
## resize, with the minimap at its right end (`minimap_box_px`); every HUD part reads it here and
## nowhere else, so the ArmyBar sits a gap above the band. `menu_top_px` is the menu's real top on
## the screen (ADR 0024 section 4), for whatever measures the screen: the edge pan's bottom band
## and the buttons of placement.
## Both follow the menu's state (ADR 0024 section 4): the open band's or the strip's, or between
## the two while it slides (`BuildSidebar` tells whoever lifts something by it in `zone_changed`).
## A scene without a sidebar leaves it at 0 (the sidebar puts it back when it leaves the tree).
## The orientation is the one rule of UiScale, applied to the window the UI scale is made for.

## The landscape build panel takes what the bottom row leaves the ArmyBar and the SelectionPanel's
## one row (`SELECTION_DP`): the canvas's 372 dp at most, two whole cards (2 x 80 dp, an 8 dp gap
## and 8 dp padding each side) at least. The SelectionPanel never grows past what is left of the
## row, whatever its names and counts: it clips the names (`SelectionPanel._fit_zone`).
const SELECTION_DP: float = 200.0
const PANEL_MIN_DP: float = 184.0
const PANEL_MAX_DP: float = 372.0
const PANEL_GAP_DP: float = 8.0  ## Between the build panel and the SelectionPanel's band.
const PILL_DP: float = 240.0  ## The landscape status pill's least width (its height is 48 dp).
const PILL_HEIGHT_DP: float = 48.0
const SLOT_DP: Vector2 = Vector2(148.0, 86.0)  ## The minimap's panel at the top right (2:1 box).
const MINIMAP_SHARE: float = 0.4  ## The most of the band's body row the portrait minimap takes.
const BAND_SHARE: float = 0.2  ## The portrait band's share of the safe height.
const BAND_MIN_DP: float = 200.0  ## The least the portrait band takes of it, in dp.
const STACK_SHARE: float = 0.4  ## The most the band and the ArmyBar line take of the safe height.
## The least the band gives way to: the status line 32, the tabs 48 and the item row 64 with two
## 8 dp gaps and 4 dp margins is 168 dp, and 4 dp more cover the gaps' rounding to whole px.
const BAND_FLOOR_DP: float = 172.0
## The collapsed menu (ADR 0024 section 2 and 3, Michael's R2): the portrait strip on the safe
## bottom edge, whose height lives here and nowhere else, and the landscape plate at the bottom
## right. The strip holds the status line (32 dp), a gap (8 dp) and the button row (48 dp) between
## the backdrop's 4 dp above and below; the plate is the button row between the same 4 dp.
const STRIP_DP: float = 96.0
const PLATE_DP: float = 56.0

## The portrait menu's height in dp (the band's while open, `STRIP_DP` while collapsed, between the
## two while it slides); 0 in landscape and while no BuildSidebar is in the tree. Static state: a
## test that sets one puts it back in `after_test`, like the UiScale override.
static var bottom_zone_dp: float = 0.0
## The build menu's real top on the screen in base px: the y of the portrait band's or strip's rect,
## which `BuildSidebar` writes (when it lays out and each frame of a slide), and the safe rect's
## bottom in landscape, where the panel floats. The band's bottom is not the safe rect's bottom
## (`SafeAreaMargin` adds a margin and gives both ends of an axis the larger inset), so with a top
## cutout the band sits higher than `safe.end.y - bottom_zone_dp` says. INF while no BuildSidebar is
## in the tree: nothing covers the map (read it through `map_bottom_px`). Static state like the
## zone: a test puts it back.
static var menu_top_px: float = INF


## Whether the window is a portrait one (UiScale.is_portrait_size), for the metrics in force.
static func is_portrait() -> bool:
	return UiScale.is_portrait_size(UiScale.current().window_size)


## The landscape build panel's width in base px for a safe area whose inner rect is `inner` base px
## wide: what is left of the bottom row after the ArmyBar, the SelectionPanel's row and the gaps.
static func panel_px(inner: float) -> float:
	var army_dp: float = (
		ArmyBar.ALL_ARMY_DP.x + SelectionModel.GROUP_COUNT * (ArmyBar.GROUP_DP.x + ArmyBar.GAP_DP)
	)
	var taken_dp: float = army_dp + ArmyBar.GAP_DP + SELECTION_DP + PANEL_GAP_DP
	return clampf(inner - UiScale.dp(taken_dp), UiScale.dp(PANEL_MIN_DP), UiScale.dp(PANEL_MAX_DP))


## What the bottom row reserves at its right end in landscape: the build panel and a gap.
static func right_zone_px(inner: float) -> float:
	return panel_px(inner) + UiScale.dp(PANEL_GAP_DP)


## The portrait bottom zone's height in base px, at the bottom of the safe area's inner rect.
static func bottom_zone_px() -> float:
	return UiScale.dp(bottom_zone_dp)


## Where the map view ends at the bottom, in base px: the build menu's real top, or the bottom of
## `safe` where no menu covers the map.
static func map_bottom_px(safe: Rect2) -> float:
	return minf(menu_top_px, safe.end.y)


## The portrait band's height in dp for a safe rect `safe_dp` dp tall: 20% of it and at least
## 200 dp, but no more than what keeps the band and the ArmyBar line (`reserved_dp`: the edge
## margin, the gap and the bar) within 40% of the safe height. The band gives way first, down to
## what its contents need (ADR 0015 section 5: never the ArmyBar, a 48 dp target or a 64 dp icon).
static func band_dp(safe_dp: float, reserved_dp: float) -> float:
	var wanted: float = maxf(safe_dp * BAND_SHARE, BAND_MIN_DP)
	return maxf(minf(wanted, safe_dp * STACK_SHARE - reserved_dp), BAND_FLOOR_DP)


## The portrait minimap's 2:1 box in base px (ADR 0015 section 5, ADR 0023 section 4): at most
## `MINIMAP_SHARE` of `row`, the width the band's body row gives it and the column beside it, which
## is itself less than the safe inner width, and no higher than `room`, the height the band leaves
## beside its tabs and item row.
static func minimap_box_px(row: float, room: float) -> Vector2:
	var width: float = minf(row * MINIMAP_SHARE, room * 2.0)
	return Vector2(width, width / 2.0)
