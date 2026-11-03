class_name HudLayout
extends RefCounted
## Where the battle-screen HUD keeps room for the build drawer (ADR 0015 section 5, ADR 0025
## sections 2 and 5, plan rows P85d and P120). The corner parts (the pill, the scope, BUILD) are
## `HudCorners`'. Landscape: the drawer is a side panel and takes no bottom zone; `right_zone_px`
## reserves BUILD's column at the bottom row's right end for the SelectionPanel's band. Portrait:
## `BuildSidebar` puts the zone in `bottom_zone_dp`: BUILD's row while the drawer is closed, the
## sheet's height while it is open, between the two while it slides; every HUD part reads it here
## and nowhere else, so the ArmyBar sits a gap above it. `menu_top_px` is the sheet's real top on
## the screen (ADR 0024 section 4), for whatever measures the screen: the edge pan's bottom band and
## the buttons of placement. `BuildSidebar` tells whoever lifts something by them in `zone_changed`.
## A scene without a sidebar leaves them at 0 and INF (the sidebar puts them back when it leaves).
## The orientation is the one rule of UiScale, applied to the window the UI scale is made for.

const STACK_SHARE: float = 0.4  ## The most the bottom stack takes of the portrait safe height.
## BUILD's row upright while the drawer is closed (BUILD 64 dp and a gap): the zone the ArmyBar
## stands above (ADR 0025 "Interim places"; P122b takes it back to 0).
const BUILD_ROW_DP: float = 72.0  # HudCorners.BUILD_DP + GAP_DP; pinned equal by a test.
## The portrait zone while the drawer is closed: BUILD's own height. Whatever stands above it adds
## its 8 dp gap, as it does above the open sheet.
const BUILD_ZONE_DP: float = 64.0  # HudCorners.BUILD_DP; pinned equal by a test.

## The portrait zone in dp (see the header); 0 in landscape and while no BuildSidebar is in the
## tree. Static state: a test that sets one puts it back in `after_test`, like the UiScale override.
static var bottom_zone_dp: float = 0.0
## The sheet's real top on the screen in base px while it shows (`BuildSidebar._apply_extent`); INF
## while it is closed, sideways, or no BuildSidebar is in the tree: nothing covers the map (read it
## through `map_bottom_px`). Static state like the zone: a test puts it back.
static var menu_top_px: float = INF
## The open side panel's width in dp (the safe part, `BuildSidebar` writes it), 0 while it is
## closed, upright, or no BuildSidebar is in the tree: `right_zone_px` reserves it for the row.
static var drawer_side_dp: float = 0.0


## The width of the first visible child of `row`, 0 for none: what the credits pill stands after at
## the top left, the Dev button, or in a release build, where it is hidden, the Surrender button.
static func first_visible_width(row: Control) -> float:
	if row != null:
		for child: Node in row.get_children():
			var control: Control = child as Control
			if control != null and control.visible:
				return control.get_combined_minimum_size().x
	return 0.0


## Whether the window is a portrait one (UiScale.is_portrait_size), for the metrics in force.
static func is_portrait() -> bool:
	return UiScale.is_portrait_size(UiScale.current().window_size)


## What the bottom row reserves at its right end in landscape, in base px: BUILD and a gap, or the
## open side panel and a gap, whichever is wider. (The row's `inner` width no longer matters.)
static func right_zone_px(_inner: float) -> float:
	return UiScale.dp(maxf(BUILD_ROW_DP, drawer_side_dp + HudCorners.GAP_DP))


## The portrait bottom zone's height in base px, at the bottom of the safe area's inner rect.
static func bottom_zone_px() -> float:
	return UiScale.dp(bottom_zone_dp)


## Where the map view ends at the bottom, in base px: the build menu's real top, or the bottom of
## `safe` where no menu covers the map.
static func map_bottom_px(safe: Rect2) -> float:
	return minf(menu_top_px, safe.end.y)
