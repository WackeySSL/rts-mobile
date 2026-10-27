class_name SpriteLift
extends RefCounted
## How far above its ground point a thing of the view stands (ADR 0023 sections 2 and 3), in world
## px at zoom 1. The iso sheets carry the numbers per art id (`IsoSheetDef.bar_lift_px`,
## `pick_lift_px` and `muzzle_lift_px`, STYLE.md "Sheets"), so each function takes the sheet of the
## thing and answers the sheet's lift. Without a sheet (a type that has none, or a layer that has no
## sorted world) the answer is the default of the thing's class, from the canvas Spec section 05 (a
## vehicle is 16 to 30 px high, an infantry figure 18) and, for a shot, the row of its weapon. A
## layer lifts a projected point by subtracting the answer from its y, so a lift scales with the
## zoom like the sprite it stands for. Pure and static.

## The top of a frame with no sheet above its ground point: any type that is not infantry, then
## infantry.
const VEHICLE_BAR_PX: float = 26.0
const INFANTRY_BAR_PX: float = 24.0
## The height of a weapon's muzzle above the shooter's ground point, by weapon id: the answer for a
## weapon whose shooter has no sheet to say (a sheet's number wins over a row).
const MUZZLE_PX: Dictionary[StringName, float] = {
	&"tank_cannon": 14.0,
	&"heavy_cannon": 17.0,
	&"artillery_gun": 18.0,
	&"rocket": 13.0,
	&"rifle": 11.0,
	&"turret_gun": 30.0,
}
const MUZZLE_DEFAULT_PX: float = 14.0


## The top of the frame of a unit of armour `armour` above its ground point: where its bar's bottom
## edge stands a gap above. `sheet` is the unit's sheet, null for none. A squad's frame holds three
## figures spread over the ground, so the sheet's number is the taller one.
static func bar_lift_px(sheet: IsoSheetDef, armour: int) -> float:
	if sheet != null and sheet.bar_lift_px > 0:
		return float(sheet.bar_lift_px)
	return INFANTRY_BAR_PX if armour == World.Armour.INFANTRY else VEHICLE_BAR_PX


## The middle of that frame above the ground point (the sheet's `pick_lift_px`): where an explosion
## over the unit is centred and where a tap picks it.
static func centre_lift_px(sheet: IsoSheetDef, armour: int) -> float:
	if sheet != null and sheet.pick_lift_px > 0:
		return float(sheet.pick_lift_px)
	return 0.5 * bar_lift_px(sheet, armour)


## The muzzle height of weapon `weapon`, an index into `weapon_ids` (the snapshot's table).
## `sheet_px` is what the sorted world says for the weapon (`WorldSort.muzzle_px`, 0 for nothing).
## The table's row stands in when it says nothing, and the default for a weapon the table lacks.
static func muzzle_lift_px(
	weapon_ids: Array[StringName], weapon: int, sheet_px: float = 0.0
) -> float:
	if sheet_px > 0.0:
		return sheet_px
	if weapon < 0 or weapon >= weapon_ids.size():
		return MUZZLE_DEFAULT_PX
	return MUZZLE_PX.get(weapon_ids[weapon], MUZZLE_DEFAULT_PX)
