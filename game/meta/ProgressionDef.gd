class_name ProgressionDef
extends Resource
## Every number of the commander rank and XP (ADR 0045 sections 2-4). The instance is
## `res://data/meta/progression.tres`, where all tuning happens; the defaults here are the ones
## that file holds. Meta only: never loaded by `game/sim`, never in a hash. Integers only.
## Tuning goal: a player who wins about half on Normal reaches rank 4 in about five matches.

## XP of a finished match by outcome (`MatchSummary.OUTCOME_*`); a surrender pays the loss row.
@export var outcome_xp: Dictionary[StringName, int] = {&"win": 100, &"loss": 40, &"draw": 60}
## Percent of `outcome_xp` by opponent level id (the AI difficulty ids).
@export var level_percent: Dictionary[StringName, int] = {&"easy": 70, &"normal": 100, &"hard": 140}
## Per full minute played, added on top, up to `minute_cap`.
@export var xp_per_minute: int = 4
@export var minute_cap: int = 40
## One-time XP of each tutorial lesson.
@export var lesson_xp: int = 40
## How many of the latest awards stay open to `apply_bonus`.
@export var awards_kept: int = 8
## The smallest multiplier `apply_bonus` accepts (1 would grant nothing).
@export var min_bonus_multiplier: int = 2
## XP needed for rank 1, 2, 3, ...: starts at 0 and rises (a data test checks it).
@export var rank_xp: PackedInt32Array = PackedInt32Array([0, 100, 250, 500, 900, 1400, 2000])
## One original title per rank, same length as `rank_xp`.
@export var rank_titles: PackedStringArray = PackedStringArray(
	["Recruit", "Scout", "Lancer", "Warden", "Marshal", "Strategist", "Commander"]
)
## Locks: {rank, kind (&"map" or &"level"), id}. A kind and id with no row is open from the start.
@export var unlocks: Array[Dictionary] = [
	{&"rank": 2, &"kind": &"map", &"id": &"map_2"},
	{&"rank": 3, &"kind": &"level", &"id": &"hard"},
	{&"rank": 4, &"kind": &"map", &"id": &"map_3"},
]
