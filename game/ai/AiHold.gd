class_name AiHold
extends RefCounted
## Hold position for the waves' artillery (ADR 0037 section 15, plan row P300), slot ARMY after
## `AiArmy` and `AiRepair`, on the same view and memory. A member of the wave squad whose type is in
## the def's `hold_types` should hold (`STANCE` `[1]`: weapon-range acquisition, no chase, so the
## gun does not walk into its minimum range); any other own combat unit that holds goes back to
## normal (`[0]`).
## So the release rule is the squad: a held unit is released when its wave ends (disbands, or the
## unit steps back), and the all-in's joiners hold the moment they join. The wish is read from the
## memory's squads and the view's own stance column every think, so nothing is stored between
## thinks and a refused or late order is simply sent again. One Command each way, at most, and only
## for the `hold_types` of the def: no other type is ever touched. Off (Easy, the frozen files)
## when the level's `hold_in_waves` is 0.

## Counters for the suites: units set to hold, units released.
var holds: int = 0
var releases: int = 0

var _on: bool = false
var _ids: Array[StringName] = []
var _resolved: bool = false
## One byte per type index: 1 for a type in `hold_types`.
var _is_hold: PackedByteArray = PackedByteArray()
var _set: PackedInt32Array = PackedInt32Array()
var _free: PackedInt32Array = PackedInt32Array()


static func create(def: OpponentDef, level: AiDifficultyDef) -> AiHold:
	var hold: AiHold = AiHold.new()
	hold._on = level.hold_in_waves > 0
	for id: StringName in def.hold_types:
		hold._ids.append(id)
	return hold


func run(view: PlayerView, memory: AiMemory, out: Array[Command]) -> void:
	if not _on or _ids.is_empty():
		return
	if not _resolved:
		_resolved = true
		_is_hold.resize(view.type_cost.size())
		_is_hold.fill(0)
		for id: StringName in _ids:
			var type: int = view.type_index_of(id)
			# A row of speed 0 is no `STANCE` target (the sim drops it): never wished.
			if type != PlayerView.MISSING and view.type_speed[type] > 0:
				_is_hold[type] = 1
	_set.clear()
	_free.clear()
	var own: PackedInt32Array = view.own_rows
	var stances: PackedInt32Array = view.own_stance
	var member_ids: PackedInt32Array = memory.member_id
	var squads: PackedInt32Array = memory.member_squad
	for at: int in member_ids.size():
		var row: int = view.row_of(member_ids[at])
		if row < 0:
			continue
		var type: int = view.row_type(row)
		if type < 0 or type >= _is_hold.size() or _is_hold[type] == 0:
			continue
		var held: int = stances[own.bsearch(row)]
		var wanted: int = 1 if squads[at] == AiArmy.WAVE else 0
		if held == wanted:
			continue
		if wanted == 1:
			_set.append(member_ids[at])
		else:
			_free.append(member_ids[at])
	if not _set.is_empty() and memory.can_send():
		out.append(Command.stance(view.player, _set.duplicate(), true))
		memory.spent()
		holds += _set.size()
	if not _free.is_empty() and memory.can_send():
		out.append(Command.stance(view.player, _free.duplicate(), false))
		memory.spent()
		releases += _free.size()
