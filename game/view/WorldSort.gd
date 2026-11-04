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
## at 0.5 / texels, per axis (`texels`). A part with several frames per direction (ADR 0027
## section 4) takes the frame number as the last argument; a layer that changes it at a rate
## keeps `base_of` from the time it dresses or turns the sprite and calls `show_base`, a table
## read with no string; `frame_count_at` is the length to wrap the frame number by. The players of
## the atlas are the owners 1..N in order; `slot_of` maps an owner to its place, one past the ends
## to the nearest. A scenario that lists no factions gives each player the faction of the first of
## its spawns whose type has a sheet (the Derrick League when none has).
## The neutral damage sheet (ADR 0028 section 4, `IsoAtlas.NEUTRAL_SHEET`) is baked after the type
## sheets for every scenario once its file exists: `neutral_sheet` is it (null before), and
## `neutral_base` the base of one of its parts for an owner, resolved once per bake.

const Z_SORT: int = 10  ## Unit rigs and buildings.
const Z_SHADOW: int = 2  ## A rig's Shadow, under the rings (3) and the fog (4).
const Z_RING: int = 3
const ART_SCALE: float = 0.5  ## World px per px of the 2x art, before the bake scale.
const FACTION_FILE: String = "res://data/factions/%s.tres"
const DEFAULT_FACTION: StringName = &"fossil"
## The triads a player can wear (ADR 0023 section 5): player 1 the first, player 2 the second,
## unless the scenario says otherwise (`ScenarioDef.team_triads`, `triad_index`).
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
## Where the neutral sheet is read from; a test points it at a crafted sheet.
var neutral_path: String = IsoAtlas.NEUTRAL_SHEET
var _sheets: Dictionary[StringName, IsoSheetDef] = {}  ## The baked art ids.
var _arts: Array[IsoPlayerArt] = []  ## Owner n is entry n - 1.
var _muzzles: PackedFloat32Array = PackedFloat32Array()  ## Per weapon index of the match, px.
var _neutral: IsoSheetDef  ## The neutral sheet of this bake, null when there is none.
## Part -> the base of that part of the neutral sheet for each player slot (one view per part).
var _neutral_bases: Dictionary[StringName, PackedInt32Array] = {}
var _key: String = ""  ## The art and players the atlas holds.
var _serial: int = -1  ## match_serial last synced.


func _init() -> void:
	y_sort_enabled = true
	z_index = Z_SORT
	z_as_relative = false


## Whether type `type` of `snap` has a footprint: a building, which no unit rig stands for.
static func is_building(snap: MatchSnapshot, type: int) -> bool:
	return type >= 0 and type < snap.type_foot_w.size() and snap.type_foot_w[type] > 0


## The index into TRIADS of the triad `player` wears: its entry of the scenario's `team_triads`,
## else its own place (player 1 the first, wrapping after eight). The neutral player wears player
## 1's, as `slot_of` gives it art. The minimap reads the same rule.
static func triad_index(triads: PackedInt32Array, player: int) -> int:
	var at: int = maxi(player, 1)
	return posmod(triads[at] if at < triads.size() else at - 1, TRIADS.size())


## Bakes the atlas for the runner's match when its `match_serial` is new and its scenario's art or
## players are not what the atlas already holds. A layer calls it before it reads the atlas.
func sync() -> void:
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap != null and snap.match_serial != _serial:
		_serial = snap.match_serial
		bake(runner.scenario)
		_muzzles = _muzzle_table(snap)


