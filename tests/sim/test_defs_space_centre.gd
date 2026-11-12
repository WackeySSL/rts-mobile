extends GdUnitTestSuite
## The space centres' data (plan row P234, ADR 0036 section 11): one BuildingDef per faction, a
## Reveal building (kind 3) with one charge of 2,700 ticks (3 minutes, answer 3 B) and no sweep
## timer, behind the Radar. Its `type_id` is its art id, which is how WorldSort finds its sheet,
## and its footprint is its art model's. A sweep reads no radius, delay or weapon, so those stay 0
## and null, as the blackout building's weapon does. What the sim does with the numbers is
## test_reveal's and test_replay_sweep's.

const FILES: Dictionary[String, Array] = {
	"fossil_space": ["fossil", "Skyrig", "fossil_radar"],
	"renew_space": ["renew", "Zenith", "renew_radar"],
}


func test_each_faction_lists_one_space_centre_with_the_adr_numbers() -> void:
	for id: String in FILES:
		var def: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		assert_object(def).override_failure_message(id).is_not_null()
		assert_str(String(def.type_id)).is_equal(id)
		assert_str(String(def.faction)).is_equal(FILES[id][0])
		assert_str(def.display_name).is_equal(FILES[id][1])
		assert_str(String(def.requires.type_id)).is_equal(FILES[id][2])
		(
			assert_array(
				[def.footprint, def.cost, def.power, def.tab, def.speed, def.radius, def.max_hp]
			)
			. is_equal([Vector2i(3, 3), 2000, -60, World.Tab.STRUCTURES, 0, 0, 1500])
		)
		assert_array([def.strike_kind, def.charge_ticks]).is_equal([Strike.Kind.REVEAL, 2700])
		assert_array([def.strike_radius, def.strike_delay, def.strike_ticks]).is_equal([0, 0, 0])
		assert_object(def.strike_weapon).is_null()
		var faction: FactionDef = load("res://data/factions/%s.tres" % FILES[id][0])
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_true()


## The art's footprint is the data's, and the art id is the type id (WorldSort bakes by it).
func test_the_art_model_of_each_has_the_data_footprint_and_the_type_id() -> void:
	for id: String in FILES:
		var def: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		var model: ArtModel = (
			load("res://assets/art/models/%s/%s.tres" % [FILES[id][0], id]) as ArtModel
		)
		assert_object(model).override_failure_message(id).is_not_null()
		assert_str(String(model.art_id)).is_equal(String(def.type_id))
		assert_int(model.footprint).is_equal(def.footprint.x)
		assert_int(def.footprint.x).is_equal(def.footprint.y)
