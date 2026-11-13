extends GdUnitTestSuite
## Upgrades (plan row P246, ADR 0036 section 10): the research items WorldLoad makes, QUEUE and its
## drops, completion in PRODUCTION, the `mod_*` tables and their readers (`Combat.damage` in FIRE
## and PROJECTILES, the rupture, the ammo cap in `Air.run`), and the own bits in PlayerView.

const Rig: GDScript = preload("res://tests/sim/support/targeting_rig.gd")
const AiRig: GDScript = preload("res://tests/ai/support/opponent_rig.gd")
const AirWorlds: GDScript = preload("res://tests/sim/support/air_worlds.gd")
const RESEARCH_TICKS: int = 3
const COST: int = 200
## base damage 10 against a 100 percent armour share.
const BASE: int = 10


## The old formula, for the equivalence table.
func _old(base: int, percent: int) -> int:
	return maxi(1, base * percent / 100) if percent > 0 else 0


func test_damage_equals_the_old_formula_at_100_and_100_on_the_edge_ints() -> void:
	var bases: Array[int] = [0, 1, 7, 100, 99999, 2147483647, -5, -2147483648]
	var percents: Array[int] = [0, 1, 50, 100, 200, -1]
	for base: int in bases:
		for percent: int in percents:
			assert_int(Combat.damage(base, percent, 100, 100)).is_equal(_old(base, percent))


func test_damage_scales_with_both_modifiers_and_stays_at_least_one() -> void:
	assert_int(Combat.damage(10, 100, 150, 100)).is_equal(15)
	assert_int(Combat.damage(10, 100, 100, 50)).is_equal(5)
	assert_int(Combat.damage(10, 100, 150, 50)).is_equal(7)  # 7.5 truncates.
	assert_int(Combat.damage(1, 100, 50, 50)).is_equal(1)  # Never below 1 against a real share.
	assert_int(Combat.damage(10, 0, 400, 400)).is_equal(0)  # No share: nothing, whatever the mods.
	# The widest case the data allows stays inside int64: 2^31 * 200 * 400 * 400.
	assert_int(Combat.damage(2147483647, 200, 400, 400)).is_equal(2147483647 * 200 * 16 / 100)


func test_a_research_item_is_a_queue_only_type_per_upgrade() -> void:
	var world: World = _world()
	var item: int = world.type_ids.find(&"sharp")
	assert_int(item).is_greater(-1)
	assert_int(world.type_tab[item]).is_equal(World.Tab.RESEARCH)
	assert_int(world.type_upgrade[item]).is_equal(0)
	assert_int(world.type_cost[item]).is_equal(COST)
	assert_int(world.type_build_ticks[item]).is_equal(RESEARCH_TICKS)
	assert_int(world.type_speed[item]).is_equal(0)
	assert_int(world.type_foot_w[item]).is_equal(0)
	assert_int(world.type_requires[item]).is_equal(world.type_ids.find(&"centre"))
	assert_int(world.type_upgrade[world.type_ids.find(&"tank")]).is_equal(-1)
	assert_int(world.type_upgrade[world.type_ids.find(&"thick")]).is_equal(1)


func test_research_completes_sets_the_bit_rebuilds_the_tables_and_spawns_nothing() -> void:
	var world: World = _world()
	var item: int = world.type_ids.find(&"sharp")
	var rows: int = world.unit_count()
	assert_bool(Production.apply_queue(world, Command.queue(1, item))).is_true()
	assert_int(world.credits[1]).is_equal(1000 - COST)
	for _tick: int in RESEARCH_TICKS - 1:
		Production.run(world)
	assert_int(world.upgrades[1]).is_equal(0)
	Production.run(world)
	assert_int(world.upgrades[1]).is_equal(1)
	assert_int(world.upgrades[2]).is_equal(0)
	assert_int(world.queue_count[1 * World.TABS + World.Tab.RESEARCH]).is_equal(0)
	assert_int(world.unit_count()).is_equal(rows)
	var weapons: int = world.weapon_damage.size()
	var tank_weapon: int = world.type_weapon[world.type_ids.find(&"tank")]
	assert_int(world.mod_dealt[1 * weapons + tank_weapon]).is_equal(150)
	assert_int(world.mod_dealt[2 * weapons + tank_weapon]).is_equal(100)
	assert_int(Upgrades.dealt(world, 1, tank_weapon)).is_equal(150)