## The atlas of `scenario`: every sheet of a type it registers, for each player in its faction's
## art and the player's triad. Nothing is baked again when that is what the atlas already holds.
func bake(scenario: ScenarioDef) -> IsoAtlas:
	var ids: Dictionary[StringName, bool] = _art_ids(scenario)
	var sheets: Array[IsoSheetDef] = []
	for sheet: IsoSheetDef in IsoAtlas.load_sheets():
		if ids.has(sheet.art_id):
			sheets.append(sheet)
	var arts: Array[IsoPlayerArt] = _player_arts(scenario, sheets)
	# After the art-id filter and after `_player_arts`, whose faction lookup reads the type sheets.
	var neutral: IsoSheetDef = IsoAtlas.load_neutral_sheet(neutral_path)
	var key: String = "%s|%s|%s" % [ids.keys(), arts.map(_describe), _neutral_key(neutral)]
	if key != _key:
		_key = key
		_arts = arts
		_sheets.clear()
		for sheet: IsoSheetDef in sheets:
			_sheets[sheet.art_id] = sheet
		var baked: Array[IsoSheetDef] = sheets.duplicate()
		if neutral != null:
			baked.append(neutral)
			if neutral_clash(ids, neutral):
				push_error("WorldSort: a type has the neutral sheet's art id %s" % neutral.art_id)
		atlas = IsoAtlas.build(baked, arts, bake_scale)
		_resolve_neutral(neutral)
		print(atlas.report())  # `atlas_bake_ms` for the log of CI and the web preview's console.
	return atlas


## The atlas base of `part` of the neutral sheet for `owner_id` (every overlay has one view; its
## frames come from `show_base`), resolved once per bake: a table read, no string. -1 without it.
func neutral_base(part: StringName, owner_id: int) -> int:
	if not _neutral_bases.has(part):
		return -1
	return _neutral_bases[part][slot_of(owner_id)]


## The neutral sheet of this bake, null while its file does not exist (P160).
func neutral_sheet() -> IsoSheetDef:
	return _neutral


## The sheet of art id `art_id` in the atlas, null for a type without one.
func sheet(art_id: StringName) -> IsoSheetDef:
	return _sheets.get(art_id)


## The muzzle height of weapon index `weapon` of the match's snapshot, world px at zoom 1: the
## sheet's `muzzle_lift_px` of the first type that carries the weapon and has a sheet. 0 when no
## sheet says (`SpriteLift.muzzle_lift_px` then reads its table). A weapon that types of both
## factions share has the first one's height. Read from the last `sync`, which never bakes here.
func muzzle_px(weapon: int) -> float:
	return _muzzles[weapon] if weapon >= 0 and weapon < _muzzles.size() else 0.0


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
## A damage part (the `dmg1` and `dmg2` patches, the whole `ruin` picture) is sized by
## `IsoAtlas.part_scale`: `dress` handles it by name.
func dress(sprite: Sprite2D, sheet_def: IsoSheetDef, part: StringName) -> void:
	sprite.texture = atlas.texture()
	sprite.region_enabled = true
	sprite.centered = false
	sprite.modulate = Color.WHITE
	if not atlas.is_empty():
		# The engine rounds a raster per axis and stretches the art to it, so a sprite is sized per
		# axis from the raster; a damage part is baked at IsoAtlas.part_factor of the bake scale.
		var per_px: Vector2 = texels(sheet_def, part)
		sprite.scale = Vector2(ART_SCALE / per_px.x, ART_SCALE / per_px.y)
		sprite.offset = -Vector2(sheet_def.origin(part)) * per_px


## The texels per px of the 2x art that `part` of `sheet_def` has on the atlas, per axis: what
## `dress` sizes the sprite and its offset by. The pose offsets and the ghost's Anim child use it
## too, so that all writers of one sprite agree below scale 1.0.
func texels(sheet_def: IsoSheetDef, part: StringName) -> Vector2:
	return IsoAtlas.texels_per_px(sheet_def.frame_size(part), atlas.part_scale(part))


## Shows frame number `frame` (0 for a part with one frame) of direction `dir` (`d<NN>`, -1 for a
## building's body or `anim`) of `part` for `owner_id`. A frame the owner's faction does not have,
## and a `frame` the part does not have, hide the sprite. It builds one key (`IsoAtlas.base`): call
## it when a sprite is dressed or turns, and change the frames of a pose with `base_of` once and
## `show_base` after it. Returns the base it resolved, so a dress or a turn that keeps it builds
## one key and not two.
func show_frame(
	sprite: Sprite2D,
	sheet_def: IsoSheetDef,
	part: StringName,
	dir: int,
	owner_id: int,
	frame: int = 0
) -> int:
	var base_index: int = base_of(sheet_def, part, dir, owner_id)
	show_base(sprite, base_index, frame)
	return base_index


