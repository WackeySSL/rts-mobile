class_name PlacementInput
extends RefCounted
## What Placement.reason reads (ADR 0017 section 2), under the World's names, so the sim fills it
## from the World (`of_world`) and the view from its snapshot (ADR 0012 section 3: the view never
## reads the World), and both judge by the same code. The packed arrays are aliases of the source's
## (GDScript shares a packed array on assignment), so an input is read at once and not kept across
## a tick. Pure data: no rule lives here.

## The map: its size in tiles, the terrain index per tile, the buildable flag per terrain index and
## the move cost per class and tile (class FOOT first).
var map_cols: int = 0
var map_rows: int = 0
var terrain: PackedByteArray = PackedByteArray()
var terrain_buildable: PackedByteArray = PackedByteArray()
var move_cost: PackedByteArray = PackedByteArray()
## The fog's `explored` (one block of `fog_cells` bytes per player), its block size and its players.
var explored: PackedByteArray = PackedByteArray()
var fog_cells: int = 0
var fog_player_count: int = 0
## The rows (owner, type, position in milli-tiles) and the type tables the rules read.
var owner: PackedInt32Array = PackedInt32Array()
var type_index: PackedInt32Array = PackedInt32Array()
var pos_x: PackedInt32Array = PackedInt32Array()
var pos_y: PackedInt32Array = PackedInt32Array()
var type_speed: PackedInt32Array = PackedInt32Array()
var type_radius: PackedInt32Array = PackedInt32Array()
var type_foot_w: PackedInt32Array = PackedInt32Array()
var type_foot_h: PackedInt32Array = PackedInt32Array()
## The rule ints (RulesDef): the reach from an own building, and the cap of buildings.
var build_reach_tiles: int = 0
var building_cap: int = 0


## The input of `world` as it stands: every field is the World's own array or int.
static func of_world(world: World) -> PlacementInput:
	var input: PlacementInput = PlacementInput.new()
	input.map_cols = world.map_cols
	input.map_rows = world.map_rows
	input.terrain = world.terrain
	input.terrain_buildable = world.terrain_buildable
	input.move_cost = world.move_cost
	input.explored = world.fog.explored
	input.fog_cells = world.fog.cells
	input.fog_player_count = world.fog.player_count
	input.owner = world.owner
	input.type_index = world.type_index
	input.pos_x = world.pos_x
	input.pos_y = world.pos_y
	input.type_speed = world.type_speed
	input.type_radius = world.type_radius
	input.type_foot_w = world.type_foot_w
	input.type_foot_h = world.type_foot_h
	input.build_reach_tiles = world.build_reach_tiles
	input.building_cap = world.building_cap
	return input
