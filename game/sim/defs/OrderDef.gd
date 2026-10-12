class_name OrderDef
extends Resource
## An order a scenario gives at match start or later (ADR 0007 section 9). ScenarioOrders turns
## it into an ordinary Command for every unit of `player` that can move.

## The tick the order is given on.
@export var tick: int = 0
@export var player: int = 0
## A Command.Type.
@export var type: int = Command.Type.ATTACK_MOVE
## The order's target is the centre of this tile.
@export var target_tile: Vector2i = Vector2i.ZERO
