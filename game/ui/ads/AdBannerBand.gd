class_name AdBannerBand
extends Control
## The band every banner placement hosts (ADR 0039 section 5, plan P430). A menu adds one
## (`AdBannerBand.new()`) at the foot of its safe rect and calls nothing: the band asks AdService
## for a banner on `enter_tree`, gives it back on `exit_tree` and lays out again on
## `banner_changed`, on a resize of the band and on a resize of the viewport.
##
## It reserves, top to bottom: the gap to the controls above (`banner_gap_dp`, or
## `start_banner_gap_dp` on the start page, ADR 0025 section 12), the small "Advertisement"
## caption (no frame; the `AdCaption` look of `theme.tres`) and `banner_height_dp()` for the banner.
## With no banner (Remove ads, no consent, no fill) it collapses to 0 height and the caption is
## hidden. The banner itself is AdService's, drawn at the safe rect's bottom; the host must give the
## band the last row of the safe rect (`is_at_safe_bottom`) so the band's banner rect is the banner.
## The caption and its size come from the theme, so the host menu needs `HudTheme` (the dp step).
##
## The band sets `custom_minimum_size` itself instead of using `DpMinSize`: its minimum is not one
## fixed dp pair, it is the sum of three parts that change with the banner's height and the theme.
## A band that leaves and re-enters the tree in one frame (`reparent`) keeps the banner: AdService
## defers its last release to idle. After a turn the real banner is destroyed and loaded again at
## the new width by the backend (P405, ADR 0039 section 5); the band only follows the height it
## reports. Never placed in the battle scene, except at the foot of the open pause menu (P435): it
## builds the band hidden, checks `preview_reserved_px` against its room and only then shows it.

const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")
const CAPTION_TEXT: String = "Advertisement"
const CAPTION_VARIATION: StringName = &"AdCaption"
## How far the band's bottom may be from the safe rect's bottom (base px).
const BOTTOM_TOLERANCE_PX: float = 1.0

## True for the start page: 48 dp of air instead of 16.
@export var start_page: bool = false:
	set(value):
		start_page = value
		if is_node_ready():
			_layout()

## Tests inject a service; null means the AdService autoload.
var service: AdServiceScript = null

var _settings: AdsSettingsDef = AdsSettingsDef.load_default()
var _caption: Label
var _bound: AdServiceScript = null
var _height_dp: int = 0
var _check_queued: bool = false
## Whether this band holds one `show_banner` of the service now (one show, one hide, never two).
var _showing: bool = false


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption = Label.new()
	_caption.name = "Caption"
	_caption.text = CAPTION_TEXT
	_caption.theme_type_variation = CAPTION_VARIATION
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_caption.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_caption.visible = false
	add_child(_caption)
	_caption.minimum_size_changed.connect(_layout)


func _enter_tree() -> void:
	get_viewport().size_changed.connect(_layout)
	_bound = service if service != null else get_node_or_null("/root/AdService") as AdServiceScript
	if _bound == null:  # A scene run without the autoload (a developer scene).
		return
	_bound.banner_changed.connect(_on_banner_changed)
	if is_visible_in_tree():
		_acquire()


func _ready() -> void:
	_layout()


func _exit_tree() -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_layout):
		viewport.size_changed.disconnect(_layout)
	if is_instance_valid(_bound):
		if _bound.banner_changed.is_connected(_on_banner_changed):
			_bound.banner_changed.disconnect(_on_banner_changed)
	_release()  # Outside the check: a band whose service died must still drop its show.
	_bound = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _caption != null:
		_layout()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _bound != null and is_inside_tree():
		# Also fires when an ancestor is shown or hidden, which the signal does not.
		if is_visible_in_tree():
			_acquire()
		else:
			_release()


## The banner's rect in this band's local px: the bottom `banner_height_dp()` of the band. Empty
## when there is no banner. To confirm in P405: the real AdMob banner is anchored to the screen's or
## the safe area's bottom; until then only the fake's strip (the safe rect's bottom) is checked.
func banner_rect() -> Rect2:
	if _height_dp <= 0:
		return Rect2()
	var height: float = UiScale.dp(float(_height_dp))
	return Rect2(0.0, size.y - height, size.x, height)


## `banner_rect()` in global px.
func global_banner_rect() -> Rect2:
	var local: Rect2 = banner_rect()
	return Rect2(get_global_rect().position + local.position, local.size)


## Whether the band's bottom is the safe rect's bottom (within a pixel), where the banner is drawn.
func is_at_safe_bottom() -> bool:
	return absf(get_global_rect().end.y - UiScale.safe_rect_base().end.y) <= BOTTOM_TOLERANCE_PX


## The gap above the caption, in dp.
func gap_dp() -> float:
	return float(_settings.start_banner_gap_dp if start_page else _settings.banner_gap_dp)


## The height the band reserves now, in base px, rounded up so rounding never eats the gap (0 when
## there is no banner).
func reserved_px() -> float:
	return _reserve_for(_height_dp)


## What `reserved_px` would be once shown now (no request is made; 0 where no banner may show).
func preview_reserved_px() -> float:
	return _reserve_for(_bound.banner_height_dp(true) if _bound != null else 0)


func _reserve_for(height_dp: int) -> float:
	if height_dp <= 0:
		return 0.0
	var caption: float = _caption.get_minimum_size().y
	return ceilf(UiScale.dp(gap_dp()) + caption + UiScale.dp(float(height_dp)))


## Takes the band's one show and reads the banner height. No-op while it already holds one.
func _acquire() -> void:
	if _showing or _bound == null:
		return
	_showing = true
	_bound.show_banner()
	_height_dp = _bound.banner_height_dp()
	_layout()


## Gives the show back and reserves 0 height. No-op while it holds none.
func _release() -> void:
	if not _showing:
		return
	_showing = false
	if is_instance_valid(_bound):
		_bound.hide_banner()
	_height_dp = 0
	_layout()


func _on_banner_changed(height_dp: int) -> void:
	if not _showing:
		return
	_height_dp = height_dp
	_layout()


func _layout() -> void:
	custom_minimum_size = Vector2(0.0, reserved_px())
	var shown: bool = _height_dp > 0
	_caption.visible = shown
	if not shown:
		return
	var caption_h: float = _caption.get_minimum_size().y
	_caption.offset_left = 0.0
	_caption.offset_right = 0.0
	_caption.offset_top = size.y - UiScale.dp(float(_height_dp)) - caption_h
	_caption.offset_bottom = _caption.offset_top + caption_h
	if not _check_queued:
		_check_queued = true
		_check_bottom.call_deferred()


## One frame after the host's layout has settled (a size change reaches the container through two
## deferred steps): a shown band off the safe bottom is a host bug. A one-shot connection, not an
## await: a band freed within that frame drops the connection instead of resuming a dead coroutine.
func _check_bottom() -> void:
	if not is_inside_tree():
		_check_queued = false
		return
	get_tree().process_frame.connect(_check_bottom_now, CONNECT_ONE_SHOT)


func _check_bottom_now() -> void:
	_check_queued = false
	if is_inside_tree() and _height_dp > 0 and not is_at_safe_bottom():
		push_error(
			(
				"AdBannerBand %s is not at the safe rect's bottom: its banner would not sit in it"
				% get_path()
			)
		)
