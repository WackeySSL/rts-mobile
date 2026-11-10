class_name AiDifficultyDef
extends Resource
## One difficulty level of the opponent AI (ADR 0030 section 6, plan row P175): the only thing that
## differs between Easy, Normal and Hard. One code path reads it; the script defaults are Normal's
## file (`data/ai/difficulty/normal.tres`, a data test pins them equal). A controller copies these
## into ints when it is made and keeps no Resource. Times are ticks at 15 Hz, values are credits.

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
## Press (P197): a wave worth at least this percent of the seen enemy value near it is ahead. It
## does not retreat for loss of value, and when it stands at an enemy producer the all-in comes
## early (a decisive push). 0 = never.
@export var press_percent: int = 150
## Whether a wave at the enemy's base focuses its finished producers (the buildings that decide the
## match) once nothing armed stands near it (0 or 1).
@export var siege_focus: int = 1
## Unit control: a unit under this percent of its hp steps back (0 = never), and groups focus the
## weakest seen enemy in reach (0 or 1).
@export var unit_retreat_hp_percent: int = 0
@export var focus_fire: int = 0
## How far the unit mix shifts toward counters of what was seen, in percent.
@export var counter_percent: int = 30
## Whether the level builds and fires its side's superweapon (0 or 1).
@export var uses_strike: int = 1
## The most Commands one think sends: Easy's slow hands.
@export var commands_per_think_max: int = 8
## Income of the player in percent. 100 at every level (ADR 0030 section 8, answer 1 C).
@export var income_percent: int = 100
