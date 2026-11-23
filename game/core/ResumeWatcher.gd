class_name ResumeWatcher
extends Node
## Keeps the resume file (`ResumeStore`) in step with the match that `MenuFlow` runs, through the
## seams MenuFlow already has (plan P514; MenuFlow is not edited):
## - on `NOTIFICATION_APPLICATION_PAUSED` it takes `current_runner()` and `current_setup()` and
##   writes the file (ADR 0042 section 5); with no match running it does nothing, so the file of a
##   killed match stays for Continue;
## - `match_start_finished(OK)` (a new match or a restart is in) deletes the file; `match_loading`
##   does not, since it now comes before the ads settle (P450) and a start that fails or is killed
##   there must keep the file of the earlier match;
## - the runner's `match_ended` deletes it;
## - when the tracked runner is no longer MenuFlow's (Exit to menu, a restart, a new match) the
##   file is deleted; the app quitting keeps it, as MenuFlow keeps its runner then.
## A failed restore deletes through `ResumeStore.delete()` itself. `ResumeWatcher.install` adds one
## to the tree. No timing and no randomness: it reads no clock.

## True while a `Restorer` plays a saved match (plan P515): the file it restores from stays (a
## `match_loading` does not delete it) and a pause writes nothing (the runner MenuFlow holds is not
## the restored one yet, and a partial log must never replace the full file). The Restorer sets and
## clears it.
static var restoring: bool = false

## The node with MenuFlow's seams: `current_runner()`, `current_setup()` and `match_start_finished`.
var flow: Node = null

var _tracked: MatchRunner = null
var _tracked_id: int = 0  ## The instance id: a freed runner no longer compares equal to itself.


## Adds a watcher for `MenuFlow` to `tree`'s root; whoever owns the app start calls this once.
static func install(tree: SceneTree, menu_flow: Node) -> ResumeWatcher:
	var watcher: ResumeWatcher = ResumeWatcher.new()
	watcher.name = "ResumeWatcher"
	watcher.bind(menu_flow)
	tree.root.add_child.call_deferred(watcher)
	return watcher


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # The pause menu pauses the tree.


## Follows `menu_flow`.
func bind(menu_flow: Node) -> void:
	flow = menu_flow
	if flow.has_signal(&"match_start_finished"):
		flow.connect(&"match_start_finished", _on_match_start_finished)


func _process(_delta: float) -> void:
	# A Variant: a runner freed by the scene change must not trip a typed assignment.
	var found: Variant = flow.current_runner() if flow != null else null
	var current: MatchRunner = found if is_instance_valid(found) else null
	var current_id: int = current.get_instance_id() if current != null else 0
	if current_id == _tracked_id:
		return
	if _tracked_id != 0:
		# The match it followed was left (its runner may be freed already), replaced or restarted.
		if is_instance_valid(_tracked) and _tracked.match_ended.is_connected(_on_match_ended):
			_tracked.match_ended.disconnect(_on_match_ended)
		ResumeStore.delete()
	_tracked = current
	_tracked_id = current_id
	if current != null:
		current.match_ended.connect(_on_match_ended)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		write_now()


## Writes the file for the running match. The pause calls it; tests too.
func write_now() -> Error:
	if restoring:
		return ERR_BUSY
	if flow == null:
		return ERR_UNCONFIGURED
	var runner: MatchRunner = flow.current_runner()
	var setup: MatchSetup = flow.current_setup()
	if runner == null or setup == null:
		return ERR_UNCONFIGURED
	return ResumeStore.write_from(runner, setup)


func _on_match_start_finished(error: Error) -> void:
	if error == OK and not restoring:
		ResumeStore.delete()


func _on_match_ended(_winner: int) -> void:
	ResumeStore.delete()
