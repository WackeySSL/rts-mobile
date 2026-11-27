class_name MainMenu
extends MenuScreen
## The main menu (ADR 0043 section 5, ADR 0052 section 3, plans P524 and P664), after the Figma
## main menu: TREADLINE, its tagline in amber caps and the two sides (`SideNameRenew`,
## `SideNameFossil`) top left over the picture's dark side (`top_left`), then the numbered items
## as a grid: two columns where the measured width holds them (`TWO_COLUMNS_DP`, never the
## orientation), else one. Each item is a number, the word and an arrow: Continue (only while a
## resume file exists, so the numbers count the items shown), Skirmish, Tutorial, Rank
## (`RankScreen`), How to play and Settings; the first shown is filled amber. The commander is one
## thin profile line above the banner (`_footer`, a top rule and small caps; a tap opens the Rank
## screen), never a card. Then the version line and, at the foot, the real `AdBannerBand` on the
## start page (its 48 dp of air is the band's data). Every item leads through `MenuRoutes`: a
## route nobody registered yet leaves the item present and disabled, and enables when the route is
## registered later. It is a menu: no Command, no sim.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")
const TOKENS: StringName = &"HudTokens"
const ARROW: Texture2D = preload("res://assets/art/svg/ui/menu_arrow.svg")
const EMBLEM_DP: float = 32.0
const TWO_COLUMNS_DP: float = 560.0  ## The room at which the items stand in two columns,
const TWO_COLUMNS_MAX_DP: float = 600.0  ## taking at most this width.
const ITEM_PAD_DP: float = 14.0  ## The number's and the arrow's distance from the item's edge.
const NUMBER_DP: float = 28.0
const ARROW_DP: float = 18.0
const VERSION_SETTING: String = "application/config/version"
const SIDES: Array[Array] = [
	[
		preload("res://assets/art/svg/icons/emblem_fossil.svg"),
		MainMenuText.SIDE_FOSSIL,
		&"SideNameFossil"
	],
	[
		preload("res://assets/art/svg/icons/emblem_renew.svg"),
		MainMenuText.SIDE_RENEW,
		&"SideNameRenew"
	],
]

## The routes the buttons use; tests replace it.
var routes: MenuRoutes = MenuRoutes.shared
## Tests inject these two before the screen is pushed; null means the autoloads.
var progression: ProgressionScript = null
var ad_service: AdServiceScript = null
## Whether a resume file exists (ADR 0042 section 6); tests replace it.
var resume_check: Callable = func() -> bool: return ResumeStore.has_file()
## The notice key a failed restore left for this menu, taken once; tests replace it.
var take_notice: Callable = func() -> StringName: return MenuFlow.take_pending_notice()

var _continue: Button
var _routed: Dictionary[Button, StringName] = {}
var _numbers: Dictionary[Button, Label] = {}
var _arrows: Dictionary[Button, TextureRect] = {}
var _grid: GridContainer
var _footer: Button
var _rank_item: Button
var _progression: ProgressionScript
var _sides: HBoxContainer
var _names: Array[Label] = []


func _ready() -> void:
	top_left = true
	super()
	MainMenuText.register()
	_build_header()
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", roundi(UiScale.dp(GAP_DP)))
	_grid.add_theme_constant_override("v_separation", roundi(UiScale.dp(GAP_DP)))
	column.add_child(_grid)
	_continue = _route_button(MainMenuText.CONTINUE, MenuRoutes.CONTINUE)  # P515.
	_route_button(MainMenuText.SKIRMISH, MenuRoutes.SKIRMISH)  # P525.
	_route_button(MainMenuText.TUTORIAL, MenuRoutes.TUTORIAL)  # P544.
	_rank_item = _route_button(MainMenuText.RANK_ITEM, MenuRoutes.RANK)  # P664 (RankScreen).
	_route_button(MainMenuText.HOW_TO_PLAY, MenuRoutes.HOW_TO_PLAY)  # P527.
	_route_button(MainMenuText.SETTINGS, MenuRoutes.SETTINGS)  # P526.
	var notice: StringName = take_notice.call()
	if notice != &"":
		_label(tr(notice), &"PauseMuted")
	var version: String = _version()  # No key yet (P523 adds it): only the copyright shows.
	_label(
		tr(MainMenuText.VERSION) % version if version != "" else tr(MainMenuText.COPYRIGHT),
		&"PauseMuted"
	)
	_footer = Button.new()  # The profile line, between the scroll and the banner (P664).
	_footer.theme_type_variation = &"MenuFooter"
	_footer.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_footer.clip_text = true
	_footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = BUTTON_DP
	_footer.add_child(floor_dp)
	_footer.pressed.connect(_open.bind(MenuRoutes.RANK))
	slot.get_parent().add_child(_footer)
	slot.get_parent().move_child(_footer, slot.get_index())
	var band: AdBannerBand = AdBannerBand.new()
	band.start_page = true
	band.service = ad_service
	slot.host(band)
	_progression = progression if progression != null else (Progression as ProgressionScript)
	_listen()
	_refresh()
	_apply()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _continue != null:
		_listen()  # Back from a screen: the resume file and the routes may have changed.
		_refresh()
	elif what == NOTIFICATION_EXIT_TREE and _continue != null:
		routes.changed.disconnect(_refresh)
		_progression.xp_changed.disconnect(_refresh_profile)


func _listen() -> void:
	routes.changed.connect(_refresh)
	_progression.xp_changed.connect(_refresh_profile)


