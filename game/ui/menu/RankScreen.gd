class_name RankScreen
extends MenuScreen
## The commander's Rank screen (ADR 0052 section 3, plan P664), opened by the main menu's RANK row:
## the title COMMANDER, the rank insignia with "RANK n NAME", the XP bar with "x / y XP", then the
## section NEXT UNLOCK (the next map or computer opponent and the rank that opens it, from
## `Progression.next_unlock()`, or "Everything is open."), and BACK at the foot (the web has no back
## event). Later rows add sections below the rank block with `_add_section`. It hosts no banner.
## Open it with `stack.push(RankScreen.new())`; `progression` and `catalog` are for tests.

const ProgressionScript: GDScript = preload("res://game/meta/progression_service.gd")
const XP_BAR_DP: float = 12.0

## Tests inject these before the screen is pushed; null means the autoload and the data file.
var progression: ProgressionScript = null
var catalog: MapCatalog = null

var _insignia: RankInsignia
var _rank_label: Label
var _xp_label: Label
var _xp_bar: ProgressBar
var _unlock_label: Label
var _back: Button
var _progression: ProgressionScript


func _ready() -> void:
	super()
	MainMenuText.register()
	MapSelectText.register()
	_progression = progression if progression != null else (Progression as ProgressionScript)
	_heading(MainMenuText.CARD, &"CapsTitle")
	_build_rank_block()
	_unlock_label = _add_section(MainMenuText.NEXT).get_child(0) as Label
	_back = add_button(tr(MainMenuText.BACK), _go_back)
	_back.set_meta(&"ui_cue", &"ui_back")
	_progression.xp_changed.connect(_refresh)
	_refresh()


## A section under the rank block: its heading (a `MenuEyebrow`) and a box to fill, which holds one
## label to start with. It lands above BACK, which stays last.
func _add_section(heading_key: StringName) -> VBoxContainer:
	_heading(heading_key, &"MenuEyebrow")
	var box: VBoxContainer = VBoxContainer.new()
	column.add_child(box)
	var text: Label = Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	if _back != null:
		column.move_child(_back, -1)
	return box


func _heading(text_key: StringName, variation: StringName) -> void:
	var label: Label = Label.new()
	label.text = tr(text_key)
	label.theme_type_variation = variation
	column.add_child(label)


func _build_rank_block() -> void:
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(UiScale.dp(GAP_DP)))
	column.add_child(head)
	_insignia = RankInsignia.new()
	head.add_child(_insignia)
	_rank_label = Label.new()
	_rank_label.theme_type_variation = &"MenuRankLabel"
	_rank_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rank_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_rank_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.theme_type_variation = &"MenuXpBar"
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size.y = UiScale.dp(XP_BAR_DP)
	column.add_child(_xp_bar)
	_xp_label = Label.new()
	column.add_child(_xp_label)


func _refresh() -> void:
	var rank: int = _progression.rank()
	var total: int = _progression.xp()
	var floor_xp: int = _progression.rank_floor_xp()
	var next_xp: int = _progression.next_rank_xp()
	_insignia.rank = rank
	_insignia.max_rank = _progression.max_rank()
	_rank_label.text = tr(MainMenuText.RANK) % [rank, _progression.title(rank).to_upper()]
	_xp_bar.min_value = floor_xp
	_xp_bar.max_value = maxi(next_xp, floor_xp + 1)
	_xp_bar.value = total
	_xp_label.text = (
		tr(MainMenuText.XP_TOP) % total
		if next_xp <= floor_xp
		else tr(MainMenuText.XP) % [total, next_xp]
	)
	_unlock_label.text = _unlock_text()


## The next unlock in words: the map's name or the computer's level, and the rank that opens it.
func _unlock_text() -> String:
	var next: Dictionary = _progression.next_unlock()
	if next.is_empty():
		return tr(MainMenuText.UNLOCK_DONE)
	var id: StringName = next[&"id"] as StringName
	var at: int = int(next[&"rank"])
	if next[&"kind"] == &"map":
		var maps: MapCatalog = catalog if catalog != null else load(MapCatalog.DEFAULT_PATH)
		var title: String = maps.title(id)
		return tr(MainMenuText.UNLOCK_MAP) % [title if title != "" else str(id), at]
	var word: StringName = MapSelect.LEVEL_TEXT.get(id, &"") as StringName
	var level: String = tr(word).capitalize() if word != &"" else str(id)
	return tr(MainMenuText.UNLOCK_OPPONENT) % [level, at]


func _go_back() -> void:
	var stack: MenuStack = get_parent() as MenuStack
	if stack != null:
		stack.back()  # Like the Android Back button.
