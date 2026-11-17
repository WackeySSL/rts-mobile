extends Node
## Puts the main menu on the stack of `main_menu.tscn` (menu.tscn itself stays an empty stack, which
## the stack tests rely on).

@export var stack_path: NodePath = ^"../MenuStack"


func _ready() -> void:
	var stack: MenuStack = get_node_or_null(stack_path) as MenuStack
	if stack == null:
		push_error("MenuRoot: no MenuStack at %s (from %s)" % [stack_path, get_path()])
		return
	stack.push(MainMenu.new())