func test_a_second_queue_of_a_researched_or_queued_item_is_dropped() -> void:
	var world: World = _world()
	var item: int = world.type_ids.find(&"sharp")
	assert_bool(Production.apply_queue(world, Command.queue(1, item))).is_true()
	assert_bool(Production.apply_queue(world, Command.queue(1, item))).is_false()  # Queued.
	assert_int(world.credits[1]).is_equal(1000 - COST)
	for _tick: int in RESEARCH_TICKS:
		Production.run(world)
	assert_bool(Production.apply_queue(world, Command.queue(1, item))).is_false()  # Researched.
	assert_int(world.credits[1]).is_equal(1000 - COST)


func test_the_tables_are_rebuilt_from_the_bits_and_losing_the_centre_keeps_them() -> void:
	var world: World = _world()
	var tank: int = world.type_ids.find(&"tank")
	var types: int = world.type_ids.size()
	world.upgrades[1] = 6  # thick and racks.
	Upgrades.rebuild(world)
	assert_int(world.mod_taken[1 * types + tank]).is_equal(60)
	assert_int(world.mod_ammo[1 * types + tank]).is_equal(2)
	assert_int(Upgrades.extra_ammo(world, 1, tank)).is_equal(2)
	assert_int(Upgrades.extra_ammo(world, 2, tank)).is_equal(0)
	world.hp[world.index_of(1)] = 0  # The centre dies.
	world.remove_dead()
	assert_int(world.upgrades[1]).is_equal(6)
	assert_int(world.mod_taken[1 * types + tank]).is_equal(60)
	world.upgrades[1] = 0
	Upgrades.rebuild(world)
	assert_int(world.mod_taken[1 * types + tank]).is_equal(100)
	assert_int(world.mod_ammo[1 * types + tank]).is_equal(0)


func test_fire_applies_the_shooters_dealt_and_the_targets_taken_percent() -> void:
	# [player 1 bits, player 2 bits, damage]: sharp deals 150 percent, thick takes 60.
	for case: Array in [[0, 0, 10], [1, 0, 15], [0, 2, 6], [1, 2, 9]]:
		var world: World = _world()
		world.upgrades[1] = case[0]
		world.upgrades[2] = case[1]
		Upgrades.rebuild(world)
		var shooter: int = _unit(world, 1, "tank", 5000)
		var target: int = _unit(world, 2, "tank", 6000)
		world.target[shooter] = world.unit_id[target]
		Combat.fire(world)
		assert_int(100000 - world.hp[target]).is_equal(case[2])


func test_a_shell_takes_the_dealt_percent_of_its_owner_and_the_taken_of_the_target() -> void:
	var world: World = _world()
	world.upgrades[1] = 1
	world.upgrades[2] = 2
	Upgrades.rebuild(world)
	var shooter: int = _unit(world, 1, "shooter", 5000)
	var target: int = _unit(world, 2, "tank", 6000)
	world.target[shooter] = world.unit_id[target]
	Combat.fire(world)
	assert_int(world.hp[target]).is_equal(100000)  # In flight.
	for _tick: int in 20:
		Combat.advance_projectiles(world)
	# 10 damage, 150 percent dealt, 60 percent taken: 9.
	assert_int(100000 - world.hp[target]).is_equal(9)


func test_the_player_view_holds_only_its_own_bits() -> void:
	var world: World = _world()
	world.upgrades[1] = 3
	world.upgrades[2] = 1
	assert_int(PlayerView.of(world, 1).upgrades).is_equal(3)
	assert_int(PlayerView.of(world, 2).upgrades).is_equal(1)


