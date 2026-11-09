extends GdUnitTestSuite
## Phase 3 end to end, a full match per faction (plan row P94, the gate's "a full match can be
## played against a dummy opponent"): the scripted player of `skirmish_player.gd` plays each
## Skirmish route of P90, the Derrick League on `skirmish_kestrel_flats` against `dummy_renew` and
## the Lumen Accord on `skirmish_kestrel_flats_mirrored` against `dummy_fossil`, to the end through
## a MatchRunner and the Commands of the queue alone (CLAUDE.md rule 4), seed 42. The matches are
## played once for all three suites of this folder (`skirmish_match.gd`). Judged here: the outcome
## and its stamps, that no Command is dropped, what the replay log holds, that each side built from
## its own faction, and the result screen that a player would see, read off the ResultScreen that
## heard the end. The strikes are test_skirmish_strikes', the replay and the two implementations
## test_skirmish_determinism's.
##
## The scripted player queues and places its structures by the path the UI uses on `main` (ADR
## 0026's old path: QUEUE, then PLACE with no type); the row that retires it (P131) changes the two
## functions of the player that send them.

const Match: GDScript = preload("res://tests/e2e/support/skirmish_match.gd")
const Player: GDScript = preload("res://tests/e2e/support/skirmish_player.gd")
const SimImpls: GDScript = preload("res://tests/sim/support/sim_impls.gd")
const FACTIONS: Array[String] = ["fossil", "renew"]
## The Commands the scripted player may send, and the dummy's.
const PLAYER_TYPES: Array[int] = [
	Command.Type.QUEUE,
	Command.Type.PLACE,
	Command.Type.ATTACK_MOVE,
	Command.Type.ATTACK,
	Command.Type.SUPERWEAPON,
]
const DUMMY_TYPES: Array[int] = [Command.Type.QUEUE, Command.Type.PLACE, Command.Type.ATTACK_MOVE]
## The dummy thinks on `tick % 15 == 7` as player 2 (ADR 0020 section 2).
const DUMMY_TICK: int = 7


func before() -> void:
	for faction: String in FACTIONS:
		Match.played(self, faction, SimImpls.Impl.GDSCRIPT)


func test_the_scripted_player_wins_each_match_and_the_runner_announces_it_once() -> void:
	for faction: String in FACTIONS:
		var played: Match.Played = _played(faction)
		var world: World = played.world
		var story: String = _story(faction)
		assert_int(world.match_end_tick).override_failure_message(story).is_greater(0)
		assert_int(world.match_end_tick).override_failure_message(story).is_less(Match.MAX_TICKS)
		assert_int(world.winner).override_failure_message(story).is_equal(1)
		# The dummy fell on the tick that ended the match, the player never did.
		assert_array(Array(world.defeated_tick)).is_equal([0, 0, world.match_end_tick])
		# The runner stopped at the end, and its published snapshot shows the same.
		assert_int(world.tick).override_failure_message(faction).is_equal(world.match_end_tick)
		assert_array([played.snapshot.match_end_tick, played.snapshot.winner]).is_equal(
			[world.match_end_tick, 1]
		)
		assert_array(played.winners).override_failure_message(faction).is_equal([1])


func test_no_command_of_either_side_is_dropped_and_no_unit_is_refused() -> void:
	for faction: String in FACTIONS:
		var world: World = _played(faction).world
		assert_int(world.dropped_commands).override_failure_message(faction).is_equal(0)
		assert_int(world.spawn_refused).override_failure_message(faction).is_equal(0)


## The log is the only way in: it holds the scripted player's Commands, which are of the types the
## script sends, and the dummy's, which are of the types the dummy sends, each side on its own
## tick of the 15, in tick order, and the strike building is fired once.
func test_the_log_holds_only_the_players_and_the_dummys_commands() -> void:
	for faction: String in FACTIONS:
		var counts: Dictionary[int, Dictionary] = {1: {}, 2: {}}
		var last_tick: int = 0
		for command: Command in _played(faction).commands():
			var label: String = (
				"%s: %d %s" % [faction, command.tick, Command.Type.find_key(command.type)]
			)
			assert_array([1, 2]).override_failure_message(label).contains([command.player_id])
			var allowed: Array[int] = PLAYER_TYPES if command.player_id == 1 else DUMMY_TYPES
			assert_array(allowed).override_failure_message(label).contains([command.type])
			assert_int(command.tick % Player.PERIOD).override_failure_message(label).is_equal(
				Player.OFFSET if command.player_id == 1 else DUMMY_TICK
			)
			assert_int(command.tick).override_failure_message(label).is_greater_equal(last_tick)
			last_tick = command.tick
			var per_type: Dictionary = counts[command.player_id]
			per_type[command.type] = per_type.get(command.type, 0) + 1
		(
			assert_int(counts[1].get(Command.Type.SUPERWEAPON, 0))
			. override_failure_message(faction)
			. is_equal(1)
		)
		(
			assert_int(counts[2].get(Command.Type.SUPERWEAPON, 0))
			. override_failure_message(faction)
			. is_equal(0)
		)
		# Every structure the player queued was placed, once, and the dummy placed what it queued.
		assert_int(counts[1].get(Command.Type.PLACE, 0)).override_failure_message(faction).is_equal(
			Player.structures()
		)
		(
			assert_int(counts[2].get(Command.Type.PLACE, 0))
			. override_failure_message(faction)
			. is_greater(0)
		)


