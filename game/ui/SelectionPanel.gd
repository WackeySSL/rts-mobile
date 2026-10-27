class_name SelectionPanel
extends PanelContainer
## What is selected and how many (read-only in Phase 1): at the bottom centre in landscape, and in
## portrait the top line, right of the top-left controls. One row per unit type: its item card (the
## generated picture of P99b, in the type's own colours), its display name and "×N". With more than
## one type a last row shows the total. Hidden when nothing is selected.
## Fed by PlayerController.selection_changed (wired in the scene), so it works on a change only:
## a selected unit that dies leaves the selection first (PlayerController), which refreshes the
## counts. It reads `runner.snapshot` afresh at each call (ADR 0012 section 3), the names from its
## `type_names`, and never writes to it. Rows are made once and reused.
## It keeps its touches (mouse_filter STOP), so a tap on it never becomes a ground order. ADR 0004
## section 1 says that of HUD buttons; this panel is none, so it widens the rule to any HUD Control
## (a pan, box or pinch finger that starts on it is lost too, which is why it is small).
## Its parent MarginContainer is the band the panel sits in, and the panel sets the band's margins
## and its own size flags by the orientation of the window (`HudLayout.is_portrait`), on a change
## of the selection and on a resize. A flip runs it twice, so every call lays out from the state
## it finds.
## Landscape: the band lies between the ArmyBar and the floating build panel (`HudLayout.
## right_zone_px`: the panel and a gap, at the bottom right) and the panel sits in its middle, at
## the bottom. A row is at most BAND_SHARE of the band's width (the safe area's inner width, the
## band's own) and at most what the ArmyBar and the zone leave of it: a longer name or a larger
## count clips the name with an ellipsis, so the panel stays between the two. Only a screen too
## narrow for the least row (see `_fit_zone`) lets the zone give way.
## Portrait (ADR 0015 section 5): the rows stand side by side in one line at the top, after the
## `top_left` control and a gap. The panel never grows past the line (an overflow would grow the
## SafeArea and push the HUD off the screen); it takes the first of four fit levels whose line
## fits (`_fit_line`): the names; icon and count; without the total; the first rows that fit and
## a "+N" chip for the types left out.
## Its look is the inherited theme's (`game/ui/theme.tres`, set on the HUD roots by main.tscn): the
## backdrop is the `panel` style of the `SelectionPanel` variation (padding and corners in dp, in
## px once `HudTheme` has run), a name is a `Label`, the counts and the total are `NumberLabel`.

const ICON_ART: String = "res://assets/art/iso/icons/item_%s.svg"
const ICON_DP: float = 40.0
const MIN_HEIGHT_DP: float = 48.0
const GAP_DP: float = 8.0
const BAND_SHARE: float = 0.4  ## The widest a row may be, of the band's width.
const PANEL_VARIATION: StringName = &"SelectionPanel"
const NUMBER_VARIATION: StringName = &"NumberLabel"
## The fit levels of the portrait line, the first that fits: the names; icon and count, the total
## last; the same without the total; the first rows that fit and a "+N" chip.
const LEVEL_NAMED: int = 1
const LEVEL_ICONS: int = 2
const LEVEL_NO_TOTAL: int = 3
const LEVEL_CHIP: int = 4

@export var runner: MatchRunner
@export var army_bar: ArmyBar  ## The landscape band starts after it.
@export var top_left: Control  ## The portrait line starts after it (the Dev button).

var _list: BoxContainer = BoxContainer.new()  ## A column in landscape, a line in portrait.
var _total: Label = Label.new()
var _chip: Label = null  ## "+N", made when a line first needs it (level 4).
var _rows: Array[Row] = []
var _shown: int = 0  ## The rows that hold a type: the first `_shown` of `_rows`.
var _level: int = LEVEL_NAMED  ## The fit level of the last layout (landscape: always the first).
var _counts: PackedInt32Array = PackedInt32Array()  ## Selected units per type index.


