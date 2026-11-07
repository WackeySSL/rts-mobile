class_name ResultScreen
extends ModalFrame
## The result screen (ADR 0019 section 6, plan P90): on `match_ended` it covers the HUD with the
## outcome as an emblem and a word, the match time and each player's units built and lost,
## buildings lost and credits harvested, from the published snapshot. "Play again" opens a new main
## scene for the same scenario, opponents and level, "Back" the dev menu until Phase 5's start page.
## Sideways the banner and the table stand side by side, upright one above the other. No ad.

const EMBLEM_ART: String = "res://assets/art/svg/icons/glyph_%s.svg"
const EMBLEM_DP: float = 64.0
const STAT_NAMES: Array[String] = [
	"Units built", "Units lost", "Buildings lost", "Credits harvested"
]

@export var runner: MatchRunner

var _body: BoxContainer
var _emblem: TextureRect
var _title: Label
var _time: Label
var _grid: GridContainer
var _again: Button


func _ready() -> void:
	_body = BoxContainer.new()  # Before `super()`, whose `_apply_dp` sizes them.
	_emblem = TextureRect.new()
	_grid = GridContainer.new()
	super()
	column.add_child(_body)
	var banner: VBoxContainer = VBoxContainer.new()
	_body.add_child(banner)
	var head: HBoxContainer = HBoxContainer.new()
	banner.add_child(head)
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(_emblem)
	_title = add_label(head, "", &"CapsBigTitle")
	_time = add_label(banner, "", &"NumberLabel")
	_body.add_child(_grid)
	var row: HBoxContainer = HBoxContainer.new()
	column.add_child(row)
	_again = add_button(row, "PLAY AGAIN", _play_again)
	_again.name = &"PlayAgainButton"
	add_button(row, "BACK", _back).name = &"BackButton"
	runner.match_ended.connect(_on_match_ended)
	_apply_dp()


func _apply_dp() -> void:
	super()
	var gap: int = roundi(UiScale.dp(GAP_DP))
	_body.vertical = HudLayout.is_portrait()
	_body.add_theme_constant_override("separation", gap * 2)
	_grid.add_theme_constant_override("h_separation", gap)
	_emblem.custom_minimum_size = UiScale.dp_vec(EMBLEM_DP, EMBLEM_DP)


@warning_ignore("integer_division")
func _on_match_ended(winner: int) -> void:
	var snap: MatchSnapshot = runner.snapshot
	var local: int = runner.scenario.local_player
	var result: String = "draw" if winner == 0 else ("victory" if winner == local else "defeat")
	_emblem.texture = load(EMBLEM_ART % result) as Texture2D
	_emblem.modulate = get_theme_color(StringName(result), &"ResultScreen")
	_title.text = result.to_upper()
	var seconds: int = snap.match_end_tick / Sim.TICK_RATE
	_time.text = "Match time %d:%02d" % [seconds / 60, seconds % 60]
	for cell: Node in _grid.get_children():
		_grid.remove_child(cell)
		cell.free()
	var counts: Array[PackedInt32Array] = [
		snap.stat_built, snap.stat_lost_units, snap.stat_lost_buildings, snap.stat_harvested
	]
	var players: int = snap.stat_built.size() - 1
	_grid.columns = players + 1
	add_label(_grid, "", &"Label")
	for player: int in range(1, players + 1):
		var who: String = (
			"You" if player == local else ("Enemy" if players == 2 else "P%d" % player)
		)
		add_label(_grid, who, &"Label")
	for line: int in STAT_NAMES.size():
		add_label(_grid, STAT_NAMES[line], &"Label")
		for player: int in range(1, players + 1):
			var number: Label = add_label(_grid, str(counts[line][player]), &"NumberLabel")
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_apply_dp()
	show_over(_again)


func _play_again() -> void:
	DevRoutes.open_main_with(
		get_tree(),
		runner.scenario.resource_path,
		runner.opponents,
		runner.opponent_levels,
		runner.first_opponent
	)


func _back() -> void:
	DevRoutes.open(get_tree(), DevRoutes.DEV_MENU_SCENE)
