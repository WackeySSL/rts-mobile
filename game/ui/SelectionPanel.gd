class_name SelectionPanel
extends PanelContainer
## What is selected and how many, at the bottom centre (read-only in Phase 1). One row per unit
## type: its own art (hull, team layer in the owner colour, turret), its name (the type id,
## capitalised) and "×N". With more than one type a last row shows the total. Hidden when nothing
## is selected.
## Fed by PlayerController.selection_changed (wired in the scene), so it works on a change only. It
## reads the World through the runner and never writes to it. Rows are made once and reused.
## It keeps its touches (mouse_filter STOP), so a tap on it never becomes a ground order. ADR 0004
## section 1 says that of HUD buttons; this panel is none, so it widens the rule to any HUD Control
## (a pan, box or pinch finger that starts on it is lost too, which is why it is small).
## Its parent MarginContainer is the band between the ArmyBar and the sidebar zone (the right 20%,
## at least 200 dp, kept free for the build sidebar). The panel sets that band's margins and sits
## in its middle. A name much longer than "Light Tank" needs a width cap before a second type lands.

const ICON_DP: float = 40.0
const MIN_HEIGHT_DP: float = 48.0
const NAME_FONT_DP: float = 16.0  ## Body text is at least 14 sp (touch-ui-rules).
const NUMBER_FONT_DP: float = 20.0  ## HUD numbers are at least 18 sp.
const PAD_DP: float = 8.0
const GAP_DP: float = 8.0
const SIDEBAR_SHARE: float = 0.2
const SIDEBAR_MIN_DP: float = 200.0
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
		count.name = "Count"
		for label: Label in [title, count]:
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			add_child(label)

	func show_type(id: StringName, number: int, tint: Color) -> void:
		visible = true
		for index: int in layers.size():  # A type without art shows a blank icon.
			var path: String = "%s%s_%s.svg" % [UnitLayer.ART_DIR, id, UnitLayer.LAYER_FILES[index]]
			layers[index].texture = load(path) if ResourceLoader.exists(path) else null
		layers[UnitLayer.TEAM_LAYER].modulate = tint
		title.text = String(id).capitalize()
		count.text = "×%d" % number

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


## Shows the units in `ids` (World ids) by type, or hides the panel when none of them exists.
func set_selected(ids: PackedInt32Array) -> void:
	var world: World = null if runner == null else runner.world
	if world == null:
		visible = false
		return
	var types: int = world.type_ids.size()
	_counts.resize(types)
	_counts.fill(0)
	for id: int in ids:
		var row: int = world.index_of(id)
		if row < 0:
			continue
		_counts[world.type_index[row]] += 1
	var tint: Color = unit_layer.team_color(runner.scenario.local_player)  # Own units only.
	var shown: int = 0
	var total: int = 0
	for type: int in types:
		if _counts[type] == 0:
			continue
		if shown == _rows.size():
			_add_row()
		_rows[shown].show_type(world.type_ids[type], _counts[type], tint)
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
		return
	var width: float = get_viewport().get_visible_rect().size.x
	var zone: float = maxf(width * SIDEBAR_SHARE, UiScale.dp(SIDEBAR_MIN_DP))
	var left: int = ceili(army_bar.get_combined_minimum_size().x + UiScale.dp(GAP_DP))
	var room: float = width - 2.0 * safe.apply().x - left - get_combined_minimum_size().x
	band.add_theme_constant_override("margin_left", left)
	band.add_theme_constant_override("margin_right", mini(ceili(zone), maxi(floori(room), 0)))
