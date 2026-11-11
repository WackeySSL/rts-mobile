extends GdUnitTestSuite
## The sorted world is one draw call (ADR 0023 section 2): everything a dressed unit rig holds that
## draws at the sorted world's z is a sprite of the match's one atlas page, with no material and
## the default filter. A node with its own texture or an untextured `_draw` goes to its own z, as
## the Ring (its own texture, z 3) and the cargo bar (z 30) do, or it breaks the batch once or
## twice a rig (the P84e regression found in the Phase 3 gate). The one allowed exception is the
## `Marker`, the dev fallback of a type with no art (every real type has art), which the walk skips.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const SortedTextures: GDScript = preload("res://tests/view/support/sorted_textures.gd")
const UiProfiles: GDScript = preload("res://tests/support/ui_profiles.gd")
## A squad, a tank and a tanker of each faction, with their owner (player 1 fossil, 2 renew).
const UNITS: Array[Array] = [
	["rifle_squad", 1],
	["renew_rifle", 2],
	["light_tank", 1],
	["renew_tank", 2],
	["harvester", 1],
	["renew_tanker", 2],
]
const TANKERS: int = 2

var _runner: MatchRunner
var _layer: UnitLayer


func before_test() -> void:
	UiScale.set_override(UiProfiles.by_name(&"android_6in"))
	var spawns: Array[SpawnDef] = []
	for i: int in UNITS.size():
		spawns.append(Rig.spawn(UNITS[i][1], UNITS[i][0], 4 + 3 * i, 4))
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	var camera: RtsCamera = auto_free(RtsCamera.new())
	add_child(camera)
	_layer = auto_free(UnitLayer.new())
	_layer.runner = _runner
	_layer.camera = camera
	add_child(_layer)
	_layer.set_process(false)
	_runner.run_ticks(1)
	_layer._process(0.0)
	_layer.set_selected(_runner.snapshot.unit_id)  # Every rig builds its Ring.


func after_test() -> void:
	UiScale.clear_override()


func test_everything_a_dressed_rig_draws_at_the_sorted_z_is_an_atlas_sprite() -> void:
	var page: Texture2D = _layer.world_sort.atlas.texture()
	assert_object(page).is_not_null()
	var snap: MatchSnapshot = _runner.snapshot
	assert_int(snap.unit_count()).is_equal(UNITS.size())
	var hulls: int = 0
	var rings: int = 0
	for row: int in snap.unit_count():
		var rig: Node2D = _layer.rig(row)
		assert_object(rig).is_not_null()
		for item: CanvasItem in _canvas_items(rig):
			if item is UnitLayer.Marker:
				continue  # The allowed exception, see the header.
			if item is UnitLayer.Ring:
				rings += 1
			if SortedTextures.resolved_z(item) != WorldSort.Z_SORT:
				continue
			if item.name == &"Hull":
				hulls += 1
			assert_object(item).is_instanceof(Sprite2D)
			if not item is Sprite2D:
				continue
			var sprite: Sprite2D = item as Sprite2D
			assert_object(sprite.texture).is_same(page)  # Not the ring's, not a plain rect.
			assert_object(sprite.material).is_null()
			assert_int(sprite.texture_filter).is_equal(CanvasItem.TEXTURE_FILTER_PARENT_NODE)
	assert_int(hulls).is_equal(snap.unit_count())  # Not blind: every hull was walked.
	assert_int(rings).is_equal(snap.unit_count())  # And every Ring, which leaves the sort.
	assert_int(_cargo_bars().size()).is_equal(TANKERS)


## P237 (ADR 0036 section 15): the shadows are on page 2, drawn at z 2 (the rigs') outside the sort,
## so the sorted world stays one call on page 1 and the shadows are one more call on page 2. No
## sprite that draws from page 2 resolves to the sort's z, whatever its name.
func test_every_rig_shadow_is_on_page_two_at_z_two_and_no_page_two_sprite_is_in_the_sort() -> void:
	var atlas: IsoAtlas = _layer.world_sort.atlas
	var page2: Texture2D = atlas.texture(IsoAtlas.PAGE_UNSORTED)
	assert_object(page2).is_not_null()
	assert_object(page2).is_not_same(atlas.texture())
	assert_int(WorldSort.Z_SHADOW).is_not_equal(WorldSort.Z_SORT)
	var shadows: int = 0
	for row: int in _runner.snapshot.unit_count():
		var sprite: Sprite2D = _layer.rig(row).get_node("Shadow")
		assert_object(sprite.texture).is_same(page2)
		assert_int(SortedTextures.resolved_z(sprite)).is_equal(WorldSort.Z_SHADOW)
		shadows += 1
	assert_int(shadows).is_equal(UNITS.size())
	for sprite: Sprite2D in SortedTextures.sprites(_layer.world_sort):
		assert_object(sprite.texture).is_not_same(page2)


func test_the_cargo_bar_draws_at_the_bars_z_outside_the_sort() -> void:
	var bars: Array[TankerCargo] = _cargo_bars()
	assert_int(bars.size()).is_equal(TANKERS)
	for bar: TankerCargo in bars:
		assert_int(SortedTextures.resolved_z(bar)).is_equal(WorldSort.Z_BARS)


func _cargo_bars() -> Array[TankerCargo]:
	var bars: Array[TankerCargo] = []
	for row: int in _runner.snapshot.unit_count():
		var bar: TankerCargo = (_layer.rig(row) as UnitLayer.Rig).cargo
		if bar != null:
			bars.append(bar)
	return bars


static func _canvas_items(root: Node) -> Array[CanvasItem]:
	var found: Array[CanvasItem] = []
	for child: Node in root.get_children():
		if child is CanvasItem:
			found.append(child as CanvasItem)
		found.append_array(_canvas_items(child))
	return found
