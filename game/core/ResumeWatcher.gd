class_name ResumeWatcher
extends Node
## Keeps the resume file (`ResumeStore`) in step with the match that `MenuFlow` runs, through the
## seams MenuFlow already has (plan P514; MenuFlow is not edited):
## - on `NOTIFICATION_APPLICATION_PAUSED` it takes `current_runner()` and `current_setup()` and
##   writes the file (ADR 0042 section 5); with no match running it does nothing, so the file of a
##   killed match stays for Continue;
## - `match_loading` (a new match or a restart) deletes the file;
## - the runner's `match_ended` deletes it;
## - when the tracked runner is no longer MenuFlow's (Exit to menu, a restart, a new match) the
##   file is deleted; the app quitting keeps it, as MenuFlow keeps its runner then.
## A failed restore deletes through `ResumeStore.delete()` itself. `ResumeWatcher.install` adds one
## to the tree. No timing and no randomness: it reads no clock.

## The node with MenuFlow's seams: `current_runner()`, `current_setup()` and `match_loading`.
var flow: Node = null

var _tracked: MatchRunner = null


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
	flow.match_loading.connect(_on_match_loading)


func _process(_delta: float) -> void:
	var current: MatchRunner = flow.current_runner() if flow != null else null
	if current == _tracked:
		return
	if _tracked != null:
		# The match it followed was left, replaced or restarted.
		if is_instance_valid(_tracked) and _tracked.match_ended.is_connected(_on_match_ended):
			_tracked.match_ended.disconnect(_on_match_ended)
		ResumeStore.delete()
	_tracked = current
	if current != null:
		current.match_ended.connect(_on_match_ended)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:
		write_now()


## Writes the file for the running match. The pause calls it; tests too.
func write_now() -> Error:
	if flow == null:
		return ERR_UNCONFIGURED
	var runner: MatchRunner = flow.current_runner()
	var setup: MatchSetup = flow.current_setup()
	if runner == null or setup == null:
		return ERR_UNCONFIGURED
	return ResumeStore.write_from(runner, setup)


func _on_match_loading(_setup: MatchSetup) -> void:
	ResumeStore.delete()


func _on_match_ended(_winner: int) -> void:
	ResumeStore.delete()
