class_name HudTheme
extends Node
## The dp step of the HUD's one Theme (`theme.tres`; ADR 0004 section 3). The theme is written in
## dp, because a Theme stores fixed numbers. This node turns it into base px: it gives each Control
## that is a sibling of it (the HUD roots under the Hud CanvasLayer, which has no theme of its own)
## a copy of the root's theme with every font size and every size of a StyleBox (content margins,
## corner radii, border widths, expand margins, shadows, a line's thickness) multiplied by
## `UiScale.base_px_per_dp()`, at `_ready` and whenever the viewport resizes. A root added to the
## Hud later, with the theme file on it, gets the copy as it enters the tree, before its children
## enter or anything is ready: the roots of one source share one copy, as at a resize.
## The copy is the root's `theme` and never a node override, so a restyle that adds a type, a
## variation or a StyleBox edits the theme file and no code here.
## It must be the first child of the Hud: its `size_changed` handler then runs before the HUD
## scripts' own, and what they read from the theme on a resize (`SelectionPanel.Row.fit_name`
## measures the name with the font size) is already the new one.
## Not scaled: a StyleBoxTexture's texture margins (they cut the picture, in texture px), the
## theme's constants (a font's `outline_size` too: layout stays in code, in dp through UiScale),
## colours, fonts and icons, and the properties of a StyleBox that are not sizes: `skew` (a shear
## ratio, so the angle is the same on every screen), `corner_detail` (a count) and
## `anti_aliasing_size` (the width of the soft edge, a sharpness setting that stays 1 px). Add what
## a restyle needs of those to `scaled()` before it uses one.

const BASE_PX_META: StringName = &"base_px"  ## On the theme: paths of entries kept in base px.
const SOURCE_META: StringName = &"source"  ## On a scaled copy: the theme it was made from.
## The StyleBox properties that are sizes in px, by the start of their name. A float below 0 is
## "not set" for a content margin and a real value for the rest (a line's `grow_begin`).
const PX_PROPERTIES: PackedStringArray = [
	"content_margin_",
	"corner_radius_",
	"border_width_",
	"expand_margin_",
	"shadow_size",
	"shadow_offset",
	"thickness",
	"grow_",
]

var _px_per_dp: float = 1.0  ## The factor of the last `_apply`.
var _copies: Dictionary[Theme, Theme] = {}  ## One copy per source, shared by the roots.


func _ready() -> void:
	get_viewport().size_changed.connect(_apply)
	get_parent().child_entered_tree.connect(_scale_root)
	_apply()


## A copy of `source` in base px, for `px_per_dp` base px per dp. The source is not changed: each
## StyleBox is copied before it is scaled. An entry listed in the source's `base_px` metadata (by
## its path in the theme file, such as "DevButton/font_sizes/font_size") keeps its value. A font
## size is rounded to whole px, like a corner radius. A content margin below 0 is "not set".
static func scaled(source: Theme, px_per_dp: float) -> Theme:
	var out: Theme = source.duplicate() as Theme
	out.set_meta(SOURCE_META, source)
	var kept: PackedStringArray = source.get_meta(BASE_PX_META, PackedStringArray())
	if out.default_font_size > 0:
		out.default_font_size = roundi(out.default_font_size * px_per_dp)
	for type: String in out.get_type_list():
		for item: String in out.get_font_size_list(type):
			if not kept.has("%s/font_sizes/%s" % [type, item]):
				out.set_font_size(item, type, roundi(out.get_font_size(item, type) * px_per_dp))
		for item: String in out.get_stylebox_list(type):
			if not kept.has("%s/styles/%s" % [type, item]):
				var box: StyleBox = out.get_stylebox(item, type).duplicate()
				_scale_box(box, px_per_dp)
				out.set_stylebox(item, type, box)
	return out


## Every px size of `box`, found by name (PX_PROPERTIES). A whole number is rounded, like a font
## size, and a content margin below 0 is "not set" and stays so.
static func _scale_box(box: StyleBox, px_per_dp: float) -> void:
	for property: Dictionary in box.get_property_list():
		var key: String = property["name"]
		if not _is_px_property(key):
			continue
		var value: Variant = box.get(key)
		match typeof(value):
			TYPE_INT:
				box.set(key, roundi((value as int) * px_per_dp))
			TYPE_FLOAT:
				if (value as float) >= 0.0 or not key.begins_with("content_margin_"):
					box.set(key, (value as float) * px_per_dp)
			TYPE_VECTOR2:
				box.set(key, (value as Vector2) * px_per_dp)


static func _is_px_property(key: String) -> bool:
	for prefix: String in PX_PROPERTIES:
		if key.begins_with(prefix):
			return true
	return false


func _apply() -> void:
	_px_per_dp = UiScale.base_px_per_dp()
	_copies.clear()
	for child: Node in get_parent().get_children():
		_scale_root(child)


## The root's theme becomes the copy of its source: a root with no theme, and a node that is not a
## Control, are left as they are.
func _scale_root(child: Node) -> void:
	var root: Control = child as Control
	if root == null or root.theme == null:
		return
	var source: Theme = root.theme.get_meta(SOURCE_META, root.theme)
	if not _copies.has(source):
		_copies[source] = scaled(source, _px_per_dp)
	root.theme = _copies[source]
