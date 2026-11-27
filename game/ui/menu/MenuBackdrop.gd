class_name MenuBackdrop
extends Control
## The menu's picture and its reading shade (ADR 0052 section 3, P663), the first child of the
## `MenuStack`, so every screen slides over the same still picture. It takes the wide or the tall
## crop by the viewport's measured aspect (the nearer one, never an orientation flag) and covers
## the screen with no letterbox. The `MenuScrim` shade of the theme darkens the text side: the left
## in the wide crop (the right with `text_on_right`), the top in the tall one. Still, with no
## parallax and no animation, so Reduced effects changes nothing. Two draw calls: picture, shade.
## `usable` is false when a picture or the shade is missing; the owner then drops it and keeps
## the flat backdrop colour.

const WIDE_ART: String = "res://assets/art/backdrops/menu_wide.png"
const TALL_ART: String = "res://assets/art/backdrops/menu_tall.png"

var wide_path: String = WIDE_ART  ## Tests point these at another file.
var tall_path: String = TALL_ART
var text_on_right: bool = false
var usable: bool = false
var is_tall: bool = false

var _wide: Texture2D
var _tall: Texture2D
var _picture: TextureRect
var _scrim: TextureRect


## Puts the picture under the stack's screens; they turn see-through only when it can be drawn,
## else it is dropped and today's flat backdrop colour stays.
static func attach(stack: MenuStack) -> MenuBackdrop:
	var backdrop: MenuBackdrop = MenuBackdrop.new()
	stack.add_child(backdrop)
	stack.move_child(backdrop, 0)
	stack.see_through = backdrop.usable
	if not backdrop.usable:
		backdrop.queue_free()
		return null
	return backdrop


func _ready() -> void:
	name = &"MenuBackdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_wide = _open(wide_path)
	_tall = _open(tall_path)
	var shade: Texture2D = get_theme_icon(&"shade", &"MenuScrim")
	if _wide == null or _tall == null or shade == null:
		return
	_picture = _layer(&"Picture", _wide)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_scrim = _layer(&"Scrim", shade)
	_scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_scrim.stretch_mode = TextureRect.STRETCH_SCALE
	usable = true
	get_viewport().size_changed.connect(_apply)
	_apply()


func _open(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _layer(layer_name: StringName, texture: Texture2D) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.name = layer_name
	rect.texture = texture
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


## The crop whose aspect is nearer the viewport's (their geometric mean is the cut).
func _apply() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var wide: float = float(_wide.get_width()) / float(_wide.get_height())
	var tall: float = float(_tall.get_width()) / float(_tall.get_height())
	is_tall = view.x / maxf(view.y, 1.0) < sqrt(wide * tall)
	_picture.texture = _tall if is_tall else _wide
	_scrim.flip_h = text_on_right and not is_tall
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.rotation = 0.0
	if is_tall:  # The shade turned a quarter: dark at the top, clear at the foot.
		_scrim.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_scrim.size = Vector2(view.y, view.x)
		_scrim.position = Vector2(view.x, 0.0)
		_scrim.rotation = TAU / 4.0
