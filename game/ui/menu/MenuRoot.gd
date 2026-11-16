extends Node
## Puts the main menu on the stack of `main_menu.tscn` (menu.tscn itself stays an empty stack, which
## the stack tests rely on). TODO(P533): the switch row makes this scene the app's start.

@export var stack_path: NodePath = ^"../MenuStack"


func _ready() -> void:
	(get_node(stack_path) as MenuStack).push(MainMenu.new())
