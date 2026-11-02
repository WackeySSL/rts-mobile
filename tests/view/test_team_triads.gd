extends GdUnitTestSuite
## Which triad a player wears (plan P90, ADR 0025 answer 7): `WorldSort.triad_index` reads the
## scenario's `team_triads` (entry p is player p's index into `WorldSort.TRIADS`, entry 0 unused)
## and falls back to the player's own place, the first player the first triad. The atlas bake and
## the minimap read the same rule, so a scenario that swaps the two colours swaps them in both.


func test_without_team_triads_a_player_wears_its_own_place_and_wraps_after_eight() -> void:
	var none: PackedInt32Array = PackedInt32Array()
	var sizes: int = WorldSort.TRIADS.size()
	assert_int(sizes).is_equal(8)
	for player: int in range(1, sizes + 3):
		assert_int(WorldSort.triad_index(none, player)).is_equal((player - 1) % sizes)
	assert_int(WorldSort.triad_index(none, 0)).is_equal(0)  # Neutral wears the first.


func test_an_entry_names_the_triad_and_a_player_past_the_end_keeps_its_place() -> void:
	var swapped: PackedInt32Array = PackedInt32Array([0, 1, 0])
	assert_int(WorldSort.triad_index(swapped, 1)).is_equal(1)
	assert_int(WorldSort.triad_index(swapped, 2)).is_equal(0)
	assert_int(WorldSort.triad_index(swapped, 3)).is_equal(2)  # Past the end: its own place.
	assert_int(WorldSort.triad_index(swapped, 0)).is_equal(1)  # Neutral wears player 1's.
	var odd: PackedInt32Array = PackedInt32Array([5, 9, -1])
	assert_int(WorldSort.triad_index(odd, 1)).is_equal(1)  # Wrapped: 9 mod 8.
	assert_int(WorldSort.triad_index(odd, 2)).is_equal(7)  # Wrapped: -1 mod 8.


func test_the_minimap_reads_the_same_rule() -> void:
	var swapped: PackedInt32Array = PackedInt32Array([0, 1, 0])
	assert_int(MinimapImage.team_slot(1)).is_equal(0)  # The default stays.
	assert_int(MinimapImage.team_slot(2)).is_equal(1)
	assert_int(MinimapImage.team_slot(1, swapped)).is_equal(1)
	assert_int(MinimapImage.team_slot(2, swapped)).is_equal(0)
	assert_int(MinimapImage.team_slot(0, swapped)).is_equal(1)  # As the atlas's slot_of(0).


## The atlas bakes the swap: the two players of a scenario with `team_triads` wear each other's
## triad, and a restart of the same scenario is not baked again.
func test_the_atlas_players_wear_the_triads_the_scenario_names() -> void:
	var scenario: ScenarioDef = load("res://data/scenarios/skirmish_kestrel_flats_mirrored.tres")
	var sorted: WorldSort = auto_free(WorldSort.new())
	var atlas: IsoAtlas = sorted.bake(scenario)
	assert_bool(atlas.is_empty()).is_false()
	assert_str(sorted.mid_colour(1).to_html(false)).is_equal(Color("1FA6C8").to_html(false))
	assert_str(sorted.mid_colour(2).to_html(false)).is_equal(Color("E8681F").to_html(false))
	assert_str(sorted.mid_colour(0).to_html(false)).is_equal(sorted.mid_colour(1).to_html(false))
	assert_object(sorted.bake(scenario)).is_same(atlas)
	var plain: ScenarioDef = load("res://data/scenarios/skirmish_kestrel_flats.tres")
	sorted.bake(plain)
	assert_str(sorted.mid_colour(1).to_html(false)).is_equal(Color("E8681F").to_html(false))
	assert_str(sorted.mid_colour(2).to_html(false)).is_equal(Color("1FA6C8").to_html(false))
