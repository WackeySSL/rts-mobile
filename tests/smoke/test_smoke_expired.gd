extends GdUnitTestSuite
## Smoke.expired_in and the expired count of Smoke.run (ADR 0038 section 6, the lead's note of
## 2026-11-14): a Command is expired when its units are all gone (or not the player's) or its ATTACK
## target is gone, and the smoke excuses only the ones that went in the lag tick, never one that was
## already invalid at its view tick.

const Smoke: GDScript = preload("res://tests/smoke/smoke_run.gd")
const GhostAi: GDScript = preload("res://tests/smoke/support/ghost_ai.gd")
const NORMAL: Array[String] = ["normal", "normal"]
const GONE: int = 888888


## A World with its units, and the id of one unit of player 1 and one of player 2.
func _world() -> Dictionary:
	var world: World = Smoke.start(1, "derrick", NORMAL)["world"]
	var mine: int = -1
	var theirs: int = -1
	for row: int in world.unit_count():
		if world.owner[row] == 1 and mine < 0:
			mine = world.unit_id[row]
		if world.owner[row] == 2 and theirs < 0:
			theirs = world.unit_id[row]
	return {"world": world, "mine": mine, "theirs": theirs}


func _commands(mine: int, theirs: int) -> Dictionary:
	return {
		"alive": Command.move(1, PackedInt32Array([mine]), 10500, 4500),
		"unit_gone": Command.move(1, PackedInt32Array([GONE]), 10500, 4500),
		"not_mine": Command.stop(1, PackedInt32Array([theirs])),
		"mixed": Command.move(1, PackedInt32Array([GONE, mine]), 10500, 4500),
		"target_ok": Command.attack(1, PackedInt32Array([mine]), theirs),
		"target_gone": Command.attack(1, PackedInt32Array([mine]), GONE),
		"both_gone": Command.attack(1, PackedInt32Array([GONE]), GONE),
		"place": Command.new(),
	}


func test_expired_is_a_unit_order_with_no_unit_left_or_an_attack_on_a_gone_target() -> void:
	var setup: Dictionary = _world()
	var world: World = setup["world"]
	var named: Dictionary = _commands(setup["mine"], setup["theirs"])
	named["place"].type = Command.Type.PLACE
	var expected: Dictionary[String, bool] = {
		"alive": false,
		"unit_gone": true,
		"not_mine": true,
		"mixed": false,
		"target_ok": false,
		"target_gone": true,
		"both_gone": true,
		"place": false,
	}
	for key: String in expected:
		var one: Array[Command] = [named[key]]
		assert_int(Smoke.expired_in(world, one)).override_failure_message(key).is_equal(
			1 if expected[key] else 0
		)
	var all: Array[Command] = []
	for key: String in expected:
		all.append(named[key])
	assert_int(Smoke.expired_in(world, all)).is_equal(4)


## The expired count of a run excuses a death in the lag tick and nothing else: a controller that
## orders a unit that never existed has every Command dropped and none expired, so the whole count
## is stale.
func test_a_command_already_gone_at_its_view_tick_is_stale_not_expired() -> void:
	var setup: Dictionary = Smoke.start(1, "derrick", NORMAL)
	var world: World = setup["world"]
	var ghost: AiController = GhostAi.new()
	ghost.player_id = 1
	ghost.think_period = 5
	ghost.think_offset = 0
	var controllers: Array[AiController] = [ghost]
	var expired: int = Smoke.run(world, setup["loop"], controllers, 40)
	assert_int(expired).is_equal(0)
	assert_int(ghost.get(&"sent")).is_equal(8)
	# The thinks of ticks 0 to 35 are applied; the one of tick 35 lands at 36, inside the 40.
	assert_int(world.dropped_commands).is_equal(8)
