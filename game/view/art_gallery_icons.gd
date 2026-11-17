extends RefCounted
## The Icons and Hud pages of the art gallery (STYLE.md, "Icons and glyphs"; plan rows P92 and
## P118g, ADR 0025, 0026 and 0037), split out of `art_gallery.gd` (plan row P308), and the shared
## row helpers they and the Ground page use. Static and view-only: `build_icons_page` and
## `build_hud_page` add a hidden full-screen page to the gallery and fill it; the gallery keeps the
## ground colours (`TERRAIN_COLORS`) and passes them in.

const TEAM_A_GROUP: StringName = &"gallery_team_a"
const TEAM_B_GROUP: StringName = &"gallery_team_b"
const PX_PER_DP: float = 1.75  ## Base px per dp on the 6-inch phone profile.
const TILE_PX: float = 64.0  ## One tile at gameplay zoom.
const BUILDING_SCALE: float = 0.5  ## The 2x art at zoom 1.
## The Icons page (STYLE.md, "Icons and glyphs"). Icons are `icons/<name>.svg`, 128 px, import scale
## 1.0, shown at their size in dp: a build tile icon 64 dp, a tab 48 dp, a HUD glyph 48 dp and a
## glyph on the map 32 dp, at the 6-inch phone's 1.75 base px per dp.
const ICON_ART: String = "res://assets/art/svg/icons/%s.svg"
const FLAG_ART: String = "res://assets/art/svg/flags/%s_%s.svg"
const TAB_ICONS: Array[String] = ["tab_structures", "tab_infantry", "tab_vehicles", "tab_flight"]
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
## The build menu's own glyphs (ADR 0024): the Build button's, and the pin, pinned and not.
const MENU_GLYPHS: Array[String] = ["glyph_menu_open", "glyph_pin", "glyph_pin_off"]
## The Hud page's rows (STYLE.md): the eighteen glyphs of ADR 0025, 0026 and 0037 by
## the part of the HUD that uses them, then the existing glyphs they stand beside, at 48 dp.
const HUD_V2_ROWS: Dictionary[String, Array] = {
	"Bar":
	[
		"glyph_deselect",
		"glyph_stop",
		"glyph_all_army",
		"glyph_plus",
		"glyph_repair",
		"glyph_sell",
		"glyph_board",
		"glyph_unload",
		"glyph_home",
		"glyph_mine",
		"glyph_hold",
	],
	"Pause":
	[
		"glyph_menu",
		"glyph_resume",
		"glyph_restart",
		"glyph_surrender",
		"glyph_exit",
		"glyph_vibration",
	],
	"Panels": ["glyph_collapse", "glyph_chevron", "glyph_alert", "glyph_construct"],
	"Beside":
	[
		"glyph_menu_open",
		"glyph_pin",
		"glyph_pin_off",
		"glyph_check",
		"glyph_cross",
		"glyph_low_power",
		"glyph_credits",
		"glyph_power",
	],
}
const HUD_V2_NEW_ROWS: Array[String] = ["Bar", "Pause", "Panels"]
const MAP_GLYPHS: Array[String] = [
	"glyph_reason_outside",
	"glyph_reason_ground",
	"glyph_reason_occupied",
	"glyph_reason_unexplored",
	"glyph_reason_too_far",
	"glyph_reason_cap",
	"glyph_offline",
	"glyph_low_power_map",
	"glyph_repair_map",
	"glyph_unload_mark",
	"glyph_construct",
]
const ARROW_GLYPH: String = "glyph_under_attack"  ## At least 48 dp on screen (ADR 0019 section 5).
const RALLY_FLAGS: Array[String] = ["rally_infantry", "rally_vehicles"]
const ITEM_ICON_DP: float = 64.0
const TAB_ICON_DP: float = 48.0
const HUD_GLYPH_DP: float = 48.0
const MAP_GLYPH_DP: float = 32.0
## The map glyphs fill two lines of this many, so that a line fits a half of the page at 1280.
const MAP_GLYPH_COLUMNS: int = 6
## Grass's first line of six (386 px) must clear the page button: it stands this far left of centre.
const MAP_GLYPH_GRASS_SHIFT_PX: float = -48.0
## The Hud page's two smaller sizes, in dp: a glyph in a 48 dp button's corner and the smallest.
const HUD_SMALL_DP: Array[float] = [32.0, 24.0]
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
	"tab_flight": Color("9AA5B1"),
	"glyph_credits": Color("F2B705"),
	"glyph_power": Color("30A46C"),
	"glyph_low_power": Color("F5A524"),
	"glyph_lock": Color("9AA5B1"),
	"glyph_pin_off": Color("9AA5B1"),
	"glyph_alert": Color("9AA5B1"),
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
	"glyph_low_power_map": Color("FF8A1F"),
	"glyph_repair_map": Color("30A46C"),
	"glyph_unload_mark": Color("F5A524"),
	"glyph_under_attack": Color("E5484D"),
}
## Rows of the Icons page, in base px from the top of their half: the HUD panel (left) holds the
## tabs, the item tiles, the HUD glyphs, and on the last line the result emblems and the build
## menu's glyphs side by side; the grass and sand strips (right) each hold the map glyphs, then the
## arrow and the rally flags. Grass's glyphs start beside the page button (24 to 144 px from the
## top and from the right edge), the sand's at the top of its half. The map glyphs fill two lines
## of six and the right half is full: a 13th map glyph needs a third line or a split of the page.
const HUD_ROW_TOPS: Array[float] = [12.0, 152.0, 520.0, 612.0]
const MAP_ROW_TOPS: Dictionary[String, Array] = {"Grass": [128.0, 262.0], "Sand": [24.0, 160.0]}
const FLAG_GAP_PX: float = 24.0
## The Hud page, in base px from the top of the page: the four 48 dp rows with a name under each
## glyph (the last two share one line, their centres `HUD_ROW_CENTRES` from the page's middle, the
## two above are no wider than the 992 px between the corner buttons at 1280 wide), the two small
## rows (one for each of `HUD_SMALL_DP`) and the strip of the site badges on a building.
const HUD_PAGE_ROW_TOPS: Array[float] = [16.0, 134.0, 252.0, 252.0]
const HUD_ROW_CENTRES: Array[float] = [0.0, 0.0, -395.0, 207.0]
const HUD_SMALL_TOPS: Array[float] = [378.0, 450.0]
const HUD_SITES_TOP: float = 510.0
const HUD_CAPTION_PX: int = 16
const HUD_CAPTION_HEIGHT_PX: float = 23.0
const HUD_CAPTION_COLOR: Color = Color("9AA5B1")
## The strip: each faction's own 3x3 vehicle factory at zoom 1 on a ground, with the badges that are
## drawn over a building on the map side by side over its body (`HUD_SITE_BADGES`): the
## construction mast of ADR 0026 and the offline glyph, both at 32 dp and both on their seats.
const HUD_SITE_SIZE: Vector2 = Vector2(208.0, 196.0)
const HUD_SITE_MARGIN_PX: float = 12.0
const HUD_SITES: Array[Dictionary] = [
	{
		"name": "SiteFossil",
		"faction": &"fossil",
		"art": &"vehicle_factory",
		"triad": 0,
		"ground": &"grass_b"
	},
	{
		"name": "SiteRenew",
		"faction": &"renew",
		"art": &"renew_factory",
		"triad": 1,
		"ground": &"sand"
	},
]
const HUD_SITE_BADGES: Array[String] = ["glyph_construct", "glyph_offline"]
const HUD_BADGE_GAP_PX: float = 6.0


