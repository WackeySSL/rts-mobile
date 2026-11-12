extends RefCounted
## The air, repair-role and upgrade data rules of P231 (ADR 0036 section 2, ADR 0037 section 2),
## one text per broken rule, and the builders of the defs that break none. test_defs_data_air pins
## them on built defs and holds every shipped file to them. The World copies these fields since
## P232 (test_world_v6); the shipped data holds none until the air data of P233 and later ships.
## The constants read the World's enums; `REVEAL` follows with P233. The ranges of move_class, tab,
## produces and strike_kind stay in test_defs_data, read from the World enums.

const AIR: int = World.MoveClass.AIR
## 1 << AIR: the AIR bit of a move-class mask (ADR 0036 section 2).
const AIR_BIT: int = 1 << AIR
const FLIGHT: int = World.Tab.FLIGHT
const RESEARCH: int = World.Tab.RESEARCH
## Strike.Kind.REVEAL from P233.
const REVEAL: int = 3
const MAX_PERCENT: int = 400
const MAX_SLOTS: int = 8
const MIN_REACH: int = 500
const MASK_MAX: int = 15
const MILLI_SQUARED: int = 1000000


## A mobile ground unit that breaks no rule when its file is tank.tres.
static func fine_unit() -> UnitDef:
	var unit: UnitDef = UnitDef.new()
	unit.type_id = &"tank"
	unit.speed = 120
	unit.radius = 300
	return unit


## A 2x2 building that breaks no rule when its file is depot.tres.
static func fine_building() -> BuildingDef:
	var building: BuildingDef = BuildingDef.new()
	building.footprint = Vector2i(2, 2)
	building.armour = 3
	building.build_ticks = 1
	return building


## A mobile ground unit with the repair role (a medic): classes FOOT, 1 slot, reach 500.
static func fine_healer() -> UnitDef:
	var unit: UnitDef = fine_unit()
	unit.repair_classes = 1
	unit.repair_hp = 5
	unit.repair_reach_milli = MIN_REACH
	unit.repair_slots = 1
	return unit


## An aircraft with ammo: move class AIR, 6 shots, 30 ticks to rearm.
static func fine_air() -> UnitDef:
	var unit: UnitDef = fine_unit()
	unit.move_class = AIR
	unit.ammo = 6
	unit.rearm_ticks = 30
	return unit


## An airfield: a 3x3 building that produces FLIGHT, two pads two tiles apart, the AIR bit only.
static func fine_airfield() -> BuildingDef:
	var field: BuildingDef = fine_building()
	field.footprint = Vector2i(3, 3)
	field.produces = FLIGHT
	field.pads = 2
	field.pad_offsets = [Vector2i(0, 0), Vector2i(2, 0)] as Array[Vector2i]
	field.repair_classes = AIR_BIT
	field.repair_hp = 10
	field.repair_period_ticks = 15
	field.repair_reach_milli = 1500
	return field


## An upgrade of the faction "fossil" that breaks no rule: +100 percent damage dealt, needs a
## building, changes one aircraft with ammo.
static func fine_upgrade() -> UpgradeDef:
	var up: UpgradeDef = UpgradeDef.new()
	up.id = &"better_bombs"
	up.faction = &"fossil"
	up.requires = BuildingDef.new()
	up.applies_to = [fine_air()] as Array[UnitDef]
	return up


## One text per broken air or repair-role rule of a unit or building file; empty when fine.
static func air_problems(file: String, unit: UnitDef) -> PackedStringArray:
	var pads: int = 0
	if unit is BuildingDef:
		pads = (unit as BuildingDef).pads
	# A type with pads needs the role's numbers too, whatever its classes say.
	var role: bool = unit.repair_classes != 0 or pads > 0
	var broken: Dictionary[String, bool] = {
		"low_flying is for AIR only": unit.low_flying and unit.move_class != AIR,
		# ADR 0036 section 9: a drone squad has no ammo and no pad.
		"a low-flying type has ammo": unit.low_flying and unit.ammo != 0,
		"ammo is for AIR only": unit.ammo != 0 and unit.move_class != AIR,
		"rearm_ticks is for AIR only": unit.rearm_ticks != 0 and unit.move_class != AIR,
		"ammo is negative": unit.ammo < 0,
		"rearm_ticks is negative": unit.rearm_ticks < 0,
		"ammo needs rearm_ticks of at least 1": unit.ammo > 0 and unit.rearm_ticks < 1,
		"repair_classes is not a move-class mask 0..15":
		unit.repair_classes < 0 or unit.repair_classes > MASK_MAX,
		"repair_period_ticks is below 1": unit.repair_period_ticks < 1,
		"repair_cost_percent is not in 0..100":
		unit.repair_cost_percent < 0 or unit.repair_cost_percent > 100,
		"repair_hp is below 1": role and unit.repair_hp < 1,
		"repair_reach_milli is below 500": role and unit.repair_reach_milli < MIN_REACH,
		# ADR 0037 section 2: 1-8 for a type without pads, 0 only with pads.
		"repair_slots is not in 1..8":
		role and pads == 0 and (unit.repair_slots < 1 or unit.repair_slots > MAX_SLOTS),
		"repair_slots is not in 0..8":
		pads > 0 and (unit.repair_slots < 0 or unit.repair_slots > MAX_SLOTS),
		"repair_seek_milli is negative": unit.repair_seek_milli < 0,
		"no type is on the Research tab": unit.tab == RESEARCH,
	}
	if unit is BuildingDef:
		var building: BuildingDef = unit
		broken["a building has repair_seek_milli"] = building.repair_seek_milli != 0
		broken["pads differs from the pad_offsets count"] = (
			building.pads != building.pad_offsets.size()
		)
		broken["an airfield does not serve AIR only"] = pads > 0 and unit.repair_classes != AIR_BIT
		broken["produces FLIGHT and having pads differ"] = (
			(building.produces == FLIGHT) != (pads > 0)
		)
		broken["a Reveal building has a strike radius, delay, length or weapon"] = (
			building.strike_kind == REVEAL
			and (
				building.strike_radius != 0
				or building.strike_delay != 0
				or building.strike_ticks != 0
				or building.strike_weapon != null
			)
		)
		for i: int in building.pad_offsets.size():
			var at: Vector2i = building.pad_offsets[i]
			if at.x < 0 or at.y < 0 or at.x >= building.footprint.x or at.y >= building.footprint.y:
				broken["a pad lies outside the footprint"] = true
			if building.pad_offsets.find(at) != i:
				broken["two pads share a tile"] = true
	var problems: PackedStringArray = PackedStringArray()
	for message: String in broken:
		if broken[message]:
			problems.append("%s: %s" % [file, message])
	return problems


