class_name EconomyLine
extends PanelContainer
## The economy line of the build drawer's head (ADR 0025 sections 3 and 5, plan P120d): the credits
## with "+N/min" under them and the power bar with "used/made", in a plate of the pill's look. While
## the drawer is open the pill folds and this line shows the economy, so it is on screen once.
## It is a mirror of the `EconomyPill`: the pill reads the snapshots and keeps the flash, the count
## -down, the income ring and the pulse (it goes on while folded), and this line takes what the pill
## shows once per frame and writes a text, a bar or a tint only when its value changed, so nothing
## is allocated at rest and `UiScale` is asked on a resize only. The digits are `DigitRow`s, the
## flash chip is the pill's (`CHIP_*`), the low-power look is the pill's: the red edge, the bar and
## the triangle, "LOW POWER" in the bar where it fits, and P89's pulse.
## The line takes no touch: the economy card is the pill's (ADR 0025 section 1 lets one unfold stand
## at a time, so opening the card would close the drawer); a touch on it is a touch on the drawer.

const GLYPH_DP: float = 24.0
const BAR_DP: Vector2 = Vector2(24.0, 28.0)  ## The bar's least size; it takes the rest.
const GAP_DP: float = 4.0
const TEXT_PAD_DP: float = 2.0  ## Each side of the numbers and the word in the bar.
const TEXT_EDGE_DP: float = 2.0
const CHIP_GAP_DP: float = 4.0  ## Between the line and the chip under its credits.
const NONE: int = -1  ## A cache that has seen nothing yet.

@export var pill: EconomyPill  ## What the line mirrors.

var _row: HBoxContainer = HBoxContainer.new()
var _credits_glyph: TextureRect
var _credits_column: VBoxContainer = VBoxContainer.new()
var _credits: DigitRow = DigitRow.new()
var _income: Label = Label.new()
var _power_glyph: TextureRect
var _bar: ProgressBar = ProgressBar.new()
var _numbers: DigitRow = DigitRow.new()
var _word: Label = Label.new()
var _chip: PanelContainer = PanelContainer.new()
var _chip_text: DigitRow = DigitRow.new()
var _low: bool = false
var _shown_credits: int = NONE
var _shown_income: int = NONE
var _shown_power: Vector2i = Vector2i(NONE, NONE)  ## Made and used.
var _shown_flash: int = 0
var _shown_step: int = NONE
var _chip_gap_px: float = 0.0  ## `CHIP_GAP_DP` in px, set on a resize (no `UiScale` per frame).


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = EconomyPill.VARIATION
	_row.name = "Line"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	_credits_glyph = _glyph("CreditsGlyph", "glyph_credits")
	_credits_column.name = "Credits"
	_credits_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_credits_column.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_credits_column.add_theme_constant_override("separation", 0)
	_row.add_child(_credits_column)
	_credits.name = "CreditsNumber"
	_credits.variation = &"NumberLabel"
	_credits.slots = EconomyPill.CREDITS_DIGITS
	_credits.set_text("0")
	_credits_column.add_child(_credits)
	_income.name = "Income"
	_income.theme_type_variation = &"ItemCaption"
	_income.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_income.text = "+0/min"
	_credits_column.add_child(_income)
	_power_glyph = _glyph("PowerGlyph", "glyph_power")
	_build_bar()
	_build_chip()
	visibility_changed.connect(_on_visibility_changed)
	get_viewport().size_changed.connect(_apply_dp)
	_apply_dp()
	_on_visibility_changed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _power_glyph != null:
		_tint()
		_fit_bar_text()


func _process(_delta: float) -> void:
	_read()


## Whether the line shows low power.
func is_low() -> bool:
	return _low


## The flash chip under the credits (a cue: it takes no touch).
func chip() -> Control:
	return _chip


## Takes what the pill shows now; a value that did not change writes nothing.
func _read() -> void:
	if pill == null:
		return
	var credits: int = pill.credits_on_screen()
	if credits != _shown_credits:
		_shown_credits = credits
		_credits.set_text(str(credits))
	var income: int = pill.income_per_minute()
	if income != _shown_income:
		_shown_income = income
		_income.text = "+%d/min" % income
	var power: Vector2i = pill.power_on_screen()
	if power != _shown_power:
		_shown_power = power
		_show_power(power.x, power.y)
	var flash: int = pill.flash_amount()
	if flash != _shown_flash:
		_shown_flash = flash
		_show_flash(flash)
	if _chip.visible:
		_place_chip()  # The drawer may still be sliding.
	if pill.pulse_step() != _shown_step:
		_shown_step = pill.pulse_step()
		self_modulate = pill.pulse_tint()
		_power_glyph.self_modulate = pill.pulse_tint()


