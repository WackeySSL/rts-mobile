class_name AdBannerSlot
extends Container
## The one bottom container of a menu screen (ADR 0043 section 8). It hosts Phase 6's
## `AdBannerBand` (P430) as its only child, so no screen builds a second band. It lands EMPTY and 0
## tall. The band owns its whole height (its gap, caption and `banner_height_dp`, from Phase 6's
## data; the start page's 48 dp is the band's `start_page`), so the slot is exactly as tall as the
## hosted band's `get_combined_minimum_size()` (0 when empty), puts the band's bottom on its own
## bottom, and lays out again when the band's minimum size changes. `MenuScreen` puts the slot's
## bottom on the safe rect's bottom and nothing below it: the real banner is drawn there.
## Phase 5 calls nothing on the band; the band shows on enter_tree and hides on exit_tree itself,
## and a covered screen leaves the tree (`MenuStack`), so a covered band drops its request.

var _band: Control = null


## The seam P430 plugs into. Takes `band` as the only child; false (and `band` untouched) when the
## slot already hosts one or `band` is null. The band is laid out by the slot, so it needs no
## anchors of its own.
func host(band: Control) -> bool:
	if band == null or has_band():
		return false
	_band = band
	add_child(band)
	if not band.minimum_size_changed.is_connected(_relayout):
		band.minimum_size_changed.connect(_relayout)
	if not band.tree_exited.is_connected(_on_band_exited):
		band.tree_exited.connect(_on_band_exited)
	_relayout()
	return true


func has_band() -> bool:
	return is_instance_valid(_band)


func _get_minimum_size() -> Vector2:
	return Vector2(0.0, _band_height())


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or not has_band() or _band.get_parent() != self:
		return
	var height: float = _band_height()
	fit_child_in_rect(_band, Rect2(0.0, size.y - height, size.x, height))


func _band_height() -> float:
	return _band.get_combined_minimum_size().y if has_band() else 0.0


func _on_band_exited() -> void:
	_check_band.call_deferred()


## The band left the slot (removed or freed). A band that only left the tree with its screen is
## still the slot's child and stays hosted.
func _check_band() -> void:
	if is_instance_valid(_band) and _band.get_parent() == self:
		return
	_band = null
	_relayout()


func _relayout() -> void:
	update_minimum_size()
	queue_sort()