func test_an_ammo_upgrade_raises_the_reload_cap_of_its_owner_only() -> void:
	var world: World = AirWorlds.world()
	var jet: int = AirWorlds.add_homed(world, "jet", AirWorlds.FIELD)
	var types: int = world.type_ids.size()
	var type: int = world.type_index[jet]
	world.mod_ammo.resize(3 * types)
	world.mod_ammo[1 * types + type] = 2
	world.ammo[jet] = AirWorlds.AMMO
	for _tick: int in 200:
		AirWorlds.step(world)
	assert_int(world.ammo[jet]).is_equal(AirWorlds.AMMO + 2)


func test_two_types_on_one_weapon_in_one_upgrade_apply_it_once() -> void:
	var world: World = _world()
	world.upgrades[1] = 8  # twin: the tank and the scout share one weapon.
	Upgrades.rebuild(world)
	var weapon: int = world.type_weapon[world.type_ids.find(&"tank")]
	assert_int(world.type_weapon[world.type_ids.find(&"scout")]).is_equal(weapon)
	assert_int(Upgrades.dealt(world, 1, weapon)).is_equal(150)
	assert_int(Combat.damage(10, 100, Upgrades.dealt(world, 1, weapon), 100)).is_equal(15)


func test_the_readers_answer_100_outside_their_table() -> void:
	var world: World = _world()
	world.upgrades[1] = 7
	Upgrades.rebuild(world)
	var weapons: int = world.weapon_damage.size()
	var types: int = world.type_ids.size()
	assert_int(Upgrades.dealt(world, 1, -1)).is_equal(100)
	assert_int(Upgrades.dealt(world, 1, weapons)).is_equal(100)  # Not player 2's first weapon.
	assert_int(Upgrades.taken(world, 1, types)).is_equal(100)
	assert_int(Upgrades.taken(world, 1, -1)).is_equal(100)
	assert_int(Upgrades.extra_ammo(world, 9, 0)).is_equal(0)


func test_a_rupture_applies_taken_and_dealt_stays_100() -> void:
	var world: World = _world()
	var ruptor: int = world.type_ids.find(&"ruptor")
	world.add_building(1, ruptor, 14, 2)
	var target: int = _unit(world, 2, "tank", 12000)
	world.upgrades[1] = 15 & ~2  # The striker has every dealt bit: they must not count.
	world.upgrades[2] = 2  # thick: the target takes 60 percent.
	Upgrades.rebuild(world)
	world.strike_x[1] = world.pos_x[target]
	world.strike_y[1] = world.pos_y[target]
	Strike._land(world, 1)
	assert_int(100000 - world.hp[target]).is_equal(60)  # 100 * 100 percent * 60 percent.


func test_a_research_item_is_no_unit_for_the_caps_and_the_ai() -> void:
	var world: World = _world()
	var item: int = world.type_ids.find(&"sharp")
	var mobile: int = ProductionSpawn.mobile_rows(world, 1)
	world.unit_cap = mobile  # At the cap: a unit would be refused, a research item is not.
	assert_bool(Production.apply_queue(world, Command.queue(1, item))).is_true()
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_equal(mobile)
	var economy: AiEconomy = AiEconomy.create(AiRig.def_of("fossil"), AiRig.level_of("normal"), 1)
	var view: PlayerView = PlayerView.of(world, 1)
	economy._take_census(view)
	assert_int(economy._units).is_equal(mobile)
	assert_bool(economy._buildable(view, world.type_ids.find(&"twin"))).is_true()
	for _tick: int in RESEARCH_TICKS:
		Production.run(world)
	assert_int(world.upgrades[1]).is_equal(1)
	assert_int(ProductionSpawn.mobile_rows(world, 1)).is_equal(mobile)
	assert_int(world.unit_count()).is_equal(2 + mobile)


