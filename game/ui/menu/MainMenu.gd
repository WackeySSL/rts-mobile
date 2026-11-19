class_name MainMenu
extends MenuScreen
## The main menu (ADR 0043 section 5, ADR 0025 section 12, plan P524): TREADLINE, the two sides
## each in its accent's light (`SideNameRenew`, `SideNameFossil`), the tagline, Continue (only
## while a resume file exists), Skirmish, Tutorial, How to play, Settings, the rank line and XP
## bar (`Progression`; `MenuRankLabel` and `MenuXpBar`, the plate `MenuRankBadge` is for screens
## that frame it), the version line and, at the foot, the real `AdBannerBand` on the start page
## (its 48 dp of air is the band's data). Every button leads through `MenuRoutes`: a route nobody
## registered yet leaves the button present and disabled, and enables when the route is
## registered later. It is a menu: no Command, no sim.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const AdServiceScript: GDScript = preload("res://game/ads/AdService.gd")
const EMBLEM_DP: float = 32.0
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
## Whether a resume file exists (ADR 0042 section 6); tests replace it.
var resume_check: Callable = func() -> bool: return ResumeStore.has_file()
## The notice key a failed restore left for this menu, taken once; tests replace it.
var take_notice: Callable = func() -> StringName: return MenuFlow.take_pending_notice()

var _continue: Button
var _routed: Dictionary[Button, StringName] = {}
var _rank_label: Label
var _xp_label: Label
var _xp_bar: ProgressBar
var _progression: ProgressionScript
var _sides: HBoxContainer
var _names: Array[Label] = []


func _ready() -> void:
	super()
	MainMenuText.register()
	_build_header()
	_continue = _route_button(MainMenuText.CONTINUE, MenuRoutes.CONTINUE)  # P515.
	_route_button(MainMenuText.SKIRMISH, MenuRoutes.SKIRMISH)  # P525.
	_route_button(MainMenuText.TUTORIAL, MenuRoutes.TUTORIAL)  # P544.
	_route_button(MainMenuText.HOW_TO_PLAY, MenuRoutes.HOW_TO_PLAY)  # P527.
	_route_button(MainMenuText.SETTINGS, MenuRoutes.SETTINGS)  # P526.
	_build_rank()
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
	for button: Button in _routed:
		button.disabled = not routes.has(_routed[button])
	_refresh_rank()


func _refresh_rank() -> void:
	var rank: int = _progression.rank()
	var total: int = _progression.xp()
	var floor_xp: int = _progression.rank_floor_xp()
	var next_xp: int = _progression.next_rank_xp()
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


func _route_button(text_key: StringName, route: StringName) -> Button:
	var button: Button = add_button(tr(text_key), _open.bind(route))
	_routed[button] = route
	return button


func _build_header() -> void:
	_label(tr(MainMenuText.TITLE), &"MenuTitle")
	var sides: HBoxContainer = HBoxContainer.new()
	sides.alignment = BoxContainer.ALIGNMENT_CENTER
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
	if _sides != null:
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


func _build_rank() -> void:
	_rank_label = _label("", &"MenuRankLabel")
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = &"MenuXpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size.y = UiScale.dp(XP_BAR_DP)
	column.add_child(_xp_bar)
	_xp_label = _label("", &"")


func _label(text: String, variation: StringName) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(label)
	return label


func _version() -> String:
	return str(ProjectSettings.get_setting(VERSION_SETTING, "")).strip_edges()
