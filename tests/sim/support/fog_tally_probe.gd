extends SimProbe
## What a FOG lockstep run reached (plan P46n2): at the FOG mark it works the phase out again from
## the definition, starting from the fog as the REMOVE mark left it, and adds what it meets to
## `tally`. The suites assert the counts, so that a run cannot pass by never meeting an overlap, a
## clipped disc or a full block. It only reads: the fog is the phase's own. A probe of the game
## never reads the World (ADR 0007 section 4); this one is a test's, a recorded exception like
## SeparationTallyProbe and TargetingTallyProbe. Not a test suite. It is a file of its own, not an
## inner class, because an inner class with a script base would name itself at run time.
##
## The rule, written from its definition and not from FogGrid, FogUpdate or the C++: the rows of a
## player whose turn it is (`(tick - player + 1) % max(fog_period_ticks, 1) == 0`, a player in
## 1..player_count) take the cell of their position (World.cell_of); a row on another cell than its
## `fog_cell` stamps the disc of its new cell and then, if it was stamped, unstamps the old one. A
## disc is the in-map tiles whose centre is within the sight of the row's type (the pad sight 0 for
## a type with no entry), found by testing every tile of the square around it (dx * 1000)^2 + (dy *
## 1000)^2 <= sight^2, so it shares no mask table with the code under test. A stamp adds its delta
## to the visible count of every cell, marks a cell with a count above 0 as explored, and lists a
## cell that flips (a count crossing 0) once per update, at the end of the block of its player,
## until the block is full (then the player's flag is set and the cell is not marked); a stamp that
## flipped a cell grows the player's version by one. stats[FOG_CELLS] grows by the in-map cells of
## every disc stamped or unstamped. A grid whose sides do not make its cells has no fog at all.
##
## It runs on the same arrays the phase starts from (the dirty blocks and the marks of the earlier
## ticks, and what FogUpdate.begin and World.remove_dead did to them), so it needs no consistent
## state: it holds the twin to the arrays it writes (visible, explored, listed, the dirty blocks and
## counts, the flags, the versions, `fog_cell` and stats[FOG_CELLS]) after every phase
## (`last_mismatches`), and the rig fails the case on a mismatch, so a probe that works the rule out
## another way than the rule fails instead of vouching for it.

## The names of the counts (each starts at 0); see count() for what each one holds.
const NAMES: Array[StringName] = [
	&"ticks",
	&"rows",
	&"turns",
	&"stays",
	&"no_player",
	&"first_stamps",
	&"restamps",
	&"unstamps",
	&"pad_moves",
	&"high_players",
	&"off_map",
	&"covered",
	&"clipped",
	&"clip_w",
	&"clip_e",
	&"clip_n",
	&"clip_s",
	&"clip_corner",
	&"overlap_stamps",
	&"overlap_unstamps",
	&"flips_on",
	&"flips_off",
	&"explored_new",
	&"listed",
	&"relisted",
	&"overflows",
	&"full_blocks",
	&"version_flips",
	&"quiet_stamps",
	&"deaths",
	&"deaths_stamped",
	&"death_on_turn"
]
const TILE: int = World.MILLI_PER_TILE
const FOG_CELLS: int = World.Stat.FOG_CELLS

var world: World
var tally: Dictionary[StringName, int] = {}
## How many of the arrays that the phase writes differ from what the probe says the rule leaves in
## them after the last count(), and the first of them in words ("" for none).
var last_mismatches: int = 0
var first_mismatch: String = ""
## The cells the rule says the last phase's stamps cover (what it adds to stats[FOG_CELLS]).
var last_covered: int = 0
var _taken: bool = false
var _stat: int = 0
var _fog_cells: PackedInt32Array = PackedInt32Array()
var _visible: PackedInt32Array = PackedInt32Array()
var _dirty: PackedInt32Array = PackedInt32Array()
var _used: PackedInt32Array = PackedInt32Array()
var _full: PackedInt32Array = PackedInt32Array()
var _version: PackedInt32Array = PackedInt32Array()
var _explored: PackedByteArray = PackedByteArray()
var _listed: PackedByteArray = PackedByteArray()


func _init(for_world: World = null) -> void:
	world = for_world
	for name: StringName in NAMES:
		tally[name] = 0


func mark(phase: int) -> void:
	if phase == SimProbe.Phase.FIRE:
		dying()
	elif phase == SimProbe.Phase.REMOVE:
		before()
	elif phase == SimProbe.Phase.FOG:
		count()


