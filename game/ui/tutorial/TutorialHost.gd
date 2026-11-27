class_name TutorialHost
extends Node
## Runs a lesson inside its match (plan row P544, ADR 0044 section 2): `attach(main)` is called by
## the main scene's `_ready`; when `MenuFlow` built this match from a lesson setup it adds a
## `TutorialDirector` and a `CoachMark`, wires them to the scene's nodes found by type, and starts
## the lesson. Any other match (a skirmish, a dev scene) gets nothing. Presentation only: it sends
## no Command.
## Where the lesson goes next: finishing the last beat and Skip both return to the Tutorial screen
## (`MenuFlow.return_to_menu`: no XP, no ad bookkeeping; the director saved the done mark).

var director: TutorialDirector
var mark: CoachMark
var flow: Node = null

var _lesson_id: StringName = &""


## Adds a host under `main` when its match is a lesson; returns it, or null when it is not one.
static func attach(main: Node, flow_node: Node = null) -> TutorialHost:
	var service: Node = flow_node if flow_node != null else MenuFlow
	var setup: MatchSetup = service.call(&"current_setup") as MatchSetup
	var runner: MatchRunner = main.get_node_or_null("MatchRunner") as MatchRunner
	if setup == null or setup.lesson_id == &"" or runner == null:
		return null
	if service.call(&"current_runner") != runner:
		return null  # Not the match the flow built (a dev route).
	var host: TutorialHost = TutorialHost.new()
	host.name = &"TutorialHost"
	host.flow = service
	main.add_child(host)
	host.begin(setup.lesson_id)
	return host


## Builds the director and the coach mark from the scene the host stands in and starts `id`.
func begin(id: StringName) -> void:
	var main: Node = get_parent()
	var def: TutorialLessonDef = TutorialStart.lesson(id)
	if def == null:
		push_warning("TutorialHost: no lesson file for %s" % id)
		return
	_lesson_id = id
	director = TutorialDirector.new()
	director.name = &"TutorialDirector"
	director.runner = main.get_node("MatchRunner") as MatchRunner
	director.camera = _find(main, "RtsCamera") as RtsCamera
	director.placement = _find(main, "PlacementController") as PlacementController
	director.strike_aim = _find(main, "StrikeAim") as StrikeAim
	director.sidebar = _find(main, "BuildSidebar") as BuildSidebar
	var controller: PlayerController = _find(main, "PlayerController") as PlayerController
	var feed: HudStateFeed = _find(main, "HudStateFeed") as HudStateFeed
	director.selection = controller.selection if controller != null else null
	director.hud = feed.state if feed != null else null
	add_child(director)
	var layer: Node = feed.get_parent() if feed != null else main
	mark = CoachMark.new()
	mark.name = &"CoachMark"
	mark.director = director
	mark.camera = director.camera
	mark.runner = director.runner
	mark.ground_layer = _find(main, "UnitLayer") as UnitLayer
	mark.air_layer = _find(main, "AirLayer") as AirLayer
	mark.hud_root = layer
	layer.add_child(mark)
	director.lesson_done.connect(_leave)
	director.lesson_skipped.connect(_leave)
	director.start(def)


## The first node under `root` whose script class is `type_name`.
static func _find(root: Node, type_name: String) -> Node:
	var found: Array[Node] = root.find_children("*", type_name, true, false)
	return found[0] if not found.is_empty() else null


func _leave(id: StringName) -> void:
	TutorialStart.note_left(id)  # Only Skip reaches here for an unfinished lesson (done is saved).
	if flow != null and flow.has_method(&"return_to_menu"):
		flow.call_deferred(&"return_to_menu", TutorialStart.RETURN_SCREEN)
