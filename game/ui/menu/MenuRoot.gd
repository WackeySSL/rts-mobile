class_name MenuRoot
extends Node
## Puts the main menu on the stack of `main_menu.tscn` (menu.tscn itself stays an empty stack, which
## the stack tests rely on). It registers the routes that exist (`MenuRoutesDefaults`) before the
## menu is pushed, so each button is live at the first show, then opens the screen `MenuFlow` was
## asked for (a lesson's end returns to the tutorial screen), if its route is registered; a route
## nobody registered, or one whose factory gives nothing, is dropped with a warning.
## On a first launch (`offer_first_launch`, set in `main_menu.tscn` only) the first lesson starts as
## soon as the boot intro has handed the menu over (`MenuStack.back_enabled`), once (P544). Only a
## menu the intro made (its stack waits for the hand-over) offers it: a menu loaded after a match
## or by a test never starts a lesson.

@export var stack_path: NodePath = ^"../MenuStack"
@export var offer_first_launch: bool = false

## Tests replace these before the node enters the tree.
var routes: MenuRoutes = MenuRoutes.shared
var register_defaults: bool = true
var take_pending: Callable = func() -> StringName: return MenuFlow.take_pending_screen()
var start_lesson: Callable = func(id: StringName) -> Error:
	return await TutorialStart.start(MenuFlow, id)


func _ready() -> void:
	var stack: MenuStack = get_node_or_null(stack_path) as MenuStack
	if stack == null:
		push_error("MenuRoot: no MenuStack at %s (from %s)" % [stack_path, get_path()])
		return
	if register_defaults:
		MenuRoutesDefaults.register(routes)
	var main: MainMenu = MainMenu.new()
	main.routes = routes
	stack.push(main)
	var pending: StringName = take_pending.call()
	if pending == &"":
		if offer_first_launch and not stack.back_enabled and TutorialStart.first_launch_due():
			TutorialStart.mark_offered()
			_start_first_lesson(stack)
		return
	var screen: MenuScreen = routes.make(pending)
	if screen == null:
		push_warning("MenuRoot: no screen for the pending route %s, dropped" % pending)
		return
	stack.push(screen)


func _start_first_lesson(stack: MenuStack) -> void:
	while not stack.back_enabled and is_inside_tree():  # The intro still owns the screen.
		await get_tree().process_frame
	if is_inside_tree():
		await start_lesson.call(TutorialStart.ORDER[0])
