class_name BuildingCollapse
extends RefCounted
## What becomes of a building that was shown when it died (ADR 0029 sections 8 to 10, plan P165;
## P159 made the hook). `BuildingLayer._drop` hands over the entry; the node stays in the sort and
## plays, on match time from the DIED tick: at 0 the `Anim` and `Head` hide; from
## `collapse_sink_ms[0]` the body and its `Damage` patch sink in `collapse_sink_steps` steps (each
## moves them down and cuts as many rows off the bottom) to `collapse_sink_percent` of the picture's
## rise; at `collapse_hide_ms` the node is hidden and the cast shadow removed; at `collapse_end_ms`
## the node is freed. The crater is laid at the DIED, scaled by `crater_scale_milli` of the
## building's type, and stays; the smoke and embers over it (P148's crater source) start at the end,
## unless the building was a site. The puffs are `CollapseFx`'s, in `AirFx`. The DIED flag
## (`Removal.died_flag`, ADR 0037 section 3) says which: a cancelled site (1) plays nothing and
## leaves no crater; a sold building (3) packs up, the sink and the dust with no flash, no fire, no
## crater and no crater smoke; any other death plays it all. A building that was not shown is not
## handed over at all.
## The sprite writes are timed, so `advance` spends them first in the buildings' share of a frame:
## 2 at the start, 4 a sink step (body and patch, region and offset) and 2 at the hide, 28 in all.
## A step that does not fit waits for the next frame and then writes the step of that moment, a
## coarser sink and never a lost one. At most `collapse_max` run at once; one more ends the oldest
## at once (hidden and freed; its crater stays). No node is made. Not a Node: it is called by the
## layer that owns it.

const START_WRITES: int = 2  ## `Anim` and `Head` hidden.
const STEP_WRITES: int = 4
const HIDE_WRITES: int = 2  ## The node and the shadow.
const PENDING: int = 0  ## States of a collapse: its start not written,
const SINKING: int = 1  ## written (the sink runs),
const HIDDEN: int = 2  ## and the node hidden.

## The numbers; the layer sets them before every call, so a change of its `life` is followed.
var life: LifeSettings
## Starts the puffs and the crater's smoke; null in a scene with no `AirFx`.
var air: AirFx = null

var _sort: WorldSort
var _decals: DecalLayer
var _cap: int = 0
var _n: int = 0  ## Collapses that run; `_order` holds their slots, the oldest first.
var _order: PackedInt32Array = PackedInt32Array()
var _entry: Array[BuildingLayer.Entry] = []
var _tick: PackedInt32Array = PackedInt32Array()
var _state: PackedByteArray = PackedByteArray()
var _step: PackedByteArray = PackedByteArray()  ## The last sink step written.
var _live: PackedByteArray = PackedByteArray()  ## 1 for a slot that is in use.
var _body_rect: Array[Rect2] = []  ## What the body and the patch showed when the building died.
var _patch_rect: Array[Rect2] = []
var _body_y: PackedFloat32Array = PackedFloat32Array()
var _patch_y: PackedFloat32Array = PackedFloat32Array()
var _patch_room: PackedFloat32Array = PackedFloat32Array()
var _blocked: bool = false  ## A write did not fit in this `advance`: later collapses wait too.


func setup(sort: WorldSort, decals: DecalLayer) -> void:
	_sort = sort
	_decals = decals


## Takes over `entry`, a shown building that left the rows in tick `died_tick`. The layer has
## already dropped it from its tables and the selection; its shadow is still in the decal layer.
@warning_ignore("integer_division")
func adopt(entry: BuildingLayer.Entry, died_tick: int, was_site: bool, flag: int) -> void:
	_make_if_resized(maxi(life.collapse_max, 0))
	# Flag 2 (a boarding) is for units, so no building has it yet; it plays nothing like 1 until
	# P265 decides what a boarding looks like.
	if flag == Removal.FLAG_CANCELLED or flag == Removal.FLAG_BOARDED:
		_free(entry)
		return
	if flag == Removal.FLAG_SOLD:  # The pack-up: no crater, no crater smoke, no flash.
		_begin(entry, died_tick, true)
		return
	var type_scale: int = life.crater_scale_milli.get(entry.type_id, 1000)
	var radius: int = entry.foot * BuildingLayer.CRATER_MILLI_PER_TILE * type_scale / 1000
	_decals.add_crater(entry.node.position, radius)
	if air != null and not was_site:
		var ticks: int = (life.collapse_end_ms * Sim.TICK_RATE + 999) / 1000
		var from: int = died_tick + ticks
		air.add_crater_source(
			entry.id, entry.node.position, entry.type, entry.tiles, entry.owner_id, from
		)
	_begin(entry, died_tick, false)


