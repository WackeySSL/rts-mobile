class_name AiBuildOrderDef
extends Resource
## One build order of one faction at one tier (ADR 0030 section 6, plan row P175):
## `data/ai/build_orders/<faction>_<tier>.tres`. `steps` has the dummy's meaning: type ids of
## buildings in order, and the player wants as many of a type as the list has up to the item, so a
## lost building is wanted again at its place. The economy's loop after the list (power, refineries,
## factories, defences up to the level's caps) is code and data of the level, not of this file.

## The order's name, for logs and tests.
@export var id: StringName = &""
## 0 weak, 1 standard, 2 strong (`AiDifficultyDef.build_order_tier`).
@export var tier: int = 0
@export var steps: Array[StringName] = []