## Pads at least `spacing` milli-tiles apart (the largest FLIGHT formation_spacing), or waiting
## aircraft drift out of repair reach (ADR 0036 section 6). Offsets are in tiles.
static func pad_spacing_problems(
	file: String, building: BuildingDef, spacing: int
) -> PackedStringArray:
	var near: bool = false
	for i: int in building.pad_offsets.size():
		for j: int in range(i + 1, building.pad_offsets.size()):
			var d: Vector2i = building.pad_offsets[j] - building.pad_offsets[i]
			near = near or (d.x * d.x + d.y * d.y) * MILLI_SQUARED < spacing * spacing
	if near:
		return PackedStringArray(["%s: pads are closer than the largest FLIGHT spacing" % file])
	return PackedStringArray()


## One text per broken rule of an upgrade of the faction `faction_id`; empty when fine.
static func upgrade_problems(
	file: String, up: UpgradeDef, faction_id: StringName
) -> PackedStringArray:
	var gone: bool = false
	var no_ammo: bool = false
	for type: UnitDef in up.applies_to:
		gone = gone or type == null
		no_ammo = no_ammo or (type != null and type.ammo < 1)
	var percent: bool = up.stat != UpgradeDef.Stat.AMMO
	var broken: Dictionary[String, bool] = {
		"cost is negative": up.cost < 0,
		"research_ticks is below 1": up.research_ticks < 1,
		"stat is not a stat":
		up.stat < UpgradeDef.Stat.DAMAGE_DEALT or up.stat > UpgradeDef.Stat.AMMO,
		"value is not in 1..400 percent": percent and (up.value < 1 or up.value > MAX_PERCENT),
		"an ammo upgrade adds less than 1 shot": not percent and up.value < 1,
		"requires is not set": up.requires == null,
		"applies_to is empty": up.applies_to.is_empty(),
		"applies_to has a null entry": gone,
		"an ammo upgrade applies to a type without ammo": not percent and no_ammo,
		"faction differs from its faction file": up.faction != faction_id,
	}
	var problems: PackedStringArray = PackedStringArray()
	for message: String in broken:
		if broken[message]:
			problems.append("%s: %s" % [file, message])
	return problems


## The rules that span files. The 400 % bound is per modifier, so (a choice, P246's combination is
## then a plain product of one value each) at most one upgrade changes one stat of one type of a
## faction. Upgrade ids may not equal type ids: research items become types, and World merges equal
## ids. A type on Research is a fault in air_problems.
static func upgrade_catalog_problems(
	units: Array[UnitDef], factions: Array[FactionDef]
) -> PackedStringArray:
	var problems: PackedStringArray = PackedStringArray()
	var type_ids: Dictionary[String, bool] = {}
	for unit: UnitDef in units:
		type_ids[String(unit.type_id)] = true
	var changed: Dictionary[String, String] = {}
	for faction: FactionDef in factions:
		for up: UpgradeDef in faction.upgrades:
			if type_ids.has(String(up.id)):
				problems.append("%s: upgrade id is also a type id" % up.id)
			for type: UnitDef in up.applies_to:
				if type == null:
					continue
				var key: String = "%s/%s/%d" % [faction.id, type.type_id, up.stat]
				if changed.has(key):
					problems.append(
						"%s and %s change one stat of %s" % [changed[key], up.id, type.type_id]
					)
				changed[key] = String(up.id)
	return problems