# Starts the sequence of `entry` in a slot (`quiet`: no flash and no fire, a sale); with no
# sequence the node is freed (the crater and its smoke, if any, stand).
func _begin(entry: BuildingLayer.Entry, died_tick: int, quiet: bool) -> void:
	if _cap == 0:
		_free(entry)
		return
	if _n == _cap:
		_end(_order[0])
	var slot: int = 0
	while _live[slot] == 1:
		slot += 1
	_live[slot] = 1
	_order[_n] = slot
	_n += 1
	_entry[slot] = entry
	_tick[slot] = died_tick
	_state[slot] = PENDING
	_step[slot] = 0
	if entry.body != null:
		_body_rect[slot] = entry.body.region_rect
		_body_y[slot] = entry.body.offset.y
	if entry.patch != null:
		_patch_rect[slot] = entry.patch.region_rect
		_patch_y[slot] = entry.patch.offset.y
		# How far the patch's drawn bottom stands above the body's (the ground), world px.
		var body_foot: float = _drawn_bottom(entry.body) if entry.body != null else 0.0
		_patch_room[slot] = maxf(body_foot - _drawn_bottom(entry.patch), 0.0)
	if air != null:
		air.collapses().start(
			entry.id, entry.node.position, entry.rise, entry.foot, died_tick, quiet
		)


## Whether any collapse runs.
func running() -> bool:
	return _n > 0


## The collapses that run.
func count() -> int:
	return _n


## The sink step last written for building `id`, -1 for one that is not collapsing.
func step_of(id: int) -> int:
	for at: int in _n:
		if _entry[_order[at]].id == id:
			return _step[_order[at]]
	return -1


## The node of the collapsing building `id`, null for none.
func node_of(id: int) -> Node2D:
	for at: int in _n:
		if _entry[_order[at]].id == id:
			return _entry[_order[at]].node
	return null


## Plays the collapses up to match time `now_ms` within `budget` sprite writes; returns the writes
## spent. A collapse that is over is freed whatever the budget. The starts and the hides go
## oldest first; the sink steps go to the collapse with the fewest steps written first (ties:
## the oldest), so a crowd of collapses on a short budget each sink a little and none is starved.
func advance(now_ms: float, budget: int) -> int:
	var spent: int = 0
	var at: int = 0
	_blocked = false
	while at < _n:
		var slot: int = _order[at]
		var t: float = now_ms - LifeClock.tick_ms(_tick[slot])
		if t >= float(life.collapse_end_ms):
			_end(slot)
			continue
		if not _blocked:
			spent += _play(slot, t, budget - spent)
		at += 1
	return spent + _sink_steps(now_ms, budget - spent)


## Frees every collapse at once (a new match): call it before the decal layer clears.
func clear() -> void:
	while _n > 0:
		_end(_order[0])


## The flag of the DIED of building `id` in `snap`'s events (`Removal.FLAG_*`), 0 for a death with
## no flag and for no DIED at all. Callers compare it with the value they mean, never with `!= 0`.
static func died_flag(snap: MatchSnapshot, id: int) -> int:
	var events: PackedInt32Array = snap.events
	for at: int in range(0, events.size(), World.EVENT_STRIDE):
		if events[at] == World.Event.DIED and events[at + 1] == id:
			return events[at + Removal.DIED_FLAG_AT]
	return 0


# Writes the start and the hide of the collapse in `slot` when due `t` ms after the DIED and they
# fit in `left` writes; sets `_blocked` when one does not. Returns the writes spent.
func _play(slot: int, t: float, left: int) -> int:
	var entry: BuildingLayer.Entry = _entry[slot]
	var used: int = 0
	if _state[slot] == PENDING:
		if left < START_WRITES:
			_blocked = true
			return 0
		if entry.anim != null:
			entry.anim.visible = false
		if entry.head != null:
			entry.head.visible = false
		_state[slot] = SINKING
		used += START_WRITES
	if t >= float(life.collapse_hide_ms):
		if _state[slot] != HIDDEN:
			if left - used < HIDE_WRITES:
				_blocked = true
				return used
			entry.node.visible = false
			_remove_shadow(entry)
			_state[slot] = HIDDEN
			used += HIDE_WRITES
		return used
	return used


# The sink step that is due `t` ms after the DIED: 0 before the sink starts, then one more every
# `(sink end - sink start) / steps` ms, the last at `steps`.
func _step_due(t: float) -> int:
	var from: float = float(life.collapse_sink_ms[0])
	var steps: int = life.collapse_sink_steps
	if t < from or steps <= 0:
		return 0
	var span: float = maxf(float(life.collapse_sink_ms[1]) - from, 1.0)
	return mini(floori((t - from) * float(steps) / span) + 1, steps)


