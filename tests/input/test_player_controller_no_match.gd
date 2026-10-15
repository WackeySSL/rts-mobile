extends GdUnitTestSuite
## PlayerController with no match to read from (P43a). A MatchRunner with no scenario never starts
## and publishes no snapshot, and a controller may have no runner at all. Neither is an error, and
## gdUnit4 fails a test on a script error, which is how a missing null guard shows here.


func test_all_army_with_no_snapshot_selects_nothing() -> void:
	var runner: MatchRunner = auto_free(MatchRunner.new())  # No scenario: start() never runs.
	add_child(runner)
	assert_object(runner.snapshot).is_null()
	var controller: PlayerController = auto_free(PlayerController.new())
	controller.runner = runner
	add_child(controller)
	controller.select_all_army()
	assert_array(controller.selection.selected).is_empty()


func test_a_controller_with_no_runner_enters_the_tree_with_its_defaults() -> void:
	var controller: PlayerController = auto_free(PlayerController.new())
	add_child(controller)  # _ready must not connect the `ticked` of a runner that is not there.
	assert_object(controller.runner).is_null()
	assert_object(controller.settings).is_not_null()
	assert_array(controller.selection.selected).is_empty()
