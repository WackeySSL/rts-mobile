extends RefCounted
## What differs between two `TypeTables` (plan row P198c), by field name: empty when they hold the
## same tables. The tests of the shared holder and the AI perf run use it to compare the holder a
## match kept with a fresh `TypeTables.of(world)`. The field lists come from the script's own
## variables, so a table added to `TypeTables` or to `PlayerView` is covered without an edit here.
## Not a test suite.

## The view's table names whose holder field is not the same name without `type_`: the two that are
## read through the weapon.
const WEAPON_DERIVED: Dictionary[String, String] = {
	"type_range": "weapon_range", "type_min_range": "weapon_min_range"
}


## Every variable of `TypeTables`: its tables, the dock offsets and the type ids.
static func fields() -> Array[String]:
	return _variables(TypeTables.new())


## The public `type_*` tables of a `PlayerView`, by name.
static func view_tables() -> Array[String]:
	var found: Array[String] = []
	for name: String in _variables(PlayerView.new()):
		if name.begins_with("type_"):
			found.append(name)
	return found


## The holder field that the view's table `name` is a copy of.
static func holder_field(name: String) -> String:
	return WEAPON_DERIVED.get(name, name.trim_prefix("type_"))


## The names of the fields in which `held` differs from `fresh`.
static func differences(held: TypeTables, fresh: TypeTables) -> Array[String]:
	var found: Array[String] = []
	for field: String in fields():
		if held.get(field) != fresh.get(field):
			found.append(field)
	return found


static func _variables(object: Object) -> Array[String]:
	var found: Array[String] = []
	for info: Dictionary in object.get_property_list():
		if (int(info["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			found.append(String(info["name"]))
	return found
