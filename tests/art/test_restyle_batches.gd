extends GdUnitTestSuite
## The batch lists of plan rows P638-P647 (`docs/art/treadline-batches.json`): every art id of the
## index is in exactly one batch, of its own faction, and a batch holds one kind of model.

const PATH: String = "res://docs/art/treadline-batches.json"


func _batches() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	assert_object(parsed).is_not_null()
	return (parsed as Dictionary)["batches"]


func test_every_art_id_of_the_index_is_in_exactly_one_batch() -> void:
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	var seen: Dictionary[String, int] = {}
	for batch: Dictionary in _batches():
		for id: String in batch["ids"]:
			seen[id] = seen.get(id, 0) + 1
	for sheet: IsoSheetDef in index.sheets:
		(
			assert_int(seen.get(String(sheet.art_id), 0))
			. override_failure_message(String(sheet.art_id))
			. is_equal(1)
		)
	assert_int(seen.size()).is_equal(index.sheets.size())


func test_a_batch_has_one_faction_one_kind_and_one_footprint_class() -> void:
	for batch: Dictionary in _batches():
		var classes: Dictionary[String, bool] = {}
		for id: String in batch["ids"]:
			var model: ArtModel = (
				load("res://assets/art/models/%s/%s.tres" % [batch["faction"], id]) as ArtModel
			)
			(
				assert_object(model)
				. override_failure_message("%s %s" % [batch["row"], id])
				. is_not_null()
			)
			var kind: String = String(model.category)
			if model.category == &"bld":
				kind += "3" if model.footprint == 3 else "small"
			elif model.category == &"veh":
				kind += "air" if model.flies() else "ground"
			classes[kind] = true
		var support: bool = String(batch["what"]).begins_with("support")
		assert_int(classes.size()).override_failure_message(batch["row"]).is_equal(
			2 if support else 1
		)
