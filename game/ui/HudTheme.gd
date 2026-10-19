class_name HudTheme
extends Node
## The dp step of the HUD's one Theme (`theme.tres`; ADR 0004 section 3). The theme is written in
## dp, because a Theme stores fixed numbers. This node turns it into base px: it gives each Control
## that is a sibling of it (the HUD roots under the Hud CanvasLayer, which has no theme of its own)
## a copy of the root's theme with every font size and every StyleBox content margin and corner
## radius multiplied by `UiScale.base_px_per_dp()`, at `_ready` and whenever the viewport resizes.
## The copy is the root's `theme` and never a node override, so a restyle that adds a type, a
## variation or a StyleBox edits the theme file and no code here.
## It must be the first child of the Hud: its `size_changed` handler then runs before the HUD
## scripts' own, and what they read from the theme on a resize (`SelectionPanel.Row.fit_name`
## measures the name with the font size) is already the new one.

const BASE_PX_META: StringName = &"base_px"  ## On the theme: paths of entries kept in base px.
const SOURCE_META: StringName = &"source"  ## On a scaled copy: the theme it was made from.


func _ready() -> void:
	get_viewport().size_changed.connect(_apply)
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


static func _scale_box(box: StyleBox, px_per_dp: float) -> void:
	for side: int in 4:
		if box.get_content_margin(side) >= 0.0:
			box.set_content_margin(side, box.get_content_margin(side) * px_per_dp)
	var flat: StyleBoxFlat = box as StyleBoxFlat
	if flat != null:
		for corner: int in 4:
			flat.set_corner_radius(corner, roundi(flat.get_corner_radius(corner) * px_per_dp))


func _apply() -> void:
	var px_per_dp: float = UiScale.base_px_per_dp()
	var copies: Dictionary[Theme, Theme] = {}  # One copy per source, shared by the roots.
	for child: Node in get_parent().get_children():
		var root: Control = child as Control
		if root == null or root.theme == null:
			continue
		var source: Theme = root.theme.get_meta(SOURCE_META, root.theme)
		if not copies.has(source):
			copies[source] = scaled(source, px_per_dp)
		root.theme = copies[source]
