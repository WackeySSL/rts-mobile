class_name CoachButtonWidth
extends RefCounted
## The width a guide card button needs (P589b): its whole text in its own theme font and size plus
## the normal stylebox's horizontal margins, at least `least` px. A Button with an overrun mode set
## drops its text from its own minimum size, so the card measures the text itself and never reads
## `get_combined_minimum_size` for it.


static func of(button: Button, least: float) -> float:
	var font: Font = button.get_theme_font(&"font")
	var size: int = button.get_theme_font_size(&"font_size")
	var box: StyleBox = button.get_theme_stylebox(&"normal")
	var text: float = font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	return maxf(ceilf(least), ceilf(text + box.get_minimum_size().x))
