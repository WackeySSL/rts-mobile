extends GdUnitTestSuite
## The unit art that UnitLayer and the gallery build on (one canvas per unit, half import scale,
## grey team layers, no turret on a squad) and the gallery's squads (assets/art/STYLE.md).

const FileScan: GDScript = preload("res://tests/support/file_scan.gd")
const UNIT_ART: String = "res://assets/art/svg/units/%s_%s.svg"
const SIDE_PX: Dictionary[String, int] = {"light_tank": 64, "rifle_squad": 32, "rocket_squad": 32}


func test_unit_layers_are_one_canvas_at_half_scale_and_squads_have_no_turret() -> void:
	for unit: String in SIDE_PX:
		for layer: String in ["hull", "team"]:
			var size: Vector2 = (load(UNIT_ART % [unit, layer]) as Texture2D).get_size()
			assert_vector(size).override_failure_message(unit + layer).is_equal(
				Vector2.ONE * SIDE_PX[unit]
			)
	assert_bool(ResourceLoader.exists(UNIT_ART % ["rifle_squad", "turret"])).is_false()
	assert_bool(ResourceLoader.exists(UNIT_ART % ["rocket_squad", "turret"])).is_false()


func test_team_layers_hold_only_greys() -> void:
	var paths: Array[String] = FileScan.list_files("res://assets/art/svg/units", "_team.svg")
	assert_int(paths.size()).is_equal(3)
	for path: String in paths:
		var image: Image = (load(path) as Texture2D).get_image()
		image.convert(Image.FORMAT_RGBA8)
		var data: PackedByteArray = image.get_data()
		var colored: int = 0
		for i: int in range(0, data.size(), 4):
			colored += int(
				data[i + 3] > 0 and (data[i] != data[i + 1] or data[i + 1] != data[i + 2])
			)
		assert_int(colored).override_failure_message(path).is_equal(0)


func test_the_gallery_has_both_squads_in_all_four_slots_tinted_by_slot() -> void:
	var gallery: Node = auto_free(
		(load("res://scenes/dev/art_gallery.tscn") as PackedScene).instantiate()
	)
	add_child(gallery)
	await await_idle_frame()
	for slot: String in ["Grass/SlotA", "Grass/SlotB", "Sand/SlotA", "Sand/SlotB"]:
		for squad: String in ["RifleSquad", "RocketSquad"]:
			var rig: Node = gallery.get_node("%s/%s" % [slot, squad])
			assert_int(rig.get_child_count()).is_equal(2)
			var team: Color = Color("2F80ED") if slot.ends_with("A") else Color("E5484D")
			var tint: Color = (rig.get_node("Team") as Sprite2D).modulate
			assert_that(tint).override_failure_message(slot).is_equal(team)
