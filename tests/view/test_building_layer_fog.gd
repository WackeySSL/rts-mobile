extends GdUnitTestSuite
## What the fog hides of the buildings (plan P115, ADR 0023 section 2, ADR 0010 section 2): an own
## building is always drawn, an enemy one only where a cell of its footprint is seen now, whole and
## with its shadow, and `reveal_enemies` shows all. The visibility is written when the local
## player's fog version moves and in no other frame. A destroyed building leaves a crater only when
## it was shown.
## On a 32 x 32 map, player 1 the local one: its Headquarters (3x3) at tile (4, 4), and player 2's
## Headquarters (3x3, cells 4-6 by 12-14) and Redoubt (1x1, cell (10, 12)). The runner is not in the
## tree: only the calls here move time. Fog cases write the published snapshot's fog (ADR 0012
## section 3) the way the sim leaves an update: the visible counts and the version one higher.

const Rig: GDScript = preload("res://tests/view/support/building_rig.gd")
const EAST_ID: int = 2  ## The enemy Headquarters.
const REDOUBT_ID: int = 3
## A cell of each corner of the enemy Headquarters' footprint, and the cells just outside it.
const CORNERS: Array[Vector2i] = [
	Vector2i(4, 12), Vector2i(6, 12), Vector2i(4, 14), Vector2i(6, 14)
]
const OUTSIDE: Array[Vector2i] = [
	Vector2i(3, 12), Vector2i(7, 12), Vector2i(4, 11), Vector2i(6, 15), Vector2i(7, 15)
]

var _runner: MatchRunner
var _layer: BuildingLayer


func before_test() -> void:
	var spawns: Array[SpawnDef] = [
		Rig.spawn(1, "headquarters", 4, 4),
		Rig.spawn(2, "renew_hq", 4, 12),
		Rig.spawn(2, "renew_defence", 10, 12),
	]
	_runner = auto_free(Rig.runner(Rig.scenario(spawns)))
	_layer = auto_free(BuildingLayer.new())
	_layer.runner = _runner
	add_child(_layer)
	_layer.set_process(false)
	_layer._process(0.0)


func after_test() -> void:
	CommandQueue.clear()


func test_an_own_building_is_drawn_whatever_the_fog_says() -> void:
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	assert_bool(_layer.building(1).visible).is_true()
	assert_bool(Rig.shadow(_layer, 1).visible).is_true()
	assert_bool(_layer.is_shown(0)).is_true()


func test_an_enemy_building_is_drawn_when_any_cell_of_its_footprint_is_seen() -> void:
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	assert_bool(_shown(EAST_ID)).is_false()
	assert_bool(_shown(REDOUBT_ID)).is_false()
	assert_bool(_layer.is_shown(1)).is_false()
	for corner: Vector2i in CORNERS:  # One cell of the nine is enough, the centre or not.
		Rig.see(_runner.snapshot, 1, [corner])
		_layer._process(0.0)
		assert_bool(_shown(EAST_ID)).override_failure_message("seen at %s" % corner).is_true()
		assert_bool(_layer.is_shown(1)).is_true()
		assert_bool(_shown(REDOUBT_ID)).is_false()  # Another building, another footprint.
	Rig.see(_runner.snapshot, 1, [Vector2i(5, 13)])  # The centre cell alone.
	_layer._process(0.0)
	assert_bool(_shown(EAST_ID)).is_true()
	for outside: Vector2i in OUTSIDE:  # The cells that touch the footprint are not the footprint.
		Rig.see(_runner.snapshot, 1, [outside])
		_layer._process(0.0)
		assert_bool(_shown(EAST_ID)).override_failure_message("seen at %s" % outside).is_false()
		assert_bool(_layer.is_shown(1)).is_false()
	Rig.see(_runner.snapshot, 1, [Vector2i(10, 12)])  # The 1x1 is its single cell.
	_layer._process(0.0)
	assert_bool(_shown(REDOUBT_ID)).is_true()
	assert_bool(_shown(EAST_ID)).is_false()


