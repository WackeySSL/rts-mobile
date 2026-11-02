extends GdUnitTestSuite
## PlayerView.row_build_left (plan row P128, ADR 0026 section 8): the construction work left of a
## row is a public column, like its hit points: an own row and a seen row answer it (a seen site is
## visible state, so an AI that sees an enemy's site reads the same number the player does), and a
## hidden row, a row outside the table and a negative row answer MISSING as for every other column.
## The crafted World of `view_worlds.gd` has the rows: player 1 owns HQ_1 and RIFLE_1, sees NEAR_FOE
## and does not see FAR_FOE.

const ViewWorlds: GDScript = preload("res://tests/sim/support/view_worlds.gd")
const MISSING: int = PlayerView.MISSING


func test_an_own_row_and_a_seen_row_answer_their_work_left() -> void:
	var world: World = ViewWorlds.crafted()
	world.build_left[world.index_of(ViewWorlds.HQ_1)] = 700
	world.build_left[world.index_of(ViewWorlds.NEAR_FOE)] = 400
	world.build_left[world.index_of(ViewWorlds.FAR_FOE)] = 250
	var view: PlayerView = PlayerView.of(world, 1)
	assert_int(view.row_build_left(view.row_of(ViewWorlds.HQ_1))).is_equal(700)
	assert_int(view.row_build_left(view.row_of(ViewWorlds.NEAR_FOE))).is_equal(400)
	# A complete building and a unit answer 0.
	assert_int(view.row_build_left(view.row_of(ViewWorlds.RIFLE_1))).is_equal(0)
	# Not seen: the row is as good as absent.
	assert_int(view.row_of(ViewWorlds.FAR_FOE)).is_equal(MISSING)
	assert_int(view.row_build_left(world.index_of(ViewWorlds.FAR_FOE))).is_equal(MISSING)
	for row: int in [-1, world.unit_count(), world.unit_count() + 5]:
		assert_int(view.row_build_left(row)).override_failure_message(str(row)).is_equal(MISSING)
	# The other player sees it the other way round.
	var other: PlayerView = PlayerView.of(world, 2)
	assert_int(other.row_build_left(world.index_of(ViewWorlds.FAR_FOE))).is_equal(250)
	assert_int(other.row_build_left(world.index_of(ViewWorlds.HQ_1))).is_equal(MISSING)


## The view keeps an alias of the column behind its getter, as for the other rows: a site that
## finishes after the view was made shows as the World has it (a view is made, read and dropped
## within one think), and nothing public is an alias.
func test_the_getter_reads_the_row_columns_and_not_a_public_array() -> void:
	var world: World = ViewWorlds.crafted()
	var view: PlayerView = PlayerView.of(world, 1)
	var row: int = view.row_of(ViewWorlds.HQ_1)
	assert_int(view.row_build_left(row)).is_equal(0)
	world.build_left[row] = 90
	assert_int(view.row_build_left(row)).is_equal(90)
	var properties: Array[String] = []
	for property: Dictionary in view.get_property_list():
		properties.append(String(property["name"]))
	assert_bool(properties.has("build_left")).is_false()
