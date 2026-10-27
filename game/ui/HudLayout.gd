class_name HudLayout
extends RefCounted
## Where the battle-screen HUD keeps room for the build menu (ADR 0015 section 5, ADR 0023 section
## 12, plan rows P85 and P85d). Landscape: three floating panels over the map, the build panel at
## the bottom right (`panel_px` wide, the bottom row's right end, which `right_zone_px` reserves
## for the SelectionPanel's band), the minimap's slot at the top right (`SLOT_DP`) and the status
## pill at the top left after the Dev button (`PILL_DP`). Portrait: the sidebar's bottom band,
## whose height `BuildSidebar` puts in `bottom_zone_dp` (`band_dp`) from `_ready` and on every
## resize; every HUD part reads it here and nowhere else, so the ArmyBar sits a gap above the band.
## A scene without a sidebar leaves it at 0 (the sidebar puts it back when it leaves the tree).
## The orientation is the one rule of UiScale, applied to the window the UI scale is made for.

## The landscape build panel takes what the bottom row leaves the ArmyBar and the SelectionPanel's
## one row (`SELECTION_DP`): the canvas's 372 dp at most, two whole cards (2 x 80 dp, an 8 dp gap
## and 8 dp padding each side) at least.
const SELECTION_DP: float = 200.0
const PANEL_MIN_DP: float = 184.0
const PANEL_MAX_DP: float = 372.0
const PANEL_GAP_DP: float = 8.0  ## Between the build panel and the SelectionPanel's band.
const PILL_DP: float = 240.0  ## The landscape status pill's least width (its height is 48 dp).
const PILL_HEIGHT_DP: float = 48.0
const SLOT_DP: Vector2 = Vector2(148.0, 86.0)  ## The minimap's panel at the top right (2:1 box).
const BAND_SHARE: float = 0.2  ## The portrait band's share of the safe height.
const BAND_MIN_DP: float = 200.0  ## The least the portrait band takes of it, in dp.
const STACK_SHARE: float = 0.4  ## The most the band and the ArmyBar line take of the safe height.
## The least the band gives way to: the status line 32, the tabs 48 and the item row 64 with two
## 8 dp gaps and 4 dp margins is 168 dp, and 4 dp more cover the gaps' rounding to whole px.
const BAND_FLOOR_DP: float = 172.0

## The portrait band's height in dp; 0 in landscape and while no BuildSidebar is in the tree. Static
## state: a test that sets one puts it back in `after_test`, like the UiScale override.
static var bottom_zone_dp: float = 0.0


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


## The portrait band's height in dp for a safe rect `safe_dp` dp tall: 20% of it and at least
## 200 dp, but no more than what keeps the band and the ArmyBar line (`reserved_dp`: the edge
## margin, the gap and the bar) within 40% of the safe height. The band gives way first, down to
## what its contents need (ADR 0015 section 5: never the ArmyBar, a 48 dp target or a 64 dp icon).
static func band_dp(safe_dp: float, reserved_dp: float) -> float:
	var wanted: float = maxf(safe_dp * BAND_SHARE, BAND_MIN_DP)
	return maxf(minf(wanted, safe_dp * STACK_SHARE - reserved_dp), BAND_FLOOR_DP)
