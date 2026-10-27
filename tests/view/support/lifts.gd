extends RefCounted
## The lifts of a type's sheet (STYLE.md "Sheets", ADR 0023 sections 2 and 3), read from the index
## and not typed in a test: the sheets are generated data and a new model changes them. World px at
## zoom 1; a lift on the screen is this times the camera's zoom. Not a test suite.


## How high a tap picks a unit of type `type_id` above its ground point (`pick_lift_px`).
static func pick(type_id: StringName) -> float:
	return float(_sheet(type_id).pick_lift_px)


## How high the top of its frame stands (`bar_lift_px`), which its bar stands over.
static func bar(type_id: StringName) -> float:
	return float(_sheet(type_id).bar_lift_px)


## How high a shot leaves it (`muzzle_lift_px`).
static func muzzle(type_id: StringName) -> float:
	return float(_sheet(type_id).muzzle_lift_px)


static func _sheet(type_id: StringName) -> IsoSheetDef:
	return (load(IsoIndex.PATH) as IsoIndex).sheet(type_id)