## The Icons page. Left, a HUD panel (the dark backdrop of the sidebar) with the three tab icons at
## 48 dp, the eleven item icons on their tiles at 64 dp, the HUD glyphs at 48 dp, and the result
## emblems and the build menu's glyphs at 48 dp side by side on the last line. Right, the glyphs
## that sit on the map at 32 dp, the under-attack arrow at 48 dp and the rally flags of both teams,
## on grass (top) and sand (bottom).
static func build_icons_page(host: Control, terrain: Dictionary[StringName, Color]) -> Control:
	var page: Control = page_root(host, "IconsPage")
	var hud: ColorRect = _icons_half(page, "Hud", HUD_BACKDROP, Rect2(0.0, 0.0, 0.5, 1.0))
	# Four tabs: the row stands a half step right of the centre, clear of the page button.
	var tab_row: Control = pixel_row(
		hud, "Tabs", HUD_ROW_TOPS[0], (TAB_ICON_DP * PX_PER_DP + ICON_GAP_PX) / 2.0
	)
	_icon_grid(tab_row, TAB_ICONS, TAB_ICON_DP, TAB_ICONS.size())
	_icon_grid(
		pixel_row(hud, "Items", HUD_ROW_TOPS[1]), ITEM_ICONS, ITEM_ICON_DP, ITEM_COLUMNS, true
	)
	_icon_grid(
		pixel_row(hud, "Glyphs", HUD_ROW_TOPS[2]), HUD_GLYPHS, HUD_GLYPH_DP, HUD_GLYPHS.size()
	)
	# The last line holds two groups of three, a gap apart and together centred on the panel.
	var shift: float = EMBLEMS.size() * (HUD_GLYPH_DP * PX_PER_DP + ICON_GAP_PX) / 2.0
	var last: float = HUD_ROW_TOPS[3]
	_icon_grid(pixel_row(hud, "Emblems", last, -shift), EMBLEMS, HUD_GLYPH_DP, EMBLEMS.size())
	_icon_grid(
		pixel_row(hud, "MenuGlyphs", last, shift), MENU_GLYPHS, HUD_GLYPH_DP, MENU_GLYPHS.size()
	)
	for ground_name: String in ["Grass", "Sand"]:
		var is_grass: bool = ground_name == "Grass"
		var colour: Color = terrain[&"grass_b"] if is_grass else terrain[&"sand"]
		var anchors: Rect2 = Rect2(0.5, 0.0 if is_grass else 0.5, 0.5, 0.5)
		var ground: ColorRect = _icons_half(page, ground_name, colour, anchors)
		var tops: Array = MAP_ROW_TOPS[ground_name]
		# Grass's first line is wider than the gap to the page button: it stands left of the centre.
		var glyphs: Control = pixel_row(
			ground, "MapGlyphs", tops[0], MAP_GLYPH_GRASS_SHIFT_PX if is_grass else 0.0
		)
		_icon_grid(glyphs, MAP_GLYPHS, MAP_GLYPH_DP, MAP_GLYPH_COLUMNS)
		_add_flag_row(pixel_row(ground, "Flags", tops[1]))
	return page


