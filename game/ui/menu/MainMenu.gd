class_name MainMenu
extends MenuScreen
## The main menu (ADR 0043 section 5, ADR 0052 section 3, plans P524 and P664): TREADLINE, the two
## sides each in its accent's light (`SideNameRenew`, `SideNameFossil`) and the tagline over the
## picture's dark side (top left, `top_left`), then the items, each a number, the word and an arrow
## (Continue only while a resume file exists, so the numbers count the items shown; the first
## shown has the amber bar), and the commander card (`RankInsignia`, the rank title, the XP bar and
## the next unlock from `Progression`). The card stands beside the items where the measured width
## holds both, else above them, never by orientation. Then the version line and, at the foot, the
## real `AdBannerBand` on the start page (its 48 dp of air is the band's data). Every item leads
## through `MenuRoutes`: a route nobody registered yet leaves the item present and disabled, and
## enables when the route is registered later. It is a menu: no Command, no sim.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")
const ARROW: Texture2D = preload("res://assets/art/svg/ui/menu_arrow.svg")
const EMBLEM_DP: float = 32.0
const TWO_COLUMNS_DP: float = 600.0  ## The room at which the card stands beside the items.
const TWO_COLUMNS_MAX_DP: float = 640.0  ## ... and the most width the two columns take.
const ITEM_PAD_DP: float = 14.0  ## The number's and the arrow's distance from the item's edge.
const NUMBER_DP: float = 28.0
const ARROW_DP: float = 18.0
const XP_BAR_DP: float = 12.0
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
var catalog: MapCatalog = null  ## The map names of the next unlock; null means the data file.
## Whether a resume file exists (ADR 0042 section 6); tests replace it.
var resume_check: Callable = func() -> bool: return ResumeStore.has_file()
## The notice key a failed restore left for this menu, taken once; tests replace it.
var take_notice: Callable = func() -> StringName: return MenuFlow.take_pending_notice()

var _continue: Button
var _routed: Dictionary[Button, StringName] = {}
var _numbers: Dictionary[Button, Label] = {}
var _arrows: Dictionary[Button, TextureRect] = {}
var _body: BoxContainer
var _list: VBoxContainer
var _card: PanelContainer
var _insignia: RankInsignia
var _unlock_label: Label
var _rank_label: Label
var _xp_label: Label
var _xp_bar: ProgressBar
var _progression: ProgressionScript
var _sides: HBoxContainer
var _names: Array[Label] = []


func _ready() -> void:
	top_left = true
	super()
	MainMenuText.register()
	MapSelectText.register()
	_build_header()
	_body = BoxContainer.new()
	_body.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	column.add_child(_body)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_body.add_child(_list)
	_continue = _route_button(MainMenuText.CONTINUE, MenuRoutes.CONTINUE)  # P515.
	_route_button(MainMenuText.SKIRMISH, MenuRoutes.SKIRMISH)  # P525.
	_route_button(MainMenuText.TUTORIAL, MenuRoutes.TUTORIAL)  # P544.
	_route_button(MainMenuText.HOW_TO_PLAY, MenuRoutes.HOW_TO_PLAY)  # P527.
	_route_button(MainMenuText.SETTINGS, MenuRoutes.SETTINGS)  # P526.
	_build_card()
	var notice: StringName = take_notice.call()
	if notice != &"":
		_label(tr(notice), &"PauseMuted")
	var version: String = _version()  # No key yet (P523 adds it): only the copyright shows.
	_label(
		tr(MainMenuText.VERSION) % version if version != "" else tr(MainMenuText.COPYRIGHT),
		&"PauseMuted"
	)
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
		_progression.xp_changed.disconnect(_refresh_rank)


func _listen() -> void:
	routes.changed.connect(_refresh)
	_progression.xp_changed.connect(_refresh_rank)


func _refresh() -> void:
	_continue.visible = resume_check.call()
	var shown: int = 0
	for button: Button in _routed:
		button.disabled = not routes.has(_routed[button])
		_arrows[button].visible = not button.disabled
		if button.visible:
			shown += 1
			_numbers[button].text = "%02d" % shown
			button.theme_type_variation = &"MenuRowOn" if shown == 1 else &"MenuRow"
	_refresh_rank()


func _refresh_rank() -> void:
	var rank: int = _progression.rank()
	var total: int = _progression.xp()
	var floor_xp: int = _progression.rank_floor_xp()
	var next_xp: int = _progression.next_rank_xp()
	_insignia.rank = rank
	_insignia.max_rank = _progression.max_rank()
	_unlock_label.text = _unlock_text()
	_rank_label.text = tr(MainMenuText.RANK) % [rank, _progression.title(rank).to_upper()]
	_xp_bar.min_value = floor_xp
	_xp_bar.max_value = maxi(next_xp, floor_xp + 1)
	_xp_bar.value = total
	_xp_label.text = (
		tr(MainMenuText.XP_TOP) % total
		if next_xp <= floor_xp
		else tr(MainMenuText.XP) % [total, next_xp]
	)


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
	_list.add_child(button)
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
	_label(tr(MainMenuText.TAGLINE), &"").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## The screen's layout hook: the row is fitted again once every handler of the resize has run.
func _apply() -> void:
	super()
	if _body == null or not is_inside_tree():
		return
	var room: float = column_room_px()
	var beside: bool = room >= UiScale.dp(TWO_COLUMNS_DP)
	_body.vertical = not beside
	_body.move_child(_card, 1 if beside else 0)
	if beside:
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


## The commander card: the stripes and the rank title, the XP bar and the next unlock.
func _build_card() -> void:
	_card = PanelContainer.new()
	_card.theme_type_variation = &"MenuRankBadge"
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(_card)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	_card.add_child(rows)
	_add_to(rows, MainMenuText.CARD, &"MenuEyebrow")
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	rows.add_child(head)
	_insignia = RankInsignia.new()
	head.add_child(_insignia)
	_rank_label = _add_to(head, &"", &"MenuRankLabel")
	_rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rank_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = &"MenuXpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size.y = UiScale.dp(XP_BAR_DP)
	rows.add_child(_xp_bar)
	_xp_label = _add_to(rows, &"", &"")
	_add_to(rows, MainMenuText.NEXT, &"MenuEyebrow")
	_unlock_label = _add_to(rows, &"", &"")
	_unlock_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _add_to(parent: Control, text_key: StringName, variation: StringName) -> Label:
	var label: Label = Label.new()
	label.text = tr(text_key) if text_key != &"" else ""
	label.theme_type_variation = variation
	parent.add_child(label)
	return label


## The next unlock in words: the map's name or the computer's level, and the rank that opens it.
func _unlock_text() -> String:
	var next: Dictionary = _progression.next_unlock()
	if next.is_empty():
		return tr(MainMenuText.UNLOCK_DONE)
	var id: StringName = next[&"id"] as StringName
	var at: int = int(next[&"rank"])
	if next[&"kind"] == &"map":
		var maps: MapCatalog = catalog if catalog != null else load(MapCatalog.DEFAULT_PATH)
		var title: String = maps.title(id)
		return tr(MainMenuText.UNLOCK_MAP) % [title if title != "" else str(id), at]
	var word: StringName = MapSelect.LEVEL_TEXT.get(id, &"") as StringName
	var level: String = tr(word).capitalize() if word != &"" else str(id)
	return tr(MainMenuText.UNLOCK_OPPONENT) % [level, at]


func _label(text: String, variation: StringName) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	column.add_child(label)
	return label


func _version() -> String:
	return str(ProjectSettings.get_setting(VERSION_SETTING, "")).strip_edges()
