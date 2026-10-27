extends Control
## Art gallery (developer scene): every asset at gameplay zoom on grass and sand, in both team
## colours, so the art can be judged on a phone through the web preview.
##
## View-only. The Units page (the one the gallery opens on) shows the six Derrick League units
## (plan row P101, ADR 0023) as the generator draws them: `_add_roster` puts the units of
## `art_gallery_units.gd` in a line for team A (the Signal triad) and one for team B (Arktisk) on
## each ground, the names under team B's line, and `_fill_zoom_rows` the Flarejack at the camera
## zoom levels in the scene's `ZoomRow` of each ground (team A on grass, team B on sand), so how
## the art looks at 0.75, 1 and 1.5 can be judged. A generated unit has no `Team` layer: the team
## colour is in its SVG text, replaced per player as the match-start bake does. `_add_atlas` adds
## the effects atlas at scale 1 to each ground, and `_add_terrain_row` a patch of map tiles with
## the explored fog over its second row.
##
## The button at the top right turns the pages: Units, Build, Ground, Icons, Iso and Terrain.
## Build (`_add_build_page`, `art_gallery_build.gd`, plan row P103, STYLE.md "Buildings") shows each
## building of both factions on the iso ground with a tank in front of it and one behind it at the
## camera zooms in two triads, the faction's emblem beside the item card. Iso (`_add_iso_page`,
## `art_gallery_iso.gd`, ADR 0023) steps through the generated blockouts and models of both
## factions, every direction in two team colours at the camera zooms. Terrain
## (`_add_terrain_page`, `art_gallery_ground.gd`, plan row P105) shows the iso ground diamonds, the
## oil and gas field stages, the wellhead and the crater on the off-map colour. Ground
## (`_add_ground_page`) shows the ore cells by level, a mixed ore field, and the ghost looks of
## STYLE.md ("Ghosts") on the iso barracks, the one that does not fit with its reason glyph. Icons
## (`_add_icons_page`) shows the sidebar's tab and item icons and the HUD glyphs at their size in
## dp on a dark HUD panel, and the glyphs and rally flags that sit on the map on grass and sand.
## The pages after Units are built in code and start hidden.
##
## To add a unit: its model goes under `assets/art/models/` (STYLE.md "Generated art") and its art
## id into `ROSTER_IDS`. A building goes into the Build page (`art_gallery_build.gd`). A flag is a
## rig with the layers `Hull` and `Team` in a team group.

