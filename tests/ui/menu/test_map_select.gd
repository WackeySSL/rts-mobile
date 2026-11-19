extends GdUnitTestSuite
## The map select (plan P525): the layout at the six sizes of ADR 0015 section 6 (inside the safe
## area, 48 dp targets, the banner slot at the safe bottom), the locks of ADR 0045, START (one
## setup, a second tap does nothing, a refusal keeps the button live), the catalog pinned against
## the scenario files, and no ad word.

const ScreenSizes: GDScript = preload("res://tests/support/screen_sizes.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const AdBandAsserts: GDScript = preload("res://tests/ui/support/ad_band_asserts.gd")
const FakeRank: GDScript = preload("res://tests/ui/support/fake_rank_progression.gd")
const FakeFlow: GDScript = preload("res://tests/ui/support/fake_start_flow.gd")
const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const SCREEN_SOURCE: String = "res://game/ui/menu/MapSelect.gd"
const TOLERANCE_PX: float = 0.5

var _window_size_before: Vector2i
var _quit_on_go_back_before: bool = true
var _menu: Control
var _stack: MenuStack
var _screen: MapSelect
var _progression: Node
var _flow: Node
var _ads: Node
var _harness: RefCounted
var _catalog: MapCatalog  ## The real one.
var _shown: MapCatalog  ## What the screen gets: a copy of the real one (map 2 is locked).


func before() -> void:
	_window_size_before = get_window().size


func after() -> void:
	get_window().size = _window_size_before


func before_test() -> void:
	_quit_on_go_back_before = get_tree().quit_on_go_back
	_progression = FakeRank.new()
	_flow = FakeFlow.new()
	_catalog = load(MapCatalog.DEFAULT_PATH) as MapCatalog
	_shown = _catalog_copy()


func after_test() -> void:
	get_tree().quit_on_go_back = _quit_on_go_back_before
	UiScale.clear_override()
	_close()
	for node: Node in [_ads, _progression, _flow]:
		if is_instance_valid(node):
			node.free()
	_ads = null
	if _harness != null:
		_harness.dispose()
		_harness = null


func test_layout_at_the_six_sizes() -> void:
	for size: Vector2i in ScreenSizes.ALL:
		await _open(_profile_with_window(size), true)
		var label: String = str(size)
		var safe: Rect2 = UiScale.safe_rect_base().grow(TOLERANCE_PX)
		var column_rect: Rect2 = _screen.column.get_global_rect()
		assert_float(column_rect.position.x).override_failure_message(label).is_greater_equal(
			safe.position.x
		)
		assert_float(column_rect.end.x).override_failure_message(label).is_less_equal(safe.end.x)
		(
			assert_bool(safe.encloses(_screen.scroll.get_global_rect()))
			. override_failure_message(label)
			. is_true()
		)
		var shown: int = 0
		for button: Button in _buttons():
			shown += 1
			(
				assert_float(button.get_global_rect().size.y)
				. override_failure_message(label)
				. is_greater_equal(UiScale.dp(48.0) - TOLERANCE_PX)
			)
			_screen.scroll.ensure_control_visible(button)
			await await_idle_frame()
			(
				assert_bool(
					_screen.scroll.get_global_rect().grow(TOLERANCE_PX).encloses(
						button.get_global_rect()
					)
				)
				. override_failure_message(label)
				. is_true()
			)
		# Three maps, two sides, three levels and START.
		assert_int(shown).override_failure_message(label).is_equal(9)
		var band: AdBannerBand = _screen.slot.get_child(0) as AdBannerBand
		AdBandAsserts.assert_lines_up(self, band, _ads, _screen.scroll, band.gap_dp(), label)
		(
			assert_float(_screen.slot.get_global_rect().end.y)
			. override_failure_message(label)
			. is_equal_approx(UiScale.safe_rect_base().end.y, TOLERANCE_PX)
		)
		_close()
		UiScale.clear_override()


func test_the_offer_slot_is_empty_and_the_banner_slot_has_no_band_of_its_own() -> void:
	await _open(_profile_with_window(ScreenSizes.PORTRAIT[0]), false, false)
	var offer: OfferSlot = _screen.column.get_node("OfferSlot") as OfferSlot
	assert_object(offer.owner).is_same(_screen)
	assert_int(offer.get_child_count()).is_equal(0)
	assert_bool(offer.visible).is_false()
	assert_bool(_screen.slot.has_band()).is_false()
	assert_float(_screen.slot.size.y).is_equal_approx(0.0, 0.01)


func test_locks_follow_the_rank() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	assert_bool(_screen._maps[&"kestrel_flats"].disabled).is_false()
	assert_bool(_screen._maps[&"map_2"].disabled).is_true()
	assert_str(_screen._maps[&"map_2"].text).contains("RANK 2")
	assert_bool(_screen._maps[&"map_3"].disabled).is_true()
	assert_str(_screen._maps[&"map_3"].text).contains("RANK 4")
	assert_bool(_screen._levels[&"normal"].disabled).is_false()
	assert_bool(_screen._levels[&"hard"].disabled).is_true()
	assert_str(_screen._levels[&"hard"].text).contains("RANK 3")
	for locked: StringName in [&"map_2", &"map_3"]:
		assert_str(String(_screen._map_cards[locked].theme_type_variation)).is_equal(
			"MenuMapCardLocked"
		)
	assert_str(String(_screen._map_cards[&"kestrel_flats"].theme_type_variation)).is_equal(
		"MenuMapCardOn"
	)
	# Picked against unpicked: the side card and the level chip.
	assert_str(String(_screen._side_cards[&"fossil"].theme_type_variation)).is_equal(
		"MenuSideCardFossil"
	)
	assert_str(String(_screen._side_cards[&"renew"].theme_type_variation)).is_equal("MenuSideCard")
	assert_str(String(_screen._levels[&"normal"].theme_type_variation)).is_equal("MenuTabOn")
	assert_str(String(_screen._levels[&"easy"].theme_type_variation)).is_equal("MenuTab")
	_screen._sides[&"renew"].pressed.emit()
	assert_str(String(_screen._side_cards[&"renew"].theme_type_variation)).is_equal(
		"MenuSideCardRenew"
	)
	assert_str(String(_screen._side_cards[&"fossil"].theme_type_variation)).is_equal("MenuSideCard")
	_progression.rank_now = 3
	_progression.xp_changed.emit()
	assert_bool(_screen._maps[&"map_2"].disabled).is_false()
	assert_bool(_screen._levels[&"hard"].disabled).is_false()
	_screen._levels[&"hard"].pressed.emit()
	assert_str(String(_screen.level)).is_equal("hard")
	assert_str(String(_screen._levels[&"hard"].theme_type_variation)).is_equal("MenuTabOn")
	assert_str(String(_screen._levels[&"normal"].theme_type_variation)).is_equal("MenuTab")
	_screen._maps[&"map_2"].pressed.emit()
	assert_str(String(_screen._map_cards[&"map_2"].theme_type_variation)).is_equal("MenuMapCardOn")
	assert_str(String(_screen._map_cards[&"kestrel_flats"].theme_type_variation)).is_equal(
		"MenuMapCard"
	)
	assert_str(_screen._levels[&"hard"].text).starts_with("> ")


func test_a_locked_start_sends_nothing() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	_screen.level = &"hard"  # Set past the closed chip: START checks the locks itself.
	_screen._on_start()
	assert_int(_flow.started.size()).is_equal(0)
	_screen.level = &"normal"
	_screen.map_id = &"map_2"
	_screen._on_start()
	assert_int(_flow.started.size()).is_equal(0)


func test_the_defaults_skip_a_locked_map_and_no_open_map_keeps_start_off() -> void:
	_shown.entries.reverse()  # The locked map comes first.
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	assert_str(String(_screen.map_id)).is_equal("kestrel_flats")
	_close()
	_shown = MapCatalog.new()  # Empty.
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	assert_str(String(_screen.map_id)).is_empty()
	assert_bool(_screen._start.disabled).is_true()


func test_start_sends_one_setup_and_a_second_tap_does_nothing() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	_screen._levels[&"easy"].pressed.emit()
	_screen._start.pressed.emit()
	_screen._start.pressed.emit()
	await await_idle_frame()
	assert_int(_flow.started.size()).is_equal(1)
	var setup: MatchSetup = _flow.started[0]
	assert_str(setup.scenario_path).is_equal("res://data/scenarios/skirmish_kestrel_flats.tres")
	assert_str(String(setup.map_id)).is_equal("kestrel_flats")
	assert_int(setup.opponents.size()).is_equal(1)
	assert_str(String(setup.opponents[0].id)).is_equal("opponent_renew")
	assert_str(String(setup.opponent_levels[0].id)).is_equal("easy")
	assert_bool(_screen._start.disabled).is_true()
	_flow.release.emit()
	await await_idle_frame()
	_screen._start.pressed.emit()
	assert_int(_flow.started.size()).is_equal(1)  # Started: the screen stays closed to taps.


func test_start_reads_starting_while_the_match_is_prepared() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	assert_str(_screen._start.text).is_equal(tr(MapSelectText.START))
	_screen._start.pressed.emit()
	assert_str(_screen._start.text).is_equal(tr(MapSelectText.STARTING))
	assert_bool(_screen._start.disabled).is_true()
	_flow.release.emit()
	await await_idle_frame()


func test_back_does_nothing_while_the_match_starts_and_pops_otherwise() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	assert_bool(_screen.on_back()).is_false()
	_screen._start.pressed.emit()
	assert_bool(_screen.on_back()).is_true()
	_flow.release.emit()
	await await_idle_frame()


func test_a_refused_start_restores_the_start_label() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	_flow.refuse = ERR_BUSY
	await (
		assert_error(func() -> void: _screen._start.pressed.emit())
		. is_push_warning("MapSelect: the match did not start (Busy)")
	)
	assert_str(_screen._start.text).is_equal(tr(MapSelectText.START))
	assert_bool(_screen._start.disabled).is_false()


func test_the_other_side_plays_the_mirrored_scenario_against_the_derrick_league() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	_screen._sides[&"renew"].pressed.emit()
	var setup: MatchSetup = _screen.build_setup()
	assert_str(setup.scenario_path).is_equal(
		"res://data/scenarios/skirmish_kestrel_flats_mirrored.tres"
	)
	assert_str(String(setup.opponents[0].id)).is_equal("opponent_fossil")


func test_a_refused_start_keeps_the_button_live() -> void:
	await _open(_profile_with_window(ScreenSizes.LANDSCAPE[0]), false)
	var words: Dictionary[Error, String] = {ERR_BUSY: "Busy", ERR_INVALID_DATA: "Invalid data"}
	for error: Error in words:
		_flow.refuse = error
		await (
			assert_error(func() -> void: _screen._start.pressed.emit())
			. is_push_warning("MapSelect: the match did not start (%s)" % words[error])
		)
		assert_bool(_screen._start.disabled).is_false()
	assert_int(_flow.started.size()).is_equal(2)
	_flow.refuse = OK
	_screen._start.pressed.emit()
	await await_idle_frame()
	assert_int(_flow.started.size()).is_equal(3)
	_flow.release.emit()


func test_the_catalog_lists_all_maps_and_pins_their_scenario_files() -> void:
	assert_array(_catalog.map_ids()).is_equal([&"kestrel_flats", &"map_2", &"map_3"])
	assert_str(_catalog.title(&"kestrel_flats")).is_equal("Kestrel Flats")
	assert_str(_catalog.title(&"map_2")).is_equal("Heron Fords")
	assert_str(_catalog.title(&"map_3")).is_equal("Curlew Crags")
	var stems: Array[String] = [
		"skirmish_kestrel_flats", "skirmish_heron_fords", "skirmish_curlew_crags"
	]
	var maps: Array[String] = [
		"res://data/maps/kestrel_flats.tres",
		"res://data/maps/heron_fords.tres",
		"res://data/maps/curlew_crags.tres"
	]
	for index: int in stems.size():
		var on_disk: Array[String] = []
		for file_name: String in DirAccess.get_files_at("res://data/scenarios"):
			if file_name.begins_with(stems[index]) and file_name.ends_with(".tres"):
				on_disk.append("res://data/scenarios/" + file_name)
		on_disk.sort()
		var listed: Array[String] = []
		for row: Dictionary in _catalog.entries[index][MapCatalog.KEY_SCENARIOS] as Array:
			listed.append(row[MapCatalog.KEY_PATH] as String)
		listed.sort()
		assert_array(listed).is_equal(on_disk)
		var map: MapDef = load(maps[index]) as MapDef
		var combos: Dictionary = {}
		for row: Dictionary in _catalog.entries[index][MapCatalog.KEY_SCENARIOS] as Array:
			var scenario: ScenarioDef = load(row[MapCatalog.KEY_PATH] as String) as ScenarioDef
			assert_object(scenario).is_not_null()
			assert_object(scenario.map).is_same(map)
			assert_str(String(scenario.factions[1].id)).is_equal(String(row[MapCatalog.KEY_PLAYER]))
			assert_str(String(scenario.factions[2].id)).is_equal(
				String(row[MapCatalog.KEY_OPPONENT])
			)
			combos["%s/%s" % [row[MapCatalog.KEY_PLAYER], row[MapCatalog.KEY_OPPONENT]]] = true
		assert_int(combos.size()).is_equal(4)  # Both sides and their mirrors.
	assert_str(_catalog.scenario_path(&"kestrel_flats", &"fossil", &"renew")).is_not_empty()
	assert_str(_catalog.scenario_path(&"map_2", &"renew", &"fossil")).is_not_empty()
	assert_str(_catalog.scenario_path(&"map_3", &"renew", &"fossil")).is_not_empty()
	assert_str(_catalog.scenario_path(&"nowhere", &"fossil", &"renew")).is_empty()


func test_the_route_is_registered_and_makes_the_screen() -> void:
	var routes: MenuRoutes = MenuRoutes.new()
	MenuRoutesDefaults.register(routes)
	assert_bool(routes.has(MenuRoutes.SKIRMISH)).is_true()
	var screen: MenuScreen = routes.make(MenuRoutes.SKIRMISH)
	assert_bool(screen is MapSelect).is_true()
	screen.free()


func test_no_ad_word_in_the_screen() -> void:
	var words: Array[String] = [
		"AdService", "RewardedOffer", "interstitial", "show_banner", "admob"
	]
	var code: String = "\n".join(FileScan.code_lines(FileAccess.get_file_as_string(SCREEN_SOURCE)))
	for word: String in words:
		(
			assert_bool(code.to_lower().contains(word.to_lower()))
			. override_failure_message(word)
			. is_false()
		)
	var shown: String = " ".join(MapSelectText.ENGLISH.values()).to_lower()
	for word: String in ["ad ", "ads", "reward", "watch", "free"]:
		assert_bool(shown.contains(word)).override_failure_message(word).is_false()


## `consent`: the fake ad service has consent. `host_band`: a band is hosted in the slot, as P430
## will (the screen itself hosts none).
func _open(profile: UiMetrics, consent: bool, host_band: bool = true) -> void:
	assert_object(profile).is_not_null()
	UiScale.set_override(profile)
	get_window().size = profile.window_size
	await await_idle_frame()
	if _harness == null:
		_harness = (load("res://tests/ads/ad_service_harness.gd") as GDScript).new()
		_ads = _harness.make(consent)
		_ads.fake_auto_close = false
		add_child(_ads)
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(_menu)
	_stack = _menu.get_node("MenuStack") as MenuStack
	_stack.slide_ms = 0
	_screen = MapSelect.new()
	_screen.progression = _progression
	_screen.flow = _flow
	_screen.catalog = _shown
	_stack.push(_screen)
	if host_band:
		var band: AdBannerBand = AdBannerBand.new()
		band.start_page = true
		band.service = _ads
		_screen.slot.host(band)
	for _frame: int in range(3):
		await await_idle_frame()


## A copy of the real catalog (map 2 behind its lock), so a test may reorder it.
func _catalog_copy() -> MapCatalog:
	var catalog: MapCatalog = MapCatalog.new()
	catalog.entries = _catalog.entries.duplicate(true)
	return catalog


func _close() -> void:
	if _menu != null:
		remove_child(_menu)
		_menu.free()
		_menu = null


func _buttons() -> Array[Button]:
	var found: Array[Button] = []
	_collect_buttons(_screen.column, found)
	return found


func _collect_buttons(node: Node, into: Array[Button]) -> void:
	for child: Node in node.get_children():
		if child is Button and (child as Button).visible:
			into.append(child as Button)
		if child is PanelContainer or child is OfferSlot:
			_collect_buttons(child, into)


func _profile_with_window(size: Vector2i) -> UiMetrics:
	for profiles: Dictionary[StringName, UiMetrics] in [UiProfiles.all(), UiProfiles.portrait()]:
		for profile_name: StringName in profiles:
			if profiles[profile_name].window_size == size:
				return profiles[profile_name]
	assert_bool(false).override_failure_message("no profile for %s" % size).is_true()
	return null
