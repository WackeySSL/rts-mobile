extends RefCounted
## Fixtures of the fog suites (plan P47). Not a test suite. The suites run on the controls_test
## scenario: a 48 x 48 map, 30 blue light tanks (ids 1-30, rows 0-29) in a block from tile (8, 18)
## to (13, 23), and 10 red ones (ids 31-40, rows 30-39), the nearest at tile (34, 10). Light tanks
## see 7 tiles and drive 120 milli-tiles a tick, so at tick 0 no red tank is in blue sight (and no
## blue one in red sight), and a blue tank needs about a hundred ticks to bring red tank 31 in view.

const CONTROLS: String = "res://data/scenarios/controls_test.tres"
const COLS: int = 48
const ROWS: int = 48
const EXPLORED: int = 140
const BLUE_TANK_6: PackedInt32Array = [6]  ## The east end of the block's first row, (16.5, 18.5).
const RED_TANK_31: int = 31  ## Row 30, at (34.5, 10.5).


## The controls_test scenario for `local_player`: a copy, so the loaded resource that other suites
## share keeps its player.
static func scenario(local_player: int = 1) -> ScenarioDef:
	var copy: ScenarioDef = (load(CONTROLS) as ScenarioDef).duplicate()
	copy.local_player = local_player
	return copy


## The alpha that `fog` gives cell `cell` for `player`: 0 visible, `shade` explored and not now,
## 255 never seen (ADR 0010 section 2). Written again here, so a wrong layer fails.
static func alpha_of(fog: FogGrid, player: int, cell: int, shade: int = EXPLORED) -> int:
	if fog.is_visible(player, cell):
		return 0
	return shade if fog.is_explored(player, cell) else 255


## The cells whose alpha in `image` is not the one `fog` gives them for `player`; empty when the
## image is the fog, the size of the map included.
static func mismatches(
	image: Image, fog: FogGrid, player: int, shade: int = EXPLORED
) -> Array[int]:
	var wrong: Array[int] = []
	if image.get_size() != Vector2i(fog.cols, fog.rows):
		wrong.append(-1)
		return wrong
	for cell: int in fog.cells:
		var pixel: Color = image.get_pixel(cell % fog.cols, cell / fog.cols)
		var black: bool = pixel.r8 == 0 and pixel.g8 == 0 and pixel.b8 == 0
		if not black or pixel.a8 != alpha_of(fog, player, cell, shade):
			wrong.append(cell)
	return wrong


## Counts of the three alphas of `image`: how many tiles are black, dimmed and clear.
static func tally(image: Image) -> Vector3i:
	var counts: Vector3i = Vector3i.ZERO
	for y: int in image.get_height():
		for x: int in image.get_width():
			var alpha: int = image.get_pixel(x, y).a8
			counts += Vector3i(int(alpha == 255), int(alpha == EXPLORED), int(alpha == 0))
	return counts


## Makes `tile` visible (count 1) or not (count 0) to `player` in the published snapshot's fog, the
## way ADR 0012 section 3 lets a SYNC test set up a view case. It leaves `explored` alone.
static func set_seen(snap: MatchSnapshot, player: int, tile: Vector2i, seen: bool) -> void:
	var fog: FogGrid = snap.fog
	fog.visible[(player - 1) * fog.cells + tile.y * fog.cols + tile.x] = 1 if seen else 0


## Clears every visible count of `player`, so the player sees nothing.
static func blind(snap: MatchSnapshot, player: int) -> void:
	var fog: FogGrid = snap.fog
	for cell: int in fog.cells:
		fog.visible[(player - 1) * fog.cells + cell] = 0


## Writes one update of `player` into the published snapshot's fog the way the sim leaves it: the
## `tiles` listed as flipped, their visible counts set to `seen`, and the version one higher. The
## snapshot's tick advances by `ticks`, so the layer sees the next tick (1) or a gap (2 or more).
static func flip(
	snap: MatchSnapshot, player: int, tiles: Array[Vector2i], seen: bool, ticks: int = 1
) -> void:
	var fog: FogGrid = snap.fog
	fog.begin_update(player)
	for tile: Vector2i in tiles:
		var cell: int = tile.y * fog.cols + tile.x
		fog.visible[(player - 1) * fog.cells + cell] = 1 if seen else 0
		if seen:
			fog.explored[(player - 1) * fog.cells + cell] = 1
		fog.dirty[(player - 1) * fog.dirty_capacity + fog.dirty_count[player - 1]] = cell
		fog.dirty_count[player - 1] += 1
	fog.version[player - 1] += 1
	snap.tick += ticks
