class_name ProjectileLayer
extends Node2D
## Draws the projectiles of the runner's published snapshot (assets/art/STYLE.md "Combat effects",
## ADR 0012 section 3, z 40 in ADR 0023 section 2): every live slot is one quad of the effects
## atlas, the SHELL region for a shot of any weapon but the rocket, the ROCKET region for that one
## (the weapon is `weapon_ids[proj_weapon]`). A quad stands at lerp(prev_proj, proj, alpha)
## projected by `IsoProjection` (ADR 0023 section 1) and lifted by the muzzle height of its weapon
## (`SpriteLift.muzzle_lift_px`, the shooter's `muzzle_lift_px` of its sheet once P113 brings them:
## a shell flies straight and level in Phase 3), turned along the move from prev_proj to proj as
## that move looks on the screen, and is as big in world px as its region, so it scales with the
## zoom.
## Whose shell it is does not matter: a slot of owner 0 (a neutral armed unit) is drawn like any.
##
## A slot whose `proj_id` differs from `prev_proj_id` is new in the last tick: it has no heading, so
## it is not drawn until the next tick (ADR 0012's amendment; the muzzle flash covers the 67 ms).
## That also holds for a slot that was freed and launched again in one tick, which has a new id.
## The tick a shell lands its slot is already free in the snapshot, so its last step is not drawn
## either (the impact puff marks the landing).
##
## A projectile on a tile that the local player does not see is not drawn (ADR 0010 section 2): the
## tile is the one of its position in the tick, from `snapshot.cell_of`, so the flag changes per
## tick. `reveal_enemies` draws every one (the perf arena, and tests whose subject is not fog).
##
## The layer reads `runner.snapshot` afresh in every frame and keeps nothing between frames but
## its plan, which `_process` rebuilds from the snapshot, so a new match (another `match_serial`)
## starts from an empty plan. `_process` writes the plan into reused packed arrays and `_draw`
## paints the same arrays, so a frame creates no object. Tests read the plan through `active_count`
## and the accessors `quad_slot`, `quad_position`, `quad_angle` and `quad_region`, and what was
## painted through `drawn_count`. Only atlas quads are painted, in one `_draw()`.

const ATLAS_ART: String = "res://assets/art/svg/fx/effects_atlas.svg"
## Regions of the atlas in the px of the imported texture (STYLE.md: SHELL 84,60,16,8 and ROCKET
## 84,72,36,12). Each sprite sits at the centre of its region and faces east.
const SHELL_REGION: Rect2 = Rect2(84.0, 60.0, 16.0, 8.0)
const ROCKET_REGION: Rect2 = Rect2(84.0, 72.0, 36.0, 12.0)
## Where a quad lands relative to its centre: the region's size, centred (no scaling).
const SHELL_QUAD: Rect2 = Rect2(-8.0, -4.0, 16.0, 8.0)
const ROCKET_QUAD: Rect2 = Rect2(-18.0, -6.0, 36.0, 12.0)
const ROCKET_ID: StringName = &"rocket"
const KIND_SHELL: int = 0
const KIND_ROCKET: int = 1
const FLOATS_PER_QUAD: int = 3  ## x and y in world px, then the heading in radians.

@export var runner: MatchRunner
## Draws the projectiles on tiles the fog hides too: the perf arena, tests that are not about fog.
@export var reveal_enemies: bool = false

var _atlas: Texture2D = load(ATLAS_ART)
## The plan of the frame: quad `i` is projectile slot `_slots[i]`, drawn of kind `_kinds[i]` at the
## FLOATS_PER_QUAD floats from `i * FLOATS_PER_QUAD` of `_geometry`.
var _slots: PackedInt32Array = PackedInt32Array()
var _kinds: PackedByteArray = PackedByteArray()
var _geometry: PackedFloat32Array = PackedFloat32Array()
var _quads: int = 0
var _drawn: int = 0  ## Quads the last _draw painted.


func _process(_delta: float) -> void:
	var had_quads: bool = _quads > 0
	_plan()
	if had_quads or _quads > 0:
		queue_redraw()


## Quads in the plan of the last frame: the live slots of the snapshot that are not new.
func active_count() -> int:
	return _quads


