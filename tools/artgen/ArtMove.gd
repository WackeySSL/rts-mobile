class_name ArtMove
extends RefCounted
## One move of a pose group (ADR 0027 section 4), parsed from one line of an `ArtModel`'s `poses`:
##
##   <part> <frame> <group> shift <dx> <dy> <dz>
##   <part> <frame> <group> turn <axis> <degrees> <px> <py> <pz>
##
## `part` is `walk`, `idle` or `anim`, `frame` counts from 0, `group` is what the primitives carry
## in `group=`. `shift` moves the group by (dx, dy, dz) tiles. `turn` turns it by `degrees` about
## the line that runs along `axis` (x, y or z) through the pivot (px, py, pz), in the model's frame
## and before the hull's yaw. The sense is the hull's own: a positive turn about z takes x towards
## y, about x takes y towards z, about y takes z towards x. So a positive turn about y swings a
## point below its pivot towards -x, backwards from a unit that faces +x. A group's moves apply in
## the order of their lines, each to the result of the one before; a pivot is a point of the
## model's frame, it does not follow an earlier move.

const KINDS: Array[StringName] = [&"shift", &"turn"]

var part: StringName = &""
var frame: int = 0
var group: StringName = &""
var shift: Vector3 = Vector3.ZERO
var axis: int = -1  ## 0, 1 or 2 for a turn about x, y or z; -1 for a shift.
var degrees: float = 0.0
var pivot: Vector3 = Vector3.ZERO


## The move of a line, or null when the line is not one (a wrong word count, an unknown part or
## kind, a frame that is not a whole number from 0, a group that is not a name, a number that is
## not one).
static func parse(line: String) -> ArtMove:
	var words: PackedStringArray = line.split(" ", false)
	if words.size() < 4 or StringName(words[3]) not in KINDS:
		return null
	var turning: bool = words[3] == "turn"
	if words.size() != (9 if turning else 7) or StringName(words[0]) not in ArtModel.POSE_PARTS:
		return null
	if not words[1].is_valid_int() or words[1].to_int() < 0 or not words[2].is_valid_identifier():
		return null
	var nums: PackedFloat64Array = PackedFloat64Array()
	for i: int in range(5 if turning else 4, words.size()):
		if not words[i].is_valid_float():
			return null
		nums.append(words[i].to_float())
	var move: ArtMove = ArtMove.new()
	move.part = StringName(words[0])
	move.frame = words[1].to_int()
	move.group = StringName(words[2])
	if not turning:
		move.shift = Vector3(nums[0], nums[1], nums[2])
		return move
	move.axis = ArtPrim.AXES.find(words[4])
	if words[4].length() != 1 or move.axis < 0:
		return null
	move.degrees = words[5].to_float()
	move.pivot = Vector3(nums[1], nums[2], nums[3])
	return move


## `point` after the move.
func place(point: Vector3) -> Vector3:
	return point + shift if axis < 0 else pivot + spin(point - pivot)


## `direction` turned by the move (a shift leaves it): what a face's normal needs.
func spin(direction: Vector3) -> Vector3:
	if axis < 0:
		return direction
	var turn: Vector2 = ArtMesh.dir(degrees)
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	var out: Vector3 = direction
	out[u] = direction[u] * turn.x - direction[v] * turn.y
	out[v] = direction[u] * turn.y + direction[v] * turn.x
	return out