# Writes the sink steps that are due at `now_ms` and fit in `left` writes, the collapse with the
# fewest steps written first. A step written is the one due at that moment (a coarser sink, never
# a lost one). Returns the writes spent.
func _sink_steps(now_ms: float, left: int) -> int:
	var used: int = 0
	while left - used >= STEP_WRITES:
		var pick: int = -1
		var due_pick: int = 0
		for at: int in _n:
			var slot: int = _order[at]
			if _state[slot] != SINKING:
				continue
			var t: float = now_ms - LifeClock.tick_ms(_tick[slot])
			var due: int = _step_due(t) if t < float(life.collapse_hide_ms) else 0
			if due > _step[slot] and (pick < 0 or _step[slot] < _step[pick]):
				pick = slot
				due_pick = due
		if pick < 0:
			break
		_sink(pick, due_pick)
		_step[pick] = due_pick
		used += STEP_WRITES
	return used


# Sinks the body and the patch of `slot` to step `step`. The body keeps its foot on the ground; the
# patch moves down with it and loses only the rows that would hang below the body's foot.
func _sink(slot: int, step: int) -> void:
	var entry: BuildingLayer.Entry = _entry[slot]
	var sunk: float = entry.rise * float(life.collapse_sink_percent) / 100.0
	sunk *= float(step) / float(life.collapse_sink_steps)
	if entry.body != null:
		var keep: float = 1.0
		if entry.patch != null:  # Rows that cover one row of the patch.
			keep = ceilf(entry.patch.scale.y / entry.body.scale.y)
		sunk = _cut_body(entry.body, _body_rect[slot], _body_y[slot], sunk, keep)
	if entry.patch != null and entry.patch.visible:
		_cut_patch(entry.patch, _patch_rect[slot], _patch_y[slot], sunk, _patch_room[slot])


# Moves the body down by about `sunk` world px, a whole number of its texel rows, and cuts as many
# rows off the bottom of its region `rect`, so its foot stays on the ground; `y` is its offset from
# before. It keeps `keep` rows at least, so a body already trimmed by its stage still shows the rows
# the patch's seam rests on. Returns the world px of the whole move (what the patch follows).
func _cut_body(body: Sprite2D, rect: Rect2, y: float, sunk: float, keep: float) -> float:
	var whole: float = floorf(sunk / body.scale.y)
	var rows: float = clampf(whole, 0.0, maxf(rect.size.y - keep, 0.0))
	body.region_rect = Rect2(rect.position, Vector2(rect.size.x, rect.size.y - rows))
	body.offset.y = y + rows
	return whole * body.scale.y


# Moves the patch down by `moved` world px with the body and cuts the rows of its region `rect`
# that would hang below the body's foot: more than `room` px below where its bottom was.
func _cut_patch(patch: Sprite2D, rect: Rect2, y: float, moved: float, room: float) -> void:
	var cut: float = clampf(ceilf((moved - room) / patch.scale.y), 0.0, rect.size.y - 1.0)
	patch.region_rect = Rect2(rect.position, Vector2(rect.size.x, rect.size.y - cut))
	patch.offset.y = y + moved / patch.scale.y


# The bottom of the drawn region of `sprite` in its parent's px.
func _drawn_bottom(sprite: Sprite2D) -> float:
	return sprite.position.y + sprite.get_rect().end.y * sprite.scale.y


# Ends the collapse in `slot`: its node is freed (and the shadow, if it is still there).
func _end(slot: int) -> void:
	var entry: BuildingLayer.Entry = _entry[slot]
	_free(entry)
	_live[slot] = 0
	_entry[slot] = null
	var at: int = 0
	while _order[at] != slot:
		at += 1
	for k: int in range(at, _n - 1):
		_order[k] = _order[k + 1]
	_n -= 1


# Frees an entry that never collapses: its shadow and its node.
func _free(entry: BuildingLayer.Entry) -> void:
	_remove_shadow(entry)
	_sort.remove_child(entry.node)
	entry.node.queue_free()


func _remove_shadow(entry: BuildingLayer.Entry) -> void:
	if entry.shadow != null:
		_decals.remove_shadow(entry.shadow)
		entry.shadow = null


# Makes the tables for `want` collapses (any change ends the running ones).
func _make_if_resized(want: int) -> void:
	if want != _cap:
		_resize(want)


func _resize(want: int) -> void:
	clear()
	_cap = want
	_order.resize(want)
	_entry.resize(want)
	_tick.resize(want)
	_state.resize(want)
	_step.resize(want)
	_live.resize(want)
	_live.fill(0)
	_body_rect.resize(want)
	_patch_rect.resize(want)
	_body_y.resize(want)
	_patch_y.resize(want)
	_patch_room.resize(want)