## The line follows the drawer: it runs while shown, and then reads everything anew.
func _on_visibility_changed() -> void:
	var shown: bool = is_visible_in_tree()
	set_process(shown)
	if shown:
		_shown_credits = NONE
		_shown_income = NONE
		_shown_power = Vector2i(NONE, NONE)
		_shown_flash = 0
		_shown_step = NONE
		_read()
	else:
		_chip.visible = false


func _show_power(made: int, used: int) -> void:
	var low: bool = used > made
	_bar.max_value = maxi(made, 1)
	_bar.value = _bar.max_value if low else used
	_numbers.set_text("%d/%d" % [used, made])
	if low != _low:
		_low = low
		theme_type_variation = EconomyPill.LOW_VARIATION if low else EconomyPill.VARIATION
		_bar.theme_type_variation = (
			EconomyPill.BAR_LOW_VARIATION if low else EconomyPill.BAR_VARIATION
		)
		_numbers.variation = (
			EconomyPill.NUMBER_LOW_VARIATION if low else EconomyPill.NUMBER_VARIATION
		)
		_power_glyph.texture = load(
			EconomyPill.ICON_ART % ("glyph_low_power" if low else "glyph_power")
		)
		_tint()
	_fit_bar_text()


## The chip shows a change of the credits ("-600", "+180") for the pill's flash time.
func _show_flash(amount: int) -> void:
	_chip.visible = amount != 0
	if amount == 0:
		return
	_chip_text.set_text("%+d" % amount)
	_chip.theme_type_variation = (
		EconomyPill.CHIP_LOSS_VARIATION if amount < 0 else EconomyPill.CHIP_GAIN_VARIATION
	)
	_place_chip()


func _place_chip() -> void:
	_chip.reset_size()
	var below: float = global_position.y + size.y + _chip_gap_px
	_chip.position = Vector2(_credits_column.global_position.x, below)


func _tint() -> void:
	var tokens: StringName = EconomyPill.TOKENS
	_credits_glyph.modulate = get_theme_color(&"money", tokens)
	_power_glyph.modulate = get_theme_color(&"danger" if _low else &"money", tokens)


## The word shows in the bar on low power where it fits, else the numbers where they fit.
func _fit_bar_text() -> void:
	var room: float = _bar.size.x - 2.0 * UiScale.dp(TEXT_PAD_DP)
	_word.visible = _low and _word.get_combined_minimum_size().x <= room
	_numbers.visible = not _word.visible and _numbers.get_combined_minimum_size().x <= room


func _glyph(glyph_name: String, icon: String) -> TextureRect:
	var glyph: TextureRect = TextureRect.new()
	glyph.name = glyph_name
	glyph.texture = load(EconomyPill.ICON_ART % icon)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_min_dp(glyph, Vector2(GLYPH_DP, GLYPH_DP))
	_row.add_child(glyph)
	return glyph


func _build_bar() -> void:
	_bar.name = "PowerBar"
	_bar.theme_type_variation = EconomyPill.BAR_VARIATION
	_bar.show_percentage = false
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.max_value = 1.0
	_bar.value = 0.0
	_min_dp(_bar, BAR_DP)
	_row.add_child(_bar)
	_numbers.name = "PowerText"
	_numbers.variation = EconomyPill.NUMBER_VARIATION
	_numbers.edge_dp = TEXT_EDGE_DP
	_numbers.set_text("0/0")
	_word.name = "PowerWord"
	_word.text = "Low power"
	_word.uppercase = true
	_word.theme_type_variation = &"PillWord"
	_word.visible = false
	_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for overlay: Control in [_numbers, _word]:
		overlay.set_anchors_preset(Control.PRESET_HCENTER_WIDE)
		overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.add_child(overlay)
	_bar.resized.connect(_fit_bar_text)
	_word.minimum_size_changed.connect(_fit_bar_text)
	_numbers.minimum_size_changed.connect(_fit_bar_text)


func _build_chip() -> void:
	_chip.name = "Flash"
	_chip.theme_type_variation = EconomyPill.CHIP_LOSS_VARIATION
	_chip.top_level = true
	_chip.visible = false
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_text.name = "FlashText"
	_chip_text.variation = EconomyPill.CHIP_VARIATION
	_chip.add_child(_chip_text)
	add_child(_chip)


## Sizes are dp, so they follow a resize.
func _apply_dp() -> void:
	_row.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_chip_gap_px = UiScale.dp(CHIP_GAP_DP)
	_tint()
	_fit_bar_text()


static func _min_dp(control: Control, size_dp: Vector2) -> void:
	var min_size: DpMinSize = DpMinSize.new()
	min_size.min_dp = size_dp
	control.add_child(min_size)
