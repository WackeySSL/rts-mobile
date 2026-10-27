class_name WorldSort
extends Node2D
## The sorted world (ADR 0023 section 2, plan P114): one node at z 10 with `y_sort_enabled`, whose
## children the engine sorts by their y every frame, so a unit standing south of a thing is drawn
## after it. A unit rig stands at its projected ground point (`UnitLayer`); a building stands at
## its footprint centre's (`BuildingLayer`, P115), which sorts a unit east or south of an n x n
## footprint in front of it and one north or west behind it. Everything in it is a region of the one
## per-match atlas in white, so the whole list is one draw call however types, owners and depths
## interleave.
## The node also owns the atlas of the match: `bake` rasterises the frames of every type the
## scenario registers, each player in its faction's art and its own triad (`IsoPlayerArt`,
## `IsoAtlas`), and `sync` does it again for a match whose art or players differ from what the
## atlas holds, so a restart of the same scenario costs nothing. A sprite is dressed once (`dress`)
## and shows another frame by a region (`show_frame`): a sheet's px are 2x art, so a region draws
## at 0.5 / bake_scale. The players of the atlas are the owners 1..N in order; `slot_of` maps an
## owner to its place, one past the ends to the nearest. A scenario that lists no factions gives
## each player the faction of the first of its spawns whose type has a sheet (the Derrick League
## when none has).

const Z_SORT: int = 10  ## Unit rigs and buildings.
const Z_SHADOW: int = 2  ## A rig's Shadow, under the rings (3) and the fog (4).
const Z_RING: int = 3
const ART_SCALE: float = 0.5  ## World px per px of the 2x art, before the bake scale.
const FACTION_FILE: String = "res://data/factions/%s.tres"
const DEFAULT_FACTION: StringName = &"fossil"
## The triads a player can wear (ADR 0023 section 5): player 1 the first, player 2 the second.
const TRIADS: Array[Array] = [
	["#FF9446", "#E8681F", "#B04B12"],
	["#62D6EE", "#1FA6C8", "#137C99"],
	["#F26A5E", "#CF3A2E", "#922219"],
	["#7AA2F7", "#3F6FE0", "#27479E"],
	["#FFDA6B", "#E6B52E", "#A47D13"],
	["#F083CF", "#C9439F", "#8C2A6E"],
	["#FFFFFF", "#DCE2E6", "#A3ACB3"],
	["#6E737A", "#44494F", "#26292D"],
]

@export var runner: MatchRunner
## The scale asked of the atlas; the bake lowers it until one page holds the frames.
@export var bake_scale: float = 1.0

var atlas: IsoAtlas = IsoAtlas.new()  ## Empty until the first `bake`.
var _sheets: Dictionary[StringName, IsoSheetDef] = {}  ## The baked art ids.
var _arts: Array[IsoPlayerArt] = []  ## Owner n is entry n - 1.
var _key: String = ""  ## The art and players the atlas holds.
var _serial: int = -1  ## match_serial last synced.


func _init() -> void:
	y_sort_enabled = true
	z_index = Z_SORT
	z_as_relative = false


## Whether type `type` of `snap` has a footprint: a building, which no unit rig stands for.
static func is_building(snap: MatchSnapshot, type: int) -> bool:
	return type >= 0 and type < snap.type_foot_w.size() and snap.type_foot_w[type] > 0


## Bakes the atlas for the runner's match when its `match_serial` is new and its scenario's art or
## players are not what the atlas already holds. A layer calls it before it reads the atlas.
func sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap != null and snap.match_serial != _serial:
		_serial = snap.match_serial
		bake(runner.scenario)


## The atlas of `scenario`: every sheet of a type it registers, for each player in its faction's
## art and the player's triad. Nothing is baked again when that is what the atlas already holds.
func bake(scenario: ScenarioDef) -> IsoAtlas:
	var ids: Dictionary[StringName, bool] = _art_ids(scenario)
	var sheets: Array[IsoSheetDef] = []
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		if ids.has(sheet.art_id):
			sheets.append(sheet)
	var arts: Array[IsoPlayerArt] = _player_arts(scenario, sheets)
	var key: String = "%s|%s" % [ids.keys(), arts.map(_describe)]
	if key != _key:
		_key = key
		_arts = arts
		_sheets.clear()
		for sheet: IsoSheetDef in sheets:
			_sheets[sheet.art_id] = sheet
		atlas = IsoAtlas.build(sheets, arts, bake_scale)
	return atlas