## Counts the rows that this tick's removal will take (hit points of 0 or less): `deaths`; of those,
## `deaths_stamped` have a disc in the fog (their unstamp is listed on the death tick), and
## `death_on_turn` belong to a player whose turn it is, so that FogUpdate.begin has just emptied
## the list that their unstamp goes into. Taken before FogUpdate.begin and World.remove_dead.
func dying() -> void:
	var players: int = world.fog.player_count
	for row: int in world.unit_count():
		if world.hp[row] > 0:
			continue
		tally[&"deaths"] += 1
		var player: int = world.owner[row]
		if world.fog_cell[row] >= 0 and player >= 1 and player <= players:
			tally[&"deaths_stamped"] += 1
			tally[&"death_on_turn"] += int(_has_turn(player))
	_taken = false


## Takes the fog and the stat as they stand before the phase (after the removal).
func before() -> void:
	var fog: FogGrid = world.fog
	_visible = fog.visible.duplicate()
	_explored = fog.explored.duplicate()
	_listed = fog.listed.duplicate()
	_dirty = fog.dirty.duplicate()
	_used = fog.dirty_count.duplicate()
	_full = fog.dirty_full.duplicate()
	_version = fog.version.duplicate()
	_fog_cells = world.fog_cell.duplicate()
	_stat = world.stats[FOG_CELLS]
	_taken = true


## Adds one FOG phase of `world` (before() taken, the phase run) to `tally`, and holds its arrays
## against the rule's (last_mismatches, first_mismatch). ticks: phases; rows: rows in the table
## (after the removal); turns: rows of a player whose turn it is; stays: of those, rows already on
## their cell; no_player: rows of a player outside 1..player_count, which never move;
## first_stamps: moves of a row not stamped yet; restamps: moves of a stamped row; unstamps: the
## old discs they take down (one per restamp); pad_moves: moves of a type with no sight entry;
## high_players: moves of a player above 2; off_map: moves of a row whose position is off the map.
## covered: cells covered by the discs stamped and unstamped (in the map); clipped: discs cut by the
## map, in total, at the west, east, north and south side, and at a corner (cut at two sides);
## overlap_stamps: cells stamped that were visible already; overlap_unstamps: cells unstamped that
## stay visible; flips_on and flips_off: cells that turned visible and dark; explored_new: cells
## that turned explored; listed: cells added to a dirty block; relisted: flips of a cell that was
## listed already; overflows: flips that found their block full; full_blocks: blocks that became
## full in the phase; version_flips: stamps that grew a version; quiet_stamps: stamps that flipped
## no cell.
@warning_ignore("integer_division")
func count() -> void:
	tally[&"ticks"] += 1
	var fog: FogGrid = world.fog
	var rows: int = world.unit_count()
	tally[&"rows"] += rows
	last_covered = 0
	if not _taken:
		last_mismatches = 1
		first_mismatch = "the probe was not given the REMOVE mark"
		return
	_taken = false
	var players: int = fog.player_count
	var usable: bool = (
		fog.cols >= 1
		and fog.rows >= 1
		and fog.cells % fog.cols == 0
		and fog.cells / fog.cols == fog.rows
	)
	for row: int in rows:
		var player: int = world.owner[row]
		if usable and (player < 1 or player > players):
			tally[&"no_player"] += 1
	if usable:
		_move_rows(rows, players)
	last_mismatches = 0
	first_mismatch = ""
	_compare(&"visible", _visible, fog.visible)
	_compare(&"explored", _explored, fog.explored)
	_compare(&"listed", _listed, fog.listed)
	_compare(&"dirty", _dirty, fog.dirty)
	_compare(&"dirty_count", _used, fog.dirty_count)
	_compare(&"dirty_full", _full, fog.dirty_full)
	_compare(&"version", _version, fog.version)
	_compare(&"fog_cell", _fog_cells, world.fog_cell)
	_compare(&"stats[FOG_CELLS]", _stat + last_covered, world.stats[FOG_CELLS])


## The rows of the players whose turn it is, in row order, moved in the probe's copy of the fog.
func _move_rows(rows: int, players: int) -> void:
	var fog: FogGrid = world.fog
	var pad: int = world.type_sight.size()
	for row: int in rows:
		var player: int = world.owner[row]
		if player < 1 or player > players or not _has_turn(player):
			continue
		tally[&"turns"] += 1
		var cell: int = world.cell_of(world.pos_x[row], world.pos_y[row])
		var old: int = _fog_cells[row]
		if cell == old:
			tally[&"stays"] += 1
			continue
		var type: int = world.type_index[row]
		var sight: int = world.type_sight[type] if type < pad else World.TYPE_PAD_SIGHT
		tally[&"first_stamps" if old < 0 else &"restamps"] += 1
		tally[&"unstamps"] += int(old >= 0)
		tally[&"pad_moves"] += int(type >= pad)
		tally[&"high_players"] += int(player > 2)
		tally[&"off_map"] += int(
			(
				world.pos_x[row] < 0
				or world.pos_y[row] < 0
				or world.pos_x[row] >= fog.cols * TILE
				or world.pos_y[row] >= fog.rows * TILE
			)
		)
		_stamp(player, cell, sight, 1)
		if old >= 0:
			_stamp(player, old, sight, -1)
		_fog_cells[row] = cell


