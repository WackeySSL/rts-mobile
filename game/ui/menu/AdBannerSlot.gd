class_name AdBannerSlot
extends Container
## The one bottom container of a menu screen (ADR 0043 section 8). It hosts Phase 6's
## `AdBannerBand` (P430) as its only child, so no screen builds a second band. It lands EMPTY and 0
## tall: until `host()` gives it a band it takes no room. Hosted, its height is
## `AdService.banner_height_dp()` plus `gap_dp` (16 dp is the floor of ADR 0039's G4; the start page
## sets 48, ADR 0025 section 12), and it lays itself out again on `AdService.banner_changed`. The
## band sits at the foot of the slot, the gap above it. Nothing is ever placed below the slot: the
## real banner is drawn at the screen's bottom edge (`MenuScreen` puts the slot at the safe rect's).
## Phase 5 calls nothing on the band; the band shows on enter_tree and hides on exit_tree itself.

const FLOOR_GAP_DP: float = 16.0

## The dp between the content above and the band.
@export var gap_dp: float = FLOOR_GAP_DP:
	set(value):
		gap_dp = maxf(value, FLOOR_GAP_DP)
		update_minimum_size()
		queue_sort()

var _band: Control = null
var _height_dp: int = 0  ## The banner's height in dp, as `AdService` last said.


func _ready() -> void:
	AdService.banner_changed.connect(_on_banner_changed)
	get_viewport().size_changed.connect(_relayout)
	_height_dp = AdService.banner_height_dp()
	_relayout()


## The seam P430 plugs into. Takes `band` as the only child; false (and `band` untouched) when the
## slot already hosts one or `band` is null. The band is laid out inside the slot, so it needs no
## anchors of its own.
func host(band: Control) -> bool:
	if band == null or _band != null:
		return false
	_band = band
	add_child(band)
	band.tree_exiting.connect(_on_band_gone.bind(band), CONNECT_ONE_SHOT)
	_relayout()
	return true


func has_band() -> bool:
	return _band != null


## The slot's height in base px: 0 with no band or no banner, else the banner plus the gap.
func wanted_height() -> float:
	if _band == null or _height_dp <= 0:
		return 0.0
	return UiScale.dp(float(_height_dp) + gap_dp)


## True when `control`'s bottom edge is the safe rect's bottom, within half a base px: nothing
## stands below it (the acceptance of P522 and of the menus that use the slot).
static func is_at_safe_bottom(control: Control) -> bool:
	return absf(control.get_global_rect().end.y - UiScale.safe_rect_base().end.y) <= 0.5


func _get_minimum_size() -> Vector2:
	return Vector2(0.0, wanted_height())


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or _band == null:
		return
	var band_px: float = UiScale.dp(float(_height_dp))
	fit_child_in_rect(_band, Rect2(0.0, size.y - band_px, size.x, band_px))


func _on_banner_changed(height_dp: int) -> void:
	_height_dp = height_dp
	_relayout()


func _on_band_gone(band: Control) -> void:
	if band == _band:
		_band = null
		_relayout()


func _relayout() -> void:
	update_minimum_size()
	queue_sort()
