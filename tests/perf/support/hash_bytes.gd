extends RefCounted
## The bytes that World.state_hash() feeds its digest at one checkpoint (plan P65q, ADR 0016): the
## stream is rebuilt here from the shape lists (World.hash_section_names(), HASHED_SCALARS,
## PROJECTILE_ARRAYS, MAP_ARRAYS, FogGrid.HASHED, PLAYER_ARRAYS, ORE_ARRAYS, the ghost records
## of GHOST_ARRAYS, the passenger records of PASSENGER_ARRAYS and the mines of MINE_ARRAYS and
## MINE_SEEN_ARRAYS) and not by calling the World's
## feed code, so a test can feed it to its own SHA-256 and compare the result with state_hash():
## the count is exact exactly when the two values are equal. Each block is a 16-byte header (the
## section's index and the byte count, two little-endian int64) and its bytes, in the order of the
## sections.
## A change of the hash layout that goes through those lists (P65 narrows FogGrid.HASHED) is
## followed on its own. Pure: no clock, no World writes. Not a test suite.

## The head of the watch line (plan P65q): it does not start with `PERF `, which P51 copies.
const HEAD: String = "WATCH sim hash_bytes"
## The base arena's (plan P93, ADR 0021 section 2): the same line for its checkpoints.
const BASES_HEAD: String = "WATCH bases hash_bytes"
## The block header: the tag and the byte count, two int64.
const HEADER_BYTES: int = 16


## The stream of `world` now, byte for byte what state_hash() feeds its context.
static func stream(world: World) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var names: PackedStringArray = World.hash_section_names()
	for tag: int in names.size():
		match names[tag]:
			"header":
				_append(out, tag, _header(world))
			"map":
				_append(out, tag, PackedInt64Array([_map_digest(world)]).to_byte_array())
			"projectiles":
				_append(out, tag, _live_slots(world))
				_append(out, tag, world.proj_free.slice(0, world.proj_free_top).to_byte_array())
			"fog":
				for array_name: StringName in FogGrid.HASHED:
					_append(out, tag, bytes_of(world.fog.get(array_name)))
			"players":
				for array_name: StringName in World.PLAYER_ARRAYS:
					_append(out, tag, bytes_of(world.get(array_name)))
			"ore":
				for array_name: StringName in World.ORE_ARRAYS:
					_append(out, tag, bytes_of(world.get(array_name)))
			"ghosts":
				_append(out, tag, bytes_of(world.ghost_count))
				_append(out, tag, _live_ghosts(world))
			"passengers":
				_append(out, tag, _live_passengers(world))
			"mines":
				_append(out, tag, _live_mines(world))
				_append(out, tag, bytes_of(world.mine_seen_count))
				_append(out, tag, _live_seen_mines(world))
			_:
				_append(out, tag, bytes_of(world.get(StringName(names[tag]))))
	return out


## state_hash() of a stream: SHA-256, the first 8 digest bytes as a signed int64.
static func digest(bytes: PackedByteArray) -> int:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().decode_s64(0)


## The values of the watch line from the byte count of each checkpoint (0 for none).
static func values(counts: PackedInt32Array) -> Dictionary:
	var low: int = counts[0] if not counts.is_empty() else 0
	var high: int = low
	for count: int in counts:
		low = mini(low, count)
		high = maxi(high, count)
	return {"checkpoints": counts.size(), "min_bytes": low, "max_bytes": high}


## A byte array as it is, any other Packed array little-endian.
static func bytes_of(table: Variant) -> PackedByteArray:
	if table is PackedByteArray:
		return table
	return table.to_byte_array()


## The tag, the byte count and the bytes of one block.
static func _append(out: PackedByteArray, tag: int, bytes: PackedByteArray) -> void:
	out.append_array(PackedInt64Array([tag, bytes.size()]).to_byte_array())
	out.append_array(bytes)


## STATE_FORMAT, the hashed scalars in list order, then the four words of the stream, as int64.
static func _header(world: World) -> PackedByteArray:
	var header: PackedInt64Array = PackedInt64Array([World.STATE_FORMAT])
	for scalar_name: StringName in World.HASHED_SCALARS:
		header.append(world.get(scalar_name))
	header.append_array(world.rng.state())
	return header.to_byte_array()


## The digest of the map grids, which the World caches until map_version moves: one block each.
static func _map_digest(world: World) -> int:
	var grids: PackedByteArray = PackedByteArray()
	for tag: int in World.MAP_ARRAYS.size():
		_append(grids, tag, bytes_of(world.get(World.MAP_ARRAYS[tag])))
	return digest(grids)


## Each live last-seen record (record `i` of player `p` is entry `p * ghost_cap + i`, `i` below
## ghost_count[p]): its fields in GHOST_ARRAYS order, players ascending.
static func _live_ghosts(world: World) -> PackedByteArray:
	var live: PackedInt32Array = PackedInt32Array()
	for player: int in world.ghost_count.size():
		for record: int in world.ghost_count[player]:
			for column_name: StringName in World.GHOST_ARRAYS:
				if column_name != &"ghost_count":
					var column: PackedInt32Array = world.get(column_name)
					live.append(column[player * world.ghost_cap + record])
	return live.to_byte_array()


## Each live passenger record (record `i` below pass_count): its fields in PASSENGER_ARRAYS order.
static func _live_passengers(world: World) -> PackedByteArray:
	var live: PackedInt32Array = PackedInt32Array()
	for record: int in clampi(world.pass_count, 0, world.pass_id.size()):
		for column_name: StringName in World.PASSENGER_ARRAYS:
			var column: PackedInt32Array = world.get(column_name)
			live.append(column[record])
	return live.to_byte_array()


## Each live mine (record `i` below mine_count): its fields in MINE_ARRAYS order.
static func _live_mines(world: World) -> PackedByteArray:
	var live: PackedInt32Array = PackedInt32Array()
	for record: int in clampi(world.mine_count, 0, world.mine_id.size()):
		for column_name: StringName in World.MINE_ARRAYS:
			var column: PackedInt32Array = world.get(column_name)
			live.append(column[record])
	return live.to_byte_array()


## Each live record of a found mine (entry `p * mine_known_cap + i`, `i` below mine_seen_count[p]):
## its fields in MINE_SEEN_ARRAYS order without the count, players ascending.
static func _live_seen_mines(world: World) -> PackedByteArray:
	var live: PackedInt32Array = PackedInt32Array()
	var shortest: int = world.mine_seen_id.size()
	shortest = mini(shortest, mini(world.mine_seen_owner.size(), world.mine_seen_cell.size()))
	for player: int in world.mine_seen_count.size():
		# The count is clamped to the player's block and to the shortest column, as WorldHash does.
		for record: int in mini(maxi(world.mine_seen_count[player], 0), world.mine_known_cap):
			var entry: int = player * world.mine_known_cap + record
			if entry >= shortest:
				break
			for column_name: StringName in World.MINE_SEEN_ARRAYS:
				if column_name != &"mine_seen_count":
					var column: PackedInt32Array = world.get(column_name)
					live.append(column[entry])
	return live.to_byte_array()


## Each live slot (id other than 0): its index, then its fields in PROJECTILE_ARRAYS order.
static func _live_slots(world: World) -> PackedByteArray:
	var live: PackedInt32Array = PackedInt32Array()
	for slot: int in world.proj_id.size():
		if world.proj_id[slot] != 0:
			live.append(slot)
			for column_name: StringName in World.PROJECTILE_ARRAYS:
				if column_name != &"proj_free":
					var column: PackedInt32Array = world.get(column_name)
					live.append(column[slot])
	return live.to_byte_array()
