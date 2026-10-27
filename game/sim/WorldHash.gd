class_name WorldHash
extends RefCounted
## The state hash and the definitions hash of a World, split out of World.gd (P70c) so that file
## stays under gdlint's 1,000 lines. Pure static helpers: they read the World passed in and keep
## nothing, apart from the map digest cache, which is the World's own `_map_digest` and
## `_map_digest_version`. World.state_hash(), hash_parts(), hash_section_names(), hash_hex() and
## defs_hash() are thin wrappers over the functions here, and World.prepare() calls map_digest(),
## so no caller names this class. No rule lives here: the code is World.gd's own, moved, and the
## bytes it feeds are the same (ADR 0007 section 8, ADR 0016, ADR 0017 section 3).


## The state hash (ADR 0007 section 8): SHA-256 over the sections of hash_section_names(), in that
## order, each block fed as its tag (the section index), its byte count and its bytes (little
## endian); the first 8 digest bytes as a signed int64. It reads only the hashed lists: the header
## ints and the stream, the map digest, the ROW_ARRAYS columns, the live projectile slots with the
## used free stack, FogGrid.HASHED (the explored bytes: the visible counts are derived from the
## hashed rows and not fed, ADR 0016), the PLAYER_ARRAYS and ORE_ARRAYS arrays and the live ghost
## records. The DERIVED_ARRAYS and the type tables stay out. A hand-built world hashes before
## prepare() too (empty helpers and map), to another value than after it.
static func state_hash(world: World) -> int:
	var ctx: HashingContext = _start_hash()
	for section: int in World.ROW_ARRAYS.size() + World.HASH_OTHER_SECTIONS:
		_feed_section(ctx, world, section)
	return ctx.finish().decode_s64(0)


## One digest prefix per section, in hash_section_names() order, of the bytes state_hash() feeds.
## For the failure message of a test that compares two hashes; it is not called in the tick.
static func hash_parts(world: World) -> PackedInt64Array:
	var parts: PackedInt64Array = PackedInt64Array()
	for section: int in World.ROW_ARRAYS.size() + World.HASH_OTHER_SECTIONS:
		var ctx: HashingContext = _start_hash()
		_feed_section(ctx, world, section)
		parts.append(ctx.finish().decode_s64(0))
	return parts


## "header", "map", one name per ROW_ARRAYS entry, "projectiles", "fog", "players", "ore", "ghosts".
## The "fog" section feeds FogGrid.HASHED, which is `explored` alone since STATE_FORMAT 2; the name
## stays. "players" feeds one block per PLAYER_ARRAYS array, "ore" one per ORE_ARRAYS array and
## "ghosts" two (_feed_ghosts); they come after "fog" since STATE_FORMAT 3.
static func hash_section_names() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray(["header", "map"])
	names.append_array(PackedStringArray(World.ROW_ARRAYS))
	names.append_array(PackedStringArray(["projectiles", "fog", "players", "ore", "ghosts"]))
	return names


## `h` as 16 lower-case hex digits, its 8 bytes least significant first (ADR 0007 section 8).
static func hash_hex(h: int) -> String:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, h)
	return bytes.hex_encode()


## The hash of the type and weapon tables, their ids, the faction ids and the rule ints: what a
## replay needs to see that it runs on other data. Call it on a prepared world, because prepare()
## pads the type tables.
static func defs_hash(world: World) -> int:
	var ctx: HashingContext = _start_hash()
	var tag: int = 0
	for table_name: StringName in World.TYPE_ARRAYS + World.WEAPON_ARRAYS:
		_feed(ctx, tag, _bytes_of(world.get(table_name)))
		tag += 1
	var rules: PackedInt64Array = PackedInt64Array()
	for rule_name: StringName in World.RULE_SCALARS:
		rules.append(world.get(rule_name))
	_feed(ctx, tag, rules.to_byte_array())
	_feed(ctx, tag + 1, PackedStringArray(world.type_ids).to_byte_array())
	_feed(ctx, tag + 2, PackedStringArray(world.weapon_ids).to_byte_array())
	_feed(ctx, tag + 3, PackedStringArray(world.faction_ids).to_byte_array())
	return ctx.finish().decode_s64(0)


## The digest of MAP_ARRAYS in list order, recomputed only when map_version has changed. The cache
## is the World's `_map_digest` and `_map_digest_version`; World.prepare() resets the version.
static func map_digest(world: World) -> int:
	if world._map_digest_version != world.map_version:
		var ctx: HashingContext = _start_hash()
		for index: int in World.MAP_ARRAYS.size():
			_feed(ctx, index, _bytes_of(world.get(World.MAP_ARRAYS[index])))
		world._map_digest = ctx.finish().decode_s64(0)
		world._map_digest_version = world.map_version
	return world._map_digest


