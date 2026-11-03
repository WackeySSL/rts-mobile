class_name BuildingAnims
extends RefCounted
## The numbers of a building's `Anim` sprite (P144, ADR 0027 sections 4 and 5), kept out of
## `BuildingLayer`: which frame a loop shows at a clock, and whether a player's power is low. All
## static, integers and one float clock, no allocation.
## The clock a loop reads never goes back and is not the match time itself: the layer adds the
## match time that passed to one clock for every building (an enemy's, whose rate never depends on
## its owner's power) and to another, scaled by `LifeSettings.low_power_rate` while the local player
## is short of power, for the local player's own. A rate change then only changes how fast the
## clock goes on, so a frame never jumps when power runs out or comes back.
## Rest pose: the atlas holds the frames of the loop and nothing else, so the rest is frame 0. A
## held loop (a site, a blackout) shows it, and so do the placement ghost and the last-seen ghosts.
## It is not the unposed `anim` primitives of the card and the shadow for the Relay Tower, the Wind
## Park and the Turbine Hall (their groups start a few frames out of phase); it is the nearest
## frame the atlas has, and the one every layer agrees on.

const ANIM: StringName = &"anim"  ## The sheet part of a building's moving element.
## Salt of `LifeClock.pick` for the phase of a loop: far from RigLife's salts.
const SALT_ANIM: int = 0x50000000
const REST: int = 0


## The phase of building `id`'s loop, ms into it: the same for an id in every run, spread over the
## loop, so two Wind Parks do not turn in step.
static func phase_ms(id: int, frames: int, frame_ms: int) -> int:
	return LifeClock.pick(id, SALT_ANIM, frames * frame_ms)


## The frame a loop of `frames` frames of `frame_ms` ms shows at `clock_ms` from `phase`.
static func frame_at(phase: int, clock_ms: float, frames: int, frame_ms: int) -> int:
	return int((float(phase) + clock_ms) / float(frame_ms)) % frames


## Whether `player` uses more power than it makes in `snap`.
static func low_power(snap: MatchSnapshot, player: int) -> bool:
	var used: PackedInt32Array = snap.power_used
	var made: PackedInt32Array = snap.power_made
	if player < 0 or player >= used.size() or player >= made.size():
		return false
	return used[player] > made[player]


## Gives the ghost sprite `parent`, dressed for its body at the art scale, its `Anim` child showing
## the rest frame, or hides the child when the sheet has no loop the owner's faction has. The child
## inherits the parent's scale, so it keeps scale 1 and only its offset moves it to its origin.
static func dress_ghost(
	parent: Sprite2D, world_sort: WorldSort, sheet: IsoSheetDef, owner_id: int
) -> void:
	var child: Sprite2D = parent.get_child(0) as Sprite2D if parent.get_child_count() > 0 else null
	var base: int = -1
	if sheet.has_part(ANIM):
		base = world_sort.base_of(sheet, ANIM, BuildingLayer.NO_FRAME, owner_id)
	if world_sort.frame_count_at(base) < 1:
		if child != null:
			child.visible = false
		return
	if child == null:
		child = Sprite2D.new()
		child.name = "Anim"
		child.region_enabled = true
		child.centered = false
		parent.add_child(child)
	child.texture = world_sort.atlas.texture()  # Every dress: a re-bake makes a new page.
	child.offset = -Vector2(sheet.origin(ANIM)) * world_sort.atlas.bake_scale()
	world_sort.show_base(child, base, REST)