## The sheet of art id `art_id` in the atlas, null for a type without one.
func sheet(art_id: StringName) -> IsoSheetDef:
	return _sheets.get(art_id)


## The atlas player of `owner_id`: owners 1..N in order, the nearest for one past the ends.
func slot_of(owner_id: int) -> int:
	return clampi(owner_id - 1, 0, maxi(_arts.size() - 1, 0))


## The mid colour of `owner_id`'s triad, for what stands in for art that is not in the atlas.
func mid_colour(owner_id: int) -> Color:
	var art: IsoPlayerArt = _arts[slot_of(owner_id)] if not _arts.is_empty() else null
	return Color(art.triad[1]) if art != null else Color.WHITE


## Makes `sprite` the sprite of `part` of `sheet` on the atlas, white, whose origin is the part's
## `IsoSheetDef.origin`: a unit's ground point, a building's footprint centre (for its body and
## its shadow), a turret's or head's pivot. Frames come from `show_frame`.
func dress(sprite: Sprite2D, sheet_def: IsoSheetDef, part: StringName) -> void:
	sprite.texture = atlas.texture()
	sprite.region_enabled = true
	sprite.centered = false
	sprite.modulate = Color.WHITE
	if not atlas.is_empty():
		sprite.scale = Vector2.ONE * (ART_SCALE / atlas.bake_scale())
		sprite.offset = -Vector2(sheet_def.origin(part)) * atlas.bake_scale()


## Shows frame `dir` (`d<NN>`, -1 for a building's body) of `part` for `owner_id`. A frame the
## owner's faction does not have hides the sprite.
func show_frame(
	sprite: Sprite2D, sheet_def: IsoSheetDef, part: StringName, dir: int, owner_id: int
) -> void:
	var region: Rect2i = atlas.region(sheet_def.art_id, part, dir, slot_of(owner_id))
	sprite.visible = region.has_area()
	sprite.region_rect = Rect2(region)


## Every art id the scenario registers: its spawns, its roster and the rosters of its factions.
static func _art_ids(scenario: ScenarioDef) -> Dictionary[StringName, bool]:
	var ids: Dictionary[StringName, bool] = {}
	if scenario == null:
		return ids
	var units: Array[UnitDef] = scenario.roster.duplicate()
	for spawn: SpawnDef in scenario.spawns:
		units.append(spawn.unit)
	for faction: FactionDef in scenario.factions:
		if faction != null:
			units.append_array(faction.roster)
	for unit: UnitDef in units:
		if unit != null:
			ids[unit.type_id] = true
	return ids


## The art of players 1..N, N the larger of the scenario's player count, its factions and the
## highest spawn owner.
static func _player_arts(scenario: ScenarioDef, sheets: Array[IsoSheetDef]) -> Array[IsoPlayerArt]:
	var arts: Array[IsoPlayerArt] = []
	if scenario == null:
		return arts
	var count: int = maxi(scenario.player_count, scenario.factions.size() - 1)
	for spawn: SpawnDef in scenario.spawns:
		count = maxi(count, spawn.owner)
	for player: int in range(1, count + 1):
		var faction: FactionDef = _faction_of(scenario, sheets, player)
		var triad: PackedStringArray = PackedStringArray(TRIADS[(player - 1) % TRIADS.size()])
		arts.append(IsoPlayerArt.make(faction.id, faction.key_triad, triad))
	return arts


static func _faction_of(
	scenario: ScenarioDef, sheets: Array[IsoSheetDef], player: int
) -> FactionDef:
	if player < scenario.factions.size() and scenario.factions[player] != null:
		return scenario.factions[player]
	for spawn: SpawnDef in scenario.spawns:
		for sheet_def: IsoSheetDef in sheets:
			if (
				spawn.owner == player
				and spawn.unit != null
				and spawn.unit.type_id == sheet_def.art_id
			):
				return load(FACTION_FILE % sheet_def.faction) as FactionDef
	return load(FACTION_FILE % DEFAULT_FACTION) as FactionDef


static func _describe(art: IsoPlayerArt) -> String:
	return "%s%s" % [art.faction, art.triad]