## The atlas base index (`IsoAtlas.base`) of direction `dir` of `part` for `owner_id`: what a layer
## keeps for a sprite from the time it is dressed or turns, and hands to `show_base`. -1 when the
## owner's faction lacks the frames. A base belongs to the atlas it came from: `sync` makes a new
## one for a new match's art, so ask again after a `sync`, when the sprites are dressed.
func base_of(sheet_def: IsoSheetDef, part: StringName, dir: int, owner_id: int) -> int:
	return atlas.base(sheet_def.art_id, part, dir, slot_of(owner_id))


## How many frames the group at `base_index` (`base_of`) has: what a layer wraps its frame number
## by, so a pose with a new frame count needs no change in the layer. 0 for no base.
func frame_count_at(base_index: int) -> int:
	return atlas.frame_count_at(base_index)


## Shows frame `frame` of the group at `base_index` (`base_of`) on `sprite`: a table read, so a
## frame change builds no string. The sprite hides when there is no such frame.
func show_base(sprite: Sprite2D, base_index: int, frame: int) -> void:
	var region: Rect2i = atlas.frame_region(base_index, frame)
	sprite.visible = region.has_area()
	sprite.region_rect = Rect2(region)


## Resolves every base of the neutral sheet for every player slot (the only place it builds keys),
## and reports a frame that cannot work: one with a key colour (it would not be shared).
func _resolve_neutral(neutral: IsoSheetDef) -> void:
	_neutral = neutral
	_neutral_bases.clear()
	if neutral == null or _arts.is_empty():
		return
	for part_name: String in neutral.parts:
		var part: StringName = StringName(part_name)
		var bases: PackedInt32Array = PackedInt32Array()
		for slot: int in _arts.size():
			bases.append(atlas.base(neutral.art_id, part, neutral.directions(part)[0], slot))
		_neutral_bases[part] = bases
		for frame: int in maxi(neutral.frame_count(part), 1):
			var text: String = IsoAtlas.read_text(
				neutral.path(part, neutral.directions(part)[0], frame)
			)
			if has_key_colour(text, _arts):
				push_error("WorldSort: a key colour in a neutral frame of %s" % part)


## Whether a registered type has the art id of `neutral`, which the sheet could not tell apart.
static func neutral_clash(ids: Dictionary[StringName, bool], neutral: IsoSheetDef) -> bool:
	return ids.has(neutral.art_id)


## Whether a player's recolour changes `text`: it holds a key colour, so it would not be shared.
static func has_key_colour(text: String, arts: Array[IsoPlayerArt]) -> bool:
	for art: IsoPlayerArt in arts:
		if art.recolour(text) != text:
			return true
	return false


static func _neutral_key(neutral: IsoSheetDef) -> String:
	return neutral.resource_path if neutral != null else ""


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
		var triad: PackedStringArray = PackedStringArray(
			TRIADS[triad_index(scenario.team_triads, player)]
		)
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


## The muzzle height of each weapon index of `snap`, from the sheets of the types that carry it.
func _muzzle_table(snap: MatchSnapshot) -> PackedFloat32Array:
	var table: PackedFloat32Array = PackedFloat32Array()
	table.resize(snap.weapon_ids.size())
	for type: int in mini(snap.type_ids.size(), snap.type_weapon.size()):
		var weapon: int = snap.type_weapon[type]
		var found: IsoSheetDef = _sheets.get(snap.type_ids[type])
		if found != null and weapon >= 0 and weapon < table.size() and table[weapon] == 0.0:
			table[weapon] = float(found.muzzle_lift_px)
	return table


static func _describe(art: IsoPlayerArt) -> String:
	return "%s%s" % [art.faction, art.triad]
