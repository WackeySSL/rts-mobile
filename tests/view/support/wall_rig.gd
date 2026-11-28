extends RefCounted
## Fixtures of the wall suites (plan P656d2). Not a test suite. The wall art is P656d4's: until it
## merges the kit has no wall piece, so the suites make PLACEHOLDER pieces here, in memory, one flat
## colour per piece key. They are never written to `assets/` and never shipped.

const COLS: int = 8
const ROWS: int = 6
## A 8 x 6 map; '#' is rock. Row 1 and 2 hold a 2 x 2 block, row 4 a lone cell and a map-edge cell.
const MAP: Array[String] = [
	"........",
	".##.....",
	".##.....",
	"........",
	"#...#...",
	"........",
]


## One 128 x 136 placeholder image per key of `WallKit.all_keys`, filled with a colour of its key.
static func pieces() -> Dictionary[StringName, Image]:
	var found: Dictionary[StringName, Image] = {}
	for key: StringName in WallKit.all_keys():
		var image: Image = Image.create(
			TerrainKitDef.WALL_CANVAS.x, TerrainKitDef.WALL_CANVAS.y, false, Image.FORMAT_RGBA8
		)
		var h: int = hash(String(key))
		image.fill(Color8(40 + h % 200, 40 + (h >> 8) % 200, 40 + (h >> 16) % 200, 255))
		found[key] = image
	return found


## A snapshot of `MAP` with a fog for one player who sees every cell (`seen`) or none; rock is
## terrain 1.
static func snapshot(seen: bool, serial: int = 1) -> MatchSnapshot:
	var snap: MatchSnapshot = MatchSnapshot.new()
	snap.match_serial = serial
	snap.map_cols = COLS
	snap.map_rows = ROWS
	snap.terrain_ids = [&"grass", &"rock"]
	snap.terrain.resize(COLS * ROWS)
	for row: int in ROWS:
		for col: int in COLS:
			snap.terrain[row * COLS + col] = 1 if MAP[row][col] == "#" else 0
	snap.fog.configure(COLS, ROWS, 1)
	if seen:
		for cell: int in COLS * ROWS:
			snap.fog.visible[cell] = 1
			snap.fog.explored[cell] = 1
	return snap
