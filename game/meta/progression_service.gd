extends Node
## Commander rank and XP (ADR 0045). XP is meta state, saved in `SaveService` section `progress`:
## `xp`, `next_award_id`, the last `awards_kept` awards, the lessons paid. The rank is derived
## from XP, never stored. Nothing is cached: every call reads the section and every change writes
## it back whole, so a SaveService reload or path switch never leaves a stale copy. When the save
## cannot take the write (read-only, refused) nothing changes and no signal fires. Phase 6 calls
## `apply_bonus` only from its reward callback. Integer arithmetic only. No class_name: this is an
## autoload (tests/project/test_autoloads.gd). Nothing here needs an ad: the bonus only speeds up
## what every player earns.

## XP changed (an award or a bonus). Read `xp()` and `rank()`.
signal xp_changed

const SaveServiceScript: GDScript = preload("res://game/meta/save_service.gd")
const SECTION: StringName = &"progress"
const DEF_PATH: String = "res://data/meta/progression.tres"
## A unit, not a balance number: `level_percent` is in percent.
const PERCENT: int = 100
const SECONDS_PER_MINUTE: int = 60

## A test seam like SaveService's: where errors go instead of push_error.
var error_sink: Callable = Callable()

var _def: ProgressionDef = null
var _save: SaveServiceScript = null
var _live: Dictionary = {}  # String id -> WeakRef of the XpAward handed out


func _ready() -> void:
	bind(SaveService, null)


## Uses `save` (the autoload by default; a test's own instance) and the tuning from `def` (null:
## `DEF_PATH`). False, with an error and no change, when the tuning is unusable.
func bind(save: SaveServiceScript, def: ProgressionDef) -> bool:
	var candidate: ProgressionDef = def if def != null else (load(DEF_PATH) as ProgressionDef)
	var problem: String = _def_problem(candidate)
	if problem != "":
		_report_error("Progression: unusable ProgressionDef: %s" % problem)
		return false
	_save = save
	_def = candidate
	_live = {}
	return true


func xp() -> int:
	return int(_read().get("xp", 0)) if _def != null else 0


## Rank 1 up, from XP.
func rank() -> int:
	if _def == null:
		return 1
	var total: int = xp()
	var found: int = 1
	for index: int in range(_def.rank_xp.size()):
		if total >= _def.rank_xp[index]:
			found = index + 1
	return found


func max_rank() -> int:
	return _def.rank_xp.size() if _def != null else 1


func title(rank_number: int) -> String:
	if _def == null:
		return ""
	return _def.rank_titles[clampi(rank_number, 1, max_rank()) - 1]


## XP the current rank starts at and the next one needs (equal at the top rank).
func rank_floor_xp() -> int:
	return _def.rank_xp[rank() - 1] if _def != null else 0


func next_rank_xp() -> int:
	return _def.rank_xp[mini(rank(), max_rank() - 1)] if _def != null else 0


## The rank that unlocks `kind` / `id`; 1 for what is open from the start.
func unlock_rank(kind: StringName, id: StringName) -> int:
	if _def == null:
		return 1
	for row: Dictionary in _def.unlocks:
		if row[&"kind"] == kind and row[&"id"] == id:
			return int(row[&"rank"])
	return 1


func is_unlocked(kind: StringName, id: StringName) -> bool:
	return rank() >= unlock_rank(kind, id)


## One of the last awards as saved (its `bonus_applied` is current), or null.
func get_award(award_id: StringName) -> XpAward:
	if _def == null:
		return null
	for entry: Dictionary in _read()["awards"]:
		if entry["id"] == String(award_id):
			return _award_from(entry)
	return null


## Adds the XP of a finished match, or of a lesson the player won (once per lesson). Null for no
## award: an abandoned match, an unknown outcome or level, a lesson that was not won or is
## already paid, or a save that cannot take the write (then nothing changes).
func award_match(summary: MatchSummary) -> XpAward:
	if _def == null or not _writable():
		return null
	var section: Dictionary = _read()
	var award: XpAward = XpAward.new()
	if summary.lesson_id != &"":
		# ADR 0045 is silent on a lost lesson: a lesson pays on completion (a win) only.
		var lessons: Array = section["lessons"]
		if summary.outcome != MatchSummary.OUTCOME_WIN or lessons.has(String(summary.lesson_id)):
			return null
		lessons.append(String(summary.lesson_id))
		award.base_xp = _def.lesson_xp
	else:
		var outcome: StringName = summary.outcome
		if outcome == MatchSummary.OUTCOME_SURRENDER:
			outcome = MatchSummary.OUTCOME_LOSS
		if not _def.outcome_xp.has(outcome):
			return null
		if not _def.level_percent.has(summary.level):
			_report_error("Progression: unknown level '%s', no award" % summary.level)
			return null
		var ticks_per_minute: int = Sim.TICK_RATE * SECONDS_PER_MINUTE
		@warning_ignore("integer_division")
		var minutes: int = maxi(0, summary.ticks) / ticks_per_minute
		var bonus: int = mini(minutes * _def.xp_per_minute, _def.minute_cap)
		@warning_ignore("integer_division")
		award.base_xp = (
			_def.outcome_xp[outcome] * _def.level_percent[summary.level] / PERCENT + bonus
		)
		award.id = StringName("a%d" % section["next_award_id"])
		section["next_award_id"] += 1
		var awards: Array = section["awards"]
		awards.append({"id": String(award.id), "base_xp": award.base_xp, "bonus_applied": false})
		while awards.size() > _def.awards_kept:
			awards.pop_front()
	section["xp"] += award.base_xp
	if not _write(section):
		return null
	if award.id != &"":
		_live[String(award.id)] = weakref(award)
	xp_changed.emit()
	return award


