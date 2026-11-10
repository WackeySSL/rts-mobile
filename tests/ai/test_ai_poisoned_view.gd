extends GdUnitTestSuite
## The hidden-row rule of `PlayerView.columns()` (plan row P198, ADR 0020 section 1, ADR 0030
## section 7): the AI indexes the columns only at rows of `own_rows` and `seen_rows` or a `row_of()`
## answer of 0 or more. Two Normal `OpponentAi` play the first ticks of `perf_ai.tres` (the scout,
## first contact and the wave, as `tests/perf/test_ai_perf.gd`) on the views of `PlayerView.of`,
## once as they are and once with every hidden row of the view's columns poisoned: type
## `0x7FFFFFFF` (any table read of it fails) and every other field MISSING. A manager that read a
## hidden row would send other Commands or end on another state hash. After every think the
## poisoned copies still equal the World at the visible rows, and the World's own state is the one
## it was before the think (the hash): a manager wrote through no column.

const SmokeRun: GDScript = preload("res://tests/smoke/smoke_run.gd")
const PATH: String = "res://data/scenarios/perf_ai.tres"
const OPPONENTS: Array[String] = [
	"res://data/dev/arena/ai/opponent_fossil.tres", "res://data/dev/arena/ai/opponent_renew.tres"
]
const LEVEL: String = "res://data/dev/arena/ai/difficulty/normal.tres"
const SEED: int = 42
## Long enough for both scouts, the first contact and a wave launch (tick 300 of the frozen defs).
const TICKS: int = 420
const POISON_TYPE: int = 0x7FFFFFFF


## What a run leaves: the Commands as encoded ints, the final hash, the thinks made, the hidden rows
## that were poisoned, and the problems the poisoned run found.
class Result:
	var encoded: PackedInt32Array = PackedInt32Array()
	var final_hash: int = 0
	var thinks: int = 0
	var poisoned_rows: int = 0
	var problems: Array[String] = []
	var contact: bool = false
	var enemy_rows: int = 0
	var waves: int = 0
	var strike_tests: int = 0


func test_poisoned_hidden_rows_change_neither_the_commands_nor_the_state() -> void:
	var clean: Result = _play(false)
	var poisoned: Result = _play(true)
	assert_array(poisoned.problems).is_empty()
	assert_int(clean.thinks).is_greater(100)
	assert_int(poisoned.thinks).is_equal(clean.thinks)
	# The poison was there to be read: hidden rows existed in the views.
	assert_int(poisoned.poisoned_rows).is_greater(0)
	assert_bool(clean.contact).is_true()
	# The sites that read other managers' rows were reached: a wave (`_tally`, `_value_in`) and a
	# strike search (`_take_list`), and the views held enemy rows that the fog hides.
	assert_int(clean.waves).is_greater(0)
	assert_int(clean.strike_tests).is_greater(0)
	assert_int(clean.enemy_rows).is_greater(0)
	assert_int(clean.encoded.size()).is_greater(0)
	assert_array(poisoned.encoded).is_equal(clean.encoded)
	assert_int(poisoned.final_hash).is_equal(clean.final_hash)


## The poison itself: a hidden row of the copies reads as poison, a visible one as the World's.
func test_the_poison_covers_exactly_the_hidden_rows() -> void:
	var world: World = SmokeRun.world_of(SEED, PATH)
	var view: PlayerView = PlayerView.of(world, 1)
	var rows: int = view.columns()[PlayerView.Column.ID].size()
	var before: Array[PackedInt32Array] = []
	for column: PackedInt32Array in view.columns():
		before.append(column.duplicate())
	var hidden: int = _poison(view)
	assert_int(hidden).is_equal(rows - view.own_rows.size() - view.seen_rows.size())
	for row: int in rows:
		var visible: bool = view.own_rows.has(row) or view.seen_rows.has(row)
		var got: Array[int] = []
		for column: PackedInt32Array in view.columns():
			got.append(column[row])
		if visible:
			var want: Array[int] = []
			for column: PackedInt32Array in before:
				want.append(column[row])
			assert_array(got).is_equal(want)
		else:
			assert_int(got[PlayerView.Column.TYPE]).is_equal(POISON_TYPE)
			assert_int(got[PlayerView.Column.HP]).is_equal(PlayerView.MISSING)