func test_research_waits_for_the_centre_and_a_defeated_owner_and_cancel_refunds() -> void:
	var world: World = _world()
	var item: int = world.type_ids.find(&"sharp")
	var queue: int = 1 * World.TABS + World.Tab.RESEARCH
	assert_bool(Production.apply_queue(world, Command.queue(1, item))).is_true()
	Production.run(world)
	world.hp[world.index_of(1)] = 0  # The centre dies.
	world.remove_dead()
	for _tick: int in 10:
		Production.run(world)
	assert_int(world.queue_progress[queue]).is_equal(Production.PROGRESS_PER_TICK)
	assert_int(world.upgrades[1]).is_equal(0)
	var refund_to: int = world.credits[1]
	assert_bool(Production.apply_cancel(world, Command.new())).is_false()
	var cancel: Command = Command.cancel(1, World.Tab.RESEARCH, 0)
	assert_bool(Production.apply_cancel(world, cancel)).is_true()
	assert_int(world.credits[1]).is_equal(refund_to + COST)
	# A defeated owner's research stands still too.
	var other: World = _world()
	assert_bool(Production.apply_queue(other, Command.queue(1, item))).is_true()
	other.defeated_tick[1] = 1
	for _tick: int in 10:
		Production.run(other)
	assert_int(other.queue_progress[queue]).is_equal(0)


func test_a_second_owners_aircraft_keep_the_plain_ammo_cap() -> void:
	var world: World = AirWorlds.world()
	var types: int = world.type_ids.size()
	var first: int = AirWorlds.add_homed(world, "jet", AirWorlds.FIELD)
	world.mod_ammo.resize(3 * types)
	world.mod_ammo[1 * types + world.type_index[first]] = 2
	var field: Vector2i = Air.pad_point(world, world.index_of(AirWorlds.FIELD), 0)
	var second: int = AirWorlds.add(world, 2, "jet", field.x, field.y)
	world.home[second] = AirWorlds.FIELD
	world.ammo[first] = AirWorlds.AMMO
	world.ammo[second] = AirWorlds.AMMO
	Air._service(world, world.index_of(AirWorlds.FIELD), second, world.tick + 1)
	assert_int(world.ammo[second]).is_equal(AirWorlds.AMMO)  # Player 2 has no extra shots.
	Air._service(world, world.index_of(AirWorlds.FIELD), first, world.tick + 1)
	assert_int(world.ammo[first]).is_equal(AirWorlds.AMMO + 1)


## `prepare()` sizes the three tables and fills them with their neutral values (no restore path
## exists, so this is the load path: ADR 0036 section 3's "rebuilt by `prepare()`").
func test_prepare_sizes_the_tables_and_fills_them_neutral() -> void:
	var world: World = _world()
	var players: int = world.player_count + 1
	assert_int(world.mod_dealt.size()).is_equal(players * world.weapon_damage.size())
	assert_int(world.mod_taken.size()).is_equal(players * world.type_ids.size())
	assert_int(world.mod_ammo.size()).is_equal(players * world.type_ids.size())
	assert_int(world.mod_dealt.count(100)).is_equal(world.mod_dealt.size())
	assert_int(world.mod_taken.count(100)).is_equal(world.mod_taken.size())
	assert_int(world.mod_ammo.count(0)).is_equal(world.mod_ammo.size())


## Two Worlds from one scenario and one command stream, a research completing mid-run: the tables
## and the hash agree at the end, and the research took effect.
func test_two_runs_of_one_command_stream_agree_on_the_tables_and_the_hash() -> void:
	var worlds: Array[World] = [_world(), _world()]
	var none: Array[Command] = []
	for world: World in worlds:
		var queued: Array[Command] = [
			Command.queue(1, world.type_ids.find(&"thick")),
			Command.queue(1, world.type_ids.find(&"racks"))
		]
		for command: Command in queued:
			command.tick = world.tick
		for tick: int in 12:
			Sim.step(world, queued if tick == 0 else none)
	assert_int(worlds[0].upgrades[1]).is_equal(6)
	assert_int(worlds[0].mod_taken.count(60)).is_equal(1)
	assert_array(worlds[1].mod_dealt).is_equal(worlds[0].mod_dealt)
	assert_array(worlds[1].mod_taken).is_equal(worlds[0].mod_taken)
	assert_array(worlds[1].mod_ammo).is_equal(worlds[0].mod_ammo)
	assert_int(worlds[1].state_hash()).is_equal(worlds[0].state_hash())


