class_name GuideCardFit
extends RefCounted
## The coach mark's card: its node tree and how it is sized (ADR 0048 sections 1 and 2). `build`
## makes the tree once; `fit` gives it a width and the height its wrapped text needs, on each
## layout. `CoachMark` keeps what changes (the dock, the tab, the modal); the parts stand here.

const BUTTON_GAP_DP: float = 12.0  ## Between Skip and Next: a slip must not end the lesson.
const TAB_CLEAR_DP: float = 8.0  ## The least between the tab's rect and a card button's.
const MIN_TEXT_DP: float = 120.0  ## The least width of the prompt beside the buttons' column.
const MIN_TARGET_DP: float = GuideRing.MIN_TARGET_DP

var card: PanelContainer
var prompt: Label
var hint: Label
var row: BoxContainer  ## Skip and Next: a row, stacked where the dock is too narrow for both.
var head: HBoxContainer  ## Narrow form: the lesson's short title and room for the tab.
var title: Label
var head_pad: Control
var main: BoxContainer  ## The prompt and the buttons: side by side (wide) or one over the other.
var side_box: BoxContainer  ## The buttons' column (wide: under the tab's room, else beside it).
var side_pad: Control
var scroll: ScrollContainer  ## The prompt and hint: scrolls where the dock is too short.
var content: VBoxContainer
var skip: Button
var next: Button


## Makes the card and its parts, the card in theme variation `variation`. The caller adds `card`
## to the tree and connects `skip` and `next`.
func build(variation: StringName) -> void:
	card = PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = variation
	card.mouse_filter = Control.MOUSE_FILTER_STOP  # Taps on the card are not map taps.
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	prompt = Label.new()
	prompt.name = "Prompt"
	prompt.theme_type_variation = &"GuidePrompt"
	hint = Label.new()
	hint.name = "Hint"
	hint.theme_type_variation = &"PauseMuted"
	hint.text = tr("Stuck? Try what the card says, or leave from the menu.")
	head = HBoxContainer.new()
	head.name = "Head"
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = Label.new()
	title.name = "Title"
	title.theme_type_variation = &"PauseMuted"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_pad = _pad("HeadPad")
	head.add_child(title)
	head.add_child(head_pad)
	column.add_child(head)
	main = BoxContainer.new()
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(main)
	scroll = ScrollContainer.new()
	scroll.name = "PromptScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER  # A drag scrolls.
	main.add_child(scroll)
	content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(content)
	for label: Label in [prompt, hint]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(label)
	side_box = BoxContainer.new()
	side_box.name = "Side"
	side_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(side_box)
	side_pad = _pad("SidePad")
	side_box.add_child(side_pad)
	row = BoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_END
	side_box.add_child(row)
	skip = _button("Skip", "SKIP LESSON", &"PauseButton")
	next = _button("Next", "NEXT", &"PausePrimary")


## The row, the head and the side pads, the buttons and the gaps at `dp`: a resize, never a frame.
func apply_metrics(dp: float) -> void:
	for box: Container in [row, main]:
		box.add_theme_constant_override("separation", roundi(BUTTON_GAP_DP * dp))
	var least: Vector2 = Vector2(MIN_TARGET_DP, MIN_TARGET_DP) * dp
	for button: Button in [skip, next]:
		button.custom_minimum_size = least
	for pad: Control in [head_pad, side_pad]:
		pad.custom_minimum_size = least


## An empty spacer of a touch target's size: the tab stands over it.
func _pad(node_name: String) -> Control:
	var pad: Control = Control.new()
	pad.name = node_name
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pad


## A card button, at least 48 dp each way.
func _button(node_name: String, text: String, variation: StringName) -> Button:
	var button: Button = Button.new()
	button.name = node_name
	button.text = tr(text)
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(button)
	return button


