extends RefCounted
## The main scene on a Skirmish, for the suites of the result screen, the pause menu and the
## two routes (plan P90). Not a suite. A suite that builds the scene through it calls
## `MenuRig.begin()` and `MenuRig.end()` itself (tests/project/test_menu_rig_scan.gd).

const DERRICK: String = DevRoutes.SKIRMISH_DERRICK
const LUMEN: String = DevRoutes.SKIRMISH_LUMEN
## The dummy of the side the player does not play.
const DUMMY_OF: Dictionary[String, String] = {
	DevRoutes.SKIRMISH_DERRICK: DevRoutes.DUMMY_RENEW,
	DevRoutes.SKIRMISH_LUMEN: DevRoutes.DUMMY_FOSSIL,
}


## A main scene of `suite` on `scenario_path` against that route's dummy, in the tree for two
## frames, with `local_player` as the player (a copy of the scenario when it is another than the
## scenario's). The way `DevRoutes.open_main_with` makes it, without the scene change.
static func open(
	suite: GdUnitTestSuite, scenario_path: String = DERRICK, local_player: int = 1
) -> Node:
	var main: Node = (load(DevRoutes.MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = main.get_node("MatchRunner")
	var scenario: ScenarioDef = load(scenario_path)
	if scenario.local_player != local_player:
		scenario = scenario.duplicate()
		scenario.local_player = local_player
	runner.scenario = scenario
	var opponents: Array[AiDef] = [load(DUMMY_OF[scenario_path]) as AiDef]
	runner.opponents = opponents
	suite.add_child(main)
	await suite.await_idle_frame()
	await suite.await_idle_frame()
	return main


## `main`'s own units, as ids: every row of player `player` that is not a building.
static func units_of(main: Node, player: int) -> PackedInt32Array:
	var snap: MatchSnapshot = (main.get_node("MatchRunner") as MatchRunner).snapshot
	var ids: PackedInt32Array = PackedInt32Array()
	for row: int in snap.unit_count():
		if snap.owner[row] == player and not WorldSort.is_building(snap, snap.type_index[row]):
			ids.append(snap.unit_id[row])
	return ids


## Ends the match the way the players do: each of `surrenderers` sends SURRENDER through the queue,
## and one tick plays. Winner: the one left, or 0 when both go at once.
static func end(main: Node, surrenderers: Array) -> void:
	for player: int in surrenderers:
		CommandQueue.submit(Command.surrender(player))
	(main.get_node("MatchRunner") as MatchRunner).run_ticks(1)
