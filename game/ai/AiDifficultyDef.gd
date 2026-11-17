class_name AiDifficultyDef
extends Resource
## One difficulty level of the opponent AI (ADR 0030 section 6, plan row P175): the only thing that
## differs between Easy, Normal and Hard. One code path reads it; the script defaults are Normal's
## file (`data/ai/difficulty/normal.tres`, a data test pins them equal) but for the fields that are
## off by default (`mend_below_percent`, `mend_floor`: the `perf_ai` frozen files name neither;
## the `perf_ai_4b` copies set each level's shipped pair, plan P304). A
## controller copies these into ints when it is made and keeps no Resource. Times are ticks at
## 15 Hz, values are credits.

## The level's name, for logs and tests.
@export var id: StringName = &"normal"
## Which build order of the faction's `OpponentDef` the level plays: 0 weak, 1 standard, 2 strong.
@export var build_order_tier: int = 1
## The age a sighting or a threat must have in the memory before it is acted on.
@export var reaction_ticks: int = 30
## Harvesters kept per own refinery (the refinery's free one included).
@export var harvesters_per_refinery: int = 2
## The caps of the loop that follows the build order.
@export var refineries_max: int = 2
@export var factories_max: int = 1
@export var defences_max: int = 2
## The scout: the first tick it may go and the ticks between two trips; an interval of 0 sends none.
@export var scout_first_tick: int = 1800
@export var scout_interval_ticks: int = 2700
## Waves: the earliest first launch, the army value (credits, scaled by hp) that launches it, how
## much more each later wave asks in percent, and the start jitter drawn from the AI's stream.
@export var wave_first_tick: int = 4050
@export var wave_first_strength: int = 4000
@export var wave_growth_percent: int = 25
@export var wave_jitter_ticks: int = 300
## From this tick every combat unit joins the waves (it ends stalemates).
@export var all_in_tick: int = 10800
## A group pulls back below this percent of its launch value, or when the enemy value near it passes
## this percent of its own. 0 = never.
@export var retreat_percent: int = 40
@export var retreat_ratio_percent: int = 200
## Unit control: a unit under this percent of its hp steps back (0 = never), and groups focus the
## weakest seen enemy in reach (0 or 1).
@export var unit_retreat_hp_percent: int = 0
@export var focus_fire: int = 0
## How far the unit mix shifts toward counters of what was seen, in percent.
@export var counter_percent: int = 30
## Whether the level builds and fires its side's superweapon (0 or 1).
@export var uses_strike: int = 1
## Building repair (ADR 0037 section 4, plan row P274): `AiEconomy` switches a building's `MEND` on
## when its hp is under `mend_below_percent` percent of the maximum (0 = never, the script default,
## so the `perf_ai` frozen files play as before; 100 = any damage) while the credits left after the
## think's spending and the economy's hold are above `mend_floor` (credits; a building that costs
## nothing goes on whatever they are). It never switches off. Easy mends nothing.
@export var mend_below_percent: int = 0
@export var mend_floor: int = 0
## Ground support (ADR 0037 sections 5 and 6, plan row P283; off by default like the mend pair, so
## the `perf_ai` frozen files play as before). `repair_retreat_percent`: `AiRepair` sends a damaged
## own ground vehicle that is not in a wave's fight to the repair building with `REPAIR` while its
## hp is under this percent of the maximum (0 = never), and back to the staging point when repaired.
## `medic_per_squads`: `AiProduction` keeps one medic squad per this many own armed infantry squads
## (0 = none), and `AiRepair` sends the medics with each wave. Easy uses neither.
@export var repair_retreat_percent: int = 0
@export var medic_per_squads: int = 0
## 1: the members of a retreating wave are sent to repair too (Hard; ADR 0037 section 5).
@export var repair_wave_retreat: int = 0
## Air and tech (ADR 0036 section 14, plan row P250; off by default like the fields above, so the
## `perf_ai` frozen files play as before). `aa_per_seen_aircraft`: `AiEconomy` wants one anti-air
## building per this many enemy aircraft seen at once (the most it has seen), at most `aa_max` (0 =
## none). `research_floor`: `AiProduction` researches the next upgrade, in data order, that changes
## a unit it owns, one at a time, while its credits left stay above this (0 = no research). Easy has
## no engineering centre, so it never researches.
@export var aa_per_seen_aircraft: int = 0
@export var aa_max: int = 0
@export var research_floor: int = 0
## The tech gate (plan row P250b): an order step that is a tech building (the airfield, the
## engineering centre or the space centre, found by their role) does not start while the own army's
## value (`AiMemory.army_value`) is under this; the steps after it wait too, the loop and the
## anti-air wish go on. 0 = no gate.
@export var tech_army_value_min: int = 0
## Hold position (ADR 0037 section 15, plan row P300; off by default like the fields above, so the
## frozen files play as before): 1 = `AiHold` sets the types of `OpponentDef.hold_types` to hold
## while they are in a wave and releases them when the wave ends. Easy uses none.
@export var hold_in_waves: int = 0
## Close-out (plan row P250c; off by default like the fields above, so the frozen files play as
## before): while no enemy producer is seen or remembered and the mirror estimate has been explored,
## `AiSweep` sends the wave to the nearest unexplored sector of the enemy half; a sector it has not
## explored this many ticks after the pick is given up. 0 = off. Easy does not search.
@export var sweep_hold_ticks: int = 0
## The most Commands one think sends: Easy's slow hands.
@export var commands_per_think_max: int = 8
## Income of the player in percent. 100 at every level (ADR 0030 section 8, answer 1 C).
@export var income_percent: int = 100