## Quads the last `_draw` painted: the plan of the frame it ran after.
func drawn_count() -> int:
	return _drawn


## The projectile slot of quad `index`, its centre in layer coordinates (world px), its heading
## (east is 0) and its atlas region.
func quad_slot(index: int) -> int:
	return _slots[index]


func quad_position(index: int) -> Vector2:
	var at: int = index * FLOATS_PER_QUAD
	return Vector2(_geometry[at], _geometry[at + 1])


func quad_angle(index: int) -> float:
	return _geometry[index * FLOATS_PER_QUAD + 2]


func quad_region(index: int) -> Rect2:
	return ROCKET_REGION if _kinds[index] == KIND_ROCKET else SHELL_REGION


## Plans the quads of the frame from the snapshot. Allocates nothing in steady state: the arrays
## are only resized when the snapshot has more slots than before.
func _plan() -> void:
	_quads = 0
	var snap: MatchSnapshot = runner.snapshot if runner != null else null
	if snap == null:
		return
	var ids: PackedInt32Array = snap.proj_id
	var prev_ids: PackedInt32Array = snap.prev_proj_id
	var slots: int = mini(ids.size(), prev_ids.size())
	if _slots.size() < slots:
		_slots.resize(slots)
		_kinds.resize(slots)
		_geometry.resize(slots * FLOATS_PER_QUAD)
	var weapons: PackedInt32Array = snap.proj_weapon
	var prev_x: PackedInt32Array = snap.prev_proj_x
	var prev_y: PackedInt32Array = snap.prev_proj_y
	var cur_x: PackedInt32Array = snap.proj_x
	var cur_y: PackedInt32Array = snap.proj_y
	var weapon_ids: Array[StringName] = snap.weapon_ids
	var rocket: int = weapon_ids.find(ROCKET_ID)  # -1 without one: no slot is a rocket.
	var alpha: float = runner.alpha()
	var geometry: PackedFloat32Array = _geometry
	var player: int = FogLayer.local_player_of(runner)
	var fog: FogGrid = snap.fog
	var fogged: bool = not reveal_enemies and FogLayer.covers(fog, player)
	var counts: PackedInt32Array = fog.visible
	var counts_at: int = (player - 1) * fog.cells
	# The scan stops at the last live slot, so a quiet frame costs one count and a fight the
	# slots up to its highest one (the sim hands out the lowest never-used slot first).
	var live: int = slots - ids.count(0)
	for slot: int in slots:
		if live == 0:
			break
		var id: int = ids[slot]
		if id == 0:
			continue
		live -= 1
		if id != prev_ids[slot]:
			continue  # New in the last tick: no heading yet.
		var from_x: int = prev_x[slot]
		var from_y: int = prev_y[slot]
		var to_x: int = cur_x[slot]
		var to_y: int = cur_y[slot]
		if fogged and counts[counts_at + snap.cell_of(to_x, to_y)] <= 0:
			continue  # On a tile the local player does not see.
		var out: int = _quads * FLOATS_PER_QUAD
		var place: Vector2 = IsoProjection.ground_to_px(from_x, from_y).lerp(
			IsoProjection.ground_to_px(to_x, to_y), alpha
		)
		geometry[out] = place.x
		geometry[out + 1] = place.y - SpriteLift.muzzle_lift_px(weapon_ids, weapons[slot])
		geometry[out + 2] = IsoProjection.screen_angle(float(to_x - from_x), float(to_y - from_y))
		_slots[_quads] = slot
		_kinds[_quads] = KIND_ROCKET if weapons[slot] == rocket else KIND_SHELL
		_quads += 1


func _draw() -> void:
	_drawn = 0
	var geometry: PackedFloat32Array = _geometry
	var kinds: PackedByteArray = _kinds
	for index: int in _quads:
		var at: int = index * FLOATS_PER_QUAD
		draw_set_transform(Vector2(geometry[at], geometry[at + 1]), geometry[at + 2])
		if kinds[index] == KIND_ROCKET:
			draw_texture_rect_region(_atlas, ROCKET_QUAD, ROCKET_REGION)
		else:
			draw_texture_rect_region(_atlas, SHELL_QUAD, SHELL_REGION)
		_drawn += 1
