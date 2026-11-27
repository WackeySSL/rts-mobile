class_name TrophyDef
extends Resource
## One trophy of the Rank screen (ADR 0054 section 2). Pure data: `TrophyRules` (P673c) reads it,
## the Rank screen shows it. Every count and tick limit lives in `data/meta/trophies.tres`.
## `id` is a save key, stable forever; only `name` and `hint` may change. Meta only, never sim.

## What a trophy asks for. Only the fields of its kind are read.
enum Kind {
	LESSONS,  ## Every id in `lesson_ids` is in `tutorial.done`.
	COUNT,  ## The career counter `counter` (with `key` for wins_faction) is at least `count`.
	WIN_GRID,  ## Every pair of `map_ids` x `levels` has a win; an empty list means any.
	MATCH,  ## This match is a win and meets every set filter below.
}

@export var id: StringName = &""
## English player text, shown through `tr()`.
@export var name: String = ""
@export var hint: String = ""
## The icon stem under `res://assets/art/svg/icons/`.
@export var glyph: StringName = &""
## Small pips under the glyph, 0 to 3 (the level).
@export var pips: int = 0
@export var kind: Kind = Kind.COUNT
@export var lesson_ids: Array[StringName] = []
## `finished`, `wins` or `wins_faction`.
@export var counter: StringName = &""
## The faction id of a `wins_faction` counter.
@export var key: StringName = &""
@export var count: int = 0
@export var map_ids: Array[StringName] = []
## Level ids (the AI difficulty ids); empty means any.
@export var levels: Array[StringName] = []
## 0 = no limit.
@export var max_ticks: int = 0
## True = a Headquarters still stands at the end.
@export var hq_standing: bool = false
## -1 = any.
@export var max_buildings_lost: int = -1