## One match of TICKS ticks. With `poison` each think gets a view whose hidden rows are poisoned.
func _play(poison: bool) -> Result:
	var result: Result = Result.new()
	var world: World = SmokeRun.world_of(SEED, PATH)
	for problem: String in SmokeRun.attach_impl(world):
		result.problems.append("sim impl: " + problem)
	var loop: MatchLoop = SmokeRun.loop_of(world, SEED, PATH)
	var level: AiDifficultyDef = load(LEVEL) as AiDifficultyDef
	var controllers: Array[AiController] = []
	for index: int in OPPONENTS.size():
		var player: int = index + 1
		var rng: DetRandom = DetRandom.create(SEED, DetRandom.STREAM_AI_BASE + player)
		var def: OpponentDef = load(OPPONENTS[index]) as OpponentDef
		controllers.append(AiFactory.create(def, level, player, rng))
	for tick: int in TICKS:
		var commands: Array[Command] = []
		for ai: AiController in controllers:
			if (tick + ai.think_offset) % maxi(ai.think_period, 1) != 0:
				continue
			var view: PlayerView = PlayerView.of(world, ai.player_id)
			var before: int = world.state_hash()
			if not poison:
				result.enemy_rows += _hidden_enemies(view)
			if poison:
				result.poisoned_rows += _poison(view)
			ai.think(view, commands)
			result.thinks += 1
			var opponent: OpponentAi = ai as OpponentAi
			result.waves = maxi(result.waves, opponent.army.waves)
			result.strike_tests = maxi(result.strike_tests, opponent.striker.tests)
			result.contact = result.contact or (ai as OpponentAi).memory.seen_unit_id.size() > 0
			if poison:
				_judge(world, view, before, tick, result)
		for command: Command in commands:
			command.encode(result.encoded)
		loop.step(world, commands)
	result.final_hash = world.state_hash()
	return result


## Replaces the view's seven public columns by copies in which every hidden row is poisoned; returns
## how many rows that was. The getters keep their aliases, so `row_of` and the lists are as made.
func _poison(view: PlayerView) -> int:
	var hidden: int = 0
	var columns: Array[PackedInt32Array] = view.columns()
	for row: int in columns[PlayerView.Column.ID].size():
		if view._shown[row] != 0:
			continue
		hidden += 1
		for column: int in columns.size():
			columns[column][row] = POISON_TYPE if column == PlayerView.Column.TYPE else -1
	# One more poisoned row past the end, so an index of -1 (a dropped `row < 0` guard) reads it.
	for column: int in columns.size():
		columns[column].append(POISON_TYPE if column == PlayerView.Column.TYPE else -1)
	return hidden


## How many rows of the view are hidden and belong to another player.
func _hidden_enemies(view: PlayerView) -> int:
	var found: int = 0
	for row: int in view._shown.size():
		if view._shown[row] == 0 and view._owner[row] > 0 and view._owner[row] != view.player:
			found += 1
	return found


## After a think: the visible entries of the copies still hold the World's values, and the World is
## as it was.
func _judge(world: World, view: PlayerView, before: int, tick: int, result: Result) -> void:
	var tag: String = "tick %d player %d" % [tick, view.player]
	if world.state_hash() != before:
		result.problems.append(tag + ": a think changed the World")
	var live: Array[PackedInt32Array] = [
		world.unit_id,
		world.owner,
		world.type_index,
		world.pos_x,
		world.pos_y,
		world.hp,
		world.build_left
	]
	var columns: Array[PackedInt32Array] = view.columns()
	for rows: PackedInt32Array in [view.own_rows, view.seen_rows]:
		for row: int in rows:
			for column: int in columns.size():
				if columns[column][row] != live[column][row]:
					result.problems.append("%s: column %d row %d was written" % [tag, column, row])
					return
