extends RefCounted
## What differs between two `TypeTables` (plan row P198c), by field name: empty when they hold the
## same tables. The tests of the shared holder and the AI perf run use it to compare the holder a
## match kept with a fresh `TypeTables.of(world)`. Not a test suite.

## Every table of `TypeTables`, as the holder names it.
const FIELDS: Array[String] = [
	"cost",
	"tab",
	"requires",
	"produces",
	"foot_w",
	"foot_h",
	"speed",
	"weapon",
	"harvest",
	"power",
	"build_ticks",
	"max_hp",
	"armour",
	"weapon_range",
	"weapon_min_range",
	"sight",
	"faction",
	"strike_kind",
	"strike_radius",
	"charge_ticks",
	"vs_armour",
	"dock_x",
	"dock_y",
	"ids",
]


## The names of the fields in which `held` differs from `fresh`.
static func differences(held: TypeTables, fresh: TypeTables) -> Array[String]:
	var found: Array[String] = []
	for field: String in FIELDS:
		if held.get(field) != fresh.get(field):
			found.append(field)
	return found
