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
## Whether a resume file exists. TODO(P515): ResumeStore (ADR 0042 section 6) replaces this seam.
var resume_check: Callable = func() -> bool: return false

var _continue: Button
var _routed: Dictionary[Button, StringName] = {}
var _rank_label: Label
var _xp_label: Label
var _xp_bar: ProgressBar
var _progression: ProgressionScript


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
		# The names give way (wrap) on a narrow phone; the emblems and "vs" keep their size.
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size.x = 0.0
		sides.add_child(name_label)
	_label(tr(MainMenuText.TAGLINE), &"").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


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
