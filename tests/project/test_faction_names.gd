extends GdUnitTestSuite
## Plan P607 (ADR 0049 section 2): the factions are Ironward (orange, id `fossil`) and Facet (blue,
## id `renew`). `FactionDef.display_name` is the one source; the menus' side names are its upper
## case (the two translation tables keep their keys, ADR 0049 section 2). No player text still
## holds the old names. The lesson text (`data/tutorial/`) is P608's and is not scanned here.

const FACTIONS: Dictionary[StringName, String] = {
	&"fossil": "res://data/factions/fossil.tres", &"renew": "res://data/factions/renew.tres"
}
const OLD_NAMES: Array[String] = ["derrick league", "lumen accord"]
## Player text: the help, the how-to-play list, the GDD, the menu tables and the dev menu's buttons.
const PLAYER_TEXT: Array[String] = [
	"res://data/help/how_to_play.tres",
	"res://docs/HOW_TO_PLAY.md",
	"res://docs/GDD.md",
	"res://game/ui/menu/MainMenuText.gd",
	"res://game/ui/menu/MapSelectText.gd",
	"res://scenes/dev/dev_menu.tscn",
	"res://data/factions/fossil.tres",
	"res://data/factions/renew.tres",
]


func test_the_shipped_display_names() -> void:
	assert_str((load(FACTIONS[&"fossil"]) as FactionDef).display_name).is_equal("Ironward")
	assert_str((load(FACTIONS[&"renew"]) as FactionDef).display_name).is_equal("Facet")


func test_the_side_names_are_the_faction_names_in_upper_case() -> void:
	var fossil: String = (load(FACTIONS[&"fossil"]) as FactionDef).display_name.to_upper()
	var renew: String = (load(FACTIONS[&"renew"]) as FactionDef).display_name.to_upper()
	assert_str(MainMenuText.ENGLISH[MainMenuText.SIDE_FOSSIL]).is_equal(fossil)
	assert_str(MainMenuText.ENGLISH[MainMenuText.SIDE_RENEW]).is_equal(renew)
	assert_str(MapSelectText.ENGLISH[MapSelectText.SIDE_FOSSIL]).is_equal(fossil)
	assert_str(MapSelectText.ENGLISH[MapSelectText.SIDE_RENEW]).is_equal(renew)
	assert_str(fossil).is_equal("IRONWARD")


func test_no_player_text_holds_an_old_name() -> void:
	for path: String in PLAYER_TEXT:
		var text: String = FileAccess.get_file_as_string(path).replace("\n", " ").to_lower()
		for old: String in OLD_NAMES:
			(
				assert_bool(text.contains(old))
				. override_failure_message("%s still names %s" % [path, old])
				. is_false()
			)
