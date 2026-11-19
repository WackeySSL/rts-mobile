extends RefCounted
## The rig of the P421 suites (tests/e2e/test_ads_end_to_end.gd and test_ads_never_answers.gd). Not
## a suite. It builds what Phase 5 and 6 ship, on the existing fakes, and drives it the way a
## player does:
## - a real `AdService` (AdServiceHarness: fake ad, consent and billing backends, an injected clock
##   `h.clock_ms`, so no wait is real) and a real MenuFlow, which only differ from the autoloads in
##   their scene changes (the main scene is added to the suite, the "menu" is a counter);
## - the real screens on a MenuStack: MainMenu (the band), MapSelect (the START button and the
##   +500 offer), SettingsScreen (the Remove ads row), the main scene's ResultScreen (Back, the
##   Double XP offer);
## - a match is ended the way the existing flow tests end it: a SURRENDER and one tick. `ticks`
##   says how long it ran, which is what the interstitial caps count.
## The suite calls `open` in `before_test` and `close` in `after_test`.

const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const FLOW_SCRIPT: String = "res://game/ui/menu/menu_flow_service.gd"
const FRAMES_LIMIT: int = 240
const SEED: int = 4242
const SKIRMISH: String = "res://data/scenarios/skirmish_kestrel_flats.tres"
const DUMMY: String = "res://data/ai/dummy_renew.tres"
const LEVEL: String = "res://data/ai/difficulty/hard.tres"

var suite: GdUnitTestSuite
var h: AdServiceHarness
var ads: Node
var fake: FakeAdBackend
var flow: Node
var progression: Node
var settings: AdsSettingsDef
var mains: Array[Node] = []
var menus: int = 0
var menu: Control
var stack: MenuStack
var screen: MenuScreen
## The clock the offers and the Remove ads rows read for their arm delay (see `press`).
var tap_ms: int = 0
var _window_before: Vector2i = Vector2i.ZERO


func _init(owner: GdUnitTestSuite) -> void:
	suite = owner


## A service with consent answered (or not, `consent` false: ads may not be requested), the flow
## and a rank-1 progression (on the harness's save file) for the menus.
func open(consent: bool = true) -> void:
	MenuRig.begin()
	# The base size, so a band lines up with the safe rect's bottom as it does on a phone.
	_window_before = suite.get_window().size
	UiScale.set_override(UiProfiles.all()[&"desktop"])
	suite.get_window().size = Vector2i(1280, 720)
	h = AdServiceHarness.new()
	ads = suite.auto_free(h.make(consent))
	suite.add_child(ads)
	fake = AdServiceHarness.fake(ads)
	settings = AdsSettingsDef.load_default()
	progression = ProgressionScript.new()
	progression.bind(h.save_service(), null)
	flow = suite.auto_free((load(FLOW_SCRIPT) as GDScript).new())
	suite.add_child(flow)
	flow.ads = ads
	flow.seed_source = func() -> int: return SEED
	flow.switch_to_main = _enter_main
	flow.switch_to_menu = _enter_menu
	tap_ms = Time.get_ticks_msec()
	mains.clear()
	menus = 0


func close() -> void:
	CommandQueue.clear()
	close_menu()
	if is_instance_valid(flow):
		flow.return_to_menu()
	for main: Node in mains:
		if is_instance_valid(main):
			suite.remove_child(main)
			main.free()
	mains.clear()
	if is_instance_valid(progression):
		progression.free()
	h.dispose()
	UiScale.clear_override()
	suite.get_window().size = _window_before
	MenuRig.end()


func close_menu() -> void:
	if menu != null and is_instance_valid(menu):
		suite.remove_child(menu)
		menu.free()
	menu = null
	stack = null
	screen = null


## Puts `next` alone on a fresh menu stack (the slide is 0 ms) and lets it settle.
func show(next: MenuScreen) -> void:
	close_menu()
	menu = (load(MENU_SCENE) as PackedScene).instantiate()
	suite.add_child(menu)
	stack = menu.get_node("MenuStack") as MenuStack
	stack.slide_ms = 0
	screen = next
	stack.push(next)
	await frames(3)


