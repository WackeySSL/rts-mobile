class_name SelectionPanel
extends PanelContainer
## What is selected and how many, at the bottom centre (read-only in Phase 1). One row per unit
## type: its own art (hull, team layer in the owner colour, turret), its display name and "×N".
## With more than one type a last row shows the total. Hidden when nothing is selected.
## Fed by PlayerController.selection_changed (wired in the scene), so it works on a change only:
## a selected unit that dies leaves the selection first (PlayerController), which refreshes the
## counts. It reads `runner.snapshot` afresh at each call (ADR 0012 section 3), the names from its
## `type_names`, and never writes to it. Rows are made once and reused.
## It keeps its touches (mouse_filter STOP), so a tap on it never becomes a ground order. ADR 0004
## section 1 says that of HUD buttons; this panel is none, so it widens the rule to any HUD Control
## (a pan, box or pinch finger that starts on it is lost too, which is why it is small).
## Its parent MarginContainer is the band between the ArmyBar and the sidebar zone (the right 20%,
## at least 200 dp, kept free for the build sidebar). The panel sets that band's margins and sits
## in its middle. A row is at most BAND_SHARE of the band's width (the safe area's inner width, the
## band's own): a longer name is clipped with an ellipsis.

const ICON_DP: float = 40.0
const MIN_HEIGHT_DP: float = 48.0
const NAME_FONT_DP: float = 16.0  ## Body text is at least 14 sp (touch-ui-rules).
const NUMBER_FONT_DP: float = 20.0  ## HUD numbers are at least 18 sp.
const PAD_DP: float = 8.0
const GAP_DP: float = 8.0
const SIDEBAR_SHARE: float = 0.2
const SIDEBAR_MIN_DP: float = 200.0
const BAND_SHARE: float = 0.4  ## The widest a row may be, of the band's width.
const BACKDROP: Color = Color(0.06, 0.08, 0.11, 0.78)

@export var runner: MatchRunner
@export var unit_layer: UnitLayer  ## Owner colours for the icons.
@export var army_bar: ArmyBar  ## The band starts after it.

var _style: StyleBoxFlat = StyleBoxFlat.new()
var _list: VBoxContainer = VBoxContainer.new()
var _total: Label = Label.new()
var _rows: Array[Row] = []
var _counts: PackedInt32Array = PackedInt32Array()  ## Selected units per type index.


## One unit type: the icon (three stacked layers), its name and its count.
class Row:
	extends HBoxContainer

	var layers: Array[TextureRect] = []
	var title: Label = Label.new()
	var count: Label = Label.new()

	func _init() -> void:
		var icon: Control = Control.new()
		icon.name = "Icon"
		var min_size: DpMinSize = DpMinSize.new()
		min_size.min_dp = Vector2(ICON_DP, ICON_DP)
		icon.add_child(min_size)
		add_child(icon)
		for file: String in UnitLayer.LAYER_FILES:
			var layer: TextureRect = TextureRect.new()
			layer.name = file.capitalize()
			layer.set_anchors_preset(Control.PRESET_FULL_RECT)
			layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.add_child(layer)
			layers.append(layer)
		title.name = "Name"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		count.name = "Count"
		for label: Label in [title, count]:
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			add_child(label)

	func show_type(id: StringName, label: String, number: int, tint: Color) -> void:
		visible = true
		for index: int in layers.size():  # A type without art shows a blank icon.
			var path: String = "%s%s_%s.svg" % [UnitLayer.ART_DIR, id, UnitLayer.LAYER_FILES[index]]
			layers[index].texture = load(path) if ResourceLoader.exists(path) else null
		layers[UnitLayer.TEAM_LAYER].modulate = tint
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
		title.add_theme_font_size_override("font_size", roundi(UiScale.dp(NAME_FONT_DP)))
		count.add_theme_font_size_override("font_size", roundi(UiScale.dp(NUMBER_FONT_DP)))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_style.bg_color = BACKDROP
	add_theme_stylebox_override("panel", _style)
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = Vector2(0.0, MIN_HEIGHT_DP)
	add_child(min_size)
	_list.name = "Rows"
	add_child(_list)
	_total.name = "Total"
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
	var tint: Color = unit_layer.team_color(runner.scenario.local_player)  # Own units only.
	var shown: int = 0
	var total: int = 0
	for type: int in types:
		if _counts[type] == 0:
			continue
		if shown == _rows.size():
			_add_row()
		_rows[shown].show_type(snap.type_ids[type], snap.type_names[type], _counts[type], tint)
		shown += 1
		total += _counts[type]
	for hidden: int in range(shown, _rows.size()):
		_rows[hidden].visible = false
	_total.text = "Total ×%d" % total
	_total.visible = shown > 1
	visible = shown > 0
	_fit_band()  # The panel's width follows the name and the count.


func _add_row() -> void:
	var row: Row = Row.new()
	row.name = "Row%d" % _rows.size()
	_list.add_child(row)
	_list.move_child(row, _rows.size())  # Above the total.
	_rows.append(row)
	row.apply_dp()


## Sizes are dp, so they follow a resize like DpMinSize does.
func _apply_dp() -> void:
	_style.set_content_margin_all(UiScale.dp(PAD_DP))
	_style.set_corner_radius_all(roundi(UiScale.dp(PAD_DP)))
	_list.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_total.add_theme_font_size_override("font_size", roundi(UiScale.dp(NUMBER_FONT_DP)))
	for row: Row in _rows:
		row.apply_dp()
	_fit_band()


## The band's margins: the ArmyBar on the left, the sidebar zone on the right. The band's minimum
## width counts both, so on a screen too narrow for all three the zone gives way and the panel sits
## in the still empty zone, instead of growing the SafeArea and pushing the HUD off the screen.
func _fit_band() -> void:
	var band: MarginContainer = get_parent() as MarginContainer
	var safe: SafeAreaMargin = null if band == null else band.get_parent() as SafeAreaMargin
	if safe == null or army_bar == null:
		_fit_rows(INF)  # No band, no cap.
		return
	var width: float = get_viewport().get_visible_rect().size.x
	var zone: float = maxf(width * SIDEBAR_SHARE, UiScale.dp(SIDEBAR_MIN_DP))
	var left: int = ceili(army_bar.get_combined_minimum_size().x + UiScale.dp(GAP_DP))
	var band_px: float = width - 2.0 * safe.apply().x
	_fit_rows(BAND_SHARE * band_px)
	var room: float = band_px - left - get_combined_minimum_size().x
	band.add_theme_constant_override("margin_left", left)
	band.add_theme_constant_override("margin_right", mini(ceili(zone), maxi(floori(room), 0)))


## Caps the name of every shown row so that the row is at most `row_px` wide.
func _fit_rows(row_px: float) -> void:
	for row: Row in _rows:
		if row.visible:
			row.fit_name(row_px)
