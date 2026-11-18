extends Node
## The one owner of scene changes between the menu and a match (ADR 0043 section 6). No class_name:
## this is an autoload (tests/project/test_autoloads.gd), listed last, after AdService.
##
## `start_match(setup)` seeds the match, takes the Phase 6 start-credits bonus (a skirmish only),
## emits `match_loading(setup)`, waits one frame so the loading card is drawn, and changes to a new
## main scene. `start_match`, `restart`, `leave_match` and `continue_match` are coroutines: always
## `await` them. While one runs, the others return ERR_BUSY (leave_match and return_to_menu do
## nothing), so a new match is never torn down by a late menu change; every await re-checks the
## match serial before it acts.
## When the runner reports the end, the summary is built and `Progression.award_match` runs once;
## `leave_match()` (the result screen's Back) then counts the match for the ad caps
## (`note_match_completed`, once per match) and awaits the post-match interstitial before the menu.
## `return_to_menu()` (Exit to menu, a failed restore) goes straight to the menu: no XP, no ad
## bookkeeping. The next lesson starts through `start_match(next_setup)`.
## Restart (`restart()`, the result screen's Play again or the pause menu's Restart) plays the
## same setup again:
## - after an ENDED skirmish it is the end of that match: `note_match_completed` once, the
##   interstitial awaited (it is between matches), then the new match with bonus 0 (it was used);
## - MID-match (abandoned) it counts nothing and shows no interstitial, and the bonus carries over
##   unchanged: it was paid for with a rewarded ad and `take_start_credits_bonus` is not called
##   again, so it is not a second grant;
## - a lesson restart calls no ad method and keeps the lesson's seed;
## - a skirmish restart draws a fresh seed.
## A tutorial lesson (a setup with a lesson id) touches none of `take_start_credits_bonus`,
## `note_match_completed` and `maybe_show_interstitial`, so lessons never count toward Phase 6's
## new-player ad grace or its caps.
## The seams of other rows, which never edit this file: `current_runner()`, `current_setup()`,
## `match_loading`, `mark_surrendered()`, `last_award()`, `take_pending_screen()`; P515 fills
## `continue_match()`. No game rule and no number lives here, and no Command is sent.

## Emitted after the bonus and the seed are written and before the main scene is built; one frame
## is awaited after it, so a loading card is drawn.
signal match_loading(setup: MatchSetup)
## Emitted once per match when its end has been scored; `award` is null for a lesson that paid
## nothing or a save that could not take the write.
signal match_scored(summary: MatchSummary, award: XpAward)

const MAIN_SCENE: String = "res://scenes/main.tscn"
const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const PLACEMENT_POST_MATCH: StringName = &"post_match"
const SEED_BYTES: int = 4
const DEFAULT_LEVEL: StringName = &"normal"
const LIFE_SETTINGS: String = "res://data/life_settings.tres"

## The ad facade; tests swap in a fake with the same methods.
var ads: Node = null
## Where the seed of a skirmish comes from (outside the sim); tests replace it.
var seed_source: Callable = _random_seed
## What a scene change does; tests replace them so no scene is swapped. Called with the main scene
## node and with no argument for the menu.
## Both return an Error.
var switch_to_main: Callable = _switch_to_main
var switch_to_menu: Callable = _switch_to_menu
## Returns the Signal awaited after `match_loading`; tests drive their own.
var loading_frame: Callable = _next_frame

var _main: Node = null
var _runner: MatchRunner = null
var _setup: MatchSetup = null
var _surrendered: bool = false
var _summary: MatchSummary = null
var _award: XpAward = null
var _scored: bool = false
var _counted: bool = false  ## note_match_completed ran for the current match.
var _busy: bool = false  ## A start, restart or leave is in flight.
var _serial: int = 0  ## Bumped whenever a match is forgotten or begun.
var _pending_screen: StringName = &""


func _ready() -> void:
	ads = AdService
	MenuPrefs.apply_audio(AudioService)  # AudioService loads before SaveService (P526).
	apply_reduced()
	get_tree().node_added.connect(apply_reduced_to)


func _exit_tree() -> void:
	MenuRoutes.shared.clear()  # The static table must not outlive the screens' scripts at exit.


## Puts the saved Reduced effects switch on the shared `LifeSettings` the match views read (they
## all use this one cached resource). Runs at boot and before each match is built, so a change in
## Settings reaches the next match and never one that runs (P526b).
func apply_reduced() -> void:
	var life: LifeSettings = load(LIFE_SETTINGS) as LifeSettings
	if life != null:
		life.reduced = MenuPrefs.reduced_effects()


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


## The screen the last `leave_match(screen)` or `return_to_menu(screen)` asked the menu to open,
## returned once and then &"" (the start menu reads it; ADR 0043 section 6).
func take_pending_screen() -> StringName:
	var screen: StringName = _pending_screen
	_pending_screen = &""
	return screen


