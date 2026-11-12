class_name WeaponDef
extends Resource
## One weapon (ADR 0009 section 1). Integers only. Distances are milli-tiles, speeds are
## milli-tiles per tick and times are ticks. The sim copies these into World at match start.

## Must be set and unique: World.from_scenario merges weapons with one id, and the first wins.
@export var id: StringName = &""
## Named `range` by the contract, which shadows the built-in function in this class only.
@warning_ignore("shadowed_global_identifier") @export var range: int = 0
@export var min_range: int = 0
@export var damage: int = 0
@export var cooldown_ticks: int = 1
## Milli-tiles per tick. 0 = hitscan.
@export var projectile_speed: int = 0
## Percent of `damage` dealt per armour class, in UnitDef.armour order: infantry, light, heavy,
## building. 100 = full damage.
@export var vs_armour: PackedInt32Array = PackedInt32Array([100, 100, 100, 100])
## The layers the weapon may hit (ADR 0036 section 2): GROUND 1, AIR 2, LOW_AIR 4. The default is 1,
## so every shipped weapon keeps its meaning. A data test allows 1..7.
@export_flags("Ground:1", "Air:2", "Low air:4") var targets: int = 1
