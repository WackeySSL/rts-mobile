class_name AdBannerBand
extends Control
## The band every banner placement hosts (ADR 0039 section 5, plan P430). A menu puts the scene in
## its bottom band and calls nothing: the band asks AdService for a banner on `enter_tree`, gives
## it back on `exit_tree` and lays out again on `banner_changed` and when the viewport resizes (a
## turn). It reserves, top to bottom: the gap to the controls above (`banner_gap_dp`, or
## `start_banner_gap_dp` on the start page, ADR 0025 section 12), the small "Advertisement"
## caption (no frame, the theme's text colour) and `banner_height_dp()` for the banner. With no
## banner (Remove ads, no consent, no fill) it collapses to 0 height and the caption is hidden.
## The banner itself is AdService's; the band only keeps its place free. Never placed in the battle
## scene; the pause menu's foot is P435.

const CAPTION_FONT_DP: float = 12.0
const CAPTION_HEIGHT_DP: float = 16.0
const CAPTION_TEXT: String = "Advertisement"

## True for the start page: 48 dp of air instead of 16.
@export var start_page: bool = false

## Tests inject a service; null means the AdService autoload.
var service: Node = null

var _height_dp: int = 0

@onready var _caption: Label = $Caption


func _enter_tree() -> void:
	get_viewport().size_changed.connect(_layout)
	var ads: Node = _ads()
	if ads == null:
		return
	ads.connect(&"banner_changed", _on_banner_changed)
	ads.call(&"show_banner")
	_height_dp = int(ads.call(&"banner_height_dp"))
	_layout()


func _ready() -> void:
	_caption.text = CAPTION_TEXT
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout()


func _exit_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_layout):
		viewport.size_changed.disconnect(_layout)
	var ads: Node = _ads()
	if ads == null:
		return
	if ads.is_connected(&"banner_changed", _on_banner_changed):
		ads.disconnect(&"banner_changed", _on_banner_changed)
	ads.call(&"hide_banner")


## The banner's rect in this band's local px: the bottom `banner_height_dp()` of the band. Empty
## when there is no banner.
func banner_rect() -> Rect2:
	if _height_dp <= 0:
		return Rect2()
	var height: float = UiScale.dp(float(_height_dp))
	return Rect2(0.0, size.y - height, size.x, height)


## The gap above the caption, in dp.
func gap_dp() -> float:
	var settings: AdsSettingsDef = AdsSettingsDef.load_default()
	return float(settings.start_banner_gap_dp if start_page else settings.banner_gap_dp)


## The height the band reserves now, in base px (0 when there is no banner).
func reserved_px() -> float:
	if _height_dp <= 0:
		return 0.0
	return UiScale.dp(gap_dp() + CAPTION_HEIGHT_DP + float(_height_dp))


func _ads() -> Node:
	if service != null:
		return service
	return get_node_or_null("/root/AdService")


func _on_banner_changed(height_dp: int) -> void:
	_height_dp = height_dp
	_layout()


func _layout() -> void:
	if _caption == null:
		return
	custom_minimum_size = Vector2(0.0, reserved_px())
	var shown: bool = _height_dp > 0
	_caption.visible = shown
	if not shown:
		return
	_caption.add_theme_font_size_override("font_size", roundi(UiScale.dp(CAPTION_FONT_DP)))
	_caption.position = Vector2(0.0, UiScale.dp(gap_dp()))
	_caption.size = Vector2(size.x, UiScale.dp(CAPTION_HEIGHT_DP))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
