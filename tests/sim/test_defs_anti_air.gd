extends GdUnitTestSuite
## The anti-air buildings' data (plan row P239, ADR 0036 sections 2 and 5, docs/GDD.md): one 1x1
## BuildingDef per faction, a gun with mask 6 (high and low air, no ground) behind the Barracks.
## The roster entry comes with P239b (art, item card): neither is buildable yet. `type_id` is the
## art id (P239b draws it). The GDD gives the names, size, cost, power and requirement; the ADR
## gives the mask. Hit points, build time, sight, the weapon's range, damage, cooldown and armour
## percents are in neither: starting values for the balance run (the build time and hit points
## follow the Redoubt's scale, the guns differ by faction as the Redoubt and the Rail Battery do).
## What the sim does with the mask is test_targeting_layers'.

const FILES: Dictionary[String, Array] = {
	"fossil_aa": ["fossil", "Burst Stack", "barracks", "burst_stack_gun", 4500, 12, 6],
	"renew_aa": ["renew", "Sky Needle", "renew_barracks", "sky_needle_gun", 5500, 45, 20],
}


func test_each_faction_lists_one_anti_air_building_with_the_gdd_numbers() -> void:
	for id: String in FILES:
		var def: BuildingDef = load("res://data/units/%s.tres" % id) as BuildingDef
		assert_object(def).override_failure_message(id).is_not_null()
		assert_str(String(def.type_id)).is_equal(id)
		assert_str(String(def.faction)).is_equal(FILES[id][0])
		assert_str(def.display_name).is_equal(FILES[id][1])
		assert_str(String(def.requires.type_id)).is_equal(FILES[id][2])
		# GDD: size, cost, power, requires.
		assert_array([def.footprint, def.cost, def.power, def.tab]).is_equal(
			[Vector2i(1, 1), 700, -20, World.Tab.STRUCTURES]
		)
		# Starting values.
		assert_array([def.max_hp, def.armour, def.build_ticks, def.sight_range]).is_equal(
			[700, World.Armour.BUILDING, 260, 7000]
		)
		assert_array([def.speed, def.radius, def.produces, def.strike_kind]).is_equal([0, 0, -1, 0])
		var gun: WeaponDef = def.weapon
		assert_object(gun).override_failure_message(id).is_not_null()
		assert_str(String(gun.id)).is_equal(FILES[id][3])
		assert_array([gun.range, gun.damage, gun.cooldown_ticks]).is_equal(
			[FILES[id][4], FILES[id][5], FILES[id][6]]
		)
		assert_int(def.acquire_range).is_equal(gun.range)
		# Not in a roster yet: the roster entry comes with P239b (art, item card).
		var faction: FactionDef = load("res://data/factions/%s.tres" % FILES[id][0])
		assert_bool(faction.roster.has(def)).override_failure_message(id).is_false()


## ADR 0036 section 5: the mask is high and low air, and never the ground.
func test_the_guns_hit_high_and_low_air_and_never_the_ground() -> void:
	for id: String in FILES:
		var gun: WeaponDef = (load("res://data/units/%s.tres" % id) as BuildingDef).weapon
		assert_int(gun.targets).override_failure_message(id).is_equal(
			World.Layer.AIR | World.Layer.LOW_AIR
		)
		assert_int(gun.targets).is_equal(6)
		assert_int(gun.targets & World.Layer.GROUND).is_equal(0)
		assert_int(gun.vs_armour.size()).is_equal(4)
		# A drone squad is INFANTRY and aircraft use LIGHT or HEAVY: none of them is immune.
		for armour: int in [World.Armour.INFANTRY, World.Armour.LIGHT, World.Armour.HEAVY]:
			assert_int(gun.vs_armour[armour]).override_failure_message(id).is_greater(0)


## The art id is the type id (WorldSort bakes by it) and the model, when P239b lands, is 1x1.
func test_the_art_model_when_present_has_the_data_footprint() -> void:
	for id: String in FILES:
		var path: String = "res://assets/art/models/%s/%s.tres" % [FILES[id][0], id]
		if not ResourceLoader.exists(path):
			continue  # P239b's art row is not merged yet.
		var model: ArtModel = load(path) as ArtModel
		assert_str(String(model.art_id)).is_equal(id)
		assert_int(model.footprint).is_equal(1)
