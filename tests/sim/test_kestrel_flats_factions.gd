extends GdUnitTestSuite
## What each Kestrel Flats start may build (plan row P79, ADR 0023 section 6): a producer queues
## the types of its own faction only. The rule is P106's one condition, `type_faction[type] !=
## type_faction[producer]`; these cases run it on the shipped rosters of both scenarios, from the
## start and from a base that owns every building of both factions (so that nothing but the faction
## can refuse a QUEUE: the requirements are met, the producers are the player's own and the credits
## and the queue room are there).

const Rig: GDScript = preload("res://tests/sim/support/kestrel_rig.gd")
const ProdRig: GDScript = preload("res://tests/sim/support/production_worlds.gd")
const RICH: int = 100000


func _faction(path: String, player: int) -> FactionDef:
	return (load(path) as ScenarioDef).factions[player]


func _type(world: World, id: StringName) -> int:
	return world.type_ids.find(id)


## `player`'s faction index in the World's `faction_ids`: that of the type of its first building.
func _own_index(world: World, player: int) -> int:
	return world.type_faction[world.type_index[Rig.building_rows(world, player)[0]]]


## The scenario's World with one of every building of both factions added for `player` on a staging
## grid in the middle of the map: the player's own faction first, so that the lowest-id producer of
## every tab is the player's own (`Production.producer_row`). The Headquarters it starts with is
## not added twice. The credits are made rich.
@warning_ignore("integer_division")
func _staged(path: String, player: int) -> World:
	var world: World = Rig.world(path)
	var scenario: ScenarioDef = load(path) as ScenarioDef
	var owned: Array[int] = []
	for row: int in Rig.building_rows(world, player):
		owned.append(world.type_index[row])
	var slot: int = 0
	for faction: FactionDef in [scenario.factions[player], scenario.factions[3 - player]]:
		for unit: UnitDef in faction.roster:
			var type: int = _type(world, unit.type_id)
			if not unit is BuildingDef or owned.has(type):
				continue
			var id: int = world.add_building(player, type, 18 + slot % 5 * 4, 18 + slot / 5 * 4)
			assert_int(id).override_failure_message(String(unit.type_id)).is_not_equal(0)
			slot += 1
	world.credits[player] = RICH
	return world


func test_every_roster_type_of_a_start_has_its_players_faction() -> void:
	for path: String in Rig.PATHS:
		var world: World = Rig.world(path)
		var types: int = 0
		for player: int in [1, 2]:
			var faction: FactionDef = _faction(path, player)
			for unit: UnitDef in faction.roster:
				var type: int = _type(world, unit.type_id)
				assert_int(type).override_failure_message(String(unit.type_id)).is_greater(-1)
				var named: StringName = world.faction_ids[world.type_faction[type]]
				assert_str(String(named)).override_failure_message(String(unit.type_id)).is_equal(
					String(faction.id)
				)
				types += 1
			# A research type is the faction's too (P249: two upgrades each).
			for up: UpgradeDef in faction.upgrades:
				var research: int = _type(world, up.id)
				assert_int(research).override_failure_message(String(up.id)).is_greater(-1)
				var owner: StringName = world.faction_ids[world.type_faction[research]]
				assert_str(String(owner)).override_failure_message(String(up.id)).is_equal(
					String(faction.id)
				)
				types += 1
		# Both rosters are registered with their research types and nothing else: twenty-six types
		# each (52: twenty-four roster types and the two upgrades; 50 before P280 put the medic
		# squads in, 48 before P279 put the repair buildings in, 46 before P292 put the minelayers
		# in, 44 before P291 put the carriers in, 38 before P249 put the engineering centres and
		# the research in, 34 before P245, 32 before P245b, 30 before P239b).
		assert_int(types).is_equal(52)
		assert_int(world.type_ids.size()).is_equal(52)
		assert_array(world.faction_ids).contains_exactly_in_any_order([&"fossil", &"renew"])


## From the start: the Headquarters queues its own faction's power plant and drops the other's, and
## the drop is counted (the commands are given in one tick, in the order of their sequences).
func test_from_the_start_a_headquarters_queues_its_own_power_plant_and_drops_the_others() -> void:
	for path: String in Rig.PATHS:
		for player: int in [1, 2]:
			var world: World = Rig.world(path)
			var own: StringName = _faction(path, player).id
			var other: StringName = _faction(path, 3 - player).id
			var credits: int = world.credits[player]
			var queue: int = ProdRig.queue_of(player, World.Tab.STRUCTURES)
			var label: String = "%s player %d" % [path, player]
			var refused: Command = Command.queue(player, _type(world, Rig.POWER[other]))
			ProdRig.step(world, [refused])
			assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
			assert_int(world.queue_count[queue]).is_equal(0)
			assert_int(world.credits[player]).is_equal(credits)
			var accepted: Command = Command.queue(player, _type(world, Rig.POWER[own]))
			ProdRig.step(world, [accepted])
			assert_int(world.dropped_commands).override_failure_message(label).is_equal(1)
			assert_array(ProdRig.items(world, player, World.Tab.STRUCTURES)).is_equal(
				[_type(world, Rig.POWER[own])]
			)
			assert_int(world.credits[player]).is_equal(
				credits - world.type_cost[accepted.payload[0]]
			)