## Feeds the blocks of section `section`, an index into hash_section_names().
static func _feed_section(ctx: HashingContext, world: World, section: int) -> void:
	var rows_end: int = 2 + World.ROW_ARRAYS.size()
	if section == 0:
		var header: PackedInt64Array = PackedInt64Array([World.STATE_FORMAT])
		for scalar_name: StringName in World.HASHED_SCALARS:
			header.append(world.get(scalar_name))
		header.append_array(world.rng.state())
		_feed(ctx, section, header.to_byte_array())
	elif section == 1:
		_feed(ctx, section, PackedInt64Array([map_digest(world)]).to_byte_array())
	elif section < rows_end:
		_feed(ctx, section, _bytes_of(world.get(World.ROW_ARRAYS[section - 2])))
	elif section == rows_end:
		_feed_projectiles(ctx, world, section)
	elif section == rows_end + 1:
		for array_name: StringName in FogGrid.HASHED:
			_feed(ctx, section, _bytes_of(world.fog.get(array_name)))
	elif section == rows_end + 2:
		for array_name: StringName in World.PLAYER_ARRAYS:
			_feed(ctx, section, _bytes_of(world.get(array_name)))
	elif section == rows_end + 3:
		for array_name: StringName in World.ORE_ARRAYS:
			_feed(ctx, section, _bytes_of(world.get(array_name)))
	else:
		_feed_ghosts(ctx, world, section)


## The live slots (index, then the fields in PROJECTILE_ARRAYS order), then the used free stack.
static func _feed_projectiles(ctx: HashingContext, world: World, section: int) -> void:
	var columns: Array[PackedInt32Array] = []
	for column_name: StringName in World.PROJECTILE_ARRAYS:
		if column_name != &"proj_free":
			columns.append(world.get(column_name))
	var ids: PackedInt32Array = world.proj_id
	var live_count: int = 0
	for slot: int in ids.size():
		if ids[slot] != 0:
			live_count += 1
	var live: PackedInt32Array = PackedInt32Array()
	live.resize(live_count * (columns.size() + 1))  # One resize, then writes by index.
	var at: int = 0
	for slot: int in ids.size():
		if ids[slot] != 0:
			live[at] = slot
			at += 1
			for column: PackedInt32Array in columns:
				live[at] = column[slot]
				at += 1
	_feed(ctx, section, live.to_byte_array())
	_feed(ctx, section, world.proj_free.slice(0, world.proj_free_top).to_byte_array())


## The live last-seen records (ADR 0017 section 3): the count of each player, then the four fields
## of each live record (record `i` of player `p` is entry `p * ghost_cap + i`), players ascending.
## A record at or above its player's count is not state.
static func _feed_ghosts(ctx: HashingContext, world: World, section: int) -> void:
	var counts: PackedInt32Array = world.ghost_count
	var ids: PackedInt32Array = world.ghost_id
	var types: PackedInt32Array = world.ghost_type
	var owners: PackedInt32Array = world.ghost_owner
	var cells: PackedInt32Array = world.ghost_cell
	var cap: int = world.ghost_cap
	var total: int = 0
	for count: int in counts:
		total += count
	var live: PackedInt32Array = PackedInt32Array()
	live.resize(total * 4)  # One resize, then writes by index.
	var at: int = 0
	for player: int in counts.size():
		for record: int in counts[player]:
			var entry: int = player * cap + record
			live[at] = ids[entry]
			live[at + 1] = types[entry]
			live[at + 2] = owners[entry]
			live[at + 3] = cells[entry]
			at += 4
	_feed(ctx, section, counts.to_byte_array())
	_feed(ctx, section, live.to_byte_array())


static func _start_hash() -> HashingContext:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	return ctx


## One block: the tag and the byte count as two int64, then the bytes (update() refuses none).
static func _feed(ctx: HashingContext, tag: int, bytes: PackedByteArray) -> void:
	ctx.update(PackedInt64Array([tag, bytes.size()]).to_byte_array())
	if not bytes.is_empty():
		ctx.update(bytes)


## A byte array as it is, any other Packed array little-endian (strings as null-terminated UTF-8).
static func _bytes_of(table: Variant) -> PackedByteArray:
	if table is PackedByteArray:
		return table
	return table.to_byte_array()