const TEAM_A_GROUP: StringName = &"gallery_team_a"
const TEAM_B_GROUP: StringName = &"gallery_team_b"
const TEAM_LAYER: NodePath = ^"Team"
const TURRET_LAYER: String = "Turret"
## Kept for tests/project, which holds it equal to `UnitLayer.RING_TEX_RADIUS_PX` until P114b moves
## the view's rings to the ellipse and drops the circle (STYLE.md "Selection ring").
const RING_TEX_RADIUS_PX: float = 72.0
const PX_PER_DP: float = 1.75  ## Base px per dp on the 6-inch phone profile.
## The Units page: the six Derrick League units by art id and display name (Michael's, ADR 0023
## section 7), a line each for team A and team B on a ground, as rows of the ground's height.
const ROSTER_IDS: Array[String] = [
	"rifle_squad", "rocket_squad", "light_tank", "heavy_tank", "artillery", "harvester"
]
const ROSTER_NAMES: Array[String] = [
	"Roustabouts", "Wildcatters", "Flarejack", "Bullhead", "Mortar Rig", "Tanker"
]
const ROSTER_TOPS: Array[float] = [0.4, 0.55]
const ROSTER_GAP_PX: float = 104.0
const ROSTER_LABEL_PX: int = 20
const ROSTER_LABEL_COLOR: Color = Color("1C2127")
const ZOOM_UNIT: String = "light_tank"  ## The zoom row's unit.
const ATLAS_ART: String = "res://assets/art/svg/fx/effects_atlas.svg"
const ATLAS_TOP_PX: float = 20.0
const ATLAS_LEFT_PX: Dictionary[String, float] = {"Grass": 190.0, "Sand": 282.0}
## Map colours by `MapView.colors` key (STYLE.md, "Fog and terrain"): a terrain id, and `<id>_b` and
## `<id>_c` for the second and third tone of its tile.
const TERRAIN_COLORS: Dictionary[StringName, Color] = {
	&"grass": Color("5E7D4A"),
	&"grass_b": Color("6F8F57"),
	&"sand": Color("CDB98F"),
	&"scrub": Color("4E5A3A"),
	&"scrub_b": Color("6B7A4F"),
	&"scrub_c": Color("8C9A6B"),
	&"rock": Color("6E6A66"),
	&"rock_b": Color("8C8782"),
	&"rock_c": Color("4F4B48"),
	&"water": Color("2E5E7E"),
	&"water_b": Color("3C7396"),
	&"ore": Color("8A6F4D"),
}
## The map tiles, 8x8 texels, as filled rects "x,y,w,h,key" (a `TERRAIN_COLORS` key) in drawing
## order: the base, then the pattern rects. There is no grid. Grass has one per parity of x + y.
const TERRAIN_TILES: Dictionary[StringName, String] = {
	&"grass": "0,0,8,8,grass",
	&"grass_b": "0,0,8,8,grass_b",
	&"sand": "0,0,8,8,sand",
	&"scrub": "0,0,8,8,scrub 1,1,3,3,scrub_b 4,4,3,3,scrub_b 1,1,1,1,scrub_c 4,4,1,1,scrub_c",
	&"rock": "0,0,8,8,rock 0,0,8,1,rock_b 0,0,1,8,rock_b 0,7,8,1,rock_c 7,0,1,8,rock_c",
	&"water": "0,0,8,8,water 1,2,4,1,water_b 4,6,4,1,water_b",
	&"ore": "0,0,8,8,ore",
}
## The terrain row's map patch: one terrain id per column, the same in every row, and the fog over
## the rows after the first. Scrub is two tiles wide, so both teams' squads stand on it.
const PATCH_IDS: Array[StringName] = [
	&"grass", &"grass", &"scrub", &"scrub", &"grass", &"rock", &"water", &"sand"
]
const PATCH_ROWS: int = 2
const TILE_PX: float = 64.0  ## One tile at gameplay zoom.
const FRAME_PX: float = 4.0  ## The dark frame around the patch, so every tile edge shows.
const FRAME_COLOR: Color = Color("1C2127")
const TERRAIN_ROW_TOP: float = 0.02
## The pages the button at the top right cycles through; the button shows the page it is on.
const PAGES: Array[String] = ["Units", "Build", "Ground", "Icons", "Iso", "Terrain"]
const BuildPage: GDScript = preload("res://game/view/art_gallery_build.gd")
const Units: GDScript = preload("res://game/view/art_gallery_units.gd")
const IsoPage: GDScript = preload("res://game/view/art_gallery_iso.gd")
const TerrainPage: GDScript = preload("res://game/view/art_gallery_ground.gd")
const ORE_ART: String = "res://assets/art/svg/ore/ore_%s.svg"
## Ore tiles by `ore_<name>.svg`: the five fill levels, two variants of each from level 1 up. A
## row of a patch is one string of names, left to right (STYLE.md, "Ore").
const ORE_LEVEL_ROWS: Array[String] = ["0 1a 2a 3a 4a", "0 1b 2b 3b 4b"]
const ORE_FIELD_ROWS: Array[String] = ["0 1a 2b 3a 2a 1b", "1b 3b 4a 4b 3a 2b", "0 2a 3b 4b 3b 1a"]
const ORE_LEVEL_TOP: float = 12.0
const ORE_FIELD_TOP: float = 168.0
const GHOST_ROW_TOP: float = 420.0
const SWATCH_ROW_TOP: float = 560.0
const GHOST_ART: String = "res://assets/art/svg/ui/ghost_%s.svg"
const GHOST_BUILDING: String = "barracks"  ## A 2x2 building: a diamond 128 px wide.
const GHOST_ART_SCALE: float = 0.5  ## The 2x art at zoom 1.
const GHOST_GAP_PX: float = 28.0
const SWATCH_SIZE: Vector2 = Vector2(192.0, 128.0)
## The ghost looks (STYLE.md, "Ghosts"): ok and danger are the UI accents, neutral the neutral team
## colour. Alphas are of the layer they colour.
const GHOST_OK: Color = Color("30A46C")
const GHOST_DANGER: Color = Color("E5484D")
const GHOST_NEUTRAL: Color = Color("9AA5B1")
const GHOST_SPRITE_ALPHA: float = 0.7
const GHOST_WASH_ALPHA: float = 0.3
const GHOST_HATCH_ALPHA: float = 0.8
const GHOST_DOTS_ALPHA: float = 0.7
const GHOST_FRAME_PX: float = 3.0
## The reason glyph the "Blocked" ghost shows, at the size of a glyph on the map (STYLE.md: the
## "Blocked" of a pending ghost uses the occupied glyph).
const GHOST_REASON_GLYPH: String = "glyph_reason_occupied"
## The Icons page (STYLE.md, "Icons and glyphs"). Icons are `icons/<name>.svg`, 128 px, import scale
## 1.0, shown at their size in dp: a build tile icon 64 dp, a tab 48 dp, a HUD glyph 48 dp and a
## glyph on the map 32 dp, at the 6-inch phone's 1.75 base px per dp.
const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const FLAG_ART: String = "res://assets/art/svg/flags/%s_%s.svg"
const TAB_ICONS: Array[String] = ["tab_structures", "tab_infantry", "tab_vehicles"]
const ITEM_ICONS: Array[String] = [
	"item_power_plant",
	"item_refinery",
	"item_barracks",
	"item_vehicle_factory",
	"item_defence_turret",
	"item_rifle_squad",
	"item_rocket_squad",
	"item_light_tank",
	"item_heavy_tank",
	"item_artillery",
	"item_harvester",
]
const HUD_GLYPHS: Array[String] = [
	"glyph_credits",
	"glyph_power",
	"glyph_low_power",
	"glyph_lock",
	"glyph_check",
	"glyph_cross",
]
const EMBLEMS: Array[String] = ["glyph_victory", "glyph_defeat", "glyph_draw"]
const MAP_GLYPHS: Array[String] = [
	"glyph_reason_outside",
	"glyph_reason_ground",
	"glyph_reason_occupied",
	"glyph_reason_unexplored",
	"glyph_reason_too_far",
	"glyph_reason_cap",
	"glyph_offline",
]
const ARROW_GLYPH: String = "glyph_under_attack"  ## At least 48 dp on screen (ADR 0019 section 5).
const RALLY_FLAGS: Array[String] = ["rally_infantry", "rally_vehicles"]
const ITEM_ICON_DP: float = 64.0
const TAB_ICON_DP: float = 48.0
const HUD_GLYPH_DP: float = 48.0
const MAP_GLYPH_DP: float = 32.0
const ICON_GAP_PX: float = 10.0
const ITEM_COLUMNS: int = 4
const HUD_BACKDROP: Color = Color("0F141C")  ## STYLE.md: the HUD panel backdrop, here opaque.
const TILE_BACKDROP: Color = Color("1B2430")  ## A build tile's own panel, a step lighter.
const TILE_MARGIN_PX: float = 4.0
## The tint the HUD gives a glyph (STYLE.md): a palette colour by state; a glyph not listed stays
## white. The tabs show the first one selected, the others at rest.
const GLYPH_TINTS: Dictionary[String, Color] = {
	"tab_infantry": Color("9AA5B1"),
	"tab_vehicles": Color("9AA5B1"),
	"glyph_credits": Color("F2B705"),
	"glyph_power": Color("30A46C"),
	"glyph_low_power": Color("F5A524"),
	"glyph_lock": Color("9AA5B1"),
	"glyph_check": Color("30A46C"),
	"glyph_cross": Color("E5484D"),
	"glyph_victory": Color("30A46C"),
	"glyph_defeat": Color("E5484D"),
	"glyph_draw": Color("9AA5B1"),
	"glyph_reason_outside": Color("E5484D"),
	"glyph_reason_ground": Color("E5484D"),
	"glyph_reason_occupied": Color("E5484D"),
	"glyph_reason_unexplored": Color("E5484D"),
	"glyph_reason_too_far": Color("E5484D"),
	"glyph_reason_cap": Color("E5484D"),
	"glyph_offline": Color("F5A524"),
	"glyph_under_attack": Color("E5484D"),
}
## Rows of the Icons page, in base px from the top of their half: the HUD panel (left) holds the
## tabs, the item tiles, the HUD glyphs and the result emblems; the grass and sand strips (right)
## each hold the map glyphs, then the arrow and the rally flags. Rows under the corner buttons,
## which cover 24 to 144 px from the top and from the left or right edge.
const HUD_ROW_TOPS: Array[float] = [12.0, 152.0, 520.0, 612.0]
const MAP_ROW_TOPS: Dictionary[String, Array] = {"Grass": [152.0, 250.0], "Sand": [24.0, 132.0]}
const FLAG_GAP_PX: float = 24.0

