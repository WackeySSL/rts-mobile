class_name ArtSvg
extends RefCounted
## The SVG text of one frame (assets/art/STYLE.md "Generated art"): a comment, the root with the
## canvas, one `g` that sets the edge, and one `polygon` per face, back to front. Only these three
## elements, colours as upper-case "#RRGGBB" (the bake replaces the key triad by exact text),
## coordinates with one decimal and a fixed order, so two runs give the same bytes.

const EDGE_PX: int = 2  ## The edge of every face at 2x; it is not a detail thinner than 2 px.


## `origin` is where the model's origin lies in the canvas, in px.
static func frame(
	comment: String, size: Vector2i, origin: Vector2i, polys: Array[ArtRender.Poly]
) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("<!-- %s -->" % comment)
	lines.append(
		(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
			% [size.x, size.y, size.x, size.y]
		)
	)
	lines.append('<g stroke-width="%d" stroke-linejoin="round">' % EDGE_PX)
	for poly: ArtRender.Poly in polys:
		var points: PackedStringArray = PackedStringArray()
		for point: Vector2 in poly.points:
			points.append("%s,%s" % [_num(point.x + origin.x), _num(point.y + origin.y)])
		var edge: String = ' stroke="%s"' % poly.stroke if poly.stroke != "" else ""
		lines.append('<polygon points="%s" fill="%s"%s/>' % [" ".join(points), poly.fill, edge])
	lines.append("</g>")
	lines.append("</svg>")
	return "\n".join(lines) + "\n"


## One decimal, no "-0", no trailing ".0".
static func _num(value: float) -> String:
	var text: String = "%.1f" % value
	return "0" if text == "-0.0" else text.trim_suffix(".0")
