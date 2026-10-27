class_name OrderDef
extends Resource
## An order a scenario gives at match start or later (ADR 0007 section 9). ScenarioOrders turns
## it into an ordinary Command: the unit-group types (ATTACK_MOVE, MOVE, ATTACK, STOP) name every
## unit of `player` that can move, QUEUE names the type `unit` and SUPERWEAPON the strike building
## of type `unit`.

## The tick the order is given on.
@export var tick: int = 0
@export var player: int = 0
## A Command.Type. QUEUE and SUPERWEAPON need `unit`.
@export var type: int = Command.Type.ATTACK_MOVE
## The order's target is the centre of this tile.
@export var target_tile: Vector2i = Vector2i.ZERO
## QUEUE: the unit or building type to queue (the world knows it by `type_id`: a spawn, `roster` or
## a listed faction's roster registered it). SUPERWEAPON: the strike building type; the order fires
## the player's first building of that type, in ascending id. Null for every other type.
@export var unit: UnitDef
