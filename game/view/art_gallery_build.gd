extends "res://game/view/art_gallery_iso.gd"
## The Build page of the art gallery (plan rows P103 and P104, ADR 0023 sections 2 and 5): the Iso
## page's list, buttons and title, over the building models only. One building at a time stands on
## the iso ground with a tank of its faction in front of it and one behind it, at the camera zoom
## levels 1, 0.75 and 1.5 in the two triads Signal and Arktisk, the scene on grass left and on sand
## right. It draws what a match draws: the frames come from the one atlas `IsoAtlas` bakes for the
## two players (the faction's key triad replaced by the player's), a sprite is a region of it at
## `0.5 / bake_scale` times the zoom, the rigs are children of one y-sorted node (a thing south of
## another is drawn after it, as `WorldSort` does) and the cast shadows lie under every body. A
## building's rig stands at its footprint's centre, a unit's at its ground point and facing its
## faction's default view; a defence's head faces the tank in front of it. The faction's emblem sits
## left of the item card. Built on first show; view-only.

const GROUND_ART: String = "res://assets/art/svg/ground/%s_%s.svg"
const EMBLEM_ART: String = "res://assets/art/svg/icons/emblem_%s.svg"
## The tank of each faction, which stands beside every building for scale.
const TANKS: Dictionary[StringName, StringName] = {
	&"fossil": &"heavy_tank", &"renew": &"renew_tank"
}
## The heading each faction's units are shown with, their default view (Spec 04): south-east for the
## Derrick League, south-west for the Lumen Accord.
const UNIT_DIRS: Dictionary[StringName, int] = {&"fossil": 6, &"renew": 10}
const BUILD_ZOOMS: Array[float] = [1.0, 0.75, 1.5]  ## The camera zoom levels, in the page's order.
const BAKE_SCALE: float = 1.0  ## What a match asks of the atlas.
const TILE_HALF: Vector2 = Vector2(32.0, 16.0)
const MARGIN_CELLS: int = 1  ## Cells of ground round the footprint.
## Where the two tanks stand from the footprint's centre, in milli-tiles of grid x and y: the front
## one east of the front corner and south of it on the screen, the behind one beyond the back
## corner, shifted to the right of the building's axis.
const FRONT_MILLI: int = 700
const BEHIND_MILLI: int = 300
const BEHIND_SHIFT_MILLI: int = 700
const HEAD_DIR: int = 8  ## The head faces down the screen, at the tank in front.
const GROUND_Z: int = -2
const SHADOW_Z: int = -1
const GAP_PX: float = 16.0
const EMBLEM_PX: float = 72.0  ## The faction's emblem, left of the item card.
const TITLE_WIDTH_PX: float = 460.0  ## Clear of the emblem.

var atlas: IsoAtlas = IsoAtlas.new()  ## The bake of the building shown; empty before the first.
var _emblem: TextureRect = null


func _init() -> void:
	super()
	name = "BuildingsPage"


## The name of a section: the zoom in percent and the triad, `Zoom75Arktisk`.
static func section_name(zoom: float, triad: int) -> String:
	return "Zoom%d%s" % [roundi(zoom * 100.0), TRIAD_NAMES[triad]]


## The ground point of a unit standing `where` ("Front" or "Behind") a building of `footprint`
## cells, from the footprint's centre, in milli-tiles.
static func unit_milli(footprint: int, where: StringName) -> Vector2i:
	var corner: int = footprint * ViewScale.MILLI_PER_TILE / 2
	if where == &"Front":
		return Vector2i.ONE * (corner + FRONT_MILLI)
	return Vector2i(
		BEHIND_SHIFT_MILLI - corner - BEHIND_MILLI, -corner - BEHIND_MILLI - BEHIND_SHIFT_MILLI
	)


func _model_paths() -> Array[String]:
	var found: Array[String] = []
	for path: String in ArtGen.model_paths():
		if (load(path) as ArtModel).category == &"bld":
			found.append(path)
	return found


