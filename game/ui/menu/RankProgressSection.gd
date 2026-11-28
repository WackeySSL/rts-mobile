class_name RankProgressSection
extends VBoxContainer
## The Rank screen's PROGRESS section (ADR 0054 section 8, plan P673e): the wins grid (one row per
## map, one cell per level, a lock and the opening rank on a map or level not yet open), then the
## lessons done, matches played, wins, time played and fastest win. Every number is
## `Progression.career()` and the catalogs; nothing here is counted. Read-only: the controls are
## `MOUSE_FILTER_PASS`, so a finger drag over them still scrolls the page (P672b). The look is the
## theme's (`MenuMapCard`, `MenuMapCardOn`, `MenuMapCardLocked`, `MenuEyebrow`, `MenuTag`).

const LOCK_ART: Texture2D = preload("res://assets/art/svg/icons/glyph_lock.svg")
const LOCK_DP: float = 16.0
## Every level column is this wide (and the head over it), so the rows line up; the map name
## takes the rest of the line.
const CELL_DP: float = 60.0
const GAP_DP: float = 6.0
const SECONDS_PER_HOUR: int = 3600
const SECONDS_PER_MINUTE: int = 60

var _progression: Node
var _maps: MapCatalog
var _lessons: PackedStringArray = PackedStringArray()


## Draws the section again from `progression` (its career and unlocks), `maps` and the lesson ids
## in `tutorial.done`.
func refresh(progression: Node, maps: MapCatalog, lessons: PackedStringArray) -> void:
	RankText.register()
	_progression = progression
	_maps = maps
	_lessons = lessons
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	var career: Dictionary = progression.call("career") as Dictionary
	_add_eyebrow(RankText.WINS_GRID)
	_add_grid(career)
	_add_stat(RankText.LESSONS, _lessons_text())
	_add_stat(RankText.MATCHES, str(int(career.get("finished", 0))))
	_add_stat(RankText.WINS, str(int(career.get("wins", 0))))
	_add_stat(RankText.TIME_PLAYED, time_text(int(career.get("play_ticks", 0))))
	_add_stat(RankText.FASTEST_WIN, fastest_text(int(career.get("best_win_ticks", 0))))


## "H h MM min" from an hour on, else "M min SS s".
static func time_text(ticks: int) -> String:
	RankText.register()
	var seconds: int = maxi(ticks, 0) / Sim.TICK_RATE
	if seconds >= SECONDS_PER_HOUR:
		var hours: int = seconds / SECONDS_PER_HOUR
		var minutes: int = seconds % SECONDS_PER_HOUR / SECONDS_PER_MINUTE
		return TranslationServer.translate(RankText.TIME_LONG) % [hours, minutes]
	var short: Array[int] = [seconds / SECONDS_PER_MINUTE, seconds % SECONDS_PER_MINUTE]
	return TranslationServer.translate(RankText.TIME_SHORT) % short


## "M:SS", or "None yet" while there is no win.
static func fastest_text(ticks: int) -> String:
	if ticks <= 0:
		return TranslationServer.translate(RankText.NO_WIN)
	RankText.register()
	var seconds: int = ticks / Sim.TICK_RATE
	var clock: Array[int] = [seconds / SECONDS_PER_MINUTE, seconds % SECONDS_PER_MINUTE]
	return TranslationServer.translate(RankText.FASTEST) % clock


## The rank a cell of `map_id` at `level` opens at, or 0 when it is open.
func cell_lock_rank(map_id: StringName, level: StringName) -> int:
	var rank: int = 0
	for row: Array in [[&"map", map_id], [&"level", level]]:
		var kind: StringName = row[0] as StringName
		var id: StringName = row[1] as StringName
		if not bool(_progression.call("is_unlocked", kind, id)):
			rank = maxi(rank, int(_progression.call("unlock_rank", kind, id)))
	return rank


func _lessons_text() -> String:
	var count: int = 0
	for id: StringName in TutorialStart.ORDER:
		count += 1 if _lessons.has(String(id)) else 0
	return tr(RankText.OF) % [count, TutorialStart.ORDER.size()]


func _add_grid(career: Dictionary) -> void:
	var wins: Dictionary = career.get("wins_grid", {}) as Dictionary
	var head: HBoxContainer = _row()
	var corner: Label = _eyebrow(RankText.MAP_HEAD)
	head.add_child(corner)
	for level: StringName in MapSelect.LEVELS:
		var word: Label = _eyebrow(MapSelect.LEVEL_TEXT[level])
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		word.custom_minimum_size.x = UiScale.dp(CELL_DP)
		head.add_child(word)
	for map_id: StringName in _maps.map_ids():
		var line: HBoxContainer = _row()
		line.name = StringName("Map_" + String(map_id))
		var title: Label = Label.new()
		title.text = _maps.title(map_id)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(title)
		var row: Dictionary = wins.get(String(map_id), {}) as Dictionary
		for level: StringName in MapSelect.LEVELS:
			line.add_child(_cell(map_id, level, int(row.get(String(level), 0))))


func _cell(map_id: StringName, level: StringName, wins: int) -> PanelContainer:
	var lock: int = cell_lock_rank(map_id, level)
	var cell: PanelContainer = PanelContainer.new()
	cell.name = StringName("Cell_%s_%s" % [map_id, level])
	cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cell.custom_minimum_size.x = UiScale.dp(CELL_DP)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.theme_type_variation = (
		&"MenuMapCardLocked" if lock > 0 else (&"MenuMapCardOn" if wins > 0 else &"MenuMapCard")
	)
	var stack: VBoxContainer = VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	cell.add_child(stack)
	if lock > 0:
		var icon: TextureRect = TextureRect.new()
		icon.name = &"Lock"
		icon.texture = LOCK_ART
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = UiScale.dp_vec(LOCK_DP, LOCK_DP)
		icon.mouse_filter = Control.MOUSE_FILTER_PASS
		stack.add_child(icon)
	var text: Label = Label.new()
	text.name = &"Value"
	text.text = tr(RankText.CELL_LOCKED) % lock if lock > 0 else str(wins)
	text.theme_type_variation = &"MenuNumber" if lock > 0 else &"MenuRankLabel"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(text)
	return cell


func _add_stat(name_key: StringName, value: String) -> void:
	var line: HBoxContainer = _row()
	line.name = StringName("Stat_" + String(name_key))
	var name_label: Label = Label.new()
	name_label.text = tr(name_key)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(name_label)
	var value_label: Label = Label.new()
	value_label.name = &"Value"
	value_label.text = value
	value_label.theme_type_variation = &"MenuTag"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_child(value_label)


func _row() -> HBoxContainer:
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	add_child(line)
	return line


func _eyebrow(key: StringName) -> Label:
	var label: Label = Label.new()
	label.text = tr(key)
	label.theme_type_variation = &"MenuEyebrow"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


func _add_eyebrow(key: StringName) -> void:
	var label: Label = _eyebrow(key)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