## One unit type: the icon (its item card), its name and its count.
class Row:
	extends HBoxContainer

	var card: TextureRect = TextureRect.new()
	var title: Label = Label.new()
	var count: Label = Label.new()

	func _init() -> void:
		var icon: Control = Control.new()
		icon.name = "Icon"
		var min_size: DpMinSize = DpMinSize.new()
		min_size.min_dp = Vector2(ICON_DP, ICON_DP)
		icon.add_child(min_size)
		add_child(icon)
		card.name = "Card"
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.add_child(card)
		title.name = "Name"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		count.name = "Count"
		count.theme_type_variation = NUMBER_VARIATION
		for label: Label in [title, count]:
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			add_child(label)

	func show_type(id: StringName, label: String, number: int) -> void:
		visible = true
		var path: String = ICON_ART % id  # A type without a card shows a blank icon.
		card.texture = load(path) if ResourceLoader.exists(path) else null
		title.text = label
		count.text = "×%d" % number

	## The name's width is its text's, or `row_px` less the icon, the count and the gaps when the
	## row would be wider: the label clips the rest with an ellipsis.
	func fit_name(row_px: float) -> void:
		var font: Font = title.get_theme_font(&"font")
		var font_px: int = title.get_theme_font_size(&"font_size")
		var text_px: float = (
			font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_px).x
		)
		var gaps_px: int = 2 * roundi(UiScale.dp(GAP_DP))  # As apply_dp() sets them.
		var fixed_px: float = UiScale.dp(ICON_DP) + gaps_px + count.get_combined_minimum_size().x
		title.custom_minimum_size.x = minf(ceilf(text_px), maxf(row_px - fixed_px, 0.0))

	func apply_dp() -> void:
		add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	theme_type_variation = PANEL_VARIATION
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = Vector2(0.0, MIN_HEIGHT_DP)
	add_child(min_size)
	_list.name = "Rows"
	_list.vertical = true
	add_child(_list)
	_total.name = "Total"
	_total.theme_type_variation = NUMBER_VARIATION
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_total.visible = false
	_list.add_child(_total)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


## Shows the units in `ids` (unit ids) by type, or hides the panel when none of them exists.
func set_selected(ids: PackedInt32Array) -> void:
	var snap: MatchSnapshot = null if runner == null else runner.snapshot
	if snap == null:
		visible = false
		return
	var types: int = snap.type_ids.size()
	var type_index: PackedInt32Array = snap.type_index
	_counts.resize(types)
	_counts.fill(0)
	for id: int in ids:
		var row: int = snap.index_of(id)
		if row < 0:
			continue
		_counts[type_index[row]] += 1
	var shown: int = 0
	var total: int = 0
	for type: int in types:
		if _counts[type] == 0:
			continue
		if shown == _rows.size():
			_add_row()
		_rows[shown].show_type(snap.type_ids[type], snap.type_names[type], _counts[type])
		shown += 1
		total += _counts[type]
	_shown = shown
	_total.text = "Total ×%d" % total
	visible = shown > 0
	_fit_band()  # Which rows show, and the panel's width, follow the name and the count.


func _add_row() -> void:
	var row: Row = Row.new()
	row.name = "Row%d" % _rows.size()
	_list.add_child(row)
	_list.move_child(row, _rows.size())  # Above the total.
	_rows.append(row)
	row.apply_dp()


## Sizes are dp, so they follow a resize like DpMinSize does.
func _apply_dp() -> void:
	_list.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	for row: Row in _rows:
		row.apply_dp()
	_fit_band()


## Lays the panel out for the window's orientation: all rows with their names first (the cap of
## every name is set on that), then the landscape band or the portrait line.
func _fit_band() -> void:
	_show_level(LEVEL_NAMED, _shown)
	var band: MarginContainer = get_parent() as MarginContainer
	var safe: SafeAreaMargin = null if band == null else band.get_parent() as SafeAreaMargin
	if safe == null or army_bar == null:
		_fit_rows(INF)  # No band, no cap.
		return
	var portrait: bool = HudLayout.is_portrait()
	_list.vertical = not portrait
	var width: float = get_viewport().get_visible_rect().size.x
	var band_px: float = width - 2.0 * safe.apply().x
	if portrait:
		_fit_line(band, band_px)
	else:
		_fit_zone(band, band_px)