@export var team_a_color: Color = Color("2F80ED")
@export var team_b_color: Color = Color("E5484D")
## Turret turn speed in radians per second.
@export var turret_turn_speed: float = 0.5
## The fog alpha of explored but not visible tiles (STYLE.md; `FogLayer.explored_alpha`).
@export var explored_fog_alpha: int = 140

var _turrets: Array[Sprite2D] = []
var _previous_quit_on_go_back: bool = true
var _page: int = 0
var _unit_page: Array[CanvasItem] = []
var _units: RefCounted = Units.new()  ## The generated units' textures, made once.
var _buildings_page: Control = null
var _ground_page: Control = null
var _icons_page: Control = null
var _iso_page: Control = null
var _terrain_page: Control = null

@onready var _back_button: Button = %BackButton
@onready var _page_button: Button = %PageButton


func _enter_tree() -> void:
	# SceneTree.quit_on_go_back is true by default and would quit the app on the Android back
	# button before the gallery can leave. Switch it off while the gallery is open.
	var tree: SceneTree = get_tree()
	_previous_quit_on_go_back = tree.quit_on_go_back
	tree.quit_on_go_back = false


func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_quit_on_go_back


func _ready() -> void:
	_add_roster()
	_fill_zoom_rows()
	_add_atlas()
	_add_terrain_row()
	for node_name: String in ["Grass", "Sand", "TerrainRow"]:
		_unit_page.append(get_node(node_name) as CanvasItem)
	_add_ground_page()
	_add_icons_page()
	_add_build_page()
	_add_iso_page()
	_add_terrain_page()
	_tint_team_layers(TEAM_A_GROUP, team_a_color)
	_tint_team_layers(TEAM_B_GROUP, team_b_color)
	for node: Node in find_children(TURRET_LAYER, "Sprite2D", true, false):
		var turret: Sprite2D = node as Sprite2D
		if turret != null:
			_turrets.append(turret)
	_back_button.pressed.connect(_go_back)
	_page_button.pressed.connect(_next_page)
	# The pages are opaque and added last, so the two buttons move above them.
	move_child(_back_button, -1)
	move_child(_page_button, -1)
	_show_page(0)