## A coloured rectangle of the Icons page, placed by its anchors (a fraction of the page).
static func _icons_half(
	page: Control, node_name: String, colour: Color, anchors: Rect2
) -> ColorRect:
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


## The Hud page (plan row P118g): the HUD panel's backdrop over the whole page, the rows of
## `HUD_V2_ROWS` at 48 dp with the name of each glyph under it, the eighteen new glyphs again at
## each of `HUD_SMALL_DP`, and each faction's vehicle factory with the construction badge and the
## offline glyph over it, where a site's badge is seen. Every row is centred, so the page fits at
## any base width from 1280.
static func build_hud_page(host: Control, terrain: Dictionary[StringName, Color]) -> Control:
	var page: Control = page_root(host, "HudPage")
	var panel: ColorRect = _icons_half(page, "Hud", HUD_BACKDROP, Rect2(0.0, 0.0, 1.0, 1.0))
	var fresh: Array[String] = []
	for index: int in HUD_V2_ROWS.size():
		var row_name: String = HUD_V2_ROWS.keys()[index]
		var icons: Array[String] = []
		icons.assign(HUD_V2_ROWS[row_name])
		if HUD_V2_NEW_ROWS.has(row_name):
			fresh.append_array(icons)
		var row: Control = pixel_row(
			panel, row_name, HUD_PAGE_ROW_TOPS[index], HUD_ROW_CENTRES[index]
		)
		_icon_grid(row, icons, HUD_GLYPH_DP, icons.size(), false, true)
	for index: int in HUD_SMALL_DP.size():
		var dp: float = HUD_SMALL_DP[index]
		var row: Control = pixel_row(panel, "Small%d" % int(dp), HUD_SMALL_TOPS[index])
		_icon_grid(row, fresh, dp, fresh.size())
	_add_site_row(terrain, pixel_row(panel, "Sites", HUD_SITES_TOP))
	return page


