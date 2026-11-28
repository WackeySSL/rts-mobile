extends GdUnitTestSuite
## `TerrainKitDef` (plan row P656c): fields and the path lookup only. The piece choice and the
## cell hash are `TerrainKit`'s (P656d) and are not tested here.


func _def() -> TerrainKitDef:
	var def: TerrainKitDef = TerrainKitDef.new()
	def.dir = "res://assets/art/terrain"
	def.terrains = PackedStringArray(["grass", "sand"])
	def.priority = PackedStringArray(["sand", "grass"])
	def.masks = {&"base": PackedStringArray(["0", "1"]), &"blend": PackedStringArray(["side_ne"])}
	def.kinds = {
		&"grass": PackedStringArray(["base"]), &"sand": PackedStringArray(["base", "blend"])
	}
	def.pieces = {
		&"grass/base/0": "grass_base_0.png",
		&"grass/base/1": "grass_base_1.png",
		&"sand/blend/side_ne": "sand_blend_side_ne.png",
	}
	return def


func test_the_defaults_are_the_standard_kit() -> void:
	var def: TerrainKitDef = TerrainKitDef.new()
	assert_str(def.dir).is_equal("res://assets/art/terrain")
	assert_int(def.variants).is_equal(4)
	assert_vector(Vector2(TerrainKitDef.TILE)).is_equal(Vector2(128, 64))
	assert_int(TerrainKitDef.RISE_MAX).is_equal(64)


func test_a_piece_is_found_by_terrain_kind_and_mask() -> void:
	var def: TerrainKitDef = _def()
	assert_str(def.path_of(&"grass", &"base", &"1")).is_equal(
		"res://assets/art/terrain/grass_base_1.png"
	)
	assert_str(def.path_of(&"sand", &"blend", &"side_ne")).is_equal(
		"res://assets/art/terrain/sand_blend_side_ne.png"
	)
	assert_bool(def.has_piece(&"sand", &"blend", &"side_ne")).is_true()


func test_a_piece_the_kit_lacks_has_no_path() -> void:
	var def: TerrainKitDef = _def()
	assert_str(def.path_of(&"grass", &"blend", &"side_ne")).is_empty()
	assert_str(def.path_of(&"water", &"base", &"0")).is_empty()
	assert_bool(def.has_piece(&"water", &"base", &"0")).is_false()


func test_the_key_is_terrain_kind_mask() -> void:
	assert_str(String(TerrainKitDef.key(&"rock", &"lip", &"outer_n"))).is_equal("rock/lip/outer_n")


func test_the_committed_kit_loads_and_names_the_six_sim_terrains() -> void:
	var def: TerrainKitDef = load("res://assets/art/terrain/kit.tres") as TerrainKitDef
	assert_object(def).is_not_null()
	assert_array(Array(def.terrains)).contains_exactly(
		["grass", "sand", "scrub", "rock", "water", "ore"]
	)
