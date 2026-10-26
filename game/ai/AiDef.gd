class_name AiDef
extends Resource
## The data of one computer player (ADR 0020 section 4, plan row P83): the dummy's build order and
## the few numbers that steer it (`data/ai/`). A controller copies these into ints and arrays when
## it is made and never keeps the Resource. Types are named by their type id, so one def reads the
## same against any roster that has the types, and a def of one faction lists only that faction's.

## The def's name, for logs and tests.
@export var id: StringName = &""
## What the player builds, in order: type ids of buildings (a unit type works the same way, on its
## tab). The player wants as many of a type as the list has up to the item, so a lost building is
## wanted again at its place. An id the roster lacks is left out.
@export var build_order: Array[StringName] = []
## The type id of the player's Headquarters (the placement spiral's centre) and of its harvester.
@export var hq_type: StringName = &"headquarters"
@export var harvester_type: StringName = &"harvester"
## The most items one production queue holds at a time, the harvesters kept per own refinery (the
## refinery's free one included), and the most spiral tiles one think asks `placement` about.
@export var queue_target: int = 2
@export var harvesters_wanted: int = 2
@export var place_tries: int = 64
## Tiles between two spiral slots: the largest footprint plus one free tile, so no building is
## walled in by the next one.
@export var place_stride_tiles: int = 4
## The defence (ADR 0020 section 4, plan row P83b). `defend_radius_tiles`: a seen enemy row within
## this many tiles of the centre of one of the player's buildings calls its idle combat units out,
## and no order of the defence sends a unit farther from its buildings than this.
## `guard_offset_tiles`: where the units wait when no enemy is within the radius, in tiles from the
## centre of the Headquarters; (2, 2) puts the point on the free tile between a 3 x 3 Headquarters
## and the first slot of the spiral (south-east of it, y grows downwards). A controller cuts each
## axis to half the radius, so the point is always within the radius.
@export var defend_radius_tiles: int = 12
@export var guard_offset_tiles: Vector2i = Vector2i(2, 2)
## Ticks between two thinks, and the tick of the period (tick % think_period) at which the first
## player of the ADR's numbering (player 2) thinks; each later player thinks one tick after.
@export var think_period: int = 15
@export var think_tick: int = 7