## Adds `base_xp * (multiplier - 1)` once for one of the last awards and marks it applied (also
## on the XpAward the caller holds, and in `get_award`). False, with nothing changed, for an
## unknown, old or lesson id, a second call, a multiplier below `min_bonus_multiplier`, or a save
## that cannot take the write.
func apply_bonus(award_id: StringName, multiplier: int) -> bool:
	if _def == null or award_id == &"" or multiplier < _def.min_bonus_multiplier:
		return false
	if not _writable():
		return false
	var section: Dictionary = _read()
	for entry: Dictionary in section["awards"]:
		if entry["id"] != String(award_id):
			continue
		if entry["bonus_applied"]:
			return false
		entry["bonus_applied"] = true
		section["xp"] += int(entry["base_xp"]) * (multiplier - 1)
		if not _write(section):
			return false
		var held: Variant = _live.get(String(award_id))
		if held is WeakRef:
			var award: XpAward = (held as WeakRef).get_ref() as XpAward
			if award != null:
				award.bonus_applied = true
		xp_changed.emit()
		return true
	return false


## The section with every field present and valid; a malformed award entry is skipped with a
## warning.
func _read() -> Dictionary:
	var raw: Dictionary = _save.get_section(SECTION)
	var section: Dictionary = {
		"xp": maxi(0, int(raw.get("xp", 0))),
		"next_award_id": maxi(1, int(raw.get("next_award_id", 1))),
		"awards": [],
		"lessons": [],
	}
	for entry: Variant in raw.get("awards", []) as Array:
		if _entry_ok(entry):
			(section["awards"] as Array).append(entry)
		else:
			_report_warning("Progression: skipped a malformed award entry")
	for lesson: Variant in raw.get("lessons", []) as Array:
		(section["lessons"] as Array).append(str(lesson))
	return section


func _entry_ok(entry: Variant) -> bool:
	if not entry is Dictionary:
		return false
	var row: Dictionary = entry
	return (
		row.get("id") is String and row.get("base_xp") is int and row.get("bonus_applied") is bool
	)


func _writable() -> bool:
	if _save.is_read_only():
		_report_warning("Progression: the save is read-only (newer version); no change made")
		return false
	return true


func _write(section: Dictionary) -> bool:
	if _save.set_section(SECTION, section):
		return true
	_report_error("Progression: the save refused section 'progress'; no change made")
	return false


func _award_from(entry: Dictionary) -> XpAward:
	var award: XpAward = XpAward.new()
	award.id = StringName(entry["id"])
	award.base_xp = entry["base_xp"]
	award.bonus_applied = entry["bonus_applied"]
	return award


func _def_problem(def: ProgressionDef) -> String:
	if def == null:
		return "not loadable"
	var problem: String = _ranks_problem(def)
	if problem == "" and (def.xp_per_minute < 0 or def.minute_cap < 0 or def.lesson_xp < 0):
		problem = "XP values must not be negative"
	if problem == "" and (def.awards_kept < 1 or def.min_bonus_multiplier < 2):
		problem = "awards_kept must be at least 1 and min_bonus_multiplier at least 2"
	for row: Dictionary in def.unlocks:
		if problem == "" and not (row.has(&"kind") and row.has(&"id") and row.get(&"rank") is int):
			problem = "an unlock row needs kind, id and rank"
	return problem


func _ranks_problem(def: ProgressionDef) -> String:
	if def.rank_xp.is_empty() or def.rank_xp[0] != 0:
		return "rank_xp must start at 0"
	if def.rank_titles.size() != def.rank_xp.size():
		return "rank_titles must match rank_xp in length"
	for index: int in range(1, def.rank_xp.size()):
		if def.rank_xp[index] <= def.rank_xp[index - 1]:
			return "rank_xp must rise"
	return ""


func _report_error(text: String) -> void:
	if error_sink.is_valid():
		error_sink.call(text)
	else:
		push_error(text)


func _report_warning(text: String) -> void:
	if error_sink.is_valid():
		error_sink.call(text)
	else:
		push_warning(text)