func _refresh() -> void:
	_continue.visible = resume_check.call()
	var shown: int = 0
	for button: Button in _routed:
		button.disabled = not routes.has(_routed[button])
		_arrows[button].visible = not button.disabled
		if button.visible:
			shown += 1
			_numbers[button].text = "%02d" % shown
			var first: bool = shown == 1
			button.theme_type_variation = &"MenuRowOn" if first else &"MenuRow"
			_numbers[button].theme_type_variation = &"MenuNumberOn" if first else &"MenuNumber"
			_arrows[button].modulate = _arrows[button].get_theme_color(
				&"ground_deep" if first else &"text", TOKENS
			)
	_footer.disabled = not routes.has(MenuRoutes.RANK)
	_refresh_profile()


## The profile line "COMMANDER · RANK 1 · 0 / 100 XP", and the title as the Rank item's hint.
func _refresh_profile() -> void:
	var rank: int = _progression.rank()
	var total: int = _progression.xp()
	var next_xp: int = _progression.next_rank_xp()
	var xp: String = (
		tr(MainMenuText.XP_TOP) % total
		if next_xp <= _progression.rank_floor_xp()
		else tr(MainMenuText.XP) % [total, next_xp]
	)
	_footer.text = tr(MainMenuText.PROFILE) % [rank, xp]
	_rank_item.text = tr(MainMenuText.RANK_HINT) % _progression.title(rank).to_upper()


func _open(route: StringName) -> void:
	var stack: MenuStack = get_parent() as MenuStack
	if stack != null and routes.has(route):
		stack.push(routes.make(route))


## An item (P664): a `MenuRow` of at least 48 dp holding its word, with its number on the left (in
## `text_mute`, set by `_refresh`) and the arrow on the right, both over it and taking no touch.
func _route_button(text_key: StringName, route: StringName) -> Button:
	var button: Button = Button.new()
	button.theme_type_variation = &"MenuRow"
	button.text = tr(text_key)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var floor_dp: DpMinSize = DpMinSize.new()
	floor_dp.min_dp = BUTTON_DP
	button.add_child(floor_dp)
	button.pressed.connect(_open.bind(route))
	var number: Label = Label.new()
	number.theme_type_variation = &"MenuNumber"
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(number)
	number.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	var arrow: TextureRect = TextureRect.new()
	arrow.texture = ARROW
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	button.add_child(arrow)
	_grid.add_child(button)
	_routed[button] = route
	_numbers[button] = number
	_arrows[button] = arrow
	return button


## The items shown, in order.
func items() -> Array[Button]:
	var shown: Array[Button] = []
	for button: Button in _routed:
		if button.visible:
			shown.append(button)
	return shown


func _build_header() -> void:
	_label(tr(MainMenuText.TITLE), &"MenuTitle")
	_label(tr(MainMenuText.TAGLINE).to_upper(), &"MenuEyebrow").autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	var sides: HBoxContainer = HBoxContainer.new()
	sides.alignment = BoxContainer.ALIGNMENT_BEGIN
	sides.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	column.add_child(sides)
	for index: int in range(SIDES.size()):
		if index == 1:
			var vs: Label = Label.new()
			vs.text = tr(MainMenuText.VS)
			sides.add_child(vs)
		var side: Array = SIDES[index]
		var emblem: TextureRect = TextureRect.new()
		emblem.texture = side[0] as Texture2D
		emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		emblem.custom_minimum_size = Vector2.ONE * UiScale.dp(EMBLEM_DP)
		sides.add_child(emblem)
		var name_label: Label = Label.new()
		name_label.text = tr(side[1] as StringName)
		name_label.theme_type_variation = side[2] as StringName
		sides.add_child(name_label)
		_names.append(name_label)
	_sides = sides
	_fit_names.call_deferred()


## The screen's layout hook: the row is fitted again once every handler of the resize has run.
func _apply() -> void:
	super()
	if _routed.is_empty() or not is_inside_tree():
		return
	var room: float = column_room_px()
	var two: bool = room >= UiScale.dp(TWO_COLUMNS_DP)
	_grid.columns = 2 if two else 1
	if two:
		column.custom_minimum_size.x = minf(room, UiScale.dp(TWO_COLUMNS_MAX_DP))
	var pad: float = UiScale.dp(ITEM_PAD_DP)
	for button: Button in _routed:
		var number: Label = _numbers[button]
		number.offset_left = pad
		number.offset_right = pad + UiScale.dp(NUMBER_DP)
		var arrow: TextureRect = _arrows[button]
		arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		arrow.offset_left = -(pad + UiScale.dp(ARROW_DP))
		arrow.offset_right = -pad
		arrow.offset_top = -UiScale.dp(ARROW_DP) * 0.5
		arrow.offset_bottom = UiScale.dp(ARROW_DP) * 0.5
	_fit_names.call_deferred()


## Compact and centred while the row's natural width fits the widest column the screen allows (the
## column grows to it); when it does not (a 360 dp phone held upright) the names take the room left
## and wrap by word. The emblems and "vs"
## keep their size.
func _fit_names() -> void:
	if _sides == null or not is_inside_tree():
		return
	var natural: float = 0.0
	for child: Node in _sides.get_children():
		var label: Label = child as Label
		if label != null and _names.has(label):
			var font: Font = label.get_theme_font("font")
			var size: int = label.get_theme_font_size("font_size")
			natural += font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
		else:
			natural += (child as Control).get_combined_minimum_size().x
	natural += _sides.get_theme_constant("separation") * (_sides.get_child_count() - 1)
	var wrap: bool = natural > column_room_px()  # The column grows to a row that fits.
	for label: Label in _names:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL if wrap else Control.SIZE_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF


func _label(text: String, variation: StringName) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	column.add_child(label)
	return label


func _version() -> String:
	return str(ProjectSettings.get_setting(VERSION_SETTING, "")).strip_edges()