## Two players; player 1's engineering centre, player 2's headquarters, 1000 credits each. Upgrades:
## "sharp" (bit 0: the tank's weapon deals 150 percent, and the ammo +2 is "thick"'s) and "thick"
## (bit 1: tanks take 60 percent, plus 2 ammo).
func _world() -> World:
	var hq: BuildingDef = _building(&"hq", World.Tab.STRUCTURES)
	var centre: BuildingDef = _building(&"centre", World.Tab.RESEARCH)
	var tank: UnitDef = Rig.unit(&"tank", 6000, 5000, 4000, 0, [100, 100, 100, 100])
	tank.max_hp = 100000
	var shooter: UnitDef = Rig.unit(&"shooter", 6000, 5000, 4000, 0, [100, 100, 100, 100])
	shooter.weapon.projectile_speed = 500
	var scout: UnitDef = Rig.unit(&"scout", 6000, 5000, 4000, 0, [100, 100, 100, 100])
	scout.weapon = tank.weapon  # Two types on one weapon.
	var ruptor: BuildingDef = _building(&"ruptor", World.Tab.STRUCTURES)
	ruptor.strike_kind = 1
	ruptor.strike_radius = 2000
	ruptor.strike_weapon = WeaponDef.new()
	ruptor.strike_weapon.id = &"rupture"
	ruptor.strike_weapon.damage = 100
	ruptor.strike_weapon.vs_armour = PackedInt32Array([100, 100, 100, 100])
	var scenario: ScenarioDef = ScenarioDef.new()
	scenario.map_size_tiles = Vector2i(24, 16)
	scenario.player_count = 2
	scenario.rules = load(Rig.RULES_PATH) as RulesDef
	scenario.roster.assign([hq, centre, tank, shooter, scout, ruptor])
	var faction: FactionDef = FactionDef.new()
	faction.id = &"fossil"
	faction.upgrades.append(
		_upgrade(&"sharp", UpgradeDef.Stat.DAMAGE_DEALT, 150, [tank, shooter], centre)
	)
	var thick: UpgradeDef = _upgrade(&"thick", UpgradeDef.Stat.DAMAGE_TAKEN, 60, [tank], centre)
	faction.upgrades.append(thick)
	faction.upgrades.append(_upgrade(&"racks", UpgradeDef.Stat.AMMO, 2, [tank], centre))
	faction.upgrades.append(
		_upgrade(&"twin", UpgradeDef.Stat.DAMAGE_DEALT, 150, [tank, scout], centre)
	)
	scenario.factions.append(faction)
	var world: World = World.from_scenario(scenario)
	Rig.reveal(world)
	world.add_building(1, world.type_ids.find(&"centre"), 2, 2)
	world.add_building(2, world.type_ids.find(&"hq"), 18, 10)
	world.credits[1] = 1000
	world.credits[2] = 1000
	return world


func _unit(world: World, player: int, id: String, x: int) -> int:
	world.add_unit(player, world.type_ids.find(StringName(id)), x, 8000)
	return world.unit_id.size() - 1


func _building(id: StringName, produces: int) -> BuildingDef:
	var def: BuildingDef = BuildingDef.new()
	def.type_id = id
	def.faction = &"fossil"
	def.max_hp = 2000
	def.armour = World.Armour.BUILDING
	def.footprint = Vector2i(3, 3)
	def.sight_range = 4000
	def.produces = produces
	return def


func _upgrade(
	id: StringName, stat: int, value: int, types: Array, requires: BuildingDef
) -> UpgradeDef:
	var def: UpgradeDef = UpgradeDef.new()
	def.id = id
	def.faction = &"fossil"
	def.cost = COST
	def.research_ticks = RESEARCH_TICKS
	def.requires = requires
	def.stat = stat
	def.value = value
	def.applies_to.assign(types)
	return def
