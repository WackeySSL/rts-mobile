class_name SpriteLift
extends RefCounted
## How far above its ground point a thing of the view stands (ADR 0023 sections 2 and 3). The
## iso sheets carry these per art id (`IsoSheetDef.bar_lift_px`, `pick_lift_px` and
## `muzzle_lift_px`, P113); until they come the numbers are here, in world px at zoom 1 and from
## the canvas Spec section 05 (a vehicle is 16 to 30 px high, an infantry figure 18). A layer lifts
## a projected point by subtracting the answer from its y, so a lift scales with the zoom like the
## sprite it stands for. Pure and static; P113 changes the bodies to sheet lookups and no caller.
##
## A bar and a death are by the unit's type id, with a default per class for a type the tables lack
## (a new roster type has a sensible bar before it has a row here). A shot is by its weapon id: a
## shot's events and a projectile slot know the weapon and not the shooter's type, and a weapon
## belongs to one kind of shooter.

## The top of the unit's frame above its ground point, by type id (the bar's bottom edge stands a
## gap above it). A squad's frame holds three figures spread over the ground, so it is taller than
## one figure: the one standing furthest back reaches higher on the screen.
const BAR_PX: Dictionary[StringName, float] = {
	&"light_tank": 24.0,
	&"heavy_tank": 30.0,
	&"artillery": 28.0,
	&"harvester": 26.0,
}
const VEHICLE_BAR_PX: float = 26.0  ## Any other type that is not infantry.
const INFANTRY_BAR_PX: float = 24.0  ## Any other infantry type.
## The height of a weapon's muzzle above the shooter's ground point, by weapon id.
const MUZZLE_PX: Dictionary[StringName, float] = {
	&"tank_cannon": 14.0,
	&"heavy_cannon": 17.0,
	&"artillery_gun": 18.0,
	&"rocket": 13.0,
	&"rifle": 11.0,
	&"turret_gun": 30.0,
}
const MUZZLE_DEFAULT_PX: float = 14.0


## The top of the frame of type `type` above its ground point: an index into the snapshot's
## `type_ids` and `type_armour`, which give the table row and the class default. A type the
## tables lack counts as a vehicle.
static func bar_lift_px(type_ids: Array[StringName], armours: PackedInt32Array, type: int) -> float:
	var known: bool = type >= 0 and type < armours.size()
	var armour: int = armours[type] if known else World.Armour.LIGHT
	var fallback: float = INFANTRY_BAR_PX if armour == World.Armour.INFANTRY else VEHICLE_BAR_PX
	if not known or type >= type_ids.size():
		return fallback
	return BAR_PX.get(type_ids[type], fallback)


## The middle of that frame above the ground point: where an explosion over the unit is centred.
static func centre_lift_px(
	type_ids: Array[StringName], armours: PackedInt32Array, type: int
) -> float:
	return 0.5 * bar_lift_px(type_ids, armours, type)


## The muzzle height of weapon `weapon`, an index into `weapon_ids` (the snapshot's table); the
## default for an index the table lacks.
static func muzzle_lift_px(weapon_ids: Array[StringName], weapon: int) -> float:
	if weapon < 0 or weapon >= weapon_ids.size():
		return MUZZLE_DEFAULT_PX
	return MUZZLE_PX.get(weapon_ids[weapon], MUZZLE_DEFAULT_PX)
