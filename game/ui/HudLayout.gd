class_name HudLayout
extends RefCounted
## Where the battle-screen HUD keeps the end of its long axis free for the build sidebar (ADR 0015
## section 5, plan P85). The right zone in landscape is 20% of the width, at least 200 dp. The
## bottom zone in portrait is the sidebar's band: `BuildSidebar` sets `bottom_zone_dp` to the
## band's height (`band_dp`) from `_ready` and on every resize, and every HUD part reads it here
## and nowhere else, so the ArmyBar sits a gap above the band. A scene without a sidebar leaves it
## at 0 (the sidebar puts it back when it leaves the tree).
## The orientation is the one rule of UiScale, applied to the window the UI scale is made for.

const SIDEBAR_SHARE: float = 0.2  ## The right zone's share of the width (landscape).
const SIDEBAR_MIN_DP: float = 200.0  ## The least a zone takes, along the long axis.
const BAND_SHARE: float = 0.2  ## The portrait band's share of the safe height.
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


## The landscape right zone's width in base px for a visible rect `width` base px wide.
static func right_zone_px(width: float) -> float:
	return maxf(width * SIDEBAR_SHARE, UiScale.dp(SIDEBAR_MIN_DP))


## The portrait bottom zone's height in base px, at the bottom of the safe area's inner rect.
static func bottom_zone_px() -> float:
	return UiScale.dp(bottom_zone_dp)


## The portrait band's height in dp for a safe rect `safe_dp` dp tall: 20% of it and at least
## 200 dp, but no more than what keeps the band and the ArmyBar line (`reserved_dp`: the edge
## margin, the gap and the bar) within 40% of the safe height. The band gives way first, down to
## what its contents need (ADR 0015 section 5: never the ArmyBar, a 48 dp target or a 64 dp icon).
static func band_dp(safe_dp: float, reserved_dp: float) -> float:
	var wanted: float = maxf(safe_dp * BAND_SHARE, SIDEBAR_MIN_DP)
	return maxf(minf(wanted, safe_dp * STACK_SHARE - reserved_dp), BAND_FLOOR_DP)