func _process(delta: float) -> void:
	var step: float = turret_turn_speed * delta
	for turret: Sprite2D in _turrets:
		turret.rotation = wrapf(turret.rotation + step, 0.0, TAU)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Never change scenes from inside a notification dispatch.
		_go_back.call_deferred()


## The six units on each ground in a line for team A and one for team B, the names under team B's.
func _add_roster() -> void:
	for ground_name: String in ["Grass", "Sand"]:
		var ground: Control = get_node(ground_name)
		for index: int in ROSTER_TOPS.size():
			var is_team_a: bool = index == 0
			var row: Control = _anchored_row(
				ground, "RosterA" if is_team_a else "RosterB", ROSTER_TOPS[index]
			)
			for i: int in ROSTER_IDS.size():
				var unit: Node2D = _units.make(ROSTER_IDS[i], 0 if is_team_a else 1)
				unit.position = Vector2((i - (ROSTER_IDS.size() - 1) / 2.0) * ROSTER_GAP_PX, 0.0)
				unit.add_to_group(TEAM_A_GROUP if is_team_a else TEAM_B_GROUP)
				row.add_child(unit)
				if not is_team_a:
					row.add_child(_roster_label(ROSTER_NAMES[i], unit.position.x))


## The name of a unit under its rig.
func _roster_label(text: String, centre: float) -> Label:
	var label: Label = Label.new()
	label.name = "Label" + text.to_pascal_case()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", ROSTER_LABEL_PX)
	label.add_theme_color_override(&"font_color", ROSTER_LABEL_COLOR)
	label.position = Vector2(centre - ROSTER_GAP_PX / 2.0, 18.0)
	label.size = Vector2(ROSTER_GAP_PX, 28.0)
	return label


## The zoom row's rigs (scaled by the camera zoom levels, in the scene) get the Flarejack, team A on
## grass and team B on sand, drawn at the sharpness the zoom asks for.
func _fill_zoom_rows() -> void:
	for ground_name: String in ["Grass", "Sand"]:
		for node: Node in get_node(ground_name + "/ZoomRow").get_children():
			var rig: Node2D = node as Node2D
			if rig != null:
				_units.fill(rig, ZOOM_UNIT, 0 if rig.is_in_group(TEAM_A_GROUP) else 1, rig.scale.x)


## The effects atlas at scale 1 on each ground.
func _add_atlas() -> void:
	for ground_name: String in ["Grass", "Sand"]:
		var ground: Control = get_node(ground_name)
		var atlas: TextureRect = TextureRect.new()
		atlas.name = "EffectsAtlas"
		atlas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		atlas.texture = load(ATLAS_ART)
		atlas.position = Vector2(ATLAS_LEFT_PX[ground_name], ATLAS_TOP_PX)
		ground.add_child(atlas)


func _add_terrain_row() -> void:
	var row: Control = _anchored_row(self, "TerrainRow", TERRAIN_ROW_TOP)
	var extent: Vector2 = Vector2(PATCH_IDS.size(), PATCH_ROWS) * TILE_PX
	var origin: Vector2 = Vector2(-extent.x / 2.0, 0.0)
	var frame: ColorRect = ColorRect.new()
	frame.name = "Frame"
	frame.color = FRAME_COLOR
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = origin - Vector2.ONE * FRAME_PX
	frame.size = extent + Vector2.ONE * 2.0 * FRAME_PX
	row.add_child(frame)
	var patch: TextureRect = TextureRect.new()
	patch.name = "Patch"
	patch.texture = ImageTexture.create_from_image(patch_image())
	patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	patch.position = origin
	patch.size = extent
	row.add_child(patch)
	var fog: ColorRect = ColorRect.new()
	fog.name = "ExploredFog"
	fog.color = Color(0.0, 0.0, 0.0, explored_fog_alpha / 255.0)
	fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fog.position = origin + Vector2(0.0, TILE_PX)
	fog.size = extent - Vector2(0.0, TILE_PX)
	row.add_child(fog)