## Starts a match from `setup`. A skirmish gets a fresh seed and the pending start-credits bonus;
## a lesson keeps its own seed and takes no bonus (the grant stays for the next skirmish). Nothing
## changes and the error comes back (the caller reports it) when the setup is refused (see
## `MatchSetup.apply`; the bonus is taken only after the setup passed), or ERR_BUSY.
func start_match(setup: MatchSetup) -> Error:
	if _busy:
		return ERR_BUSY
	var refused: Error = _check(setup)
	if refused != OK:
		return refused
	_busy = true
	if setup.lesson_id == &"":
		setup.match_seed = int(seed_source.call()) & DetRandom.SEED_MASK
		setup.bonus_starting_credits = int(ads.take_start_credits_bonus())
	var error: Error = await _begin(setup)
	_busy = false
	return error


## Plays `_setup` again; the rules are in the header comment.
func restart() -> Error:
	if _busy:
		return ERR_BUSY
	if _setup == null:
		return ERR_UNCONFIGURED
	var again: MatchSetup = MatchSetup.from_dict(_setup.to_dict())
	if again == null:
		return ERR_INVALID_DATA
	var refused: Error = _check(again)
	if refused != OK:
		return refused
	_busy = true
	var serial: int = _serial
	if again.lesson_id == &"":
		again.match_seed = int(seed_source.call()) & DetRandom.SEED_MASK
		if _scored:
			await _count_end()
			again.bonus_starting_credits = 0
	if serial != _serial:
		_busy = false
		return ERR_BUSY
	var error: Error = await _begin(again)
	_busy = false
	return error


## The restore of ADR 0042 section 6; P515 fills it. Until then there is nothing to continue.
func continue_match() -> Error:
	if _busy:
		return ERR_BUSY
	return ERR_UNAVAILABLE


## Leaves a finished match for the menu (the result screen's Back), asking it to open `screen`
## (see `take_pending_screen`). An ended skirmish counts for the ad caps and awaits the post-match
## interstitial first; a lesson and a match with no end go straight. A second call while one runs
## does nothing. Always `await` it.
func leave_match(screen: StringName = &"") -> void:
	if _busy:
		return
	_busy = true
	_pending_screen = screen
	var serial: int = _serial
	var lesson: bool = _setup != null and _setup.lesson_id != &""
	if _scored and not lesson:
		await _count_end()
	if serial != _serial:
		_busy = false
		return
	_to_menu()


## Exit to menu from the pause menu or a failed restore, asking it to open `screen`: no XP, no ad
## bookkeeping.
func return_to_menu(screen: StringName = &"") -> void:
	if _busy:
		return
	_busy = true
	_pending_screen = screen
	_to_menu()


## Counts an ended skirmish once for the ad caps, then awaits the post-match interstitial.
func _count_end() -> void:
	if _counted:
		return
	_counted = true
	# Whole seconds of play: ticks over the tick rate, the remainder dropped on purpose.
	@warning_ignore("integer_division")
	var seconds: int = _summary.ticks / Sim.TICK_RATE
	ads.note_match_completed(seconds)
	await ads.maybe_show_interstitial(PLACEMENT_POST_MATCH)


## A probe runner checks the setup before anything is taken or built, so a refused setup costs
## nothing.
func _check(setup: MatchSetup) -> Error:
	var probe: MatchRunner = MatchRunner.new()
	var error: Error = setup.apply(probe)
	probe.free()
	return error


## The setup has passed `_check`. Emits `match_loading`, waits one frame, builds the scene.
func _begin(setup: MatchSetup) -> Error:
	var serial: int = _serial
	match_loading.emit(setup)
	await loading_frame.call()
	if serial != _serial:
		return ERR_BUSY
	apply_reduced()
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	var runner: MatchRunner = main.get_node("MatchRunner")
	var error: Error = setup.apply(runner)
	if error != OK:
		main.free()
		return error
	_forget_match()
	_main = main
	_runner = runner
	_setup = setup
	runner.match_ended.connect(_on_match_ended)
	error = switch_to_main.call(main) as Error
	if error != OK:
		_forget_match()
		main.free()
	return error


## Every `IntroPlayer` and `MenuStack` that enters the tree takes the saved switch before its
## `_ready` (a node that set `reduced` on itself stays on); any other node is left alone.
func apply_reduced_to(node: Node) -> void:
	if node is IntroPlayer:
		(node as IntroPlayer).reduced = (node as IntroPlayer).reduced or MenuPrefs.reduced_effects()
	elif node is MenuStack:
		(node as MenuStack).reduced = (node as MenuStack).reduced or MenuPrefs.reduced_effects()


func _on_match_ended(_winner: int) -> void:
	if _scored or _setup == null or _runner == null:
		return
	_scored = true
	_summary = MatchSummary.from_snapshot(
		_runner.snapshot, _level_id(), _setup.map_id, _local_seat(), _surrendered, _setup.lesson_id
	)
	_award = Progression.award_match(_summary)
	match_scored.emit(_summary, _award)


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
	var error: Error = switch_to_menu.call() as Error
	if error != OK:
		push_error("MenuFlow: cannot change to the menu (%s)" % error_string(error))


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
	_counted = false
	_busy = false
	_serial += 1


func _switch_to_main(main: Node) -> Error:
	return get_tree().change_scene_to_node(main)


func _switch_to_menu() -> Error:
	return get_tree().change_scene_to_file(MENU_SCENE)


func _next_frame() -> Signal:
	return get_tree().process_frame


func _random_seed() -> int:
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes(SEED_BYTES)
	return bytes.decode_u32(0)
