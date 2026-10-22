class_name HudLayout
extends RefCounted
## Where the battle-screen HUD keeps the end of its long axis free for the build sidebar (ADR 0015
## section 5). The right zone in landscape (20% of the width, at least 200 dp) stays reserved and
## empty until Phase 3's sidebar row, as ADR 0004's Amendment (P21) has it. The bottom zone in
## portrait is the sidebar's band: it is not reserved while the sidebar does not exist, so its
## height is 0 and the ArmyBar sits on the bottom edge. Phase 3's sidebar row sets
## `bottom_zone_dp` to the band's height; every HUD part reads it here and nowhere else.
## The orientation is the one rule of UiScale, applied to the window the UI scale is made for.

const SIDEBAR_SHARE: float = 0.2  ## The right zone's share of the width (landscape).
const SIDEBAR_MIN_DP: float = 200.0  ## The least a zone takes, along the long axis.

## The portrait bottom zone's height in dp; 0 until the sidebar row. Static state: a test that sets
## one puts it back in `after_test`, like the UiScale override.
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
