class_name UpgradeDef
extends Resource
## One researchable upgrade (ADR 0036 section 2): one level, researched or not. The engineering
## centre (`requires`) researches it as a queue-only RESEARCH item. Plain data; the sim copies what
## it needs into World at match start. Integers only; times are ticks at 15 Hz.

## The most a percent modifier may be (a data test), so a damage product stays in int range.
const MAX_PERCENT: int = 400
const DAMAGE_DEALT: int = 0
const DAMAGE_TAKEN: int = 1
const AMMO: int = 2

@export var id: StringName = &""
@export var display_name: String = ""
## A FactionDef `id`.
@export var faction: StringName = &""
@export var cost: int = 0
@export var research_ticks: int = 1
## The building whose owner may research it (the engineering centre). Null = none.
@export var requires: UnitDef
@export_enum("Damage dealt:0", "Damage taken:1", "Ammo:2") var stat: int = 0
## A percent for the damage stats (100 = no change), an amount of extra shots for AMMO.
@export var value: int = 100
## The types it changes.
@export var applies_to: Array[UnitDef] = []


## The data-test rules of this upgrade, one message per fault; empty = valid.
func validate() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var tag: String = String(id)
	if cost < 0 or research_ticks < 1:
		out.append("%s: cost >= 0 and research_ticks >= 1 are required" % tag)
	if stat < DAMAGE_DEALT or stat > AMMO:
		out.append("%s: stat %d outside 0..2" % [tag, stat])
	elif stat == AMMO and value < 1:
		out.append("%s: an ammo upgrade adds at least 1 shot" % tag)
	elif stat != AMMO and (value < 1 or value > MAX_PERCENT):
		out.append("%s: value %d outside 1..%d percent" % [tag, value, MAX_PERCENT])
	if requires == null or applies_to.is_empty():
		out.append("%s: requires and applies_to must be set" % tag)
	return out
