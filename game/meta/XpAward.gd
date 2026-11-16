class_name XpAward
extends RefCounted
## One award of `Progression.award_match`: a stable id (a counter in the save), the XP it added
## and whether the Double XP bonus was applied. A tutorial lesson's award has the empty id, so
## `apply_bonus` refuses it (lessons never count for ads).

var id: StringName = &""
var base_xp: int = 0
var bonus_applied: bool = false