func test_a_shown_enemy_building_is_whole_and_its_shadow_goes_with_it() -> void:
	var node: Node2D = _layer.building(EAST_ID)
	var shadow: Sprite2D = Rig.shadow(_layer, EAST_ID)
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	assert_bool(node.visible).is_false()
	assert_bool(shadow.visible).is_false()
	assert_that(node.position).is_equal(IsoProjection.ground_to_px(5500, 13500))  # It keeps its place.
	# Seen at one cell: the whole sprite, in white, with its head and its shadow, and no dim of its
	# own (the fog on the ground, z 4, and the ghosts do the dimming).
	Rig.see(_runner.snapshot, 1, [Vector2i(6, 14)])
	_layer._process(0.0)
	assert_bool(node.visible).is_true()
	assert_bool(shadow.visible).is_true()
	assert_that(shadow.modulate).is_equal(Color.WHITE)
	for sprite: Node in node.find_children("*", "Sprite2D", true, false):
		assert_that((sprite as Sprite2D).modulate).is_equal(Color.WHITE)
		assert_that((sprite as Sprite2D).self_modulate).is_equal(Color.WHITE)
	assert_that(node.modulate).is_equal(Color.WHITE)


func test_reveal_enemies_shows_every_enemy_building() -> void:
	Rig.see(_runner.snapshot, 1, [])
	_layer.reveal_enemies = true
	_layer._process(0.0)
	assert_bool(_layer.is_shown(1)).is_true()
	assert_bool(_layer.is_shown(2)).is_true()
	Rig.see(_runner.snapshot, 1, [])  # The next fog update draws them.
	_layer._process(0.0)
	assert_bool(_shown(EAST_ID)).is_true()
	assert_bool(_shown(REDOUBT_ID)).is_true()


func test_a_fog_the_snapshot_does_not_cover_hides_nothing() -> void:
	_runner.snapshot.fog = FogGrid.new()  # No cells: no fog for anybody.
	assert_bool(_layer.is_shown(1)).is_true()
	assert_bool(BuildingLayer.is_seen(_runner.snapshot, 1, 1)).is_true()


func test_visibility_is_written_when_the_fog_version_moves_and_in_no_other_frame() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [])
	_layer._process(0.0)
	assert_bool(_shown(EAST_ID)).is_false()
	var redraws: int = _layer.redraw_count()
	# The counts change without a version: no flip was announced, and the layer does not look.
	snap.fog.visible[12 * snap.fog.cols + 4] = 1
	for _frame: int in 30:
		snap.tick += 1
		_layer._process(1.0 / 60.0)
	assert_bool(_shown(EAST_ID)).is_false()
	snap.fog.version[0] += 1  # The sim announces it.
	_layer._process(0.0)
	assert_bool(_shown(EAST_ID)).is_true()
	assert_int(_layer.redraw_count()).is_equal(redraws)  # Nothing was made anew for it.
	Rig.see(snap, 1, [])
	_layer._process(0.0)
	assert_bool(_shown(EAST_ID)).is_false()
	assert_int(_layer.redraw_count()).is_equal(redraws)


func test_the_other_players_fog_does_not_show_a_building() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	Rig.see(snap, 1, [])
	Rig.see(snap, 2, CORNERS)  # Player 2 sees its own footprint: that is not player 1's sight.
	_layer._process(0.0)
	assert_bool(_shown(EAST_ID)).is_false()


func test_a_building_destroyed_in_sight_leaves_a_crater_and_one_destroyed_unseen_does_not() -> void:
	_layer.decals.crater_texture = ImageTexture.create_from_image(
		Image.create(8, 4, false, Image.FORMAT_RGBA8)
	)
	# The Redoubt (row 2) is in sight and falls: its 1x1 footprint's crater stays where it stood.
	Rig.see(_runner.snapshot, 1, [Vector2i(10, 12)])
	_layer._process(0.0)
	assert_bool(_shown(REDOUBT_ID)).is_true()
	_runner.world.hp[2] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_int(_layer.building_count()).is_equal(2)
	assert_int(_layer.decals.crater_count()).is_equal(1)
	var mark: Sprite2D = _layer.decals.find_child("Crater", true, false)
	assert_that(mark.position).is_equal(IsoProjection.ground_to_px(10500, 12500))
	assert_vector(mark.scale).is_equal_approx(Vector2.ONE * (500.0 / 1500.0), Vector2(0.001, 0.001))
	# The enemy Headquarters (row 1) is out of sight when it falls: nobody saw it, so no crater.
	Rig.see(_runner.snapshot, 1, [])
	_layer._process(0.0)
	assert_bool(_shown(EAST_ID)).is_false()
	_runner.world.hp[1] = 0
	_runner.run_ticks(1)
	_layer._process(0.0)
	assert_int(_layer.building_count()).is_equal(1)
	assert_int(_layer.decals.crater_count()).is_equal(1)


## Whether building `id` is drawn: its node and its shadow both.
func _shown(id: int) -> bool:
	var node: Node2D = _layer.building(id)
	var shadow: Sprite2D = Rig.shadow(_layer, id)
	assert_bool(node.visible == shadow.visible).is_true()
	return node.visible