## Whether the player's turn is this tick: the rule's cadence, a period below 1 being 1.
func _has_turn(player: int) -> bool:
	return (world.tick - player + 1) % maxi(world.fog_period_ticks, 1) == 0


## One stamp (delta +1) or unstamp (-1) of the disc of `sight` milli at `cell`, in the probe's copy:
## every tile of the square around the cell that lies in the map and within the sight.
@warning_ignore("integer_division")
func _stamp(player: int, cell: int, sight: int, delta: int) -> void:
	var fog: FogGrid = world.fog
	var cols: int = fog.cols
	var block: int = player - 1
	var base: int = block * fog.cells
	var list_at: int = block * fog.dirty_capacity
	var centre_x: int = cell % cols
	var centre_y: int = cell / cols
	var radius: int = sight / TILE
	var west: bool = centre_x - radius < 0
	var east: bool = centre_x + radius > cols - 1
	var north: bool = centre_y - radius < 0
	var south: bool = centre_y + radius > fog.rows - 1
	_count_clip(west, east, north, south)
	var flipped: bool = false
	var overflowed: bool = false
	var covered: int = 0
	for y: int in range(maxi(centre_y - radius, 0), mini(centre_y + radius, fog.rows - 1) + 1):
		for x: int in range(maxi(centre_x - radius, 0), mini(centre_x + radius, cols - 1) + 1):
			var dx: int = (x - centre_x) * TILE
			var dy: int = (y - centre_y) * TILE
			if dx * dx + dy * dy > sight * sight:
				continue
			covered += 1
			var at: int = y * cols + x
			var before: int = _visible[base + at]
			var after: int = before + delta
			_visible[base + at] = after
			if after > 0:
				tally[&"explored_new"] += int(_explored[base + at] == 0)
				_explored[base + at] = 1
			if (before > 0) == (after > 0):
				tally[&"overlap_stamps"] += int(delta > 0 and before > 0)
				tally[&"overlap_unstamps"] += int(delta < 0 and after > 0)
				continue
			flipped = true
			tally[&"flips_on" if after > 0 else &"flips_off"] += 1
			if _listed[base + at] != 0:
				tally[&"relisted"] += 1
			elif _used[block] < fog.dirty_capacity:
				_dirty[list_at + _used[block]] = at
				_used[block] += 1
				_listed[base + at] = 1
				tally[&"listed"] += 1
			else:
				overflowed = true
				tally[&"overflows"] += 1
	tally[&"covered"] += covered
	last_covered += covered
	if overflowed:
		tally[&"full_blocks"] += int(_full[block] == 0)
		_full[block] = 1
	if flipped:
		_version[block] += 1
		tally[&"version_flips"] += 1
	else:
		tally[&"quiet_stamps"] += 1


## The clipped counts of one disc: the sides of the map that cut it.
func _count_clip(west: bool, east: bool, north: bool, south: bool) -> void:
	if not (west or east or north or south):
		return
	tally[&"clipped"] += 1
	tally[&"clip_w"] += int(west)
	tally[&"clip_e"] += int(east)
	tally[&"clip_n"] += int(north)
	tally[&"clip_s"] += int(south)
	tally[&"clip_corner"] += int((west or east) and (north or south))


## Counts the array `name` into `last_mismatches` when it is not what the probe worked out (`want`),
## and words the first one of the phase in `first_mismatch`.
func _compare(name: String, want: Variant, have: Variant) -> void:
	if want == have:
		return
	last_mismatches += 1
	if first_mismatch != "":
		return
	if typeof(want) == TYPE_INT:
		first_mismatch = "%s is %d, the rule leaves %d" % [name, have, want]
		return
	if want.size() != have.size():
		first_mismatch = "%s has %d entries, the rule %d" % [name, have.size(), want.size()]
		return
	for at: int in want.size():
		if want[at] != have[at]:
			first_mismatch = "%s[%d] is %d, the rule leaves %d" % [name, at, have[at], want[at]]
			return
