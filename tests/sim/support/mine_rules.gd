extends RefCounted
## The ground-support data rules of P285 (ADR 0037 sections 7 and 8), one text per broken rule, and
## the builders of the defs that break none. test_defs_data_mine pins them on built defs and holds
## every shipped file to them. The shipped data holds no layer or ejecting carrier until P290.

const MAX_PERCENT: int = 100
const MAX_VS_PERCENT: int = 200


## A mobile ground unit that breaks no rule when its file is tank.tres.
static func fine_unit() -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = &"tank"
	unit.speed = 120
	unit.radius = 300
	return unit


## A minelayer: it lays a mine of a weapon with a blast, for 60 credits, finds mines in 3 tiles and
## never triggers one.
static func fine_layer() -> UnitDef:
	var unit: UnitDef = fine_unit()
	var mine: WeaponDef = WeaponDef.new()
	mine.id = &"shot_charge"
	mine.damage = 80
	mine.blast_milli = 1000
	unit.mine_weapon = mine
	unit.mine_cost = 60
	unit.mine_aware = true
	unit.detect_milli = 3000
	return unit


## A ground carrier: 4 squad slots (FOOT) and half of the hp left to the passengers.
static func fine_carrier() -> UnitDef:
	var unit: UnitDef = fine_unit()
	unit.carry_slots = 4
	unit.carry_classes = 1
	unit.carry_eject_percent = 50
	return unit


## One text per broken ground-support rule of a unit or building file; empty when fine.
static func mine_problems(file: String, unit: UnitDef) -> PackedStringArray:
	var layer: bool = unit.mine_weapon != null
	var broken: Dictionary[String, bool] = {
		"mine_cost is negative": unit.mine_cost < 0,
		"mine_cost is below 1": layer and unit.mine_cost < 1,
		"mine_cost needs a mine_weapon": not layer and unit.mine_cost != 0,
		"detect_milli is negative": unit.detect_milli < 0,
		"carry_eject_percent is not in 0..100":
		unit.carry_eject_percent < 0 or unit.carry_eject_percent > MAX_PERCENT,
		"carry_eject_percent needs carry_slots":
		unit.carry_eject_percent != 0 and unit.carry_slots < 1,
		"a mine weapon has no blast": layer and unit.mine_weapon.blast_milli < 1,
		"a mine weapon is also the gun": layer and unit.mine_weapon == unit.weapon,
	}
	if unit is BuildingDef:
		broken["a building lays a mine"] = layer
		broken["a building is mine-aware"] = unit.mine_aware
		broken["a building detects mines"] = unit.detect_milli != 0
		broken["a building ejects"] = unit.carry_eject_percent != 0
	var problems: PackedStringArray = PackedStringArray()
	for message: String in broken:
		if broken[message]:
			problems.append("%s: %s" % [file, message])
	return problems


## One text per broken rule of a mine weapon file (the strike-weapon pattern): damage, no range or
## flight (a mine blasts where it lies), 4 percents in 0..200, and an id equal to its file name.
static func mine_weapon_problems(
	file: String, weapon: WeaponDef, weapon_path: String
) -> PackedStringArray:
	var percents: Array = Array(weapon.vs_armour)
	var broken: Dictionary[String, bool] = {
		"mine weapon damage is below 1": weapon.damage < 1,
		"mine weapon has a range, a minimum range or a flight":
		weapon.range != 0 or weapon.min_range != 0 or weapon.projectile_speed != 0,
		"vs_armour is not 4 percents in 0..200":
		(
			percents.size() != 4
			or (percents.size() > 0 and (percents.min() < 0 or percents.max() > MAX_VS_PERCENT))
		),
		"mine weapon id %s differs from its file name" % weapon.id:
		String(weapon.id) != weapon_path.get_file().get_basename(),
	}
	var problems: PackedStringArray = PackedStringArray()
	for message: String in broken:
		if broken[message]:
			problems.append("%s: %s" % [file, message])
	return problems


## The weapon-id rule across files: a weapon id belongs to one file, whether the weapon is a gun,
## a strike weapon or a mine. World merges weapons by id (first wins), so a mine that shares an id
## with a gun would blast with the gun's numbers, or the gun with the mine's.
static func weapon_id_problems(units: Array) -> PackedStringArray:
	var files: Dictionary[String, String] = {}
	var problems: PackedStringArray = PackedStringArray()
	for unit: UnitDef in units:
		var weapons: Array[WeaponDef] = [unit.weapon, unit.mine_weapon]
		var building: BuildingDef = unit as BuildingDef
		if building != null:
			weapons.append(building.strike_weapon)
		for weapon: WeaponDef in weapons:
			if weapon == null:
				continue
			var id: String = String(weapon.id)
			if files.get(id, weapon.resource_path) != weapon.resource_path:
				problems.append(
					"%s: weapon id %s is used twice" % [unit.resource_path.get_file(), id]
				)
			files[id] = weapon.resource_path
	return problems