## Every buildable type of the other faction is dropped and counted, whatever its tab, from a base
## that owns every building of both factions: one drop each, nothing queued, nothing paid.
func test_every_buildable_type_of_the_other_faction_is_dropped_and_counted() -> void:
	for path: String in Rig.PATHS:
		for player: int in [1, 2]:
			var world: World = _staged(path, player)
			var commands: Array[Command] = []
			for unit: UnitDef in _faction(path, 3 - player).roster:
				if unit.tab >= 0:
					var command: Command = Command.queue(player, _type(world, unit.type_id))
					command.sequence = commands.size()
					commands.append(command)
			for up: UpgradeDef in _faction(path, 3 - player).upgrades:
				var research: Command = Command.queue(player, _type(world, up.id))
				research.sequence = commands.size()
				commands.append(research)
			# Twenty-five items: twenty-three roster types (the headquarters is the one type nothing
			# builds) and two research types (twenty-four items before P280 added the medic squads,
			# twenty-three items before P279 added the repair
			# buildings, twenty-two before P292 added the minelayers,
			# twenty-one before P291 added the carriers, eighteen items and no research before
			# P249, sixteen before P245 added the aircraft, fifteen before P245b added the
			# airfield).
			assert_int(commands.size()).is_equal(25)
			var label: String = "%s player %d" % [path, player]
			ProdRig.step(world, commands)
			assert_int(world.dropped_commands).override_failure_message(label).is_equal(25)
			for tab: int in World.TABS:
				var queue: int = ProdRig.queue_of(player, tab)
				assert_int(world.queue_count[queue]).override_failure_message(label).is_equal(0)
			assert_int(world.credits[player]).is_equal(RICH)


## The faction is the one thing that refuses them: with a type's faction set to the player's own,
## the same QUEUE is accepted, at each of the three tabs.
func test_the_faction_alone_refuses_the_other_factions_power_plant_rifle_and_tank() -> void:
	for path: String in Rig.PATHS:
		for player: int in [1, 2]:
			var world: World = _staged(path, player)
			var other: StringName = _faction(path, 3 - player).id
			for ids: Dictionary[StringName, StringName] in [Rig.POWER, Rig.RIFLE, Rig.TANK]:
				var type: int = _type(world, ids[other])
				var queue: Command = Command.queue(player, type)
				var label: String = "%s player %d %s" % [path, player, ids[other]]
				(
					assert_bool(Production.apply_queue(world, queue))
					. override_failure_message(label)
					. is_false()
				)
				world.type_faction[type] = _own_index(world, player)
				(
					assert_bool(Production.apply_queue(world, queue))
					. override_failure_message(label)
					. is_true()
				)


## Its own faction's three items are accepted at their three tabs from the same base, and paid.
func test_a_base_queues_its_own_factions_power_plant_rifle_and_tank() -> void:
	for path: String in Rig.PATHS:
		for player: int in [1, 2]:
			var world: World = _staged(path, player)
			var own: StringName = _faction(path, player).id
			var commands: Array[Command] = []
			var cost: int = 0
			for ids: Dictionary[StringName, StringName] in [Rig.POWER, Rig.RIFLE, Rig.TANK]:
				var type: int = _type(world, ids[own])
				cost += world.type_cost[type]
				var command: Command = Command.queue(player, type)
				command.sequence = commands.size()
				commands.append(command)
			ProdRig.step(world, commands)
			var label: String = "%s player %d" % [path, player]
			assert_int(world.dropped_commands).override_failure_message(label).is_equal(0)
			assert_int(world.credits[player]).is_equal(RICH - cost)
			for tab: int in World.Tab.VEHICLES + 1:  # One item on each of the three drawer tabs.
				assert_int(ProdRig.items(world, player, tab).size()).is_equal(1)
			for tab: int in range(World.Tab.VEHICLES + 1, World.TABS):  # FLIGHT and RESEARCH: none.
				assert_int(ProdRig.items(world, player, tab).size()).is_equal(0)
