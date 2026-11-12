extends GdUnitTestSuite
## The strike button with a space centre (plan P235, ADR 0036 sections 11 and 12): the sweep has
## no aim, so a ready REVEAL building lights the check mark at once and a confirm sends one
## SUPERWEAPON with no point; a sweep that stands, and its spare centres, never count as ready
## (the sim drops them), so a Deep Bore beside a fired space centre keeps the button; low power
## refuses the sweep. Every "ready" is proven against `Strike.apply_superweapon` on the same World.
## The World is reveal_worlds.gd's (two space centres and a Deep Bore of player 1, 40 ticks charge).

const Reveals: GDScript = preload("res://tests/sim/support/reveal_worlds.gd")
const Rig: GDScript = preload("res://tests/input/support/strike_rig.gd")
const MenuRig: GDScript = preload("res://tests/support/menu_rig.gd")

var _world: World
var _aim: StrikeAim
var _sent: Array[Command] = []


func before_test() -> void:
	MenuRig.begin()
	_world = Reveals.world()
	_sent.clear()
	var controller: PlayerController = auto_free(PlayerController.new())
	controller.settings = InputSettings.new()
	controller.command_sink = func(command: Command) -> void: _sent.append(command)
	controller.vibrate = func(_ms: int) -> void: pass
	_aim = auto_free(StrikeAim.new())
	_aim.controller = controller


func after_test() -> void:
	MenuRig.end()


func _ready_tick() -> void:
	while _world.tick < Reveals.fire_tick(_world, Reveals.SPACE_A):
		Reveals.step(_world)


func _read() -> void:
	if _aim.runner == null:
		_aim.runner = auto_free(Rig.runner(Rig.snapshot(_world)))
	_aim.runner.snapshot = Rig.snapshot(_world)
	_aim.refresh()


## Player 1 owns only its space centres: the Deep Bore and the blackout building change hands.
func _only_space_centres() -> void:
	_world.owner[_world.index_of(Reveals.BORE)] = 2
	_world.owner[_world.index_of(Reveals.ARRAY_1)] = 2


func test_a_ready_space_centre_has_no_aim_and_one_check_mark_sends_one_point_free_fire() -> void:
	_only_space_centres()
	_ready_tick()
	_read()
	assert_array([_aim.owned, _aim.reveal, _aim.building_id]).is_equal(
		[true, true, Reveals.SPACE_A]
	)
	assert_bool(_aim.begin()).is_true()
	assert_array([_aim.active, _aim.has_point]).is_equal([true, true])  # Lit, no map tap.
	_aim.place(Vector2i(9000, 9000))  # A map tap is no point of a sweep.
	assert_object(_aim.point).is_equal(Vector2i.ZERO)
	assert_bool(_aim.confirm()).is_true()
	assert_int(_sent.size()).is_equal(1)
	(
		assert_array([_sent[0].type, _sent[0].target_id, _sent[0].target_x, _sent[0].target_y])
		. is_equal([Command.Type.SUPERWEAPON, Reveals.SPACE_A, 0, 0])
	)
	assert_bool(Strike.apply_superweapon(_world, _sent[0])).is_true()  # The sim takes it.
	assert_array([_world.reveal_site[1], _world.reveal[1]]).is_equal([Reveals.SPACE_A, 1])
	assert_bool(_aim.active).is_false()
	assert_bool(_aim.confirm()).is_false()  # A second press is a no-op.
	assert_int(_sent.size()).is_equal(1)


func test_a_standing_sweep_never_reads_ready_and_the_deep_bore_keeps_the_button() -> void:
	_ready_tick()
	Reveals.step(_world, [Reveals.fire(Reveals.SPACE_A)])
	assert_array([_world.reveal_site[1], _world.reveal[1]]).is_equal([Reveals.SPACE_A, 1])
	_read()
	# The fired centre keeps its ready tick and the spare is dropped by the sim: neither binds.
	assert_array([_aim.building_id, _aim.reveal, _aim.sweep_bound]).is_equal(
		[Reveals.BORE, false, false]
	)
	assert_int(_aim.sweep).is_equal(Reveal.State.ON)  # The owner's sweep still shows.
	assert_bool(Strike.apply_superweapon(_world, Reveals.fire(Reveals.SPACE_B))).is_false()
	assert_bool(_aim.begin()).is_true()  # The aim is the Deep Bore's: it needs a point.
	assert_bool(_aim.has_point).is_false()
	assert_bool(_aim.confirm()).is_false()
	assert_array(_sent).is_empty()


func test_with_only_the_fired_centre_the_button_shows_the_sweep_and_cannot_fire() -> void:
	_only_space_centres()
	_ready_tick()
	Reveals.step(_world, [Reveals.fire(Reveals.SPACE_A)])
	_read()
	assert_array([_aim.owned, _aim.building_id, _aim.sweep_bound, _aim.sweep]).is_equal(
		[true, 0, true, Reveal.State.ON]
	)
	assert_bool(_aim.begin()).is_false()
	_world.reveal[1] = Reveal.State.PAUSED  # A blackout or low power: the state as the sim writes it.
	_read()
	assert_array([_aim.building_id, _aim.sweep_bound, _aim.sweep]).is_equal(
		[0, true, Reveal.State.PAUSED]
	)
	_world.reveal_site[1] = 0  # The sweep is over and the centre is back, charged: ready again.
	_world.reveal[1] = 0
	_read()
	assert_array([_aim.sweep, _aim.sweep_bound, _aim.reveal]).is_equal([0, false, true])


func test_a_sweep_ignores_a_rupture_in_the_air_and_the_bore_does_not() -> void:
	_ready_tick()
	_world.strike_tick[1] = _world.tick + 5
	_read()
	assert_array([_aim.building_id, _aim.reveal]).is_equal([Reveals.SPACE_A, true])
	assert_bool(Strike.apply_superweapon(_world, Reveals.fire(Reveals.SPACE_A))).is_true()


func test_low_power_refuses_the_sweep_dims_the_button_and_a_ready_bore_still_wins() -> void:
	_ready_tick()
	Reveals.drain(_world, 20, 14)
	Reveals.step(_world)
	assert_bool(Power.is_low(_world, 1)).is_true()
	_read()
	assert_array([_aim.building_id, _aim.low_power]).is_equal([Reveals.BORE, false])
	_only_space_centres()
	_read()
	assert_array([_aim.owned, _aim.building_id, _aim.reveal, _aim.low_power]).is_equal(
		[true, 0, true, true]
	)
	assert_bool(_aim.begin()).is_false()
	assert_bool(Strike.apply_superweapon(_world, Reveals.fire(Reveals.SPACE_A))).is_false()
	assert_int(_world.reveal[1]).is_equal(0)


func test_low_power_arriving_while_the_check_mark_is_lit_ends_the_aim() -> void:
	_only_space_centres()
	_ready_tick()
	_read()
	assert_bool(_aim.begin()).is_true()
	Reveals.drain(_world, 20, 14)
	Reveals.step(_world)
	_read()
	assert_bool(_aim.active).is_false()
	assert_bool(_aim.confirm()).is_false()
	assert_array(_sent).is_empty()