func test_each_side_built_from_its_own_faction_and_the_player_kept_its_whole_base() -> void:
	for faction: String in FACTIONS:
		var world: World = _played(faction).world
		var other: String = Match.ROUTES[faction]["dummy_faction"]
		for row: int in world.unit_count():
			var owner_faction: String = faction if world.owner[row] == 1 else other
			var type: int = world.type_index[row]
			var label: String = "%s: row %d" % [faction, row]
			(
				assert_str(String(world.faction_ids[world.type_faction[type]]))
				. override_failure_message(label)
				. is_equal(owner_faction)
			)
		# Nothing of the player's was lost but a unit; every stage of the script stands.
		assert_int(world.stat_lost_buildings[1]).override_failure_message(faction).is_equal(0)
		var roles: Dictionary = Player.ROLES[faction]
		var expected: Dictionary[StringName, int] = {
			roles["hq"]: 1,
			roles["power"]: 2,
			roles["refinery"]: 1,
			roles["radar"]: 1,
			roles["strike"]: 1,
			roles["barracks"]: 1,
		}
		for id: StringName in expected:
			var label: String = "%s: %s" % [faction, id]
			assert_int(_count(world, 1, id)).override_failure_message(label).is_equal(expected[id])


func test_both_economies_ran_and_both_sides_built() -> void:
	for faction: String in FACTIONS:
		var world: World = _played(faction).world
		var dummy: AiDef = load(Match.ROUTES[faction]["dummy"]) as AiDef
		assert_int(world.stat_harvested[1]).override_failure_message(faction).is_greater(0)
		assert_int(world.stat_harvested[2]).override_failure_message(faction).is_greater(0)
		# The player: its structures and its army. The refinery's free tanker is not in `stat_built`
		# (only a finished site, a placed structure and a queue item are: Production.gd), so it is not
		# counted here; that it came is the player's harvested credits above. The count used to ask
		# for one more than the script builds and met it only when a rifle squad died and was
		# trained again; with the docks and exits facing the map centre (ADR 0033) that no longer
		# happens in either match (22 built, nothing of the player's lost).
		var army: int = Player.ESCORT - 2 + Player.ROCKETS
		assert_int(world.stat_built[1]).override_failure_message(faction).is_greater_equal(
			Player.structures() + army
		)
		# The dummy: its whole build order, which it keeps wanting back as it loses it.
		assert_int(world.stat_built[2]).override_failure_message(faction).is_greater_equal(
			dummy.build_order.size()
		)


## The winner took down every producer of the other, and nothing else decides a defeat.
func test_the_dummy_has_no_producer_left_and_the_player_still_has_its_headquarters() -> void:
	for faction: String in FACTIONS:
		var world: World = _played(faction).world
		var left: Array[int] = [0, 0, 0]
		for row: int in world.unit_count():
			var type: int = world.type_index[row]
			if world.type_produces[type] >= 0 and world.build_left[row] == 0:
				left[world.owner[row]] += 1
		assert_array(left).override_failure_message(faction).is_equal([0, left[1], 0])
		assert_int(left[1]).override_failure_message(faction).is_greater(0)
		# It had them: the Headquarters, the barracks and the factory are three buildings lost.
		assert_int(world.stat_lost_buildings[2]).override_failure_message(faction).is_greater_equal(
			3
		)


## The result screen that heard the end: a victory, the match time of the tick that ended it and
## the table of the final World's numbers, the player as "You".
func test_the_result_screen_shows_the_victory_with_the_numbers_of_the_match() -> void:
	for faction: String in FACTIONS:
		var played: Match.Played = _played(faction)
		var world: World = played.world
		var seconds: int = world.match_end_tick / Sim.TICK_RATE
		assert_str(played.screen_title).override_failure_message(faction).is_equal("VICTORY")
		assert_str(played.screen_emblem).override_failure_message(faction).ends_with(
			"glyph_victory.svg"
		)
		assert_str(played.screen_time).override_failure_message(faction).is_equal(
			"Match time %d:%02d" % [seconds / 60, seconds % 60]
		)
		var cells: Array[String] = ["", "You", "Enemy"]
		var lines: Dictionary[String, PackedInt32Array] = {
			"Units built": world.stat_built,
			"Units lost": world.stat_lost_units,
			"Buildings lost": world.stat_lost_buildings,
			"Credits harvested": world.stat_harvested,
		}
		for line: String in lines:
			cells.append_array([line, str(lines[line][1]), str(lines[line][2])])
		assert_array(played.screen_cells).override_failure_message(faction).is_equal(cells)
		# Not a table of zeros: both sides built, harvested and lost buildings or units.
		assert_int(world.stat_built[1]).is_greater(0)
		assert_int(world.stat_harvested[1]).is_greater(0)
		assert_int(world.stat_lost_buildings[2]).is_greater(0)


## The strike came first and the match went on after it: it was fired before the end, and the end is
## after the strike's effect, so the strike did not win the match by itself.
func test_the_strike_was_fired_before_the_end_and_the_match_went_on_after_it() -> void:
	for faction: String in FACTIONS:
		var played: Match.Played = _played(faction)
		assert_int(played.player.strike_tick).override_failure_message(faction).is_greater(0)
		assert_int(played.world.match_end_tick).override_failure_message(faction).is_greater(
			played.player.strike_effect_tick
		)


## The faction and the last ten things the script did, for the failure message of a match that
## did not end as it should.
func _story(faction: String) -> String:
	var events: Array[String] = _played(faction).player.events
	return "%s, the script's last steps:\n%s" % [faction, "\n".join(events.slice(-10))]


func _played(faction: String) -> Match.Played:
	return Match.played(self, faction, SimImpls.Impl.GDSCRIPT)


## How many rows of `player` have the type id `id`.
func _count(world: World, player: int, id: StringName) -> int:
	var type: int = world.type_ids.find(id)
	var found: int = 0
	for row: int in world.unit_count():
		if world.owner[row] == player and world.type_index[row] == type:
			found += 1
	return found
