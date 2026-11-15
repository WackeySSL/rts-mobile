extends Node
## Commander rank and XP (ADR 0045). XP is meta state, saved in `SaveService` section `progress`:
## `xp`, `next_award_id`, the last `awards_kept` awards, the lessons paid. The rank is derived
## from XP, never stored. Phase 6 calls `apply_bonus` only from its reward callback. Integer
## arithmetic only. No class_name: this is an autoload (tests/project/test_autoloads.gd).
## Nothing here needs an ad: the bonus only speeds up what every player earns.

## XP changed (an award or a bonus). Read `xp()` and `rank()`.
signal xp_changed

const SECTION: StringName = &"progress"
const DEF_PATH: String = "res://data/meta/progression.tres"

var _def: ProgressionDef = null
var _save: Node = null
var _xp: int = 0
var _next_award_id: int = 1
var _awards: Array[Dictionary] = []  # {id: String, base_xp: int, bonus_applied: bool}
var _lessons: Array[String] = []


func _ready() -> void:
	bind(SaveService, null)


## Reads the saved section from `save` (the autoload by default; a test's own instance) and the
## tuning from `def` (null: `DEF_PATH`). Tests call it again to simulate a restart.
func bind(save: Node, def: ProgressionDef) -> void:
	_save = save
	_def = def if def != null else (load(DEF_PATH) as ProgressionDef)
	var section: Dictionary = _save.call("get_section", SECTION)
	_xp = maxi(0, int(section.get("xp", 0)))
	_next_award_id = maxi(1, int(section.get("next_award_id", 1)))
	_awards = []
	for entry: Variant in section.get("awards", []) as Array:
		if entry is Dictionary:
			_awards.append(entry)
	_lessons = []
	for lesson: Variant in section.get("lessons", []) as Array:
		_lessons.append(str(lesson))


func xp() -> int:
	return _xp


## Rank 1 up, from XP.
func rank() -> int:
	var found: int = 1
	for index: int in range(_def.rank_xp.size()):
		if _xp >= _def.rank_xp[index]:
			found = index + 1
	return found


func max_rank() -> int:
	return _def.rank_xp.size()


func title(rank_number: int) -> String:
	return _def.rank_titles[clampi(rank_number, 1, max_rank()) - 1]


## XP the current rank starts at and the next one needs (equal at the top rank).
func rank_floor_xp() -> int:
	return _def.rank_xp[rank() - 1]


func next_rank_xp() -> int:
	return _def.rank_xp[mini(rank(), max_rank() - 1)]


## The rank that unlocks `kind` / `id`; 1 for what is open from the start.
func unlock_rank(kind: StringName, id: StringName) -> int:
	for row: Dictionary in _def.unlocks:
		if row[&"kind"] == kind and row[&"id"] == id:
			return int(row[&"rank"])
	return 1


func is_unlocked(kind: StringName, id: StringName) -> bool:
	return rank() >= unlock_rank(kind, id)


## Adds the XP of a finished match or lesson. Null for no award: an abandoned match, an unknown
## outcome, or a lesson already paid.
func award_match(summary: MatchSummary) -> XpAward:
	var award: XpAward = XpAward.new()
	if summary.lesson_id != &"":
		if _lessons.has(String(summary.lesson_id)):
			return null
		_lessons.append(String(summary.lesson_id))
		award.base_xp = _def.lesson_xp
	else:
		var outcome: StringName = summary.outcome
		if outcome == MatchSummary.OUTCOME_SURRENDER:
			outcome = MatchSummary.OUTCOME_LOSS
		if not _def.outcome_xp.has(outcome):
			return null
		var percent: int = _def.level_percent.get(summary.level, 100)
		@warning_ignore("integer_division")
		var minutes: int = maxi(0, summary.ticks) / _def.ticks_per_minute
		var bonus: int = mini(minutes * _def.xp_per_minute, _def.minute_cap)
		@warning_ignore("integer_division")
		award.base_xp = _def.outcome_xp[outcome] * percent / 100 + bonus
		award.id = StringName("a%d" % _next_award_id)
		_next_award_id += 1
		_awards.append({"id": String(award.id), "base_xp": award.base_xp, "bonus_applied": false})
		while _awards.size() > _def.awards_kept:
			_awards.pop_front()
	_xp += award.base_xp
	_persist()
	xp_changed.emit()
	return award


## Adds `base_xp * (multiplier - 1)` once for one of the last awards. False for an unknown, old
## or lesson id, a second call, or a multiplier below `min_bonus_multiplier`.
func apply_bonus(award_id: StringName, multiplier: int) -> bool:
	if award_id == &"" or multiplier < _def.min_bonus_multiplier:
		return false
	for entry: Dictionary in _awards:
		if entry["id"] != String(award_id):
			continue
		if entry["bonus_applied"]:
			return false
		entry["bonus_applied"] = true
		_xp += int(entry["base_xp"]) * (multiplier - 1)
		_persist()
		xp_changed.emit()
		return true
	return false


func _persist() -> void:
	(
		_save
		. call(
			"set_section",
			SECTION,
			{
				"xp": _xp,
				"next_award_id": _next_award_id,
				"awards": _awards,
				"lessons": _lessons,
			}
		)
	)
