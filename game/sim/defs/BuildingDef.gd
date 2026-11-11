class_name BuildingDef
extends UnitDef
## A building type (ADR 0017 section 1, ADR 0018 section 9): a UnitDef with a footprint. Data gives
## it speed 0, radius 0 and armour Building (a data test pins all three). The sim copies these
## into World at match start, as for UnitDef. Offsets and the footprint are in tiles.

## Width and height in tiles, at most 3 x 3. 1 x 1 by default, so a definition built in a test is
## a valid footprint.
@export var footprint: Vector2i = Vector2i(1, 1)
## Power made (above 0) or used (below 0).
@export var power: int = 0
## The tab whose queue this building lets the player use: -1 none, else a World.Tab.
@export_enum("None:-1", "Structures:0", "Infantry:1", "Vehicles:2", "Flight:3", "Research:4")
var produces: int = -1
## The unit that comes with the building when the player places it (the refinery's harvester).
## Null = none.
@export var free_unit: UnitDef
## The cell a harvester unloads at, and the cell a produced unit appears at: tile offsets from the
## footprint's origin (its top-left tile), authored for the south side of a square footprint on its
## ring. The sim turns them to the side that faces the map's centre (Buildings.facing, ADR 0033).
## A dock of (0, 0) means none and is never turned.
@export var dock: Vector2i = Vector2i.ZERO
@export var exit: Vector2i = Vector2i.ZERO

## The superweapon of a strike building (ADR 0023 section 10), all 0 and no weapon for every other
## building: the kind (0 none, 1 rupture, 2 blackout), the ticks from placement (and from each
## firing; for a Reveal building the one charge from completion) until it may fire, the radius
## around the target point in milli-tiles, the rupture's warning in ticks, the blackout's length
## in ticks, and the rupture's weapon (a WeaponDef, so its damage goes through the armour percents).
@export_enum("None:0", "Rupture:1", "Blackout:2", "Reveal:3") var strike_kind: int = 0
@export var charge_ticks: int = 0
@export var strike_radius: int = 0
@export var strike_delay: int = 0
@export var strike_ticks: int = 0
@export var strike_weapon: WeaponDef

## The landing pads of an airfield (ADR 0036 section 2): their number, and one tile offset from the
## footprint origin each, inside the footprint. 0 pads = not an airfield.
@export var pads: int = 0
@export var pad_offsets: Array[Vector2i] = []


## The data-test rules of this building, one message per fault; empty = valid. `max_flight_spacing`
## is the largest `formation_spacing` of any FLIGHT type: pads must lie at least that far apart
## (milli-tiles), or waiting aircraft drift out of repair reach.
func validate_building(max_flight_spacing: int) -> PackedStringArray:
	var out: PackedStringArray = validate()
	var tag: String = String(type_id)
	if pads < 0 or pad_offsets.size() != pads:
		out.append("%s: pads %d does not match %d pad_offsets" % [tag, pads, pad_offsets.size()])
	if pads == 0 and repair_classes != 0 and repair_slots < 1:
		out.append("%s: repair_slots 0 is only for a type with pads" % tag)
	for i: int in pad_offsets.size():
		var a: Vector2i = pad_offsets[i]
		if a.x < 0 or a.y < 0 or a.x >= footprint.x or a.y >= footprint.y:
			out.append("%s: pad %d lies outside the footprint" % [tag, i])
		for j: int in range(i + 1, pad_offsets.size()):
			var d: Vector2i = pad_offsets[j] - a
			if (d.x * d.x + d.y * d.y) * 1000000 < max_flight_spacing * max_flight_spacing:
				out.append("%s: pads %d and %d closer than %d" % [tag, i, j, max_flight_spacing])
	if strike_kind < 0 or strike_kind > 3:
		out.append("%s: strike_kind %d outside 0..3" % [tag, strike_kind])
	if (
		strike_kind == 3
		and (strike_ticks != 0 or strike_radius != 0 or strike_delay != 0 or strike_weapon != null)
	):
		out.append("%s: a Reveal building has no strike_ticks, radius, delay or weapon" % tag)
	return out