## Gives the card `width` px, never more, and the height its wrapped text needs at that width, at
## most `max_height`: past that the prompt scrolls in its own area and the buttons keep their foot
## row. The row stacks where the width cannot hold Skip and Next side by side. Returns the size. The
## labels' and the box's cached minimums are dropped first, or the height read is the one of the
## width before.
func fit(
	width: float, max_height: float, dp: float, mirror: bool, settings: GuideSettingsDef
) -> Vector2:
	var margin: Vector2 = card.get_theme_stylebox(&"panel").get_minimum_size()
	var inner: float = floorf(width - margin.x)  # Whole px: a label is never over.
	var gap: float = BUTTON_GAP_DP * dp
	var least: float = ceilf(MIN_TARGET_DP * dp)  # A button's minimum is whole px.
	# Wide by the dock's width, and in any landscape dock: a head row would cost 48 dp of the 126 dp
	# a small phone's dock has (ADR 0048 section 2, deviation noted there).
	var wide: bool = width >= settings.card_wide_dp * dp or not HudLayout.is_portrait()
	var across: float = 0.0
	var widest: float = least
	var count: int = 0
	for button: Button in [skip, next]:
		button.clip_text = false
		button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		if button.visible:
			count += 1
			var button_width: float = CoachButtonWidth.of(button, MIN_TARGET_DP * dp)
			widest = maxf(widest, button_width)
			across += button_width + (gap if across > 0.0 else 0.0)
	if wide and inner - widest - gap < MIN_TEXT_DP * dp:
		wide = false  # Not even a column beside the prompt leaves it its least width.
	var text_width: float = inner
	head.visible = not wide
	side_pad.visible = wide
	main.vertical = not wide
	main.move_child(side_box, 0 if mirror and wide else 1)
	head.move_child(head_pad, 0 if mirror else 1)
	side_box.visible = wide or count > 0
	row.visible = count > 0  # An action beat has no button: the row takes no height.
	if wide:  # The buttons go under the tab, stacked or in a row, else beside it, by the height.
		var stacked: float = count * least + maxf(count - 1.0, 0.0) * gap
		# The tab stands at the card's corner, the pad `margin.top` below it: the real gap between
		# the tab and the button under it is that margin plus the separation (at least 8 dp).
		var top_margin: float = card.get_theme_stylebox(&"panel").get_margin(SIDE_TOP)
		var tight: float = maxf(TAB_CLEAR_DP * dp - top_margin, 0.0)
		var avail: float = max_height - margin.y
		var beside: bool = count > 0 and least + tight + least > avail
		var side: float = least
		if count > 0:
			side = across + gap + least if beside else maxf(least, across)
		var under: bool = not beside and least + tight + stacked <= avail
		var squeezed: bool = false  # No column fits the height either: the row keeps its words.
		if count > 0 and inner - side - gap < MIN_TEXT_DP * dp:  # Too little left for the prompt:
			squeezed = least + tight + stacked > avail
			if not squeezed:  # the buttons stack in a column under the tab.
				beside = false
				under = true
		if under:
			side = widest if count > 0 else least
		side_box.vertical = not beside
		side_box.move_child(side_pad, 0 if mirror or not beside else 1)
		row.vertical = under
		var below: float = stacked if under else least  # The row's height under the tab.
		side_box.add_theme_constant_override(
			"separation",
			roundi(gap) if beside else floori(clampf(avail - least - below, tight, gap))
		)
		side_box.custom_minimum_size.x = side
		text_width = maxf(inner - side - gap, minf(MIN_TEXT_DP * dp, inner))
		if squeezed:  # The prompt takes what is left and scrolls in it.
			text_width = maxf(inner - side - gap, 0.0)
	else:
		side_box.vertical = true
		row.vertical = across > inner
		side_box.custom_minimum_size.x = 0.0
	for button: Button in [skip, next]:
		# Stacked, a button is as wide as the card: only there may a longer text be trimmed.
		var own: float = CoachButtonWidth.of(button, MIN_TARGET_DP * dp)
		var trim: bool = row.vertical and not wide and own > inner
		button.clip_text = trim
		button.text_overrun_behavior = (
			TextServer.OVERRUN_TRIM_ELLIPSIS if trim else TextServer.OVERRUN_NO_TRIMMING
		)
	for box: Container in [row, side_box, main]:  # A button's trim drops its minimum: sort again.
		box.update_minimum_size()
		box.queue_sort()
	for label: Label in [prompt, hint]:  # The wrapped height needs the width first.
		label.custom_minimum_size.x = text_width
		label.size.x = text_width
		label.update_minimum_size()
	content.custom_minimum_size.x = text_width
	content.update_minimum_size()
	var column: Control = main.get_parent() as Control
	var sep: float = column.get_theme_constant(&"separation")
	var used: float = margin.y
	if not wide:
		used += least + sep
		if count > 0:
			used += row.get_combined_minimum_size().y + gap  # `main`'s own separation.
	var room: float = maxf(floorf(max_height - used), 0.0)
	scroll.custom_minimum_size = Vector2(
		text_width, minf(content.get_combined_minimum_size().y, room)
	)
	main.update_minimum_size()
	column.update_minimum_size()
	card.custom_minimum_size = Vector2(width, 0.0)
	card.update_minimum_size()
	card.size = Vector2(width, card.get_combined_minimum_size().y)
	return card.size
