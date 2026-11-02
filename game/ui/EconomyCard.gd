class_name EconomyCard
extends PanelContainer
## The economy pill's detail card (ADR 0025 section 3, plan P119b): the credits with the income per
## minute, the tankers, the power used and made, a chip for each own building type that uses power
## (its display name and the sum it uses) and, on low power, a line on what that does. It reads one
## published snapshot per `show_from` and sends nothing; the pill decides when it shows (the ECONOMY
## unfold) and where (`HudCorners.CARD`). It takes every touch that lands on it: any touch closes
## it, and a touch on the card is no touch on the map. Rows are made once and reused and a text is
## written only when it changes. The look is the theme's (`HudPanel`, `NumberLabel`).

const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const PANEL_VARIATION: StringName = &"HudPanel"
const NUMBER_VARIATION: StringName = &"NumberLabel"
const TOKENS: StringName = &"HudTokens"
const GLYPH_DP: float = 24.0
const GAP_DP: float = 4.0  ## Between chips side by side.
## Between the rows: small, so the card at its tallest (six consumers and the low-power line) fits
## under the pill on the shortest screen at any px rounding of the text.
const ROW_GAP_DP: float = 2.0
const CHIP_VARIATION: StringName = &"EconomyConsumer"
const CREDITS_DIGITS: int = 5
## What low power does (GDD "Economy"; the percentage is `data/rules.tres`'s). Two lines of their
## own: a wrapped label's height waits for its width, which this card's height cannot.
const LOW_TEXT: String = "Production is slower.\nDefences are offline."

var _column: VBoxContainer = VBoxContainer.new()
var _credits_glyph: TextureRect
var _credits: DigitRow = DigitRow.new()
var _income: DigitRow = DigitRow.new()
var _tankers: DigitRow = DigitRow.new()
var _power_glyph: TextureRect
var _power: DigitRow = DigitRow.new()
var _grid: GridContainer = GridContainer.new()
var _warning: Label = Label.new()
var _chips: Array[Chip] = []
var _used: PackedInt32Array = PackedInt32Array()  ## Power used per building type, reused.
var _low: bool = false


## One consumer: a building type's display name and the power its buildings use together.
class Chip:
	extends PanelContainer

	var name_label: Label = Label.new()
	var sum: DigitRow = DigitRow.new()

	func _init() -> void:
		var line: HBoxContainer = HBoxContainer.new()
		add_child(line)
		name_label.name = "Name"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(name_label)
		sum.name = "Sum"
		sum.variation = EconomyCard.NUMBER_VARIATION
		line.add_child(sum)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func show_type(type_name: String, used: int) -> void:
		if name_label.text != type_name:
			name_label.text = type_name
		sum.set_text(str(used))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # A touch on the card is the card's, never the map's.
	theme_type_variation = PANEL_VARIATION
	add_child(_column)
	var credits_line: HBoxContainer = _line("CardCreditsRow")
	_credits_glyph = _glyph(credits_line, "CardCreditsGlyph", "glyph_credits")
	_number(credits_line, _credits, "CardCredits", CREDITS_DIGITS)
	_spacer(credits_line)
	_number(credits_line, _income, "CardIncome", 0)
	credits_line.add_child(_text("/min", "CardPerMinute"))
	var status_line: HBoxContainer = _line("CardStatusRow")
	status_line.add_child(_text("Tankers", "CardTankersCaption"))
	_number(status_line, _tankers, "CardTankers", 0)
	_spacer(status_line)
	_power_glyph = _glyph(status_line, "CardPowerGlyph", "glyph_power")
	_number(status_line, _power, "CardPower", 0)
	_grid.name = "CardChips"
	_grid.columns = 2
	_column.add_child(_grid)
	_warning.name = "CardWarning"
	_warning.text = LOW_TEXT
	_warning.visible = false
	_column.add_child(_warning)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _power_glyph != null:
		_tint()


