class_name RankTrophySection
extends VBoxContainer
## The Trophies part of the Rank screen (ADR 0054 section 8, P673d). `attach` fills the box that
## `RankScreen._add_section` made: its heading gets the earned count, and each trophy of the
## catalog is one row, a `TrophyBadge` and its name, hint and either EARNED or the progress
## ("7/10"). A trophy gives no reward. Rows are read-only (`MOUSE_FILTER_PASS`). The section calls
## `Progression.refresh_trophies()` each time it enters the tree, so a screen coming back refreshes.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const GAP_DP: float = 12.0

var _progression: ProgressionScript
var _heading: Label


## Puts the section into `box` (replacing its placeholder label) and builds the rows.
func attach(box: VBoxContainer, progression: ProgressionScript) -> void:
	_progression = progression
	for child: Node in box.get_children():
		box.remove_child(child)
		child.free()
	_heading = box.get_parent().get_child(box.get_index() - 1) as Label
	box.add_child(self)


## The progress of a trophy as (done, total), or (0, 0) when it has none to show: a COUNT trophy
## against its counter, a WIN_GRID trophy by the cells won. Lessons and one-match trophies read as
## their hint alone.
static func progress_of(def: TrophyDef, career: CareerStats) -> Vector2i:
	if def.kind == TrophyDef.Kind.COUNT:
		return Vector2i(mini(career.counter(def.counter, def.key), def.count), def.count)
	if def.kind != TrophyDef.Kind.WIN_GRID:
		return Vector2i.ZERO
	var maps: Array[StringName] = def.map_ids.duplicate()
	var levels: Array[StringName] = def.levels.duplicate()
	if maps.is_empty():
		maps.append(&"")  # An empty list means any, which `wins_on` reads from an empty id.
	if levels.is_empty():
		levels.append(&"")
	var won: int = 0
	for map_id: StringName in maps:
		for level: StringName in levels:
			won += 1 if career.wins_on(map_id, level) > 0 else 0
	return Vector2i(won, maps.size() * levels.size())


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _progression != null:
		_progression.refresh_trophies()
		_rebuild()


func _rebuild() -> void:
	RankText.register()
	for child: Node in get_children():
		remove_child(child)
		child.free()
	add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	mouse_filter = Control.MOUSE_FILTER_PASS
	_heading.text = tr(RankText.TROPHIES)  # The screen's own tr() ran before the table existed.
	var catalog: TrophyCatalog = _progression.trophy_catalog()
	if catalog == null:
		return
	var career: CareerStats = CareerStats.read(_progression.career(), 1, _ignore)
	var earned: int = _progression.earned_count()
	_heading.text = tr(RankText.TROPHIES_COUNT) % [earned, catalog.trophies.size()]
	for def: TrophyDef in catalog.trophies:
		add_child(_row(def, career))


func _ignore(_message: String) -> void:
	pass


func _row(def: TrophyDef, career: CareerStats) -> HBoxContainer:
	var lit: bool = _progression.is_earned(def.id)
	var row: HBoxContainer = HBoxContainer.new()
	row.name = String(def.id)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	var badge: TrophyBadge = TrophyBadge.new()
	badge.glyph = def.glyph
	badge.pips = def.pips
	badge.lit = lit
	row.add_child(badge)
	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(texts)
	texts.add_child(_label(&"Name", tr(def.name), &"" if lit else &"MenuNumber"))
	texts.add_child(_label(&"Hint", tr(def.hint), &"MenuFooterHint"))
	if lit:
		texts.add_child(_label(&"Status", tr(RankText.EARNED), &"MenuTag"))
		return row
	var progress: Vector2i = progress_of(def, career)
	if progress.y > 1:  # A target of 1 adds nothing: the hint already says it.
		var words: String = tr(RankText.PROGRESS) % [progress.x, progress.y]
		texts.add_child(_label(&"Status", words, &"MenuFooterHint"))
	return row


func _label(label_name: StringName, text: String, look: StringName) -> Label:
	var label: Label = Label.new()
	label.name = label_name
	label.text = text
	label.theme_type_variation = look
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