## The CPU-side map patch of the terrain row, 8 texels per tile.
static func patch_image() -> Image:
	var image: Image = Image.create(8 * PATCH_IDS.size(), 8 * PATCH_ROWS, false, Image.FORMAT_RGBA8)
	for y: int in PATCH_ROWS:
		for x: int in PATCH_IDS.size():
			var id: StringName = PATCH_IDS[x]
			if id == &"grass" and (x + y) % 2 == 1:
				id = &"grass_b"
			var tile: Image = tile_image(TERRAIN_TILES[id])
			image.blit_rect(tile, Rect2i(0, 0, 8, 8), Vector2i(8 * x, 8 * y))
	return image


## The CPU-side 8x8 tile of a `TERRAIN_TILES` spec: its rects in drawing order, nothing else.
static func tile_image(spec: String) -> Image:
	var image: Image = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for fill: String in spec.split(" "):
		var part: PackedStringArray = fill.split(",")
		var rect: Rect2i = Rect2i(int(part[0]), int(part[1]), int(part[2]), int(part[3]))
		image.fill_rect(rect, TERRAIN_COLORS[StringName(part[4])])
	return image


## An empty Control in the middle of `ground`, `top` of the way down, that rigs are added to.
func _anchored_row(ground: Control, row_name: String, top: float) -> Control:
	var row: Control = Control.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.anchor_top = top
	row.anchor_bottom = top
	ground.add_child(row)
	return row


func _tint_team_layers(group: StringName, color: Color) -> void:
	for rig: Node in get_tree().get_nodes_in_group(group):
		if not is_ancestor_of(rig):
			continue
		var layer: CanvasItem = rig.get_node_or_null(TEAM_LAYER) as CanvasItem
		if layer != null:
			layer.modulate = color


## The Build page (plan row P103, STYLE.md "Buildings"), built by `art_gallery_build.gd` on first
## show.
func _add_build_page() -> void:
	_buildings_page = BuildPage.new()
	_buildings_page.grass_color = TERRAIN_COLORS[&"grass_b"]
	_buildings_page.sand_color = TERRAIN_COLORS[&"sand"]
	add_child(_buildings_page)


## The Iso page (plan row P99, ADR 0023): the generated blockouts, built by `art_gallery_iso.gd`.
func _add_iso_page() -> void:
	_iso_page = IsoPage.new()
	_iso_page.grass_color = TERRAIN_COLORS[&"grass_b"]
	_iso_page.sand_color = TERRAIN_COLORS[&"sand"]
	add_child(_iso_page)


## The Terrain page (plan row P105): the iso ground, fields, wellhead and crater, built by
## `art_gallery_ground.gd` on first show.
func _add_terrain_page() -> void:
	_terrain_page = TerrainPage.new()
	_terrain_page.grass_color = TERRAIN_COLORS[&"grass_b"]
	_terrain_page.sand_color = TERRAIN_COLORS[&"sand"]
	add_child(_terrain_page)