func main_menu() -> MainMenu:
	var main: MainMenu = MainMenu.new()
	main.routes = MenuRoutes.new()
	main.progression = progression
	main.ad_service = ads
	main.resume_check = func() -> bool: return false
	main.take_notice = func() -> StringName: return &""
	return main


func map_select() -> MapSelect:
	var map: MapSelect = MapSelect.new()
	map.progression = progression
	map.flow = flow
	return map


## The map select on the stack with its offer on this rig's service and clock.
func show_map_select() -> MapSelect:
	var map: MapSelect = map_select()
	await show(map)
	map.offer.use_service(ads)
	map.offer.now_ms = func() -> int: return tap_ms
	await frames(3)
	return map


## The settings screen (not in a match: the Remove ads rows are there) on this service.
func show_settings() -> SettingsScreen:
	var settings_screen: SettingsScreen = SettingsScreen.new()
	settings_screen.routes = MenuRoutes.new()
	settings_screen.ad_service = ads
	settings_screen.dev_enabled = func() -> bool: return false
	settings_screen.in_match = func() -> bool: return false
	await show(settings_screen)
	var rows: RemoveAdsRows = settings_screen.remove_rows
	rows.now_ms = func() -> int: return tap_ms
	return settings_screen


## A setup for a start that does not go through the map select (the flow's own entry).
func make_setup() -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.scenario_path = SKIRMISH
	var opponents: Array[AiDef] = [load(DUMMY) as AiDef]
	setup.opponents = opponents
	var levels: Array[AiDifficultyDef] = [load(LEVEL) as AiDifficultyDef]
	setup.opponent_levels = levels
	return setup


func band() -> AdBannerBand:
	for node: Node in menu.find_children("*", "AdBannerBand", true, false):
		return node as AdBannerBand
	return null


## A tap on `button` after the arm delay of the offers and rows (`reward_arm_ms`).
func press(button: Button) -> void:
	tap_ms = maxi(tap_ms, Time.get_ticks_msec()) + settings.reward_arm_ms + 1
	button.pressed.emit()


## START on the map select. Returns when the flow has built the match (or, with `wait` false,
## right after the tap).
func start_match(map: MapSelect, wait: bool = true) -> void:
	press(map._start)
	if wait:
		await until(func() -> bool: return flow.current_runner() != null)


## The match that runs now ends after `ticks` ticks (one is enough where play time is not the
## point) with a SURRENDER of the local player, as the flow tests end it.
func end_match(ticks: int) -> void:
	var runner: MatchRunner = flow.current_runner()
	if ticks > 1:
		runner.run_ticks(ticks - 1)
	CommandQueue.submit(Command.surrender(flow.current_setup().scenario().local_player))
	runner.run_ticks(1)
	await frames(2)


## The ResultScreen of the newest main scene.
func result() -> ResultScreen:
	return mains.back().get_node("Hud/ResultScreen") as ResultScreen


## Back on the result screen (the flow's `leave_match`), awaited until the menu opens.
func leave(wait: bool = true) -> void:
	var before: int = menus
	press(result().find_child("BackButton", true, false) as Button)
	if wait:
		await until(func() -> bool: return menus > before)


## Interstitials the backend has shown.
func interstitials() -> int:
	return fake.shows.count(AdBackend.KIND_INTERSTITIAL)


func rewarded() -> int:
	return fake.shows.count(AdBackend.KIND_REWARDED)


## Process frames until `done` holds (at most FRAMES_LIMIT); the caller asserts the outcome.
func until(done: Callable) -> void:
	for _i: int in FRAMES_LIMIT:
		if bool(done.call()):
			return
		await frames(1)


func frames(count: int) -> void:
	await AdServiceHarness.frames(count)


## Adds the main scene to the suite's tree and hands its result screen to this flow and service.
func _enter_main(main: Node) -> Error:
	mains.append(main)
	suite.add_child(main)
	var result_screen: ResultScreen = main.get_node("Hud/ResultScreen") as ResultScreen
	result_screen.flow = flow
	result_screen.offer.use_service(ads)
	result_screen.offer.now_ms = func() -> int: return tap_ms
	return OK


func _enter_menu() -> Error:
	menus += 1
	return OK
