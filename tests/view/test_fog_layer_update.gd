extends GdUnitTestSuite
## What an update of FogLayer does to the texture, and which span of the work it times (plan P47,
## fix round 2; the other FogLayer cases are in test_fog_layer.gd and test_fog_layer_player2.gd,
## which gdlint's limit of 20 public methods per file keeps full).
## `ImageTexture.update()` reads back stale headless, but it emits `changed` on the texture, so the
## cases count that signal: a patch that never reached the texture would freeze the fog on the
## phone (no dimmed trail, nothing covered again) with every pixel check of `image()` still green.
## The timed span is what the perf card's fog update reads (`last_update_usec()`, gate 0.4 ms): a
## clock that records what the layer has done at each read shows that the first read comes before
## the paint and the second after the upload.
## A layer whose runner has no snapshot yet draws nothing and takes the first one it finds (round
## 3): the P50b perf arena builds its layers, whose `_ready` and first frame come before the
## scene script starts the match. A layer with no runner at all draws nothing either.
## Exact cases write one update into the published snapshot's fog, as ADR 0012 section 3 lets a
## SYNC test do, and emit `ticked`. The runner is not in the tree.

const Rig: GDScript = preload("res://tests/view/support/fog_rig.gd")
const TILE: Vector2i = Vector2i(30, 30)  ## A tile that nobody sees at tick 0 of controls_test.

var _runner: MatchRunner
var _fog: FogLayer


func before_test() -> void:
	_runner = auto_free(MatchRunner.new())
	_runner.scenario = Rig.scenario(1)
	_runner.start()
	_fog = auto_free(FogLayer.new())
	_fog.runner = _runner
	add_child(_fog)
	_fog.set_process(false)  # Frames come only from `_fog._process()`.


func test_a_patch_or_a_rebuild_updates_the_texture_once_and_an_idle_frame_not() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var texture: Texture2D = _fog.texture
	var changed: Array[int] = [0]
	texture.changed.connect(func() -> void: changed[0] += 1)
	_fog._process(0.0)  # Nothing new since the first image.
	assert_int(changed[0]).is_equal(0)
	Rig.flip(snap, 1, [TILE] as Array[Vector2i], true)
	_runner.ticked.emit(snap.tick)  # A patch.
	assert_int(changed[0]).is_equal(1)
	Rig.flip(snap, 1, [TILE] as Array[Vector2i], false)
	_runner.ticked.emit(snap.tick)
	assert_int(changed[0]).is_equal(2)
	_fog._process(0.0)  # The frame after a tick looks again and finds the version it has.
	assert_int(changed[0]).is_equal(2)
	Rig.flip(snap, 1, [TILE] as Array[Vector2i], true, 2)
	_runner.ticked.emit(snap.tick)  # A gap in the ticks: a rebuild of the same size.
	assert_int(_fog.rebuild_count()).is_equal(2)
	assert_int(changed[0]).is_equal(3)
	_fog.explored_alpha = 90  # Another alpha: a rebuild again.
	_fog._process(0.0)
	assert_int(_fog.rebuild_count()).is_equal(3)
	assert_int(changed[0]).is_equal(4)
	assert_object(_fog.texture).is_same(texture)  # All of them on the texture it had.
	assert_int(_fog.upload_count()).is_equal(5)  # The first image and the four above.


func test_a_patch_is_timed_from_before_its_paint_to_after_its_upload() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var uploads: int = _fog.upload_count()
	var reads: Array[Vector3i] = _record_reads()
	Rig.flip(snap, 1, [TILE] as Array[Vector2i], true)
	_runner.ticked.emit(snap.tick)
	assert_int(_fog.upload_count()).is_equal(uploads + 1)
	assert_int(_fog.rebuild_count()).is_equal(1)  # A patch.
	# At the first read the tile is as it was in the working array and in the image; at the
	# second, after the paint and the upload, in both.
	assert_array(reads).is_equal([Vector3i(255, 255, uploads), Vector3i(0, 0, uploads + 1)])
	assert_int(_fog.last_update_usec()).is_equal(10)  # The clock steps 10 a read.


func test_a_rebuild_is_timed_from_before_its_paint_to_after_its_upload() -> void:
	var snap: MatchSnapshot = _runner.snapshot
	var uploads: int = _fog.upload_count()
	var reads: Array[Vector3i] = _record_reads()
	Rig.flip(snap, 1, [TILE] as Array[Vector2i], true, 2)  # A gap in the ticks.
	_runner.ticked.emit(snap.tick)
	assert_int(_fog.rebuild_count()).is_equal(2)
	assert_array(reads).is_equal([Vector3i(255, 255, uploads), Vector3i(0, 0, uploads + 1)])
	assert_int(_fog.last_update_usec()).is_equal(10)


## Replaces the layer's clock with one that steps 10 microseconds a read and records, at each read,
## the alpha byte of TILE in the working array, its alpha in the image the layer holds, and the
## uploads so far. The array is the layer's own (`_bytes`): the only place the paint shows before
## the upload.
func _record_reads() -> Array[Vector3i]:
	var reads: Array[Vector3i] = []
	var at: int = (TILE.y * Rig.COLS + TILE.x) * FogLayer.BYTES_PER_TEXEL + FogLayer.ALPHA_BYTE
	_fog.usec_clock = func() -> int:
		var pixel: Color = _fog.image().get_pixel(TILE.x, TILE.y)
		reads.append(Vector3i(_fog._bytes[at], pixel.a8, _fog.upload_count()))
		return reads.size() * 10
	return reads


func test_a_layer_whose_runner_has_no_snapshot_yet_draws_nothing_until_it_has_one() -> void:
	var idle: MatchRunner = auto_free(MatchRunner.new())  # Not started: no snapshot.
	var fog: FogLayer = auto_free(FogLayer.new())
	fog.runner = idle
	add_child(fog)  # `_ready` looks once.
	fog.set_process(false)
	assert_object(idle.snapshot).is_null()
	fog._process(0.0)
	assert_object(fog.texture).is_null()
	assert_int(fog.upload_count()).is_equal(0)
	assert_int(fog.rebuild_count()).is_equal(0)
	idle.scenario = Rig.scenario(1)
	idle.start()  # Publishes tick 0 with no `ticked`.
	fog._process(0.0)
	assert_int(fog.rebuild_count()).is_equal(1)
	assert_int(fog.upload_count()).is_equal(1)
	assert_array(Rig.mismatches(fog.image(), idle.snapshot.fog, 1)).is_empty()


func test_a_layer_with_no_runner_draws_nothing() -> void:
	var bare: FogLayer = auto_free(FogLayer.new())
	add_child(bare)  # `_ready` has no runner to connect to or look at.
	bare.set_process(false)
	bare._process(0.0)
	assert_object(bare.texture).is_null()
	assert_int(bare.upload_count()).is_equal(0)
	assert_int(bare.rebuild_count()).is_equal(0)