func _layer_sprite(layer: String, path: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = layer.capitalize()
	sprite.texture = load(path)
	return sprite


## The Ground page: ore by level and as a field, the ghost looks and the two pattern tiles.
func _add_ground_page() -> void:
	_ground_page = _page_root("GroundPage")
	for ground_name: String in ["Grass", "Sand"]:
		var ground: ColorRect = _page_ground(_ground_page, ground_name)
		_add_ore_patch(_pixel_row(ground, "OreLevels", ORE_LEVEL_TOP), ORE_LEVEL_ROWS)
		_add_ore_patch(_pixel_row(ground, "OreField", ORE_FIELD_TOP), ORE_FIELD_ROWS)
		_add_ghost_row(_pixel_row(ground, "Ghosts", GHOST_ROW_TOP))
		_add_swatches(_pixel_row(ground, "Swatches", SWATCH_ROW_TOP))


## Ore tiles side by side with no gap, in the dark frame of the terrain patch.
func _add_ore_patch(row: Control, spec_rows: Array[String]) -> void:
	var columns: int = spec_rows[0].split(" ").size()
	var extent: Vector2 = Vector2(columns, spec_rows.size()) * TILE_PX
	var origin: Vector2 = Vector2(-extent.x / 2.0, 0.0)
	var frame: ColorRect = ColorRect.new()
	frame.name = "Frame"
	frame.color = FRAME_COLOR
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.position = origin - Vector2.ONE * FRAME_PX
	frame.size = extent + Vector2.ONE * 2.0 * FRAME_PX
	row.add_child(frame)
	for y: int in spec_rows.size():
		var names: PackedStringArray = spec_rows[y].split(" ")
		for x: int in names.size():
			var tile: TextureRect = TextureRect.new()
			tile.name = "Ore%d_%d" % [x, y]
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.texture = load(ORE_ART % names[x])
			tile.position = origin + Vector2(x, y) * TILE_PX
			tile.size = Vector2.ONE * TILE_PX
			row.add_child(tile)


## Three ghosts of one 2x2 building: it fits, it does not fit, and it was last seen. A cell is the
## building's canvas box at zoom 1, which the diamond of its footprint fills the foot of (ADR 0023
## section 3: the marks lie on the footprint's cells, the sprite rises from the back corner).
func _add_ghost_row(row: Control) -> void:
	var sheet: IsoSheetDef = (load(IsoIndex.PATH) as IsoIndex).sheet(StringName(GHOST_BUILDING))
	var size: Vector2 = Vector2(sheet.frame_size(&"hull")) * GHOST_ART_SCALE
	var half: Vector2 = Vector2(
		sheet.footprint * IsoProjection.HALF_W, sheet.footprint * IsoProjection.HALF_H
	)
	var back: Vector2 = Vector2(size.x / 2.0, sheet.anchor(&"hull").y * GHOST_ART_SCALE)
	var diamond: PackedVector2Array = PackedVector2Array(
		[
			back,
			back + Vector2(half.x, half.y),
			back + Vector2(0.0, 2.0 * half.y),
			back + Vector2(-half.x, half.y)
		]
	)
	var kinds: Array[String] = ["Valid", "Blocked", "Seen"]
	for i: int in kinds.size():
		var cell: Control = Control.new()
		cell.name = "Ghost" + kinds[i]
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.size = size
		cell.position = Vector2((i - 1) * (size.x + GHOST_GAP_PX) - size.x / 2.0, 0.0)
		row.add_child(cell)
		_build_ghost(cell, kinds[i], diamond)


## A ghost: own building at a fade over a wash on its footprint's diamond and a solid frame when it
## fits; the same in danger red with the hatch tile and a reason glyph on top when it does not (the
## wash first, then the faded sprite, then hatch and frame, so the blocked cells read through it);
## the other player's building under the dots and the explored fog, over the whole sprite box, when
## it was last seen.
func _build_ghost(cell: Control, kind: String, diamond: PackedVector2Array) -> void:
	var seen: bool = kind == "Seen"
	var rig: CanvasGroup = CanvasGroup.new()
	rig.name = "Rig"
	var hull: Sprite2D = Sprite2D.new()
	hull.name = "Hull"
	hull.texture = _ghost_texture(1 if seen else 0)
	hull.centered = false
	rig.add_child(hull)
	if not seen:
		# `self_modulate`, not `modulate`: modulate reaches the Hull child too (as MoveMarkerLayer
		# notes), and the group is what is faded once.
		rig.self_modulate = Color(1.0, 1.0, 1.0, GHOST_SPRITE_ALPHA)
	if seen:
		cell.add_child(rig)
		cell.add_child(_pattern_rect(cell.size, "seen", GHOST_NEUTRAL, GHOST_DOTS_ALPHA))
		var fog: ColorRect = ColorRect.new()
		fog.name = "ExploredFog"
		fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fog.color = Color(0.0, 0.0, 0.0, explored_fog_alpha / 255.0)
		fog.size = cell.size
		cell.add_child(fog)
		return
	var accent: Color = GHOST_OK if kind == "Valid" else GHOST_DANGER
	var wash: Polygon2D = Polygon2D.new()
	wash.name = "Wash"
	wash.polygon = diamond
	wash.color = Color(accent, GHOST_WASH_ALPHA)
	cell.add_child(wash)
	cell.add_child(rig)
	if kind == "Blocked":
		var hatch: Polygon2D = Polygon2D.new()
		hatch.name = "PatternHatch"
		hatch.polygon = diamond
		hatch.uv = diamond
		hatch.texture = load(GHOST_ART % "hatch")
		hatch.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		hatch.color = Color(accent, GHOST_HATCH_ALPHA)
		cell.add_child(hatch)
	var frame: Line2D = Line2D.new()
	frame.name = "Frame"
	frame.points = diamond
	frame.closed = true
	frame.width = GHOST_FRAME_PX
	frame.default_color = accent
	cell.add_child(frame)
	if kind == "Blocked":
		# The glyph on the hatch it is read against: it is tinted danger red like the hatch, so the
		# seat in its file (STYLE.md, "Icons and glyphs") is what keeps it apart from the bands.
		var size_px: float = MAP_GLYPH_DP * PX_PER_DP
		var middle: Vector2 = (diamond[0] + diamond[2]) / 2.0
		cell.add_child(
			_icon_rect(GHOST_REASON_GLYPH, size_px, middle - Vector2.ONE * size_px / 2.0)
		)


## The ghost building's hull frame in the triad of player `triad` (0 Signal, 1 Arktisk), the
## Derrick League's own art with its key triad replaced as the match-start bake does it, at the
## scale of zoom 1.
func _ghost_texture(triad: int) -> ImageTexture:
	var path: String = IsoSheetDef.frame_path(
		&"fossil", &"bld", StringName(GHOST_BUILDING), &"hull", -1
	)
	var art: IsoPlayerArt = IsoPlayerArt.make(
		&"fossil",
		PackedStringArray(ArtPalette.KEYS[&"fossil"]),
		PackedStringArray(WorldSort.TRIADS[triad])
	)
	var image: Image = Image.new()
	image.load_svg_from_string(art.recolour(FileAccess.get_file_as_string(path)), GHOST_ART_SCALE)
	return ImageTexture.create_from_image(image)


## The two pattern tiles on their own, repeated over a rect, so the seams can be judged.
func _add_swatches(row: Control) -> void:
	var names: Array[String] = ["hatch", "seen"]
	var colours: Array[Color] = [GHOST_DANGER, GHOST_NEUTRAL]
	for i: int in names.size():
		var swatch: TextureRect = _pattern_rect(SWATCH_SIZE, names[i], colours[i], 1.0)
		swatch.name = "Swatch" + names[i].capitalize()
		swatch.position = Vector2(
			(i - 1) * (SWATCH_SIZE.x + GHOST_GAP_PX) + GHOST_GAP_PX / 2.0, 0.0
		)
		row.add_child(swatch)


## A pattern tile (`ui/ghost_<name>.svg`) repeated over `extent`, tinted `colour` at `alpha`.
func _pattern_rect(extent: Vector2, name: String, colour: Color, alpha: float) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.name = "Pattern" + name.capitalize()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = load(GHOST_ART % name)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_TILE
	rect.size = extent
	rect.modulate = Color(colour, alpha)
	return rect


## A page: an empty full-screen Control that starts hidden, over the Units page.
func _page_root(page_name: String) -> Control:
	var page: Control = Control.new()
	page.name = page_name
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.visible = false
	add_child(page)
	return page


## The grass half (left) or the sand half (right) of a page, with the colours of the Units page.
func _page_ground(page: Control, ground_name: String) -> ColorRect:
	var is_grass: bool = ground_name == "Grass"
	var ground: ColorRect = ColorRect.new()
	ground.name = ground_name
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ground.color = TERRAIN_COLORS[&"grass_b"] if is_grass else TERRAIN_COLORS[&"sand"]
	ground.anchor_left = 0.0 if is_grass else 0.5
	ground.anchor_right = 0.5 if is_grass else 1.0
	ground.anchor_bottom = 1.0
	page.add_child(ground)
	return ground


## An empty Control `top` base px down the middle of `ground`, that a row of things is added to.
func _pixel_row(ground: Control, row_name: String, top: float) -> Control:
	var row: Control = Control.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.offset_top = top
	row.offset_bottom = top
	ground.add_child(row)
	return row


## The Icons page. Left, a HUD panel (the dark backdrop of the sidebar) with the three tab icons at
## 48 dp, the eleven item icons on their tiles at 64 dp, the HUD glyphs and the result emblems at
## 48 dp. Right, the glyphs that sit on the map at 32 dp, the under-attack arrow at 48 dp and the
## rally flags of both teams, on grass (top) and sand (bottom).
func _add_icons_page() -> void:
	_icons_page = _page_root("IconsPage")
	var hud: ColorRect = _icons_half(_icons_page, "Hud", HUD_BACKDROP, Rect2(0.0, 0.0, 0.5, 1.0))
	_icon_grid(_pixel_row(hud, "Tabs", HUD_ROW_TOPS[0]), TAB_ICONS, TAB_ICON_DP, TAB_ICONS.size())
	_icon_grid(
		_pixel_row(hud, "Items", HUD_ROW_TOPS[1]), ITEM_ICONS, ITEM_ICON_DP, ITEM_COLUMNS, true
	)
	_icon_grid(
		_pixel_row(hud, "Glyphs", HUD_ROW_TOPS[2]), HUD_GLYPHS, HUD_GLYPH_DP, HUD_GLYPHS.size()
	)
	_icon_grid(_pixel_row(hud, "Emblems", HUD_ROW_TOPS[3]), EMBLEMS, HUD_GLYPH_DP, EMBLEMS.size())
	for ground_name: String in ["Grass", "Sand"]:
		var is_grass: bool = ground_name == "Grass"
		var colour: Color = TERRAIN_COLORS[&"grass_b"] if is_grass else TERRAIN_COLORS[&"sand"]
		var anchors: Rect2 = Rect2(0.5, 0.0 if is_grass else 0.5, 0.5, 0.5)
		var ground: ColorRect = _icons_half(_icons_page, ground_name, colour, anchors)
		var tops: Array = MAP_ROW_TOPS[ground_name]
		var glyphs: Control = _pixel_row(ground, "MapGlyphs", tops[0])
		_icon_grid(glyphs, MAP_GLYPHS, MAP_GLYPH_DP, MAP_GLYPHS.size())
		_add_flag_row(_pixel_row(ground, "Flags", tops[1]))


## A coloured rectangle of the Icons page, placed by its anchors (a fraction of the page).
func _icons_half(page: Control, node_name: String, colour: Color, anchors: Rect2) -> ColorRect:
	var half: ColorRect = ColorRect.new()
	half.name = node_name
	half.mouse_filter = Control.MOUSE_FILTER_IGNORE
	half.color = colour
	half.anchor_left = anchors.position.x
	half.anchor_top = anchors.position.y
	half.anchor_right = anchors.end.x
	half.anchor_bottom = anchors.end.y
	page.add_child(half)
	return half


## Icons of `dp` dp in lines of `columns`, each line centred on the row. An item icon sits on its
## tile, a step lighter than the panel, the way the sidebar draws it.
func _icon_grid(
	row: Control, icons: Array[String], dp: float, columns: int, tiles: bool = false
) -> void:
	var size_px: float = dp * PX_PER_DP
	for i: int in icons.size():
		var line: int = floori(float(i) / float(columns))
		var in_line: int = mini(columns, icons.size() - line * columns)
		var x: float = (i % columns - (in_line - 1) / 2.0) * (size_px + ICON_GAP_PX) - size_px / 2.0
		var at: Vector2 = Vector2(x, line * (size_px + ICON_GAP_PX))
		if tiles:
			var tile: ColorRect = ColorRect.new()
			tile.name = "Tile" + icons[i].to_pascal_case()
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.color = TILE_BACKDROP
			tile.position = at - Vector2.ONE * TILE_MARGIN_PX
			tile.size = Vector2.ONE * (size_px + 2.0 * TILE_MARGIN_PX)
			row.add_child(tile)
		row.add_child(_icon_rect(icons[i], size_px, at))


## An icon file as a square `TextureRect` of `size_px` at `at`, tinted as the HUD tints it.
func _icon_rect(icon: String, size_px: float, at: Vector2) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.name = icon.to_pascal_case()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = load(ICON_ART % icon)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.position = at
	rect.size = Vector2.ONE * size_px
	rect.modulate = GLYPH_TINTS[icon] if GLYPH_TINTS.has(icon) else Color.WHITE
	return rect


## The under-attack arrow at 48 dp, then the rally flag of each tab in team A and team B.
func _add_flag_row(row: Control) -> void:
	var arrow_px: float = HUD_GLYPH_DP * PX_PER_DP
	var flags: int = RALLY_FLAGS.size() * 2
	var total: float = arrow_px + flags * (TILE_PX + FLAG_GAP_PX)
	var left: float = -total / 2.0
	row.add_child(_icon_rect(ARROW_GLYPH, arrow_px, Vector2(left, 0.0)))
	var centre: float = left + arrow_px + FLAG_GAP_PX + TILE_PX / 2.0
	for flag: String in RALLY_FLAGS:
		for is_team_a: bool in [true, false]:
			var rig: Node2D = Node2D.new()
			rig.name = flag.to_pascal_case() + ("A" if is_team_a else "B")
			rig.add_to_group(TEAM_A_GROUP if is_team_a else TEAM_B_GROUP)
			for layer: String in ["hull", "team"]:
				rig.add_child(_layer_sprite(layer, FLAG_ART % [flag, layer]))
			rig.position = Vector2(centre, arrow_px / 2.0)
			row.add_child(rig)
			centre += TILE_PX + FLAG_GAP_PX


func _next_page() -> void:
	_show_page((_page + 1) % PAGES.size())


func _show_page(index: int) -> void:
	_page = index
	for node: CanvasItem in _unit_page:
		node.visible = index == 0
	_buildings_page.visible = index == 1
	_ground_page.visible = index == 2
	_icons_page.visible = index == 3
	_iso_page.visible = index == 4
	_terrain_page.visible = index == 5
	_page_button.text = PAGES[index]


func _go_back() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)