## Shows `player`'s economy from `snap`, and `income` credits per minute. A building counts as the
## power rule counts it (ADR 0018 section 4): not while it is a construction site and not while a
## blackout holds it offline.
func show_from(snap: MatchSnapshot, player: int, income: int) -> void:
	var made: int = _entry(snap.power_made, player)
	var used: int = _entry(snap.power_used, player)
	_credits.set_text(str(_entry(snap.credits, player)))
	_income.set_text("+%d" % income)
	_power.set_text("%d/%d" % [used, made])
	var low: bool = used > made
	if low != _low:
		_low = low
		_power_glyph.texture = load(ICON_ART % ("glyph_low_power" if low else "glyph_power"))
		_tint()
	_warning.visible = low
	_tankers.set_text(str(_scan(snap, player)))
	var shown: int = 0
	for type: int in _used.size():
		if _used[type] <= 0:
			continue
		if shown == _chips.size():
			_add_chip()
		_chips[shown].show_type(snap.type_names[type], _used[type])
		_chips[shown].visible = true
		shown += 1
	for index: int in range(shown, _chips.size()):
		_chips[index].visible = false


## Counts `player`'s tankers and sums the power each of its building types uses into `_used`.
func _scan(snap: MatchSnapshot, player: int) -> int:
	var types: int = snap.type_power.size()
	_used.resize(types)
	_used.fill(0)
	var tankers: int = 0
	var building_left: PackedInt32Array = snap.build_left
	var offline: PackedInt32Array = snap.offline_until
	for row: int in snap.unit_count():
		if snap.owner[row] != player:
			continue
		var type: int = snap.type_index[row]
		tankers += 1 if OrderRules.is_tanker(snap, type) else 0
		var power: int = snap.type_power[type] if type < types else 0
		if power < 0 and building_left[row] == 0 and offline[row] <= snap.tick:
			_used[type] -= power
	return tankers


func _add_chip() -> void:
	var chip: Chip = Chip.new()
	chip.name = "Chip%d" % _chips.size()
	chip.theme_type_variation = CHIP_VARIATION
	_grid.add_child(chip)
	_chips.append(chip)


## A row of the card.
func _line(row_name: String) -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.name = row_name
	_column.add_child(line)
	return line


## A number in the theme's look, `digits` slots wide at least.
func _number(line: HBoxContainer, number: DigitRow, node_name: String, digits: int) -> void:
	number.name = node_name
	number.variation = NUMBER_VARIATION
	number.slots = digits
	line.add_child(number)


func _spacer(line: HBoxContainer) -> void:
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(spacer)


## A glyph of at least `GLYPH_DP`, added to `line`.
func _glyph(line: HBoxContainer, node_name: String, icon: String) -> TextureRect:
	var glyph: TextureRect = TextureRect.new()
	glyph.name = node_name
	glyph.texture = load(ICON_ART % icon)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = Vector2(GLYPH_DP, GLYPH_DP)
	glyph.add_child(min_size)
	line.add_child(glyph)
	return glyph


func _text(text: String, node_name: String) -> Label:
	var label: Label = Label.new()
	label.name = node_name
	label.text = text
	return label


## The glyphs' tints are the pill's: money for the coin and the bolt, danger for the triangle.
func _tint() -> void:
	_credits_glyph.modulate = get_theme_color(&"money", TOKENS)
	_power_glyph.modulate = get_theme_color(&"danger" if _low else &"money", TOKENS)


## Sizes are dp, so they follow a resize.
func _apply_dp() -> void:
	var row_gap: int = roundi(UiScale.dp(ROW_GAP_DP))
	_column.add_theme_constant_override("separation", row_gap)
	_grid.add_theme_constant_override("h_separation", roundi(UiScale.dp(GAP_DP)))
	_grid.add_theme_constant_override("v_separation", row_gap)
	_tint()


static func _entry(values: PackedInt32Array, player: int) -> int:
	return values[player] if player >= 0 and player < values.size() else 0