## Each faction's 3x3 vehicle factory at zoom 1 on grass or sand with the construction badge and the
## offline glyph over its body, both at the size of a glyph on the map, and a line that says so.
static func _add_site_row(terrain: Dictionary[StringName, Color], row: Control) -> void:
	var size_px: float = MAP_GLYPH_DP * PX_PER_DP
	var badges: int = HUD_SITE_BADGES.size()
	var pair: float = badges * size_px + (badges - 1) * HUD_BADGE_GAP_PX
	var at: float = 0.0
	for site: Dictionary in HUD_SITES:
		var swatch: ColorRect = ColorRect.new()
		swatch.name = site["name"]
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatch.color = terrain[site["ground"]]
		swatch.position = Vector2(at, 0.0)
		swatch.size = HUD_SITE_SIZE
		var building: TextureRect = TextureRect.new()
		building.name = "Building"
		building.mouse_filter = Control.MOUSE_FILTER_IGNORE
		building.texture = building_texture(site["faction"], site["art"], site["triad"])
		building.size = building.texture.get_size()
		building.position = Vector2((HUD_SITE_SIZE.x - building.size.x) / 2.0, HUD_SITE_MARGIN_PX)
		swatch.add_child(building)
		var badge_at: Vector2 = Vector2(
			(HUD_SITE_SIZE.x - pair) / 2.0, building.position.y + building.size.y * 0.42
		)
		for badge: String in HUD_SITE_BADGES:
			swatch.add_child(icon_rect(badge, size_px, badge_at))
			badge_at.x += size_px + HUD_BADGE_GAP_PX
		row.add_child(swatch)
		at += HUD_SITE_SIZE.x + ICON_GAP_PX
	var note: Label = Label.new()
	note.name = "LabelSites"
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.text = "badges on a building"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	note.add_theme_font_size_override(&"font_size", HUD_CAPTION_PX)
	note.add_theme_color_override(&"font_color", HUD_CAPTION_COLOR)
	note.size = Vector2(HUD_SITE_SIZE.x, HUD_CAPTION_HEIGHT_PX)
	note.position = Vector2(-note.size.x - ICON_GAP_PX, (HUD_SITE_SIZE.y - note.size.y) / 2.0)
	row.add_child(note)


## Icons of `dp` dp in lines of `columns`, each line centred on the row. An item icon sits on its
## tile, a step lighter than the panel, the way the sidebar draws it; with `captions` each glyph has
## its name under it.
static func _icon_grid(
	row: Control,
	icons: Array[String],
	dp: float,
	columns: int,
	tiles: bool = false,
	captions: bool = false
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
		row.add_child(icon_rect(icons[i], size_px, at))
		if captions:
			row.add_child(_icon_caption(icons[i], at, size_px))


## The name of a glyph, centred under it: the file's name without `glyph_`.
static func _icon_caption(icon: String, at: Vector2, size_px: float) -> Label:
	var short: String = icon.trim_prefix("glyph_")
	var label: Label = Label.new()
	label.name = "Label" + short.to_pascal_case()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = short.replace("_", " ")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", HUD_CAPTION_PX)
	label.add_theme_color_override(&"font_color", HUD_CAPTION_COLOR)
	label.size = Vector2(size_px + ICON_GAP_PX, HUD_CAPTION_HEIGHT_PX)
	label.position = at + Vector2((size_px - label.size.x) / 2.0, size_px + 2.0)
	return label


## An icon file as a square `TextureRect` of `size_px` at `at`, tinted as the HUD tints it.
static func icon_rect(icon: String, size_px: float, at: Vector2) -> TextureRect:
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
static func _add_flag_row(row: Control) -> void:
	var arrow_px: float = HUD_GLYPH_DP * PX_PER_DP
	var flags: int = RALLY_FLAGS.size() * 2
	var total: float = arrow_px + flags * (TILE_PX + FLAG_GAP_PX)
	var left: float = -total / 2.0
	row.add_child(icon_rect(ARROW_GLYPH, arrow_px, Vector2(left, 0.0)))
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


## The hull frame of building `art_id` of `faction` in the triad of player `triad`, its key triad
## replaced as the match-start bake does it, at the scale of zoom 1.
static func building_texture(faction: StringName, art_id: StringName, triad: int) -> ImageTexture:
	var path: String = IsoSheetDef.frame_path(faction, &"bld", art_id, &"hull", -1)
	var art: IsoPlayerArt = IsoPlayerArt.make(
		faction,
		PackedStringArray(ArtPalette.KEYS[faction]),
		PackedStringArray(WorldSort.TRIADS[triad])
	)
	var image: Image = Image.new()
	image.load_svg_from_string(art.recolour(FileAccess.get_file_as_string(path)), BUILDING_SCALE)
	return ImageTexture.create_from_image(image)


## A page: an empty full-screen Control that starts hidden, over the Units page.
static func page_root(host: Control, page_name: String) -> Control:
	var page: Control = Control.new()
	page.name = page_name
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.anchor_right = 1.0
	page.anchor_bottom = 1.0
	page.visible = false
	host.add_child(page)
	return page


## An empty Control `top` base px down the middle of `ground`, `centre` base px right of the middle,
## that a row of things is added to.
static func pixel_row(
	ground: Control, row_name: String, top: float, centre: float = 0.0
) -> Control:
	var row: Control = Control.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.5
	row.anchor_right = 0.5
	row.offset_left = centre
	row.offset_right = centre
	row.offset_top = top
	row.offset_bottom = top
	ground.add_child(row)
	return row


static func _layer_sprite(layer: String, path: String) -> Sprite2D:
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = layer.capitalize()
	sprite.texture = load(path)
	return sprite