## The Iso page's list, buttons, title and card, and the emblem left of the card.
func _build_ui() -> void:
	super()
	_title.size.x = TITLE_WIDTH_PX
	_emblem = TextureRect.new()
	_emblem.name = "Emblem"
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_emblem.anchor_left = 1.0
	_emblem.anchor_right = 1.0
	_emblem.offset_right = _icon.offset_left - 16.0
	_emblem.offset_left = _emblem.offset_right - EMBLEM_PX
	_emblem.offset_top = 24.0 + (ICON_PX - EMBLEM_PX) / 2.0
	_emblem.offset_bottom = _emblem.offset_top + EMBLEM_PX
	add_child(_emblem)


## The building at `_index`: its atlas, then a section for each zoom and triad.
func _fill() -> void:
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var model: ArtModel = load(_paths[_index]) as ArtModel
	_title.text = (
		"%d / %d  %s: %s (%dx%d)"
		% [
			_index + 1,
			_paths.size(),
			FACTION_NAMES[model.faction],
			model.art_id,
			model.footprint,
			model.footprint
		]
	)
	_icon.texture = load(ArtGen.icon_path(model)) as Texture2D
	var emblem: String = EMBLEM_ART % model.faction
	_emblem.texture = load(emblem) as Texture2D if ResourceLoader.exists(emblem) else null
	_emblem.modulate = Color(ArtPalette.KEYS[model.faction][ArtPalette.LEFT])
	var index: IsoIndex = load(IsoIndex.PATH) as IsoIndex
	var building: IsoSheetDef = index.sheet(model.art_id)
	var tank: IsoSheetDef = index.sheet(TANKS[model.faction])
	var arts: Array[IsoPlayerArt] = []
	for triad: int in TRIAD_NAMES.size():
		arts.append(
			IsoPlayerArt.make(
				model.faction,
				PackedStringArray(ArtPalette.KEYS[model.faction]),
				PackedStringArray(TRIADS[triad])
			)
		)
	atlas = IsoAtlas.build([building, tank], arts, BAKE_SCALE)
	var grounds: Array[ColorRect] = [_ground("Grass", grass_color), _ground("Sand", sand_color)]
	var top: float = FIRST_TOP_PX
	for zoom: float in BUILD_ZOOMS:
		for triad: int in TRIAD_NAMES.size():
			var height: float = 0.0
			for ground: ColorRect in grounds:
				height = _scene_section(ground, building, tank, zoom, triad, top)
			top += height
	_content.custom_minimum_size = Vector2(0.0, maxf(top, get_viewport_rect().size.y))


## One zoom and triad on one ground: its label and the scene under it. Returns the height it took.
func _scene_section(
	ground: ColorRect, building: IsoSheetDef, tank: IsoSheetDef, zoom: float, triad: int, top: float
) -> float:
	var row: Control = Control.new()
	row.name = section_name(zoom, triad)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.offset_top = top
	ground.add_child(row)
	var title: Label = _label("%s, zoom %s" % [TRIAD_NAMES[triad], zoom], HALF_WIDTH_PX)
	title.position.x = -HALF_WIDTH_PX / 2.0
	row.add_child(title)
	var bounds: Rect2 = _scene_bounds(building, tank, zoom)
	var scene: Node2D = _scene(ground.name == "Sand", building, tank, zoom, triad)
	scene.position = Vector2(0.0, LABEL_PX - bounds.position.y)
	row.add_child(scene)
	return LABEL_PX + bounds.size.y + GAP_PX


## Everything the scene covers, in px from the footprint's centre at `zoom`: the ground, the
## building and its shadow, and a tank's frames at each of the two places.
func _scene_bounds(building: IsoSheetDef, tank: IsoSheetDef, zoom: float) -> Rect2:
	var cells: int = building.footprint + 2 * MARGIN_CELLS
	var reach: Vector2 = Vector2(cells * TILE_HALF.x, cells * TILE_HALF.y) * zoom
	var box: Rect2 = Rect2(-reach, 2.0 * reach)
	for part: StringName in [&"hull", &"shadow"]:
		box = box.merge(_frame_rect(building, part, Vector2.ZERO, zoom))
	for where: StringName in [&"Front", &"Behind"]:
		var at: Vector2 = _px(unit_milli(building.footprint, where), zoom)
		for part: StringName in [&"hull", &"shadow"]:
			box = box.merge(_frame_rect(tank, part, at, zoom))
		var mount: Vector2 = tank.mount(UNIT_DIRS[tank.faction]) * BASE_SCALE * zoom
		box = box.merge(_frame_rect(tank, &"turret", at + mount, zoom))
	return box