## Landscape: the band's margins are the ArmyBar on the left and the build panel's zone on the
## right, and the rows are capped to what they leave (the bottom row's room, less the backdrop's
## padding), so a long name clips and the panel never slides into the zone. The band's minimum
## width counts both margins; on a screen too narrow for them and the least row the zone gives
## way, instead of growing the SafeArea and pushing the HUD off the screen.
func _fit_zone(band: MarginContainer, band_px: float) -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_END
	var zone: float = HudLayout.right_zone_px(band_px)
	var left: int = ceili(army_bar.get_combined_minimum_size().x + UiScale.dp(GAP_DP))
	var between: float = band_px - left - ceilf(zone)  # The panel's room, backdrop included.
	var cap: float = minf(
		BAND_SHARE * band_px, between - get_theme_stylebox(&"panel").get_minimum_size().x
	)
	_fit_rows(cap)
	var over: float = get_combined_minimum_size().x - between
	if over > 0.0:  # The box layout rounds sizes up to whole px: the name gives the excess back.
		_fit_rows(cap - over)
	var room: float = band_px - left - get_combined_minimum_size().x
	band.add_theme_constant_override("margin_left", left)
	band.add_theme_constant_override("margin_right", mini(ceili(zone), maxi(floori(room), 0)))


## Portrait: the line runs from the `top_left` control's right edge plus a gap to the band's right
## edge, and the panel takes the first fit level whose width fits it. A name may take the whole
## line (one row is cut at its end, not at BAND_SHARE of the width, which would cut "Light Tank" on
## a narrow phone); with more rows the next level takes the names away. Level 4 drops rows from the
## end, one at a time, until the rest and the chip fit; the first row always stays. Only a line
## narrower than any phone leaves the panel wider than the line.
func _fit_line(band: MarginContainer, band_px: float) -> void:
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var left: int = 0
	if top_left != null and top_left.visible:
		left = ceili(top_left.get_combined_minimum_size().x + UiScale.dp(GAP_DP))
	band.add_theme_constant_override("margin_left", left)
	band.add_theme_constant_override("margin_right", 0)
	var line: float = band_px - left
	_fit_rows(line - get_theme_stylebox(&"panel").get_minimum_size().x)  # A row may take the line.
	var level: int = LEVEL_NAMED
	var rows: int = _shown
	while get_combined_minimum_size().x > line:
		if level < LEVEL_NO_TOTAL:
			level += 1
		elif rows > 1:
			level = LEVEL_CHIP
			rows -= 1
		else:
			break
		_show_level(level, rows)


## Shows the first `rows` type rows at fit `level`: names at the first level, the total (with more
## than one type) at the first two, and at the last the chip for the types left out.
func _show_level(level: int, rows: int) -> void:
	_level = level
	for index: int in _rows.size():
		_rows[index].visible = index < mini(rows, _shown)
		_rows[index].title.visible = level == LEVEL_NAMED
	_total.visible = _shown > 1 and level <= LEVEL_ICONS
	var left_out: int = maxi(_shown - rows, 0) if level == LEVEL_CHIP else 0
	if left_out > 0 and _chip == null:
		_chip = Label.new()
		_chip.name = "More"
		_chip.theme_type_variation = NUMBER_VARIATION
		_list.add_child(_chip)
	if _chip != null:
		_chip.visible = left_out > 0
		_chip.text = "+%d" % left_out


## Caps the name of every shown row so that the row is at most `row_px` wide.
func _fit_rows(row_px: float) -> void:
	for row: Row in _rows:
		if row.visible:
			row.fit_name(row_px)
