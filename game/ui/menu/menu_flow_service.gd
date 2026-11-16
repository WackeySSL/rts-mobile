extends Node
## The one owner of scene changes between the menu and a match (ADR 0043 section 6). No class_name:
## this is an autoload (tests/project/test_autoloads.gd), listed last, after AdService.
##
## `start_match(setup)` seeds the match, takes the Phase 6 start-credits bonus (a skirmish only),
## emits `match_loading(setup)` and changes to a new main scene. When the runner reports the end,
## the summary is built and `Progression.award_match` runs once; `leave_match()` (the result
## screen's Back) then counts the match for the ad caps and awaits the post-match interstitial
## before the menu. `return_to_menu()` (Exit to menu, a failed restore) goes straight to the menu:
## no XP, no ad bookkeeping. A tutorial lesson (a setup with a lesson id) touches none of
## `take_start_credits_bonus`, `note_match_completed` and `maybe_show_interstitial`, so lessons
## never count toward Phase 6's new-player ad grace or its caps.
## The seams of other rows, which never edit this file: `current_runner()`, `current_setup()`,
## `match_loading`, `mark_surrendered()`, `last_award()`; P515 fills `continue_match()`.
## No game rule and no number lives here, and no Command is sent.

## Emitted after the bonus and the seed are written and before the main scene is built, so a
## loading card can show for one frame.
signal match_loading(setup: MatchSetup)
## Emitted once per match when its end has been scored; `award` is null for a lesson that paid
## nothing or a save that could not take the write.
signal match_scored(summary: MatchSummary, award: XpAward)

const MAIN_SCENE: String = "res://scenes/main.tscn"
const MENU_SCENE: String = "res://scenes/menu/menu.tscn"
const PLACEMENT_POST_MATCH: StringName = &"post_match"
const SEED_BYTES: int = 4
const DEFAULT_LEVEL: StringName = &"normal"

## The ad facade; tests swap in a fake with the same methods.
var ads: Node = null
## Where the seed of a skirmish comes from (outside the sim); tests replace it.
var seed_source: Callable = _random_seed
## What a scene change does; tests replace them so no scene is swapped. Called with the main scene
## node and with no argument for the menu.
var switch_to_main: Callable = _switch_to_main
var switch_to_menu: Callable = _switch_to_menu

var _main: Node = null
var _runner: MatchRunner = null
var _setup: MatchSetup = null
var _surrendered: bool = false
var _summary: MatchSummary = null
var _award: XpAward = null
var _scored: bool = false
var _leaving: bool = false


func _ready() -> void:
	ads = AdService


## The running match's runner, or null outside a match.
func current_runner() -> MatchRunner:
	return _runner if is_instance_valid(_runner) else null


## The setup of the running match (the bonus and seed written), or null outside a match.
func current_setup() -> MatchSetup:
	return _setup


## The summary and the award of the match that has ended (null before its end).
func last_summary() -> MatchSummary:
	return _summary


func last_award() -> XpAward:
	return _award


## The pause menu calls this when the player's own Surrender command is sent: the sim cannot tell
## a surrender from a defeat (MatchSummary).
func mark_surrendered() -> void:
	_surrendered = true


## Starts a match from `setup`. A skirmish gets a fresh seed and the pending start-credits bonus;
## a lesson keeps its own seed and takes no bonus (the grant stays for the next skirmish). Nothing
## changes and the error comes back (the caller reports it) when the setup is refused (see
## `MatchSetup.apply`); the bonus is taken only after the setup passed.
func start_match(setup: MatchSetup) -> Error:
	var refused: Error = _check(setup)
	if refused != OK:
		return refused
	if setup.lesson_id == &"":
		setup.match_seed = int(seed_source.call()) & DetRandom.SEED_MASK
		setup.bonus_starting_credits = int(ads.take_start_credits_bonus())
	return _begin(setup)


## Plays `_setup` again: the same setup, a fresh seed for a skirmish. The bonus is not taken again
## and not carried over, so a restart is not a free second bonus.
func restart() -> Error:
	if _setup == null:
		return ERR_UNCONFIGURED
	var again: MatchSetup = MatchSetup.from_dict(_setup.to_dict())
	if again == null:
		return ERR_INVALID_DATA
	if again.lesson_id == &"":
		again.match_seed = int(seed_source.call()) & DetRandom.SEED_MASK
	again.bonus_starting_credits = 0
	return _begin(again)


## The restore of ADR 0042 section 6; P515 fills it. Until then there is nothing to continue.
func continue_match() -> Error:
	return ERR_UNAVAILABLE


## Leaves a finished match for the menu (the result screen's Back). An ended skirmish counts for
## the ad caps and awaits the post-match interstitial first; a lesson and a match with no end go
## straight. Always `await` it.
func leave_match() -> void:
	if _leaving:
		return
	_leaving = true
	var lesson: bool = _setup != null and _setup.lesson_id != &""
	if _scored and not lesson:
		ads.note_match_completed(_summary.ticks / Sim.TICK_RATE)
		await ads.maybe_show_interstitial(PLACEMENT_POST_MATCH)
	_to_menu()


## Exit to menu from the pause menu or a failed restore: no XP, no ad bookkeeping.
func return_to_menu() -> void:
	if _leaving:
		return
	_leaving = true
	_to_menu()


## A probe runner checks the setup before anything is taken or built, so a refused setup costs
## nothing.
func _check(setup: MatchSetup) -> Error:
	var probe: MatchRunner = MatchRunner.new()
	var error: Error = setup.apply(probe)
	probe.free()
	return error


func _begin(setup: MatchSetup) -> Error:
	var refused: Error = _check(setup)
	if refused != OK:
		return refused
	match_loading.emit(setup)
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = main.get_node("MatchRunner")
	setup.apply(runner)
	_forget_match()
	_main = main
	_runner = runner
	_setup = setup
	runner.match_ended.connect(_on_match_ended)
	switch_to_main.call(main)
	return OK


func _on_match_ended(winner: int) -> void:
	if _scored or _setup == null or _runner == null:
		return
	_scored = true
	_summary = MatchSummary.from_snapshot(
		_runner.snapshot, _level_id(), _setup.map_id, _local_seat(), _surrendered, _setup.lesson_id
	)
	_award = Progression.award_match(_summary)
	match_scored.emit(_summary, _award)
	# `winner` is already in the snapshot; the parameter only matches the signal.
	assert(winner == _runner.snapshot.winner)


func _level_id() -> StringName:
	for level: AiDifficultyDef in _setup.opponent_levels:
		if level != null:
			return level.id
	return DEFAULT_LEVEL


func _local_seat() -> int:
	if _setup.local_seat != 0:
		return _setup.local_seat
	return _setup.scenario().local_player


func _to_menu() -> void:
	_forget_match()
	switch_to_menu.call()


func _forget_match() -> void:
	if is_instance_valid(_runner) and _runner.match_ended.is_connected(_on_match_ended):
		_runner.match_ended.disconnect(_on_match_ended)
	_main = null
	_runner = null
	_setup = null
	_surrendered = false
	_summary = null
	_award = null
	_scored = false
	_leaving = false


func _switch_to_main(main: Node) -> void:
	get_tree().change_scene_to_node(main)


func _switch_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _random_seed() -> int:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(SEED_BYTES)
	return bytes.decode_u32(0)
