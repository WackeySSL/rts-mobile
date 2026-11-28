class_name TrophyBadge
extends Control
## One trophy's badge on the Rank screen (ADR 0054 section 8, P673d): a drawn square frame, the
## glyph SVG tinted inside it and up to three pips under the glyph. Lit uses the `money` token,
## dim the `text_mute` token, both from the theme (`HudTokens`). A glyph file that is missing draws
## the frame alone, with a warning. Read-only: it passes touches on, so the page scroll works.

const SIZE_DP: float = 56.0
const FRAME_DP: float = 2.0
const GLYPH_ART: String = "res://assets/art/svg/icons/%s.svg"
## The glyph fills this share of the frame's side, the pips sit in the strip under it.
const GLYPH_SHARE: float = 0.54
const PIP_DP: float = 7.0
const PIP_GAP_DP: float = 4.0

var glyph: StringName = &"":
	set(value):
		glyph = value
		_texture = _load_glyph()
		queue_redraw()
var pips: int = 0:
	set(value):
		pips = clampi(value, 0, TrophyCatalog.MAX_PIPS)
		queue_redraw()
var lit: bool = false:
	set(value):
		lit = value
		queue_redraw()

var _texture: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = UiScale.dp_vec(SIZE_DP, SIZE_DP)


func _draw() -> void:
	var token: StringName = &"money" if lit else &"text_mute"
	if not has_theme_color(token, &"HudTokens"):
		return
	var tone: Color = get_theme_color(token, &"HudTokens")
	var half: float = UiScale.dp(FRAME_DP) * 0.5
	draw_rect(Rect2(Vector2.ONE * half, size - Vector2.ONE * half * 2.0), tone, false, half * 2.0)
	var side: float = minf(size.x, size.y) * GLYPH_SHARE
	var pip_room: float = UiScale.dp(PIP_DP) * 2.0 if pips > 0 else 0.0
	var top: float = (size.y - side - pip_room) * 0.5
	if _texture != null:
		var at: Vector2 = Vector2((size.x - side) * 0.5, top)
		draw_texture_rect(_texture, Rect2(at, Vector2.ONE * side), false, tone)
	var radius: float = UiScale.dp(PIP_DP) * 0.5
	var step: float = UiScale.dp(PIP_DP + PIP_GAP_DP)
	var left: float = (size.x - step * float(pips - 1)) * 0.5
	for index: int in range(pips):
		var centre: Vector2 = Vector2(left + step * float(index), top + side + radius * 3.0)
		draw_circle(centre, radius, tone)


func _load_glyph() -> Texture2D:
	if glyph == &"":
		return null
	var path: String = GLYPH_ART % glyph
	if not ResourceLoader.exists(path):
		push_warning("TrophyBadge: no glyph file %s; the frame alone" % path)
		return null
	return load(path) as Texture2D
