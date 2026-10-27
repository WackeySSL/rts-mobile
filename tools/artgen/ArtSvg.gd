class_name ArtSvg
extends RefCounted
## The SVG text of a generated file (assets/art/STYLE.md "Generated art"): a comment, the root with
## the canvas, groups of polygons back to front. Only these three elements (`svg`, `g`, `polygon`),
## colours as upper-case "#RRGGBB" (the bake replaces the key triad by exact text), coordinates
## with one decimal and a fixed order, so two runs give the same bytes.

const EDGE_PX: int = 2  ## The edge of every face at 2x; it is not a detail thinner than 2 px.


## One frame of a part: one group that sets the edge, one polygon per face. `origin` is where the
## model's origin lies in the canvas, in px.
static func frame(
	comment: String, size: Vector2i, origin: Vector2i, polys: Array[ArtRender.Poly]
) -> String:
	var attributes: String = 'stroke-width="%d" stroke-linejoin="round"' % EDGE_PX
	return document(comment, size, group(attributes, polys, Vector2(origin)))


## One frame of a cast shadow: its polygons are black and one group makes them 35 % together, so
## where two overlap the shadow is no darker.
static func shadow(
	comment: String, size: Vector2i, origin: Vector2i, polys: Array[ArtRender.Poly]
) -> String:
	var attributes: String = 'opacity="%s"' % ArtShadow.OPACITY
	return document(comment, size, group(attributes, polys, Vector2(origin)))


## The file: `body` is the lines between the root and its end.
static func document(comment: String, size: Vector2i, body: PackedStringArray) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("<!-- %s -->" % comment)
	lines.append(
		(
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
			% [size.x, size.y, size.x, size.y]
		)
	)
	lines.append_array(body)
	lines.append("</svg>")
	return "\n".join(lines) + "\n"


## A `g` with `attributes` round one polygon per entry of `polys`, each point scaled and moved.
static func group(
	attributes: String,
	polys: Array[ArtRender.Poly],
	origin: Vector2 = Vector2.ZERO,
	scale: float = 1.0
) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("<g %s>" % attributes if attributes != "" else "<g>")
	for poly: ArtRender.Poly in polys:
		var points: PackedStringArray = PackedStringArray()
		for point: Vector2 in poly.points:
			var at: Vector2 = point * scale + origin
			points.append("%s,%s" % [num(at.x), num(at.y)])
		var edge: String = ' stroke="%s"' % poly.stroke if poly.stroke != "" else ""
		lines.append('<polygon points="%s" fill="%s"%s/>' % [" ".join(points), poly.fill, edge])
	lines.append("</g>")
	return lines


## One decimal, no "-0", no trailing ".0".
static func num(value: float) -> String:
	var text: String = "%.1f" % value
	return "0" if text == "-0.0" else text.trim_suffix(".0")