## The canvas of `part` of `sheet` with its origin at `at`, px at `zoom`.
func _frame_rect(sheet: IsoSheetDef, part: StringName, at: Vector2, zoom: float) -> Rect2:
	if not sheet.has_part(part):
		return Rect2(at, Vector2.ZERO)
	var scale_px: float = BASE_SCALE * zoom
	return Rect2(
		at - Vector2(sheet.origin(part)) * scale_px, Vector2(sheet.frame_size(part)) * scale_px
	)


## The scene on `sand` or grass for the player `triad`: the ground diamonds under a y-sorted node
## of the building's rig and the two tanks'.
func _scene(
	sand: bool, building: IsoSheetDef, tank: IsoSheetDef, zoom: float, triad: int
) -> Node2D:
	var scene: Node2D = Node2D.new()
	scene.name = "Scene"
	var floor_tiles: Node2D = Node2D.new()
	floor_tiles.name = "Ground"
	floor_tiles.z_index = GROUND_Z
	scene.add_child(floor_tiles)
	var n: int = building.footprint
	for col: int in range(-MARGIN_CELLS, n + MARGIN_CELLS):
		for row: int in range(-MARGIN_CELLS, n + MARGIN_CELLS):
			var tile: Sprite2D = Sprite2D.new()
			tile.name = "Cell%d_%d" % [col, row]
			tile.texture = load(GROUND_ART % ["sand" if sand else "grass", "ab"[(col + row) & 1]])
			tile.scale = Vector2.ONE * zoom
			var corner: int = ViewScale.MILLI_PER_TILE
			tile.position = _px(Vector2i(2 * col + 1 - n, 2 * row + 1 - n) * corner / 2, zoom)
			floor_tiles.add_child(tile)
	var rigs: Node2D = Node2D.new()
	rigs.name = "Rigs"
	rigs.y_sort_enabled = true
	scene.add_child(rigs)
	rigs.add_child(_scene_rig("Building", building, Vector2i.ZERO, HEAD_DIR, zoom, triad))
	for where: StringName in [&"Front", &"Behind"]:
		var at: Vector2i = unit_milli(n, where)
		rigs.add_child(_scene_rig(String(where), tank, at, UNIT_DIRS[tank.faction], zoom, triad))
	return scene


## A rig of `sheet` standing at ground point `milli`, facing `dir`: Shadow, Hull and the Turret or
## Head at its mount, as the game's rigs have them.
func _scene_rig(
	rig_name: String, sheet: IsoSheetDef, milli: Vector2i, dir: int, zoom: float, triad: int
) -> Node2D:
	var rig: Node2D = Node2D.new()
	rig.name = rig_name
	rig.position = _px(milli, zoom)
	var hull_dir: int = -1 if sheet.category == &"bld" else dir
	for part: StringName in [&"shadow", &"hull", &"turret", &"head"]:
		if not sheet.has_part(part):
			continue
		var frame: int = hull_dir if part in [&"shadow", &"hull"] else dir
		var sprite: Sprite2D = Sprite2D.new()
		sprite.name = String(part).capitalize()
		sprite.texture = atlas.texture()
		sprite.region_enabled = true
		sprite.centered = false
		sprite.region_rect = Rect2(atlas.region(sheet.art_id, part, frame, triad))
		sprite.scale = Vector2.ONE * BASE_SCALE * zoom / atlas.bake_scale()
		sprite.offset = -Vector2(sheet.origin(part)) * atlas.bake_scale()
		if part == &"shadow":
			sprite.z_index = SHADOW_Z
		if part in [&"turret", &"head"]:
			var mount_dir: int = 6 if sheet.category == &"bld" else dir
			sprite.position = sheet.mount(mount_dir) * BASE_SCALE * zoom
		rig.add_child(sprite)
	return rig


func _px(milli: Vector2i, zoom: float) -> Vector2:
	return IsoProjection.ground_to_px(milli.x, milli.y) * zoom
