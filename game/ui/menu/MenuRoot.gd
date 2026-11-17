class_name MenuRoot
extends Node
## Puts the main menu on the stack of `main_menu.tscn` (menu.tscn itself stays an empty stack, which
## the stack tests rely on). It registers the routes that exist (`MenuRoutesDefaults`) before the
## menu is pushed, so each button is live at the first show, then opens the screen `MenuFlow` was
## asked for (a lesson's end returns to the tutorial screen), if its route is registered.
## TODO(P533): the switch row makes this scene the app's start.

@export var stack_path: NodePath = ^"../MenuStack"

## Tests replace these before the node enters the tree.
var routes: MenuRoutes = MenuRoutes.shared
var register_defaults: bool = true
var take_pending: Callable = func() -> StringName: return MenuFlow.take_pending_screen()


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
	if pending != &"" and routes.has(pending):
		stack.push(routes.make(pending))
