extends RefCounted
## Shared checks for a menu that hosts the ad banner band (P430; Phase 5's menu tests call them).
## Not a suite. The fake's "Test ad" strip stands for the real banner: it is drawn at the safe
## rect's bottom, so a band that lines up with it lines up with where AdService puts the banner.
## The service must run with `fake_auto_close = false` so the strip exists.

const STRIP_NODE: String = "FakeTestBanner"
const TOLERANCE_PX: float = 1.0


## The fake banner's strip (a Control) under `service`, or null when none is drawn.
static func strip_of(service: Node) -> Control:
	var layer: Node = service.get_node_or_null(STRIP_NODE)
	return layer.get_child(0) as Control if layer != null else null


## The band sits at the safe rect's bottom, its banner rect is the strip's rect, the caption fills
## the band's width, is centred and ends at or above the banner, and `above` (the control over the
## band) is `gap_dp` plus the caption away from the strip, with no slack. `label` names the case.
static func assert_lines_up(
	suite: GdUnitTestSuite,
	band: AdBannerBand,
	service: Node,
	above: Control,
	gap_dp: float,
	label: String
) -> void:
	var strip: Control = strip_of(service)
	suite.assert_object(strip).append_failure_message(label).is_not_null()
	if strip == null:
		return
	suite.assert_bool(band.is_at_safe_bottom()).append_failure_message(label).is_true()
	var banner: Rect2 = band.global_banner_rect()
	var drawn: Rect2 = strip.get_global_rect()
	suite.assert_float(banner.position.x).append_failure_message(label).is_equal_approx(
		drawn.position.x, TOLERANCE_PX
	)
	suite.assert_float(banner.position.y).append_failure_message(label).is_equal_approx(
		drawn.position.y, TOLERANCE_PX
	)
	suite.assert_float(banner.size.x).append_failure_message(label).is_equal_approx(
		drawn.size.x, TOLERANCE_PX
	)
	suite.assert_float(banner.size.y).append_failure_message(label).is_equal_approx(
		drawn.size.y, TOLERANCE_PX
	)
	var caption: Label = band.get_node("Caption")
	suite.assert_bool(caption.visible).append_failure_message(label).is_true()
	var caption_rect: Rect2 = caption.get_global_rect()
	var band_rect: Rect2 = band.get_global_rect()
	suite.assert_float(caption_rect.size.x).append_failure_message(label).is_equal_approx(
		band_rect.size.x, TOLERANCE_PX
	)
	suite.assert_float(caption_rect.get_center().x).append_failure_message(label).is_equal_approx(
		band_rect.get_center().x, TOLERANCE_PX
	)
	suite.assert_float(caption_rect.end.y).append_failure_message(label).is_less_equal(
		drawn.position.y + TOLERANCE_PX
	)
	var air: float = drawn.position.y - above.get_global_rect().end.y
	var wanted: float = UiScale.dp(gap_dp)
	suite.assert_float(air).append_failure_message(label).is_greater_equal(wanted - 0.01)
	suite.assert_float(air).append_failure_message(label).is_less_equal(
		wanted + caption_rect.size.y + TOLERANCE_PX
	)
