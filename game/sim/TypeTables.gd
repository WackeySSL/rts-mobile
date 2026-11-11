class_name TypeTables
extends RefCounted
## The type tables of a World as a player's view reads them (ADR 0020 section 1, plan row P198c):
## copies of the World's per-type arrays, one entry per type index, and the three tables that are
## derived through each type's weapon. `PlayerView.of` takes them from here and hands them to the
## view under the same names (`view.type_cost`, ...), so this file is where their meaning lives.
## Pure: no Node, no clock, no World kept; `of` reads the World and writes nothing.
##
## Aliasing (ADR 0012 section 2): every array is a `duplicate()` of the World's, so it is the
## holder's own and never the World's. A view that takes one shares its storage with the holder
## until one side writes, and then the writer forks its own copy: a write through a view's table
## cannot reach the World or the holder.

## The armour classes of `World.Armour` (a test pins them equal), the width of `vs_armour`.
const ARMOUR_CLASSES: int = 4

## A cost in credits, the tab a type is built on and the type it requires (-1 for none), the tab a
## building produces (-1), the footprint in tiles (0 for a unit), the speed in milli-tiles a tick
## (0 for a building), the weapon index (-1 for none), a harvester's cargo capacity (0), the power a
## building makes (positive) or uses (negative), and the ticks a type takes to build.
var cost: PackedInt32Array = PackedInt32Array()
var tab: PackedInt32Array = PackedInt32Array()
var requires: PackedInt32Array = PackedInt32Array()
var produces: PackedInt32Array = PackedInt32Array()
var foot_w: PackedInt32Array = PackedInt32Array()
var foot_h: PackedInt32Array = PackedInt32Array()
var speed: PackedInt32Array = PackedInt32Array()
var weapon: PackedInt32Array = PackedInt32Array()
var harvest: PackedInt32Array = PackedInt32Array()
var power: PackedInt32Array = PackedInt32Array()
var build_ticks: PackedInt32Array = PackedInt32Array()
## Hit points, the armour class (`World.Armour`), the type's weapon range and minimum range in
## milli-tiles (0 for a type without a weapon), sight in milli-tiles as the World keeps it, the
## faction (an index into the World's faction ids, -1 for none), the strike kind (0 none, 1
## rupture, 2 blackout), its radius in milli-tiles and its charge in ticks.
var max_hp: PackedInt32Array = PackedInt32Array()
var armour: PackedInt32Array = PackedInt32Array()
var weapon_range: PackedInt32Array = PackedInt32Array()
var weapon_min_range: PackedInt32Array = PackedInt32Array()
var sight: PackedInt32Array = PackedInt32Array()
var faction: PackedInt32Array = PackedInt32Array()
var strike_kind: PackedInt32Array = PackedInt32Array()
var strike_radius: PackedInt32Array = PackedInt32Array()
var charge_ticks: PackedInt32Array = PackedInt32Array()
## The percent the type's weapon does against each armour class, flat `type * 4 + class`; all 0 for
## a type without a weapon.
var vs_armour: PackedInt32Array = PackedInt32Array()
## The type ids, and the dock offsets that make a type a refinery.
var ids: Array[StringName] = []
var dock_x: PackedInt32Array = PackedInt32Array()
var dock_y: PackedInt32Array = PackedInt32Array()


## The tables of `world` as it stands: copies, so a caller that writes one writes its own.
static func of(world: World) -> TypeTables:
	var tables: TypeTables = TypeTables.new()
	tables.cost = world.type_cost.duplicate()
	tables.tab = world.type_tab.duplicate()
	tables.requires = world.type_requires.duplicate()
	tables.produces = world.type_produces.duplicate()
	tables.foot_w = world.type_foot_w.duplicate()
	tables.foot_h = world.type_foot_h.duplicate()
	tables.speed = world.type_speed.duplicate()
	tables.weapon = world.type_weapon.duplicate()
	tables.harvest = world.type_harvest.duplicate()
	tables.power = world.type_power.duplicate()
	tables.build_ticks = world.type_build_ticks.duplicate()
	tables.dock_x = world.type_dock_x.duplicate()
	tables.dock_y = world.type_dock_y.duplicate()
	tables.ids = world.type_ids.duplicate()
	tables.max_hp = world.type_max_hp.duplicate()
	tables.armour = world.type_armour.duplicate()
	tables.sight = world.type_sight.duplicate()
	tables.faction = world.type_faction.duplicate()
	tables.strike_kind = world.type_strike_kind.duplicate()
	tables.strike_radius = world.type_strike_radius.duplicate()
	tables.charge_ticks = world.type_charge_ticks.duplicate()
	tables._take_weapon_tables(world)
	return tables


## `weapon_range`, `weapon_min_range` and `vs_armour`, read through each type's weapon.
func _take_weapon_tables(world: World) -> void:
	var weapons: PackedInt32Array = world.type_weapon
	var ranges: PackedInt32Array = world.weapon_range
	var min_ranges: PackedInt32Array = world.weapon_min_range
	var percents: PackedInt32Array = world.weapon_vs_armour
	var types: int = weapons.size()
	var made_range: PackedInt32Array = PackedInt32Array()
	var made_min: PackedInt32Array = PackedInt32Array()
	var made_percent: PackedInt32Array = PackedInt32Array()
	made_range.resize(types)
	made_min.resize(types)
	made_percent.resize(types * ARMOUR_CLASSES)
	for type: int in types:
		var index: int = weapons[type]
		if index < 0 or index >= ranges.size():
			continue
		made_range[type] = ranges[index]
		if index < min_ranges.size():
			made_min[type] = min_ranges[index]
		# `_entry` written out: this loop runs once a type of the match.
		var from: int = index * ARMOUR_CLASSES
		var to: int = type * ARMOUR_CLASSES
		for klass: int in mini(ARMOUR_CLASSES, percents.size() - from):
			made_percent[to + klass] = percents[from + klass]
	weapon_range = made_range
	weapon_min_range = made_min
	vs_armour = made_percent
