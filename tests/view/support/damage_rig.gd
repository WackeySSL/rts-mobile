extends RefCounted
## Fixtures of the building damage suites (plan P159). Not a test suite. No real sheet has damage
## parts yet, so the suites craft one for the Barracks (art id `barracks`, 2x2): a body of
## `BODY_PX` x `BODY_PX` art px, `dmg1` and `dmg2` patches that reach `OVERLAP_PX` rows below their
## cuts, a shadow, and on request a four-frame `anim` part and a sixteen-direction `head`. The
## sorted world is built by hand around that sheet (no bake from the index), so the layers under
## test dress their sprites from it.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const KEY: PackedStringArray = ["#FF9446", "#E8681F", "#B04B12"]
const TRIAD: PackedStringArray = ["#62D6EE", "#1FA6C8", "#137C99"]
const BODY_PX: int = 100
const CUTS: Array[int] = [60, 70]
const OVERLAP_PX: int = 4
const ART_ID: StringName = &"barracks"
const UNIT: String = "barracks"
const ANIM_FRAMES: int = 4


## The crafted sheet. `extras` may hold `anim`, `head` (true), `cuts` (PackedInt32Array), `sizes`
## (part -> Vector2i).
static func sheet(extras: Dictionary = {}) -> IsoSheetDef:
	var made: IsoSheetDef = IsoSheetDef.new()
	made.art_id = ART_ID
	made.faction = &"fossil"
	made.category = &"bld"
	made.footprint = 2
	var names: Array[StringName] = [&"hull", &"dmg1", &"dmg2"]
	var sizes: Dictionary[StringName, Vector2i] = {
		&"hull": Vector2i(BODY_PX, BODY_PX),
		&"dmg1": Vector2i(BODY_PX, CUTS[0] + OVERLAP_PX),
		&"dmg2": Vector2i(BODY_PX, CUTS[1] + OVERLAP_PX),
		&"anim": Vector2i(20, 20),
		&"head": Vector2i(20, 20),
		&"shadow": Vector2i(BODY_PX, BODY_PX),
	}
	var given: Dictionary = extras.get("sizes", {})
	for part: StringName in given:
		sizes[part] = given[part]
	if extras.get("anim", false):
		names.append(&"anim")
	if extras.get("head", false):
		names.append(&"head")
	names.append(&"shadow")
	for part: StringName in names:
		made.parts.append(String(part))
		made.sizes.append_array([sizes[part].x, sizes[part].y])
		made.anchors.append_array([40, 60])
		made.counts.append(16 if part == &"head" else 1)
		made.frames.append(ANIM_FRAMES if part == &"anim" else 1)
	if extras.get("head", false):
		made.mounts = PackedVector2Array([Vector2(0.0, -20.0)])
	made.anim_ms = 100
	made.cuts = extras.get("cuts", PackedInt32Array(CUTS))
	return made


## Every frame an SVG of its part's canvas size, distinct per file so no two frames share a slot.
static func reader(def: IsoSheetDef) -> Callable:
	return func(path: String) -> String:
		var size: Vector2i = Vector2i(BODY_PX, BODY_PX)
		for part: String in def.parts:
			if path.get_file().contains("_%s" % part):
				size = def.frame_size(StringName(part))
		var grey: int = 16 + (path.hash() % 200)
		return (
			'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % [size.x, size.y]
			+ '<rect width="%d" height="%d" fill="#%02X8080"/></svg>' % [size.x, size.y, grey]
		)


## A sorted world holding `def` baked at `scale` for two players, synced to the runner's match so it
## never bakes the index. Not in the tree.
static func sort(runner: MatchRunner, def: IsoSheetDef, scale: float = 1.0) -> WorldSort:
	var made: WorldSort = WorldSort.new()
	made.runner = runner
	var art: IsoPlayerArt = IsoPlayerArt.make(&"fossil", KEY, TRIAD)
	made._arts = [art, art]
	made.atlas = IsoAtlas.build([def], made._arts, scale, false, reader(def))
	made._sheets[def.art_id] = def
	made._serial = runner.snapshot.match_serial
	return made


## A paused runner with a Barracks for each of `spawns` (`[owner, x, y]`, the top-left tile).
static func runner(spawns: Array) -> MatchRunner:
	var list: Array[SpawnDef] = []
	for at: Array in spawns:
		list.append(Rig.spawn(at[0], UNIT, at[1], at[2]))
	return Rig.runner(Rig.scenario(list))


## Sets the hp of building `id` in the world to `percent` of its type's max hp (at least 1).
static func set_hp(match_runner: MatchRunner, id: int, percent: int) -> void:
	var world: World = match_runner.world
	var row: int = world.index_of(id)
	@warning_ignore("integer_division")
	world.hp[row] = maxi(world.type_max_hp[world.type_index[row]] * percent / 100, 1)


## `set_hp`, then one tick, so the published snapshot and `ticked` carry it.
static func hit(match_runner: MatchRunner, id: int, percent: int) -> void:
	set_hp(match_runner, id, percent)
	match_runner.run_ticks(1)
